// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "TopgradeMenu",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "TopgradeMenu", targets: ["TopgradeMenu"]),
    ],
    targets: [
        .target(name: "TopgradeMenuCore"),
        .executableTarget(
            name: "TopgradeMenu",
            dependencies: ["TopgradeMenuCore"]
        ),
        .executableTarget(
            name: "TopgradeMenuChecks",
            dependencies: ["TopgradeMenuCore"]
        ),
    ]
)
