// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudeSignal",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeSignal",
            path: "Sources/ClaudeSignal"
        )
    ]
)
