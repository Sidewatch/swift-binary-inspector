//
//  MachOImage.swift
//  BinaryInspector
//
//  One Mach-O image — a thin file, or one slice of a universal file — and everything its load
//  commands say about it.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A parsed `mach_header` / `mach_header_64` and its load commands.
///
/// Every file offset here is absolute in the file the image was parsed from: for a slice of a
/// universal binary the slice offset is already added, so an offset can be used to index the
/// original `Data` directly. Header fields are kept raw for the caller to name.
public struct MachOImage: Equatable, Sendable {
    /// The bytes of the file this image occupies (the whole file for a thin image).
    public let sliceRange: Range<Int>
    /// True for `MH_MAGIC_64` (64-bit header and commands).
    public let is64Bit: Bool
    /// True when the image's fields are big-endian (`MH_CIGAM` / `MH_CIGAM_64` read on a little-endian Mac).
    public let isBigEndian: Bool
    /// `cputype` (`CPU_TYPE_ARM64` is 0x0100000C, `CPU_TYPE_X86_64` 0x01000007).
    public let cpuType: Int32
    /// `cpusubtype` as stored, feature bits included; mask with `0x00FFFFFF` for the subtype proper.
    public let cpuSubtype: Int32
    /// The architecture as `lipo` names it (`"arm64"`, `"arm64e"`, `"x86_64"`, …), or `nil` when
    /// the pair is not one ``MachOArchitecture`` knows.
    public let architectureName: String?
    /// `filetype`: 1 object, 2 executable, 6 dylib, 7 dylinker, 8 bundle, 10 dSYM, ….
    public let fileType: UInt32
    /// `ncmds` as declared.
    public let commandCount: UInt32
    /// `sizeofcmds` as declared.
    public let commandsSize: UInt32
    /// The header `flags` (`MH_PIE`, `MH_TWOLEVEL`, …).
    public let flags: UInt32
    /// Every load command read, in order.
    public let loadCommands: [MachOLoadCommand]
    /// Every `LC_SEGMENT` / `LC_SEGMENT_64`, in order.
    public let segments: [MachOSegment]
    /// The libraries the image links (every dylib command except `LC_ID_DYLIB`), in order.
    public let dylibs: [MachODylib]
    /// The image's own install name (`LC_ID_DYLIB`), present for dylibs and frameworks.
    public let installName: MachODylib?
    /// Every `LC_RPATH` path, in order.
    public let rpaths: [String]
    /// `LC_UUID`.
    public let uuid: UUID?
    /// `LC_BUILD_VERSION` and `LC_VERSION_MIN_*` commands, in order.
    public let buildVersions: [MachOBuildVersion]
    /// `LC_MAIN`.
    public let entryPoint: MachOEntryPoint?
    /// `LC_CODE_SIGNATURE`.
    public let codeSignature: MachOCodeSignature?
    /// `LC_ENCRYPTION_INFO` / `LC_ENCRYPTION_INFO_64`.
    public let encryption: MachOEncryptionInfo?
    /// `LC_SYMTAB`: where the symbols are. Read them with ``MachOParser/symbols(in:image:limit:)``.
    public let symbolTable: MachOSymbolTableLocation?
    /// What was malformed and skipped. Empty for a well-formed image.
    public let issues: [MachOIssue]

    /// Creates an image. Everything after `flags` defaults to empty.
    public init(
        sliceRange: Range<Int>, is64Bit: Bool, isBigEndian: Bool, cpuType: Int32, cpuSubtype: Int32, architectureName: String?,
        fileType: UInt32, commandCount: UInt32, commandsSize: UInt32, flags: UInt32,
        loadCommands: [MachOLoadCommand] = [], segments: [MachOSegment] = [], dylibs: [MachODylib] = [],
        installName: MachODylib? = nil, rpaths: [String] = [], uuid: UUID? = nil, buildVersions: [MachOBuildVersion] = [],
        entryPoint: MachOEntryPoint? = nil, codeSignature: MachOCodeSignature? = nil, encryption: MachOEncryptionInfo? = nil,
        symbolTable: MachOSymbolTableLocation? = nil, issues: [MachOIssue] = []
    ) {
        self.sliceRange = sliceRange
        self.is64Bit = is64Bit
        self.isBigEndian = isBigEndian
        self.cpuType = cpuType
        self.cpuSubtype = cpuSubtype
        self.architectureName = architectureName
        self.fileType = fileType
        self.commandCount = commandCount
        self.commandsSize = commandsSize
        self.flags = flags
        self.loadCommands = loadCommands
        self.segments = segments
        self.dylibs = dylibs
        self.installName = installName
        self.rpaths = rpaths
        self.uuid = uuid
        self.buildVersions = buildVersions
        self.entryPoint = entryPoint
        self.codeSignature = codeSignature
        self.encryption = encryption
        self.symbolTable = symbolTable
        self.issues = issues
    }

    /// True when the image has an `LC_CODE_SIGNATURE` whose range lies inside its slice. This
    /// says a signature is present, not that it is valid.
    public var isSigned: Bool { codeSignature?.isWithinSlice == true }
}
