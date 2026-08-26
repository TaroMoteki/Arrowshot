// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PictoJot",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "PictoJot", targets: ["PictoJot"])
    ],
    targets: [
        .executableTarget(
            name: "PictoJot",
            path: "Sources/PictoJot",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreImage"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("ServiceManagement")
            ]
        ),
        .testTarget(
            name: "PictoJotTests",
            dependencies: ["PictoJot"],
            path: "Tests/PictoJotTests"
        )
    ]
)
