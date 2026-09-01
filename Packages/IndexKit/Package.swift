// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "IndexKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "IndexKit", targets: ["IndexKit"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore")
    ],
    targets: [
        .target(name: "IndexKit", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(name: "IndexKitTests", dependencies: ["IndexKit"])
    ],
    swiftLanguageModes: [.v6]
)
