// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "JettyNotepad",
    platforms: [.macOS(.v13)],
    targets: [
        .target(
            name: "JettyNotepadKit",
            path: "Sources/JettyNotepadKit",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
        .executableTarget(
            name: "JettyNotepad",
            dependencies: ["JettyNotepadKit"],
            path: "Sources/JettyNotepad"
        ),
        .executableTarget(
            name: "JettyNotepadTests",
            dependencies: ["JettyNotepadKit"],
            path: "Tests/JettyNotepadTests",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
            ]
        ),
    ]
)
