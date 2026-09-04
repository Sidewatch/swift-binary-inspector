//
//  ByteSearch.swift
//  SwiftBinaryInspect
//
//  Find a byte pattern (hex or ASCII) in binary data — every match offset.
//
//  Created by David Sherlock on 7/18/26.
//

import Foundation

/// Locate every occurrence of a byte pattern in binary data. Patterns come in as an
/// ASCII string, a hex string (`"ff 00 4d5a"`, spaces optional), or raw bytes; each
/// search returns all match offsets so a hex view can highlight/step through them.
public enum ByteSearch {

    /// All offsets where `needle` occurs in `data` at or after `from` (overlapping matches
    /// included). Empty `needle` returns no matches.
    public static func find(_ needle: [UInt8], in data: Data, from: Int = 0) -> [Int] {
        guard !needle.isEmpty, needle.count <= data.count else { return [] }
        var out: [Int] = []
        let base = data.startIndex
        let last = data.count - needle.count
        var i = max(0, from)
        while i <= last {
            var j = 0
            while j < needle.count, data[base + i + j] == needle[j] { j += 1 }
            if j == needle.count { out.append(i) }
            i += 1
        }
        return out
    }

    /// Find an ASCII/UTF-8 substring's byte pattern in `data`.
    public static func findString(_ s: String, in data: Data, from: Int = 0) -> [Int] {
        find([UInt8](s.utf8), in: data, from: from)
    }

    /// Find a hex pattern (`"ffd8"` / `"ff d8 ff"`, case-insensitive, spaces optional) in
    /// `data`. Returns `nil` when the pattern isn't valid hex (odd digit count or a
    /// non-hex character), distinguishing "bad pattern" from "no matches" (`[]`).
    public static func findHex(_ hex: String, in data: Data, from: Int = 0) -> [Int]? {
        guard let needle = parseHex(hex) else { return nil }
        return find(needle, in: data, from: from)
    }

    /// Parse a hex string (spaces/tabs/newlines ignored, case-insensitive) into bytes, or
    /// `nil` on an odd number of digits or any non-hex character. Empty input → `[]`.
    public static func parseHex(_ hex: String) -> [UInt8]? {
        let digits = hex.filter { !$0.isWhitespace }
        guard digits.count % 2 == 0 else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(digits.count / 2)
        var it = digits.makeIterator()
        while let hi = it.next(), let lo = it.next() {
            guard let h = hi.hexDigitValue, let l = lo.hexDigitValue else { return nil }
            out.append(UInt8(h << 4 | l))
        }
        return out
    }
}
