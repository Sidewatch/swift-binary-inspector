//
//  MachOParserTests.swift
//  BinaryInspectorTests
//
//  Tests for `MachOParser` over the checked-in fixtures. Every expected value was read from
//  these exact files with otool -h / -l / -L / -fv and nm -ap --no-dyldinfo.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import BinaryInspector

/// Tests for `MachOParser` over the checked-in fixtures: headers, load commands, segments and
/// sections, dylibs, platform, signature, symbols, and universal files with absolute offsets.
final class MachOParserTests: XCTestCase {

    private func thinImage(_ name: String) throws -> (Data, MachOImage) {
        let data = try MachOFixture.data(name)
        let file = try XCTUnwrap(MachOParser.parse(data))
        XCTAssertFalse(file.isUniversal)
        XCTAssertEqual(file.slices.count, 1)
        return (data, try XCTUnwrap(file.slices.first?.image))
    }

    // MARK: - Thin arm64 executable

    func testArm64ExecutableHeader() throws {
        let data = try MachOFixture.data("hello-arm64")
        let file = try XCTUnwrap(MachOParser.parse(data))
        let slice = try XCTUnwrap(file.slices.first)
        XCTAssertEqual(slice.offset, 0)
        XCTAssertEqual(slice.size, 50328)
        XCTAssertEqual(slice.architectureName, "arm64")
        let image = try XCTUnwrap(slice.image)
        XCTAssertEqual(image.sliceRange, 0..<50328)
        XCTAssertTrue(image.is64Bit)
        XCTAssertFalse(image.isBigEndian)
        XCTAssertEqual(image.cpuType, 16_777_228)
        XCTAssertEqual(image.cpuSubtype, 0)
        XCTAssertEqual(image.fileType, 2)
        XCTAssertEqual(image.commandCount, 18)
        XCTAssertEqual(image.commandsSize, 1288)
        XCTAssertEqual(image.flags, 0x0020_0085)
        XCTAssertEqual(image.issues, [])
    }

    func testArm64ExecutableLoadCommands() throws {
        let (_, image) = try thinImage("hello-arm64")
        XCTAssertEqual(
            image.loadCommands.map(\.name),
            [
                "LC_SEGMENT_64", "LC_SEGMENT_64", "LC_SEGMENT_64", "LC_SEGMENT_64", "LC_SEGMENT_64", "LC_DYLD_CHAINED_FIXUPS",
                "LC_DYLD_EXPORTS_TRIE", "LC_SYMTAB", "LC_DYSYMTAB", "LC_LOAD_DYLINKER", "LC_UUID", "LC_BUILD_VERSION",
                "LC_SOURCE_VERSION", "LC_MAIN", "LC_LOAD_DYLIB", "LC_FUNCTION_STARTS", "LC_DATA_IN_CODE", "LC_CODE_SIGNATURE",
            ])
        XCTAssertEqual(image.loadCommands.map(\.size), [72, 392, 152, 232, 72, 16, 16, 24, 80, 32, 24, 32, 16, 24, 56, 16, 16, 16])
        XCTAssertEqual(image.loadCommands.map(\.index), Array(0..<18))
        // Commands follow the 32-byte header back to back.
        var offset = 32
        for command in image.loadCommands {
            XCTAssertEqual(command.fileOffset, offset, command.name)
            offset += Int(command.size)
        }
        XCTAssertEqual(image.loadCommands[13].command, 0x8000_0028)
        XCTAssertTrue(image.loadCommands[13].requiresDyld)
        XCTAssertFalse(image.loadCommands[0].requiresDyld)
    }

