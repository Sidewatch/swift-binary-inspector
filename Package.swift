// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "BinaryInspector",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BinaryInspector", targets: ["BinaryInspector"]),
    ],
    targets: [
        .target(name: "BinaryInspector", path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "BinaryInspectorTests", dependencies: ["BinaryInspector"], path: "Tests"),
    ]
)
