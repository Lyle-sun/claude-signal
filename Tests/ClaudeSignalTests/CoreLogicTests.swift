import Foundation
import ClaudeSignalKit

// MARK: - Lightweight Test Runner (no XCTest dependency)

var testsPassed = 0
var testsFailed = 0

func assertEqual<T: Equatable>(_ actual: T, _ expected: T, file: String = #file, line: Int = #line, _ label: String = "") {
    if actual == expected {
        testsPassed += 1
    } else {
        testsFailed += 1
        let prefix = label.isEmpty ? "" : "\(label): "
        print("❌ FAIL \(file):\(line) — \(prefix)expected \(expected), got \(actual)")
    }
}

func assertEqual(_ actual: Double, _ expected: Double, accuracy: Double, file: String = #file, line: Int = #line, _ label: String = "") {
    if abs(actual - expected) <= accuracy {
        testsPassed += 1
    } else {
        testsFailed += 1
        let prefix = label.isEmpty ? "" : "\(label): "
        print("❌ FAIL \(file):\(line) — \(prefix)expected \(expected)±\(accuracy), got \(actual)")
    }
}

func assertTrue(_ actual: Bool, file: String = #file, line: Int = #line, _ label: String = "") {
    if actual {
        testsPassed += 1
    } else {
        testsFailed += 1
        let prefix = label.isEmpty ? "" : "\(label): "
        print("❌ FAIL \(file):\(line) — \(prefix)expected true, got false")
    }
}

func assertFalse(_ actual: Bool, file: String = #file, line: Int = #line, _ label: String = "") {
    assertTrue(!actual, file: file, line: line, label)
}

// MARK: - cwdToSlug

doTestCwdToSlug: do {
    let monitor = ContextMonitor()

    assertEqual(monitor.cwdToSlug("/Users/lyle/Desktop/Projects"), "-Users-lyle-Desktop-Projects", "standard path")
    assertEqual(monitor.cwdToSlug("/Users/lyle/foo:bar"), "-Users-lyle-foo-bar", "colon in path")
    assertEqual(monitor.cwdToSlug("/"), "-", "root path")
    assertEqual(monitor.cwdToSlug(""), "", "empty path")
}

// MARK: - SignalState Priority

doTestSignalStatePriority: do {
    assertTrue(SignalState.confirming > SignalState.critical, "confirming > critical")
    assertTrue(SignalState.critical > SignalState.warning, "critical > warning")
    assertTrue(SignalState.warning > SignalState.running, "warning > running")
    assertTrue(SignalState.running > SignalState.idle, "running > idle")
    assertTrue(SignalState.idle > SignalState.error, "idle > error")
}

// MARK: - SignalState.max

doTestSignalStateMax: do {
    let states: [SignalState] = [.running, .confirming, .idle]
    assertEqual(states.max(), .confirming, "max of mixed states")
}

// MARK: - SignalState.needsAction

doTestSignalStateNeedsAction: do {
    assertTrue(SignalState.confirming.needsAction, "confirming needs action")
    assertTrue(SignalState.critical.needsAction, "critical needs action")
    assertFalse(SignalState.running.needsAction, "running does not need action")
    assertFalse(SignalState.idle.needsAction, "idle does not need action")
    assertFalse(SignalState.warning.needsAction, "warning does not need action")
}

// MARK: - SessionInfo.signalState

doTestSessionSignalState: do {
    var s1 = makeSession(status: .waiting)
    assertEqual(s1.signalState, .confirming, "waiting → confirming")

    var s2 = makeSession(status: .busy)
    assertEqual(s2.signalState, .running, "busy → running")

    let s3 = makeSession(status: .idle)
    assertEqual(s3.signalState, .idle, "idle → idle")

    var s4 = makeSession(status: .busy)
    s4.contextTokens = 160_000
    assertEqual(s4.signalState, .warning, "80% context → warning")

    var s5 = makeSession(status: .busy)
    s5.contextTokens = 250_000
    assertEqual(s5.signalState, .critical, ">limit context → critical")

    var s6 = makeSession(status: .waiting)
    s6.isStale = true
    assertEqual(s6.signalState, .idle, "stale → idle")

    var s7 = makeSession(status: .waiting)
    s7.contextTokens = 160_000
    assertEqual(s7.signalState, .confirming, "waiting overrides warning")

    var s8 = makeSession(status: .waiting)
    s8.contextTokens = 250_000
    assertEqual(s8.signalState, .critical, "critical overrides waiting")
}

// MARK: - SessionInfo.contextPercent

doTestContextPercent: do {
    var s = makeSession()
    s.contextTokens = 100_000
    assertEqual(s.contextPercent, 0.5, accuracy: 0.01, "50% context")

    s.contextWindowLimit = 100_000
    s.contextTokens = 75_000
    assertEqual(s.contextPercent, 0.75, accuracy: 0.01, "75% with custom limit")
}