    func testArm64ExecutableSegmentsAndSections() throws {
        let (_, image) = try thinImage("hello-arm64")
        XCTAssertEqual(image.segments.map(\.name), ["__PAGEZERO", "__TEXT", "__DATA_CONST", "__DATA", "__LINKEDIT"])
        XCTAssertEqual(image.segments.map(\.vmAddress), [0, 0x1_0000_0000, 0x1_0000_4000, 0x1_0000_8000, 0x1_0001_C000])
        XCTAssertEqual(image.segments.map(\.vmSize), [0x1_0000_0000, 0x4000, 0x4000, 0x14000, 0x4000])
        XCTAssertEqual(image.segments.map(\.fileOffset), [0, 0, 16384, 32768, 49152])
        XCTAssertEqual(image.segments.map(\.fileSize), [0, 16384, 16384, 16384, 1176])
        XCTAssertEqual(image.segments.map(\.maxProtection), [0, 5, 3, 3, 1])
        XCTAssertEqual(image.segments.map(\.initialProtection), [0, 5, 3, 3, 1])
        XCTAssertEqual(image.segments.map(\.flags), [0, 0, 0x10, 0, 0])
        XCTAssertEqual(image.segments.map(\.sections.count), [0, 4, 1, 2, 0])

        let text = image.segments[1].sections
        XCTAssertEqual(text.map(\.name), ["__text", "__stubs", "__cstring", "__unwind_info"])
        XCTAssertEqual(text.map(\.address), [0x1_0000_0548, 0x1_0000_05B0, 0x1_0000_05BC, 0x1_0000_05C4])
        XCTAssertEqual(text.map(\.size), [0x68, 0xC, 0x7, 0x60])
        XCTAssertEqual(text.map(\.fileOffset), [1352, 1456, 1468, 1476])
        XCTAssertEqual(text.map(\.alignment), [2, 2, 0, 2])
        XCTAssertEqual(text.map(\.flags), [0x8000_0400, 0x8000_0408, 0x2, 0])
        XCTAssertEqual(text.map(\.segmentName), ["__TEXT", "__TEXT", "__TEXT", "__TEXT"])
        XCTAssertEqual(text[2].type, 2)  // S_CSTRING_LITERALS

        let common = image.segments[3].sections[1]
        XCTAssertEqual(common.name, "__common")
        XCTAssertEqual(common.address, 0x1_0000_8010)
        XCTAssertEqual(common.size, 0x10000)
        XCTAssertNil(common.fileOffset)  // offset 0: zero-fill
        XCTAssertEqual(common.alignment, 4)
        XCTAssertEqual(common.type, 1)
        XCTAssertTrue(common.isZeroFill)
        XCTAssertFalse(image.segments[3].sections[0].isZeroFill)
    }

    func testArm64ExecutableIdentityPlatformEntryAndSignature() throws {
        let (_, image) = try thinImage("hello-arm64")
        XCTAssertEqual(image.uuid, UUID(uuidString: "86D328AB-4029-3AD9-A88D-AB318D983FD1"))
        XCTAssertEqual(image.buildVersions.count, 1)
        let build = try XCTUnwrap(image.buildVersions.first)
        XCTAssertEqual(build.command, 0x32)
        XCTAssertEqual(build.platform, 1)
        XCTAssertEqual(build.minimumOS.description, "12.0.0")
        XCTAssertEqual(build.sdk.description, "27.0.0")
        XCTAssertEqual(build.tools, [MachOBuildTool(tool: 3, version: MachOVersion(rawValue: 0x699D_0100))])
        XCTAssertEqual(build.tools.first?.version.description, "27037.1.0")
        XCTAssertEqual(image.entryPoint, MachOEntryPoint(fileOffset: 1352, stackSize: 0))
        XCTAssertEqual(image.codeSignature, MachOCodeSignature(fileOffset: 49792, size: 536, isWithinSlice: true))
        XCTAssertTrue(image.isSigned)
        XCTAssertNil(image.encryption)
        XCTAssertEqual(
            image.symbolTable, MachOSymbolTableLocation(symbolsOffset: 49336, symbolCount: 21, stringsOffset: 49680, stringsSize: 104))
        XCTAssertEqual(
            image.dylibs,
            [
                MachODylib(
                    kind: .load, path: "/usr/lib/libSystem.B.dylib", currentVersion: MachOVersion(rawValue: 0x054F_0000),
                    compatibilityVersion: MachOVersion(rawValue: 0x0001_0000), timestamp: 2)
            ])
        XCTAssertEqual(image.dylibs.first?.currentVersion.description, "1359.0.0")
        XCTAssertNil(image.installName)
        XCTAssertEqual(image.rpaths, [])
    }

