// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Arrowshot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Arrowshot", targets: ["Arrowshot"])
    ],
    targets: [
        .executableTarget(
            name: "Arrowshot",
            path: "Sources/Arrowshot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "ArrowshotTests",
            dependencies: ["Arrowshot"],
            path: "Tests/ArrowshotTests"
        )
    ]
)
