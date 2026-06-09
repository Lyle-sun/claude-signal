import Foundation

/// Claude Code JSONL 顶层记录。
/// 实时 tail 解析和后台索引共享同一套模型，避免 schema 变化时两边漂移。
struct ClaudeCodeJsonlRecord: Decodable {
    let type: String?
    let sessionId: String?
    let timestamp: String?
    let cwd: String?
    let message: ClaudeCodeJsonlMessage?
}

struct ClaudeCodeJsonlMessage: Decodable {
    let model: String?
    let usage: ClaudeCodeJsonlUsage?
}

struct ClaudeCodeJsonlUsage: Decodable {
    let inputTokens: Int?
    let cacheReadInputTokens: Int?
    let outputTokens: Int?
    let cacheCreationInputTokens: Int?

    enum CodingKeys: String, CodingKey {
        case inputTokens = "input_tokens"
        case cacheReadInputTokens = "cache_read_input_tokens"
        case outputTokens = "output_tokens"
        case cacheCreationInputTokens = "cache_creation_input_tokens"
    }
}
