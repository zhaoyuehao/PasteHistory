// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PasteHistory",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "PasteHistory",
            path: "Sources/PasteHistory",
            resources: [.copy("Resources/ivory_tree.scn")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Cocoa"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("CoreGraphics"),
                .linkedFramework("Vision"),
                .linkedFramework("SceneKit"),
                .linkedLibrary("sqlite3"),
            ]
        )
    ]
)
