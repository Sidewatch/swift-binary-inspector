//
//  BinaryValues.swift
//  BinaryInspector
//
//  Decode the bytes at an offset as every common fixed-width type — the "data inspector"
//  panel behind a hex view's caret.
//
//  Created by David Sherlock on 8/4/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Reads the bytes at a single offset back as each common fixed-width scalar type, for the
/// "interpreted as…" panel beside a hex view's caret. A type whose span runs past the end comes
/// back `inRange == false` with a placeholder, never dropped, so the rows never shift.
public enum BinaryValues {

    /// Byte order used to assemble multi-byte values.
    public enum Endianness: String, CaseIterable, Equatable, Sendable {
        case little, big
        /// Display name for a segmented control.
        public var label: String { self == .little ? "Little" : "Big" }
        /// True for big-endian, the flag form the typed readers take.
        var isBig: Bool { self == .big }
    }

    /// One decoded interpretation of the bytes at an offset.
    public struct Value: Equatable, Sendable {
        /// Type name for the label column (`"Int32"`, `"Float32"`, …).
        public let type: String
        /// The decoded value, or ``BinaryValues/outOfRange`` when the span overruns the data.
        public let text: String
        /// How many bytes this interpretation consumes.
        public let byteWidth: Int
        /// False when `offset + byteWidth` runs past the end — `text` is a placeholder.
        public let inRange: Bool

        /// Creates one decoded row.
        public init(type: String, text: String, byteWidth: Int, inRange: Bool) {
            self.type = type
            self.text = text
            self.byteWidth = byteWidth
            self.inRange = inRange
        }
    }

    /// Placeholder shown for an interpretation that runs past the end of the data.
    public static let outOfRange = "—"

    /// Decodes the bytes at `offset` as every supported type, in panel order.
    ///
    /// The row set is fixed — 8/16/32/64-bit signed and unsigned integers, 32/64-bit floats,
    /// then the byte as ASCII — because rows that come and go as the caret moves are unreadable.
    /// An out-of-range `offset` yields all-placeholder rows; single-byte types ignore `endianness`.
    public static func decode(_ data: Data, at offset: Int, endianness: Endianness = .little) -> [Value] {
        let big = endianness.isBig
        return [
            value("Int8", int8(data, offset).map(String.init), 1, data, offset),
            value("UInt8", uint8(data, offset).map(String.init), 1, data, offset),
            value("Int16", int16(data, offset, big).map(String.init), 2, data, offset),
            value("UInt16", uint16(data, offset, big).map(String.init), 2, data, offset),
            value("Int32", int32(data, offset, big).map(String.init), 4, data, offset),
            value("UInt32", uint32(data, offset, big).map(String.init), 4, data, offset),
            value("Int64", int64(data, offset, big).map(String.init), 8, data, offset),
            value("UInt64", uint64(data, offset, big).map(String.init), 8, data, offset),
            value("Float32", float32(data, offset, big).map(floatText), 4, data, offset),
            value("Float64", float64(data, offset, big).map(doubleText), 8, data, offset),
            value("ASCII", uint8(data, offset).map { String(HexDump.printableASCII($0)) }, 1, data, offset),
        ]
    }

    /// Build a row, marking it out-of-range when the span does not fit.
    private static func value(_ type: String, _ text: String?, _ width: Int, _ data: Data, _ offset: Int) -> Value {
        let fits = offset >= 0 && offset + width <= data.count
        return Value(type: type, text: fits ? (text ?? outOfRange) : outOfRange, byteWidth: width, inRange: fits)
    }

    // MARK: - Typed reads (each `nil` when the span runs past the end)

    /// The byte at offset `o`.
    public static func uint8(_ d: Data, _ o: Int) -> UInt8? {
        guard o >= 0, o + 1 <= d.count else { return nil }
        return d[d.startIndex + o]
    }

    /// The byte at offset `o`, signed.
    public static func int8(_ d: Data, _ o: Int) -> Int8? { uint8(d, o).map { Int8(bitPattern: $0) } }

    /// Unsigned 16-bit integer at offset `o`.
    public static func uint16(_ d: Data, _ o: Int, _ bigEndian: Bool) -> UInt16? {
        ByteReader.u16(d, o, bigEndian: bigEndian)
    }

    /// Signed 16-bit integer at offset `o`.
    public static func int16(_ d: Data, _ o: Int, _ bigEndian: Bool) -> Int16? {
        uint16(d, o, bigEndian).map { Int16(bitPattern: $0) }
    }

    /// Unsigned 32-bit integer at offset `o`.
    public static func uint32(_ d: Data, _ o: Int, _ bigEndian: Bool) -> UInt32? {
        ByteReader.u32(d, o, bigEndian: bigEndian)
    }

    /// Signed 32-bit integer at offset `o`.
    public static func int32(_ d: Data, _ o: Int, _ bigEndian: Bool) -> Int32? {
        uint32(d, o, bigEndian).map { Int32(bitPattern: $0) }
    }

    /// Unsigned 64-bit integer at offset `o`.
    public static func uint64(_ d: Data, _ o: Int, _ bigEndian: Bool) -> UInt64? {
        ByteReader.u64(d, o, bigEndian: bigEndian)
    }

    /// Signed 64-bit integer at offset `o`.
    public static func int64(_ d: Data, _ o: Int, _ bigEndian: Bool) -> Int64? {
        uint64(d, o, bigEndian).map { Int64(bitPattern: $0) }
    }

    /// IEEE-754 single precision from the four bytes at `offset`.
    public static func float32(_ d: Data, _ o: Int, _ bigEndian: Bool) -> Float? {
        uint32(d, o, bigEndian).map { Float(bitPattern: $0) }
    }

    /// IEEE-754 double precision from the eight bytes at `offset`.
    public static func float64(_ d: Data, _ o: Int, _ bigEndian: Bool) -> Double? {
        uint64(d, o, bigEndian).map { Double(bitPattern: $0) }
    }

    // MARK: - Float formatting

    /// Formats a `Float` at Float precision. NaN/infinity are spelled out, since hitting one
    /// usually means the offset or endianness is wrong.
    ///
    /// Must not use `%g` or widen to `Double`: `%g` renders `100.0` as `1e+02`, and widening
    /// prints conversion noise (`0.1` as `0.100000001`). `description` round-trips exactly.
    static func floatText(_ f: Float) -> String {
        if f.isNaN { return "NaN" }
        if f.isInfinite { return f < 0 ? "-Infinity" : "Infinity" }
        return f.description
    }

    /// Formats a `Double` the same way as ``floatText(_:)``.
    static func doubleText(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        return d.description
    }
}
