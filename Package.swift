// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BinaryInspector",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BinaryInspector", targets: ["BinaryInspector"]),
    ],
    dependencies: [
        .package(path: "../swift-foundation-extensions"),
    ],
    targets: [
        .target(name: "BinaryInspector",
                dependencies: [.product(name: "FoundationExtensions", package: "swift-foundation-extensions")],
                path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "BinaryInspectorTests", dependencies: ["BinaryInspector"], path: "Tests"),
    ]
)
