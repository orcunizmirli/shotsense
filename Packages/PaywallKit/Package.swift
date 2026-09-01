// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "PaywallKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "PaywallKit", targets: ["PaywallKit"])
    ],
    dependencies: [
        .package(path: "../AppFoundation"),
        .package(path: "../ShotCore")
    ],
    targets: [
        .target(name: "PaywallKit", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(
            name: "PaywallKitTests",
            dependencies: [
                "PaywallKit",
                .product(name: "ShotCoreTestSupport", package: "ShotCore")
            ]
        )
    ],
    swiftLanguageModes: [.v6]
)
