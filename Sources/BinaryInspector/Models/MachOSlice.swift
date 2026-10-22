//
//  MachOSlice.swift
//  BinaryInspector
//
//  One architecture slice of a Mach-O file: where it sits and the image inside it.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A `fat_arch` / `fat_arch_64` entry of a universal file, or the one implied slice of a thin
/// file (offset 0, the whole file, the CPU from the image header).
public struct MachOSlice: Equatable, Sendable {
    /// Position in the universal header, from 0.
    public let index: Int
    /// `cputype` as the slice entry records it.
    public let cpuType: Int32
    /// `cpusubtype` as the slice entry records it, feature bits included.
    public let cpuSubtype: Int32
    /// The architecture as `lipo -archs` names it, or `nil` when unknown.
    public let architectureName: String?
    /// Absolute file offset of the slice.
    public let offset: UInt64
    /// The slice's length as declared.
    public let size: UInt64
    /// `align` as stored: a power of two (14 means 16 KiB). 0 for a thin file.
    public let alignment: UInt32
    /// The image in the slice, or `nil` when the slice lies outside the file or is not a Mach-O
    /// image (the file's ``MachOFile/issues`` says which).
    public let image: MachOImage?

    /// Creates a slice.
    public init(
        index: Int, cpuType: Int32, cpuSubtype: Int32, architectureName: String?, offset: UInt64, size: UInt64, alignment: UInt32,
        image: MachOImage?
    ) {
        self.index = index
        self.cpuType = cpuType
        self.cpuSubtype = cpuSubtype
        self.architectureName = architectureName
        self.offset = offset
        self.size = size
        self.alignment = alignment
        self.image = image
    }
}
