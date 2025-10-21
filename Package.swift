// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ASAAttributionSDK",
    platforms: [
        // The SDK supports iOS 13+, but attribution is only performed on iOS 14.3+.
        // macOS, iPadOS apps on macOS, and Catalyst apps are NOT supported.
        // The SDK will gracefully detect and disable itself on unsupported platforms.
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "ASAAttributionSDK",
            targets: ["ASAAttributionSDK"]
        ),
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ASAAttributionSDK",
            dependencies: [],
            linkerSettings: [
                .linkedFramework("AdServices", .when(platforms: [.iOS]))
            ]
        ),
        .testTarget(
            name: "ASAAttributionSDKTests",
            dependencies: ["ASAAttributionSDK"]
        )
    ]
) 