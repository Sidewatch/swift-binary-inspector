//
//  MachOMalformedTests.swift
//  BinaryInspectorTests
//
//  Tests for MachOParser on hand-built images: 32-bit and big-endian layouts, commands no
//  fixture carries, and every malformed case the parser steps around instead of failing.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import BinaryInspector

/// Tests for `MachOParser` on images built by `MachOImageBuilder`.
final class MachOMalformedTests: XCTestCase {

    private func parseImage(_ data: Data, file: StaticString = #filePath, line: UInt = #line) throws -> MachOImage {
        try XCTUnwrap(MachOParser.parse(data)?.slices.first?.image, file: file, line: line)
    }

    // MARK: - 32-bit and big-endian layouts

    /// A 32-bit big-endian image (MH_CIGAM, PowerPC): LC_SEGMENT with `section`, nlist entries,
    /// a lazy dylib — every field read in the right width and byte order.
    func testThirtyTwoBitBigEndianImage() throws {
        var b = MachOImageBuilder(is64: false, bigEndian: true)
        b.cpuType = 18
        b.cpuSubtype = 0
        b.fileType = 2
        b.flags = 0x85
        b.commands = [
            b.segment(
                "__TEXT", vmAddress: 0x1000, vmSize: 0x2000, fileOffset: 0, fileSize: 0x1800,
                sections: [TestSection(name: "__text", segment: "__TEXT", address: 0x1100, size: 0x40, offset: 0x100, flags: 0x8000_0400)]),
            b.dylib(0x20, "/usr/lib/libLazy.dylib", current: 0x0001_0203, compatibility: 0x0001_0000),
            [],  // the symtab, filled in once the command area's size is known
        ]
        b.commands[2] = b.symtab(symbolsOffset: 0, count: 0, stringsOffset: 0, stringsSize: 0)
        let tables = b.commandsEnd
        b.commands[2] = b.symtab(symbolsOffset: UInt32(tables), count: 2, stringsOffset: UInt32(tables + 24), stringsSize: 16)
        var t = b.writer()
        for (strx, type, sect, desc, value) in [
            (1 as UInt32, 0x0F as UInt8, 1 as UInt8, 0x0010 as UInt16, 0x1100 as UInt32), (8, 0x01, 0, 0x0100, 0),
        ] {
            t.u32(strx)
            t.u8(type)
            t.u8(sect)
            t.u16(desc)
            t.u32(value)
        }
        t.raw(Array("\0_start\0_puts\0\0\0".utf8))
        let data = b.build(trailing: t.bytes)

        let image = try parseImage(data)
        XCTAssertFalse(image.is64Bit)
        XCTAssertTrue(image.isBigEndian)
        XCTAssertEqual(image.cpuType, 18)
        XCTAssertEqual(image.architectureName, "ppc")
        XCTAssertEqual(image.flags, 0x85)
        XCTAssertEqual(image.loadCommands.map(\.name), ["LC_SEGMENT", "LC_LAZY_LOAD_DYLIB", "LC_SYMTAB"])
        XCTAssertEqual(image.issues, [])
        let segment = try XCTUnwrap(image.segments.first)
        XCTAssertEqual(segment.name, "__TEXT")
        XCTAssertEqual(segment.vmAddress, 0x1000)
        XCTAssertEqual(segment.vmSize, 0x2000)
        XCTAssertEqual(segment.fileSize, 0x1800)
        XCTAssertEqual(segment.maxProtection, 7)
        XCTAssertEqual(segment.initialProtection, 5)
        XCTAssertEqual(
            segment.sections,
            [
                MachOSection(
                    name: "__text", segmentName: "__TEXT", address: 0x1100, size: 0x40, fileOffset: 0x100, alignment: 2, flags: 0x8000_0400)
            ])
        XCTAssertEqual(image.dylibs.map(\.kind), [.lazy])
        XCTAssertEqual(image.dylibs.first?.path, "/usr/lib/libLazy.dylib")
        XCTAssertEqual(image.dylibs.first?.currentVersion.description, "1.2.3")

        let symbols = MachOParser.symbols(in: data, image: image).symbols
        XCTAssertEqual(symbols.map(\.name), ["_start", "_puts"])
        XCTAssertEqual(symbols.map(\.value), [0x1100, 0])
        XCTAssertEqual(symbols.map(\.type), [0x0F, 0x01])
        XCTAssertEqual(symbols.map(\.sectionNumber), [1, 0])
        XCTAssertEqual(symbols.map(\.descriptor), [0x0010, 0x0100])
        XCTAssertEqual(symbols.map(\.kind), [.section, .undefined])
    }

