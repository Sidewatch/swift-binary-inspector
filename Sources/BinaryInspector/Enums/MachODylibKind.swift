//
//  MachODylibKind.swift
//  BinaryInspector
//
//  Which load command named a dylib.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The dylib commands, by the command that carried them.
public enum MachODylibKind: String, Sendable, CaseIterable {
    /// `LC_ID_DYLIB`: the image's own install name.
    case id
    /// `LC_LOAD_DYLIB`: an ordinary link.
    case load
    /// `LC_LOAD_WEAK_DYLIB`: the image still loads when the library is missing.
    case weak
    /// `LC_REEXPORT_DYLIB`: linked, and its symbols re-exported as the image's own.
    case reexport
    /// `LC_LAZY_LOAD_DYLIB`: loaded on first use (obsolete).
    case lazy
    /// `LC_LOAD_UPWARD_DYLIB`: an upward link that may form a cycle.
    case upward
}
