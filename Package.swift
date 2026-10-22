// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BinaryInspector",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BinaryInspector", targets: ["BinaryInspector"])
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions")
    ],
    targets: [
        .target(
            name: "BinaryInspector",
            dependencies: [.product(name: "FoundationExtensions", package: "swift-foundation-extensions")],
            path: "Sources",
            resources: [.process("BinaryInspector/Localizable.xcstrings")],
            swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(
            name: "BinaryInspectorTests", dependencies: ["BinaryInspector"], path: "Tests",
            exclude: ["BinaryInspectorTests/Fixtures/src", "BinaryInspectorTests/Fixtures/make_fixtures.sh"],
            resources: [.copy("BinaryInspectorTests/Fixtures/MachO")]),
        // Development tool for scripts/validate_macho.py; deliberately not a product, so nothing
        // that depends on this package builds or sees it.
        .executableTarget(
            name: "macho-dump", dependencies: ["BinaryInspector"], path: "Tools/MachODump",
            swiftSettings: [.swiftLanguageMode(.v6)]),
    ]
)
