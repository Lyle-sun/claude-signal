import Foundation
import os.log

/// 后台增量索引器
/// 扫描 ~/.claude/projects/ 下的 jsonl 文件，增量解析并写入 SQLite
/// 每次只处理自上次索引以来的新内容
/// 线程安全：每次 runIncrementalIndex 创建独立的 Database 连接
final public class Indexer {
    private let parser = ClaudeCodeJsonlParser()
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "Indexer")

    /// Claude Code 数据根目录
    let claudeDir: URL

    /// 数据库文件路径（每次 runIncrementalIndex 创建独立连接）
    let databaseURL: URL

    /// 单文件索引超时（秒）
    private let fileTimeout: Double = 10.0

    /// 每批事务提交的行数
    private let batchSize = 1000

    /// 索引进度回调
    public var onProgress: ((Int, Int) -> Void)? // (completed, total)

    /// 索引完成回调
    public var onComplete: ((IndexResult) -> Void)?

    /// 索引结果
    public struct IndexResult {
        public let filesProcessed: Int
        public let messagesIndexed: Int
        public let errors: Int
        public let duration: TimeInterval
    }

    /// 当前运行时的数据库连接（仅在 runIncrementalIndex 期间有效）
    private var _db: Database?

    public init(databaseURL: URL, claudeDir: URL? = nil) {
        self.databaseURL = databaseURL
        self.claudeDir = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    private var projectsDir: URL {
        claudeDir.appendingPathComponent("projects")
    }

    /// 当前运行时的数据库连接
    private var database: Database {
        guard let db = _db else {
            fatalError("Database not available outside runIncrementalIndex()")
        }
        return db
    }

    // MARK: - Full Index

    /// 执行增量索引，只处理有变化的项目目录
    public func runIncrementalIndex() -> IndexResult {
        let startTime = Date()

        // 创建独立数据库连接（此方法在后台线程运行）
        let database = Database(databaseURL: databaseURL)
        self._db = database
        defer { self._db = nil }

        guard database.open() else {
            logger.error("Failed to open database for indexing")
            return IndexResult(filesProcessed: 0, messagesIndexed: 0, errors: 1, duration: 0)
        }

        // 检查数据库完整性
        if !database.checkIntegrity() {
            logger.warning("Database integrity check failed, recreating...")
            if !database.deleteAndRecreate() {
                return IndexResult(filesProcessed: 0, messagesIndexed: 0, errors: 1, duration: 0)
            }
        }

        // 发现所有项目目录
        guard let projectDirs = discoverProjectDirs() else {
            return IndexResult(filesProcessed: 0, messagesIndexed: 0, errors: 0, duration: Date().timeIntervalSince(startTime))
        }

        var totalFiles = 0
        var totalMessages = 0
        var totalErrors = 0

        for (index, projectDir) in projectDirs.enumerated() {
            onProgress?(index, projectDirs.count)

            let (files, messages, errors) = indexProjectDir(projectDir)
            totalFiles += files
            totalMessages += messages
            totalErrors += errors
        }

        let duration = Date().timeIntervalSince(startTime)
        let result = IndexResult(filesProcessed: totalFiles, messagesIndexed: totalMessages, errors: totalErrors, duration: duration)
        logger.info("Index complete: \(totalMessages) messages from \(totalFiles) files in \(String(format: "%.1f", duration))s")

        onComplete?(result)
        return result
    }

    // MARK: - Project Discovery

    /// 发现 ~/.claude/projects/ 下的所有项目目录
    private func discoverProjectDirs() -> [URL]? {
        guard FileManager.default.fileExists(atPath: projectsDir.path) else {
            logger.info("Projects directory not found")
            return []
        }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: projectsDir,
            includingPropertiesForKeys: [.isDirectoryKey]
        ) else {
            logger.error("Failed to list projects directory")
            return nil
        }

        return contents.filter { url in
            (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        }
    }

    // MARK: - Index Single Project

    /// 索引一个项目目录下的所有 jsonl 文件
    private func indexProjectDir(_ projectDir: URL) -> (files: Int, messages: Int, errors: Int) {
        let projectSlug = projectDir.lastPathComponent

        guard let jsonlFiles = discoverJsonlFiles(in: projectDir) else {
            return (0, 0, 0)
        }

        var totalFiles = 0
        var totalMessages = 0
        var totalErrors = 0

        for jsonlFile in jsonlFiles {
            let (messages, errors) = indexJsonlFile(jsonlFile, projectSlug: projectSlug)
            totalFiles += 1
            totalMessages += messages
            totalErrors += errors
        }

        return (totalFiles, totalMessages, totalErrors)
    }

    /// 发现目录下的所有 .jsonl 文件
    private func discoverJsonlFiles(in dir: URL) -> [URL]? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else {
            return nil
        }

        return contents.filter { $0.pathExtension == "jsonl" }
    }

    // MARK: - Index Single JSONL File

    /// 索引单个 jsonl 文件（增量）
    private func indexJsonlFile(_ fileURL: URL, projectSlug: String) -> (messages: Int, errors: Int) {
        let indexKey = indexStateKey(projectSlug: projectSlug, fileURL: fileURL)

        // 获取文件属性
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: fileURL.path),
              let fileSize = attrs[.size] as? UInt64,
              let modDate = attrs[.modificationDate] as? Date else {
            logger.warning("Failed to get file attributes: \(fileURL.lastPathComponent)")
            return (0, 1)
        }

        let fileMtime = modDate.timeIntervalSince1970

        // 查询上次索引状态
        let lastIndexState = getIndexState(indexKey: indexKey)
        let lastOffset = lastIndexState?.byteOffset ?? 0
        let lastSize = lastIndexState?.fileSize ?? 0
        let lastMtime = lastIndexState?.mtime ?? 0

        // 文件未变化则跳过
        if lastSize == fileSize && lastMtime == fileMtime {
            return (0, 0)
        }

        // 文件截断检测：如果文件变小了，全量重索引
        var effectiveOffset = lastOffset
        if lastIndexState == nil || fileSize < lastSize {
            logger.info("File truncated, resetting offset: \(fileURL.lastPathComponent)")
            effectiveOffset = 0
        }

        // 解析文件
        let (results, bytesProcessed, errorCount) = parser.parseFile(
            fileURL: fileURL,
            byteOffset: effectiveOffset
        )

        guard !results.isEmpty || errorCount > 0 else {
            // 无新数据，但更新索引状态
            updateIndexState(
                indexKey: indexKey,
                byteOffset: bytesProcessed,
                fileSize: fileSize,
                mtime: fileMtime,
                error: nil
            )
            return (0, errorCount)
        }

        // 写入数据库
        var writeErrors = 0
        do {
            try database.inTransaction {
                var batchCount = 0

                if effectiveOffset == 0 {
                    resetDailyUsage(for: results)
                }

                for usage in results {
                    // 更新 sessions 表
                    upsertSession(usage: usage)

                    // 插入 daily_usage
                    upsertDailyUsage(usage: usage)

                    batchCount += 1

                    // 每 batchSize 条提交一次事务
                    if batchCount >= batchSize {
                        _ = database.commit()
                        _ = database.beginTransaction()
                        batchCount = 0
                    }
                }

                // 更新索引状态
                updateIndexState(
                    indexKey: indexKey,
                    byteOffset: bytesProcessed,
                    fileSize: fileSize,
                    mtime: fileMtime,
                    error: nil
                )
            }
        } catch {
            logger.error("Transaction failed for \(fileURL.lastPathComponent): \(error.localizedDescription)")
            writeErrors = 1

            // 记录错误到 index_state
            updateIndexState(
                indexKey: indexKey,
                byteOffset: lastOffset, // 不更新 offset，下次重试
                fileSize: lastSize,
                mtime: lastMtime,
                error: error.localizedDescription
            )
        }

        return (results.count, errorCount + writeErrors)
    }

    // MARK: - Index State

    private struct IndexStateRecord {
        let byteOffset: UInt64
        let fileSize: UInt64
        let mtime: TimeInterval
    }

    private func indexStateKey(projectSlug: String, fileURL: URL) -> String {
        "\(projectSlug)/\(fileURL.lastPathComponent)"
    }

    private func getIndexState(indexKey: String) -> IndexStateRecord? {
        var result: IndexStateRecord?

        database.query(
            "SELECT last_indexed_byte_offset, last_file_size, last_file_mtime FROM index_state WHERE project_slug = ?",
            [indexKey]
        ) { stmt in
            result = IndexStateRecord(
                byteOffset: UInt64(Database.intColumn(stmt, 0)),
                fileSize: UInt64(Database.intColumn(stmt, 1)),
                mtime: Database.doubleColumn(stmt, 2)
            )
        }

        return result
    }

    private func updateIndexState(
        indexKey: String,
        byteOffset: UInt64,
        fileSize: UInt64,
        mtime: TimeInterval,
        error: String?
    ) {
        database.executeWithParams(
            """
            INSERT OR REPLACE INTO index_state
                (project_slug, source, last_indexed_byte_offset, last_file_size, last_file_mtime, last_error)
            VALUES (?, 'claude-code', ?, ?, ?, ?)
            """,
            [indexKey, Int(byteOffset), Int(fileSize), mtime, error ?? ""]
        )
    }

    // MARK: - Upsert Helpers

    private func upsertSession(usage: ClaudeCodeJsonlParser.ParsedUsage) {
        // 解析 timestamp 获取 start_time
        let startTime = parseISO8601ToEpoch(usage.timestamp)

        database.executeWithParams(
            """
            INSERT OR REPLACE INTO sessions
                (session_id, source, project_slug, model, start_time, cwd)
            VALUES (?, 'claude-code', ?, ?, ?, ?)
            """,
            [usage.sessionId, usage.projectSlug, usage.model, startTime as Any, usage.cwd]
        )
    }

    private func resetDailyUsage(for usages: [ClaudeCodeJsonlParser.ParsedUsage]) {
        let sessionIds = Set(usages.map(\.sessionId))
        for sessionId in sessionIds {
            database.executeWithParams(
                "DELETE FROM daily_usage WHERE source = 'claude-code' AND session_id = ?",
                [sessionId]
            )
        }
    }

    private func upsertDailyUsage(usage: ClaudeCodeJsonlParser.ParsedUsage) {
        // 从 ISO8601 timestamp 提取日期部分
        let date = extractDate(from: usage.timestamp)

        guard !date.isEmpty else { return }

        database.executeWithParams(
            """
            INSERT INTO daily_usage
                (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count)
            VALUES (?, ?, 'claude-code', ?, ?, ?, ?, ?, 1)
            ON CONFLICT(date, session_id, source, model) DO UPDATE SET
                input_tokens = input_tokens + excluded.input_tokens,
                output_tokens = output_tokens + excluded.output_tokens,
                cache_read_tokens = cache_read_tokens + excluded.cache_read_tokens,
                message_count = message_count + 1
            """,
            [date, usage.sessionId, usage.projectSlug, usage.model,
             usage.inputTokens, usage.outputTokens, usage.cacheReadTokens]
        )
    }

    // MARK: - Date Helpers

    /// 从 ISO8601 字符串提取本地日期 "2026-05-12T06:29:09.652Z" → "2026-05-12"（本地时区）
    private func extractDate(from iso8601: String) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso8601) else {
            // fallback: 直接截取前 10 字符（UTC 日期）
            guard iso8601.count >= 10 else { return "" }
            return String(iso8601.prefix(10))
        }
        let localFormatter = DateFormatter()
        localFormatter.dateFormat = "yyyy-MM-dd"
        localFormatter.timeZone = TimeZone.current
        return localFormatter.string(from: date)
    }

    /// 将 ISO8601 转为 Unix epoch (秒)
    private func parseISO8601ToEpoch(_ iso8601: String) -> Int? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let date = formatter.date(from: iso8601) else { return nil }
        return Int(date.timeIntervalSince1970)
    }
}
