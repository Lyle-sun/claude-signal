// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "ClaudeSignal",
    platforms: [.macOS(.v13)],
    dependencies: [],
    targets: [
        // 核心逻辑库（可被测试目标依赖）
        .target(
            name: "ClaudeSignalKit",
            path: "Sources/ClaudeSignalKit"
        ),
        // 可执行目标（仅 main.swift 入口）
        .executableTarget(
            name: "ClaudeSignal",
            dependencies: ["ClaudeSignalKit"],
            path: "Sources/ClaudeSignal",
            resources: [.process("Resources")]
        ),
        // 单元测试（executableTarget，无需 XCTest，自带轻量 assert runner）
        .executableTarget(
            name: "ClaudeSignalTests",
            dependencies: ["ClaudeSignalKit"],
            path: "Tests/ClaudeSignalTests"
        )
    ]
)
