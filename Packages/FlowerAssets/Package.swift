// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "FlowerAssets",
    platforms: [.visionOS(.v26)],
    products: [
        .library(name: "FlowerAssets", targets: ["FlowerAssets"]),
    ],
    targets: [
        .target(name: "FlowerAssets", dependencies: []),
    ]
)
