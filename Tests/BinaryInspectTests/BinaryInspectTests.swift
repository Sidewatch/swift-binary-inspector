//
//  BinaryInspectTests.swift
//  Tests for SwiftBinaryInspect
//
//  Created by David Sherlock on 7/18/26.
//

import XCTest
@testable import BinaryInspect

final class BinaryInspectTests: XCTestCase {

    // MARK: - HexDump

    func testHexDumpRows() {
        let data = Data((0..<20).map { UInt8($0) })
        let rows = HexDump.rows(of: data, bytesPerRow: 16)
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].offset, 0)
        XCTAssertEqual(rows[0].bytes.count, 16)
        XCTAssertEqual(rows[1].offset, 16)
        XCTAssertEqual(rows[1].bytes.count, 4)          // short final row
        XCTAssertEqual(rows[0].offsetColumn, "00000000")
        XCTAssertEqual(rows[0].hexBytes[0], "00")
        XCTAssertEqual(rows[0].hexBytes[15], "0f")
    }

    func testHexDumpAsciiGutter() {
        let data = Data("Hi\u{01}!".utf8)               // printable, control, printable
        let row = HexDump.rows(of: data)[0]
        XCTAssertEqual(row.asciiColumn, "Hi.!")         // control byte → '.'
    }

    func testHexDumpWindow() {
        let data = Data((0..<100).map { UInt8($0) })
        let rows = HexDump.rows(of: data, bytesPerRow: 8, from: 16, length: 8)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].offset, 16)
        XCTAssertEqual(rows[0].bytes, Array(16..<24).map { UInt8($0) })
    }

    func testHexDumpRenderAligns() {
        let out = HexDump.render(Data([0xDE, 0xAD]), bytesPerRow: 4)
        XCTAssertTrue(out.hasPrefix("00000000  de ad"), out)
        XCTAssertTrue(out.hasSuffix("|..|"), out)       // 0xDE/0xAD not printable
    }

    // Regression: rows/render subscripted with zero-based positions, trapping on a
    // Data slice that keeps its parent's non-zero indices.
    func testHexDumpHandlesDataSliceWithNonZeroStartIndex() {
        let parent = Data((0..<64).map { UInt8($0) })
        let slice = parent[16...]
        XCTAssertEqual(slice.startIndex, 16)
        let rows = HexDump.rows(of: slice, bytesPerRow: 16)
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[0].offset, 0)               // offsets are within the slice
        XCTAssertEqual(rows[0].bytes, Array(16..<32).map { UInt8($0) })
        XCTAssertEqual(rows[2].bytes, Array(48..<64).map { UInt8($0) })
        XCTAssertTrue(HexDump.render(slice).hasPrefix("00000000  10 11"), HexDump.render(slice))

        let windowed = HexDump.rows(of: slice, bytesPerRow: 8, from: 8, length: 8)
        XCTAssertEqual(windowed.count, 1)
        XCTAssertEqual(windowed[0].offset, 8)
        XCTAssertEqual(windowed[0].bytes, Array(24..<32).map { UInt8($0) })
    }

    // MARK: - MagicBytes

    func testMagicPNG() {
        let t = MagicBytes.identify(Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))
        XCTAssertEqual(t?.ext, "png")
        XCTAssertEqual(t?.category, .image)
    }

    func testMagicPDFandELF() {
        XCTAssertEqual(MagicBytes.identify(Data("%PDF-1.7".utf8))?.ext, "pdf")
        XCTAssertEqual(MagicBytes.identify(Data([0x7F, 0x45, 0x4C, 0x46]))?.category, .executable)
    }

    func testMagicCafebabeDisambiguation() {
        // count 2 ⇒ Mach-O universal
        let fat = Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])
        XCTAssertEqual(MagicBytes.identify(fat)?.name, "Mach-O universal binary")
        // major version 52 ⇒ Java class
        let java = Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x34])
        XCTAssertEqual(MagicBytes.identify(java)?.ext, "class")
    }

    func testMagicFixedOffsetSignatures() {
        var tar = Data(count: 262); tar.replaceSubrange(257..<262, with: [0x75, 0x73, 0x74, 0x61, 0x72])
        XCTAssertEqual(MagicBytes.identify(tar)?.ext, "tar")

        var wav = Data("RIFF".utf8); wav.append(Data([0, 0, 0, 0])); wav.append(Data("WAVE".utf8))
        XCTAssertEqual(MagicBytes.identify(wav)?.ext, "wav")
    }

    func testMagicUnknown() {
        XCTAssertNil(MagicBytes.identify(Data([0x12, 0x34, 0x56, 0x78])))
    }

    // MARK: - BinaryStrings

    func testStringsASCII() {
        var data = Data([0x00, 0x01])
        data.append(Data("hello".utf8))
        data.append(Data([0x00]))
        data.append(Data("hi".utf8))                    // too short at minLength 4
        let found = BinaryStrings.extract(from: data, minLength: 4)
        XCTAssertEqual(found.count, 1)
        XCTAssertEqual(found[0].value, "hello")
        XCTAssertEqual(found[0].offset, 2)
    }

    func testStringsUTF16LE() {
        // "OK" as UTF-16LE: 4F 00 4B 00
        let data = Data([0x4F, 0x00, 0x4B, 0x00])
        let found = BinaryStrings.extract(from: data, minLength: 2, encoding: .utf16LE)
        XCTAssertEqual(found.first?.value, "OK")
        XCTAssertEqual(found.first?.offset, 0)
    }

    // MARK: - Entropy

    func testEntropyBounds() {
        XCTAssertEqual(Entropy.shannon(Data(repeating: 0x41, count: 1000)), 0, accuracy: 1e-9)
        let allBytes = Data((0..<256).map { UInt8($0) })
        XCTAssertEqual(Entropy.shannon(allBytes), 8.0, accuracy: 1e-9)
        XCTAssertEqual(Entropy.shannon(Data()), 0)
    }

    func testEntropyBlocks() {
        let data = Data(repeating: 0, count: 300)
        let blocks = Entropy.blocks(data, blockSize: 256)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[1].length, 44)
        XCTAssertEqual(blocks[0].entropy, 0, accuracy: 1e-9)
    }

    // MARK: - ByteSearch

    func testSearchBytesAndString() {
        let data = Data("the cat sat on the mat".utf8)
        XCTAssertEqual(ByteSearch.findString("the", in: data), [0, 15])
        XCTAssertEqual(ByteSearch.findString("zzz", in: data), [])
    }

    func testSearchHex() {
        let data = Data([0xFF, 0xD8, 0xFF, 0x00, 0xFF, 0xD8])
        XCTAssertEqual(ByteSearch.findHex("ffd8", in: data), [0, 4])
        XCTAssertEqual(ByteSearch.findHex("FF D8", in: data), [0, 4])   // spaces + case
        XCTAssertNil(ByteSearch.findHex("fff", in: data))               // odd digits
        XCTAssertNil(ByteSearch.findHex("gg", in: data))                // non-hex
    }

    func testParseHex() {
        XCTAssertEqual(ByteSearch.parseHex("4d5a"), [0x4D, 0x5A])
        XCTAssertEqual(ByteSearch.parseHex(""), [])
    }

    // MARK: - BinaryFormat

    func testFormatELF() {
        let elf = Data([0x7F, 0x45, 0x4C, 0x46, 0x02, 0x01, 0x01, 0x00,
                        0, 0, 0, 0, 0, 0, 0, 0,
                        0x02, 0x00,          // e_type = EXEC (LE)
                        0x3E, 0x00])         // e_machine = x86-64 (LE)
        let info = BinaryFormat.parse(elf)
        XCTAssertEqual(info?.kind, .elf)
        XCTAssertEqual(info?.bits, 64)
        XCTAssertEqual(info?.endian, .little)
        XCTAssertEqual(info?.arch, "x86-64")
        XCTAssertEqual(info?.type, "executable")
    }

    func testFormatMachO64() {
        // CF FA ED FE (64-bit LE), cputype 0x0100000C (arm64), filetype 2 (EXECUTE)
        let macho = Data([0xCF, 0xFA, 0xED, 0xFE, 0x0C, 0x00, 0x00, 0x01,
                          0, 0, 0, 0, 0x02, 0x00, 0x00, 0x00])
        let info = BinaryFormat.parse(macho)
        XCTAssertEqual(info?.kind, .machO)
        XCTAssertEqual(info?.bits, 64)
        XCTAssertEqual(info?.arch, "ARM64")
        XCTAssertEqual(info?.type, "executable")
    }

    func testFormatMachOFat() {
        var fat = Data([0xCA, 0xFE, 0xBA, 0xBE, 0, 0, 0, 2])
        fat.append(Data([0x01, 0x00, 0x00, 0x0C] + [UInt8](repeating: 0, count: 16)))   // arm64 slice
        fat.append(Data([0x01, 0x00, 0x00, 0x07] + [UInt8](repeating: 0, count: 16)))   // x86-64 slice
        let info = BinaryFormat.parse(fat)
        XCTAssertEqual(info?.kind, .machOUniversal)
        XCTAssertEqual(info?.arch, "ARM64, x86-64")
    }

    func testFormatPE() {
        var pe = Data(count: 0x58)
        pe.replaceSubrange(0..<2, with: [0x4D, 0x5A])                       // MZ
        pe.replaceSubrange(0x3C..<0x40, with: [0x40, 0, 0, 0])              // e_lfanew = 0x40
        pe.replaceSubrange(0x40..<0x44, with: [0x50, 0x45, 0, 0])           // "PE\0\0"
        pe.replaceSubrange(0x44..<0x46, with: [0x64, 0x86])                 // machine x86-64
        pe.replaceSubrange(0x56..<0x58, with: [0x02, 0x00])                 // characteristics (exe, not DLL)
        let info = BinaryFormat.parse(pe)
        XCTAssertEqual(info?.kind, .pe)
        XCTAssertEqual(info?.arch, "x86-64")
        XCTAssertEqual(info?.bits, 64)
        XCTAssertEqual(info?.type, "executable")
    }

    func testFormatJavaAndWASM() {
        let java = BinaryFormat.parse(Data([0xCA, 0xFE, 0xBA, 0xBE, 0x00, 0x00, 0x00, 0x34]))
        XCTAssertEqual(java?.kind, .java)
        XCTAssertEqual(java?.type, "class file")

        let wasm = BinaryFormat.parse(Data([0x00, 0x61, 0x73, 0x6D, 0x01, 0x00, 0x00, 0x00]))
        XCTAssertEqual(wasm?.kind, .wasm)
    }

    func testFormatUnknownReturnsNil() {
        XCTAssertNil(BinaryFormat.parse(Data([0x00, 0x00, 0x00, 0x00])))
    }
}
