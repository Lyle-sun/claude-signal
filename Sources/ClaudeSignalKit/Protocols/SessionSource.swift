import Foundation

/// 统一数据源协议 — 所有 AI CLI 工具的会话数据通过此接口提供
/// 当前实现：ClaudeCodeSource
/// 未来实现：CodexSource 等
protocol SessionSource: AnyObject {
    /// 数据源标识（如 "claude-code"）
    var sourceIdentifier: String { get }

    /// 显示名称（如 "Claude Code"）
    var displayName: String { get }

    /// SF Symbol 图标名称
    var systemImageName: String { get }

    /// Context 窗口上限（token 数）
    var contextWindowLimit: Int { get }

    /// 获取所有活跃会话
    func fetchSessions() -> [SessionInfo]

    /// 获取指定会话的 context token 数
    func fetchContextTokens(sessionId: String, cwd: String) -> Int?

    /// 获取指定会话最后一轮 assistant usage 快照
    func fetchLatestUsageSnapshot(sessionId: String, cwd: String) -> UsageSnapshot?
}
