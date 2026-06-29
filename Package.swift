// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "QuotaWake",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(
            name: "QuotaWakeCore",
            targets: ["QuotaWakeCore"]
        ),
        .executable(
            name: "QuotaWake",
            targets: ["QuotaWake"]
        )
    ],
    targets: [
        .target(
            name: "QuotaWakeCore"
        ),
        .executableTarget(
            name: "QuotaWake",
            dependencies: ["QuotaWakeCore"]
        ),
        .testTarget(
            name: "QuotaWakeCoreTests",
            dependencies: ["QuotaWakeCore"]
        )
    ]
)
