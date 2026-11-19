// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "mac-dev-cleanup",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "mac-dev-cleanup", targets: ["mac-dev-cleanup"]),
    ],
    targets: [
        .target(name: "DevCleanupCore"),
        .executableTarget(name: "mac-dev-cleanup", dependencies: ["DevCleanupCore"]),
        .testTarget(name: "DevCleanupCoreTests", dependencies: ["DevCleanupCore"]),
    ]
)
