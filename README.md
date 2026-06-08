# Claude Signal

macOS 菜单栏灯塔，监控 Claude Code 会话状态。

## 它解决什么问题

用 Claude Code 跑任务时，经常需要手动确认（权限、工具调用等），但切走终端后就看不到提示，任务一直卡着。Claude Signal 在菜单栏亮一盏灯塔——灯泡颜色就是状态信号，你扫一眼就知道。

**不是通知，是信号灯。** 通知弹一下就消失，灯塔一直在那亮着。

## 功能

- 🏠 **白灯**：无活跃会话 / 检测失败
- 🟢 **绿灯**（呼吸）：Claude Code 正常运行
- 🔴 **红灯**（急闪）：Claude Code 等待确认，需要你回去操作
- 🟡 **黄灯**：Context 用量超过 75%
- 🟣 **紫灯**（急闪）：Context 超过 100%，需要开新会话
- 🔈 **声音提醒**：状态变化时提示音
- 🖥️ **多会话**：同时监控多个 Claude Code 实例
- 🔗 **点击跳转**：点击跳回对应终端窗口

## 灯塔图标

Logo 是一座灯塔——灯泡变色表示状态，塔身永远不动。运行时灯泡缓慢呼吸，等待确认时急促闪烁。和产品名 "Signal" 直接对应。

## 系统要求

- macOS 13 (Ventura) 或更高
- Claude Code CLI

## 安装

```bash
git clone https://github.com/your-username/claude-signal.git
cd claude-signal
bash build-app.sh

# 复制到 Applications
cp -R .build/ClaudeSignal.app /Applications/
```

首次打开如果被 Gatekeeper 拦截：
```bash
xattr -cr /Applications/ClaudeSignal.app
```

## 使用

1. 双击 ClaudeSignal.app，菜单栏出现白灯（无会话）
2. 在终端启动 Claude Code，灯塔亮绿灯并开始呼吸
3. Claude Code 等待确认时，灯塔变红灯 + 急促闪烁 + 声音提醒
4. 点击菜单栏图标查看会话详情、Context 用量、跳转终端

零配置——装上就能用。

## 技术细节

- 纯 Swift / AppKit，无外部依赖
- 灯塔图标两层渲染：塔身 = NSStatusItem image（静态），灯泡 = CALayer 子图层（动画）
- 通过读取 `~/.claude/sessions/{pid}.json` 获取会话状态
- 通过读取 jsonl 文件获取 context token 用量
- `LSUIElement=true` 隐藏 Dock 图标，纯菜单栏 App

## License

MIT
