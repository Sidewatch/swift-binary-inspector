#!/usr/bin/env python3 -I
#
#  validate_macho.py
#  BinaryInspector
#
#  Runs MachOParser (through the macho-dump tool) over every Mach-O file in the system and
#  application locations below, and compares what it reads with lipo, otool and nm.
#
#  Created by David Sherlock on 10/22/26.
#  Copyright © 2026 ArrayPress Limited. MIT licence.
#
#  Usage: scripts/validate_macho.py [--jobs N] [--limit N] [--report FILE] [PATH ...]
#
#  With no PATH arguments it scans the default locations. It builds macho-dump in release mode
#  first. Only macOS with the developer tools installed can run it; `swift test` never does.
#  Exit status 0 when every comparison matched (or every remaining difference is one listed in
#  KNOWN_TOOL_DIFFERENCES), 1 otherwise.

import argparse
import collections
import concurrent.futures
import glob
import json
import os
import re
import struct
import subprocess
import sys
import time

PACKAGE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DUMP = os.path.join(PACKAGE, ".build", "release", "macho-dump")

THIN_MAGICS = {b"\xfe\xed\xfa\xce", b"\xfe\xed\xfa\xcf", b"\xce\xfa\xed\xfe", b"\xcf\xfa\xed\xfe"}

# Differences that are the tools' output, not the parser. They are compared in the tools' own
# terms, counted, and reported separately with these explanations.
KNOWN_TOOL_DIFFERENCES = {
    "nm prints an unnamed stab as a plain row": (
        "llvm-nm has no name for some stab types (N_AST 0x32, the Swift module path) and prints "
        "them as ordinary symbols, with the letter their low type bits give ('a'). Compared as such."
    ),
}

# Notes on how the tools are driven, printed with the report.
TOOL_NOTES = [
    "nm runs with --no-dyldinfo: by default llvm-nm adds export-trie symbols that are not in "
    "LC_SYMTAB, so its count would exceed nsyms.",
    "otool runs through a symlink with a plain name: the otool wrapper re-splits a path that "
    "contains parentheses and otool-classic then cannot open it.",
]


# MARK: - Collecting files


def is_macho(path):
    """True when the file starts with a thin Mach-O magic or a universal header (Java excluded)."""
    try:
        with open(path, "rb") as handle:
            head = handle.read(8)
    except OSError:
        return False
    if head[:4] in THIN_MAGICS:
        return True
    if head[:4] == b"\xca\xfe\xba\xbe" and len(head) == 8:
        return struct.unpack(">I", head[4:])[0] <= 30
    return head[:4] == b"\xca\xfe\xba\xbf"


def default_paths():
    """Every regular file in the locations the brief names, deduplicated by real path."""
    candidates = []
    for directory in ["/usr/bin", "/usr/sbin", "/bin", "/sbin", "/usr/libexec"]:
        candidates += glob.glob(directory + "/*")
    candidates += glob.glob("/Applications/*/Contents/MacOS/*")
    for root in glob.glob("/Applications/*/Contents/Frameworks"):
        for directory, _, names in os.walk(root):
            candidates += [os.path.join(directory, name) for name in names]
    candidates += glob.glob("/Library/Audio/Plug-Ins/VST3/*.vst3/Contents/MacOS/*")
    candidates += glob.glob("/Library/Audio/Plug-Ins/Components/*.component/Contents/MacOS/*")
    candidates += glob.glob("/System/Applications/*/Contents/MacOS/*")
    seen, paths = set(), []
    for path in candidates:
        if os.path.islink(path) or not os.path.isfile(path):
            continue
        real = os.path.realpath(path)
        if real in seen or not os.access(real, os.R_OK) or not is_macho(real):
            continue
        seen.add(real)
        paths.append(real)
    return sorted(paths)


# MARK: - Running the tools


def run(arguments):
    """stdout of a tool, or None when it fails."""
    try:
        result = subprocess.run(arguments, capture_output=True, timeout=600)
    except (OSError, subprocess.TimeoutExpired):
        return None
    if result.returncode != 0:
        return None
    return result.stdout.decode("utf-8", "surrogateescape")


