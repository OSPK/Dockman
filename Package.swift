// swift-tools-version: 6.0
import PackageDescription

// Dockman — additional, per-Space macOS Docks. See /docs for the specification.
// Phase 0: SpacesKit + dockman-spike (the validated feasibility gate).
// Phase 1: ConfigKit + DockKit + the `dockman` agent app (walking skeleton).
//
// Targets use the v5 language mode for now; docs/03 §5 calls for tightening to
// Swift 6 strict concurrency in the hardening phase.
let v5: [SwiftSetting] = [.swiftLanguageMode(.v5)]

let package = Package(
    name: "Dockman",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "SpacesKit", targets: ["SpacesKit"]),
        .library(name: "ConfigKit", targets: ["ConfigKit"]),
        .library(name: "DockKit", targets: ["DockKit"]),
        .executable(name: "dockman", targets: ["Dockman"]),
        .executable(name: "dockman-spike", targets: ["DockmanSpike"]),
    ],
    targets: [
        .target(name: "SpacesKit", swiftSettings: v5),
        .target(name: "ConfigKit", swiftSettings: v5),
        .target(name: "DockKit", dependencies: ["SpacesKit", "ConfigKit"], swiftSettings: v5),
        .executableTarget(
            name: "Dockman",
            dependencies: ["DockKit", "SpacesKit", "ConfigKit"],
            swiftSettings: v5
        ),
        .executableTarget(name: "DockmanSpike", dependencies: ["SpacesKit"], swiftSettings: v5),
        .testTarget(name: "SpacesKitTests", dependencies: ["SpacesKit"], swiftSettings: v5),
        .testTarget(name: "ConfigKitTests", dependencies: ["ConfigKit"], swiftSettings: v5),
        .testTarget(name: "DockKitTests", dependencies: ["DockKit", "SpacesKit", "ConfigKit"], swiftSettings: v5),
    ]
)
