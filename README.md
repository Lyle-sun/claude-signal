# Claude Signal

macOS 菜单栏红绿灯，监控 Claude Code 会话状态。

## 它解决什么问题

用 Claude Code 跑任务时，经常需要手动确认（权限、工具调用等），但切走终端后就看不到提示，任务一直卡着。Claude Signal 在菜单栏亮一个持续可见的信号灯——红灯 = 需要你操作，绿灯 = 正常运行，黄灯 = context 快满了。

**不是通知，是信号灯。** 通知弹一下就消失，信号灯一直在那亮着。你扫一眼就知道状态。

## 功能

- 🟢 **绿灯**：Claude Code 正常运行
- 🔴 **红灯**：Claude Code 等待确认（需要你回去操作）
- 🟡 **黄灯**：Context 用量超过 75%（接近上限提醒）
- 🔴 **常亮红灯**：Context 用量超过 100%（需要开新会话）
- 🔈 **声音提醒**：首次进入等待状态时响一次
- 🖥️ **多会话**：同时监控多个 Claude Code 实例
- 🔗 **点击跳转**：点击跳回对应终端窗口（Terminal.app / iTerm2）

## 系统要求

- macOS 13 (Ventura) 或更高
- Claude Code CLI

## 安装

```bash
# 从源码构建
git clone https://github.com/your-username/claude-signal.git
cd claude-signal
bash build-app.sh

# 复制到桌面或 Applications
cp -R .build/ClaudeSignal.app ~/Desktop/
# 或
cp -R .build/ClaudeSignal.app /Applications/
```

首次打开如果被 Gatekeeper 拦截：
```bash
xattr -cr ~/Desktop/ClaudeSignal.app
```

## 使用

1. 双击 ClaudeSignal.app，菜单栏出现灰灯（无会话状态）
2. 在终端启动 Claude Code，灰灯变绿灯
3. Claude Code 等待确认时，变红灯 + 声音提醒
4. 点击菜单栏图标查看会话详情、跳转终端

零配置——装上就能用，不需要改 Claude Code 设置。

## 技术细节

- 纯 Swift / AppKit，无外部依赖
- 通过读取 `~/.claude/sessions/{pid}.json` 获取会话状态（不依赖 Hooks）
- 通过读取 `~/.claude/projects/{slug}/{sessionId}.jsonl` 获取 context token 用量
- `LSUIElement=true` 隐藏 Dock 图标，纯菜单栏 App
- Emoji 图标绕过 macOS 暗色模式 template 渲染限制

## License

MIT