    func testArm64ExecutableSymbols() throws {
        let (data, image) = try thinImage("hello-arm64")
        let table = MachOParser.symbols(in: data, image: image)
        XCTAssertEqual(table.declaredCount, 21)
        XCTAssertFalse(table.truncated)
        let symbols = table.symbols
        XCTAssertEqual(
            symbols.map(\.name),
            [
                "_twice", "", "/fixtures/", "hello.c", "hello-arm64.o", "", "_main", "", "", "", "_twice", "", "", "_counter", "_scratch",
                "", "__mh_execute_header", "_counter", "_main", "_scratch", "_printf",
            ])
        XCTAssertEqual(
            symbols.map(\.value),
            [
                0x1_0000_05A8, 0, 0, 0, 0, 0x1_0000_0548, 0x1_0000_0548, 0x60, 0x1_0000_0548, 0x1_0000_05A8, 0x1_0000_05A8, 0x8,
                0x1_0000_05A8, 0, 0, 0, 0x1_0000_0000, 0x1_0000_8000, 0x1_0000_0548, 0x1_0000_8010, 0,
            ])
        XCTAssertEqual(symbols.map(\.isDebug), [false] + Array(repeating: true, count: 15) + Array(repeating: false, count: 5))
        // Stab codes: SO 0x64, OSO 0x66, BNSYM 0x2E, FUN 0x24, ENSYM 0x4E, GSYM 0x20.
        XCTAssertEqual(
            symbols[1...15].map(\.type), [0x64, 0x64, 0x64, 0x66, 0x2E, 0x24, 0x24, 0x4E, 0x2E, 0x24, 0x24, 0x4E, 0x20, 0x20, 0x64])
        XCTAssertEqual(symbols[4].descriptor, 1)  // nm: OSO "03 0001" -> desc 1
        XCTAssertEqual(symbols[1].sectionNumber, 1)
        XCTAssertTrue(symbols[1...15].allSatisfy { $0.kind == nil && !$0.isExternal })

        XCTAssertEqual(symbols[0].kind, .section)  // t _twice
        XCTAssertFalse(symbols[0].isExternal)
        XCTAssertEqual(symbols[0].sectionNumber, 1)
        XCTAssertEqual(symbols[16].kind, .section)  // T __mh_execute_header
        XCTAssertTrue(symbols[16].isExternal)
        XCTAssertEqual(symbols[17].sectionNumber, 6)  // D _counter in __DATA,__data (6th section)
        XCTAssertEqual(symbols[19].sectionNumber, 7)  // S _scratch in __DATA,__common
        XCTAssertEqual(symbols[20].kind, .undefined)  // U _printf
        XCTAssertTrue(symbols[20].isExternal)
        XCTAssertEqual(symbols[20].sectionNumber, 0)
        XCTAssertFalse(symbols.contains { $0.isPrivateExternal })
    }

    func testSymbolLimitTruncates() throws {
        let (data, image) = try thinImage("hello-arm64")
        let table = MachOParser.symbols(in: data, image: image, limit: 3)
        XCTAssertEqual(table.symbols.map(\.name), ["_twice", "", "/fixtures/"])
        XCTAssertEqual(table.declaredCount, 21)
        XCTAssertTrue(table.truncated)
        XCTAssertEqual(MachOParser.symbols(in: data, image: image, limit: -5).symbols, [])
        XCTAssertEqual(MachOParser.symbols(in: data, image: image, limit: 21).truncated, false)
    }

    // MARK: - Thin x86_64 executable

    func testX86_64ExecutableWithVersionMinAndNoSignature() throws {
        let (data, image) = try thinImage("hello-x86_64")
        XCTAssertEqual(image.architectureName, "x86_64")
        XCTAssertEqual(image.cpuType, 16_777_223)
        XCTAssertEqual(image.cpuSubtype, 3)
        XCTAssertEqual(image.commandCount, 15)
        XCTAssertEqual(image.commandsSize, 1360)
        XCTAssertEqual(image.loadCommands[4].name, "LC_DYLD_INFO_ONLY")
        XCTAssertEqual(image.loadCommands[9].name, "LC_VERSION_MIN_MACOSX")
        XCTAssertEqual(
            image.buildVersions,
            [
                MachOBuildVersion(
                    command: 0x24, platform: 1, minimumOS: MachOVersion(rawValue: 0x000A_0D00), sdk: MachOVersion(rawValue: 0x001B_0000),
                    tools: [])
            ])
        XCTAssertEqual(image.uuid, UUID(uuidString: "7CEB6850-D602-3E4B-A7A7-0609FD7C7298"))
        XCTAssertNil(image.codeSignature)
        XCTAssertFalse(image.isSigned)
        XCTAssertEqual(image.entryPoint?.fileOffset, 1440)
        XCTAssertEqual(image.segments.map(\.name), ["__PAGEZERO", "__TEXT", "__DATA", "__LINKEDIT"])
        XCTAssertEqual(image.segments[2].sections.map(\.name), ["__la_symbol_ptr", "__data", "__got", "__common"])
        let symbols = MachOParser.symbols(in: data, image: image).symbols
        XCTAssertEqual(symbols.count, 23)
        XCTAssertEqual(symbols.suffix(2).map(\.name), ["_printf", "dyld_stub_binder"])
        XCTAssertEqual(symbols[1].name, "__dyld_private")
        XCTAssertEqual(symbols[1].value, 0x1_0000_1010)
    }

