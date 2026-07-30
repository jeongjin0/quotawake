// swift-tools-version: 5.9

import PackageDescription

var products: [Product] = [
    .library(
        name: "QuotaWakeCore",
        targets: ["QuotaWakeCore"]
    ),
    .executable(
        name: "quotawake",
        targets: ["QuotaWakeCLI"]
    )
]

var targets: [Target] = [
    .target(
        name: "QuotaWakeCore"
    ),
    .executableTarget(
        name: "QuotaWakeCLI",
        dependencies: [
            "QuotaWakeCore",
            .product(name: "ArgumentParser", package: "swift-argument-parser")
        ]
    ),
    .testTarget(
        name: "QuotaWakeCoreTests",
        dependencies: ["QuotaWakeCore"]
    ),
    .testTarget(
        name: "QuotaWakeCLITests",
        dependencies: ["QuotaWakeCLI", "QuotaWakeCore"]
    )
]

#if os(macOS)
products.append(
    .executable(
        name: "QuotaWakeMac",
        targets: ["QuotaWakeMac"]
    )
)
targets.append(
    .executableTarget(
        name: "QuotaWakeMac",
        dependencies: ["QuotaWakeCore"],
        path: "Sources/QuotaWake"
    )
)
#endif

let package = Package(
    name: "QuotaWake",
    platforms: [
        .macOS(.v13)
    ],
    products: products,
    dependencies: [
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            exact: "1.7.0"
        )
    ],
    targets: targets
)
