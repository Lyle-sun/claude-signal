import Foundation

/// Claude Code 会话状态（从 sessions/{pid}.json 的 status 字段解析）
enum SessionStatus: String, Decodable {
    case busy
    case idle
    case waiting
}

/// 一个 Claude Code 会话的信息
struct SessionInfo: Identifiable {
    var id: Int { pid }  // PID 即唯一标识

    let pid: Int
    let sessionId: String
    let cwd: String
    var status: SessionStatus
    var waitingFor: String?
    var contextTokens: Int
    var lastKnownTokens: Int?   // usage 缺失时保持上次值
    var isStale: Bool           // 进程已不存在

    // MARK: - Computed

    /// 会话显示名：项目目录名
    var projectName: String {
        URL(fileURLWithPath: cwd).lastPathComponent
    }

    /// 会话显示名（含 PID，仅调试用）
    var displayName: String {
        "\(projectName) (PID \(pid))"
    }

    /// Context 百分比（基于 200K 阈值）
    var contextPercent: Double {
        let maxTokens = 200_000
        return Double(contextTokens) / Double(maxTokens)
    }

    /// Context 用量人类可读描述
    var contextDescription: String {
        let k = contextTokens / 1000
        return "\(k)K / 200K"
    }

    /// 该会话对应的信号状态
    var signalState: SignalState {
        if isStale { return .idle }

        // 先检查 context 阈值
        if contextTokens > 200_000 { return .critical }
        if contextTokens > 150_000 { return .warning }

        // 再检查会话状态
        switch status {
        case .busy:     return .running
        case .idle:     return .idle
        case .waiting:  return .confirming
        }
    }
}

// MARK: - Session File Decoding

struct SessionFile: Decodable {
    let pid: Int
    let sessionId: String
    let cwd: String
    let status: SessionStatus
    let waitingFor: String?
}

// MARK: - JSONL Usage Decoding

struct JsonlMessage: Decodable {
    let type: String?
    let message: JsonlMessageContent?
}

struct JsonlMessageContent: Decodable {
    let usage: UsageData?
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
}
