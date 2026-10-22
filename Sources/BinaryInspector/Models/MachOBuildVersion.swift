//
//  MachOBuildVersion.swift
//  BinaryInspector
//
//  The platform, minimum OS and SDK an image was built for (LC_BUILD_VERSION or LC_VERSION_MIN_*).
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// What an image targets, from either the current `LC_BUILD_VERSION` command or one of the
/// older `LC_VERSION_MIN_*` commands. An image may carry more than one (a zippered Mac
/// Catalyst binary records both macOS and Mac Catalyst).
public struct MachOBuildVersion: Equatable, Hashable, Sendable {
    /// The load command it came from: `LC_BUILD_VERSION` (0x32), `LC_VERSION_MIN_MACOSX` (0x24),
    /// `LC_VERSION_MIN_IPHONEOS` (0x25), `LC_VERSION_MIN_TVOS` (0x2F) or `LC_VERSION_MIN_WATCHOS` (0x30).
    public let command: UInt32
    /// The `PLATFORM_*` constant: 1 macOS, 2 iOS, 3 tvOS, 4 watchOS, 6 Mac Catalyst, 11 visionOS, ….
    /// For a version-min command it is the platform that command implies.
    public let platform: UInt32
    /// The minimum OS version.
    public let minimumOS: MachOVersion
    /// The SDK version it was built against.
    public let sdk: MachOVersion
    /// The tools recorded by `LC_BUILD_VERSION`; always empty for a version-min command.
    public let tools: [MachOBuildTool]

    /// Creates a build-version record.
    public init(command: UInt32, platform: UInt32, minimumOS: MachOVersion, sdk: MachOVersion, tools: [MachOBuildTool]) {
        self.command = command
        self.platform = platform
        self.minimumOS = minimumOS
        self.sdk = sdk
        self.tools = tools
    }
}
