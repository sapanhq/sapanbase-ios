// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "HelpBentoSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "HelpBentoSDK",
            targets: ["HelpBentoSDK"]
        )
    ],
    targets: [
        .target(
            name: "HelpBentoSDK",
            path: "Sources/HelpBentoSDK"
        )
    ]
)
