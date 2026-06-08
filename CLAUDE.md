# CLAUDE.md — Claude Signal

macOS 菜单栏红绿灯状态监控，监控 Claude Code 会话状态和 context 用量。

## 技术栈

- 语言：Swift 5.9+ / SwiftUI
- 最低支持：macOS 13 (Ventura)
- 无外部依赖，纯系统框架

## 项目结构

```
claude-signal/
├── CLAUDE.md              # 本文件
├── README.md
├── .gitignore
├── docs/
│   └── design.md          # 完整设计文档（架构、信号源、视觉规范）
├── ClaudeSignal/          # Xcode 项目源码
│   ├── ClaudeSignalApp.swift    # App 入口 + MenuBarExtra
│   ├── Models/                  # 数据模型（SignalState, SessionInfo）
│   ├── Services/                # 监控服务（SessionMonitor, ContextMonitor）
│   ├── Views/                   # SwiftUI 视图（MenuBarView, PopoverView）
│   └── Helpers/                 # 工具类（TerminalActivator, SoundPlayer）
└── ClaudeSignal.xcodeproj/
```

## 构建与运行

```bash
# 用 Xcode 打开
open ClaudeSignal.xcodeproj

# 或命令行构建
xcodebuild -project ClaudeSignal.xcodeproj -scheme ClaudeSignal -configuration Debug build
```

## 代码规范

- 文件命名：PascalCase，与主要类型名一致
- Swift 代码风格：遵循 Swift API Design Guidelines
- 注释密度：公共接口加文档注释，实现细节不强制
- 状态管理：用 `@Observable`（macOS 14+）/ `@Published` + `ObservableObject`
- 动画：状态转换统一用 Spring 动画（`response: 0.35, dampingFraction: 0.8`）
- 日志：用 `os_log`，subsystem 为 `com.claude-signal.app`

## 设计决策记录

所有架构和设计决策见 `docs/design.md`，包括：
- 信号源设计（session 文件 + 进程检测兜底）
- 状态模型和聚合优先级
- 视觉设计规范（SF Symbol、颜色、动画参数）
- 分阶段交付计划（Phase 1/2/3）

## 验证

- 改完跑 `xcodebuild build` 确认编译通过
- 核心逻辑变更时手动验证：启动 App → 检测 Claude Code 会话 → 状态切换 → 声音提醒
