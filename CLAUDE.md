# CLAUDE.md — Claude Signal

macOS 菜单栏灯塔状态监控，监控 Claude Code 会话状态和 context 用量。

## 技术栈

- 语言：Swift 5.9+ / 纯 AppKit（不用 SwiftUI）
- 最低支持：macOS 13 (Ventura)
- 无外部依赖，纯系统框架
- 构建：SPM + build-app.sh 生成 .app bundle

## 项目结构

```
claude-signal/
├── CLAUDE.md              # 本文件
├── README.md
├── .gitignore
├── Package.swift           # SPM 配置
├── build-app.sh            # 构建 .app bundle + ad-hoc 签名
├── docs/
│   └── design.md           # 完整设计文档（架构、信号源、视觉规范）
└── Sources/ClaudeSignal/
    ├── main.swift               # 程序入口：手动设置 NSApplication delegate
    ├── ClaudeSignalApp.swift    # AppDelegate：菜单栏图标、定时刷新、菜单、两层动画
    ├── Models/
    │   ├── SignalState.swift    # 信号状态枚举（idle/running/confirming/warning/critical/error）
    │   └── SessionInfo.swift    # 会话信息模型（含 context 计算、状态推导）
    ├── Services/
    │   ├── SessionMonitor.swift     # 读取 ~/.claude/sessions/ + 僵尸检测
    │   ├── ContextMonitor.swift     # 读取 jsonl 获取 token 用量
    │   └── SignalAggregator.swift   # 聚合多个会话状态 → 全局状态
    ├── Helpers/
    │   ├── SoundPlayer.swift        # 声音提醒（含静音、per-session 冷却）
    │   └── TerminalActivator.swift  # AppleScript 激活终端窗口
    └── Resources/
        ├── tower_{1x,2x,3x}.png             # 塔身（白色，静态层）
        ├── tower_template_{1x,2x,3x}.png    # 塔身模板（idle/error 用系统渲染白色）
        ├── beacon_idle_{1x,2x,3x}.png       # 灯泡模板（系统渲染白色）
        ├── beacon_running_{1x,2x,3x}.png    # 灯泡绿色
        ├── beacon_confirming_{1x,2x,3x}.png # 灯泡红色
        ├── beacon_warning_{1x,2x,3x}.png    # 灯泡黄色
        ├── beacon_critical_{1x,2x,3x}.png   # 灯泡紫色
        └── beacon_error_{1x,2x,3x}.png      # 灯泡模板（系统渲染白色）
```

## 构建与运行

```bash
# 生成 .app bundle（构建 + 打包 + 签名）
bash build-app.sh

# 安装到桌面
cp -R .build/ClaudeSignal.app ~/Desktop/

# 运行
open ~/Desktop/ClaudeSignal.app
```

## 关键技术决策

1. **纯 AppKit 而非 SwiftUI**：`MenuBarExtra` 的 `label` 不响应 `@Published` 变化，`NSStatusBar` + `NSStatusItem` 可靠
2. **手动 main.swift 入口**：Swift `@main` 属性在 `AppDelegate` 上不会正确设置 delegate，必须手动 `app.delegate = delegate; app.run()`
3. **灯塔图标 + 两层动画**：logo 是灯塔形状，产品名 "Signal" 的视觉化。塔身 = 按钮 image（静态），灯泡 = CALayer 子图层（动画）。只有灯泡闪烁，塔身不动
4. **6 色状态体系**：白(idle) / 绿(running) / 红(confirming) / 黄(warning) / 紫(critical) / 白(error)。idle/error 用 `isTemplate=true` 让系统渲染，和电池图标同款白色
5. **LSUIElement=true**：隐藏 Dock 图标，仅菜单栏显示
6. **信号源**：`~/.claude/sessions/{pid}.json`（status + waitingFor）+ jsonl（token 用量）
7. **僵尸检测**：`kill(pid_t(pid), 0)` 验证进程是否存活

## 灯塔动画参数

- **running**：灯泡缓慢呼吸 opacity 1.0↔0.2，周期 1.8s，easeInEaseOut
- **confirming/critical**：灯泡急促闪烁 opacity 1.0↔0.05，周期 0.6s，easeInEaseOut
- **idle/warning/error**：灯泡常亮，无动画

## 代码规范

- 文件命名：PascalCase，与主要类型名一致
- Swift 代码风格：遵循 Swift API Design Guidelines
- 注释密度：公共接口加文档注释，实现细节不强制
- 日志：用 `os_log`，subsystem 为 `com.claude-signal.app`

## 验证

```bash
# 编译验证
swift build -c release

# 生成 .app 并验证
bash build-app.sh && open .build/ClaudeSignal.app
```

核心逻辑变更时手动验证：启动 App → 检测 Claude Code 会话 → 状态切换 → 声音提醒
