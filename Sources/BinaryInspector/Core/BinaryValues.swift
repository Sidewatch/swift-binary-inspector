//
//  BinaryValues.swift
//  SwiftBinaryInspect
//
//  Decode the bytes at an offset as every common fixed-width type — the "data inspector"
//  panel behind a hex view's caret.
//
//  Created by David Sherlock on 8/4/26.
//

import Foundation

/// Reads the bytes at a single offset back as each common fixed-width scalar type, so a
/// hex view can show "what is this, interpreted as…" beside the caret. Read-only and
/// bounds-checked: a type whose span runs past the end comes back `inRange == false` with
/// a placeholder string rather than being dropped, so the panel's row set never shifts
/// under the caret as it nears the end of the file.
public enum BinaryValues {

    /// Byte order used to assemble multi-byte values.
    public enum Endianness: String, CaseIterable, Equatable, Sendable {
        case little, big
        /// Display name for a segmented control.
        public var label: String { self == .little ? "Little" : "Big" }
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

        public init(type: String, text: String, byteWidth: Int, inRange: Bool) {
            self.type = type
            self.text = text
            self.byteWidth = byteWidth
            self.inRange = inRange
        }
    }

    /// Placeholder shown for an interpretation that runs past the end of the data.
    public static let outOfRange = "—"

    /// Decode the bytes at `offset` as every supported type, in panel order.
    ///
    /// The row set is fixed and never varies with position: 8/16/32/64-bit signed and
    /// unsigned integers, 32/64-bit floats, then the raw byte as ASCII. That stability is
    /// deliberate — a panel whose rows appear and disappear as the caret moves is unreadable.
    ///
    /// - Parameters:
    ///   - data: The bytes being inspected.
    ///   - offset: Byte offset of the caret. Out-of-range offsets yield all-placeholder rows.
    ///   - endianness: Byte order for the multi-byte types (single-byte types ignore it).
    /// - Returns: One ``Value`` per supported type, in a stable display order.
    public static func decode(_ data: Data, at offset: Int, endianness: Endianness = .little) -> [Value] {
        let big = endianness.isBig
        return [
            value("Int8",    int8(data, offset).map(String.init),            1, data, offset),
            value("UInt8",   uint8(data, offset).map(String.init),           1, data, offset),
            value("Int16",   int16(data, offset, big).map(String.init),      2, data, offset),
            value("UInt16",  uint16(data, offset, big).map(String.init),     2, data, offset),
            value("Int32",   int32(data, offset, big).map(String.init),      4, data, offset),
            value("UInt32",  uint32(data, offset, big).map(String.init),     4, data, offset),
            value("Int64",   int64(data, offset, big).map(String.init),      8, data, offset),
            value("UInt64",  uint64(data, offset, big).map(String.init),     8, data, offset),
            value("Float32", float32(data, offset, big).map(floatText),      4, data, offset),
            value("Float64", float64(data, offset, big).map(doubleText),     8, data, offset),
            value("ASCII",   uint8(data, offset).map { String(HexDump.printableASCII($0)) }, 1, data, offset),
        ]
    }

    /// Build a row, marking it out-of-range when the span does not fit.
    private static func value(_ type: String, _ text: String?, _ width: Int, _ data: Data, _ offset: Int) -> Value {
        let fits = offset >= 0 && offset + width <= data.count
        return Value(type: type, text: fits ? (text ?? outOfRange) : outOfRange, byteWidth: width, inRange: fits)
    }

    // MARK: - Typed reads (each `nil` when the span runs past the end)

    public static func uint8(_ d: Data, _ o: Int) -> UInt8? {
        guard o >= 0, o + 1 <= d.count else { return nil }
        return d[d.startIndex + o]
    }

    public static func int8(_ d: Data, _ o: Int) -> Int8? { uint8(d, o).map { Int8(bitPattern: $0) } }

    public static func uint16(_ d: Data, _ o: Int, _ bigEndian: Bool) -> UInt16? {
        ByteReader.u16(d, o, bigEndian: bigEndian)
    }

    public static func int16(_ d: Data, _ o: Int, _ bigEndian: Bool) -> Int16? {
        uint16(d, o, bigEndian).map { Int16(bitPattern: $0) }
    }

    public static func uint32(_ d: Data, _ o: Int, _ bigEndian: Bool) -> UInt32? {
        ByteReader.u32(d, o, bigEndian: bigEndian)
    }

    public static func int32(_ d: Data, _ o: Int, _ bigEndian: Bool) -> Int32? {
        uint32(d, o, bigEndian).map { Int32(bitPattern: $0) }
    }

    public static func uint64(_ d: Data, _ o: Int, _ bigEndian: Bool) -> UInt64? {
        ByteReader.u64(d, o, bigEndian: bigEndian)
    }

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

    /// Format a `Float` for the panel. NaN/infinity are named rather than printed as
    /// `nan`/`inf`, because in binary reverse-engineering hitting one usually means the
    /// offset or the endianness is wrong, and that should read as a signal not a value.
    /// Format a `Float` at Float precision.
    ///
    /// Swift's own `description` is the shortest string that round-trips back to the SAME
    /// value at that type's precision, and it only reaches for scientific notation at genuine
    /// extremes. Two bugs came from hand-rolling this with `%g` instead:
    /// `100.0` rendered as `1e+02` (because `%g` prefers exponents once the exponent exceeds
    /// the precision), and a `Float` widened to `Double` before formatting printed nine
    /// digits of conversion noise — `0.1` as `0.100000001`. Widening a Float and asking for
    /// Double precision shows the error, not the value.
    static func floatText(_ f: Float) -> String {
        if f.isNaN { return "NaN" }
        if f.isInfinite { return f < 0 ? "-Infinity" : "Infinity" }
        return f.description
    }

    static func doubleText(_ d: Double) -> String {
        if d.isNaN { return "NaN" }
        if d.isInfinite { return d < 0 ? "-Infinity" : "Infinity" }
        return d.description
    }
}
