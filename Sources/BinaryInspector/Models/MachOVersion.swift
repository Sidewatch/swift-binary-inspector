//
//  MachOVersion.swift
//  BinaryInspector
//
//  A version number packed into 32 bits the Mach-O way: X.Y.Z as xxxx.yy.zz.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A version packed into one 32-bit field as `xxxx.yy.zz` — 16 bits of major, 8 of minor and 8
/// of patch. Dylib current/compatibility versions, the minimum OS and SDK of a build version
/// command, and build-tool versions all use this encoding.
public struct MachOVersion: Equatable, Hashable, Sendable, CustomStringConvertible {
    /// The packed value as stored in the file.
    public let rawValue: UInt32

    /// Wraps a packed value.
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    /// The top 16 bits.
    public var major: Int { Int(rawValue >> 16) }
    /// Bits 8–15.
    public var minor: Int { Int((rawValue >> 8) & 0xFF) }
    /// The low 8 bits.
    public var patch: Int { Int(rawValue & 0xFF) }

    /// `"major.minor.patch"`, always three parts (`"1.0.0"`), as `otool -L` prints dylib versions.
    public var description: String { "\(major).\(minor).\(patch)" }
}