    // MARK: - Universal

    func testUniversalSlices() throws {
        for (name, fat64) in [("hello-universal", false), ("hello-universal-fat64", true)] {
            let data = try MachOFixture.data(name)
            let file = try XCTUnwrap(MachOParser.parse(data))
            XCTAssertTrue(file.isUniversal, name)
            XCTAssertEqual(file.usesFat64, fat64, name)
            XCTAssertEqual(file.issues, [], name)
            XCTAssertEqual(file.slices.map(\.architectureName), ["x86_64", "arm64"], name)
            XCTAssertEqual(file.slices.map(\.cpuType), [0x0100_0007, 0x0100_000C], name)
            XCTAssertEqual(file.slices.map(\.cpuSubtype), [3, 0], name)
            XCTAssertEqual(file.slices.map(\.offset), [4096, 16384], name)
            XCTAssertEqual(file.slices.map(\.size), [8848, 50328], name)
            XCTAssertEqual(file.slices.map(\.alignment), [12, 14], name)
            XCTAssertEqual(file.slices.map(\.index), [0, 1], name)
            XCTAssertEqual(file.images.map(\.sliceRange), [4096..<12944, 16384..<66712], name)
        }
    }

    /// Each slice's image is the thin file's image with every file offset moved by the slice
    /// offset — and those absolute offsets index the universal file's bytes directly.
    func testUniversalOffsetsAreAbsolute() throws {
        let data = try MachOFixture.data("hello-universal")
        let file = try XCTUnwrap(MachOParser.parse(data))
        for (index, thinName) in ["hello-x86_64", "hello-arm64"].enumerated() {
            let (thinData, thin) = try thinImage(thinName)
            let image = try XCTUnwrap(file.slices[index].image)
            let shift = image.sliceRange.lowerBound
            let shift64 = UInt64(shift)
            XCTAssertEqual(image.loadCommands.map(\.fileOffset), thin.loadCommands.map { $0.fileOffset + shift }, thinName)
            XCTAssertEqual(image.segments.map(\.fileOffset), thin.segments.map { $0.fileOffset + shift64 }, thinName)
            XCTAssertEqual(
                image.segments.flatMap(\.sections).map(\.fileOffset),
                thin.segments.flatMap(\.sections).map { $0.fileOffset.map { $0 + shift64 } }, thinName)
            XCTAssertEqual(image.entryPoint?.fileOffset, thin.entryPoint.map { $0.fileOffset + shift64 }, thinName)
            XCTAssertEqual(image.codeSignature?.fileOffset, thin.codeSignature.map { $0.fileOffset + shift64 }, thinName)
            XCTAssertEqual(image.codeSignature?.isWithinSlice, thin.codeSignature?.isWithinSlice, thinName)
            XCTAssertEqual(image.symbolTable?.symbolsOffset, thin.symbolTable.map { $0.symbolsOffset + shift64 }, thinName)
            XCTAssertEqual(image.symbolTable?.stringsOffset, thin.symbolTable.map { $0.stringsOffset + shift64 }, thinName)
            XCTAssertEqual(image.uuid, thin.uuid, thinName)
            XCTAssertEqual(image.segments.map(\.vmAddress), thin.segments.map(\.vmAddress), thinName)
            // The bytes at each absolute command offset are that command's cmd value.
            for command in image.loadCommands {
                let cmd = data.subdata(in: command.fileOffset..<(command.fileOffset + 4)).withUnsafeBytes {
                    $0.loadUnaligned(as: UInt32.self)
                }
                XCTAssertEqual(UInt32(littleEndian: cmd), command.command, thinName)
            }
            XCTAssertEqual(
                MachOParser.symbols(in: data, image: image), MachOParser.symbols(in: thinData, image: thin), "\(thinName) symbols")
        }
    }

