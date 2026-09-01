// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DesignSystem",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "DesignSystem", targets: ["DesignSystem"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore")
    ],
    targets: [
        .target(name: "DesignSystem", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(name: "DesignSystemTests", dependencies: ["DesignSystem"])
    ],
    swiftLanguageModes: [.v6]
)
