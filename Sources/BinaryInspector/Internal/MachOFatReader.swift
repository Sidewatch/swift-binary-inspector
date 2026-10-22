//
//  MachOFatReader.swift
//  BinaryInspector
//
//  Reads a universal (fat) header and parses the image in each slice.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The universal-file half of the Mach-O reader. The fat header is always big-endian:
/// `magic`, `nfat_arch`, then `nfat_arch` entries of `fat_arch` (20 bytes, 32-bit offsets,
/// magic `0xCAFEBABE`) or `fat_arch_64` (32 bytes, 64-bit offsets, magic `0xCAFEBABF`).
enum MachOFatReader {

    /// `FAT_MAGIC`.
    static let fatMagic: UInt32 = 0xCAFE_BABE
    /// `FAT_MAGIC_64`.
    static let fatMagic64: UInt32 = 0xCAFE_BABF
    /// The most slices read. It is also the line `BinaryFormat` draws between a universal
    /// binary and a Java class file, which share `0xCAFEBABE` (a class file's version puts a
    /// number of 45 or more where `nfat_arch` sits). Real files have a handful of slices; the cap
    /// keeps a hostile header from making the reader parse one image thousands of times.
    static let maxSlices = 30

    /// The file's slices, or `nil` when `file` is not a universal header (including the Java
    /// case: `0xCAFEBABE` with more than `maxSlices` entries).
    static func read(_ file: BoundedBytes) -> MachOFile? {
        let header = file.withByteOrder(bigEndian: true)
        guard let magic = header.u32(0), magic == fatMagic || magic == fatMagic64, let declared = header.u32(4) else { return nil }
        let wide = magic == fatMagic64
        if !wide && declared > maxSlices { return nil }
        let entrySize = wide ? 32 : 20
        let fitting = (header.count - 8) / entrySize
        let count = min(Int(declared), fitting, maxSlices)
        var issues: [MachOIssue] = []
        if count < declared { issues.append(.fatHeaderTruncated(declared: declared, read: count)) }
        let slices = (0..<count).map { slice(at: 8 + $0 * entrySize, index: $0, wide: wide, file: header, issues: &issues) }
        return MachOFile(isUniversal: true, usesFat64: wide, slices: slices, issues: issues)
    }

    /// One `fat_arch` / `fat_arch_64` entry at `entry`, with the image its bytes hold.
    private static func slice(at entry: Int, index: Int, wide: Bool, file: BoundedBytes, issues: inout [MachOIssue]) -> MachOSlice {
        let cpuType = Int32(bitPattern: file.u32(entry) ?? 0)
        let cpuSubtype = Int32(bitPattern: file.u32(entry + 4) ?? 0)
        let offset = file.word(entry + 8, wide: wide) ?? 0
        let size = file.word(entry + (wide ? 16 : 12), wide: wide) ?? 0
        let alignment = file.u32(entry + (wide ? 24 : 16)) ?? 0
        let image = sliceImage(index: index, offset: offset, size: size, file: file, issues: &issues)
        return MachOSlice(
            index: index, cpuType: cpuType, cpuSubtype: cpuSubtype,
            architectureName: MachOArchitecture.name(cpuType: cpuType, cpuSubtype: cpuSubtype),
            offset: offset, size: size, alignment: alignment, image: image)
    }

    /// The image in the slice's bytes — clipped to the file when the slice runs past its end.
    private static func sliceImage(index: Int, offset: UInt64, size: UInt64, file: BoundedBytes, issues: inout [MachOIssue]) -> MachOImage?
    {
        guard offset < UInt64(file.count) else {
            issues.append(.sliceOutOfBounds(slice: index))
            return nil
        }
        let start = Int(offset)
        let available = file.count - start
        if size > UInt64(available) { issues.append(.sliceTruncated(slice: index, declared: size, available: available)) }
        let length = Int(min(size, UInt64(available)))
        guard let bytes = file.window(start, length), let image = MachOImageReader.read(bytes, sliceStart: start) else {
            issues.append(.sliceNotMachO(slice: index))
            return nil
        }
        return image
    }
}