def arch_arguments(universal, arch):
    return ["-arch", arch] if universal else []


SAFE_PATH = re.compile(r"^[A-Za-z0-9._/+-]+$")
LINKS = None


def plain_path(path):
    """`path` itself, or a symlink to it with a plain name when it holds characters (such as
    parentheses) that the otool wrapper mishandles."""
    global LINKS
    if SAFE_PATH.match(path):
        return path
    if LINKS is None:
        import tempfile

        LINKS = tempfile.mkdtemp(prefix="macho-validate-")
    link = os.path.join(LINKS, "f%08x" % (hash(path) & 0xFFFFFFFF))
    if not os.path.lexists(link):
        try:
            os.symlink(path, link)
        except FileExistsError:
            pass
    return link


# MARK: - Parsing otool -l


def parse_otool_l(text):
    """A list of load commands: {'cmd', 'fields', 'tools', 'sections'} in file order."""
    commands, current, section = [], None, None
    for line in text.splitlines():
        if line.startswith("Load command "):
            current = {"fields": {}, "tools": [], "sections": [], "lines": []}
            commands.append(current)
            section = None
            continue
        if current is None:
            continue
        stripped = line.strip()
        if stripped == "Section":
            section = {}
            current["sections"].append(section)
            continue
        current["lines"].append(stripped)
        key, _, value = stripped.partition(" ")
        value = value.strip()
        target = section if section is not None else current["fields"]
        if section is None and key in ("tool", "version") and "ntools" in current["fields"]:
            if key == "tool":
                current["tools"].append([value, None])
            elif current["tools"]:
                current["tools"][-1][1] = value
            continue
        if key == "current" or key == "compatibility":
            key, value = key + " version", value.replace("version", "", 1).strip()
        target.setdefault(key, value)
    for command in commands:
        command["cmd"] = command["fields"].get("cmd", "")
    return commands


def number(text):
    text = text.split()[0] if text else "0"
    return int(text, 16) if text.lower().startswith("0x") else int(text)


def our_version(text):
    """Our X.Y.Z in otool -l's spelling: X.Y when the patch is 0, 'n/a' for 0.0.0."""
    major, minor, patch = text.split(".")
    if major == "0" and minor == "0" and patch == "0":
        return "n/a"
    return f"{major}.{minor}" if patch == "0" else text


def name_value(command, key):
    """The value of an lc_str line ('name X (offset 24)')."""
    raw = command["fields"].get(key, "")
    return re.sub(r" \(offset \d+\)$", "", raw)


# MARK: - Parsing otool -L and nm -ap


def parse_otool_L(text):
    """(path, compat, current, marker) per line after the header."""
    rows = []
    for line in text.splitlines()[1:]:
        match = re.match(r"^\t(.*) \(compatibility version ([^,]*), current version ([^,)]*)(?:, (\w+))?\)$", line)
        if match:
            rows.append(match.groups())
    return rows


NM_STAB = re.compile(r"^([0-9a-f]+) - ([0-9a-f]{2}) ([0-9a-f]{4}) +(\S+) ?(.*)$")
NM_PLAIN = re.compile(r"^([0-9a-f]+| +) (\S) (.*)$")


def parse_nm(text):
    """(value or None, letter, name, stab-fields) per line."""
    rows = []
    for line in text.split("\n"):
        if not line:
            continue
        stab = NM_STAB.match(line)
        if stab:
            rows.append((int(stab.group(1), 16), "-", stab.group(5), (int(stab.group(2), 16), int(stab.group(3), 16))))
            continue
        plain = NM_PLAIN.match(line)
        if plain:
            value = plain.group(1).strip()
            rows.append((int(value, 16) if value else None, plain.group(2), plain.group(3), None))
        else:
            rows.append((None, "?", line, None))
    return rows