    // MARK: - Dylib, bundle, object

    func testDylibInstallNameRpathAndLinkKinds() throws {
        let (data, image) = try thinImage("libgreeter.dylib")
        XCTAssertEqual(image.fileType, 6)
        XCTAssertEqual(
            image.installName,
            MachODylib(
                kind: .id, path: "@rpath/libgreeter.dylib", currentVersion: MachOVersion(rawValue: 0x0002_0304),
                compatibilityVersion: MachOVersion(rawValue: 0x0002_0000), timestamp: 1))
        XCTAssertEqual(image.installName?.currentVersion.description, "2.3.4")
        XCTAssertEqual(image.installName?.compatibilityVersion.description, "2.0.0")
        XCTAssertEqual(image.dylibs.map(\.kind), [.weak, .reexport, .upward, .load])
        XCTAssertEqual(
            image.dylibs.map(\.path),
            ["/usr/lib/libz.1.dylib", "/usr/lib/libc++.1.dylib", "/usr/lib/libobjc.A.dylib", "/usr/lib/libSystem.B.dylib"])
        XCTAssertEqual(image.dylibs.map(\.currentVersion.description), ["1.2.12", "2200.27.0", "228.0.0", "1359.0.0"])
        XCTAssertEqual(image.dylibs.map(\.compatibilityVersion.description), ["1.0.0", "1.0.0", "1.0.0", "1.0.0"])
        XCTAssertEqual(image.rpaths, ["@loader_path/../lib"])
        XCTAssertNil(image.entryPoint)
        XCTAssertEqual(image.codeSignature, MachOCodeSignature(fileOffset: 33008, size: 416, isWithinSlice: true))
        XCTAssertEqual(image.uuid, UUID(uuidString: "505ED90C-A27E-37AB-B2DB-AD2C906389C2"))
        let symbols = MachOParser.symbols(in: data, image: image).symbols
        XCTAssertEqual(symbols.map(\.name), ["_checksum", "_greeting", "_adler32"])
        XCTAssertEqual(symbols.map(\.value), [0x4E4, 0x4D8, 0])
        XCTAssertEqual(symbols.map(\.kind), [.section, .section, .undefined])
    }

    func testBundle() throws {
        let (data, image) = try thinImage("plugin.bundle")
        XCTAssertEqual(image.fileType, 8)
        XCTAssertEqual(image.commandCount, 13)
        XCTAssertEqual(image.commandsSize, 616)
        XCTAssertNil(image.entryPoint)
        XCTAssertNil(image.installName)
        XCTAssertTrue(image.isSigned)
        XCTAssertEqual(image.segments.map(\.name), ["__TEXT", "__LINKEDIT"])
        XCTAssertEqual(image.uuid, UUID(uuidString: "66FB421B-7054-322F-842D-C7DE702625CA"))
        let symbols = MachOParser.symbols(in: data, image: image).symbols
        XCTAssertEqual(symbols.map(\.name), ["_plugin_version"])
        XCTAssertEqual(symbols.map(\.value), [0x2A8])
    }

