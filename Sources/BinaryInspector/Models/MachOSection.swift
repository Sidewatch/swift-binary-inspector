//
//  MachOSection.swift
//  BinaryInspector
//
//  One section inside a Mach-O segment: name, address range, file position and flags.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A `section` / `section_64` record from a segment command.
public struct MachOSection: Equatable, Hashable, Sendable {
    /// `sectname`, e.g. `"__text"`.
    public let name: String
    /// `segname` as written in the section record, e.g. `"__TEXT"`. Object files put every
    /// section in one unnamed segment, so this can differ from the enclosing segment's name.
    public let segmentName: String
    /// `addr`: the section's first virtual address.
    public let address: UInt64
    /// `size` in bytes.
    public let size: UInt64
    /// Absolute file offset of the section's bytes (the slice offset is already added), or `nil`
    /// when the record's `offset` is 0 — a zero-fill section with no bytes in the file.
    public let fileOffset: UInt64?
    /// `align` as stored: a power of two, so 3 means 8-byte alignment.
    public let alignment: UInt32
    /// The `flags` field: section type in the low byte, attributes above it.
    public let flags: UInt32

    /// Creates a section record.
    public init(
        name: String, segmentName: String, address: UInt64, size: UInt64, fileOffset: UInt64?, alignment: UInt32, flags: UInt32
    ) {
        self.name = name
        self.segmentName = segmentName
        self.address = address
        self.size = size
        self.fileOffset = fileOffset
        self.alignment = alignment
        self.flags = flags
    }

    /// The section type: `flags & 0xFF` (`S_REGULAR` 0, `S_ZEROFILL` 1, `S_CSTRING_LITERALS` 2, …).
    public var type: UInt8 { UInt8(truncatingIfNeeded: flags) }

    /// True for the zero-fill types (`S_ZEROFILL`, `S_GB_ZEROFILL`, `S_THREAD_LOCAL_ZEROFILL`),
    /// whose bytes exist only in memory.
    public var isZeroFill: Bool { type == 0x01 || type == 0x0C || type == 0x12 }
}
