//
//  MachOBuildTool.swift
//  BinaryInspector
//
//  One tool entry of an LC_BUILD_VERSION command: which tool, which version.
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation

/// A `build_tool_version` record.
public struct MachOBuildTool: Equatable, Hashable, Sendable {
    /// The `tool` constant: 1 clang, 2 swift, 3 ld, 4 lld, 1024 metal, … (raw, for the caller to name).
    public let tool: UInt32
    /// The tool's version.
    public let version: MachOVersion

    /// Creates a tool record.
    public init(tool: UInt32, version: MachOVersion) {
        self.tool = tool
        self.version = version
    }
}
