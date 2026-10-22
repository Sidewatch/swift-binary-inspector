//
//  MachOSymbolKind.swift
//  BinaryInspector
//
//  The N_TYPE bits of a non-debug Mach-O symbol.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The `N_TYPE` field (`n_type & 0x0E`) of a symbol that is not a debug entry.
public enum MachOSymbolKind: UInt8, Sendable, CaseIterable {
    /// `N_UNDF`: undefined — supplied by another image (or a common symbol when the value is non-zero).
    case undefined = 0x0
    /// `N_ABS`: an absolute value, not relocated.
    case absolute = 0x2
    /// `N_INDR`: an alias for another symbol.
    case indirect = 0xA
    /// `N_PBUD`: undefined, but prebound to an address.
    case prebound = 0xC
    /// `N_SECT`: defined in the section numbered `n_sect`.
    case section = 0xE
}
