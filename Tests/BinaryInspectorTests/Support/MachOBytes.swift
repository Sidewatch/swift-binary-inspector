//
//  MachOBytes.swift
//  BinaryInspectorTests
//
//  Builds small Mach-O images byte by byte, for the cases the checked-in fixtures cannot
//  cover: 32-bit and big-endian images, obsolete commands and deliberately malformed files.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A byte writer in one byte order.
struct MachOBytes {
    /// True to write multi-byte values big-endian.
    var bigEndian: Bool
    /// The bytes written so far.
    private(set) var bytes: [UInt8] = []

    init(bigEndian: Bool = false) { self.bigEndian = bigEndian }

    mutating func u8(_ value: UInt8) { bytes.append(value) }
    mutating func u16(_ value: UInt16) { append(UInt64(value), width: 2) }
    mutating func u32(_ value: UInt32) { append(UInt64(value), width: 4) }
    mutating func u64(_ value: UInt64) { append(value, width: 8) }
    /// A pointer-sized value: 8 bytes when `wide`, else 4.
    mutating func word(_ value: UInt64, wide: Bool) { wide ? u64(value) : u32(UInt32(truncatingIfNeeded: value)) }
    /// A fixed 16-byte name field, NUL-padded.
    mutating func name16(_ name: String) { raw(Array(name.utf8.prefix(16)) + Array(repeating: 0, count: 16 - min(16, name.utf8.count))) }
    mutating func raw(_ more: [UInt8]) { bytes += more }
    /// Zero bytes up to a multiple of `alignment`.
    mutating func pad(to alignment: Int) { while bytes.count % alignment != 0 { bytes.append(0) } }

    private mutating func append(_ value: UInt64, width: Int) {
        for i in 0..<width {
            let shift = bigEndian ? (width - 1 - i) * 8 : i * 8
            bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift)))
        }
    }
}

/// One section for `MachOImageBuilder.segment`.
struct TestSection {
    var name: String
    var segment: String
    var address: UInt64
    var size: UInt64
    var offset: UInt32
    var flags: UInt32 = 0
}

/// Builds a whole thin image: a header followed by load commands, then optional trailing bytes.
struct MachOImageBuilder {
    var is64: Bool
    var bigEndian: Bool
    var cpuType: UInt32 = 0x0100_000C
    var cpuSubtype: UInt32 = 0
    var fileType: UInt32 = 2
    var flags: UInt32 = 0
    /// Each command's complete bytes, header included.
    var commands: [[UInt8]] = []
    /// Overrides for the header's `ncmds` / `sizeofcmds` (nil: computed).
    var declaredCount: UInt32?
    var declaredSize: UInt32?

    init(is64: Bool = true, bigEndian: Bool = false) {
        self.is64 = is64
        self.bigEndian = bigEndian
    }

    var headerSize: Int { is64 ? 32 : 28 }
    /// Where the bytes after the load commands start.
    var commandsEnd: Int { headerSize + commands.reduce(0) { $0 + $1.count } }

    func writer() -> MachOBytes { MachOBytes(bigEndian: bigEndian) }

    /// The image, followed by `trailing` bytes.
    func build(trailing: [UInt8] = []) -> Data {
        var w = writer()
        w.u32(is64 ? 0xFEED_FACF : 0xFEED_FACE)
        w.u32(cpuType)
        w.u32(cpuSubtype)
        w.u32(fileType)
        w.u32(declaredCount ?? UInt32(commands.count))
        w.u32(declaredSize ?? UInt32(commands.reduce(0) { $0 + $1.count }))
        w.u32(flags)
        if is64 { w.u32(0) }
        for command in commands { w.raw(command) }
        w.raw(trailing)
        return Data(w.bytes)
    }

    /// A command with `cmd`, a computed `cmdsize`, and `body` after the 8-byte header.
    func command(_ cmd: UInt32, size: UInt32? = nil, _ body: (inout MachOBytes) -> Void) -> [UInt8] {
        var b = writer()
        body(&b)
        var w = writer()
        w.u32(cmd)
        w.u32(size ?? UInt32(8 + b.bytes.count))
        w.raw(b.bytes)
        return w.bytes
    }

    /// `LC_SEGMENT` or `LC_SEGMENT_64` (by `is64`) with `sections`.
    func segment(
        _ name: String, vmAddress: UInt64, vmSize: UInt64, fileOffset: UInt64, fileSize: UInt64, sections: [TestSection] = [],
        declaredSections: UInt32? = nil
    ) -> [UInt8] {
        command(is64 ? 0x19 : 0x1) { w in
            w.name16(name)
            for value in [vmAddress, vmSize, fileOffset, fileSize] { w.word(value, wide: is64) }
            w.u32(7)
            w.u32(5)
            w.u32(declaredSections ?? UInt32(sections.count))
            w.u32(0)
            for s in sections {
                w.name16(s.name)
                w.name16(s.segment)
                w.word(s.address, wide: is64)
                w.word(s.size, wide: is64)
                w.u32(s.offset)
                w.u32(2)
                w.u32(0)
                w.u32(0)
                w.u32(s.flags)
                w.u32(0)
                w.u32(0)
                if is64 { w.u32(0) }
            }
        }
    }

    /// A dylib command (`cmd` picks the kind) naming `path`.
    func dylib(_ cmd: UInt32, _ path: String, current: UInt32 = 0x10000, compatibility: UInt32 = 0x10000, nameOffset: UInt32 = 24)
        -> [UInt8]
    {
        command(cmd) { w in
            w.u32(nameOffset)
            w.u32(2)
            w.u32(current)
            w.u32(compatibility)
            w.raw(Array(path.utf8) + [0])
            w.pad(to: 8)
        }
    }

    /// `LC_SYMTAB`.
    func symtab(symbolsOffset: UInt32, count: UInt32, stringsOffset: UInt32, stringsSize: UInt32) -> [UInt8] {
        command(0x2) { w in
            w.u32(symbolsOffset)
            w.u32(count)
            w.u32(stringsOffset)
            w.u32(stringsSize)
        }
    }
}
