// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "WebBox",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "WebBox", targets: ["WebBox"])
    ],
    targets: [
        .executableTarget(
            name: "WebBox",
            path: "Sources/WebBox",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("UniformTypeIdentifiers"),
                .linkedFramework("UserNotifications")
            ]
        )
    ]
)
