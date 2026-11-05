// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gremlets",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Gremlets", targets: ["Gremlets"]),
    ],
    targets: [
        // Platform-agnostic engine: physics, surfaces, behavior AI, sprite metadata.
        // No AppKit imports here, so a Windows/Linux front end can reuse it.
        .target(name: "GremletsCore"),
        // macOS front end: overlay windows, window-surface detection, menu bar, rendering.
        .executableTarget(name: "Gremlets", dependencies: ["GremletsCore"]),
        // Dev tool that generates the placeholder pixel-art sprite sheets (Aseprite JSON format).
        .executableTarget(name: "spritegen"),
        .testTarget(name: "GremletsCoreTests", dependencies: ["GremletsCore"]),
    ]
)
