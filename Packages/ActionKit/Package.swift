// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ActionKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ActionKit", targets: ["ActionKit"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore")
    ],
    targets: [
        .target(name: "ActionKit", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(name: "ActionKitTests", dependencies: ["ActionKit"])
    ],
    swiftLanguageModes: [.v6]
)
