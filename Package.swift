// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "glean",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "GleanApp", targets: ["GleanApp"]),
        .library(name: "GleanCore", targets: ["GleanCore"]),
    ],
    targets: [
        .target(
            name: "GleanCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "GleanApp",
            dependencies: ["GleanCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GleanCoreTests",
            dependencies: ["GleanCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
