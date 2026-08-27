// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "langShot",
    platforms: [.macOS(.v10_15)],
    products: [
        .library(name: "LangShotCore", targets: ["LangShotCore"]),
        .library(name: "LangShotPlatform", targets: ["LangShotPlatform"]),
        .executable(name: "langshot-helper", targets: ["LangShotHelper"])
    ],
    targets: [
        .target(name: "LangShotCore"),
        .target(name: "LangShotPlatform", dependencies: ["LangShotCore"]),
        .executableTarget(name: "LangShotHelper", dependencies: ["LangShotCore", "LangShotPlatform"]),
        .testTarget(name: "LangShotCoreTests", dependencies: ["LangShotCore"]),
        .testTarget(name: "LangShotPlatformTests", dependencies: ["LangShotPlatform", "LangShotCore"])
    ]
)
