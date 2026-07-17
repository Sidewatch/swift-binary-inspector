//
//  ByteReader.swift
//  SwiftBinaryInspect
//
//  Bounds-checked little/big-endian integer reads over Data — shared by the format parsers.
//
//  Created by David Sherlock on 7/18/26.
//

import Foundation

/// Bounds-checked, endian-aware fixed-width integer reads over `Data`. Every read returns
/// `nil` rather than trapping when the requested span runs past the end, so the format
/// parsers can treat truncated files as simply "unrecognized" instead of crashing.
enum ByteReader {

    /// Read a `UInt16` at `offset`, big- or little-endian. `nil` if out of range.
    static func u16(_ d: Data, _ offset: Int, bigEndian: Bool) -> UInt16? {
        guard offset >= 0, offset + 2 <= d.count else { return nil }
        let b0 = UInt16(d[d.startIndex + offset])
        let b1 = UInt16(d[d.startIndex + offset + 1])
        return bigEndian ? (b0 << 8) | b1 : (b1 << 8) | b0
    }

    /// Read a `UInt32` at `offset`, big- or little-endian. `nil` if out of range.
    static func u32(_ d: Data, _ offset: Int, bigEndian: Bool) -> UInt32? {
        guard offset >= 0, offset + 4 <= d.count else { return nil }
        let s = d.startIndex + offset
        let b = (0..<4).map { UInt32(d[s + $0]) }
        return bigEndian
            ? (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
            : (b[3] << 24) | (b[2] << 16) | (b[1] << 8) | b[0]
    }

    /// True when `data` begins with `prefix`.
    static func hasPrefix(_ data: Data, _ prefix: [UInt8]) -> Bool {
        guard data.count >= prefix.count else { return false }
        for (i, b) in prefix.enumerated() where data[data.startIndex + i] != b { return false }
        return true
    }

    /// True when the bytes at `offset` equal `bytes`.
    static func matches(_ data: Data, at offset: Int, _ bytes: [UInt8]) -> Bool {
        guard offset >= 0, offset + bytes.count <= data.count else { return false }
        for (i, b) in bytes.enumerated() where data[data.startIndex + offset + i] != b { return false }
        return true
    }
}
