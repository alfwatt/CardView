// swift-tools-version:6.1

import Foundation
import PackageDescription

// Uses a local sibling checkout if one is present (development), otherwise
// falls back to the git remote (CI, or anyone who hasn't checked it out locally).
func localOrRemote(_ name: String, url: String, from version: Version) -> Package.Dependency {
    let packageDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
    let localPath = packageDirectory.deletingLastPathComponent().appendingPathComponent(name).path
    if FileManager.default.fileExists(atPath: localPath) {
        return .package(path: localPath)
    }
    return .package(url: url, from: version)
}

let package = Package(
    name: "CardView",
    defaultLocalization: "en",
    platforms: [.macOS(.v12), .iOS(.v14), .tvOS(.v14)],
    products: [
        .library(name: "CardView", type: .dynamic, targets: ["CardView"])
    ],
    dependencies: [
        localOrRemote("KitBridge", url: "https://github.com/alfwatt/KitBridge.git", from: "2.2.0"),
        localOrRemote("ILFoundation", url: "https://github.com/alfwatt/ILFoundation.git", from: "1.2.0")
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
