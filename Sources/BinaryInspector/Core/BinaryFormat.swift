//
//  BinaryFormat.swift
//  SwiftBinaryInspect
//
//  Structural header parsing for the common executable formats: Mach-O, ELF, PE, Java, WASM.
//
//  Created by David Sherlock on 7/18/26.
//

import Foundation

/// Parses just enough of an executable's header to describe it: format, word size,
/// byte order, CPU architecture, object type, and a few extra display fields. Every read
/// is bounds-checked, so a truncated or non-executable file simply returns `nil` (or an
/// `Info` with the unknown pieces left `nil`) rather than trapping.
public enum BinaryFormat {

    /// The recognized container formats.
    public enum Kind: String {
        case machO = "Mach-O"
        case machOUniversal = "Mach-O Universal"
        case elf = "ELF"
        case pe = "PE/COFF"
        case java = "Java class"
        case wasm = "WebAssembly"
    }

    /// Byte order of the multi-byte fields.
    public enum Endian: String { case little = "little-endian", big = "big-endian" }

    /// A parsed header summary. `bits`/`endian`/`arch`/`type` are best-effort and may be
    /// `nil` for a format where the field doesn't apply; `fields` carries extra
    /// name/value rows for a details panel.
    public struct Info: Equatable {
        public let kind: Kind
        public let bits: Int?
        public let endian: Endian?
        public let arch: String?
        public let type: String?
        public let fields: [Field]

        public init(kind: Kind, bits: Int?, endian: Endian?, arch: String?, type: String?, fields: [Field]) {
            self.kind = kind; self.bits = bits; self.endian = endian
            self.arch = arch; self.type = type; self.fields = fields
        }
    }

    /// A single name/value row for display.
    public struct Field: Equatable {
        public let name: String
        public let value: String
        public init(_ name: String, _ value: String) { self.name = name; self.value = value }
    }

    /// Parse `data`'s executable header, or `nil` when it isn't one of the known formats.
    public static func parse(_ data: Data) -> Info? {
        guard data.count >= 4 else { return nil }
        if ByteReader.hasPrefix(data, [0x7F, 0x45, 0x4C, 0x46]) { return parseELF(data) }
        if ByteReader.hasPrefix(data, [0xCA, 0xFE, 0xBA, 0xBE]) {
            // Shared 0xCAFEBABE magic: small arch count ⇒ Mach-O universal, else Java class.
            let count = ByteReader.u32(data, 4, bigEndian: true) ?? 0xFFFF
            return count <= 30 ? parseMachOFat(data, archCount: count) : parseJava(data)
        }
        for magic in machOMagics where ByteReader.hasPrefix(data, magic.bytes) { return parseMachO(data, magic) }
        if ByteReader.hasPrefix(data, [0x4D, 0x5A]) { return parsePE(data) }
        if ByteReader.hasPrefix(data, [0x00, 0x61, 0x73, 0x6D]) { return parseWASM(data) }
        return nil
    }

    // MARK: - ELF

    private static func parseELF(_ d: Data) -> Info {
        let is64 = d.count > 4 && d[d.startIndex + 4] == 2
        let big = d.count > 5 && d[d.startIndex + 5] == 2
        let type = ByteReader.u16(d, 16, bigEndian: big).map { elfType($0) }
        let machine = ByteReader.u16(d, 18, bigEndian: big).map { elfMachine($0) }
        return Info(kind: .elf, bits: is64 ? 64 : 32, endian: big ? .big : .little,
                    arch: machine, type: type,
                    fields: [Field("Class", is64 ? "ELF64" : "ELF32")])
    }

    private static func elfType(_ t: UInt16) -> String {
        switch t {
        case 1: return "relocatable"
        case 2: return "executable"
        case 3: return "shared object"
        case 4: return "core dump"
        default: return "type 0x\(String(t, radix: 16))"
        }
    }

    private static func elfMachine(_ m: UInt16) -> String {
        switch m {
        case 0x02: return "SPARC"
        case 0x03: return "x86"
        case 0x08: return "MIPS"
        case 0x14: return "PowerPC"
        case 0x15: return "PowerPC64"
        case 0x28: return "ARM"
        case 0x3E: return "x86-64"
        case 0xB7: return "AArch64"
        case 0xF3: return "RISC-V"
        default:   return "machine 0x\(String(m, radix: 16))"
        }
    }

    // MARK: - Mach-O

    private struct MachOMagic { let bytes: [UInt8]; let is64: Bool; let big: Bool }
    private static let machOMagics: [MachOMagic] = [
        .init(bytes: [0xFE, 0xED, 0xFA, 0xCE], is64: false, big: true),   // 32-bit BE
        .init(bytes: [0xFE, 0xED, 0xFA, 0xCF], is64: true,  big: true),   // 64-bit BE
        .init(bytes: [0xCE, 0xFA, 0xED, 0xFE], is64: false, big: false),  // 32-bit LE
        .init(bytes: [0xCF, 0xFA, 0xED, 0xFE], is64: true,  big: false),  // 64-bit LE
    ]

