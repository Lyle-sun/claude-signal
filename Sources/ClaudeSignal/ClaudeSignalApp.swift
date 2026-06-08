import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private let aggregator = SignalAggregator()
    private let soundPlayer = SoundPlayer()
    private let terminalActivator = TerminalActivator()
    private var timer: Timer?
    private var lastAnimatedState: SignalState?
    private var beaconLayer: CALayer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Claude Signal"

        // 创建灯泡子图层（叠在塔身 image 上方，只动画这一层）
        let beacon = CALayer()
        beacon.contentsGravity = .resizeAspect
        beacon.masksToBounds = false
        button.layer?.addSublayer(beacon)
        beaconLayer = beacon

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
    }

    // MARK: - Icon Update

    private func updateIcon() {
        let state = aggregator.globalState
        guard let button = statusItem.button else { return }

        // 塔身 = 按钮 image（不动）
        button.image = towerImage(for: state)
        button.toolTip = "Claude Signal — \(state.description)"

        // 灯泡 = 子图层（动画）
        if let beacon = beaconLayer {
            beacon.frame = button.layer?.bounds ?? .zero
            beacon.contents = beaconImage(for: state)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            beacon.opacity = 1.0
        }

        // 菜单在打开时实时构建
        statusItem.menu = buildMenu()

        // 只在状态变化时更新动画
        if state != lastAnimatedState {
            updatePulseAnimation(for: state)
            lastAnimatedState = state
        }
    }

    // MARK: - Image Loading

    /// 加载塔身图片（白色/模板，不含灯泡）
    private func towerImage(for state: SignalState) -> NSImage {
        let isTemplate = (state == .idle || state == .error)
        let name = isTemplate ? "tower_template" : "tower"

        if let url = Bundle.main.url(forResource: name, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            img.isTemplate = isTemplate
            return img
        }

        let devPath = "/Users/lyle/Desktop/Projects/claude-signal/Sources/ClaudeSignal/Resources/\(name)_2x.png"
        if let img = NSImage(contentsOf: URL(fileURLWithPath: devPath)) {
            img.isTemplate = isTemplate
            return img
        }

        return simpleDot(color: state.nsColor, size: 18)
    }

    /// 加载灯泡图片（状态色，只有灯泡+光芒+光晕）
    private func beaconImage(for state: SignalState) -> NSImage? {
        let beaconName: String
        switch state {
        case .idle:       beaconName = "beacon_idle"
        case .running:    beaconName = "beacon_running"
        case .confirming: beaconName = "beacon_confirming"
        case .warning:    beaconName = "beacon_warning"
        case .critical:   beaconName = "beacon_critical"
        case .error:      beaconName = "beacon_error"
        }

        if let url = Bundle.main.url(forResource: beaconName, withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }

        let devPath = "/Users/lyle/Desktop/Projects/claude-signal/Sources/ClaudeSignal/Resources/\(beaconName)_2x.png"
        if let img = NSImage(contentsOf: URL(fileURLWithPath: devPath)) {
            return img
        }

        return nil
    }

    /// Fallback: 纯色圆点
    private func simpleDot(color: NSColor, size: CGFloat) -> NSImage {
        let img = NSImage(size: NSSize(width: size, height: size))
        img.lockFocus()
        let circle = NSBezierPath(ovalIn: NSRect(x: 3, y: 3, width: size - 6, height: size - 6))
        color.setFill()
        circle.fill()
        img.unlockFocus()
        img.isTemplate = false
        return img
    }

    // MARK: - Pulse Animation (只动画灯泡图层)

    private func updatePulseAnimation(for state: SignalState) {
        guard let beacon = beaconLayer else { return }

        // 先移除旧动画
        beacon.removeAnimation(forKey: "pulse")

        switch state {
        case .running:
            // 灯塔呼吸：只有灯泡层在闪，塔身不动
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.2
            pulse.duration = 1.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            beacon.add(pulse, forKey: "pulse")

        case .confirming, .critical:
            // 急促闪烁：灯泡快速明灭
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.05
            pulse.duration = 0.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            beacon.add(pulse, forKey: "pulse")

        default:
            // 静态，灯泡常亮
            beacon.opacity = 1.0
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
