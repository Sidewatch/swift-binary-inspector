//
//  MachOImage+Addresses.swift
//  BinaryInspector
//
//  Maps between an image's virtual addresses and absolute file offsets, and finds the segment
//  or section that holds either.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

extension MachOImage {

    /// The absolute file offset that holds the byte at `address`, or `nil` when no segment backs
    /// that address with file bytes: outside every segment, in a segment's zero-fill tail (past
    /// `fileSize`), or in bytes this file does not contain. A segment maps at most `vmSize`
    /// bytes, so a `fileSize` larger than `vmSize` counts only up to `vmSize`.
    public func fileOffset(forAddress address: UInt64) -> Int? {
        for segment in segments where address >= segment.vmAddress {
            let delta = address - segment.vmAddress
            guard delta < Self.mappedLength(segment) else { continue }
            let (offset, overflow) = segment.fileOffset.addingReportingOverflow(delta)
            guard !overflow, offset < UInt64(sliceRange.upperBound) else { continue }
            return Int(offset)
        }
        return nil
    }

    /// The virtual address the byte at absolute file offset `offset` is loaded at, or `nil` when
    /// the offset is outside the image's slice or in no segment's file-backed part (the header
    /// and load commands of an object file, for one, belong to no segment).
    public func address(forFileOffset offset: Int) -> UInt64? {
        guard sliceRange.contains(offset) else { return nil }
        let position = UInt64(offset)
        for segment in segments where position >= segment.fileOffset {
            let delta = position - segment.fileOffset
            guard delta < Self.mappedLength(segment) else { continue }
            let (address, overflow) = segment.vmAddress.addingReportingOverflow(delta)
            if !overflow { return address }
        }
        return nil
    }

    /// The first segment whose memory (`vmAddress ..< vmAddress + vmSize`, zero-fill included)
    /// holds `address`.
    public func segment(containingAddress address: UInt64) -> MachOSegment? {
        segments.first { address >= $0.vmAddress && address - $0.vmAddress < $0.vmSize }
    }

    /// The first section whose `address ..< address + size` holds `address`.
    public func section(containingAddress address: UInt64) -> MachOSection? {
        for segment in segments {
            if let hit = segment.sections.first(where: { address >= $0.address && address - $0.address < $0.size }) { return hit }
        }
        return nil
    }

    /// The first segment whose file-backed bytes hold absolute file offset `offset`.
    public func segment(containingFileOffset offset: Int) -> MachOSegment? {
        guard offset >= 0 else { return nil }
        let position = UInt64(offset)
        return segments.first { position >= $0.fileOffset && position - $0.fileOffset < Self.mappedLength($0) }
    }

    /// The first section with bytes in the file (not zero-fill) whose range holds absolute file
    /// offset `offset`.
    public func section(containingFileOffset offset: Int) -> MachOSection? {
        guard offset >= 0 else { return nil }
        let position = UInt64(offset)
        for segment in segments {
            let hit = segment.sections.first {
                guard let start = $0.fileOffset, !$0.isZeroFill else { return false }
                return position >= start && position - start < $0.size
            }
            if let hit { return hit }
        }
        return nil
    }

    /// The part of `segment` backed by file bytes: `fileSize`, but never more than `vmSize`.
    private static func mappedLength(_ segment: MachOSegment) -> UInt64 { min(segment.fileSize, segment.vmSize) }
}