def nm_letter(symbol, sections):
    """The letter llvm-nm prints for one of our symbols (non-stab)."""
    value, kind, sect, _, name = symbol[0], symbol[1], symbol[2], symbol[3], symbol[4]
    n_type = kind & 0x0E
    external = kind & 0x01
    if n_type == 0x0:
        letter = "c" if external and int(value, 16) != 0 else "u"
    elif n_type == 0x2:
        letter = "a"
    elif n_type == 0xE:
        if 1 <= sect <= len(sections):
            segname, sectname = sections[sect - 1]
            if segname == "__TEXT" and sectname == "__text":
                letter = "t"
            elif segname == "__DATA" and sectname == "__data":
                letter = "d"
            elif segname == "__DATA" and sectname == "__bss":
                letter = "b"
            else:
                letter = "s"
        else:
            letter = "?"
    elif n_type == 0xA:
        letter = "i"
    elif n_type == 0xC:
        letter = "p"
    else:
        letter = "?"
    return letter.upper() if external else letter


# MARK: - Comparing one slice


class Findings:
    def __init__(self):
        self.mismatches = collections.defaultdict(list)
        self.checks = collections.Counter()
        self.known = collections.Counter()
        self.entries = 0

    def check(self, category, ok, where, detail):
        self.checks[category] += 1
        if not ok:
            self.mismatches[category].append(f"{where}: {detail}")


def compare_commands(image, otool, findings, where):
    ours = image["commands"]
    findings.check("command count", len(ours) == len(otool), where, f"ours {len(ours)} otool {len(otool)}")
    for mine, theirs in zip(ours, otool):
        name = theirs["cmd"]
        if not name.startswith("LC_"):
            match = re.search(r"0x([0-9a-fA-F]+)", name)
            name = mine["name"] if match and int(match.group(1), 16) == mine["cmd"] else name
        findings.check("command names", mine["name"] == name, where, f"#{len(ours)} ours {mine['name']} otool {theirs['cmd']}")
        findings.check("command sizes", mine["size"] == number(theirs["fields"].get("cmdsize", "0")), where, f"{mine['name']} size")


def compare_segments(image, otool, findings, where):
    theirs = [c for c in otool if c["cmd"] in ("LC_SEGMENT", "LC_SEGMENT_64")]
    ours = image["segments"]
    findings.check("segment count", len(ours) == len(theirs), where, f"ours {len(ours)} otool {len(theirs)}")
    for mine, other in zip(ours, theirs):
        f = other["fields"]
        expected = {
            "name": f.get("segname", ""), "vmaddr": number(f["vmaddr"]), "vmsize": number(f["vmsize"]),
            "fileoff": number(f["fileoff"]), "filesize": number(f["filesize"]), "maxprot": number(f["maxprot"]),
            "initprot": number(f["initprot"]),
        }
        got = {
            "name": mine["name"], "vmaddr": int(mine["vmaddr"], 16), "vmsize": int(mine["vmsize"], 16),
            "fileoff": int(mine["fileoff"], 16), "filesize": int(mine["filesize"], 16), "maxprot": mine["maxprot"] & 0xFFFFFFFF,
            "initprot": mine["initprot"] & 0xFFFFFFFF,
        }
        findings.check("segment fields", got == expected, where, f"{mine['name']} ours {got} otool {expected}")
        findings.check("section count", len(mine["sections"]) == len(other["sections"]), where, f"{mine['name']} sections")
        for ms, os_ in zip(mine["sections"], other["sections"]):
            exp = {
                "name": os_.get("sectname", ""), "segname": os_.get("segname", ""), "addr": number(os_["addr"]),
                "size": number(os_["size"]), "offset": number(os_["offset"]), "align": number(os_["align"].replace("2^", "")),
                "flags": number(os_["flags"]),
            }
            got_s = {
                "name": ms["name"], "segname": ms["segname"], "addr": int(ms["addr"], 16), "size": int(ms["size"], 16),
                "offset": int(ms["offset"], 16), "align": ms["align"], "flags": ms["flags"],
            }
            findings.check("section fields", got_s == exp, where, f"{ms['segname']},{ms['name']} ours {got_s} otool {exp}")


DYLIB_COMMANDS = {
    "LC_LOAD_DYLIB": "load", "LC_LOAD_WEAK_DYLIB": "weak", "LC_REEXPORT_DYLIB": "reexport",
    "LC_LAZY_LOAD_DYLIB": "lazy", "LC_LOAD_UPWARD_DYLIB": "upward",
}


