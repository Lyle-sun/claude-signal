import Foundation
import os.log

/// 合并多信号源 → 统一状态 → 灯色决策
@MainActor
final class SignalAggregator: ObservableObject {
    @Published var globalState: SignalState = .idle
    @Published var sessions: [SessionInfo] = []
    @Published var errorMessage: String?

    private let sessionMonitor = SessionMonitor()
    private let contextMonitor = ContextMonitor()
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "SignalAggregator")

    /// 是否检测到 Claude Code 安装
    var claudeCodeInstalled: Bool {
        sessionMonitor.claudeDirExists
    }

    /// 刷新所有会话状态
    func refresh() {
        // 1. 检测 Claude Code 是否安装
        guard claudeCodeInstalled else {
            globalState = .error
            errorMessage = "Claude Code 未检测到"
            sessions = []
            return
        }

        // 2. 获取会话列表
        var currentSessions = sessionMonitor.fetchSessions()

        // 3. 为每个会话补充 context token 数据
        for i in currentSessions.indices {
            if let tokens = contextMonitor.fetchContextTokens(
                sessionId: currentSessions[i].sessionId,
                cwd: currentSessions[i].cwd
            ) {
                currentSessions[i].contextTokens = tokens
                currentSessions[i].lastKnownTokens = tokens
            } else if let last = currentSessions[i].lastKnownTokens {
                // usage 缺失时保持上次值
                currentSessions[i].contextTokens = last
            }
            // 两者都没有时 contextTokens 保持 0
        }

        // 4. 聚合全局状态：取优先级最高的
        if currentSessions.isEmpty {
            globalState = .idle
            errorMessage = nil
        } else {
            globalState = currentSessions.map(\.signalState).max() ?? .idle
            errorMessage = nil
        }

        sessions = currentSessions
        logger.debug("Refreshed: \(self.sessions.count) sessions, global state: \(self.globalState.description)")
    }
}
