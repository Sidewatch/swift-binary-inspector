//
//  MachOImageAddressesTests.swift
//  BinaryInspectorTests
//
//  Tests for MachOImage's address <-> file offset mapping and segment/section lookups:
//  file-backed parts only, zero-fill tails, addresses outside every segment, universal slices.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import BinaryInspector

/// Tests for `MachOImage`'s address and file-offset mapping. Layout of hello-arm64 (otool -l):
/// `__TEXT` 0x100000000 +0x4000 at file 0 (0x4000 bytes); `__DATA` 0x100008000 +0x14000 at file
/// 32768 with only 0x4000 file bytes; `__LINKEDIT` 0x10001C000 +0x4000 at file 49152 with 1176
/// file bytes; `__PAGEZERO` 0 +4 GiB with no file bytes.
final class MachOImageAddressesTests: XCTestCase {

    private func image(_ name: String, slice: Int = 0) throws -> MachOImage {
        try XCTUnwrap(MachOParser.parse(try MachOFixture.data(name))?.slices[slice].image)
    }

    func testAddressToFileOffsetInFileBackedSegments() throws {
        let image = try image("hello-arm64")
        XCTAssertEqual(image.fileOffset(forAddress: 0x1_0000_0548), 1352)  // __text
        XCTAssertEqual(image.fileOffset(forAddress: 0x1_0000_0000), 0)  // the header is in __TEXT
        XCTAssertEqual(image.fileOffset(forAddress: 0x1_0000_4000), 16384)  // __DATA_CONST
        XCTAssertEqual(image.fileOffset(forAddress: 0x1_0000_8000), 32768)  // __data
        XCTAssertEqual(image.fileOffset(forAddress: 0x1_0001_C000 + 1175), 49152 + 1175)  // last __LINKEDIT file byte
    }

    func testZeroFillTailHasNoFileOffset() throws {
        let image = try image("hello-arm64")
        XCTAssertEqual(image.fileOffset(forAddress: 0x1_0000_BFFF), 49151)  // last file-backed byte of __DATA
        XCTAssertNil(image.fileOffset(forAddress: 0x1_0000_C000))  // first zero-fill byte (vmsize > filesize)
        XCTAssertNil(image.fileOffset(forAddress: 0x1_0001_BFFF))  // last byte of __DATA's memory
        XCTAssertNil(image.fileOffset(forAddress: 0x1_0001_C000 + 1176))  // __LINKEDIT past its filesize
        // ...but the address still belongs to the segment and section.
        XCTAssertEqual(image.segment(containingAddress: 0x1_0000_C000)?.name, "__DATA")
        XCTAssertEqual(image.section(containingAddress: 0x1_0000_C000)?.name, "__common")
        XCTAssertEqual(image.segment(containingAddress: 0x1_0001_BFFF)?.name, "__DATA")
    }

    func testAddressOutsideEverySegment() throws {
        let image = try image("hello-arm64")
        for address: UInt64 in [0x1_0002_0000, 0x2_0000_0000, .max] {
            XCTAssertNil(image.fileOffset(forAddress: address), "\(address)")
            XCTAssertNil(image.segment(containingAddress: address), "\(address)")
            XCTAssertNil(image.section(containingAddress: address), "\(address)")
        }
        // __PAGEZERO holds the address but has no file bytes.
        XCTAssertNil(image.fileOffset(forAddress: 0x1000))
        XCTAssertEqual(image.segment(containingAddress: 0x1000)?.name, "__PAGEZERO")
        XCTAssertNil(image.section(containingAddress: 0x1000))
    }

    func testFileOffsetToAddress() throws {
        let image = try image("hello-arm64")
        XCTAssertEqual(image.address(forFileOffset: 0), 0x1_0000_0000)  // __TEXT, not the empty __PAGEZERO
        XCTAssertEqual(image.address(forFileOffset: 1352), 0x1_0000_0548)
        XCTAssertEqual(image.address(forFileOffset: 32768), 0x1_0000_8000)
        XCTAssertEqual(image.address(forFileOffset: 50327), 0x1_0001_C000 + 1175)
        XCTAssertNil(image.address(forFileOffset: 50328))  // one past the end of the file
        XCTAssertNil(image.address(forFileOffset: -1))
        XCTAssertEqual(image.segment(containingFileOffset: 16384)?.name, "__DATA_CONST")
        XCTAssertEqual(image.segment(containingFileOffset: 16383)?.name, "__TEXT")
        XCTAssertEqual(image.section(containingFileOffset: 1352)?.name, "__text")
        XCTAssertEqual(image.section(containingFileOffset: 1455)?.name, "__text")
        XCTAssertEqual(image.section(containingFileOffset: 1456)?.name, "__stubs")
        // In __DATA's file bytes but past __data's 4 bytes: a segment, no section (__common is zero-fill).
        XCTAssertEqual(image.segment(containingFileOffset: 32784)?.name, "__DATA")
        XCTAssertNil(image.section(containingFileOffset: 32784))
        XCTAssertNil(image.segment(containingFileOffset: -1))
        XCTAssertNil(image.section(containingFileOffset: -1))
    }

    func testRoundTripsEveryFileBackedSectionByte() throws {
        let image = try image("hello-arm64")
        for section in image.segments.flatMap(\.sections) where !section.isZeroFill {
            let start = try XCTUnwrap(section.fileOffset)
            for delta in [0, section.size - 1] {
                let offset = Int(start + delta)
                XCTAssertEqual(image.fileOffset(forAddress: section.address + delta), offset, section.name)
                XCTAssertEqual(image.address(forFileOffset: offset), section.address + delta, section.name)
            }
        }
    }

