// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "LibraryKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "LibraryKit", targets: ["LibraryKit"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore"),
        .package(path: "../DesignSystem")
    ],
    targets: [
        .target(name: "LibraryKit", dependencies: ["AppFoundation", "ShotCore", "DesignSystem"]),
        .testTarget(
            name: "LibraryKitTests",
            dependencies: [
                "LibraryKit",
                .product(name: "ShotCoreTestSupport", package: "ShotCore")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