    private static func parseMachO(_ d: Data, _ m: MachOMagic) -> Info {
        let cpu = ByteReader.u32(d, 4, bigEndian: m.big)
        let filetype = ByteReader.u32(d, 12, bigEndian: m.big)
        return Info(kind: .machO, bits: m.is64 ? 64 : 32, endian: m.big ? .big : .little,
                    arch: cpu.map { machoCPU($0) }, type: filetype.map { machoType($0) },
                    fields: [Field("Magic", m.is64 ? "MH_MAGIC_64" : "MH_MAGIC")])
    }

    private static func parseMachOFat(_ d: Data, archCount: UInt32) -> Info {
        // The fat header is always big-endian; each fat_arch is cputype(4) cpusubtype(4)
        // offset(4) size(4) align(4) = 20 bytes, starting at offset 8.
        var arches: [String] = []
        for i in 0..<Int(min(archCount, 30)) {
            if let cpu = ByteReader.u32(d, 8 + i * 20, bigEndian: true) { arches.append(machoCPU(cpu)) }
        }
        return Info(kind: .machOUniversal, bits: nil, endian: .big, arch: arches.joined(separator: ", "),
                    type: "universal (\(archCount) slices)",
                    fields: arches.enumerated().map { Field("Slice \($0.offset)", $0.element) })
    }

    private static func machoCPU(_ c: UInt32) -> String {
        switch c {
        case 7:          return "x86"
        case 0x0100_0007: return "x86-64"
        case 12:         return "ARM"
        case 0x0100_000C: return "ARM64"
        case 18:         return "PowerPC"
        case 0x0100_0012: return "PowerPC64"
        default:         return "cpu 0x\(String(c, radix: 16))"
        }
    }

    private static func machoType(_ t: UInt32) -> String {
        switch t {
        case 1:  return "object"
        case 2:  return "executable"
        case 4:  return "core dump"
        case 6:  return "dynamic library"
        case 7:  return "dynamic linker"
        case 8:  return "bundle"
        case 10: return "dSYM companion"
        default: return "type \(t)"
        }
    }

    // MARK: - PE / COFF

    private static func parsePE(_ d: Data) -> Info? {
        guard let lfanew = ByteReader.u32(d, 0x3C, bigEndian: false) else {
            return Info(kind: .pe, bits: nil, endian: .little, arch: nil, type: "DOS/MZ", fields: [])
        }
        let pe = Int(lfanew)
        guard ByteReader.matches(d, at: pe, [0x50, 0x45, 0x00, 0x00]) else {
            return Info(kind: .pe, bits: nil, endian: .little, arch: nil, type: "DOS/MZ (no PE header)", fields: [])
        }
        let machine = ByteReader.u16(d, pe + 4, bigEndian: false)
        let characteristics = ByteReader.u16(d, pe + 22, bigEndian: false) ?? 0
        let isDLL = characteristics & 0x2000 != 0
        let (arch, bits) = machine.map { peMachine($0) } ?? (nil, nil)
        return Info(kind: .pe, bits: bits, endian: .little, arch: arch,
                    type: isDLL ? "dynamic library" : "executable",
                    fields: [Field("Characteristics", "0x\(String(characteristics, radix: 16))")])
    }

    private static func peMachine(_ m: UInt16) -> (String?, Int?) {
        switch m {
        case 0x014C: return ("x86", 32)
        case 0x8664: return ("x86-64", 64)
        case 0x01C0: return ("ARM", 32)
        case 0xAA64: return ("ARM64", 64)
        case 0x0200: return ("IA-64", 64)
        default:     return ("machine 0x\(String(m, radix: 16))", nil)
        }
    }

    // MARK: - Java / WASM

    private static func parseJava(_ d: Data) -> Info {
        let major = ByteReader.u16(d, 6, bigEndian: true) ?? 0
        // Class-file major 45 == Java 1.1; each later Java release adds one.
        let java = major >= 45 ? "Java \(major - 44)" : "pre-1.1"
        return Info(kind: .java, bits: nil, endian: .big, arch: "JVM bytecode", type: "class file",
                    fields: [Field("Class version", "\(major)"), Field("Target", java)])
    }

    private static func parseWASM(_ d: Data) -> Info {
        let version = ByteReader.u32(d, 4, bigEndian: false) ?? 0
        return Info(kind: .wasm, bits: 32, endian: .little, arch: "WebAssembly", type: "module",
                    fields: [Field("Version", "\(version)")])
    }
}