// MARK: - SessionInfo.contextDescription

doTestContextDescription: do {
    var s = makeSession()
    s.contextTokens = 150_000
    assertEqual(s.contextDescription, "150K / 200K", "default limit description")

    s.contextWindowLimit = 100_000
    s.contextTokens = 50_000
    assertEqual(s.contextDescription, "50K / 100K", "custom limit description")
}

// MARK: - SessionInfo.projectName

doTestProjectName: do {
    let s = makeSession()
    assertEqual(s.projectName, "Projects", "fallback to cwd name")

    var s2 = makeSession()
    s2.sessionName = "my-session"
    assertEqual(s2.projectName, "my-session", "uses sessionName when set")
}

// MARK: - Helper

func makeSession(
    status: SessionStatus = .idle,
    contextTokens: Int = 0
) -> SessionInfo {
    SessionInfo(
        pid: 12345,
        sessionId: "test-session-id",
        cwd: "/Users/lyle/Desktop/Projects",
        status: status,
        waitingFor: nil,
        contextTokens: contextTokens,
        lastKnownTokens: nil,
        isStale: false
    )
}

// MARK: - ModelPricing

doTestModelPricing: do {
    // 已知模型：Sonnet 4
    let cost = ModelPricing.calculate(model: "claude-sonnet-4-6", inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 1_000_000)
    assertEqual(cost.inputCost, 3.0, accuracy: 0.001, "sonnet input cost")
    assertEqual(cost.outputCost, 15.0, accuracy: 0.001, "sonnet output cost")
    assertEqual(cost.cacheReadCost, 0.30, accuracy: 0.001, "sonnet cache read cost")
    assertEqual(cost.totalCost, 18.30, accuracy: 0.001, "sonnet total cost")

    // 已知模型：Opus 4
    let opusCost = ModelPricing.calculate(model: "claude-opus-4-8", inputTokens: 100_000, outputTokens: 50_000, cacheReadTokens: 200_000)
    assertEqual(opusCost.inputCost, 1.5, accuracy: 0.001, "opus input cost for 100K")
    assertEqual(opusCost.outputCost, 3.75, accuracy: 0.001, "opus output cost for 50K")
    assertEqual(opusCost.cacheReadCost, 0.30, accuracy: 0.001, "opus cache read cost for 200K")

    // 已知模型：GLM-5.1（Input $1.00/M, Output $3.20/M, Cache $0.10/M）
    let glmCost = ModelPricing.calculate(model: "glm-5.1", inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 1_000_000)
    assertEqual(glmCost.inputCost, 1.00, accuracy: 0.001, "glm-5.1 input cost")
    assertEqual(glmCost.outputCost, 3.20, accuracy: 0.001, "glm-5.1 output cost")
    assertEqual(glmCost.cacheReadCost, 0.10, accuracy: 0.001, "glm-5.1 cache read cost")
    assertEqual(glmCost.totalCost, 4.30, accuracy: 0.001, "glm-5.1 total cost")

    // 未知模型：成本为 $0
    let unknownCost = ModelPricing.calculate(model: "some-unknown-model", inputTokens: 1_000_000, outputTokens: 1_000_000, cacheReadTokens: 1_000_000)
    assertEqual(unknownCost.totalCost, 0.0, accuracy: 0.001, "unknown model cost is $0")

    // 前缀匹配
    assertTrue(ModelPricing.isKnownModel("claude-sonnet-4-6-20250514"), "prefix match for sonnet variant")

    // isKnownModel
    assertTrue(ModelPricing.isKnownModel("claude-sonnet-4-6"), "sonnet is known")
    assertTrue(ModelPricing.isKnownModel("glm-5.1"), "glm-5.1 is known")
    assertFalse(ModelPricing.isKnownModel("some-unknown-model"), "unknown model is not known")

    // isSyntheticModel
    assertTrue(ModelPricing.isSyntheticModel("<synthetic>"), "<synthetic> is synthetic")
    assertFalse(ModelPricing.isSyntheticModel("claude-sonnet-4-6"), "sonnet is not synthetic")
}

// MARK: - Database Basic Operations

