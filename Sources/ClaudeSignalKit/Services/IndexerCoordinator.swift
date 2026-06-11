import Foundation
import os.log

/// 索引调度器
/// 在后台队列上运行 Indexer，完成后通知主线程
@MainActor
public final class IndexerCoordinator {
    private let _indexer: Indexer
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "IndexerCoordinator")

    /// 后台队列
    private let indexingQueue = DispatchQueue(label: "com.claude-signal.indexer", qos: .utility)

    /// 数据库 URL
    public let databaseURL: URL

    /// 索引状态
    public enum IndexStatus {
        case idle
        case indexing(progress: Double) // 0.0 ~ 1.0
        case completed(Indexer.IndexResult)
        case failed(Error)
    }

    /// 当前状态
    public private(set) var status: IndexStatus = .idle

    /// 用量数据读取层
    public var usageStore: UsageStore?

    /// App 会频繁请求索引，这里统一节流，避免无谓 I/O。
    private let minimumIndexInterval: TimeInterval = 60
    private var lastIndexStartedAt: Date?

    public init(claudeDir: URL? = nil) {
        // 数据库路径：~/Library/Application Support/ClaudeSignal/usage.sqlite
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dbDir = appSupport.appendingPathComponent("ClaudeSignal", isDirectory: true)
        let dbURL = dbDir.appendingPathComponent("usage.sqlite")

        self.databaseURL = dbURL
        self._indexer = Indexer(databaseURL: dbURL, claudeDir: claudeDir)
        self.usageStore = UsageStore(databaseURL: dbURL)

        // 绑定进度回调
        _indexer.onProgress = { [weak self] completed, total in
            guard let self else { return }
            let progress = total > 0 ? Double(completed) / Double(total) : 0
            Task { @MainActor in
                self.status = .indexing(progress: progress)
            }
        }

        _indexer.onComplete = { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                self.status = .completed(result)
                self.logger.info("Indexing completed: \(result.messagesIndexed) messages in \(String(format: "%.1f", result.duration))s")
            }
        }
    }

    /// 启动增量索引（后台异步）
    public func startIndexing(force: Bool = false) {
        if case .indexing = status {
            logger.info("Indexing already in progress")
            return
        }

        if !force,
           let lastIndexStartedAt,
           Date().timeIntervalSince(lastIndexStartedAt) < minimumIndexInterval {
            return
        }

        lastIndexStartedAt = Date()
        status = .indexing(progress: 0)

        indexingQueue.async { [weak self] in
            guard let self else { return }
            // Indexer 内部创建独立的 Database 连接，线程安全
            let result = self._indexer.runIncrementalIndex()

            Task { @MainActor in
                if result.errors > 0 && result.messagesIndexed == 0 {
                    self.status = .failed(NSError(domain: "com.claude-signal.indexer", code: 1, userInfo: [
                        NSLocalizedDescriptionKey: "Indexing failed with \(result.errors) errors"
                    ]))
                } else {
                    self.status = .completed(result)
                }
            }
        }
    }

    /// 强制重新索引（删除索引状态，从头开始）
    public func forceReindex() {
        status = .idle

        // 清空 index_state 表（独立连接）
        let db = Database(databaseURL: databaseURL)
        if db.open() {
            _ = db.execute("DELETE FROM index_state")
            db.close()
        }

        startIndexing(force: true)
    }
}
