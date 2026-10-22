# Audit log

Last full audit: **17 Sep 2026** — every source file covered by the MECHANICAL checks below (build warnings, tests,
dead-code and risk-pattern scans, docs drift); line-by-line logic review was targeted at the areas changed since
5 Sep 2026, not the whole tree. Nothing needs re-scanning unless it changed after that date. Add a dated line under *History* when you audit again, and keep the
*Known non-issues* list current so the next pass skips them.

## What a full audit checks

1. `swift build` warnings (none allowed except those listed under known non-issues) and `swift test` green.
2. Dead code: every `func`/type/property declared once and referenced nowhere in the app or the family
   (`grep -w` across `*.swift` AND non-Swift files — selectors and MCP names live in strings). Protocol
   requirements, `override`s, `@objc` actions and public API are NOT dead because Sidewatch does not call them.
3. Risky patterns: `Timer` without `invalidate`, `addObserver(forName:)` without `removeObserver`, `as!`, `try!`
   outside literal regexes, `fatalError` outside `init?(coder:)`, `print(` outside harnesses, TODO/FIXME left behind.
4. Docs drift: every name in CLAUDE.md's module map exists; AGENTS.md mirrors CLAUDE.md; README Usage matches the API.

## Result on 17 Sep 2026

- Build: clean. Tests: green.
- Nothing to fix in this package.

## Logic review — 18 Sep 2026 (every source and test file, line by line)

Nothing to fix. Checked: `BinaryBuffer`'s piece table (`splitBoundary` re-walks for the second edge
of a removal, so its index is valid after the first split; `added` is append-only, so a snapshot of
the piece list restores any state exactly; `isModified` is a comparison against `savedPieces`, not a
flag; the differential fuzz against a plain array), `BinaryDiff.compare`'s honest `truncated`,
every `ByteReader` read bounds-checked (PE's `e_lfanew` may be any 32-bit value and cannot overflow
a 64-bit offset), the 0xCAFEBABE disambiguation, `ByteSearch`'s overlapping matches, `Entropy`,
`HexDump` over a slice with a non-zero `startIndex`.

## Mach-O structure parser — 22 Oct 2026 (new code, validated against Apple's tools)

`MachOParser` (Core/), its models (Models/, Enums/), helpers (Support/) and readers (Internal/) were
added. `scripts/validate_macho.py` runs the parser (through the `macho-dump` tool) over every
Mach-O file in /usr/bin, /usr/sbin, /bin, /sbin, /usr/libexec (top level),
/Applications/*/Contents/MacOS, every Mach-O file under /Applications/*/Contents/Frameworks,
/Library/Audio/Plug-Ins/VST3 and Components bundles, and /System/Applications/*/Contents/MacOS
(symlinks skipped, real paths deduplicated), and compares per slice with `lipo -archs`,
`otool -l`, `otool -L` and `nm -ap --no-dyldinfo`.

- Result: **1,629 files, 4,126 slices, 3,656,016 symbols, 0 mismatches** in every category:
  architectures; command count, names and sizes (111,460); segment fields incl. protections
  (20,013); section name/segname/addr/size/offset/align/flags (72,486); dylibs by kind, path and
  versions (otool -l and otool -L); install name; rpaths; UUID; LC_BUILD_VERSION and
  LC_VERSION_MIN_* incl. tools; LC_MAIN; LC_CODE_SIGNATURE and the signed flag; encryption;
  LC_SYMTAB; every symbol's name, value, stab sect/desc and nm type letter. The 7 test fixtures
  (9 slices) also validate clean.
- Corpus coverage: 1,462 universal + 167 thin; arm64e, arm64e.x1, x86_64, x86_64h, arm64;
  executables, dylibs (186 install names), bundles; 286 slices with rpaths; weak links; 60
  LC_VERSION_MIN_MACOSX; 40 Mac Catalyst build versions. NOT in the corpus, so covered only by
  the fixtures (re-export and upward links, fat_arch_64, MH_OBJECT) or by hand-built images in
  MachOMalformedTests (lazy links, 32-bit and big-endian images, LC_ENCRYPTION_INFO(_64),
  tvOS/watchOS/iOS version-min). System dylibs live in the dyld shared cache, not on disk.
- Known tool differences (compared in the tools' own terms, not mismatches):
  - llvm-nm prints stab type N_AST (0x32, a Swift module path; 20 entries) as a plain `a` row.
  - llvm-nm adds export-trie symbols unless given `--no-dyldinfo`.
  - The otool wrapper re-splits a path containing parentheses; the script calls it through a
    plain-named symlink.
- Performance: parse (headers and load commands) of the 526 MB universal Chrome framework
  (2 slices, 158 commands) 0.11–0.22 ms; slowest of all 1,629 files 3.5 ms (cold, 8 jobs in
  parallel). macho-dump over IDEFoundation, 138,425 symbols read and serialised: 20 ms total.
- Mutation testing: 60 mutants of the new code, all KILLED by the new tests (59 in the first
  run; M39, the slice-bound check in `address(forFileOffset:)`, survived until a segment whose
  file range runs past the slice was added to the test). The crash and hang mutants were re-run
  against each robustness test alone: the fuzz test kills M01 (bounds check off), M47 (cString
  offset unchecked), M16 (nsects uncapped, hangs) and M48 (walk past the bytes, hangs); the
  truncation test kills M01, M47 and M13; the hostile-count test kills M48.

## Known non-issues (do not "fix" these again)

- `BinaryBuffer.clearHistory()` has no caller in Sidewatch — public API, kept on purpose.
- `BinaryStrings` scans UTF-16 at even offsets from byte 0 only; a wide string starting at an odd
  offset is not found. Scanning both parities would double the cost for a case that has not come up.
- `MachOParser` keeps the FIRST `LC_UUID`, `LC_MAIN`, `LC_CODE_SIGNATURE`, encryption and `LC_SYMTAB`
  command when a damaged file repeats one, and caps a universal header at 30 slices (the same line
  `BinaryFormat` draws against Java class files). A section whose `offset` is 0 has a nil
  `fileOffset`. These are decisions, not bugs.
- `macho-dump` (Tools/) has no product on purpose: it is a development tool for the validation script.

## History

- 17 Sep 2026 — full audit (app + all 20 libraries), Claude with David.
- 18 Sep 2026 — logic review (every source and test file, line by line), Claude with David.
- 22 Oct 2026 — Mach-O structure parser added; validated against lipo/otool/nm (1,629 files, 4,126 slices, 0 mismatches); 60 mutants killed.
- 22 Oct 2026 (evening) — real 32-bit and encrypted fixtures added (`make_fixtures.sh`): a LINKED 32-bit
  executable (watchOS arm64_32: MH_MAGIC, LC_SEGMENT, 32-bit nlist), i386 and armv7 objects (current linkers refuse
  to link either; clang still compiles them), an iOS executable linked `-encryptable` (a real
  LC_ENCRYPTION_INFO_64, cryptid 0) and the same file with cryptid 1, as FairPlay leaves an App Store binary.
  `scripts/validate_macho.py` over all 12 fixtures: 0 mismatches in every category, encryption included. Exact-value
  tests from otool and nm; the fuzz and truncation tests cover the new files. Mutants killed: 32-bit nlist read as
  64-bit, LC_SEGMENT read as LC_SEGMENT_64, cryptid read from the padding (caught only by the cryptid 1 copy).
  Still only hand-built: big-endian images (only PowerPC produced them; no current Apple tool can, and LLVM's
  big-endian ARM targets emit ELF) and lazy links (the linker no longer supports `-lazy_library`).

