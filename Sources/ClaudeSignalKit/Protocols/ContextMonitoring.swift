import Foundation

/// Context 监控协议 — 读取会话的 token 用量
protocol ContextMonitoring {
    /// 获取指定会话的 context token 数
    func fetchContextTokens(sessionId: String, cwd: String) -> Int?
}