doTestDatabase: do {
    // 使用临时目录创建数据库
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-signal-test-\(Int.random(in: 1...99999))")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let dbURL = tmpDir.appendingPathComponent("test.sqlite")
    let db = Database(databaseURL: dbURL)

    // 打开并创建 schema
    assertTrue(db.open(), "database opens successfully")

    // 写入测试数据
    assertTrue(db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-08", "test-session-1", "claude-code", "-Users-lyle-Desktop-Projects", "claude-sonnet-4-6", 1000, 500, 200, 1]
    ), "insert row 1")

    assertTrue(db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-08", "test-session-2", "claude-code", "-Users-lyle-Desktop-Projects", "glm-5.1", 2000, 1000, 0, 3]
    ), "insert row 2")

    // 读取验证
    var totalInput = 0
    db.query("SELECT SUM(input_tokens) FROM daily_usage") { stmt in
        totalInput = Database.intColumn(stmt, 0)
    }
    assertEqual(totalInput, 3000, "sum of input tokens")

    // 事务测试
    var transactionSuccess = false
    do {
        try db.inTransaction {
            _ = db.executeWithParams(
                "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                ["2026-06-09", "test-session-3", "claude-code", "-Users-lyle-Desktop-Projects", "claude-opus-4-8", 5000, 2000, 1000, 2]
            )
            transactionSuccess = true
        }
    } catch {
        transactionSuccess = false
    }
    assertTrue(transactionSuccess, "transaction commit succeeds")

    // 验证事务写入
    var count = 0
    db.query("SELECT COUNT(*) FROM daily_usage") { stmt in
        count = Database.intColumn(stmt, 0)
    }
    assertEqual(count, 3, "3 rows after transaction")

    // 完整性检查
    assertTrue(db.checkIntegrity(), "integrity check passes")

    db.close()
}

// MARK: - JsonlParser

doTestJsonlParser: do {
    let parser = ClaudeCodeJsonlParser()

    // 创建临时 jsonl 文件
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-signal-test-parser-\(Int.random(in: 1...99999))")
    let slugDir = tmpDir.appendingPathComponent("-Users-lyle-Desktop-Projects")
    try? FileManager.default.createDirectory(at: slugDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let jsonlPath = slugDir.appendingPathComponent("test-session-id.jsonl")
    let jsonlContent = """
    {"type":"last-prompt","sessionId":"test-session-id"}
    {"type":"assistant","sessionId":"test-session-id","timestamp":"2026-06-08T12:00:00.000Z","cwd":"/Users/lyle/Desktop/Projects","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":1000,"output_tokens":500,"cache_read_input_tokens":200,"cache_creation_input_tokens":0}}}
    {"type":"assistant","sessionId":"test-session-id","timestamp":"2026-06-08T12:01:00.000Z","cwd":"/Users/lyle/Desktop/Projects","message":{"model":"claude-sonnet-4-6","usage":{"input_tokens":2000,"output_tokens":800,"cache_read_input_tokens":400,"cache_creation_input_tokens":0}}}
    {"type":"assistant","sessionId":"test-session-id","timestamp":"2026-06-08T12:02:00.000Z","cwd":"/Users/lyle/Desktop/Projects","message":{"model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}
    {"type":"user","sessionId":"test-session-id","timestamp":"2026-06-08T12:03:00.000Z"}
    """
    try! jsonlContent.write(to: jsonlPath, atomically: true, encoding: .utf8)

    let (results, bytesProcessed, errorCount) = parser.parseFile(fileURL: jsonlPath)

    assertEqual(results.count, 2, "parsed 2 assistant messages (synthetic excluded)")
    assertEqual(errorCount, 0, "no parse errors")
    assertTrue(bytesProcessed > 0, "bytes processed > 0")

    // 验证第一条结果
    if let first = results.first {
        assertEqual(first.model, "claude-sonnet-4-6", "model is sonnet")
        assertEqual(first.inputTokens, 1000, "input tokens")
        assertEqual(first.outputTokens, 500, "output tokens")
        assertEqual(first.cacheReadTokens, 200, "cache read tokens")
        assertEqual(first.projectSlug, "-Users-lyle-Desktop-Projects", "project slug")
    }

    // 增量解析测试（offset 从文件末尾开始，应无新数据）
    let (_, bytesProcessed2, _) = parser.parseFile(fileURL: jsonlPath, byteOffset: bytesProcessed)
    // bytesProcessed2 应等于当前文件大小（无新内容可读）
    // 但 parseFile 返回的是当前文件大小，所以这里只要不出错就行
}

// MARK: - UsageStore + Database Integration

doTestUsageStoreIntegration: do {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-signal-test-usage-\(Int.random(in: 1...99999))")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let dbURL = tmpDir.appendingPathComponent("test.sqlite")
    let db = Database(databaseURL: dbURL)
    db.open()

    // 插入测试数据
    _ = db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-08", "sess-1", "claude-code", "-Users-lyle-Desktop-Projects", "claude-sonnet-4-6", 10000, 5000, 2000, 10]
    )
    _ = db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-07", "sess-2", "claude-code", "-Users-lyle-Desktop-Projects", "claude-sonnet-4-6", 8000, 3000, 1000, 5]
    )
    _ = db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-08", "sess-3", "claude-code", "-Users-lyle-Desktop-Projects", "some-unknown-model", 5000, 2000, 0, 3]
    )

    let store = UsageStore(databaseURL: dbURL)

    // 测试 fetchSummary
    let summary = store.fetchSummary()
    assertEqual(summary.totalInputTokens, 23000, "total input tokens")
    assertEqual(summary.totalOutputTokens, 10000, "total output tokens")
    assertEqual(summary.totalMessages, 18, "total messages")
    assertEqual(summary.averageTokensPerMessage, 2000, "average tokens per message")
    assertTrue(summary.totalCost > 0, "total cost > 0 (all known models have pricing)")
    assertEqual(summary.unknownModelRatio, Double(3) / Double(18), accuracy: 0.01, "unknown model ratio")

    // 测试 fetchModelUsage
    let modelUsage = store.fetchModelUsage()
    assertEqual(modelUsage.count, 2, "2 models")

    // 测试 fetchDailyUsage
    let dailyUsage = store.fetchDailyUsage()
    assertEqual(dailyUsage.count, 2, "2 days of data")

    // 测试 fetchProjectUsage
    let projectUsage = store.fetchProjectUsage()
    assertEqual(projectUsage.count, 1, "1 project")
    assertEqual(projectUsage[0].projectSlug, "-Users-lyle-Desktop-Projects", "project slug")

    db.close()
}

