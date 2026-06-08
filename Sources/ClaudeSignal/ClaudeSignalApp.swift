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
    private var popover: NSPopover?
    private var popoverVC: NSViewController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 创建菜单栏图标
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp])

        // 创建 Popover
        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentSize = NSSize(width: 320, height: 280)
        let vc = NSViewController()
        vc.view = NSView()
        popover.contentViewController = vc
        self.popover = popover
        self.popoverVC = vc

        // 首次刷新
        aggregator.refresh()
        updateIcon()
        updatePopoverContent()

        // 启动轮询
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            let prev = self.aggregator.globalState
            self.aggregator.refresh()
            self.updateIcon()
            self.updatePopoverContent()
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

        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        if let image = NSImage(systemSymbolName: state.sfSymbolName, accessibilityDescription: state.description)?
            .withSymbolConfiguration(config) {
            image.isTemplate = true
            button.image = image
            button.imagePosition = .imageOnly
        }
        button.imageScaling = .scaleProportionallyDown
        button.toolTip = "Claude Signal — \(state.description)"

        // confirming / critical 时启动脉冲动画
        updatePulseAnimation(for: state)
    }

    // MARK: - Pulse Animation

    private func updatePulseAnimation(for state: SignalState) {
        // 停止旧动画
        pulseTimer?.invalidate()
        pulseTimer = nil
        isPulseOn = true

        guard state.needsAction, let altSymbol = state.pulseAlternateSymbol else { return }

        // 每 0.8 秒交替图标
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
        pulseTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self, let button = self.statusItem.button else { return }
            self.isPulseOn.toggle()
            let symbolName = self.isPulseOn ? state.sfSymbolName : altSymbol
            if let image = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(config) {
                image.isTemplate = true
                button.image = image
            }
        }
    }

    // MARK: - Popover

    private func updatePopoverContent() {
        guard let popover, let popoverVC else { return }

        let view = PopoverView(
            sessions: aggregator.sessions,
            globalState: aggregator.globalState,
            isMuted: soundPlayer.isMuted,
            onJump: { [weak self] pid in
                self?.terminalActivator.activateTerminal(forPID: pid)
                self?.popover?.performClose(nil)
            },
            onToggleMute: { [weak self] in
                self?.soundPlayer.isMuted.toggle()
                self?.updatePopoverContent()
            },
            onQuit: {
                NSApp.terminate(nil)
            }
        )

        let hostingView = NSHostingView(rootView: view)
        hostingView.frame = popoverVC.view.bounds
        hostingView.autoresizingMask = [.width, .height]

        // 替换内容
        popoverVC.view.subviews.forEach { $0.removeFromSuperview() }
        popoverVC.view.addSubview(hostingView)

        // 根据内容调整高度
        let height = max(200, 80 + aggregator.sessions.count * 90)
        popover.contentSize = NSSize(width: 320, height: min(height, 500))
    }

    // MARK: - Actions

    @objc private func statusItemClicked() {
        guard let button = statusItem.button, let popover else { return }

        if popover.isShown {
            popover.performClose(nil)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
    }

    // MARK: - State Change

    private func handleStateChange(from previous: SignalState, to current: SignalState) {
        guard previous != current else { return }
        for session in aggregator.sessions {
            soundPlayer.alertIfNeeded(for: session, previousState: previous)
        }
    }
}
