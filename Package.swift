// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SapanBaseSDK",
    platforms: [
        .iOS(.v14)
    ],
    products: [
        .library(
            name: "SapanBaseSDK",
            targets: ["SapanBaseSDK"]
        )
    ],
    targets: [
        .target(
            name: "SapanBaseSDK",
            path: "Sources/SapanBaseSDK"
        )
    ]
)
