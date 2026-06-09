import AppKit
import SwiftUI

/// 仪表盘窗口控制器 — 单例，管理 NSWindow 生命周期
final class DashboardWindowController: NSObject, NSWindowDelegate {
    static let shared = DashboardWindowController()

    private var window: NSWindow?
    private let minSize = NSSize(width: 600, height: 400)
    private let initialSize = NSSize(width: 780, height: 520)

    private override init() {
        super.init()
    }

    // MARK: - Window Lifecycle

    func openWindow(with aggregator: SignalAggregator, terminalActivator: TerminalActivating, usageStore: UsageStore? = nil) {
        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let contentView = DashboardView(aggregator: aggregator, terminalActivator: terminalActivator, usageStore: usageStore)
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = true
        hostingView.autoresizingMask = [.width, .height]

        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )

        newWindow.title = "Claude Signal"
        newWindow.contentView = hostingView
        newWindow.minSize = minSize
        newWindow.isReleasedWhenClosed = false
        newWindow.delegate = self

        // 恢复上次窗口位置
        restoreFrame(for: newWindow)

        newWindow.makeKeyAndOrderFront(nil)
        // LSUIElement=true 下必须显式激活
        NSApp.activate(ignoringOtherApps: true)

        self.window = newWindow
    }

    // MARK: - Frame Persistence

    private func restoreFrame(for window: NSWindow) {
        let defaults = UserDefaults.standard
        guard let frameString = defaults.string(forKey: "dashboardWindowFrame") else {
            window.center()
            return
        }
        let frame = NSRectFromString(frameString)
        // 确保窗口在可见屏幕区域内
        if NSScreen.screens.contains(where: { $0.visibleFrame.intersects(frame) }) {
            window.setFrame(frame, display: false)
        } else {
            window.center()
        }
    }

    private func saveFrame() {
        guard let window else { return }
        UserDefaults.standard.set(NSStringFromRect(window.frame), forKey: "dashboardWindowFrame")
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        saveFrame()
        // 销毁 hostingView 释放 SwiftUI diffing 开销
        window?.contentView = nil
        window = nil
    }
}
