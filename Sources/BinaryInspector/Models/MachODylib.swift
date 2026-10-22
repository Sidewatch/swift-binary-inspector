//
//  MachODylib.swift
//  BinaryInspector
//
//  A dylib named by a load command: a library the image links, or the image's own install name.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A `dylib_command`: the path of a library and the versions recorded with it.
public struct MachODylib: Equatable, Hashable, Sendable {
    /// Which command named it — a link (`LC_LOAD_DYLIB` and its variants) or the image's own
    /// identity (`LC_ID_DYLIB`).
    public let kind: MachODylibKind
    /// The install name, e.g. `"/usr/lib/libSystem.B.dylib"` or `"@rpath/Example.framework/Example"`.
    public let path: String
    /// The library's current version.
    public let currentVersion: MachOVersion
    /// The oldest version the image is compatible with.
    public let compatibilityVersion: MachOVersion
    /// The build timestamp field (seconds since 1970; usually 2 or 0 in modern binaries).
    public let timestamp: UInt32

    /// Creates a dylib record.
    public init(
        kind: MachODylibKind, path: String, currentVersion: MachOVersion, compatibilityVersion: MachOVersion, timestamp: UInt32
    ) {
        self.kind = kind
        self.path = path
        self.currentVersion = currentVersion
        self.compatibilityVersion = compatibilityVersion
        self.timestamp = timestamp
    }
}
