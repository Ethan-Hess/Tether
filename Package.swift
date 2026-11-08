// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Tether",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TetherKit", targets: ["TetherKit"]),
        .executable(name: "tether", targets: ["tether"]),
        .executable(name: "TetherApp", targets: ["TetherApp"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.3.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .target(
            name: "TetherKit",
            resources: [.copy("Resources/Profiles"), .copy("Resources/Runtimes"), .copy("Resources/Notices")]
        ),
        .executableTarget(
            name: "tether",
            dependencies: [
                "TetherKit",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .executableTarget(
            name: "TetherApp",
            dependencies: ["TetherKit", .product(name: "Sparkle", package: "Sparkle")]
        ),
        .testTarget(name: "TetherKitTests", dependencies: ["TetherKit"]),
    ]
)
