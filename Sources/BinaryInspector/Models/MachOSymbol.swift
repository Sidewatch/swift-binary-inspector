//
//  MachOSymbol.swift
//  BinaryInspector
//
//  One nlist entry of a Mach-O symbol table, with its type byte decoded.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An `nlist` / `nlist_64` entry.
public struct MachOSymbol: Equatable, Hashable, Sendable {
    /// The name from the string table, or `nil` when `n_strx` points outside it.
    public let name: String?
    /// `n_type` as stored.
    public let type: UInt8
    /// `n_sect`: the 1-based section number for a section-defined symbol, 0 (`NO_SECT`) otherwise.
    public let sectionNumber: UInt8
    /// `n_desc`: reference flags, weak/lazy bits and the two-level-namespace library ordinal.
    public let descriptor: UInt16
    /// `n_value`: an address for defined symbols, a size for common symbols, 0 for undefined ones.
    public let value: UInt64

    /// Creates a symbol.
    public init(name: String?, type: UInt8, sectionNumber: UInt8, descriptor: UInt16, value: UInt64) {
        self.name = name
        self.type = type
        self.sectionNumber = sectionNumber
        self.descriptor = descriptor
        self.value = value
    }

    /// True for a debugger (stab) entry: any of the `N_STAB` bits (0xE0) set. Such an entry's
    /// type byte is a stab code, so ``kind`` is `nil`.
    public var isDebug: Bool { type & 0xE0 != 0 }
    /// `N_EXT`: visible outside the image.
    public var isExternal: Bool { !isDebug && type & 0x01 != 0 }
    /// `N_PEXT`: a private external — was external, and was made local by the static linker.
    public var isPrivateExternal: Bool { !isDebug && type & 0x10 != 0 }
    /// The `N_TYPE` bits decoded, or `nil` for a debug entry or an undefined bit pattern.
    public var kind: MachOSymbolKind? { isDebug ? nil : MachOSymbolKind(rawValue: type & 0x0E) }
}
