//
//  MachOLoadCommand.swift
//  BinaryInspector
//
//  One load command of a Mach-O image: its number, name, size and where it sits in the file.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// One entry of an image's load-command list, whatever its kind. The commands the parser
/// understands are also decoded into the image's typed fields (segments, dylibs, UUID, …); this
/// row is the uniform list a "Load Commands" table shows.
public struct MachOLoadCommand: Equatable, Hashable, Sendable {
    /// Position in the image's command list, from 0.
    public let index: Int
    /// The `cmd` value as stored, including the `LC_REQ_DYLD` bit when set.
    public let command: UInt32
    /// The constant's name (`"LC_SEGMENT_64"`, `"LC_LOAD_DYLIB"`, …), or the number in hex
    /// (`"0x3b"`, `"LC_REQ_DYLD|0x3b"`) for a command this package does not know. See
    /// ``MachOLoadCommandName``.
    public let name: String
    /// The `cmdsize` value: the command's length in bytes, header included.
    public let size: UInt32
    /// Absolute offset of the command in the file (the slice offset is already added).
    public let fileOffset: Int

    /// Creates a load-command row.
    public init(index: Int, command: UInt32, name: String, size: UInt32, fileOffset: Int) {
        self.index = index
        self.command = command
        self.name = name
        self.size = size
        self.fileOffset = fileOffset
    }

    /// True when the command carries `LC_REQ_DYLD` (0x80000000): dyld must understand it to load the image.
    public var requiresDyld: Bool { command & 0x8000_0000 != 0 }
}
