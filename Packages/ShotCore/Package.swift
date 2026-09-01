// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "ShotCore",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "ShotCore", targets: ["ShotCore"]),
        // Sahte portlar birden çok pakette kullanılıyor (ShotCore, LibraryKit); ayrı ürün
        // olmasalardı her paket kendi kopyasını tutar ve zamanla ayrışırlardı.
        .library(name: "ShotCoreTestSupport", targets: ["ShotCoreTestSupport"])
    ],
    dependencies: [
        .package(path: "../AppFoundation")
    ],
    targets: [
        .target(name: "ShotCore", dependencies: ["AppFoundation"]),
        .target(name: "ShotCoreTestSupport", dependencies: ["AppFoundation", "ShotCore"]),
        .testTarget(name: "ShotCoreTests", dependencies: ["ShotCore", "ShotCoreTestSupport"])
    ],
    swiftLanguageModes: [.v6]
)
