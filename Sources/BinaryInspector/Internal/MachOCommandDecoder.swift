//
//  MachOCommandDecoder.swift
//  BinaryInspector
//
//  Decodes the load commands the parser understands into an image's typed fields.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Collects one image's load commands as `MachOImageReader` walks them. Each `decode` call gets
/// a command's bytes already narrowed to its `cmdsize`, so no read here can leave the command; a
/// command too short for its structure is recorded as an issue and skipped. Offsets in the
/// commands are relative to the slice and are made absolute with `absolute(_:)`.
struct MachOCommandDecoder {
    /// The slice's bytes, in the image's byte order.
    let slice: BoundedBytes
    /// Absolute file offset of the slice.
    let sliceStart: Int

    var loadCommands: [MachOLoadCommand] = []
    var segments: [MachOSegment] = []
    var dylibs: [MachODylib] = []
    var installName: MachODylib?
    var rpaths: [String] = []
    var uuid: UUID?
    var buildVersions: [MachOBuildVersion] = []
    var entryPoint: MachOEntryPoint?
    var codeSignature: MachOCodeSignature?
    var encryption: MachOEncryptionInfo?
    var symbolTable: MachOSymbolTableLocation?
    var issues: [MachOIssue] = []

    /// The longest string read from a command. Paths are far shorter (`PATH_MAX` is 1024); the
    /// cap only matters for a hostile command several megabytes long with no NUL.
    static let maxStringLength = 65_536

    init(slice: BoundedBytes, sliceStart: Int) {
        self.slice = slice
        self.sliceStart = sliceStart
    }

    /// Decode command number `index`, whose `cmd` is `command` and whose bytes (header included) are `body`.
    mutating func decode(_ command: UInt32, body: BoundedBytes, index: Int) {
        let decoded: Bool
        switch command {
        case 0x1: decoded = decodeSegment(body, wide: false, index: index)
        case 0x19: decoded = decodeSegment(body, wide: true, index: index)
        case 0x2: decoded = decodeSymbolTable(body)
        case 0xD, 0xC, 0x8000_0018, 0x8000_001F, 0x20, 0x8000_0023: decoded = decodeDylib(body, command: command, index: index)
        case 0x8000_001C: decoded = decodeRpath(body, index: index)
        case 0x1B: decoded = decodeUUID(body)
        case 0x32: decoded = decodeBuildVersion(body, index: index)
        case 0x24, 0x25, 0x2F, 0x30: decoded = decodeVersionMin(body, command: command)
        case 0x8000_0028: decoded = decodeMain(body)
        case 0x1D: decoded = decodeCodeSignature(body)
        case 0x21, 0x2C: decoded = decodeEncryption(body)
        default: decoded = true
        }
        if !decoded { issues.append(.commandTooSmall(index: index, command: command)) }
    }

    /// The finished image.
    func image(
        sliceRange: Range<Int>, is64Bit: Bool, isBigEndian: Bool, cpuType: Int32, cpuSubtype: Int32, architectureName: String?,
        fileType: UInt32, commandCount: UInt32, commandsSize: UInt32, flags: UInt32
    ) -> MachOImage {
        MachOImage(
            sliceRange: sliceRange, is64Bit: is64Bit, isBigEndian: isBigEndian, cpuType: cpuType, cpuSubtype: cpuSubtype,
            architectureName: architectureName, fileType: fileType, commandCount: commandCount, commandsSize: commandsSize,
            flags: flags, loadCommands: loadCommands, segments: segments, dylibs: dylibs, installName: installName, rpaths: rpaths,
            uuid: uuid, buildVersions: buildVersions, entryPoint: entryPoint, codeSignature: codeSignature, encryption: encryption,
            symbolTable: symbolTable, issues: issues)
    }

    /// A slice-relative offset made absolute. Saturates instead of overflowing, which only a
    /// hostile 64-bit offset within `sliceStart` of `UInt64.max` could reach.
    func absolute(_ relative: UInt64) -> UInt64 {
        let (sum, overflow) = relative.addingReportingOverflow(UInt64(sliceStart))
        return overflow ? .max : sum
    }

    // MARK: - Segments

