//
//  MachOCodeSignature.swift
//  BinaryInspector
//
//  Where an image's code signature lives: the LC_CODE_SIGNATURE command.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The `linkedit_data_command` for `LC_CODE_SIGNATURE`. Only the location is read; the
/// signature blob itself is not parsed or verified.
public struct MachOCodeSignature: Equatable, Hashable, Sendable {
    /// Absolute file offset of the signature: `dataoff` plus the slice offset.
    public let fileOffset: UInt64
    /// `datasize`: the signature's length in bytes.
    public let size: UInt32
    /// True when the whole signature lies inside the slice's bytes. A command pointing outside
    /// the slice (a truncated or damaged file) is recorded but does not make the image signed.
    public let isWithinSlice: Bool

    /// Creates a code-signature location.
    public init(fileOffset: UInt64, size: UInt32, isWithinSlice: Bool) {
        self.fileOffset = fileOffset
        self.size = size
        self.isWithinSlice = isWithinSlice
    }
}
