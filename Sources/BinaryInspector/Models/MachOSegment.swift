//
//  MachOSegment.swift
//  BinaryInspector
//
//  One segment of a Mach-O image (LC_SEGMENT or LC_SEGMENT_64) and its sections.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A segment command, 32- or 64-bit, with the sections it declares.
///
/// The first `fileSize` bytes of the segment's memory come from the file; the rest of `vmSize`
/// is zero-filled. ``MachOImage/fileOffset(forAddress:)`` maps only that file-backed part.
public struct MachOSegment: Equatable, Hashable, Sendable {
    /// `segname`, e.g. `"__TEXT"`. Empty for the single segment of an object file.
    public let name: String
    /// `vmaddr`: the segment's first virtual address.
    public let vmAddress: UInt64
    /// `vmsize`: bytes of memory the segment occupies.
    public let vmSize: UInt64
    /// Absolute file offset of the segment's bytes: `fileoff` plus the slice offset.
    public let fileOffset: UInt64
    /// `filesize`: bytes the segment takes from the file.
    public let fileSize: UInt64
    /// `maxprot`: the most permissive VM protection allowed (r=1, w=2, x=4).
    public let maxProtection: Int32
    /// `initprot`: the VM protection the segment starts with.
    public let initialProtection: Int32
    /// The segment `flags` (`SG_PROTECTED_VERSION_1`, `SG_READ_ONLY`, …).
    public let flags: UInt32
    /// The sections the command declares, in file order. Never more than the command's size
    /// can hold, whatever `nsects` says.
    public let sections: [MachOSection]

    /// Creates a segment.
    public init(
        name: String, vmAddress: UInt64, vmSize: UInt64, fileOffset: UInt64, fileSize: UInt64,
        maxProtection: Int32, initialProtection: Int32, flags: UInt32, sections: [MachOSection]
    ) {
        self.name = name
        self.vmAddress = vmAddress
        self.vmSize = vmSize
        self.fileOffset = fileOffset
        self.fileSize = fileSize
        self.maxProtection = maxProtection
        self.initialProtection = initialProtection
        self.flags = flags
        self.sections = sections
    }
}