    /// `segment_command` (56 bytes, `section` 68) or `segment_command_64` (72 bytes, `section_64` 80).
    private mutating func decodeSegment(_ body: BoundedBytes, wide: Bool, index: Int) -> Bool {
        let headerSize = wide ? 72 : 56, sectionSize = wide ? 80 : 68, w = wide ? 8 : 4
        guard body.contains(0, headerSize), let name = body.fixedString(8, 16), let vmAddress = body.word(24, wide: wide),
            let vmSize = body.word(24 + w, wide: wide), let fileOffset = body.word(24 + 2 * w, wide: wide),
            let fileSize = body.word(24 + 3 * w, wide: wide), let maxProt = body.u32(24 + 4 * w),
            let initProt = body.u32(28 + 4 * w), let declared = body.u32(32 + 4 * w), let flags = body.u32(36 + 4 * w)
        else { return false }
        let fitting = (body.count - headerSize) / sectionSize
        let count = min(Int(declared), fitting)
        if count < declared { issues.append(.sectionsExceedCommand(index: index, declared: declared, read: count)) }
        let sections = (0..<count).compactMap { section(body, at: headerSize + $0 * sectionSize, wide: wide) }
        segments.append(
            MachOSegment(
                name: name, vmAddress: vmAddress, vmSize: vmSize, fileOffset: absolute(fileOffset), fileSize: fileSize,
                maxProtection: Int32(bitPattern: maxProt), initialProtection: Int32(bitPattern: initProt), flags: flags,
                sections: sections))
        return true
    }

    /// One `section` / `section_64` record at `offset` inside a segment command.
    private func section(_ body: BoundedBytes, at offset: Int, wide: Bool) -> MachOSection? {
        let w = wide ? 8 : 4
        guard let name = body.fixedString(offset, 16), let segmentName = body.fixedString(offset + 16, 16),
            let address = body.word(offset + 32, wide: wide), let size = body.word(offset + 32 + w, wide: wide),
            let fileOffset = body.u32(offset + 32 + 2 * w), let alignment = body.u32(offset + 36 + 2 * w),
            let flags = body.u32(offset + 48 + 2 * w)
        else { return nil }
        return MachOSection(
            name: name, segmentName: segmentName, address: address, size: size,
            fileOffset: fileOffset == 0 ? nil : absolute(UInt64(fileOffset)), alignment: alignment, flags: flags)
    }

    // MARK: - Libraries and paths

    /// `dylib_command`: `name` (lc_str), `timestamp`, `current_version`, `compatibility_version`.
    private mutating func decodeDylib(_ body: BoundedBytes, command: UInt32, index: Int) -> Bool {
        guard let nameOffset = body.u32(8), let timestamp = body.u32(12), let current = body.u32(16),
            let compatibility = body.u32(20)
        else { return false }
        guard let path = string(body, at: nameOffset, index: index) else { return true }
        let dylib = MachODylib(
            kind: Self.dylibKind(command), path: path, currentVersion: MachOVersion(rawValue: current),
            compatibilityVersion: MachOVersion(rawValue: compatibility), timestamp: timestamp)
        if dylib.kind == .id {
            if installName == nil { installName = dylib }
        } else {
            dylibs.append(dylib)
        }
        return true
    }

    /// The dylib kind each dylib command number stands for.
    private static func dylibKind(_ command: UInt32) -> MachODylibKind {
        switch command {
        case 0xD: return .id
        case 0x8000_0018: return .weak
        case 0x8000_001F: return .reexport
        case 0x20: return .lazy
        case 0x8000_0023: return .upward
        default: return .load
        }
    }

    /// `rpath_command`: one `path` (lc_str).
    private mutating func decodeRpath(_ body: BoundedBytes, index: Int) -> Bool {
        guard let pathOffset = body.u32(8) else { return false }
        if let path = string(body, at: pathOffset, index: index) { rpaths.append(path) }
        return true
    }

    /// An `lc_str`: a NUL-terminated string at `offset` from the command's start, which must lie
    /// inside the command. `nil` (and an issue) otherwise.
    private mutating func string(_ body: BoundedBytes, at offset: UInt32, index: Int) -> String? {
        guard let value = body.cString(Int(offset), maxLength: Self.maxStringLength) else {
            issues.append(.badStringOffset(index: index))
            return nil
        }
        return value
    }

