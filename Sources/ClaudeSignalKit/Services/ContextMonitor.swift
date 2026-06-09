import Foundation
import os.log

/// 监控 Claude Code 会话的 context token 用量
/// 读取 ~/.claude/projects/{slug}/{sessionId}.jsonl 中末尾 assistant 消息的 message.usage
final public class ContextMonitor: ContextMonitoring {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "ContextMonitor")

    /// Claude Code 数据根目录（可注入，默认 ~/.claude）
    let claudeDir: URL

    /// JSONL 单行最大长度（超过则跳过，防止恶意/损坏文件）
    private let maxLineLength = 1_000_000 // 1MB

    /// tail-read 读取的字节数（从文件末尾读取，避免全量加载大文件）
    private let tailReadSize: Int = 64 * 1024 // 64KB

    /// 最多向前回溯的字节数。Claude Code compact/附件记录可能把最后一条 assistant usage 挤出 64KB 尾部。
    private let maxTailSearchSize: Int = 4 * 1024 * 1024 // 4MB

    public init(claudeDir: URL? = nil) {
        self.claudeDir = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    private var projectsDir: URL {
        claudeDir.appendingPathComponent("projects")
    }

    /// 为会话获取 context token 数
    /// - Parameters:
    ///   - sessionId: 会话 ID
    ///   - cwd: 工作目录路径
    /// - Returns: token 数，nil 表示读取失败
    func fetchContextTokens(sessionId: String, cwd: String) -> Int? {
        fetchLatestUsageSnapshot(sessionId: sessionId, cwd: cwd)?.contextTokens
    }

    /// 获取最后一轮 assistant usage 快照，用于会话卡片展示本轮 token 与模型。
    public func fetchLatestUsageSnapshot(sessionId: String, cwd: String) -> UsageSnapshot? {
        guard let jsonlPath = resolveJsonlPath(sessionId: sessionId, cwd: cwd) else {
            logger.debug("JSONL not found for session \(sessionId, privacy: .public)")
            return nil
        }

        return fetchLatestUsageSnapshot(from: jsonlPath)
    }

    /// 尽量直接定位 jsonl；slug 只作为 fast path，失败后按 sessionId 反查 projects 下的文件。
    public func resolveJsonlPath(sessionId: String, cwd: String) -> URL? {
        let fastPath = projectsDir
            .appendingPathComponent(cwdToSlug(cwd))
            .appendingPathComponent("\(sessionId).jsonl")

        if FileManager.default.fileExists(atPath: fastPath.path) {
            return fastPath
        }

        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return nil
        }

        let candidates = projectDirs.compactMap { projectDir -> URL? in
            let values = try? projectDir.resourceValues(forKeys: [.isDirectoryKey])
            guard values?.isDirectory == true else { return nil }
            let candidate = projectDir.appendingPathComponent("\(sessionId).jsonl")
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }

        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }

        return candidates.first { jsonlPath in
            jsonlContainsCwd(jsonlPath, cwd: cwd)
        } ?? candidates[0]
    }

    private func fetchLatestUsageSnapshot(from jsonlPath: URL) -> UsageSnapshot? {
        // 使用 tail-read：只读取文件末尾部分，避免全量加载大文件
        guard let fileHandle = try? FileHandle(forReadingFrom: jsonlPath) else {
            logger.warning("Failed to open JSONL: \(jsonlPath.lastPathComponent)")
            return nil
        }
        defer { try? fileHandle.close() }

        guard let fileSize = try? fileHandle.seekToEnd() else {
            return nil
        }

        var readSize = min(UInt64(tailReadSize), fileSize)
        let maxReadSize = min(UInt64(maxTailSearchSize), fileSize)

        while readSize <= maxReadSize {
            let readOffset = fileSize - readSize
            try? fileHandle.seek(toOffset: readOffset)

            guard let data = try? fileHandle.read(upToCount: Int(readSize)),
                  let content = String(data: data, encoding: .utf8) else {
                logger.warning("Failed to read JSONL tail: \(jsonlPath.lastPathComponent)")
                return nil
            }

            if let snapshot = parseLastUsageSnapshot(from: content) {
                return snapshot
            }

            if readSize == maxReadSize { break }
            readSize = min(readSize * 2, maxReadSize)
        }

        logger.debug("No assistant usage found within tail search window: \(jsonlPath.lastPathComponent)")
        return nil
    }

    private func jsonlContainsCwd(_ jsonlPath: URL, cwd: String) -> Bool {
        guard let fileHandle = try? FileHandle(forReadingFrom: jsonlPath) else {
            return false
        }
        defer { try? fileHandle.close() }

        guard let data = try? fileHandle.read(upToCount: 128 * 1024),
              let content = String(data: data, encoding: .utf8) else {
            return false
        }

        var found = false
        content.enumerateLines { line, stop in
            guard !line.isEmpty,
                  line.count <= self.maxLineLength,
                  let data = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(ClaudeCodeJsonlRecord.self, from: data) else {
                return
            }

            if record.cwd == cwd {
                found = true
                stop = true
            }
        }
        return found
    }

    /// 将 cwd 转换为 projects 目录下的 slug 格式
    /// /Users/lyle/Desktop/Projects → -Users-lyle-Desktop-Projects
    /// 注意：此算法必须与 Claude Code 的 slug 算法一致
    public func cwdToSlug(_ cwd: String) -> String {
        cwd
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
    }

    /// 从 jsonl 内容解析最后一条 assistant 消息的 usage
    private func parseLastUsage(from content: String) -> Int? {
        parseLastUsageSnapshot(from: content)?.contextTokens
    }

    /// 从 jsonl 内容解析最后一条 assistant 消息的 usage 快照
    private func parseLastUsageSnapshot(from content: String) -> UsageSnapshot? {
        var lastUsage: ClaudeCodeJsonlUsage?
        var lastModel: String?

        content.enumerateLines { line, _ in
            guard !line.isEmpty,
                  line.count <= self.maxLineLength,
                  let data = line.data(using: .utf8),
                  let record = try? JSONDecoder().decode(ClaudeCodeJsonlRecord.self, from: data),
                  record.type == "assistant",
                  let usage = record.message?.usage else {
                return
            }
            lastUsage = usage
            lastModel = record.message?.model
        }

        guard let usage = lastUsage else {
            logger.debug("No assistant message with usage found")
            return nil
        }

        return UsageSnapshot(
            inputTokens: usage.inputTokens ?? 0,
            outputTokens: usage.outputTokens ?? 0,
            cacheReadTokens: usage.cacheReadInputTokens ?? 0,
            model: lastModel
        )
    }
}
