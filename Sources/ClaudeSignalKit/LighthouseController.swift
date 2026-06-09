import AppKit
import os.log

/// 灯塔控制器：菜单栏图标 + 灯泡动画 + 状态变化 + 声音 + 右键菜单
/// 从 AppDelegate 中提取，AppDelegate 只做编排
@MainActor
final class LighthouseController {
    private var statusItem: NSStatusItem!
    private let aggregator: SignalAggregator
    private var soundPlayer: SoundPlaying
    private var lastAnimatedState: SignalState?
    private var beaconLayer: CALayer?
    private var previousGlobalState: SignalState = .idle
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "Lighthouse")

    // Per-session 状态追踪（用于声音提醒）
    private var previousSessionStates: [Int: SignalState] = [:]
    private var actionStateEnteredAt: [Int: Date] = [:]

    init(aggregator: SignalAggregator, soundPlayer: SoundPlaying) {
        self.aggregator = aggregator
        self.soundPlayer = soundPlayer
    }

    // MARK: - Setup

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.imagePosition = .imageLeft
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Claude Signal"
        button.target = self
        button.action = #selector(handleStatusItemClick(_:))
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        // 首次刷新
        updateIcon()
    }

    // MARK: - Icon Update

    func updateIcon() {
        let state = aggregator.globalState
        guard let button = statusItem.button else { return }

        button.image = statusIconImage(for: state)
        updateBadgeTitle(on: button, state: state)
        button.toolTip = tooltipText(for: state)

        // 只在状态变化时更新动画
        if state != lastAnimatedState {
            updatePulseAnimation(for: state)
            lastAnimatedState = state
        }
    }

    /// 处理状态变化：per-session 声音提醒
    func handleStateChange() {
        let currentSessions = aggregator.sessions

        for session in currentSessions {
            let previousState = previousSessionStates[session.pid]
            soundPlayer.alertIfNeeded(for: session, previousState: previousState)

            if session.signalState.needsAction {
                if previousState != session.signalState || actionStateEnteredAt[session.pid] == nil {
                    actionStateEnteredAt[session.pid] = Date()
                }
            } else {
                actionStateEnteredAt.removeValue(forKey: session.pid)
            }

            // 如果会话从 confirming 离开，重置声音冷却
            if previousState == .confirming && session.signalState != .confirming {
                soundPlayer.sessionLeftConfirming(pid: session.pid)
            }

            previousSessionStates[session.pid] = session.signalState
        }

        // 清理已消失的会话
        let currentPIDs = Set(currentSessions.map(\.pid))
        for pid in previousSessionStates.keys {
            if !currentPIDs.contains(pid) {
                previousSessionStates.removeValue(forKey: pid)
                actionStateEnteredAt.removeValue(forKey: pid)
                soundPlayer.removeSession(pid: pid)
            }
        }

        previousGlobalState = aggregator.globalState
    }

    // MARK: - Tooltip

    private func tooltipText(for state: SignalState) -> String {
        let sessions = aggregator.sessions
        if sessions.isEmpty {
            return "Claude Signal — \(state.description)"
        }

        let confirming = sessions.filter { $0.signalState == .confirming }.count
        let critical = sessions.filter { $0.signalState == .critical }.count
        let running = sessions.filter { $0.signalState == .running }.count

        if confirming > 0 || critical > 0 {
            return "Claude Signal — \(confirming) 个等待确认 / \(critical) 个 Context 超限"
        }
        return "Claude Signal — \(running) 个运行中"
    }

    // MARK: - Image Loading

    private func statusIconImage(for state: SignalState) -> NSImage {
        let iconSide: CGFloat = 22
        let size = NSSize(width: iconSide, height: iconSide)
        let image = NSImage(size: size)

        image.lockFocus()

        let iconRect = NSRect(x: 0, y: 0, width: iconSide, height: iconSide)
        towerImage(for: state).draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)
        beaconImage(for: state)?.draw(in: iconRect, from: .zero, operation: .sourceOver, fraction: 1)

        image.unlockFocus()
        image.isTemplate = false
        return image
    }

    private func updateBadgeTitle(on button: NSStatusBarButton, state: SignalState) {
        let count = actionableSessionCount
        guard count >= 2 else {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            return
        }

        let badgeFont = NSFont.systemFont(ofSize: 13, weight: .light)
        let badgeText = "\(count)"
        let badgeAttributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: NSColor.white.withAlphaComponent(0.94),
            .font: badgeFont,
            .baselineOffset: 0
        ]
        button.attributedTitle = NSAttributedString(string: badgeText, attributes: badgeAttributes)
    }

    private func towerImage(for state: SignalState) -> NSImage {
        let isTemplate = (state == .idle)
        let name = isTemplate ? "tower_template" : "tower"

        let img = Bundle.main.image(forResource: name)
        if let img {
            let copy = img.copy() as? NSImage ?? img
            copy.isTemplate = isTemplate
            return copy
        }

        return simpleDot(color: state.nsColor, size: 18)
    }

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

        return Bundle.main.image(forResource: beaconName)
    }

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

    // MARK: - Pulse Animation

    private func updatePulseAnimation(for state: SignalState) {
        guard let beacon = beaconLayer else { return }

        beacon.removeAnimation(forKey: "pulse")

        switch state {
        case .running:
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.2
            pulse.duration = 1.8
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            beacon.add(pulse, forKey: "pulse")

        case .confirming, .critical:
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1.0
            pulse.toValue = 0.05
            pulse.duration = 0.6
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            beacon.add(pulse, forKey: "pulse")

        default:
            beacon.opacity = 1.0
        }
    }

    // MARK: - Right-Click Menu

    private func buildContextMenu() -> NSMenu {
        let menu = NSMenu()

        menu.addItem(readOnlyMenuItem(title: statusSummaryText(), iconName: "circle.fill", isHeading: false))
        menu.addItem(NSMenuItem.separator())

        let actionable = actionableSessions
        if !actionable.isEmpty {
            menu.addItem(readOnlyMenuItem(title: "待处理会话", iconName: nil, isHeading: true))

            for session in actionable {
                menu.addItem(
                    readOnlyMenuItem(
                        title: actionableMenuTitle(for: session),
                        iconName: session.signalState == .confirming ? "exclamationmark.circle" : "gauge.with.dots.needle.100percent",
                        isHeading: false
                    )
                )
            }

            menu.addItem(NSMenuItem.separator())
        }

        let openItem = NSMenuItem(title: "打开仪表盘", action: #selector(openDashboard), keyEquivalent: "")
        openItem.target = self
        openItem.image = NSImage(systemSymbolName: "chart.bar", accessibilityDescription: nil)
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        let muteTitle = soundPlayer.isMuted ? "取消静音" : "静音"
        let muteIcon = soundPlayer.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        let muteItem = NSMenuItem(title: muteTitle, action: #selector(toggleMute), keyEquivalent: "")
        muteItem.target = self
        muteItem.image = NSImage(systemSymbolName: muteIcon, accessibilityDescription: nil)
        menu.addItem(muteItem)

        menu.addItem(NSMenuItem.separator())

        let quitItem = NSMenuItem(title: "退出 Claude Signal", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)

        return menu
    }

    private func readOnlyMenuItem(title: String, iconName: String?, isHeading: Bool) -> NSMenuItem {
        let item = NSMenuItem()
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 280, height: isHeading ? 22 : 26))

        let stack = NSStackView()
        stack.orientation = .horizontal
        stack.alignment = .centerY
        stack.spacing = 8
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        if let iconName {
            let imageView = NSImageView()
            imageView.image = NSImage(systemSymbolName: iconName, accessibilityDescription: nil)
            imageView.contentTintColor = isHeading ? .secondaryLabelColor : .labelColor
            imageView.translatesAutoresizingMaskIntoConstraints = false
            imageView.widthAnchor.constraint(equalToConstant: 14).isActive = true
            imageView.heightAnchor.constraint(equalToConstant: 14).isActive = true
            stack.addArrangedSubview(imageView)
        }

        let label = NSTextField(labelWithString: title)
        label.font = isHeading ? .systemFont(ofSize: 12, weight: .semibold) : .systemFont(ofSize: 13)
        label.textColor = isHeading ? .secondaryLabelColor : .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.maximumNumberOfLines = 1
        stack.addArrangedSubview(label)

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 12),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -12),
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])

        item.view = view
        return item
    }

    // MARK: - Actions

    @objc private func handleStatusItemClick(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        switch event.type {
        case .rightMouseUp:
            let menu = buildContextMenu()
            menu.popUp(positioning: nil, at: CGPoint(x: 0, y: sender.bounds.maxY + 2), in: sender)
        default:
            return
        }
    }

    private var actionableSessionCount: Int {
        aggregator.sessions.filter { $0.signalState.needsAction }.count
    }

    private var actionableSessions: [SessionInfo] {
        aggregator.sessions
            .filter { $0.signalState.needsAction }
            .sorted { lhs, rhs in
                let lhsEntered = actionStateEnteredAt[lhs.pid] ?? .distantFuture
                let rhsEntered = actionStateEnteredAt[rhs.pid] ?? .distantFuture
                return lhsEntered < rhsEntered
            }
    }

    private func statusSummaryText() -> String {
        let sessions = aggregator.sessions
        let confirming = sessions.filter { $0.signalState == .confirming }.count
        let critical = sessions.filter { $0.signalState == .critical }.count
        let actionable = confirming + critical

        if actionable == 0 {
            let running = sessions.filter { $0.signalState == .running }.count
            if running > 0 {
                return "\(running) 个会话运行中"
            }
            return "空闲 · 无活跃会话"
        }

        if actionable == 1 {
            if confirming == 1 { return "1 个会话等待确认" }
            return "1 个会话 Context 超限"
        }

        var parts: [String] = []
        if confirming > 0 {
            parts.append("\(confirming) 个等待确认")
        }
        if critical > 0 {
            parts.append("\(critical) 个 Context 超限")
        }
        return parts.joined(separator: " · ")
    }

    private func actionableMenuTitle(for session: SessionInfo) -> String {
        switch session.signalState {
        case .confirming:
            return "\(session.projectName) — 等待确认 · \(durationText(for: session))"
        case .critical:
            return "\(session.projectName) — Context 超限"
        default:
            return "\(session.projectName) — \(session.signalState.description)"
        }
    }

    private func durationText(for session: SessionInfo) -> String {
        let start = actionStateEnteredAt[session.pid] ?? Date()
        let seconds = max(0, Int(Date().timeIntervalSince(start)))
        if seconds >= 3600 {
            return "\(seconds / 3600)h \((seconds % 3600) / 60)m"
        }
        if seconds >= 60 {
            return "\(seconds / 60)m\(seconds % 60)s"
        }
        return "\(seconds)s"
    }

    @objc private func openDashboard() {
        NotificationCenter.default.post(name: .openDashboard, object: nil)
    }

    @objc private func toggleMute() {
        soundPlayer.isMuted.toggle()
    }
}

// MARK: - Notification Name

extension Notification.Name {
    static let openDashboard = Notification.Name("com.claude-signal.openDashboard")
}
