//
//  MachOArchitecture.swift
//  BinaryInspector
//
//  The lipo-style name of a Mach-O cputype/cpusubtype pair.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// Names architectures the way `lipo -archs` prints them.
public enum MachOArchitecture {

    /// `CPU_SUBTYPE_MASK`: the high byte of `cpusubtype` carries feature flags (the arm64e
    /// pointer-authentication ABI version, x86 `LIB64`), not the subtype.
    public static let subtypeFeatureMask: UInt32 = 0xFF00_0000

    /// The name of `cpuType`/`cpuSubtype` (`"arm64"`, `"arm64e"`, `"x86_64"`, `"x86_64h"`, `"i386"`,
    /// `"armv7k"`, `"arm64_32"`, …), or `nil` for a pair this table does not know. The subtype's
    /// feature bits are masked off first, so an arm64e slice with a pointer-authentication
    /// version is still `"arm64e"`.
    public static func name(cpuType: Int32, cpuSubtype: Int32) -> String? {
        let subtype = UInt32(bitPattern: cpuSubtype) & ~subtypeFeatureMask
        switch UInt32(bitPattern: cpuType) {
        case 0x0100_000C: return arm64Names[subtype]
        case 0x0100_0007: return subtype == 8 ? "x86_64h" : subtype == 3 ? "x86_64" : nil
        case 0x0000_0007: return subtype == 3 ? "i386" : nil
        case 0x0200_000C: return subtype <= 1 ? "arm64_32" : nil
        case 0x0000_000C: return armNames[subtype]
        case 0x0000_0012: return "ppc"
        case 0x0100_0012: return "ppc64"
        default: return nil
        }
    }

    /// `CPU_SUBTYPE_ARM64_*` names.
    private static let arm64Names: [UInt32: String] = [0: "arm64", 1: "arm64v8", 2: "arm64e", 3: "arm64.x1", 12: "arm64e.x1"]

    /// `CPU_SUBTYPE_ARM_*` names.
    private static let armNames: [UInt32: String] = [
        0: "arm", 5: "armv4t", 6: "armv6", 7: "armv5", 8: "xscale", 9: "armv7", 10: "armv7f", 11: "armv7s", 12: "armv7k",
        13: "armv8", 14: "armv6m", 15: "armv7m", 16: "armv7em",
    ]
}
