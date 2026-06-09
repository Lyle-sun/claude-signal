import Foundation
import os.log

/// 合并多信号源 → 统一状态 → 灯色决策
@MainActor
final class SignalAggregator: ObservableObject {
    @Published var globalState: SignalState = .idle
    @Published var sessions: [SessionInfo] = []
    @Published var errorMessage: String?

    private var sources: [SessionSource]
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "SignalAggregator")

    init(sources: [SessionSource] = []) {
        self.sources = sources
    }

    /// 后续配置数据源（AppDelegate 初始化时使用）
    func configure(sources: [SessionSource]) {
        self.sources = sources
    }

    /// 是否检测到任何数据源安装
    var anySourceInstalled: Bool {
        sources.contains { source in
            if let monitor = source as? SessionMonitoring {
                return monitor.isInstalled
            }
            return true
        }
    }

    /// 刷新所有会话状态
    /// I/O 在后台队列执行，结果发布到 @MainActor
    func refresh() {
        guard !sources.isEmpty else {
            globalState = .error
            errorMessage = "No data sources configured"
            sessions = []
            return
        }

        // 在后台队列执行 I/O 密集操作
        let currentSources = sources
        DispatchQueue.global(qos: .utility).async { [weak self] in
            var allSessions: [SessionInfo] = []

            for source in currentSources {
                let sourceSessions = source.fetchSessions().map { session -> SessionInfo in
                    var s = session
                    s.sourceIdentifier = source.sourceIdentifier
                    s.contextWindowLimit = source.contextWindowLimit
                    return s
                }
                allSessions.append(contentsOf: sourceSessions)
            }

            // 为每个会话获取 context token
            for i in allSessions.indices {
                let source = currentSources.first { $0.sourceIdentifier == allSessions[i].sourceIdentifier }
                if let snapshot = source?.fetchLatestUsageSnapshot(
                    sessionId: allSessions[i].sessionId,
                    cwd: allSessions[i].cwd
                ) {
                    allSessions[i].contextTokens = snapshot.contextTokens
                    allSessions[i].lastKnownTokens = snapshot.contextTokens
                    allSessions[i].lastInputTokens = snapshot.inputTokens
                    allSessions[i].lastOutputTokens = snapshot.outputTokens
                    allSessions[i].lastCacheReadTokens = snapshot.cacheReadTokens
                    allSessions[i].modelName = snapshot.model
                } else if let tokens = source?.fetchContextTokens(
                    sessionId: allSessions[i].sessionId,
                    cwd: allSessions[i].cwd
                ) {
                    allSessions[i].contextTokens = tokens
                    allSessions[i].lastKnownTokens = tokens
                } else if let last = allSessions[i].lastKnownTokens {
                    allSessions[i].contextTokens = last
                }
            }

            // 发布到 @MainActor
            Task { @MainActor [weak self] in
                guard let self else { return }

                if allSessions.isEmpty {
                    self.globalState = .idle
                    self.errorMessage = nil
                } else {
                    self.globalState = allSessions.map(\.signalState).max() ?? .idle
                    self.errorMessage = nil
                }

                self.sessions = allSessions
            }
        }
    }
}
