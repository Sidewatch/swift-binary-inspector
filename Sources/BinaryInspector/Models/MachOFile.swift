//
//  MachOFile.swift
//  BinaryInspector
//
//  A whole Mach-O file, thin or universal, as a list of slices.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The result of ``MachOParser/parse(_:)``. A thin file is one slice covering the whole file;
/// a universal file has one slice per `fat_arch` entry.
public struct MachOFile: Equatable, Sendable {
    /// True for a universal (fat) file.
    public let isUniversal: Bool
    /// True when the universal header uses 64-bit `fat_arch_64` entries (magic `0xCAFEBABF`).
    public let usesFat64: Bool
    /// The slices, in header order.
    public let slices: [MachOSlice]
    /// Problems with the universal header or with whole slices. Problems inside an image are on
    /// that image's ``MachOImage/issues``.
    public let issues: [MachOIssue]

    /// Creates a file.
    public init(isUniversal: Bool, usesFat64: Bool, slices: [MachOSlice], issues: [MachOIssue]) {
        self.isUniversal = isUniversal
        self.usesFat64 = usesFat64
        self.slices = slices
        self.issues = issues
    }

    /// The images of every slice that has one, in slice order.
    public var images: [MachOImage] { slices.compactMap(\.image) }
}
