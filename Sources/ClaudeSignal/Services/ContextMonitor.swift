import Foundation
import os.log

/// 监控 Claude Code 会话的 context token 用量
/// 读取 ~/.claude/projects/{slug}/{sessionId}.jsonl 中末尾 assistant 消息的 message.usage
final class ContextMonitor {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "ContextMonitor")

    private var projectsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
            .appendingPathComponent("projects")
    }

    /// 为会话获取 context token 数
    /// - Parameters:
    ///   - sessionId: 会话 ID
    ///   - cwd: 工作目录路径
    /// - Returns: token 数，nil 表示读取失败
    func fetchContextTokens(sessionId: String, cwd: String) -> Int? {
        let slug = cwdToSlug(cwd)
        let jsonlPath = projectsDir
            .appendingPathComponent(slug)
            .appendingPathComponent("\(sessionId).jsonl")

        guard FileManager.default.fileExists(atPath: jsonlPath.path) else {
            logger.debug("JSONL not found: \(jsonlPath.path)")
            return nil
        }

        guard let content = try? String(contentsOfFile: jsonlPath.path, encoding: .utf8) else {
            logger.warning("Failed to read JSONL: \(jsonlPath.lastPathComponent)")
            return nil
        }

        return parseLastUsage(from: content)
    }

    /// 将 cwd 转换为 projects 目录下的 slug 格式
    /// /Users/lyle/Desktop/Projects → -Users-lyle-Desktop-Projects
    private func cwdToSlug(_ cwd: String) -> String {
        cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// 从 jsonl 内容解析最后一条 assistant 消息的 usage
    private func parseLastUsage(from content: String) -> Int? {
        var lastUsage: UsageData?

        content.enumerateLines { line, _ in
            guard !line.isEmpty,
                  let data = line.data(using: .utf8),
                  let message = try? JSONDecoder().decode(JsonlMessage.self, from: data),
                  message.type == "assistant",
                  let usage = message.message?.usage else {
                return
            }
            lastUsage = usage
        }

        guard let usage = lastUsage else {
            logger.debug("No assistant message with usage found")
            return nil
        }

        return usage.totalContextTokens
    }
}
