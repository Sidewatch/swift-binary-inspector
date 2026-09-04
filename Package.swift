// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BinaryInspect",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "BinaryInspect", targets: ["BinaryInspect"]),
    ],
    targets: [
        .target(name: "BinaryInspect", path: "Sources",
                swiftSettings: [.swiftLanguageMode(.v6)]),
        .testTarget(name: "BinaryInspectTests", dependencies: ["BinaryInspect"], path: "Tests"),
    ]
)