    /// A 32-bit little-endian image (MH_MAGIC, i386) with the commands no fixture carries.
    func testThirtyTwoBitLittleEndianImageWithObsoleteCommands() throws {
        var b = MachOImageBuilder(is64: false, bigEndian: false)
        b.cpuType = 7
        b.cpuSubtype = 3
        b.commands = [
            b.command(0x21) { w in
                w.u32(0x1000)
                w.u32(0x2000)
                w.u32(1)
            },
            b.command(0x25) { w in
                w.u32(0x0009_0300)
                w.u32(0x000A_0000)
            },
            b.command(0x1B) { w in w.raw(Array(0..<16)) },
            b.command(0x8000_001C) { w in
                w.u32(12)
                w.raw(Array("@executable_path/Frameworks\0".utf8))
            },
        ]
        let image = try parseImage(b.build())
        XCTAssertFalse(image.is64Bit)
        XCTAssertFalse(image.isBigEndian)
        XCTAssertEqual(image.architectureName, "i386")
        XCTAssertEqual(image.encryption, MachOEncryptionInfo(fileOffset: 0x1000, size: 0x2000, cryptID: 1))
        XCTAssertEqual(image.encryption?.isEncrypted, true)
        XCTAssertEqual(
            image.buildVersions,
            [
                MachOBuildVersion(
                    command: 0x25, platform: 2, minimumOS: MachOVersion(rawValue: 0x0009_0300), sdk: MachOVersion(rawValue: 0x000A_0000),
                    tools: [])
            ])
        XCTAssertEqual(image.buildVersions.first?.minimumOS.description, "9.3.0")
        XCTAssertEqual(image.uuid, UUID(uuid: (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15)))
        XCTAssertEqual(image.rpaths, ["@executable_path/Frameworks"])
    }

    func testEncryptionInfo64AndTVOSWatchOSVersionMins() throws {
        var b = MachOImageBuilder()
        b.commands = [
            b.command(0x2C) { w in
                w.u32(0x4000)
                w.u32(0x8000)
                w.u32(0)
                w.u32(0)
            },
            b.command(0x2F) { w in
                w.u32(0x000C_0000)
                w.u32(0)
            },
            b.command(0x30) { w in
                w.u32(0x0005_0000)
                w.u32(0)
            },
            b.command(0x24) { w in
                w.u32(0x000A_0F00)
                w.u32(0)
            },
        ]
        let image = try parseImage(b.build())
        XCTAssertEqual(image.encryption, MachOEncryptionInfo(fileOffset: 0x4000, size: 0x8000, cryptID: 0))
        XCTAssertEqual(image.encryption?.isEncrypted, false)
        XCTAssertEqual(image.buildVersions.map(\.platform), [3, 4, 1])
        XCTAssertEqual(image.buildVersions.map(\.command), [0x2F, 0x30, 0x24])
    }

    // MARK: - Names

