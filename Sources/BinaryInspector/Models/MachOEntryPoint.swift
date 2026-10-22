//
//  MachOEntryPoint.swift
//  BinaryInspector
//
//  Where an executable starts: the LC_MAIN command.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// An `entry_point_command` (`LC_MAIN`).
public struct MachOEntryPoint: Equatable, Hashable, Sendable {
    /// Absolute file offset of `main`: the command's `entryoff` plus the slice offset.
    public let fileOffset: UInt64
    /// `stacksize`: the initial stack size requested, or 0 for the default.
    public let stackSize: UInt64

    /// Creates an entry-point record.
    public init(fileOffset: UInt64, stackSize: UInt64) {
        self.fileOffset = fileOffset
        self.stackSize = stackSize
    }
}
