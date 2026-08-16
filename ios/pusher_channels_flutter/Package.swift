// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "pusher_channels_flutter",
    platforms: [
        .iOS("13.0")
    ],
    products: [
        .library(name: "pusher-channels-flutter", targets: ["pusher_channels_flutter"])
    ],
    dependencies: [
        .package(name: "FlutterFramework", path: "../FlutterFramework"),
        .package(url: "https://github.com/pusher/pusher-websocket-swift.git", from: "10.1.10")
    ],
    targets: [
        .target(
            name: "pusher_channels_flutter",
            dependencies: [
                .product(name: "FlutterFramework", package: "FlutterFramework"),
                .product(name: "PusherSwift", package: "pusher-websocket-swift")
            ],
            resources: [
                .process("PrivacyInfo.xcprivacy")
            ]
        )
    ]
)
