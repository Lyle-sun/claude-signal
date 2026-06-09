import Foundation
import os.log

/// Claude Code jsonl 解析器
/// 独立于 ContextMonitor 的实时解析，专为 Indexer 设计
/// ContextMonitor 做实时 tail-read（只取最后 usage），Indexer 做全量增量解析
public struct ClaudeCodeJsonlParser {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "JsonlParser")

    public init() {}

    /// 单行最大长度（超过则跳过）
    private let maxLineLength = 1_000_000 // 1MB

    /// 解析结果：一条 assistant 消息的用量数据
    public struct ParsedUsage: Sendable {
        public let sessionId: String
        public let model: String
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let timestamp: String       // ISO8601
        public let projectSlug: String
        public let cwd: String
    }

    /// 解析整个 jsonl 文件，从指定字节偏移量开始
    /// - Parameters:
    ///   - fileURL: jsonl 文件路径
    ///   - byteOffset: 起始偏移量（0 = 全量解析）
    /// - Returns: (解析结果数组, 读取的字节数, 错误数)
    public func parseFile(fileURL: URL, byteOffset: UInt64 = 0) -> (results: [ParsedUsage], bytesProcessed: UInt64, errorCount: Int) {
        guard let fileHandle = try? FileHandle(forReadingFrom: fileURL) else {
            logger.warning("Failed to open jsonl: \(fileURL.lastPathComponent)")
            return ([], 0, 0)
        }
        defer { try? fileHandle.close() }

        // 获取文件大小
        guard let fileSize = try? fileHandle.seekToEnd() else {
            return ([], 0, 0)
        }

        // 如果 offset 超过文件大小（文件被截断或替换），从头开始
        var effectiveOffset = byteOffset
        if byteOffset > fileSize {
            logger.info("File truncated or replaced, resetting offset from \(byteOffset) to 0")
            effectiveOffset = 0
        }

        // seek 到偏移量
        try? fileHandle.seek(toOffset: effectiveOffset)

        // 读取剩余内容
        let remainingSize = fileSize - effectiveOffset
        guard remainingSize > 0 else {
            return ([], fileSize, 0)
        }

        let readSize = Int(min(remainingSize, UInt64(10 * 1024 * 1024))) // 最多 10MB
        guard let data = try? fileHandle.read(upToCount: readSize),
              let content = String(data: data, encoding: .utf8) else {
            logger.warning("Failed to read jsonl content")
            return ([], fileSize, 0)
        }

        // 提取项目 slug（从文件路径中获取）
        let projectSlug = fileURL.deletingLastPathComponent().lastPathComponent
        // sessionId 就是文件名（去掉 .jsonl 后缀）
        let sessionId = fileURL.deletingPathExtension().lastPathComponent

        var results: [ParsedUsage] = []
        var errorCount = 0

        content.enumerateLines { line, _ in
            guard !line.isEmpty else { return }
            guard line.count <= self.maxLineLength else {
                self.logger.warning("Skipping oversized line (\(line.count) chars)")
                errorCount += 1
                return
            }

            guard let lineData = line.data(using: .utf8) else {
                errorCount += 1
                return
            }

            do {
                let obj = try JSONDecoder().decode(JsonlTopLevel.self, from: lineData)

                // 只处理 assistant 类型且有 usage 的消息
                guard obj.type == "assistant",
                      let message = obj.message,
                      let usage = message.usage else {
                    return
                }

                // 跳过 synthetic 消息（无真实 token）
                let model = message.model ?? "unknown"
                guard !ModelPricing.isSyntheticModel(model) else { return }

                // 跳过全零 usage（synthetic 可能漏标）
                let inputTokens = usage.inputTokens ?? 0
                let outputTokens = usage.outputTokens ?? 0
                let cacheReadTokens = usage.cacheReadInputTokens ?? 0
                guard inputTokens > 0 || outputTokens > 0 || cacheReadTokens > 0 else { return }

                let parsed = ParsedUsage(
                    sessionId: obj.sessionId ?? sessionId,
                    model: model,
                    inputTokens: inputTokens,
                    outputTokens: outputTokens,
                    cacheReadTokens: cacheReadTokens,
                    timestamp: obj.timestamp ?? "",
                    projectSlug: projectSlug,
                    cwd: obj.cwd ?? ""
                )
                results.append(parsed)
            } catch {
                self.logger.debug("JSON decode error at offset: \(error.localizedDescription)")
                errorCount += 1
            }
        }

        return (results, fileSize, errorCount)
    }
}

// MARK: - JSONL Decoding Models

/// jsonl 顶层对象（比 ContextMonitor 的 JsonlMessage 更完整）
struct JsonlTopLevel: Decodable {
    let type: String?
    let sessionId: String?
    let timestamp: String?
    let cwd: String?
    let message: JsonlTopLevelMessage?
}

/// jsonl 中 assistant 消息的 message 字段
struct JsonlTopLevelMessage: Decodable {
    let model: String?
    let usage: JsonlTopLevelUsage?
}

/// jsonl 中 assistant 消息的 usage 字段
struct JsonlTopLevelUsage: Decodable {
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
