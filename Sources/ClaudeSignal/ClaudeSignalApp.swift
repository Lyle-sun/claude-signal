import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let aggregator = SignalAggregator()
    private let soundPlayer = SoundPlayer()
    private let terminalActivator = TerminalActivator()
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp])

        // 首次刷新
        aggregator.refresh()
        updateIcon()
        rebuildMenu()

        // 启动轮询
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let prev = self.aggregator.globalState
            self.aggregator.refresh()
            self.updateIcon()
            self.rebuildMenu()
            self.handleStateChange(from: prev, to: self.aggregator.globalState)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }

    // MARK: - Icon Update

    private func updateIcon() {
        let state = aggregator.globalState
        guard let button = statusItem.button else { return }

        // macOS 暗色模式下 NSStatusBarButton 强制 template 渲染，自定义颜色不生效
        // 使用 emoji 作为图标，颜色 100% 可控
        button.title = state.emoji
        button.image = nil
        button.font = NSFont.systemFont(ofSize: 15)
        button.toolTip = state.description
    }

    // MARK: - Menu Rebuild

    private func rebuildMenu() {
        let menu = NSMenu()

        if aggregator.sessions.isEmpty {
            if !aggregator.claudeCodeInstalled {
                menu.addItem(NSMenuItem(title: "Claude Code 未检测到", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "请先安装 Claude Code CLI", action: nil, keyEquivalent: ""))
            } else {
                menu.addItem(NSMenuItem(title: "无 Claude Code 会话", action: nil, keyEquivalent: ""))
                menu.addItem(NSMenuItem(title: "启动 Claude Code 后自动检测", action: nil, keyEquivalent: ""))
            }
        } else {
            for session in aggregator.sessions {
                let item = NSMenuItem()
                item.title = "\(session.signalState.emoji) \(session.displayName)"
                item.toolTip = "Context: \(session.contextDescription)"

                let sessionMenu = NSMenu()

                if let waiting = session.waitingFor {
                    let waitItem = NSMenuItem(title: "等待: \(waiting)", action: nil, keyEquivalent: "")
                    waitItem.isEnabled = false
                    sessionMenu.addItem(waitItem)
                }

                let ctxItem = NSMenuItem(title: "Context: \(session.contextDescription)", action: nil, keyEquivalent: "")
                ctxItem.isEnabled = false
                sessionMenu.addItem(ctxItem)

                let jumpItem = NSMenuItem(title: "跳转到终端", action: #selector(jumpToTerminal(_:)), keyEquivalent: "")
                jumpItem.representedObject = session.pid
                sessionMenu.addItem(jumpItem)

                item.submenu = sessionMenu
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        let muteTitle = soundPlayer.isMuted ? "🔈 取消静音" : "🔇 静音"
        menu.addItem(NSMenuItem(title: muteTitle, action: #selector(toggleMute), keyEquivalent: ""))

        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "退出 Claude Signal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))

        statusItem.menu = menu
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        rebuildMenu()
    }

    @objc private func jumpToTerminal(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else { return }
        terminalActivator.activateTerminal(forPID: pid)
    }

    @objc private func toggleMute() {
        soundPlayer.isMuted.toggle()
        rebuildMenu()
    }

    // MARK: - State Change

    private func handleStateChange(from previous: SignalState, to current: SignalState) {
        guard previous != current else { return }
        for session in aggregator.sessions {
            soundPlayer.alertIfNeeded(for: session, previousState: previous)
        }
    }
}
