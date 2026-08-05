// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BinaryInspect",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13),
        .watchOS(.v6),
        .visionOS(.v1)
    ],
    products: [
        .library(name: "BinaryInspect", targets: ["BinaryInspect"]),
    ],
    targets: [
        .target(name: "BinaryInspect", path: "Sources",
                swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
        .testTarget(name: "BinaryInspectTests", dependencies: ["BinaryInspect"], path: "Tests"),
    ]
)
