//
//  MachOSymbolTableLocation.swift
//  BinaryInspector
//
//  Where an image's symbol and string tables live: the LC_SYMTAB command.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A `symtab_command`. The symbols themselves are read on demand by
/// ``MachOParser/symbols(in:image:limit:)``, so parsing a file never pays for them.
public struct MachOSymbolTableLocation: Equatable, Hashable, Sendable {
    /// Absolute file offset of the first `nlist` entry: `symoff` plus the slice offset.
    public let symbolsOffset: UInt64
    /// `nsyms` as declared.
    public let symbolCount: UInt32
    /// Absolute file offset of the string table: `stroff` plus the slice offset.
    public let stringsOffset: UInt64
    /// `strsize`: the string table's length in bytes.
    public let stringsSize: UInt32

    /// Creates a symbol-table location.
    public init(symbolsOffset: UInt64, symbolCount: UInt32, stringsOffset: UInt64, stringsSize: UInt32) {
        self.symbolsOffset = symbolsOffset
        self.symbolCount = symbolCount
        self.stringsOffset = stringsOffset
        self.stringsSize = stringsSize
    }
}
