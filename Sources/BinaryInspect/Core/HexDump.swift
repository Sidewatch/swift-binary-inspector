//
//  HexDump.swift
//  SwiftBinaryInspect
//
//  Classic xxd-style hex + ASCII dump, as structured rows for a UI or a plain string.
//
//  Created by David Sherlock on 7/18/26.
//

import Foundation

/// A read-only hex/ASCII dumper. Produces either structured rows (offset + raw bytes,
/// so a view can colorize each byte cell itself) or a classic `xxd`-style string.
/// Pure Foundation, allocation-light, never mutates the input.
public enum HexDump {

    /// One dump row: the byte offset of its first byte, plus the raw bytes it covers
    /// (1...`bytesPerRow` of them — the final row may be short).
    public struct Row: Equatable {
        /// Absolute offset of `bytes[0]` within the original data.
        public let offset: UInt64
        /// The raw bytes on this row (never empty; at most one row's worth).
        public let bytes: [UInt8]

        public init(offset: UInt64, bytes: [UInt8]) {
            self.offset = offset
            self.bytes = bytes
        }

        /// The offset column formatted as a fixed-width lowercase hex address (8 digits).
        public var offsetColumn: String { String(format: "%08x", offset) }

        /// Per-byte two-char lowercase hex (`["ff", "00", …]`) — exactly `bytes.count` entries.
        /// A view can pad to `bytesPerRow` with blanks itself and color each cell by category.
        public var hexBytes: [String] { bytes.map { String(format: "%02x", $0) } }

        /// The ASCII gutter: printable bytes as themselves, everything else as `.`.
        public var asciiColumn: String { String(bytes.map { HexDump.printableASCII($0) }) }
    }

    /// Split `data` into dump rows.
    ///
    /// - Parameters:
    ///   - data: The bytes to dump.
    ///   - bytesPerRow: Bytes per row (clamped to at least 1; default 16).
    ///   - from: Start offset into `data` (clamped into range).
    ///   - length: How many bytes to cover from `from` (default: to the end).
    /// - Returns: The rows, in order. Empty when the requested window is empty.
    public static func rows(of data: Data, bytesPerRow: Int = 16, from: Int = 0, length: Int? = nil) -> [Row] {
        let width = max(1, bytesPerRow)
        let start = min(max(0, from), data.count)
        let end = min(data.count, length.map { start + max(0, $0) } ?? data.count)
        guard start < end else { return [] }
        // Data slices keep their parent's indices — subscript relative to startIndex.
        let base = data.startIndex
        var rows: [Row] = []
        rows.reserveCapacity((end - start + width - 1) / width)
        var i = start
        while i < end {
            let rowEnd = min(i + width, end)
            rows.append(Row(offset: UInt64(i), bytes: [UInt8](data[(base + i)..<(base + rowEnd)])))
            i = rowEnd
        }
        return rows
    }

    /// Render `data` as a classic `xxd`-style string: `offset  hex hex …  |ascii|`, one
    /// row per `bytesPerRow`. The hex column is padded so the ASCII gutter stays aligned
    /// on a short final row.
    ///
    /// - Parameters: see ``rows(of:bytesPerRow:from:length:)``.
    /// - Returns: The multi-line dump (no trailing newline), or `""` for an empty window.
    public static func render(_ data: Data, bytesPerRow: Int = 16, from: Int = 0, length: Int? = nil) -> String {
        let width = max(1, bytesPerRow)
        return rows(of: data, bytesPerRow: width, from: from, length: length).map { row in
            var hex = row.hexBytes.joined(separator: " ")
            let full = width * 3 - 1   // "ff" * width + (width-1) spaces
            if hex.count < full { hex += String(repeating: " ", count: full - hex.count) }
            return "\(row.offsetColumn)  \(hex)  |\(row.asciiColumn)|"
        }.joined(separator: "\n")
    }

    /// The printable-ASCII glyph for a byte: the byte itself for `0x20...0x7E`, else `.`.
    public static func printableASCII(_ b: UInt8) -> Character {
        (0x20...0x7E).contains(b) ? Character(UnicodeScalar(b)) : "."
    }
}
