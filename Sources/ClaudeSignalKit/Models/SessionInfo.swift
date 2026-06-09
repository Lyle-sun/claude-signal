import Foundation

/// Claude Code 会话状态（从 sessions/{pid}.json 的 status 字段解析）
public enum SessionStatus: String, Decodable {
    case busy
    case idle
    case waiting
}

/// 一个 Claude Code 会话的信息
public struct SessionInfo: Identifiable {
    public var id: Int { pid }  // PID 即唯一标识

    public let pid: Int
    public let sessionId: String
    public let cwd: String
    public var status: SessionStatus
    public var waitingFor: String?
    public var contextTokens: Int
    public var lastKnownTokens: Int?   // usage 缺失时保持上次值
    public var lastInputTokens: Int?
    public var lastOutputTokens: Int?
    public var lastCacheReadTokens: Int?
    public var modelName: String?
    public var isStale: Bool           // 进程已不存在
    public var sessionName: String?    // 从 jsonl 解码的会话名（可能为空）
    public var startedAt: Date?
    public var sourceIdentifier: String = "claude-code"  // 数据源标识

    /// Context 窗口上限（从 SessionSource 注入，不再硬编码 200K）
    public var contextWindowLimit: Int = 200_000

    /// Context 警告阈值（默认为 contextWindowLimit 的 75%）
    public var contextWarningThreshold: Int {
        Int(Double(contextWindowLimit) * 0.75)
    }

    public init(
        pid: Int,
        sessionId: String,
        cwd: String,
        status: SessionStatus,
        waitingFor: String? = nil,
        contextTokens: Int,
        lastKnownTokens: Int? = nil,
        lastInputTokens: Int? = nil,
        lastOutputTokens: Int? = nil,
        lastCacheReadTokens: Int? = nil,
        modelName: String? = nil,
        isStale: Bool = false,
        sessionName: String? = nil,
        startedAt: Date? = nil,
        sourceIdentifier: String = "claude-code",
        contextWindowLimit: Int = 200_000
    ) {
        self.pid = pid
        self.sessionId = sessionId
        self.cwd = cwd
        self.status = status
        self.waitingFor = waitingFor
        self.contextTokens = contextTokens
        self.lastKnownTokens = lastKnownTokens
        self.lastInputTokens = lastInputTokens
        self.lastOutputTokens = lastOutputTokens
        self.lastCacheReadTokens = lastCacheReadTokens
        self.modelName = modelName
        self.isStale = isStale
        self.sessionName = sessionName
        self.startedAt = startedAt
        self.sourceIdentifier = sourceIdentifier
        self.contextWindowLimit = contextWindowLimit
    }

    // MARK: - Computed

    /// 会话显示名：优先 sessionName，否则用项目目录名
    public var projectName: String {
        sessionName ?? URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// 会话显示名（含 PID，仅调试用）
    public var displayName: String {
        "\(projectName) (PID \(pid))"
    }

    /// Context 百分比（基于注入的 contextWindowLimit）
    public var contextPercent: Double {
        Double(contextTokens) / Double(contextWindowLimit)
    }

    /// Context 用量人类可读描述
    public var contextDescription: String {
        let used = contextTokens / 1000
        let max = contextWindowLimit / 1000
        return "\(used)K / \(max)K"
    }

    /// Context 利用率描述
    public var contextPercentDescription: String {
        "\(Int((contextPercent * 100).rounded()))%"
    }

    /// 会话运行时长描述
    public var durationDescription: String {
        guard let startedAt else { return "未知" }
        let seconds = max(0, Int(Date().timeIntervalSince(startedAt)))
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours > 0 {
            return "\(hours)h \(minutes)m"
        }
        return "\(minutes)m"
    }

    /// 该会话对应的信号状态
    /// 优先级：stale > critical > confirming > warning > running > idle
    public var signalState: SignalState {
        if isStale { return .idle }

        // critical（context 超限）是硬限制，优先级最高
        if contextTokens > contextWindowLimit { return .critical }

        // confirming（等待确认）需要用户操作，优先于 warning
        if status == .waiting { return .confirming }

        // warning（context 接近限制）是提醒
        if contextTokens > contextWarningThreshold { return .warning }

        // 其余按会话状态
        switch status {
        case .busy:     return .running
        case .idle:     return .idle
        case .waiting:  return .confirming  // unreachable, kept for exhaustiveness
        }
    }
}

// MARK: - Session File Decoding

struct SessionFile: Decodable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let startedAt: Int64?
    let status: SessionStatus
    let waitingFor: String?
    let name: String?  // Optional: Claude Code 可能不写入此字段
}

// MARK: - JSONL Usage Decoding

struct JsonlMessage: Decodable {
    let type: String?
    let message: JsonlMessageContent?
}

struct JsonlMessageContent: Decodable {
    let model: String?
    let usage: UsageData?
}

struct UsageSnapshot {
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let model: String?

    var contextTokens: Int {
        inputTokens + cacheReadTokens
    }
}

struct UsageData: Decodable {
    let inputTokens: Int?
    let cacheReadInputTokens: Int?
    let outputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
    }

    /// 总 context token 数（不含 output_tokens）
    var totalContextTokens: Int {
        (inputTokens ?? 0) + (cacheReadInputTokens ?? 0)
    }

    var snapshotTokens: UsageSnapshot {
        UsageSnapshot(
            inputTokens: inputTokens ?? 0,
            outputTokens: outputTokens ?? 0,
            cacheReadTokens: cacheReadInputTokens ?? 0,
            model: nil
        )
    }
}
