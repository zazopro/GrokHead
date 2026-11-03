// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "GrokHead",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "GrokHead", targets: ["GrokHead"])
    ],
    targets: [
        .executableTarget(
            name: "GrokHead",
            path: "GrokHead",
            exclude: [
                "Info.plist",
                "AppIcon-1024.png"
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("UserNotifications"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("UniformTypeIdentifiers")
            ]
        )
    ]
)
