// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteHistory",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PasteHistory",
            path: "Sources/PasteHistory",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
