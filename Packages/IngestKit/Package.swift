// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "IngestKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "IngestKit", targets: ["IngestKit"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore")
    ],
    targets: [
        .target(name: "IngestKit", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(name: "IngestKitTests", dependencies: ["IngestKit"])
    ],
    swiftLanguageModes: [.v6]
)
