import Foundation

/// Claude Code 数据源 — 唯一的 SessionSource 实现
/// 未来 Codex 等可实现同样的协议
final class ClaudeCodeSource: SessionSource {
    let sourceIdentifier = "claude-code"
    let displayName = "Claude Code"
    let systemImageName = "terminal"
    let contextWindowLimit = 200_000
    var isInstalled: Bool { sessionMonitor.isInstalled }

    private let sessionMonitor: SessionMonitor
    private let contextMonitor: ContextMonitor

    /// 最近一次实时 usage 快照。jsonl 尾部暂时没有 assistant usage 时，使用这个缓存保持 UI 稳定。
    private var latestUsageSnapshots: [String: UsageSnapshot] = [:]

    init(claudeDir: URL? = nil, databaseURL: URL? = nil) {
        self.sessionMonitor = SessionMonitor(claudeDir: claudeDir)
        self.contextMonitor = ContextMonitor(claudeDir: claudeDir)
    }

    func fetchSessions() -> [SessionInfo] {
        sessionMonitor.fetchSessions()
    }

    func fetchLatestUsageSnapshot(sessionId: String, cwd: String) -> UsageSnapshot? {
        if let snapshot = contextMonitor.fetchLatestUsageSnapshot(sessionId: sessionId, cwd: cwd) {
            latestUsageSnapshots[sessionId] = snapshot
            return snapshot
        }
        return latestUsageSnapshots[sessionId]
    }
}
