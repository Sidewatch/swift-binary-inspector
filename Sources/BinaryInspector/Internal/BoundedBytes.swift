//
//  BoundedBytes.swift
//  BinaryInspector
//
//  Bounds-checked, endian-aware reads over a raw byte buffer — the Mach-O reader's ByteReader.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A window onto raw bytes with the same contract as `ByteReader`: every read returns `nil`
/// rather than trapping when the requested span leaves the window. It reads through an
/// `UnsafeRawBufferPointer` instead of subscripting `Data`, because the Mach-O reader walks
/// hundreds of thousands of symbol entries and a per-byte `Data` subscript costs too much.
///
/// Offsets are relative to the window. `window(_:_:)` narrows to a sub-range (a load command,
/// a slice) so a decoder cannot read past the structure it was handed.
struct BoundedBytes {
    /// The bytes visible through this window.
    let raw: UnsafeRawBufferPointer
    /// True when multi-byte fields are stored big-endian.
    let bigEndian: Bool

    /// Number of bytes in the window.
    var count: Int { raw.count }

    /// True when `length` bytes starting at `offset` lie inside the window. Written so that no
    /// sum can overflow, whatever a hostile file puts in `offset` or `length`.
    func contains(_ offset: Int, _ length: Int) -> Bool {
        offset >= 0 && length >= 0 && offset <= raw.count && length <= raw.count - offset
    }

    /// The sub-window `offset ..< offset + length`, or `nil` when it does not fit.
    func window(_ offset: Int, _ length: Int) -> BoundedBytes? {
        guard contains(offset, length) else { return nil }
        return BoundedBytes(raw: UnsafeRawBufferPointer(rebasing: raw[offset..<(offset + length)]), bigEndian: bigEndian)
    }

    /// The same bytes read with another byte order.
    func withByteOrder(bigEndian: Bool) -> BoundedBytes { BoundedBytes(raw: raw, bigEndian: bigEndian) }

    /// The byte at `offset`, or `nil` out of range.
    func u8(_ offset: Int) -> UInt8? {
        guard contains(offset, 1) else { return nil }
        return raw[offset]
    }

    /// The `UInt16` at `offset`, or `nil` out of range.
    func u16(_ offset: Int) -> UInt16? {
        guard contains(offset, 2) else { return nil }
        let v = raw.loadUnaligned(fromByteOffset: offset, as: UInt16.self)
        return bigEndian ? UInt16(bigEndian: v) : UInt16(littleEndian: v)
    }

    /// The `UInt32` at `offset`, or `nil` out of range.
    func u32(_ offset: Int) -> UInt32? {
        guard contains(offset, 4) else { return nil }
        let v = raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self)
        return bigEndian ? UInt32(bigEndian: v) : UInt32(littleEndian: v)
    }

    /// The `UInt64` at `offset`, or `nil` out of range.
    func u64(_ offset: Int) -> UInt64? {
        guard contains(offset, 8) else { return nil }
        let v = raw.loadUnaligned(fromByteOffset: offset, as: UInt64.self)
        return bigEndian ? UInt64(bigEndian: v) : UInt64(littleEndian: v)
    }

    /// A pointer-sized field: 8 bytes when `wide`, else 4 bytes widened to 64 bits.
    func word(_ offset: Int, wide: Bool) -> UInt64? {
        wide ? u64(offset) : u32(offset).map(UInt64.init)
    }

    /// A fixed-width name field such as `segname[16]`: the bytes up to the first NUL, or all of
    /// them when the field is full. `nil` when the field does not fit.
    func fixedString(_ offset: Int, _ length: Int) -> String? {
        guard contains(offset, length) else { return nil }
        return Self.decode(raw[offset..<(offset + length)])
    }

    /// The NUL-terminated string at `offset`, read no further than the window's end or
    /// `maxLength` bytes, whichever comes first. A string that hits either limit without a NUL
    /// is returned as far as it was read. `nil` when `offset` is outside the window.
    func cString(_ offset: Int, maxLength: Int) -> String? {
        guard offset >= 0, offset < raw.count else { return nil }
        let end = offset + min(maxLength, raw.count - offset)
        return Self.decode(raw[offset..<end])
    }

    /// UTF-8 decoding (with repair) of `bytes` up to their first NUL.
    private static func decode(_ bytes: Slice<UnsafeRawBufferPointer>) -> String {
        let stop = bytes.firstIndex(of: 0) ?? bytes.endIndex
        return String(decoding: UnsafeRawBufferPointer(rebasing: bytes[bytes.startIndex..<stop]), as: UTF8.self)
    }
}
