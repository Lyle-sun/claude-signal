# AGENTS.md — Codex Signal

macOS 菜单栏灯塔状态监控 + 仪表盘窗口，监控 Codex 会话状态和 context 用量。

## 技术栈

- 语言：Swift 5.9+
- 灯塔部分：纯 AppKit（NSStatusBar + CALayer 两层动画）
- 仪表盘窗口：SwiftUI（通过 NSHostingView 嵌入 NSWindow）
- 最低支持：macOS 13 (Ventura)
- 无外部依赖，纯系统框架
- 构建：SPM + build-app.sh 生成 .app bundle

## 项目结构

```
Codex-signal/
├── AGENTS.md              # 本文件
├── README.md
├── .gitignore
├── Package.swift           # SPM 配置（3 targets: Kit库 + 可执行 + 测试）
├── build-app.sh            # 构建 .app bundle + ad-hoc 签名
├── Sources/ClaudeSignal/   # 可执行目标（仅 main.swift + Resources）
│   ├── main.swift               # 程序入口，import ClaudeSignalKit
│   └── Resources/               # 灯塔图标资源
├── Sources/ClaudeSignalKit/ # 核心逻辑库（public API 供 executable + tests 访问）
│   ├── AppDelegate.swift         # 编排层（~50行）
│   ├── LighthouseController.swift # 灯塔：图标+动画+状态+声音+右键菜单
│   ├── Models/
│   │   ├── SignalState.swift     # 6色信号状态枚举
│   │   ├── SessionInfo.swift     # 会话信息模型（含 context 计算、状态推导、JSONL 解码模型）
│   │   └── ModelPricing.swift    # 模型定价（$/M tokens，未知模型 $0）
│   ├── Protocols/
│   │   ├── SessionSource.swift   # 统一数据源协议
│   │   ├── SessionMonitoring.swift
│   │   ├── ContextMonitoring.swift
│   │   ├── SoundPlaying.swift
│   │   └── TerminalActivating.swift
│   ├── Services/
│   │   ├── SignalAggregator.swift # @MainActor, 聚合多源 → 全局状态
│   │   ├── ClaudeCodeSource.swift # Codex 数据源实现（SQLite 优先 + jsonl fallback）
│   │   ├── SessionMonitor.swift   # 读取 ~/.Codex/sessions/ + 僵尸检测
│   │   ├── ContextMonitor.swift   # 读取 jsonl 获取 token 用量（tail-read）
│   │   ├── Database.swift         # SQLite3 薄封装（WAL 模式、事务、完整性检查）
│   │   ├── ClaudeCodeJsonlParser.swift # Codex jsonl 全量解析（增量偏移）
│   │   ├── Indexer.swift          # 后台增量索引器（文件截断检测、事务原子写入）
│   │   ├── IndexerCoordinator.swift # @MainActor 索引调度 + 状态管理
│   │   └── UsageStore.swift       # 数据读取层（日/项目/模型维度 + 成本计算）
│   ├── Dashboard/
│   │   ├── DashboardWindowController.swift # 单例窗口管理
│   │   ├── DashboardView.swift    # 主视图（NavigationSplitView: Sessions/Usage/Settings）
│   │   ├── SessionCardView.swift  # 会话卡片（视觉层级：主/次/三级）
│   │   ├── UsageView.swift        # 用量分析（总览卡片、趋势图、项目排行、模型分布）
│   │   └── SettingsView.swift     # 设置页（context 阈值、轮询间隔、声音开关）
│   └── Helpers/
│       ├── SoundPlayer.swift      # 声音提醒（per-session 冷却+重入检测）
│       └── TerminalActivator.swift # AppleScript 激活终端窗口
└── Tests/ClaudeSignalTests/ # 核心逻辑测试（轻量 assert runner，无 XCTest 依赖）
    └── CoreLogicTests.swift
```

## 构建与运行

```bash
# 生成 .app bundle
bash build-app.sh

# 安装到桌面
cp -R .build/ClaudeSignal.app ~/Desktop/

# 运行
open ~/Desktop/ClaudeSignal.app
```

## 关键技术决策

1. **灯塔 AppKit + 窗口 SwiftUI**：灯塔保持 AppKit（NSStatusBar + CALayer），仪表盘窗口用 SwiftUI（NSHostingView）
2. **Protocol + DI**：5 个协议抽象数据源、监控、声音、终端。ClaudeCodeSource 是唯一实现，为 Codex 等预留接口
3. **@MainActor 隔离**：SignalAggregator 和 LighthouseController 标注 @MainActor，I/O 在后台队列执行
4. **6 色状态体系**：白(idle) / 绿(running) / 红(confirming) / 黄(warning) / 紫(critical) / 白(error)
5. **LSUIElement=true**：隐藏 Dock 图标，窗口需 NSApp.activate(ignoringOtherApps: true) 才能到前台
6. **信号源**：`~/.Codex/sessions/{pid}.json` + jsonl（tail-read 64KB）
7. **僵尸检测**：`kill(pid_t(pid), 0)` 验证进程是否存活
8. **contextWindowLimit 参数化**：不再硬编码 200K，从 SessionSource 注入
9. **SQLite 用量分析**：原生 SQLite3 薄封装（WAL 模式），增量索引器后台运行，daily_usage 表按日/项目/模型聚合
10. **模型定价**：硬编码定价表，未知模型成本 $0，前缀匹配处理版本号后缀
11. **ContextMonitor 双路径**：优先从 SQLite 读取（由 Indexer 维护），fallback 直接读 jsonl（实时性更好）

## 灯塔动画参数

- **running**：灯泡缓慢呼吸 opacity 1.0↔0.2，周期 1.8s，easeInEaseOut
- **confirming/critical**：灯泡急促闪烁 opacity 1.0↔0.05，周期 0.6s，easeInEaseOut
- **idle/warning/error**：灯泡常亮，无动画

## 代码规范

- 文件命名：PascalCase，与主要类型名一致
- Swift 代码风格：遵循 Swift API Design Guidelines
- 注释密度：公共接口加文档注释，实现细节不强制
- 日志：用 `os_log`，subsystem 为 `com.Codex-signal.app`

## 验证

```bash
# 编译验证
swift build -c release

# 单元测试（轻量 assert runner，无需 Xcode/XCTest）
swift run ClaudeSignalTests

# 生成 .app 并验证
bash build-app.sh && open .build/ClaudeSignal.app
```

核心逻辑变更时手动验证：启动 App → 检测 Codex 会话 → 状态切换 → 声音提醒 → 点击图标开仪表盘
