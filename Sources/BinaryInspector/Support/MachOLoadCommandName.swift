//
//  MachOLoadCommandName.swift
//  BinaryInspector
//
//  The <mach-o/loader.h> constant name of a load command number.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Names load commands as `otool -l` prints them.
public enum MachOLoadCommandName {

    /// `LC_REQ_DYLD`: set on commands dyld must understand to load the image.
    public static let requiresDyldBit: UInt32 = 0x8000_0000

    /// The constant for `command` (`"LC_SEGMENT_64"`, `"LC_MAIN"`, …). The `LC_REQ_DYLD` bit is
    /// part of the match, so `0x22` is `"LC_DYLD_INFO"` and `0x80000022` is `"LC_DYLD_INFO_ONLY"`.
    /// A number this table does not know keeps its value in hex: `"0x3b"`, or `"LC_REQ_DYLD|0x3b"`
    /// when the bit is set.
    public static func name(for command: UInt32) -> String {
        if let known = names[command] { return known }
        let low = command & ~requiresDyldBit
        let hex = "0x" + String(low, radix: 16)
        return command & requiresDyldBit != 0 ? "LC_REQ_DYLD|" + hex : hex
    }

    /// Every command in `<mach-o/loader.h>` as of the macOS 27 SDK.
    private static let names: [UInt32: String] = [
        0x1: "LC_SEGMENT", 0x2: "LC_SYMTAB", 0x3: "LC_SYMSEG", 0x4: "LC_THREAD", 0x5: "LC_UNIXTHREAD",
        0x6: "LC_LOADFVMLIB", 0x7: "LC_IDFVMLIB", 0x8: "LC_IDENT", 0x9: "LC_FVMFILE", 0xA: "LC_PREPAGE",
        0xB: "LC_DYSYMTAB", 0xC: "LC_LOAD_DYLIB", 0xD: "LC_ID_DYLIB", 0xE: "LC_LOAD_DYLINKER", 0xF: "LC_ID_DYLINKER",
        0x10: "LC_PREBOUND_DYLIB", 0x11: "LC_ROUTINES", 0x12: "LC_SUB_FRAMEWORK", 0x13: "LC_SUB_UMBRELLA",
        0x14: "LC_SUB_CLIENT", 0x15: "LC_SUB_LIBRARY", 0x16: "LC_TWOLEVEL_HINTS", 0x17: "LC_PREBIND_CKSUM",
        0x8000_0018: "LC_LOAD_WEAK_DYLIB", 0x19: "LC_SEGMENT_64", 0x1A: "LC_ROUTINES_64", 0x1B: "LC_UUID",
        0x8000_001C: "LC_RPATH", 0x1D: "LC_CODE_SIGNATURE", 0x1E: "LC_SEGMENT_SPLIT_INFO", 0x8000_001F: "LC_REEXPORT_DYLIB",
        0x20: "LC_LAZY_LOAD_DYLIB", 0x21: "LC_ENCRYPTION_INFO", 0x22: "LC_DYLD_INFO", 0x8000_0022: "LC_DYLD_INFO_ONLY",
        0x8000_0023: "LC_LOAD_UPWARD_DYLIB", 0x24: "LC_VERSION_MIN_MACOSX", 0x25: "LC_VERSION_MIN_IPHONEOS",
        0x26: "LC_FUNCTION_STARTS", 0x27: "LC_DYLD_ENVIRONMENT", 0x8000_0028: "LC_MAIN", 0x29: "LC_DATA_IN_CODE",
        0x2A: "LC_SOURCE_VERSION", 0x2B: "LC_DYLIB_CODE_SIGN_DRS", 0x2C: "LC_ENCRYPTION_INFO_64", 0x2D: "LC_LINKER_OPTION",
        0x2E: "LC_LINKER_OPTIMIZATION_HINT", 0x2F: "LC_VERSION_MIN_TVOS", 0x30: "LC_VERSION_MIN_WATCHOS", 0x31: "LC_NOTE",
        0x32: "LC_BUILD_VERSION", 0x8000_0033: "LC_DYLD_EXPORTS_TRIE", 0x8000_0034: "LC_DYLD_CHAINED_FIXUPS",
        0x8000_0035: "LC_FILESET_ENTRY", 0x36: "LC_ATOM_INFO", 0x37: "LC_FUNCTION_VARIANTS", 0x38: "LC_FUNCTION_VARIANT_FIXUPS",
        0x39: "LC_TARGET_TRIPLE", 0x3A: "LC_LAZY_LOAD_DYLIB_INFO",
    ]
}
