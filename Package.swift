// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GitRadar",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "GitRadar", targets: ["GitRadar"])
    ],
    targets: [
        .executableTarget(
            name: "GitRadar",
            path: "Sources/GitRadar",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI")
            ]
        )
    ]
)