    func testLoadCommandNames() {
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x19), "LC_SEGMENT_64")
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x22), "LC_DYLD_INFO")
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x8000_0022), "LC_DYLD_INFO_ONLY")
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x8000_0018), "LC_LOAD_WEAK_DYLIB")
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x18), "0x18")  // the weak number without LC_REQ_DYLD is not a command
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x3A), "LC_LAZY_LOAD_DYLIB_INFO")
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x3B), "0x3b")
        XCTAssertEqual(MachOLoadCommandName.name(for: 0x8000_003B), "LC_REQ_DYLD|0x3b")
        XCTAssertEqual(MachOLoadCommandName.name(for: 0), "0x0")
    }

    func testArchitectureNames() {
        func name(_ type: UInt32, _ subtype: UInt32) -> String? {
            MachOArchitecture.name(cpuType: Int32(bitPattern: type), cpuSubtype: Int32(bitPattern: subtype))
        }
        XCTAssertEqual(name(0x0100_000C, 0), "arm64")
        XCTAssertEqual(name(0x0100_000C, 2), "arm64e")
        XCTAssertEqual(name(0x0100_000C, 0x8000_0002), "arm64e")  // pointer-auth ABI bits masked off
        XCTAssertEqual(name(0x0100_000C, 0x8000_000C), "arm64e.x1")
        XCTAssertEqual(name(0x0100_0007, 3), "x86_64")
        XCTAssertEqual(name(0x0100_0007, 0x8000_0003), "x86_64")  // CPU_SUBTYPE_LIB64
        XCTAssertEqual(name(0x0100_0007, 8), "x86_64h")
        XCTAssertEqual(name(7, 3), "i386")
        XCTAssertEqual(name(0x0200_000C, 1), "arm64_32")
        XCTAssertEqual(name(12, 9), "armv7")
        XCTAssertEqual(name(12, 12), "armv7k")
        XCTAssertNil(name(0x0100_000C, 99))
        XCTAssertNil(name(0x99, 0))
    }

    func testVersionDecoding() {
        let version = MachOVersion(rawValue: 0x054F_0A0B)
        XCTAssertEqual(version.major, 1359)
        XCTAssertEqual(version.minor, 10)
        XCTAssertEqual(version.patch, 11)
        XCTAssertEqual(version.description, "1359.10.11")
        XCTAssertEqual(MachOVersion(rawValue: 0xFFFF_FFFF).description, "65535.255.255")
    }

    func testSymbolTypeDecoding() {
        func symbol(_ type: UInt8) -> MachOSymbol { MachOSymbol(name: "s", type: type, sectionNumber: 0, descriptor: 0, value: 0) }
        // A stab whose code has the low bit set (N_OLEVEL 0x87) is not external.
        XCTAssertTrue(symbol(0x87).isDebug)
        XCTAssertFalse(symbol(0x87).isExternal)
        XCTAssertFalse(symbol(0xF0).isPrivateExternal)
        XCTAssertNil(symbol(0x87).kind)
        // N_PEXT | N_SECT | N_EXT.
        XCTAssertTrue(symbol(0x1F).isPrivateExternal)
        XCTAssertTrue(symbol(0x1F).isExternal)
        XCTAssertEqual(symbol(0x1F).kind, .section)
        XCTAssertEqual(symbol(0x0B).kind, .indirect)
        XCTAssertEqual(symbol(0x0C).kind, .prebound)
        XCTAssertEqual(symbol(0x02).kind, .absolute)
        XCTAssertEqual(symbol(0x01).kind, .undefined)
        XCTAssertNil(symbol(0x08).kind)  // N_TYPE 0x8 is not defined
    }

    /// The three zero-fill section types, and a zero-fill section that (oddly) records a file
    /// offset: it still has no bytes in the file.
    func testZeroFillSections() throws {
        func section(_ flags: UInt32, offset: UInt64?) -> MachOSection {
            MachOSection(name: "__z", segmentName: "__DATA", address: 0x2000, size: 0x100, fileOffset: offset, alignment: 0, flags: flags)
        }
        XCTAssertEqual(
            [0x01, 0x0C, 0x12, 0x00, 0x02, 0x8000_0001].map { section($0, offset: nil).isZeroFill }, [true, true, true, false, false, true])
        let image = MachOImage(
            sliceRange: 0..<0x4000, is64Bit: true, isBigEndian: false, cpuType: 0x0100_000C, cpuSubtype: 0, architectureName: "arm64",
            fileType: 2, commandCount: 0, commandsSize: 0, flags: 0,
            segments: [
                MachOSegment(
                    name: "__DATA", vmAddress: 0x2000, vmSize: 0x1000, fileOffset: 0x1000, fileSize: 0x1000, maxProtection: 3,
                    initialProtection: 3, flags: 0, sections: [section(0x0C, offset: 0x1000), section(0, offset: 0x1000)])
            ])
        XCTAssertEqual(image.section(containingFileOffset: 0x1000)?.flags, 0)  // the regular one, not the zero-fill one
        XCTAssertEqual(image.section(containingAddress: 0x2000)?.flags, 0x0C)  // by address, the first one
    }

    // MARK: - Malformed load commands

    func testCommandSizeBelowEightStopsTheWalk() throws {
        var b = MachOImageBuilder()
        b.commands = [b.command(0x1B) { w in w.raw(Array(repeating: 1, count: 16)) }, b.command(0x99, size: 0) { _ in }]
        let image = try parseImage(b.build(trailing: Array(repeating: 0, count: 64)))
        XCTAssertEqual(image.loadCommands.count, 1)
        XCTAssertEqual(image.issues, [.badCommandSize(index: 1, fileOffset: 32 + 24, size: 0)])
        XCTAssertNotNil(image.uuid)
    }

    func testCommandSizePastTheCommandAreaStopsTheWalk() throws {
        var b = MachOImageBuilder()
        b.commands = [b.command(0x1B, size: 4096) { w in w.raw(Array(repeating: 1, count: 16)) }]
        let image = try parseImage(b.build(trailing: Array(repeating: 0, count: 8192)))
        XCTAssertEqual(image.loadCommands, [])
        XCTAssertEqual(image.issues, [.badCommandSize(index: 0, fileOffset: 32, size: 4096)])
        XCTAssertNil(image.uuid)
    }

    /// `ncmds` of four billion with a few real commands: the walk ends with the bytes, at once.
    func testHugeCommandCountEndsWithTheBytes() throws {
        var b = MachOImageBuilder()
        b.commands = [b.command(0x99) { _ in }, b.command(0x98) { _ in }]
        b.declaredCount = .max
        let start = Date()
        let image = try parseImage(b.build())
        XCTAssertLessThan(Date().timeIntervalSince(start), 1)
        XCTAssertEqual(image.loadCommands.map(\.command), [0x99, 0x98])
        XCTAssertEqual(image.issues, [.commandsTruncated(declared: .max, read: 2)])
    }

    func testCommandsSizePastTheSliceIsClipped() throws {
        var b = MachOImageBuilder()
        b.commands = [b.command(0x99) { _ in }]
        b.declaredSize = 0x7FFF_FFFF
        let image = try parseImage(b.build())
        XCTAssertEqual(image.loadCommands.count, 1)
        XCTAssertEqual(image.issues, [.commandsExceedSlice(declared: 0x7FFF_FFFF, available: 8)])
    }

    func testSectionCountIsCappedByCommandSize() throws {
        var b = MachOImageBuilder()
        b.commands = [
            b.segment(
                "__TEXT", vmAddress: 0, vmSize: 0x100, fileOffset: 0, fileSize: 0x100,
                sections: [TestSection(name: "__text", segment: "__TEXT", address: 0, size: 4, offset: 0x40)],
                declaredSections: 1_000_000)
        ]
        let image = try parseImage(b.build())
        XCTAssertEqual(image.segments.first?.sections.map(\.name), ["__text"])
        XCTAssertEqual(image.issues, [.sectionsExceedCommand(index: 0, declared: 1_000_000, read: 1)])
    }

    func testStringOffsetOutsideTheCommandIsSkipped() throws {
        var b = MachOImageBuilder()
        b.commands = [b.dylib(0xC, "/usr/lib/libA.dylib", nameOffset: 4000), b.dylib(0xC, "/usr/lib/libB.dylib")]
        let image = try parseImage(b.build())
        XCTAssertEqual(image.dylibs.map(\.path), ["/usr/lib/libB.dylib"])
        XCTAssertEqual(image.issues, [.badStringOffset(index: 0)])
        XCTAssertEqual(image.loadCommands.count, 2)
    }

    func testStringWithoutTerminatorStopsAtTheCommandEnd() throws {
        var b = MachOImageBuilder()
        b.commands = [
            b.command(0x8000_001C) { w in
                w.u32(12)
                w.raw(Array("@rpath/abc".utf8))  // no NUL: the command ends right after the 'c'
            }
        ]
        let image = try parseImage(b.build(trailing: Array("XYZ\0".utf8)))
        XCTAssertEqual(image.rpaths, ["@rpath/abc"])
    }

    func testCommandsTooShortForTheirStructure() throws {
        var b = MachOImageBuilder()
        b.commands = [
            b.command(0x1B) { w in w.raw([1, 2, 3, 4]) },  // LC_UUID needs 24 bytes
            b.command(0x19) { w in w.name16("__TEXT") },  // LC_SEGMENT_64 needs 72
            b.command(0x2) { w in w.u32(0) },  // LC_SYMTAB needs 24
            b.command(0x8000_0028) { w in w.u64(0) },  // LC_MAIN needs 24
            b.command(0x32) { w in  // LC_BUILD_VERSION declaring 50 tools, holding 1
                w.u32(1)
                w.u32(0x000C_0000)
                w.u32(0x000D_0000)
                w.u32(50)
                w.u32(3)
                w.u32(0x0001_0000)
            },
        ]
        let image = try parseImage(b.build())
        XCTAssertEqual(image.loadCommands.count, 5)
        XCTAssertNil(image.uuid)
        XCTAssertEqual(image.segments, [])
        XCTAssertNil(image.symbolTable)
        XCTAssertNil(image.entryPoint)
        XCTAssertEqual(image.buildVersions.first?.tools, [MachOBuildTool(tool: 3, version: MachOVersion(rawValue: 0x0001_0000))])
        XCTAssertEqual(
            image.issues,
            [
                .commandTooSmall(index: 0, command: 0x1B), .commandTooSmall(index: 1, command: 0x19),
                .commandTooSmall(index: 2, command: 0x2),
                .commandTooSmall(index: 3, command: 0x8000_0028), .commandTooSmall(index: 4, command: 0x32),
            ])
    }

    func testCodeSignatureOutsideTheSliceIsNotSigned() throws {
        var b = MachOImageBuilder()
        b.commands = [
            b.command(0x1D) { w in
                w.u32(0x40)
                w.u32(0x1000)
            }
        ]
        let image = try parseImage(b.build(trailing: Array(repeating: 0, count: 64)))
        XCTAssertEqual(image.codeSignature, MachOCodeSignature(fileOffset: 0x40, size: 0x1000, isWithinSlice: false))
        XCTAssertFalse(image.isSigned)

        var inside = MachOImageBuilder()
        inside.commands = [
            inside.command(0x1D) { w in
                w.u32(0x30)
                w.u32(0x20)
            }
        ]
        let signed = try parseImage(inside.build(trailing: Array(repeating: 0, count: 64)))
        XCTAssertTrue(signed.isSigned)  // 0x30 + 0x20 = 80 bytes, inside the 112-byte file
    }

    // MARK: - Malformed symbol tables

    func testSymbolNameOutsideTheStringTableIsNil() throws {
        var b = MachOImageBuilder()
        b.commands = [b.symtab(symbolsOffset: 0, count: 0, stringsOffset: 0, stringsSize: 0)]
        let tables = UInt32(b.commandsEnd)
        b.commands = [b.symtab(symbolsOffset: tables, count: 3, stringsOffset: tables + 48, stringsSize: 8)]
        var t = b.writer()
        for strx: UInt32 in [1, 8, 0xFFFF_FFFF] {
            t.u32(strx)
            t.u8(0x0F)
            t.u8(1)
            t.u16(0)
            t.u64(0x10)
        }
        t.raw(Array("\0_inside".utf8))  // 8 bytes: index 8 is the first byte past the table
        t.raw(Array("_outside\0".utf8))
        let data = b.build(trailing: t.bytes)
        let image = try parseImage(data)
        let symbols = MachOParser.symbols(in: data, image: image).symbols
        XCTAssertEqual(symbols.map(\.name), ["_inside", nil, nil])
    }

    func testSymbolTablePastTheSliceIsTruncated() throws {
        var b = MachOImageBuilder()
        b.commands = [b.symtab(symbolsOffset: 0, count: 0, stringsOffset: 0, stringsSize: 0)]
        let tables = UInt32(b.commandsEnd)
        b.commands = [b.symtab(symbolsOffset: tables, count: 400_000_000, stringsOffset: 0, stringsSize: 0)]
        let data = b.build(trailing: Array(repeating: 0, count: 16 * 5 + 7))
        let image = try parseImage(data)
        let table = MachOParser.symbols(in: data, image: image)
        XCTAssertEqual(table.symbols.count, 5)
        XCTAssertEqual(table.declaredCount, 400_000_000)
        XCTAssertTrue(table.truncated)
        // Data that is not the image's file: nothing is read past its end.
        let short = MachOParser.symbols(in: data.prefix(40), image: image)
        XCTAssertEqual(short.symbols, [])
        XCTAssertTrue(short.truncated)
        XCTAssertEqual(MachOParser.symbols(in: data, image: try parseImage(MachOImageBuilder().build())), .empty)
    }

    // MARK: - Malformed universal headers

    private func fat(_ entries: [(cpu: UInt32, offset: UInt64, size: UInt64)], wide: Bool = false, declared: UInt32? = nil, length: Int)
        -> [UInt8]
    {
        var w = MachOBytes(bigEndian: true)
        w.u32(wide ? 0xCAFE_BABF : 0xCAFE_BABE)
        w.u32(declared ?? UInt32(entries.count))
        for entry in entries {
            w.u32(entry.cpu)
            w.u32(0)
            w.word(entry.offset, wide: wide)
            w.word(entry.size, wide: wide)
            w.u32(12)
            if wide { w.u32(0) }
        }
        return w.bytes + Array(repeating: 0, count: max(0, length - w.bytes.count))
    }

    func testUniversalSliceProblemsAreFlaggedNotFatal() throws {
        let thin = Array(try MachOFixture.data("hello-x86_64"))
        var bytes = fat(
            [(0x0100_0007, 4096, UInt64(thin.count)), (0x0100_000C, 1 << 40, 100), (0x0100_000C, 256, 64), (0x0100_0007, 4096, 1 << 33)],
            wide: true, length: 4096)
        bytes += thin
        let file = try XCTUnwrap(MachOParser.parse(Data(bytes)))
        XCTAssertTrue(file.isUniversal)
        XCTAssertEqual(file.slices.count, 4)
        XCTAssertNotNil(file.slices[0].image)
        XCTAssertNil(file.slices[1].image)
        XCTAssertNil(file.slices[2].image)
        XCTAssertNotNil(file.slices[3].image)  // truncated, but its image is all there
        XCTAssertEqual(
            file.issues,
            [.sliceOutOfBounds(slice: 1), .sliceNotMachO(slice: 2), .sliceTruncated(slice: 3, declared: 1 << 33, available: thin.count)])
        XCTAssertEqual(file.slices[3].image?.segments.map(\.name), ["__PAGEZERO", "__TEXT", "__DATA", "__LINKEDIT"])
        XCTAssertEqual(file.images.count, 2)
    }

    func testUniversalHeaderCounts() throws {
        // 0xCAFEBABE: 30 entries is a universal file, 31 is a Java class.
        XCTAssertEqual(MachOParser.parse(Data(fat([], declared: 30, length: 8 + 30 * 20)))?.slices.count, 30)
        XCTAssertNil(MachOParser.parse(Data(fat([], declared: 31, length: 8 + 31 * 20))))
        // 0xCAFEBABF has no Java ambiguity: a huge count is read up to the cap, and flagged.
        let wide = try XCTUnwrap(MachOParser.parse(Data(fat([], wide: true, declared: 1000, length: 8 + 1000 * 32))))
        XCTAssertTrue(wide.usesFat64)
        XCTAssertEqual(wide.slices.count, 30)
        XCTAssertEqual(wide.issues.first, .fatHeaderTruncated(declared: 1000, read: 30))
        // Entries that do not fit in the file.
        let short = try XCTUnwrap(MachOParser.parse(Data(fat([], declared: 3, length: 8 + 20 + 5))))
        XCTAssertEqual(short.slices.count, 1)
        XCTAssertEqual(short.issues.first, .fatHeaderTruncated(declared: 3, read: 1))
    }

    /// A slice at an offset near the top of the 64-bit range cannot overflow the absolute sum.
    func testHostileSegmentOffsetSaturates() throws {
        var b = MachOImageBuilder()
        b.commands = [b.segment("__TEXT", vmAddress: 0, vmSize: 0x10, fileOffset: .max - 2, fileSize: 0x10)]
        let thin = b.build()
        let bytes = fat([(0x0100_000C, 64, UInt64(thin.count))], wide: true, length: 64) + Array(thin)
        let image = try XCTUnwrap(MachOParser.parse(Data(bytes))?.images.first)
        XCTAssertEqual(image.segments.first?.fileOffset, .max)
        XCTAssertNil(image.fileOffset(forAddress: 0))
    }
}
