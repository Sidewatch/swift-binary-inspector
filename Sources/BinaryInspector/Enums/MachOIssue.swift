//
//  MachOIssue.swift
//  BinaryInspector
//
//  A malformed part of a Mach-O file that the parser skipped instead of failing.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Something the parser found wrong and stepped around. A damaged file still yields whatever
/// could be read; these say what was left out and why. Values are raw so the caller words them.
public enum MachOIssue: Equatable, Hashable, Sendable {
    /// The universal header declares `declared` slices but only `read` entries fit in the file.
    case fatHeaderTruncated(declared: UInt32, read: Int)
    /// Slice `slice` starts at or past the end of the file; it has no image.
    case sliceOutOfBounds(slice: Int)
    /// Slice `slice` declares `declared` bytes but only `available` are in the file; the image
    /// was parsed from the bytes present.
    case sliceTruncated(slice: Int, declared: UInt64, available: Int)
    /// Slice `slice` does not hold a Mach-O image (a universal static library holds `ar`
    /// archives, for example); it has no image.
    case sliceNotMachO(slice: Int)
    /// `sizeofcmds` (`declared`) runs past the slice; only the `available` bytes were walked.
    case commandsExceedSlice(declared: UInt32, available: Int)
    /// The header declares `declared` load commands but the walk stopped after `read`.
    case commandsTruncated(declared: UInt32, read: Int)
    /// Load command `index` at absolute `fileOffset` has a `cmdsize` below 8 or past the
    /// command area; the walk stopped there.
    case badCommandSize(index: Int, fileOffset: Int, size: UInt32)
    /// Load command `index` (`command`) is shorter than its structure, or than the entries it
    /// declares. It is still listed; whatever did not fit was not decoded.
    case commandTooSmall(index: Int, command: UInt32)
    /// Segment command `index` declares `declared` sections but its size holds only `read`.
    case sectionsExceedCommand(index: Int, declared: UInt32, read: Int)
    /// Load command `index` names a string at an offset outside the command; the string was skipped.
    case badStringOffset(index: Int)
}
