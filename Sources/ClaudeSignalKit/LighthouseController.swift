import AppKit
import os.log

/// 灯塔控制器：菜单栏图标 + 灯泡动画 + 状态变化 + 声音 + 右键菜单
/// 从 AppDelegate 中提取，AppDelegate 只做编排
@MainActor
final class LighthouseController {
    private var statusItem: NSStatusItem!
    private let aggregator: SignalAggregator
    private var soundPlayer: SoundPlaying
    private let terminalActivator: TerminalActivating
    private var lastAnimatedState: SignalState?
    private var beaconLayer: CALayer?
    private var previousGlobalState: SignalState = .idle
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "Lighthouse")

    // Per-session 状态追踪（用于声音提醒）
    private var previousSessionStates: [Int: SignalState] = [:]

    init(aggregator: SignalAggregator, soundPlayer: SoundPlaying, terminalActivator: TerminalActivating) {
        self.aggregator = aggregator
        self.soundPlayer = soundPlayer
        self.terminalActivator = terminalActivator
    }

    // MARK: - Setup

    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.wantsLayer = true
        button.imagePosition = .imageOnly
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Claude Signal"

        // 创建灯泡子图层
        let beacon = CALayer()
        beacon.contentsGravity = .resizeAspect
        beacon.masksToBounds = false
        button.layer?.addSublayer(beacon)
        beaconLayer = beacon

        // 左右键均弹菜单（通过菜单 Open Dashboard 进入仪表盘）
        statusItem.menu = buildContextMenu()

        // 首次刷新
        updateIcon()
    }

    // MARK: - Icon Update

    func updateIcon() {
        let state = aggregator.globalState
        guard let button = statusItem.button else { return }

        // 塔身 = 按钮 image（不动）
        button.image = towerImage(for: state)
        button.toolTip = tooltipText(for: state)

        // 灯泡 = 子图层（动画）
        if let beacon = beaconLayer {
            beacon.frame = button.layer?.bounds ?? .zero
            beacon.contents = beaconImage(for: state)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
            beacon.opacity = 1.0
        }

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
        let running = sessions.filter { $0.signalState == .running }.count

        if confirming > 0 {
            return "Claude Signal — \(running) 个运行中 / \(confirming) 个等待确认"
        }
        return "Claude Signal — \(running) 个运行中"
    }

    // MARK: - Image Loading

    private func towerImage(for state: SignalState) -> NSImage {
        let isTemplate = (state == .idle || state == .error)
        let name = isTemplate ? "tower_template" : "tower"

        let img = Bundle.main.image(forResource: name)
        if let img {
            img.isTemplate = isTemplate
            return img
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

    // MARK: - Actions

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
