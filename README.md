# Claude Signal

macOS 菜单栏灯塔 + 仪表盘，监控 Claude Code 会话状态、Context 用量和成本。

<p align="center">
  <img src="https://github.com/Lyle-sun/claude-signal/releases/download/v0.1.0/dashboard-sessions.png" width="700">
</p>

## 它解决什么问题

用 Claude Code 跑任务时，经常需要手动确认（权限、工具调用等），但切走终端后就看不到提示，任务一直卡着。Claude Signal 在菜单栏亮一盏灯塔——灯泡颜色就是状态信号，你扫一眼就知道。

**不是通知，是信号灯。** 通知弹一下就消失，灯塔一直在那亮着。

## 功能

### 灯塔信号

- ⚪ **白灯**：无活跃会话
- 🟢 **绿灯**（呼吸）：Claude Code 正常运行
- 🔴 **红灯**（急闪）：Claude Code 等待确认，需要你回去操作
- 🟡 **黄灯**：Context 用量超过 75%
- 🟣 **紫灯**（急闪）：Context 超过上限，需要开新会话
- 🔈 **声音提醒**：进入等待确认或超限状态时提示音

### 仪表盘窗口

点击菜单栏图标打开仪表盘，包含四个视图：

- **会话** — 所有活跃 Claude Code 会话的实时状态、Context 进度、模型、Token 用量

  <img src="https://github.com/Lyle-sun/claude-signal/releases/download/v0.1.0/dashboard-sessions.png" width="600">

- **今日** — 当日消耗独立视图，含近 90 日 P90 参考对比

  <img src="https://github.com/Lyle-sun/claude-signal/releases/download/v0.1.0/dashboard-today.png" width="600">

- **用量** — Token 趋势图、模型分布、项目排行、成本统计，支持按日/7天/30天/90天筛选

  <img src="https://github.com/Lyle-sun/claude-signal/releases/download/v0.1.0/dashboard-usage.png" width="600">

- **设置** — Context 上限、警告阈值、轮询间隔、声音、界面语言

### 成本分析

基于模型定价自动计算费用，支持：

- Claude Opus 4 / Sonnet 4 / Haiku
- GLM-5 / GLM-5.1（智谱 AI）
- DeepSeek V4 / V4-Pro
- 未知模型显示警告，成本按 $0 计算

## 首次运行

启动后你会看到菜单栏出现白色灯塔图标——这是正常的，表示没有检测到 Claude Code 会话。在终端启动 Claude Code 后，灯塔会在 2 秒内变绿。

## 系统要求

- macOS 13 (Ventura) 或更高
- Claude Code CLI

## 安装

### 下载安装（推荐）

1. 从 [Releases](https://github.com/Lyle-sun/claude-signal/releases) 下载最新 `ClaudeSignal.dmg`
2. 打开 DMG，将 ClaudeSignal.app 拖入 Applications 文件夹
3. 首次打开如果被 macOS Gatekeeper 拦截：
   ```bash
   xattr -cr /Applications/ClaudeSignal.app
   ```

### 从源码构建

```bash
git clone https://github.com/Lyle-sun/claude-signal.git
cd claude-signal
bash build-app.sh
cp -R .build/ClaudeSignal.app /Applications/
```

## 使用

1. 启动 ClaudeSignal.app，菜单栏出现白灯（无会话）
2. 在终端启动 Claude Code，灯塔亮绿灯并开始呼吸
3. Claude Code 等待确认时，灯塔变红灯 + 急促闪烁 + 声音提醒
4. 点击菜单栏图标打开仪表盘窗口，查看会话详情和用量分析
5. 在仪表盘中点击「会话定位」跳回对应终端窗口
6. 右键图标可以静音或退出

零配置——装上就能用。

## License

MIT