def compare_dylibs(image, otool, otool_L, findings, where):
    theirs = [
        (DYLIB_COMMANDS[c["cmd"]], name_value(c, "name"), c["fields"].get("current version"), c["fields"].get("compatibility version"))
        for c in otool if c["cmd"] in DYLIB_COMMANDS
    ]
    ours = [(d["kind"], d["path"], d["current"], d["compat"]) for d in image["dylibs"]]
    findings.check("dylibs (otool -l)", ours == theirs, where, f"ours {ours} otool {theirs}")
    ids = [c for c in otool if c["cmd"] == "LC_ID_DYLIB"]
    expected_id = (name_value(ids[0], "name"), ids[0]["fields"].get("current version")) if ids else None
    got_id = (image["id"]["path"], image["id"]["current"]) if image["id"] else None
    findings.check("install name", got_id == expected_id, where, f"ours {got_id} otool {expected_id}")
    rpaths = [name_value(c, "path") for c in otool if c["cmd"] == "LC_RPATH"]
    findings.check("rpaths", image["rpaths"] == rpaths, where, f"ours {image['rpaths']} otool {rpaths}")
    if otool_L is not None:
        marker = {"load": None, "weak": "weak", "reexport": "reexport", "upward": "upward", "lazy": "lazy"}
        listed = [(d["path"], d["compat"], d["current"], marker[d["kind"]]) for d in image["dylibs"]]
        if image["id"] and image["filetype"] == 6:
            listed.insert(0, (image["id"]["path"], image["id"]["compat"], image["id"]["current"], None))
        findings.check("dylibs (otool -L)", listed == otool_L, where, f"ours {listed} otool {otool_L}")


def compare_identity(image, otool, findings, where):
    uuids = [c["fields"].get("uuid") for c in otool if c["cmd"] == "LC_UUID"]
    findings.check("uuid", image["uuid"] == (uuids[0] if uuids else None), where, f"ours {image['uuid']} otool {uuids}")
    builds = []
    for c in otool:
        f = c["fields"]
        if c["cmd"] == "LC_BUILD_VERSION":
            builds.append(("LC_BUILD_VERSION", f.get("platform"), f.get("minos"), f.get("sdk"), [tuple(t) for t in c["tools"]]))
        elif c["cmd"].startswith("LC_VERSION_MIN_"):
            builds.append((c["cmd"], None, f.get("version"), f.get("sdk"), []))
    names = {50: "LC_BUILD_VERSION", 0x24: "LC_VERSION_MIN_MACOSX", 0x25: "LC_VERSION_MIN_IPHONEOS", 0x2F: "LC_VERSION_MIN_TVOS", 0x30: "LC_VERSION_MIN_WATCHOS"}
    ours = []
    for b in image["builds"]:
        command = names[b["cmd"]]
        platform = str(b["platform"]) if command == "LC_BUILD_VERSION" else None
        tools = [(str(t[0]), our_version(t[1])) for t in b["tools"]]
        ours.append((command, platform, our_version(b["minos"]), our_version(b["sdk"]), tools))
    findings.check("build versions", ours == builds, where, f"ours {ours} otool {builds}")


