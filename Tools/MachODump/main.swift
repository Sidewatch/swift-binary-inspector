//
//  main.swift
//  macho-dump
//
//  Prints MachOParser's view of Mach-O files as JSON lines, for scripts/validate_macho.py to
//  compare against otool, nm and lipo. A development tool: no product exports it.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import BinaryInspector
import Foundation

/// Usage: `macho-dump [--symbols] [--paths-from FILE] [FILE ...]`. One JSON object per line per
/// file. `--symbols` adds every symbol (value, type, name); `--paths-from` reads paths one per line.
/// 64-bit values are hex strings so no JSON reader rounds them.
func hex(_ value: UInt64) -> String { "0x" + String(value, radix: 16) }

func section(_ s: MachOSection, sliceStart: UInt64) -> [String: Any] {
    [
        "name": s.name, "segname": s.segmentName, "addr": hex(s.address), "size": hex(s.size),
        "offset": s.fileOffset.map { hex($0 - sliceStart) } ?? "0x0", "align": s.alignment, "flags": s.flags, "type": s.type,
    ]
}

func segment(_ s: MachOSegment, sliceStart: UInt64) -> [String: Any] {
    [
        "name": s.name, "vmaddr": hex(s.vmAddress), "vmsize": hex(s.vmSize), "fileoff": hex(s.fileOffset - sliceStart),
        "filesize": hex(s.fileSize), "maxprot": s.maxProtection, "initprot": s.initialProtection, "flags": s.flags,
        "sections": s.sections.map { section($0, sliceStart: sliceStart) },
    ]
}

func dylib(_ d: MachODylib) -> [String: Any] {
    ["kind": d.kind.rawValue, "path": d.path, "current": d.currentVersion.description, "compat": d.compatibilityVersion.description]
}

func build(_ b: MachOBuildVersion) -> [String: Any] {
    [
        "cmd": b.command, "platform": b.platform, "minos": b.minimumOS.description, "sdk": b.sdk.description,
        "tools": b.tools.map { [$0.tool, $0.version.description] as [Any] },
    ]
}

func image(_ i: MachOImage, data: Data, withSymbols: Bool) -> [String: Any] {
    let start = UInt64(i.sliceRange.lowerBound)
    var out: [String: Any] = [
        "slice_start": i.sliceRange.lowerBound, "slice_end": i.sliceRange.upperBound, "is64": i.is64Bit, "big_endian": i.isBigEndian,
        "cputype": i.cpuType, "cpusubtype": i.cpuSubtype, "arch": i.architectureName ?? NSNull(), "filetype": i.fileType,
        "ncmds": i.commandCount, "sizeofcmds": i.commandsSize, "flags": i.flags,
        "commands": i.loadCommands.map { ["name": $0.name, "cmd": $0.command, "size": $0.size, "offset": $0.fileOffset] as [String: Any] },
        "segments": i.segments.map { segment($0, sliceStart: start) }, "dylibs": i.dylibs.map(dylib),
        "id": i.installName.map(dylib) ?? NSNull(), "rpaths": i.rpaths, "uuid": i.uuid?.uuidString ?? NSNull(),
        "builds": i.buildVersions.map(build), "signed": i.isSigned, "issues": i.issues.map { "\($0)" },
    ]
    if let m = i.entryPoint { out["main"] = ["entryoff": hex(m.fileOffset - start), "stacksize": hex(m.stackSize)] }
    if let c = i.codeSignature { out["codesig"] = ["dataoff": hex(c.fileOffset - start), "datasize": c.size, "inside": c.isWithinSlice] }
    if let e = i.encryption { out["encryption"] = ["cryptoff": hex(e.fileOffset - start), "cryptsize": e.size, "cryptid": e.cryptID] }
    if let t = i.symbolTable {
        out["symtab"] = [
            "symoff": hex(t.symbolsOffset - start), "nsyms": t.symbolCount, "stroff": hex(t.stringsOffset - start),
            "strsize": t.stringsSize,
        ]
        let table = MachOParser.symbols(in: data, image: i, limit: Int.max)
        var symbols: [String: Any] = ["count": table.symbols.count, "truncated": table.truncated]
        if withSymbols {
            symbols["list"] = table.symbols.map {
                [hex($0.value), Int($0.type), Int($0.sectionNumber), Int($0.descriptor), $0.name ?? NSNull()] as [Any]
            }
        }
        out["symbols"] = symbols
    }
    return out
}

func dump(_ path: String, withSymbols: Bool) -> [String: Any] {
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: path), options: .alwaysMapped) else {
        return ["path": path, "error": "unreadable"]
    }
    let clock = ContinuousClock()
    var parsed: MachOFile?
    let elapsed = clock.measure { parsed = MachOParser.parse(data) }
    guard let file = parsed else { return ["path": path, "error": "not mach-o"] }
    let microseconds = elapsed.components.attoseconds / 1_000_000_000_000 + elapsed.components.seconds * 1_000_000
    return [
        "path": path, "size": data.count, "parse_us": microseconds, "universal": file.isUniversal, "fat64": file.usesFat64,
        "issues": file.issues.map { "\($0)" },
        "slices": file.slices.map { s -> [String: Any] in
            [
                "index": s.index, "arch": s.architectureName ?? NSNull(), "cputype": s.cpuType, "cpusubtype": s.cpuSubtype,
                "offset": hex(s.offset), "size": hex(s.size), "align": s.alignment,
                "image": s.image.map { image($0, data: data, withSymbols: withSymbols) } ?? NSNull(),
            ]
        },
    ]
}

var arguments = Array(CommandLine.arguments.dropFirst())
let withSymbols = arguments.contains("--symbols")
arguments.removeAll { $0 == "--symbols" }
var paths: [String] = []
var index = 0
while index < arguments.count {
    if arguments[index] == "--paths-from", index + 1 < arguments.count {
        let list = (try? String(contentsOfFile: arguments[index + 1], encoding: .utf8)) ?? ""
        paths += list.split(separator: "\n").map(String.init)
        index += 2
    } else {
        paths.append(arguments[index])
        index += 1
    }
}
for path in paths {
    autoreleasepool {
        let object = dump(path, withSymbols: withSymbols)
        if let json = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) {
            FileHandle.standardOutput.write(json)
            FileHandle.standardOutput.write(Data("\n".utf8))
        }
    }
}