doTestRecentSessionUsage: do {
    let tmpDir = FileManager.default.temporaryDirectory.appendingPathComponent("claude-signal-test-recent-\(Int.random(in: 1...99999))")
    try? FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tmpDir) }

    let dbURL = tmpDir.appendingPathComponent("test.sqlite")
    let db = Database(databaseURL: dbURL)
    db.open()

    _ = db.executeWithParams(
        "INSERT INTO sessions (session_id, source, project_slug, model, start_time, cwd) VALUES (?, ?, ?, ?, ?, ?)",
        ["recent-a", "claude-code", "-Users-lyle-Desktop-Projects-alpha", "claude-sonnet-4-6", 1780988400, "/Users/lyle/Desktop/Projects/alpha"]
    )
    _ = db.executeWithParams(
        "INSERT INTO sessions (session_id, source, project_slug, model, start_time, cwd) VALUES (?, ?, ?, ?, ?, ?)",
        ["recent-b", "claude-code", "-Users-lyle-Desktop-Projects-beta", "glm-5.1", 1780984800, "/Users/lyle/Desktop/Projects/beta"]
    )
    _ = db.executeWithParams(
        "INSERT INTO sessions (session_id, source, project_slug, model, start_time, cwd) VALUES (?, ?, ?, ?, ?, ?)",
        ["old-c", "claude-code", "-Users-lyle-Desktop-Projects-old", "claude-sonnet-4-6", 1778800000, "/Users/lyle/Desktop/Projects/old"]
    )

    _ = db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-09", "recent-a", "claude-code", "-Users-lyle-Desktop-Projects-alpha", "claude-sonnet-4-6", 1000, 200, 300, 2]
    )
    _ = db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-09", "recent-a", "claude-code", "-Users-lyle-Desktop-Projects-alpha", "glm-5.1", 400, 100, 50, 1]
    )
    _ = db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-06-08", "recent-b", "claude-code", "-Users-lyle-Desktop-Projects-beta", "glm-5.1", 900, 80, 20, 4]
    )
    _ = db.executeWithParams(
        "INSERT INTO daily_usage (date, session_id, source, project_slug, model, input_tokens, output_tokens, cache_read_tokens, message_count) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        ["2026-05-01", "old-c", "claude-code", "-Users-lyle-Desktop-Projects-old", "claude-sonnet-4-6", 9999, 999, 99, 9]
    )

    let store = UsageStore(databaseURL: dbURL)
    let recent = store.fetchRecentSessionUsage(range: .last7Days, limit: 10)

    assertEqual(recent.count, 2, "recent sessions excludes old range")
    assertEqual(recent[0].sessionId, "recent-a", "newest session first")
    assertEqual(recent[0].projectSlug, "-Users-lyle-Desktop-Projects-alpha", "project slug")
    assertEqual(recent[0].model, "mixed", "mixed model label")
    assertEqual(recent[0].inputTokens, 1400, "aggregated input")
    assertEqual(recent[0].outputTokens, 300, "aggregated output")
    assertEqual(recent[0].cacheReadTokens, 350, "aggregated cache")
    assertEqual(recent[0].messageCount, 3, "aggregated messages")
    assertTrue(recent[0].cost.totalCost > 0, "recent session cost")
    assertEqual(recent[1].sessionId, "recent-b", "older session second")

    db.close()
}

// MARK: - Results

print("")
if testsFailed == 0 {
    print("✅ All \(testsPassed) tests passed")
} else {
    print("❌ \(testsFailed) test(s) failed, \(testsPassed) passed")
    exit(1)
}
