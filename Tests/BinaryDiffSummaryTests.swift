//
//  BinaryDiffSummaryTests.swift
//  BinaryInspectorTests
//
//  Tests for the diff status line and the per-run hex preview.
//
//  Created by David Sherlock on 9/5/26.
//

import XCTest
@testable import BinaryInspector

final class BinaryDiffSummaryTests: XCTestCase {

    private func result(runs: [BinaryDiff.Run] = [], differing: Int = 0, delta: Int = 0, truncated: Bool = false) -> BinaryDiff.Result {
        BinaryDiff.Result(runs: runs, differingBytes: differing, comparedLength: 100, lengthDelta: delta, truncated: truncated)
    }

    func testIdentical() {
        XCTAssertEqual(result().summary(filename: "a.bin", compareName: "b.bin"), "b.bin: identical.")
    }

    func testRunsAndBytes() {
        let r = result(runs: [BinaryDiff.Run(offset: 0, length: 1)], differing: 1)
        XCTAssertEqual(r.summary(filename: "a.bin", compareName: "b.bin"), "b.bin: 1 run, 1 byte differ")
        let many = result(runs: Array(repeating: BinaryDiff.Run(offset: 0, length: 2), count: 3), differing: 17)
        XCTAssertEqual(many.summary(filename: "a.bin", compareName: "b.bin"), "b.bin: 3 runs, 17 bytes differ")
    }

    func testWhichFileIsLongerIsNamed() {
        XCTAssertEqual(result(delta: 2048).summary(filename: "a.bin", compareName: "b.bin"), "b.bin: b.bin is 2.0 KB longer")
        XCTAssertEqual(result(delta: -500).summary(filename: "a.bin", compareName: "b.bin"), "b.bin: a.bin is 500 B longer")
    }

    func testCappedListIsSaid() {
        let r = result(runs: [BinaryDiff.Run(offset: 0, length: 1)], differing: 1, delta: 1, truncated: true)
        XCTAssertEqual(r.summary(filename: "a.bin", compareName: "b.bin"),
                       "b.bin: 1 run, 1 byte differ · b.bin is 1 B longer · list capped — more differences follow")
    }

    func testRunPreview() {
        let mine = Data([0x00, 0x01, 0x02, 0x03]), theirs = Data([0xff, 0xfe, 0x02, 0x03])
        XCTAssertEqual(BinaryDiff.Run(offset: 0, length: 2).preview(in: mine, against: theirs), "00 01  →  ff fe")
        XCTAssertEqual(BinaryDiff.Run(offset: 1, length: 3).preview(in: mine, against: theirs, showing: 2), "01 02…  →  fe 02…")
        XCTAssertEqual(BinaryDiff.Run(offset: 3, length: 4).preview(in: mine, against: Data([0xaa])), "03  →  —", "a side with no bytes there")
        XCTAssertEqual(BinaryDiff.Run(offset: 0, length: 2).preview(in: mine, against: nil), "", "nothing to compare against")
    }
}