def compare_linkedit(image, otool, findings, where):
    def first(name):
        found = [c["fields"] for c in otool if c["cmd"] == name]
        return found[0] if found else None

    sig = first("LC_CODE_SIGNATURE")
    expected = (number(sig["dataoff"]), number(sig["datasize"])) if sig else None
    got = (int(image["codesig"]["dataoff"], 16), image["codesig"]["datasize"]) if "codesig" in image else None
    findings.check("code signature", got == expected, where, f"ours {got} otool {expected}")
    if sig:
        inside = number(sig["dataoff"]) + number(sig["datasize"]) <= image["slice_end"] - image["slice_start"]
        findings.check("signed flag", image["signed"] == inside, where, f"ours {image['signed']} expected {inside}")
    main = first("LC_MAIN")
    expected = (number(main["entryoff"]), number(main["stacksize"])) if main else None
    got = (int(image["main"]["entryoff"], 16), int(image["main"]["stacksize"], 16)) if "main" in image else None
    findings.check("entry point", got == expected, where, f"ours {got} otool {expected}")
    enc = first("LC_ENCRYPTION_INFO") or first("LC_ENCRYPTION_INFO_64")
    expected = (number(enc["cryptoff"]), number(enc["cryptsize"]), number(enc["cryptid"])) if enc else None
    got = (
        (int(image["encryption"]["cryptoff"], 16), image["encryption"]["cryptsize"], image["encryption"]["cryptid"])
        if "encryption" in image else None
    )
    findings.check("encryption", got == expected, where, f"ours {got} otool {expected}")
    sym = first("LC_SYMTAB")
    expected = (number(sym["symoff"]), number(sym["nsyms"]), number(sym["stroff"]), number(sym["strsize"])) if sym else None
    st = image.get("symtab")
    got = (int(st["symoff"], 16), st["nsyms"], int(st["stroff"], 16), st["strsize"]) if st else None
    findings.check("symtab command", got == expected, where, f"ours {got} otool {expected}")


def compare_symbols(image, nm_rows, findings, where):
    symbols = image.get("symbols")
    ours = symbols["list"] if symbols else []
    findings.check("symbol count", len(ours) == len(nm_rows), where, f"ours {len(ours)} nm {len(nm_rows)}")
    if len(ours) != len(nm_rows):
        return
    findings.entries += len(ours)
    sections = [(s["segname"], s["name"]) for seg in image["segments"] for s in seg["sections"]]
    bad_names = bad_values = bad_letters = 0
    first_bad = None
    for mine, theirs in zip(ours, nm_rows):
        value, n_type, sect, desc, name = int(mine[0], 16), mine[1], mine[2], mine[3], mine[4]
        their_value, letter, their_name, stab = theirs
        is_stab = n_type & 0xE0 != 0
        name_ok = (name or "") == their_name or (name is None and "bad string index" in their_name)
        if is_stab and stab is None:
            findings.known["nm prints an unnamed stab as a plain row"] += 1
            value_ok = value == their_value
            letter_ok = nm_letter(mine, sections) == letter
        elif is_stab:
            value_ok = value == their_value and stab == (sect, desc)
            letter_ok = letter == "-"
        else:
            if letter in ("U", "u") and their_value is None:
                value_ok = True
            else:
                value_ok = value == their_value
            letter_ok = nm_letter(mine, sections) == letter
            if letter == "I":
                name_ok = their_name.startswith((name or "") + " (indirect for ")
        bad_names += not name_ok
        bad_values += not value_ok
        bad_letters += not letter_ok
        if first_bad is None and not (name_ok and value_ok and letter_ok):
            first_bad = f"ours {mine} nm {theirs}"
    findings.check("symbol names", bad_names == 0, where, f"{bad_names} differ; first {first_bad}")
    findings.check("symbol values", bad_values == 0, where, f"{bad_values} differ; first {first_bad}")
    findings.check("symbol types", bad_letters == 0, where, f"{bad_letters} differ; first {first_bad}")


# MARK: - One file


