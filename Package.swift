// swift-tools-version:5.10

import PackageDescription

let package = Package(
    name: "CardView",
    platforms: [.macOS(.v12), .iOS(.v14), .tvOS(.v14)],
    products: [
        .library( name: "CardView", type: .dynamic, targets: ["CardView"])
    ],
    dependencies: [
      .package( url: "https://github.com/alfwatt/KitBridge.git", from: "2.2.0"),
      .package( url: "https://github.com/alfwatt/ILFoundation.git", from: "1.2.0")
    ],
    targets: [
        .target(
            name: "CardView",
            dependencies: ["KitBridge", "ILFoundation"]
        )
    ]
)