    func testObjectFile() throws {
        let (data, image) = try thinImage("plugin.o")
        XCTAssertEqual(image.fileType, 1)
        XCTAssertEqual(image.commandCount, 4)
        XCTAssertEqual(image.commandsSize, 360)
        XCTAssertEqual(image.flags, 0x2000)
        XCTAssertEqual(image.loadCommands.map(\.name), ["LC_SEGMENT_64", "LC_BUILD_VERSION", "LC_SYMTAB", "LC_DYSYMTAB"])
        let segment = try XCTUnwrap(image.segments.first)
        XCTAssertEqual(segment.name, "")
        XCTAssertEqual(segment.vmAddress, 0)
        XCTAssertEqual(segment.vmSize, 0x28)
        XCTAssertEqual(segment.fileOffset, 392)
        XCTAssertEqual(segment.fileSize, 40)
        XCTAssertEqual(segment.sections.map(\.name), ["__text", "__compact_unwind"])
        XCTAssertEqual(segment.sections.map(\.segmentName), ["__TEXT", "__LD"])
        XCTAssertEqual(segment.sections.map(\.address), [0, 8])
        XCTAssertEqual(segment.sections.map(\.size), [8, 0x20])
        XCTAssertEqual(segment.sections.map(\.fileOffset), [392, 400])
        XCTAssertEqual(image.buildVersions.first?.tools, [])
        XCTAssertNil(image.uuid)
        XCTAssertNil(image.codeSignature)
        XCTAssertFalse(image.isSigned)
        let symbols = MachOParser.symbols(in: data, image: image).symbols
        XCTAssertEqual(symbols.map(\.name), ["ltmp0", "ltmp1", "_plugin_version"])
        XCTAssertEqual(symbols.map(\.value), [0, 8, 0])
        XCTAssertEqual(symbols.map(\.isExternal), [false, false, true])
        XCTAssertEqual(symbols.map(\.sectionNumber), [1, 2, 1])
    }

    // MARK: - 32-bit images (real compiler and linker output)

    func testWatchArm64_32ExecutableIsALinked32BitImage() throws {
        let (data, image) = try thinImage("hello-arm64_32")
        XCTAssertFalse(image.is64Bit, "MH_MAGIC: the 32-bit header, LC_SEGMENT and 32-bit nlist")
        XCTAssertFalse(image.isBigEndian)
        XCTAssertEqual(image.cpuType, 0x0200_000C)
        XCTAssertEqual(image.cpuSubtype, 1)
        XCTAssertEqual(image.architectureName, "arm64_32")
        XCTAssertEqual(image.fileType, 2)
        XCTAssertEqual(image.commandCount, 18)
        XCTAssertEqual(image.commandsSize, 1120)
        XCTAssertEqual(image.flags, 0x0020_0085)
        XCTAssertEqual(image.loadCommands.filter { $0.command == 0x1 }.count, 5, "five LC_SEGMENT, not LC_SEGMENT_64")
        XCTAssertEqual(image.segments.map(\.name), ["__PAGEZERO", "__TEXT", "__DATA_CONST", "__DATA", "__LINKEDIT"])
        XCTAssertEqual(image.segments.map(\.vmAddress), [0, 0x4000, 0xC000, 0x10000, 0x24000])
        XCTAssertEqual(image.segments.map(\.vmSize), [0x4000, 0x8000, 0x4000, 0x14000, 0x4000])
        XCTAssertEqual(image.segments.map(\.fileOffset), [0, 0, 32768, 49152, 65536])
        XCTAssertEqual(image.segments.map(\.fileSize), [0, 32768, 16384, 16384, 328])
        XCTAssertEqual(image.buildVersions.first?.platform, 4, "watchOS")
        XCTAssertEqual(image.buildVersions.first?.minimumOS.description, "8.0.0")
        let symbols = MachOParser.symbols(in: data, image: image).symbols
        XCTAssertEqual(symbols.count, 6)
        let byName = Dictionary(symbols.compactMap { s in s.name.map { ($0, s.value) } }, uniquingKeysWith: { a, _ in a })
        XCTAssertEqual(byName["_main"], 0x8000)
        XCTAssertEqual(byName["_twice"], 0x8060)
        XCTAssertEqual(byName["_counter"], 0x10000)
        XCTAssertEqual(byName["_scratch"], 0x10010)
        XCTAssertEqual(byName["__mh_execute_header"], 0x4000)
        XCTAssertEqual(symbols.first { $0.name == "_printf" }?.kind, .undefined)
        // A 32-bit address maps through the 32-bit segments: _main's bytes, and none for zero-fill.
        XCTAssertEqual(image.fileOffset(forAddress: 0x8000), 0x4000)
        XCTAssertNil(image.fileOffset(forAddress: 0x20000), "past __DATA's file-backed part")
    }

