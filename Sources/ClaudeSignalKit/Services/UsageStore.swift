import Foundation
import SQLite3
import os.log

/// 用量数据读取层
/// 从 SQLite 查询 token 用量和成本数据
public final class UsageStore {
    /// 读取专用数据库连接（与 Indexer 的写入连接分离，避免线程冲突）
    private let readDB: Database
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "UsageStore")

    public init(databaseURL: URL) {
        self.readDB = Database(databaseURL: databaseURL)
    }

    // MARK: - Data Models

    /// 每日用量汇总
    public struct DailyUsage {
        public let date: String
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let totalTokens: Int
        public let messageCount: Int
        public let cost: ModelPricing.Cost
    }

    /// 项目用量汇总
    public struct ProjectUsage {
        public let projectSlug: String
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let totalTokens: Int
        public let messageCount: Int
        public let sessionCount: Int
        public let cost: ModelPricing.Cost
    }

    /// 模型用量汇总
    public struct ModelUsage {
        public let model: String
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let totalTokens: Int
        public let messageCount: Int
        public let cost: ModelPricing.Cost
        public let isKnown: Bool
    }

    /// 最近会话用量汇总
    public struct RecentSessionUsage {
        public let sessionId: String
        public let date: String
        public let projectSlug: String
        public let model: String
        public let inputTokens: Int
        public let outputTokens: Int
        public let cacheReadTokens: Int
        public let totalTokens: Int
        public let messageCount: Int
        public let cost: ModelPricing.Cost
        public let startTime: Int?
    }

    /// 总览统计
    public struct UsageSummary {
        public let totalInputTokens: Int
        public let totalOutputTokens: Int
        public let totalCacheReadTokens: Int
        public let totalMessages: Int
        public let totalSessions: Int
        public let totalCost: Double
        public let averageTokensPerMessage: Int
        public let unknownModelRatio: Double // 0.0 ~ 1.0，未知模型消息占比
    }

    // MARK: - Date Range

    /// 查询范围
    public enum DateRange: String, CaseIterable {
        case today = "今日"
        case last7Days = "近 7 天"
        case last30Days = "近 30 天"
        case last90Days = "近 90 天"

        /// 返回 (startDate, endDate) 闭区间，格式 "yyyy-MM-dd"，本地时区
        public var dateRange: (start: String, end: String) {
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd"
            f.timeZone = TimeZone.current
            let today = f.string(from: Date())
            let cal = Calendar.current

            switch self {
            case .today:
                return (today, today)
            case .last7Days:
                let start = f.string(from: cal.date(byAdding: .day, value: -6, to: Date())!)
                return (start, today)
            case .last30Days:
                let start = f.string(from: cal.date(byAdding: .day, value: -29, to: Date())!)
                return (start, today)
            case .last90Days:
                let start = f.string(from: cal.date(byAdding: .day, value: -89, to: Date())!)
                return (start, today)
            }
        }
    }

    // MARK: - Query Methods

    /// 获取每日用量趋势
    public func fetchDailyUsage(range: DateRange = .last30Days) -> [DailyUsage] {
        var results: [DailyUsage] = []
        let opened = readDB.openReadOnly()
        logger.info("UsageStore.fetchDailyUsage: open=\(opened), range=\(range.rawValue)")

        let (startDate, endDate) = range.dateRange

        readDB.query(
            """
            SELECT date,
                   SUM(input_tokens) as total_input,
                   SUM(output_tokens) as total_output,
                   SUM(cache_read_tokens) as total_cache_read,
                   SUM(message_count) as total_messages
            FROM daily_usage
            WHERE date >= ? AND date <= ?
            GROUP BY date
            ORDER BY date ASC
            """,
            [startDate, endDate]
        ) { stmt in
            let date = Database.stringColumn(stmt, 0) ?? ""
            let inputTokens = Database.intColumn(stmt, 1)
            let outputTokens = Database.intColumn(stmt, 2)
            let cacheReadTokens = Database.intColumn(stmt, 3)
            let messageCount = Database.intColumn(stmt, 4)
            let totalTokens = inputTokens + outputTokens + cacheReadTokens

            let cost = ModelPricing.Cost(inputCost: 0, outputCost: 0, cacheReadCost: 0)

            results.append(DailyUsage(
                date: date,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                totalTokens: totalTokens,
                messageCount: messageCount,
                cost: cost
            ))
        }

        // 填充实际成本
        results = results.map { daily in
            let (inputCost, outputCost, cacheReadCost) = calculateDailyCost(date: daily.date)
            return DailyUsage(
                date: daily.date,
                inputTokens: daily.inputTokens,
                outputTokens: daily.outputTokens,
                cacheReadTokens: daily.cacheReadTokens,
                totalTokens: daily.totalTokens,
                messageCount: daily.messageCount,
                cost: ModelPricing.Cost(inputCost: inputCost, outputCost: outputCost, cacheReadCost: cacheReadCost)
            )
        }

        logger.info("UsageStore.fetchDailyUsage: returning \(results.count) rows, \(startDate)~\(endDate)")
        return results
    }

    /// 获取项目用量排行
    public func fetchProjectUsage(range: DateRange = .last30Days) -> [ProjectUsage] {
        var results: [ProjectUsage] = []
        readDB.openReadOnly()

        let (startDate, endDate) = range.dateRange

        readDB.query(
            """
            SELECT project_slug,
                   SUM(input_tokens) as total_input,
                   SUM(output_tokens) as total_output,
                   SUM(cache_read_tokens) as total_cache_read,
                   SUM(message_count) as total_messages,
                   COUNT(DISTINCT session_id) as session_count
            FROM daily_usage
            WHERE date >= ? AND date <= ?
            GROUP BY project_slug
            ORDER BY total_input + total_output + total_cache_read DESC
            """,
            [startDate, endDate]
        ) { stmt in
            let projectSlug = Database.stringColumn(stmt, 0) ?? ""
            let inputTokens = Database.intColumn(stmt, 1)
            let outputTokens = Database.intColumn(stmt, 2)
            let cacheReadTokens = Database.intColumn(stmt, 3)
            let messageCount = Database.intColumn(stmt, 4)
            let sessionCount = Database.intColumn(stmt, 5)
            let totalTokens = inputTokens + outputTokens + cacheReadTokens

            let (inputCost, outputCost, cacheReadCost) = calculateProjectCost(
                projectSlug: projectSlug, startDate: startDate, endDate: endDate
            )

            results.append(ProjectUsage(
                projectSlug: projectSlug,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                totalTokens: totalTokens,
                messageCount: messageCount,
                sessionCount: sessionCount,
                cost: ModelPricing.Cost(inputCost: inputCost, outputCost: outputCost, cacheReadCost: cacheReadCost)
            ))
        }

        return results
    }

    /// 获取模型用量分布
    public func fetchModelUsage(range: DateRange = .last30Days) -> [ModelUsage] {
        var results: [ModelUsage] = []
        readDB.openReadOnly()

        let (startDate, endDate) = range.dateRange

        readDB.query(
            """
            SELECT model,
                   SUM(input_tokens) as total_input,
                   SUM(output_tokens) as total_output,
                   SUM(cache_read_tokens) as total_cache_read,
                   SUM(message_count) as total_messages
            FROM daily_usage
            WHERE date >= ? AND date <= ?
            GROUP BY model
            ORDER BY total_input + total_output + total_cache_read DESC
            """,
            [startDate, endDate]
        ) { stmt in
            let model = Database.stringColumn(stmt, 0) ?? "unknown"
            let inputTokens = Database.intColumn(stmt, 1)
            let outputTokens = Database.intColumn(stmt, 2)
            let cacheReadTokens = Database.intColumn(stmt, 3)
            let messageCount = Database.intColumn(stmt, 4)
            let totalTokens = inputTokens + outputTokens + cacheReadTokens
            let isKnown = ModelPricing.isKnownModel(model)

            let cost = ModelPricing.calculate(
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens
            )

            results.append(ModelUsage(
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                totalTokens: totalTokens,
                messageCount: messageCount,
                cost: cost,
                isKnown: isKnown
            ))
        }

        return results
    }

    /// 获取总览统计
    public func fetchSummary(range: DateRange = .last30Days) -> UsageSummary {
        readDB.openReadOnly()

        let (startDate, endDate) = range.dateRange

        var totalInput = 0, totalOutput = 0, totalCacheRead = 0, totalMessages = 0, totalSessions = 0
        var totalCost: Double = 0
        var knownMessages = 0

        readDB.query(
            """
            SELECT SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens),
                   SUM(message_count), COUNT(DISTINCT session_id)
            FROM daily_usage
            WHERE date >= ? AND date <= ?
            """,
            [startDate, endDate]
        ) { stmt in
            totalInput = Database.intColumn(stmt, 0)
            totalOutput = Database.intColumn(stmt, 1)
            totalCacheRead = Database.intColumn(stmt, 2)
            totalMessages = Database.intColumn(stmt, 3)
            totalSessions = Database.intColumn(stmt, 4)
        }

        let modelUsages = fetchModelUsage(range: range)
        for mu in modelUsages {
            totalCost += mu.cost.totalCost
            if mu.isKnown {
                knownMessages += mu.messageCount
            }
        }

        let unknownRatio = totalMessages > 0 ? Double(totalMessages - knownMessages) / Double(totalMessages) : 0
        let averageTokensPerMessage = totalMessages > 0
            ? (totalInput + totalOutput + totalCacheRead) / totalMessages
            : 0

        return UsageSummary(
            totalInputTokens: totalInput,
            totalOutputTokens: totalOutput,
            totalCacheReadTokens: totalCacheRead,
            totalMessages: totalMessages,
            totalSessions: totalSessions,
            totalCost: totalCost,
            averageTokensPerMessage: averageTokensPerMessage,
            unknownModelRatio: unknownRatio
        )
    }

    /// 获取最近会话用量明细
    public func fetchRecentSessionUsage(range: DateRange = .last30Days, limit: Int = 30) -> [RecentSessionUsage] {
        var results: [RecentSessionUsage] = []
        readDB.openReadOnly()

        let (startDate, endDate) = range.dateRange

        readDB.query(
            """
            SELECT d.session_id,
                   MAX(d.date) as last_date,
                   d.project_slug,
                   CASE WHEN COUNT(DISTINCT d.model) = 1 THEN MIN(d.model) ELSE 'mixed' END as model_label,
                   SUM(d.input_tokens) as total_input,
                   SUM(d.output_tokens) as total_output,
                   SUM(d.cache_read_tokens) as total_cache_read,
                   SUM(d.message_count) as total_messages,
                   MAX(s.start_time) as start_time
            FROM daily_usage d
            LEFT JOIN sessions s ON s.session_id = d.session_id AND s.source = d.source
            WHERE d.date >= ? AND d.date <= ?
            GROUP BY d.session_id, d.project_slug
            ORDER BY COALESCE(MAX(s.start_time), 0) DESC, last_date DESC
            LIMIT ?
            """,
            [startDate, endDate, limit]
        ) { stmt in
            let sessionId = Database.stringColumn(stmt, 0) ?? ""
            let date = Database.stringColumn(stmt, 1) ?? ""
            let projectSlug = Database.stringColumn(stmt, 2) ?? ""
            let model = Database.stringColumn(stmt, 3) ?? "unknown"
            let inputTokens = Database.intColumn(stmt, 4)
            let outputTokens = Database.intColumn(stmt, 5)
            let cacheReadTokens = Database.intColumn(stmt, 6)
            let messageCount = Database.intColumn(stmt, 7)
            let startTimeValue = Database.intColumn(stmt, 8)
            let startTime = startTimeValue > 0 ? startTimeValue : nil
            let totalTokens = inputTokens + outputTokens + cacheReadTokens
            let (inputCost, outputCost, cacheReadCost) = calculateSessionCost(
                sessionId: sessionId,
                startDate: startDate,
                endDate: endDate
            )

            results.append(RecentSessionUsage(
                sessionId: sessionId,
                date: date,
                projectSlug: projectSlug,
                model: model,
                inputTokens: inputTokens,
                outputTokens: outputTokens,
                cacheReadTokens: cacheReadTokens,
                totalTokens: totalTokens,
                messageCount: messageCount,
                cost: ModelPricing.Cost(inputCost: inputCost, outputCost: outputCost, cacheReadCost: cacheReadCost),
                startTime: startTime
            ))
        }

        return results
    }

    // MARK: - Private Cost Helpers

    /// 计算某日期的总成本
    private func calculateDailyCost(date: String) -> (inputCost: Double, outputCost: Double, cacheReadCost: Double) {
        var inputCost: Double = 0
        var outputCost: Double = 0
        var cacheReadCost: Double = 0

        readDB.query(
            """
            SELECT model, SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens)
            FROM daily_usage
            WHERE date = ?
            GROUP BY model
            """,
            [date]
        ) { stmt in
            let model = Database.stringColumn(stmt, 0) ?? "unknown"
            let input = Database.intColumn(stmt, 1)
            let output = Database.intColumn(stmt, 2)
            let cacheRead = Database.intColumn(stmt, 3)

            let cost = ModelPricing.calculate(
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead
            )
            inputCost += cost.inputCost
            outputCost += cost.outputCost
            cacheReadCost += cost.cacheReadCost
        }

        return (inputCost, outputCost, cacheReadCost)
    }

    /// 计算某项目在指定日期范围内的总成本
    private func calculateProjectCost(
        projectSlug: String,
        startDate: String,
        endDate: String
    ) -> (inputCost: Double, outputCost: Double, cacheReadCost: Double) {
        var inputCost: Double = 0
        var outputCost: Double = 0
        var cacheReadCost: Double = 0

        readDB.query(
            """
            SELECT model, SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens)
            FROM daily_usage
            WHERE project_slug = ? AND date >= ? AND date <= ?
            GROUP BY model
            """,
            [projectSlug, startDate, endDate]
        ) { stmt in
            let model = Database.stringColumn(stmt, 0) ?? "unknown"
            let input = Database.intColumn(stmt, 1)
            let output = Database.intColumn(stmt, 2)
            let cacheRead = Database.intColumn(stmt, 3)

            let cost = ModelPricing.calculate(
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead
            )
            inputCost += cost.inputCost
            outputCost += cost.outputCost
            cacheReadCost += cost.cacheReadCost
        }

        return (inputCost, outputCost, cacheReadCost)
    }

    /// 计算某会话在指定日期范围内的总成本
    private func calculateSessionCost(
        sessionId: String,
        startDate: String,
        endDate: String
    ) -> (inputCost: Double, outputCost: Double, cacheReadCost: Double) {
        var inputCost: Double = 0
        var outputCost: Double = 0
        var cacheReadCost: Double = 0

        readDB.query(
            """
            SELECT model, SUM(input_tokens), SUM(output_tokens), SUM(cache_read_tokens)
            FROM daily_usage
            WHERE session_id = ? AND date >= ? AND date <= ?
            GROUP BY model
            """,
            [sessionId, startDate, endDate]
        ) { stmt in
            let model = Database.stringColumn(stmt, 0) ?? "unknown"
            let input = Database.intColumn(stmt, 1)
            let output = Database.intColumn(stmt, 2)
            let cacheRead = Database.intColumn(stmt, 3)

            let cost = ModelPricing.calculate(
                model: model,
                inputTokens: input,
                outputTokens: output,
                cacheReadTokens: cacheRead
            )
            inputCost += cost.inputCost
            outputCost += cost.outputCost
            cacheReadCost += cost.cacheReadCost
        }

        return (inputCost, outputCost, cacheReadCost)
    }
}
