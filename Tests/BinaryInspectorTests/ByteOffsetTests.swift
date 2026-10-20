//
//  ByteOffsetTests.swift
//  BinaryInspectorTests
//
//  `ByteOffset.parse`: plain and 0x-prefixed hex, only a leading prefix, and junk refused.
//
//  Created by David Sherlock on 10/21/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import XCTest
@testable import BinaryInspector

/// `ByteOffset.parse`.
final class ByteOffsetTests: XCTestCase {
    func testPlainAndPrefixedHex() {
        XCTAssertEqual(ByteOffset.parse("1f40"), 0x1F40)
        XCTAssertEqual(ByteOffset.parse(" 0x1F40 "), 0x1F40)
        XCTAssertEqual(ByteOffset.parse("0X10"), 0x10)
    }

    func testOnlyALeadingPrefixCounts() {
        XCTAssertNil(ByteOffset.parse("10x0"), "not 0x10")
        XCTAssertNil(ByteOffset.parse("0x0x10"))
    }

    func testJunkIsRefused() {
        XCTAssertNil(ByteOffset.parse(""))
        XCTAssertNil(ByteOffset.parse("0x"))
        XCTAssertNil(ByteOffset.parse("-10"))
        XCTAssertNil(ByteOffset.parse("12g"))
        XCTAssertNil(ByteOffset.parse("ffffffffffffffffffff"), "overflow")
    }
}
