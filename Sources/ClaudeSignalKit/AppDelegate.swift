import AppKit

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {
    private let aggregator = SignalAggregator()
    private let soundPlayer = SoundPlayer()
    private let terminalActivator = TerminalActivator()
    private var lighthouse: LighthouseController?
    private var timer: Timer?
    private let indexerCoordinator = IndexerCoordinator()

    nonisolated public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        // 注入数据源（传入 databaseURL 用于从 SQLite 读取 context tokens）
        let claudeCodeSource = ClaudeCodeSource(databaseURL: indexerCoordinator.databaseURL)
        aggregator.configure(sources: [claudeCodeSource])

        // 创建灯塔控制器
        lighthouse = LighthouseController(
            aggregator: aggregator,
            soundPlayer: soundPlayer,
            terminalActivator: terminalActivator
        )
        lighthouse?.setupStatusItem()

        // 监听"打开仪表盘"通知
        NotificationCenter.default.addObserver(
            forName: .openDashboard,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                DashboardWindowController.shared.openWindow(
                    with: self.aggregator,
                    terminalActivator: self.terminalActivator,
                    usageStore: self.indexerCoordinator.usageStore
                )
            }
        }

        // 首次刷新
        aggregator.refresh()
        lighthouse?.updateIcon()

        // 启动后台索引
        indexerCoordinator.startIndexing()

        // 启动轮询
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.aggregator.refresh()
                self.lighthouse?.updateIcon()
                self.lighthouse?.handleStateChange()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        timer?.invalidate()
    }
}
