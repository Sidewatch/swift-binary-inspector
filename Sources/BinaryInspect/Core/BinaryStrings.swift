//
//  BinaryStrings.swift
//  SwiftBinaryInspect
//
//  Printable-string extraction (the `strings(1)` idea) over arbitrary bytes.
//
//  Created by David Sherlock on 7/18/26.
//

import Foundation

/// Extracts runs of printable characters from binary data — the classic `strings(1)`
/// tool. Supports ASCII and UTF-16 (both byte orders), each match tagged with the byte
/// offset where it starts so a UI can jump to it in a hex view.
public enum BinaryStrings {

    /// Which character width/encoding to scan for.
    public enum Encoding {
        /// One byte per character, `0x20...0x7E` plus tab.
        case ascii
        /// Two bytes per character, little-endian (Windows-style wide strings).
        case utf16LE
        /// Two bytes per character, big-endian.
        case utf16BE
    }

    /// A recovered string and the byte offset it begins at.
    public struct Found: Equatable {
        public let offset: Int
        public let value: String
        public init(offset: Int, value: String) { self.offset = offset; self.value = value }
    }

    /// Extract every printable run of at least `minLength` characters.
    ///
    /// - Parameters:
    ///   - data: The bytes to scan.
    ///   - minLength: Minimum run length to report (clamped to ≥ 1; default 4).
    ///   - encoding: Character width to scan for (default `.ascii`).
    /// - Returns: Matches in offset order.
    public static func extract(from data: Data, minLength: Int = 4, encoding: Encoding = .ascii) -> [Found] {
        let minLen = max(1, minLength)
        switch encoding {
        case .ascii:   return scanASCII(data, minLen: minLen)
        case .utf16LE: return scanUTF16(data, minLen: minLen, bigEndian: false)
        case .utf16BE: return scanUTF16(data, minLen: minLen, bigEndian: true)
        }
    }

    /// True for bytes that count as printable in an ASCII scan (`0x20...0x7E` or tab).
    private static func isPrintable(_ b: UInt8) -> Bool { (0x20...0x7E).contains(b) || b == 0x09 }

    private static func scanASCII(_ data: Data, minLen: Int) -> [Found] {
        var out: [Found] = []
        var runStart = -1
        var scalars: [UInt8] = []
        let base = data.startIndex
        func flush(_ endIndex: Int) {
            if runStart >= 0, scalars.count >= minLen {
                out.append(Found(offset: runStart, value: String(decoding: scalars, as: UTF8.self)))
            }
            runStart = -1; scalars.removeAll(keepingCapacity: true)
        }
        for i in 0..<data.count {
            let b = data[base + i]
            if isPrintable(b) {
                if runStart < 0 { runStart = i }
                scalars.append(b)
            } else {
                flush(i)
            }
        }
        flush(data.count)
        return out
    }

    private static func scanUTF16(_ data: Data, minLen: Int, bigEndian: Bool) -> [Found] {
        var out: [Found] = []
        var runStart = -1
        var chars: [Character] = []
        func flush() {
            if runStart >= 0, chars.count >= minLen {
                out.append(Found(offset: runStart, value: String(chars)))
            }
            runStart = -1; chars.removeAll(keepingCapacity: true)
        }
        var i = 0
        while i + 1 < data.count {
            guard let u = ByteReader.u16(data, i, bigEndian: bigEndian) else { break }
            // Treat only the printable-ASCII subset of the BMP as "a wide string" —
            // enough for the Windows resource / UTF-16 path names this is meant to surface,
            // without false-positive runs from arbitrary two-byte noise.
            if u >= 0x20, u <= 0x7E {
                if runStart < 0 { runStart = i }
                chars.append(Character(UnicodeScalar(u)!))
            } else if u == 0x09 {
                if runStart < 0 { runStart = i }
                chars.append("\t")
            } else {
                flush()
            }
            i += 2
        }
        flush()
        return out
    }
}
