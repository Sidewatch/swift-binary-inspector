//
//  MachOImageReader.swift
//  BinaryInspector
//
//  Reads one Mach-O header and walks its load commands.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// The thin-image half of the Mach-O reader: the `mach_header` and the walk over the load
/// commands that follow it. Each command is handed to `MachOCommandDecoder` already narrowed
/// to its own `cmdsize` bytes.
enum MachOImageReader {

    /// The four header magics, as a little-endian read of the first four bytes sees them.
    private static let magics: [UInt32: (is64: Bool, bigEndian: Bool)] = [
        0xFEED_FACE: (false, false),  // MH_MAGIC
        0xFEED_FACF: (true, false),  // MH_MAGIC_64
        0xCEFA_EDFE: (false, true),  // MH_CIGAM
        0xCFFA_EDFE: (true, true),  // MH_CIGAM_64
    ]

    /// True when `bytes` starts with one of the thin-image magics.
    static func hasMagic(_ bytes: BoundedBytes) -> Bool {
        bytes.withByteOrder(bigEndian: false).u32(0).map { magics[$0] != nil } ?? false
    }

    /// The image whose bytes are `slice`, which starts at absolute file offset `sliceStart`.
    /// `nil` when `slice` does not start with a Mach-O magic or is too short for the header.
    static func read(_ slice: BoundedBytes, sliceStart: Int) -> MachOImage? {
        guard let magic = slice.withByteOrder(bigEndian: false).u32(0), let form = magics[magic] else { return nil }
        let bytes = slice.withByteOrder(bigEndian: form.bigEndian)
        let headerSize = form.is64 ? 32 : 28
        guard bytes.contains(0, headerSize), let cpuType = bytes.u32(4), let cpuSubtype = bytes.u32(8), let fileType = bytes.u32(12),
            let commandCount = bytes.u32(16), let commandsSize = bytes.u32(20), let flags = bytes.u32(24)
        else { return nil }
        var decoder = MachOCommandDecoder(slice: bytes, sliceStart: sliceStart)
        walkCommands(
            in: bytes, headerSize: headerSize, declaredCount: commandCount, declaredSize: commandsSize, decoder: &decoder)
        let type = Int32(bitPattern: cpuType), subtype = Int32(bitPattern: cpuSubtype)
        return decoder.image(
            sliceRange: sliceStart..<(sliceStart + bytes.count), is64Bit: form.is64, isBigEndian: form.bigEndian,
            cpuType: type, cpuSubtype: subtype, architectureName: MachOArchitecture.name(cpuType: type, cpuSubtype: subtype),
            fileType: fileType, commandCount: commandCount, commandsSize: commandsSize, flags: flags)
    }

    /// Walk the load commands. The area is `sizeofcmds` bytes after the header, cut to the
    /// bytes present; every command must be at least 8 bytes and fit inside it, so the walk
    /// takes at most one step per 8 bytes whatever `ncmds` claims.
    private static func walkCommands(
        in bytes: BoundedBytes, headerSize: Int, declaredCount: UInt32, declaredSize: UInt32, decoder: inout MachOCommandDecoder
    ) {
        let available = bytes.count - headerSize
        if Int(declaredSize) > available { decoder.issues.append(.commandsExceedSlice(declared: declaredSize, available: available)) }
        guard let area = bytes.window(headerSize, min(Int(declaredSize), available)) else { return }
        var cursor = 0
        var index = 0
        while index < Int(declaredCount) {
            guard let command = area.u32(cursor), let size = area.u32(cursor + 4) else {
                decoder.issues.append(.commandsTruncated(declared: declaredCount, read: index))
                return
            }
            let fileOffset = decoder.sliceStart + headerSize + cursor
            guard size >= 8, let body = area.window(cursor, Int(size)) else {
                decoder.issues.append(.badCommandSize(index: index, fileOffset: fileOffset, size: size))
                return
            }
            decoder.loadCommands.append(
                MachOLoadCommand(
                    index: index, command: command, name: MachOLoadCommandName.name(for: command), size: size, fileOffset: fileOffset))
            decoder.decode(command, body: body, index: index)
            cursor += Int(size)
            index += 1
        }
    }
}