    func testI386AndArmv7ObjectsAre32Bit() throws {
        let (_, i386) = try thinImage("plugin-i386.o")
        XCTAssertFalse(i386.is64Bit)
        XCTAssertEqual(i386.cpuType, 7)
        XCTAssertEqual(i386.cpuSubtype, 3)
        XCTAssertEqual(i386.architectureName, "i386")
        XCTAssertEqual(i386.fileType, 1)
        XCTAssertEqual(i386.commandCount, 4)
        XCTAssertEqual(i386.commandsSize, 380)
        let i386Sections = try XCTUnwrap(i386.segments.first?.sections)
        XCTAssertEqual(i386Sections.map(\.name), ["__text", "__compact_unwind", "__eh_frame"])
        XCTAssertEqual(i386Sections.map(\.address), [0, 0xC, 0x20])
        XCTAssertEqual(i386Sections.map(\.size), [0xA, 0x14, 0x34])
        XCTAssertEqual(i386Sections.map(\.fileOffset), [408, 420, 440])

        let (_, armv7) = try thinImage("plugin-armv7.o")
        XCTAssertFalse(armv7.is64Bit)
        XCTAssertEqual(armv7.cpuType, 12)
        XCTAssertEqual(armv7.cpuSubtype, 9)
        XCTAssertEqual(armv7.architectureName, "armv7")
        XCTAssertEqual(armv7.commandsSize, 244)
        let armSections = try XCTUnwrap(armv7.segments.first?.sections)
        XCTAssertEqual(armSections.map(\.name), ["__text"])
        XCTAssertEqual(armSections.map(\.size), [4])
        XCTAssertEqual(armSections.map(\.fileOffset), [272])
    }

    // MARK: - Encryption (a real LC_ENCRYPTION_INFO_64 from the linker)

    func testEncryptionInfoFromTheLinkerAndAsFairPlayLeavesIt() throws {
        let (_, linked) = try thinImage("hello-ios")
        let info = try XCTUnwrap(linked.encryption, "-encryptable adds LC_ENCRYPTION_INFO_64")
        XCTAssertEqual(info.fileOffset, 16384)
        XCTAssertEqual(info.size, 16384)
        XCTAssertEqual(info.cryptID, 0)
        XCTAssertFalse(info.isEncrypted)
        XCTAssertEqual(linked.buildVersions.first?.platform, 2, "iOS")
        XCTAssertEqual(linked.buildVersions.first?.minimumOS.description, "15.0.0")

        let (_, encrypted) = try thinImage("hello-ios-encrypted")
        XCTAssertEqual(encrypted.encryption?.cryptID, 1)
        XCTAssertEqual(encrypted.encryption?.isEncrypted, true)
        XCTAssertEqual(encrypted.encryption?.fileOffset, 16384)
    }

    // MARK: - Not Mach-O

    func testNonMachOReturnsNil() throws {
        XCTAssertNil(MachOParser.parse(Data()))
        XCTAssertNil(MachOParser.parse(Data([0xCF, 0xFA, 0xED])))
        XCTAssertNil(MachOParser.parse(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])))  // PNG
        XCTAssertNil(MachOParser.parse(Data([0x7F, 0x45, 0x4C, 0x46, 2, 1, 1, 0] + [UInt8](repeating: 0, count: 56))))  // ELF
        // A Java class: 0xCAFEBABE, minor 0, major 52 -> "52 slices", over the 30 cap.
        XCTAssertNil(MachOParser.parse(Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x34] + [UInt8](repeating: 0, count: 64))))
        // A thin magic whose header is cut short.
        let hello = try MachOFixture.data("hello-arm64")
        XCTAssertNil(MachOParser.parse(hello.prefix(31)))
        XCTAssertNotNil(MachOParser.parse(hello.prefix(32)))
    }

    /// A `Data` slice keeps its parent's indices; offsets must still be relative to the slice.
    func testDataSliceWithNonZeroStartIndex() throws {
        let hello = try MachOFixture.data("hello-arm64")
        let padded = Data(repeating: 0xEE, count: 7) + hello
        let slice = padded[7...]
        XCTAssertEqual(slice.startIndex, 7)
        let image = try XCTUnwrap(MachOParser.parse(slice)?.images.first)
        XCTAssertEqual(image.sliceRange, 0..<50328)
        XCTAssertEqual(MachOParser.symbols(in: slice, image: image).symbols.count, 21)
    }
}