    // MARK: - Identity and platform

    /// `uuid_command`: 16 bytes after the header.
    private mutating func decodeUUID(_ body: BoundedBytes) -> Bool {
        guard body.contains(8, 16) else { return false }
        let b = (0..<16).map { body.u8(8 + $0) ?? 0 }
        if uuid == nil {
            uuid = UUID(uuid: (b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7], b[8], b[9], b[10], b[11], b[12], b[13], b[14], b[15]))
        }
        return true
    }

    /// `build_version_command`: platform, minos, sdk, ntools, then `ntools` (tool, version) pairs.
    private mutating func decodeBuildVersion(_ body: BoundedBytes, index: Int) -> Bool {
        guard let platform = body.u32(8), let minOS = body.u32(12), let sdk = body.u32(16), let declared = body.u32(20) else {
            return false
        }
        let count = min(Int(declared), (body.count - 24) / 8)
        let tools = (0..<count).compactMap { i -> MachOBuildTool? in
            guard let tool = body.u32(24 + i * 8), let version = body.u32(28 + i * 8) else { return nil }
            return MachOBuildTool(tool: tool, version: MachOVersion(rawValue: version))
        }
        buildVersions.append(
            MachOBuildVersion(
                command: 0x32, platform: platform, minimumOS: MachOVersion(rawValue: minOS), sdk: MachOVersion(rawValue: sdk),
                tools: tools))
        return count == declared
    }

    /// `version_min_command`: version, sdk. The platform is implied by the command.
    private mutating func decodeVersionMin(_ body: BoundedBytes, command: UInt32) -> Bool {
        guard let version = body.u32(8), let sdk = body.u32(12) else { return false }
        let platform: UInt32 = command == 0x24 ? 1 : command == 0x25 ? 2 : command == 0x2F ? 3 : 4
        buildVersions.append(
            MachOBuildVersion(
                command: command, platform: platform, minimumOS: MachOVersion(rawValue: version), sdk: MachOVersion(rawValue: sdk),
                tools: []))
        return true
    }

    // MARK: - Entry, signature, encryption, symbols

    /// `entry_point_command`: entryoff, stacksize.
    private mutating func decodeMain(_ body: BoundedBytes) -> Bool {
        guard let entry = body.u64(8), let stack = body.u64(16) else { return false }
        if entryPoint == nil { entryPoint = MachOEntryPoint(fileOffset: absolute(entry), stackSize: stack) }
        return true
    }

    /// `linkedit_data_command` for `LC_CODE_SIGNATURE`: dataoff, datasize.
    private mutating func decodeCodeSignature(_ body: BoundedBytes) -> Bool {
        guard let offset = body.u32(8), let size = body.u32(12) else { return false }
        if codeSignature == nil {
            let inside = UInt64(offset) + UInt64(size) <= UInt64(slice.count)
            codeSignature = MachOCodeSignature(fileOffset: absolute(UInt64(offset)), size: size, isWithinSlice: inside)
        }
        return true
    }

    /// `encryption_info_command` (and the `_64` form, which only adds padding): cryptoff, cryptsize, cryptid.
    private mutating func decodeEncryption(_ body: BoundedBytes) -> Bool {
        guard let offset = body.u32(8), let size = body.u32(12), let id = body.u32(16) else { return false }
        if encryption == nil { encryption = MachOEncryptionInfo(fileOffset: absolute(UInt64(offset)), size: size, cryptID: id) }
        return true
    }

    /// `symtab_command`: symoff, nsyms, stroff, strsize.
    private mutating func decodeSymbolTable(_ body: BoundedBytes) -> Bool {
        guard let symbols = body.u32(8), let count = body.u32(12), let strings = body.u32(16), let size = body.u32(20) else {
            return false
        }
        if symbolTable == nil {
            symbolTable = MachOSymbolTableLocation(
                symbolsOffset: absolute(UInt64(symbols)), symbolCount: count, stringsOffset: absolute(UInt64(strings)),
                stringsSize: size)
        }
        return true
    }
}
