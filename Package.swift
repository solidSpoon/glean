// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "graze",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "GrazeApp", targets: ["GrazeApp"]),
        .library(name: "GrazeCore", targets: ["GrazeCore"]),
    ],
    targets: [
        .target(
            name: "GrazeCore",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "GrazeApp",
            dependencies: ["GrazeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "GrazeCoreTests",
            dependencies: ["GrazeCore"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
