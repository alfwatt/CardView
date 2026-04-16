// swift-tools-version:6.1

import PackageDescription

let package = Package(
    name: "CardView",
    defaultLocalization: "en",
    platforms: [.macOS(.v12), .iOS(.v14), .tvOS(.v14)],
    products: [
        .library(name: "CardView", type: .dynamic, targets: ["CardView"])
    ],
    dependencies: [
        .package(url: "https://github.com/alfwatt/KitBridge.git", from: "2.2.0"),
        .package(url: "https://github.com/alfwatt/ILFoundation.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "CardView",
            dependencies: [
                .product(name: "KitBridge", package: "KitBridge"),
                .product(name: "ILFoundation", package: "ILFoundation")
            ],
            publicHeadersPath: "include"
        ),
        .target(
            name: "Deck",
            dependencies: ["CardView"],
            exclude: ["Deck.entitlements"],
            resources: [
                .process("Assets.xcassets")
            ]
        )
    ]
)