def validate(path):
    findings = Findings()
    dump_text = run([DUMP, "--symbols", path])
    if not dump_text:
        findings.check("parsed", False, path, "macho-dump failed")
        return path, findings, 0, None
    dump = json.loads(dump_text)
    if "error" in dump:
        findings.check("parsed", False, path, dump["error"])
        return path, findings, 0, None
    findings.check("parsed", True, path, "")
    archs = (run(["lipo", "-archs", path]) or "").split()
    ours = [s["arch"] or f"cputype {s['cputype']} cpusubtype {s['cpusubtype']}" for s in dump["slices"]]
    findings.check("architectures", ours == archs, path, f"ours {ours} lipo {archs}")
    for slice_ in dump["slices"]:
        image = slice_["image"]
        where = f"{path} [{slice_['arch']}]"
        if image is None:
            findings.check("slice image", False, where, f"no image: {dump['issues']}")
            continue
        findings.check("issues", not image["issues"], where, f"{image['issues']}")
        arch = arch_arguments(dump["universal"], slice_["arch"])
        otool_path = plain_path(path)
        otool_l = run(["otool", "-l"] + arch + [otool_path])
        if otool_l is None:
            findings.check("otool ran", False, where, "otool -l failed")
            continue
        commands = parse_otool_l(otool_l)
        compare_commands(image, commands, findings, where)
        compare_segments(image, commands, findings, where)
        otool_L = run(["otool", "-L"] + arch + [otool_path])
        compare_dylibs(image, commands, parse_otool_L(otool_L) if otool_L is not None else None, findings, where)
        compare_identity(image, commands, findings, where)
        compare_linkedit(image, commands, findings, where)
        nm_text = run(["nm", "-ap", "--no-dyldinfo"] + arch + [path])
        if nm_text is None:
            findings.check("nm ran", image.get("symtab") is None or image["symtab"]["nsyms"] == 0, where, "nm -ap failed")
        else:
            compare_symbols(image, parse_nm(nm_text), findings, where)
    return path, findings, len(dump["slices"]), (dump["size"], dump["parse_us"])


# MARK: - Main


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("paths", nargs="*")
    parser.add_argument("--jobs", type=int, default=max(2, (os.cpu_count() or 4) // 2))
    parser.add_argument("--limit", type=int, default=0)
    parser.add_argument("--report", default="")
    arguments = parser.parse_args()

    build = subprocess.run(["swift", "build", "-c", "release", "--product", "macho-dump"], cwd=PACKAGE, capture_output=True)
    if build.returncode != 0:
        sys.stderr.write(build.stderr.decode())
        return 2
    paths = arguments.paths or default_paths()
    if arguments.limit:
        paths = paths[: arguments.limit]
    started = time.time()
    totals, checks, known = collections.Counter(), collections.Counter(), collections.Counter()
    mismatches = collections.defaultdict(list)
    timings = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=arguments.jobs) as pool:
        for path, findings, slices, timing in pool.map(validate, paths):
            totals["files"] += 1
            totals["slices"] += slices
            totals["symbols"] += findings.entries
            checks.update(findings.checks)
            known.update(findings.known)
            for category, items in findings.mismatches.items():
                mismatches[category] += items
            if timing:
                timings.append((timing[1], timing[0], path))
    report = {
        "files": totals["files"], "slices": totals["slices"], "symbols_compared": totals["symbols"],
        "seconds": round(time.time() - started, 1),
        "checks": dict(checks), "mismatch_counts": {k: len(v) for k, v in mismatches.items()},
        "mismatches": {k: v for k, v in mismatches.items()},
        "known_tool_differences": {k: {"count": n, "why": KNOWN_TOOL_DIFFERENCES[k]} for k, n in known.items()},
        "tool_notes": TOOL_NOTES,
        "slowest_parses_us": sorted(timings, reverse=True)[:5],
        "largest_files": sorted(((t[1], t[0], t[2]) for t in timings), reverse=True)[:5],
    }
    if arguments.report:
        with open(arguments.report, "w") as handle:
            json.dump(report, handle, indent=1)
    print(f"files {report['files']}  slices {report['slices']}  symbols {report['symbols_compared']}  in {report['seconds']} s")
    for category in sorted(checks):
        count = len(mismatches.get(category, []))
        print(f"  {category:22} checks {checks[category]:7}  mismatches {count}")
    for category, count in sorted(known.items()):
        print(f"\nknown tool difference: {category} ({count}): {KNOWN_TOOL_DIFFERENCES[category]}")
    for note in TOOL_NOTES:
        print(f"note: {note}")
    for category, items in sorted(mismatches.items()):
        print(f"\n{category} ({len(items)}):")
        for item in items[:10]:
            print("  " + item[:600])
    print("\nslowest parse (us, bytes, path):", report["slowest_parses_us"][:3])
    print("largest files (bytes, parse us, path):", report["largest_files"][:3])
    return 0 if not mismatches else 1


if __name__ == "__main__":
    sys.exit(main())
