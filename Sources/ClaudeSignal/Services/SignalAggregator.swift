import Foundation
import os.log

/// 合并多信号源 → 统一状态 → 灯色决策
final class SignalAggregator: ObservableObject {
    @Published var globalState: SignalState = .idle
    @Published var sessions: [SessionInfo] = []
    @Published var errorMessage: String?

    let soundPlayer = SoundPlayer()
    let terminalActivator = TerminalActivator()

    private let sessionMonitor = SessionMonitor()
    private let contextMonitor = ContextMonitor()

    /// 是否检测到 Claude Code 安装
    var claudeCodeInstalled: Bool {
        sessionMonitor.claudeDirExists
    }

    /// 刷新所有会话状态
    func refresh() {
        guard claudeCodeInstalled else {
            globalState = .error
            errorMessage = "Claude Code 未检测到"
            sessions = []
            return
        }

        var currentSessions = sessionMonitor.fetchSessions()

        for i in currentSessions.indices {
            if let tokens = contextMonitor.fetchContextTokens(
                sessionId: currentSessions[i].sessionId,
                cwd: currentSessions[i].cwd
            ) {
                currentSessions[i].contextTokens = tokens
                currentSessions[i].lastKnownTokens = tokens
            } else if let last = currentSessions[i].lastKnownTokens {
                currentSessions[i].contextTokens = last
            }
        }

        if currentSessions.isEmpty {
            globalState = .idle
            errorMessage = nil
        } else {
            globalState = currentSessions.map(\.signalState).max() ?? .idle
            errorMessage = nil
        }

        sessions = currentSessions
    }
}
