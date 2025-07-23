// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ASAAttributionSDK",
    platforms: [
        // The SDK supports iOS 13+, but attribution is only performed on iOS 14.3+.
        .iOS(.v13)
    ],
    products: [
        .library(
            name: "ASAAttributionSDK",
            type: .static,
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
        )
    ],
    swiftLanguageVersions: [.v5]
) 