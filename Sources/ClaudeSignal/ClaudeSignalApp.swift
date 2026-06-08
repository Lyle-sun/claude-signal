import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let aggregator = SignalAggregator()
    private let soundPlayer = SoundPlayer()
    private let terminalActivator = TerminalActivator()
    private var timer: Timer?
    private var pulseTimer: Timer?
    private var isPulseOn = true

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.image = coloredDot(color: SignalState.idle.nsColor, size: 14)
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Claude Signal"

        // 首次刷新
        aggregator.refresh()
        updateIcon()

        // 启动轮询
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let prev = self.aggregator.globalState
            self.aggregator.refresh()
            self.updateIcon()
            self.handleStateChange(from: prev, to: self.aggregator.globalState)
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        pulseTimer?.invalidate()
    }

    // MARK: - Icon Update

    private func updateIcon() {
        let state = aggregator.globalState
        guard let button = statusItem.button else { return }

        button.image = coloredDot(color: state.nsColor, size: 14)
        button.toolTip = "Claude Signal — \(state.description)"

        // 菜单在打开时实时构建
        statusItem.menu = buildMenu()

        updatePulseAnimation(for: state)
    }

    /// 手动绘制彩色圆点（isTemplate=false 保留真实颜色）
    private func coloredDot(color: NSColor, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let circle = NSBezierPath(ovalIn: NSRect(x: 1, y: 1, width: size - 2, height: size - 2))
        color.setFill()
        circle.fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: - Pulse Animation

    private func updatePulseAnimation(for state: SignalState) {
        pulseTimer?.invalidate()
        pulseTimer = nil
        isPulseOn = true

        guard state.needsAction else { return }

        let fullColor = state.nsColor
        let dimColor = fullColor.withAlphaComponent(0.3)
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.isPulseOn.toggle()
            button.image = self.coloredDot(color: self.isPulseOn ? fullColor : dimColor, size: 14)
        }
    }

    // MARK: - Menu

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.minimumWidth = 280

        // Header
        let headerItem = NSMenuItem()
        headerItem.view = makeHeaderView()
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        if aggregator.sessions.isEmpty {
            let emptyItem = NSMenuItem(title: "无 Claude Code 会话", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
            let hintItem = NSMenuItem(title: "启动 Claude Code 后自动检测", action: nil, keyEquivalent: "")
            hintItem.isEnabled = false
            menu.addItem(hintItem)
        } else {
            for session in aggregator.sessions {
                let sessionItem = NSMenuItem()
                sessionItem.view = makeSessionCard(session: session)
                sessionItem.representedObject = session.pid

                // 子菜单放操作
                let subMenu = NSMenu()
                let jumpItem = NSMenuItem(title: "跳转到终端", action: #selector(jumpToTerminal(_:)), keyEquivalent: "")
                jumpItem.representedObject = session.pid
                subMenu.addItem(jumpItem)
                sessionItem.submenu = subMenu
                menu.addItem(sessionItem)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // 静音
        let muteTitle = soundPlayer.isMuted ? "已静音" : "静音"
        let muteIcon = soundPlayer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let muteItem = NSMenuItem(title: muteTitle, action: #selector(toggleMute), keyEquivalent: "")
        muteItem.image = NSImage(systemSymbolName: muteIcon, accessibilityDescription: nil)
        menu.addItem(muteItem)

        // 退出
        let quitItem = NSMenuItem(title: "退出 Claude Signal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    // MARK: - Custom Menu Item Views

    private func makeHeaderView() -> NSView {
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: 36))

        let dot = NSView(frame: NSRect(x: 12, y: 13, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = aggregator.globalState.nsColor.cgColor
        dot.layer?.cornerRadius = 5
        container.addSubview(dot)

        let title = NSTextField(labelWithString: "Claude Signal")
        title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
        title.frame = NSRect(x: 28, y: 10, width: 150, height: 18)
        container.addSubview(title)

        let stateLabel = NSTextField(labelWithString: aggregator.globalState.description)
        stateLabel.font = NSFont.systemFont(ofSize: 11)
        stateLabel.textColor = .secondaryLabelColor
        stateLabel.alignment = .right
        stateLabel.frame = NSRect(x: 160, y: 10, width: 108, height: 18)
        container.addSubview(stateLabel)

        return container
    }

    private func makeSessionCard(session: SessionInfo) -> NSView {
        let cardWidth: CGFloat = 260
        let cardHeight: CGFloat = 70

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: cardHeight + 12))
        container.wantsLayer = true
        container.layer?.cornerRadius = 6

        // 卡片背景
        let card = NSView(frame: NSRect(x: 10, y: 4, width: cardWidth, height: cardHeight))
        card.wantsLayer = true
        card.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        card.layer?.cornerRadius = 6
        card.layer?.borderColor = NSColor.separatorColor.cgColor
        card.layer?.borderWidth = 0.5
        container.addSubview(card)

        // 状态圆点
        let dot = NSView(frame: NSRect(x: 10, y: 46, width: 8, height: 8))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = session.signalState.nsColor.cgColor
        dot.layer?.cornerRadius = 4
        card.addSubview(dot)

        // 项目名
        let name = NSTextField(labelWithString: session.projectName)
        name.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        name.frame = NSRect(x: 24, y: 43, width: 180, height: 16)
        name.lineBreakMode = .byTruncatingTail
        card.addSubview(name)

        // "待确认" badge
        if session.signalState == .confirming {
            let badge = NSTextField(labelWithString: "待确认")
            badge.font = NSFont.systemFont(ofSize: 10, weight: .semibold)
            badge.textColor = .white
            badge.alignment = .center
            badge.backgroundColor = .systemRed
            badge.drawsBackground = true
            badge.frame = NSRect(x: 200, y: 44, width: 48, height: 16)
            badge.wantsLayer = true
            badge.layer?.cornerRadius = 4
            badge.layer?.masksToBounds = true
            card.addSubview(badge)
        }

        // Context 进度条背景
        let progressBg = NSView(frame: NSRect(x: 10, y: 26, width: cardWidth - 20, height: 4))
        progressBg.wantsLayer = true
        progressBg.layer?.backgroundColor = NSColor.separatorColor.cgColor
        progressBg.layer?.cornerRadius = 2
        card.addSubview(progressBg)

        // Context 进度条填充
        let progressWidth = max(2, (cardWidth - 20) * min(session.contextPercent, 1.0))
        let progressFill = NSView(frame: NSRect(x: 10, y: 26, width: progressWidth, height: 4))
        progressFill.wantsLayer = true
        progressFill.layer?.backgroundColor = progressColor(for: session.contextPercent).cgColor
        progressFill.layer?.cornerRadius = 2
        card.addSubview(progressFill)

        // Context 文字
        let ctxLabel = NSTextField(labelWithString: "Context")
        ctxLabel.font = NSFont.systemFont(ofSize: 10)
        ctxLabel.textColor = .tertiaryLabelColor
        ctxLabel.frame = NSRect(x: 10, y: 6, width: 60, height: 14)
        card.addSubview(ctxLabel)

        let ctxValue = NSTextField(labelWithString: session.contextDescription)
        ctxValue.font = NSFont.systemFont(ofSize: 10, weight: .medium)
        ctxValue.textColor = contextValueColor(for: session.contextPercent)
        ctxValue.alignment = .right
        ctxValue.frame = NSRect(x: cardWidth - 80, y: 6, width: 70, height: 14)
        card.addSubview(ctxValue)

        return container
    }

    private func progressColor(for percent: Double) -> NSColor {
        if percent > 1.0 { return .systemRed }
        if percent > 0.75 { return .systemYellow }
        return .systemGreen
    }

    private func contextValueColor(for percent: Double) -> NSColor {
        if percent > 1.0 { return .systemRed }
        if percent > 0.75 { return .systemOrange }
        return .secondaryLabelColor
    }

    // MARK: - Actions

    @objc private func jumpToTerminal(_ sender: NSMenuItem) {
        guard let pid = sender.representedObject as? Int else { return }
        terminalActivator.activateTerminal(forPID: pid)
    }

    @objc private func toggleMute() {
        soundPlayer.isMuted.toggle()
        statusItem.menu = buildMenu()
    }

    // MARK: - State Change

    private func handleStateChange(from previous: SignalState, to current: SignalState) {
        guard previous != current else { return }
        for session in aggregator.sessions {
            soundPlayer.alertIfNeeded(for: session, previousState: previous)
        }
    }
}
