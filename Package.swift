// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ScreenCaptureAll",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "ScreenCaptureAll", targets: ["ScreenCaptureAll"])
    ],
    targets: [
        .executableTarget(
            name: "ScreenCaptureAll",
            path: "Sources"
        )
    ]
)