    func testObjectFileHeaderBelongsToNoSegment() throws {
        let image = try image("plugin.o")
        XCTAssertNil(image.address(forFileOffset: 100))  // load commands
        XCTAssertEqual(image.address(forFileOffset: 392), 0)
        XCTAssertEqual(image.fileOffset(forAddress: 8), 400)  // __compact_unwind
        XCTAssertNil(image.fileOffset(forAddress: 0x28))  // past vmsize
    }

    /// In a universal file the mapping gives absolute offsets, and only inside the slice.
    func testUniversalSliceMapsToAbsoluteOffsets() throws {
        let data = try MachOFixture.data("hello-universal")
        let arm = try image("hello-universal", slice: 1)
        let thin = try MachOFixture.data("hello-arm64")
        XCTAssertEqual(arm.fileOffset(forAddress: 0x1_0000_0548), 16384 + 1352)
        XCTAssertEqual(arm.address(forFileOffset: 16384 + 1352), 0x1_0000_0548)
        XCTAssertNil(arm.address(forFileOffset: 1352))  // inside the x86_64 slice, not this one
        XCTAssertEqual(arm.section(containingFileOffset: 16384 + 1352)?.name, "__text")
        XCTAssertEqual(arm.segment(containingFileOffset: 16384)?.name, "__TEXT")
        let offset = try XCTUnwrap(arm.fileOffset(forAddress: 0x1_0000_0548))
        XCTAssertEqual(data[offset..<(offset + 0x68)], thin[1352..<(1352 + 0x68)])
        XCTAssertNil(arm.fileOffset(forAddress: 0x1_0000_C000))  // zero-fill stays nil

        let x86 = try image("hello-universal", slice: 0)
        XCTAssertEqual(x86.fileOffset(forAddress: 0x1_0000_05A0), 4096 + 1440)
        XCTAssertEqual(x86.address(forFileOffset: 4096), 0x1_0000_0000)
        XCTAssertNil(x86.address(forFileOffset: 16384))  // the arm64 slice
    }

    // MARK: - Hand-built segments

    private func syntheticImage(_ segments: [MachOSegment], sliceRange: Range<Int> = 0..<0x10000) -> MachOImage {
        MachOImage(
            sliceRange: sliceRange, is64Bit: true, isBigEndian: false, cpuType: 0x0100_000C, cpuSubtype: 0, architectureName: "arm64",
            fileType: 2, commandCount: 0, commandsSize: 0, flags: 0, segments: segments)
    }

    private func segment(_ name: String, vm: UInt64, vmSize: UInt64, file: UInt64, fileSize: UInt64) -> MachOSegment {
        MachOSegment(
            name: name, vmAddress: vm, vmSize: vmSize, fileOffset: file, fileSize: fileSize, maxProtection: 1, initialProtection: 1,
            flags: 0, sections: [])
    }

    /// A segment maps at most vmsize bytes, even when filesize claims more.
    func testFileSizeLargerThanVMSizeIsCappedAtVMSize() {
        let image = syntheticImage([segment("A", vm: 0x1000, vmSize: 0x10, file: 0x40, fileSize: 0x100)])
        XCTAssertEqual(image.fileOffset(forAddress: 0x100F), 0x4F)
        XCTAssertNil(image.fileOffset(forAddress: 0x1010))
        XCTAssertEqual(image.address(forFileOffset: 0x4F), 0x100F)
        XCTAssertNil(image.address(forFileOffset: 0x50))
        XCTAssertNil(image.segment(containingFileOffset: 0x50))
    }

    /// Offsets past the bytes present map to nothing, and sums near UInt64.max never trap.
    func testMappingStaysInsideTheSliceAndNeverOverflows() {
        let image = syntheticImage(
            [
                segment("Past", vm: 0x1000, vmSize: 0x1000, file: 0xFF00, fileSize: 0x1000),
                segment("Top", vm: .max - 0xF, vmSize: 0x100, file: 0x20, fileSize: 0x100),
                segment("Far", vm: 0x9000, vmSize: 0x100, file: .max - 1, fileSize: 0x100),
            ], sliceRange: 0..<0x10000)
        XCTAssertEqual(image.fileOffset(forAddress: 0x1000), 0xFF00)
        XCTAssertNil(image.fileOffset(forAddress: 0x1100))  // 0x10000: past the slice
        // "Past" claims file bytes to 0x10F00, but the slice (the bytes present) ends at 0x10000.
        XCTAssertEqual(image.address(forFileOffset: 0xFFFF), 0x10FF)
        XCTAssertNil(image.address(forFileOffset: 0x10000))
        XCTAssertNil(image.address(forFileOffset: 0x10010))
        XCTAssertEqual(image.fileOffset(forAddress: .max), 0x2F)
        XCTAssertEqual(image.address(forFileOffset: 0x2F), .max)
        XCTAssertNil(image.address(forFileOffset: 0x30))  // .max + 1 would overflow
        XCTAssertNil(image.fileOffset(forAddress: 0x9005))  // .max - 1 + 5 would overflow
        XCTAssertEqual(image.segment(containingAddress: 0x9005)?.name, "Far")
    }
}
