import SwiftUI
import AppKit

// MARK: - App Delegate (管理轮询生命周期)

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let aggregator = SignalAggregator()
    let soundPlayer = SoundPlayer()
    let terminalActivator = TerminalActivator()

    private let refreshInterval: TimeInterval = 2.0
    private var timer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 隐藏 Dock 图标（等效 LSUIElement=true）
        NSApp.setActivationPolicy(.accessory)

        // 立即刷新一次
        aggregator.refresh()

        // 启动定时轮询
        timer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                let prev = self.aggregator.globalState
                self.aggregator.refresh()
                self.handleStateChange(from: prev, to: self.aggregator.globalState)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
        timer = nil
    }

    @MainActor
    private func handleStateChange(from previous: SignalState, to current: SignalState) {
        guard previous != current else { return }
        for session in aggregator.sessions {
            soundPlayer.alertIfNeeded(for: session, previousState: previous)
        }
    }
}

// MARK: - App

@main
struct ClaudeSignalApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate

    var body: some Scene {
        MenuBarExtra {
            MenuBarView(
                aggregator: delegate.aggregator,
                soundPlayer: delegate.soundPlayer,
                terminalActivator: delegate.terminalActivator
            )
        } label: {
            Image(systemName: delegate.aggregator.globalState.sfSymbolName)
                .foregroundStyle(delegate.aggregator.globalState.color)
                .pulsingIfConfirming(delegate.aggregator.globalState == .confirming)
        }
        .menuBarExtraStyle(.menu)
    }
}

// MARK: - Pulse Animation Compatibility

extension View {
    @ViewBuilder
    func pulsingIfConfirming(_ isActive: Bool) -> some View {
        if #available(macOS 14.0, *) {
            self.symbolEffect(.pulse, options: .repeating, isActive: isActive)
        } else {
            self
        }
    }
}
