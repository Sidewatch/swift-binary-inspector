//
//  MachOEncryptionInfo.swift
//  BinaryInspector
//
//  The encrypted range of an image: LC_ENCRYPTION_INFO or LC_ENCRYPTION_INFO_64.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An `encryption_info_command` / `encryption_info_command_64`.
public struct MachOEncryptionInfo: Equatable, Hashable, Sendable {
    /// Absolute file offset of the encrypted range: `cryptoff` plus the slice offset.
    public let fileOffset: UInt64
    /// `cryptsize`: the encrypted range's length in bytes.
    public let size: UInt32
    /// `cryptid`: 0 when the range is not (or no longer) encrypted, otherwise the encryption system.
    public let cryptID: UInt32

    /// Creates an encryption record.
    public init(fileOffset: UInt64, size: UInt32, cryptID: UInt32) {
        self.fileOffset = fileOffset
        self.size = size
        self.cryptID = cryptID
    }

    /// True when `cryptID` is non-zero: the range is encrypted on disk.
    public var isEncrypted: Bool { cryptID != 0 }
}
