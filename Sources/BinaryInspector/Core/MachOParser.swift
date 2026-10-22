//
//  MachOParser.swift
//  BinaryInspector
//
//  Reads the structure of a Mach-O file, thin or universal: slices, load commands, segments,
//  sections, linked libraries, platform, signature and symbols.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The Mach-O structure reader. Where ``BinaryFormat`` names a file's format in one line, this
/// reads everything an inspector shows about a Mach-O file.
///
/// Every read is bounds-checked against the bytes actually present. A truncated, corrupt or
/// hostile file never traps, never loops for long and never allocates more than its own size
/// suggests: counts are capped by the bytes that could hold them, and whatever is malformed is
/// skipped and listed in ``MachOFile/issues`` or ``MachOImage/issues`` rather than failing the
/// whole parse.
///
/// `parse(_:)` reads headers and load commands only — a 100 MB universal binary parses in a
/// few milliseconds. Symbols are read separately, on demand, by ``symbols(in:image:limit:)``.
public enum MachOParser {

    /// The default cap on symbols returned by ``symbols(in:image:limit:)``.
    public static let defaultSymbolLimit = 200_000

    /// The structure of `data`, or `nil` when it is not a Mach-O file: neither a thin-image magic
    /// with a complete header, nor a universal header. `0xCAFEBABE` with more than 30 entries is
    /// a Java class file, as ``BinaryFormat`` decides, and gives `nil`.
    ///
    /// Map large files rather than reading them (`Data(contentsOf:options: .alwaysMapped)`): only
    /// the headers and load commands are touched.
    public static func parse(_ data: Data) -> MachOFile? {
        data.withUnsafeBytes { raw in
            let bytes = BoundedBytes(raw: raw, bigEndian: false)
            if MachOImageReader.hasMagic(bytes) { return thin(bytes) }
            return MachOFatReader.read(bytes)
        }
    }

    /// Up to `limit` entries of `image`'s symbol table, in table order, with names from its
    /// string table. `data` must be the file `image` was parsed from. Entries that run past the
    /// slice are not returned, and ``MachOSymbolTable/truncated`` is set whenever fewer than the
    /// declared count come back. An image without `LC_SYMTAB` gives ``MachOSymbolTable/empty``.
    public static func symbols(in data: Data, image: MachOImage, limit: Int = defaultSymbolLimit) -> MachOSymbolTable {
        data.withUnsafeBytes { raw in
            MachOSymbolReader.read(BoundedBytes(raw: raw, bigEndian: false), image: image, limit: limit)
        }
    }

    /// A thin file: one slice covering the whole file.
    private static func thin(_ bytes: BoundedBytes) -> MachOFile? {
        guard let image = MachOImageReader.read(bytes, sliceStart: 0) else { return nil }
        let slice = MachOSlice(
            index: 0, cpuType: image.cpuType, cpuSubtype: image.cpuSubtype, architectureName: image.architectureName, offset: 0,
            size: UInt64(bytes.count), alignment: 0, image: image)
        return MachOFile(isUniversal: false, usesFat64: false, slices: [slice], issues: [])
    }
}
