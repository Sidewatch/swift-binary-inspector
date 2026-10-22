//
//  MachOSymbolTable.swift
//  BinaryInspector
//
//  The symbols read from one image, and whether the read stopped short.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The result of ``MachOParser/symbols(in:image:limit:)``.
public struct MachOSymbolTable: Equatable, Sendable {
    /// The symbols, in table order.
    public let symbols: [MachOSymbol]
    /// `nsyms` as the image declares it.
    public let declaredCount: Int
    /// True when fewer than `declaredCount` symbols were returned: the limit was reached or the
    /// table runs past the end of the slice. A caller must say so rather than imply the list is complete.
    public let truncated: Bool

    /// Creates a symbol-table result.
    public init(symbols: [MachOSymbol], declaredCount: Int, truncated: Bool) {
        self.symbols = symbols
        self.declaredCount = declaredCount
        self.truncated = truncated
    }

    /// The empty result, for an image without `LC_SYMTAB`.
    public static let empty = MachOSymbolTable(symbols: [], declaredCount: 0, truncated: false)
}
