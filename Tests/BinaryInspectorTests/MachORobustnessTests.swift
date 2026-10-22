//
//  MachORobustnessTests.swift
//  BinaryInspectorTests
//
//  Tests that MachOParser survives damaged input: every fixture truncated at many lengths and
//  with seeded random byte flips must parse (or give nil) without trapping, quickly, and with
//  every reported offset inside the bytes it was given.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import BinaryInspector

/// Truncation and fuzz tests for `MachOParser`, `MachOParser.symbols` and the address mapping.
final class MachORobustnessTests: XCTestCase {

    /// A deterministic generator (SplitMix64), so a failure reproduces from its case number.
    private struct SplitMix64: RandomNumberGenerator {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D1_33A4_9B1C_E133
            return z ^ (z >> 31)
        }
    }

    /// Parse `data` and exercise everything a viewer would call, checking that every offset the
    /// parser reports as present really is inside `data`. Returns the seconds it took.
    @discardableResult
    private func exercise(_ data: Data, _ label: @autoclosure () -> String) -> TimeInterval {
        let start = Date()
        guard let file = MachOParser.parse(data) else { return Date().timeIntervalSince(start) }
        XCTAssertLessThanOrEqual(file.slices.count, 30, label())
        for image in file.images {
            XCTAssertGreaterThanOrEqual(image.sliceRange.lowerBound, 0, label())
            XCTAssertLessThanOrEqual(image.sliceRange.upperBound, data.count, label())
            XCTAssertLessThanOrEqual(image.loadCommands.count, data.count / 8, label())
            for command in image.loadCommands {
                XCTAssertGreaterThanOrEqual(command.fileOffset, image.sliceRange.lowerBound, label())
                XCTAssertLessThanOrEqual(command.fileOffset + Int(command.size), image.sliceRange.upperBound, label())
            }
            for segment in image.segments {
                XCTAssertLessThanOrEqual(segment.sections.count, data.count / 68, label())
            }
            let table = MachOParser.symbols(in: data, image: image, limit: 50_000)
            XCTAssertLessThanOrEqual(table.symbols.count, max(0, image.sliceRange.count / 12), label())
            XCTAssertEqual(table.truncated, table.symbols.count < table.declaredCount, label())
            for segment in image.segments.prefix(8) {
                for address in [segment.vmAddress, segment.vmAddress &+ segment.fileSize / 2, segment.vmAddress &+ segment.vmSize &- 1] {
                    if let offset = image.fileOffset(forAddress: address) {
                        XCTAssertTrue(image.sliceRange.contains(offset), label())
                    }
                    _ = image.section(containingAddress: address)
                }
            }
            for offset in stride(
                from: image.sliceRange.lowerBound, to: image.sliceRange.upperBound, by: max(1, image.sliceRange.count / 16))
            {
                _ = image.address(forFileOffset: offset)
                _ = image.section(containingFileOffset: offset)
            }
        }
        return Date().timeIntervalSince(start)
    }

    /// Every fixture cut at every length up to 2 KiB (the headers and load commands) and at
    /// every 61st length after that.
    func testTruncatedFixturesNeverTrap() throws {
        var cases = 0
        var slowest: TimeInterval = 0
        for name in MachOFixture.all {
            let data = try MachOFixture.data(name)
            let lengths = Array(0...min(2048, data.count)) + Array(stride(from: 2049, through: data.count, by: 61))
            for length in lengths {
                slowest = max(slowest, exercise(data.prefix(length), "\(name) cut at \(length)"))
                cases += 1
            }
        }
        XCTAssertGreaterThan(cases, 15_000)
        XCTAssertLessThan(slowest, 0.25)
    }

    /// 4,000 seeded cases: a fixture with 1 to 16 bytes replaced, mostly in the first 4 KiB
    /// where the headers, load commands and (for the universal files) slice table live.
    func testRandomByteFlipsNeverTrap() throws {
        let fixtures = try MachOFixture.all.map { try Array(MachOFixture.data($0)) }
        var random = SplitMix64(state: 0x5EED_0F_FAC0)
        var slowest: TimeInterval = 0
        var parsed = 0
        for index in 0..<4000 {
            let which = Int(random.next() % UInt64(fixtures.count))
            var bytes = fixtures[which]
            let flips = 1 + Int(random.next() % 16)
            for _ in 0..<flips {
                let window = random.next() % 5 == 0 ? bytes.count : min(4096, bytes.count)
                let position = Int(random.next() % UInt64(window))
                bytes[position] = random.next() % 3 == 0 ? 0xFF : UInt8(truncatingIfNeeded: random.next())
            }
            let data = Data(bytes)
            if MachOParser.parse(data) != nil { parsed += 1 }
            slowest = max(slowest, exercise(data, "case \(index) (\(MachOFixture.all[which]), \(flips) flips)"))
        }
        XCTAssertGreaterThan(parsed, 1000)  // most damaged files still yield a structure
        XCTAssertLessThan(slowest, 0.25)
    }

    /// A hostile header built to make a careless parser loop or allocate: `ncmds` and
    /// `sizeofcmds` of four billion over a megabyte of eight-byte commands.
    func testHostileCountsStayBounded() throws {
        var b = MachOImageBuilder()
        b.declaredCount = .max
        b.declaredSize = .max
        var commands = MachOBytes()
        for _ in 0..<(1 << 17) {
            commands.u32(0x99)
            commands.u32(8)
        }
        let start = Date()
        let image = try XCTUnwrap(MachOParser.parse(b.build(trailing: commands.bytes))?.images.first)
        XCTAssertEqual(image.loadCommands.count, 1 << 17)
        XCTAssertEqual(image.issues.last, .commandsTruncated(declared: .max, read: 1 << 17))
        XCTAssertLessThan(Date().timeIntervalSince(start), 2)
    }
}
