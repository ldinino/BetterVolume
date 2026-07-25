// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BetterVolume",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "BetterVolume", targets: ["BetterVolumeApp"])
    ],
    targets: [
        // Pure logic. No AppKit, no CoreAudio, fully unit-testable.
        .target(name: "AudioRouting"),
        // The only target that talks to the Core Audio HAL.
        .target(name: "AudioHAL", dependencies: ["AudioRouting"]),
        // Menu bar agent.
        .executableTarget(name: "BetterVolumeApp", dependencies: ["AudioRouting", "AudioHAL"]),
        .testTarget(name: "AudioRoutingTests", dependencies: ["AudioRouting"]),
    ]
)
