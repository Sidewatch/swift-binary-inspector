//
//  MachOSymbolReader.swift
//  BinaryInspector
//
//  Reads an image's nlist entries and their names from the string table.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The symbol half of the Mach-O reader. Entries are `nlist` (12 bytes) or `nlist_64` (16
/// bytes): `n_strx` u32, `n_type` u8, `n_sect` u8, `n_desc` u16, `n_value` u32 or u64.
enum MachOSymbolReader {

    /// The longest symbol name read. Mangled Swift names run to a few kilobytes; the cap only
    /// matters for a hostile string table with no NUL.
    static let maxNameLength = 65_536

    /// Up to `limit` symbols of `image`, read from `file` (the whole file the image was parsed
    /// from). Both tables are clipped to the image's slice, and a name is read only from inside
    /// the string table.
    static func read(_ file: BoundedBytes, image: MachOImage, limit: Int) -> MachOSymbolTable {
        guard let table = image.symbolTable else { return .empty }
        let declared = Int(table.symbolCount)
        guard let slice = file.window(image.sliceRange.lowerBound, image.sliceRange.count)?.withByteOrder(bigEndian: image.isBigEndian)
        else { return MachOSymbolTable(symbols: [], declaredCount: declared, truncated: declared > 0) }
        let entrySize = image.is64Bit ? 16 : 12
        let start = relative(table.symbolsOffset, in: image, limit: slice.count)
        let count = min(declared, (slice.count - start) / entrySize, max(limit, 0))
        let strings = stringTable(table, in: image, slice: slice)
        var symbols: [MachOSymbol] = []
        symbols.reserveCapacity(count)
        for i in 0..<count {
            let entry = start + i * entrySize
            guard let strx = slice.u32(entry), let type = slice.u8(entry + 4), let section = slice.u8(entry + 5),
                let descriptor = slice.u16(entry + 6), let value = slice.word(entry + 8, wide: image.is64Bit)
            else { break }
            let name = strings.cString(Int(strx), maxLength: maxNameLength)
            symbols.append(MachOSymbol(name: name, type: type, sectionNumber: section, descriptor: descriptor, value: value))
        }
        return MachOSymbolTable(symbols: symbols, declaredCount: declared, truncated: symbols.count < declared)
    }

    /// The string table's bytes, cut to the part inside the slice.
    private static func stringTable(_ table: MachOSymbolTableLocation, in image: MachOImage, slice: BoundedBytes) -> BoundedBytes {
        let start = relative(table.stringsOffset, in: image, limit: slice.count)
        let length = min(Int(table.stringsSize), slice.count - start)
        return slice.window(start, length) ?? BoundedBytes(raw: UnsafeRawBufferPointer(rebasing: slice.raw[0..<0]), bigEndian: false)
    }

    /// An absolute offset made relative to the image's slice, clamped to `0...limit`.
    private static func relative(_ absolute: UInt64, in image: MachOImage, limit: Int) -> Int {
        let base = UInt64(image.sliceRange.lowerBound)
        guard absolute >= base else { return limit }
        return Int(min(absolute - base, UInt64(limit)))
    }
}
