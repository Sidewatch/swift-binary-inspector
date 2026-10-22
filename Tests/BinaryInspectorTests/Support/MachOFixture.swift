//
//  MachOFixture.swift
//  BinaryInspectorTests
//
//  Loads the checked-in Mach-O fixtures (Fixtures/MachO, built by Fixtures/make_fixtures.sh).
//
//  Created by David Sherlock on 10/22/26.
//  Copyright © 2026 ArrayPress Limited. MIT licence.
//

import Foundation
import XCTest

/// The fixture files, by name.
enum MachOFixture {
    /// Every fixture, for the tests that run over all of them.
    static let all = [
        "hello-arm64", "hello-x86_64", "hello-universal", "hello-universal-fat64", "libgreeter.dylib", "plugin.bundle", "plugin.o",
    ]

    /// The bytes of fixture `name`; fails the test when it is missing.
    static func data(_ name: String, file: StaticString = #filePath, line: UInt = #line) throws -> Data {
        let url = try XCTUnwrap(
            Bundle.module.url(forResource: name, withExtension: nil, subdirectory: "MachO"), "missing fixture \(name)", file: file,
            line: line)
        return try Data(contentsOf: url)
    }
}
