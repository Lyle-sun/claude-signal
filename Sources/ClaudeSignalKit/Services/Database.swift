import Foundation
import SQLite3
import os.log

/// SQLite3 薄封装
/// 提供数据库打开/关闭、建表、增删改查等基础操作
/// 线程安全：所有操作在调用方管理的串行队列上执行
final public class Database {
    private var db: OpaquePointer?
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "Database")

    /// 数据库文件路径
    public let databaseURL: URL

    /// 当前 schema 版本
    private let currentSchemaVersion = 1

    // MARK: - Init / Deinit

    public init(databaseURL: URL) {
        self.databaseURL = databaseURL
    }

    deinit {
        close()
    }

    // MARK: - Open / Close

    /// 打开数据库，不存在则创建
    /// - Returns: true 表示成功
    @discardableResult
    public func open() -> Bool {
        guard db == nil else { return true }

        // 确保目录存在
        let dir = databaseURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE
        let result = sqlite3_open_v2(databaseURL.path, &db, flags, nil)

        if result != SQLITE_OK {
            let errMsg: String = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            logger.error("Failed to open database: \(errMsg)")
            if let db { sqlite3_close(db) }
            self.db = nil
            return false
        }

        // 启用 WAL 模式（并发读写更安全）
        execute("PRAGMA journal_mode=WAL")
        // 启用外键约束
        execute("PRAGMA foreign_keys=ON")

        return createSchema()
    }

    /// 以只读模式打开数据库（不创建、不建 schema，用于读取端）
    @discardableResult
    public func openReadOnly() -> Bool {
        guard db == nil else { return true }

        // 文件不存在则不打开（读取端不负责创建）
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            logger.info("Database file not found, skipping openReadOnly")
            return false
        }

        let flags = SQLITE_OPEN_READONLY
        guard FileManager.default.fileExists(atPath: databaseURL.path) else {
            logger.info("Database file not found, skipping openReadOnly")
            return false
        }

        let result = sqlite3_open_v2(databaseURL.path, &db, flags, nil)

        if result != SQLITE_OK {
            let errMsg: String = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            logger.error("Failed to open database (readonly): \(errMsg)")
            if let db { sqlite3_close(db) }
            self.db = nil
            return false
        }

        // 启用 WAL 模式（确保能看到写入端的已提交数据）
        execute("PRAGMA journal_mode=WAL")

        return true
    }

    public func close() {
        guard let db else { return }
        sqlite3_close(db)
        self.db = nil
    }

    // MARK: - Schema

    private func createSchema() -> Bool {
        // 检查 schema 版本
        let version = getInt("SELECT version FROM schema_version LIMIT 1") ?? 0

        if version == currentSchemaVersion {
            return true // 已是最新
        }

        if version == 0 {
            // 全新数据库
            return createSchemaV1()
        }

        // 未来版本迁移在此添加
        // if version == 1 { return migrateV1toV2() }

        logger.error("Unknown schema version: \(version)")
        return false
    }

    private func createSchemaV1() -> Bool {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS sessions (
                session_id TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                project_slug TEXT NOT NULL,
                model TEXT,
                start_time INTEGER,
                end_time INTEGER,
                pid INTEGER,
                cwd TEXT
            )
            """,

            """
            CREATE TABLE IF NOT EXISTS daily_usage (
                date TEXT NOT NULL,
                session_id TEXT NOT NULL,
                source TEXT NOT NULL,
                project_slug TEXT NOT NULL,
                model TEXT NOT NULL,
                input_tokens INTEGER DEFAULT 0,
                output_tokens INTEGER DEFAULT 0,
                cache_read_tokens INTEGER DEFAULT 0,
                message_count INTEGER DEFAULT 0,
                PRIMARY KEY (date, session_id, source, model)
            )
            """,

            """
            CREATE TABLE IF NOT EXISTS index_state (
                project_slug TEXT PRIMARY KEY,
                source TEXT NOT NULL,
                last_indexed_byte_offset INTEGER DEFAULT 0,
                last_file_size INTEGER DEFAULT 0,
                last_file_mtime REAL DEFAULT 0,
                last_error TEXT
            )
            """,

            "CREATE INDEX IF NOT EXISTS idx_daily_usage_project_date ON daily_usage(project_slug, date)",
            "CREATE INDEX IF NOT EXISTS idx_daily_usage_source ON daily_usage(source, date)",

            """
            CREATE TABLE IF NOT EXISTS schema_version (
                version INTEGER PRIMARY KEY
            )
            """,

            "INSERT OR REPLACE INTO schema_version (version) VALUES (1)"
        ]

        for sql in statements {
            if !execute(sql) {
                logger.error("Failed to create schema, statement: \(sql)")
                return false
            }
        }

        logger.info("Database schema v1 created")
        return true
    }

    // MARK: - Execute

    /// 执行无返回值的 SQL 语句
    @discardableResult
    public func execute(_ sql: String) -> Bool {
        guard let db else {
            logger.error("Database not open")
            return false
        }

        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)

        if result != SQLITE_OK {
            let errMsg = String(cString: sqlite3_errmsg(db))
            logger.error("Prepare failed: \(sql) — \(errMsg)")
            return false
        }

        let stepResult = sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        if stepResult != SQLITE_DONE && stepResult != SQLITE_ROW {
            let errMsg = String(cString: sqlite3_errmsg(db))
            logger.error("Execute failed: \(sql) — \(errMsg)")
            return false
        }

        return true
    }

    // MARK: - Query Helpers

    /// 执行查询，返回单个 Int 值
    func getInt(_ sql: String) -> Int? {
        guard let db else { return nil }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(stmt) }

        guard sqlite3_step(stmt) == SQLITE_ROW else { return nil }
        return Int(sqlite3_column_int64(stmt, 0))
    }

    /// 执行带参数的查询，对每行调用 callback
    public func query(_ sql: String, _ params: [Any] = [], _ rowHandler: (OpaquePointer) -> Void) {
        guard let db else { return }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Query prepare failed: \(String(cString: sqlite3_errmsg(db)))")
            return
        }

        // 绑定参数
        bindParams(stmt: stmt, params: params)

        while sqlite3_step(stmt!) == SQLITE_ROW {
            rowHandler(stmt!)
        }

        sqlite3_finalize(stmt)
    }

    /// 执行带参数的增删改，返回受影响行数
    @discardableResult
    public func executeWithParams(_ sql: String, _ params: [Any] = []) -> Bool {
        guard let db else { return false }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK else {
            logger.error("Prepare failed: \(sql) — \(String(cString: sqlite3_errmsg(db)))")
            return false
        }

        bindParams(stmt: stmt, params: params)

        let result = sqlite3_step(stmt)
        sqlite3_finalize(stmt)

        if result != SQLITE_DONE {
            logger.error("Execute failed: \(sql) — \(String(cString: sqlite3_errmsg(db)))")
            return false
        }

        return true
    }

    // MARK: - Transaction

    public func beginTransaction() -> Bool {
        execute("BEGIN TRANSACTION")
    }

    public func commit() -> Bool {
        execute("COMMIT")
    }

    public func rollback() -> Bool {
        execute("ROLLBACK")
    }

    /// 在事务中执行闭包，自动 commit/rollback
    public func inTransaction<T>(_ block: () throws -> T) throws -> T {
        _ = beginTransaction()
        do {
            let result = try block()
            _ = commit()
            return result
        } catch {
            _ = rollback()
            throw error
        }
    }

    // MARK: - Bind Helpers

    private func bindParams(stmt: OpaquePointer?, params: [Any]) {
        guard let stmt else { return }

        for (index, param) in params.enumerated() {
            let idx = Int32(index + 1) // SQLite 参数从 1 开始

            switch param {
            case let text as String:
                sqlite3_bind_text(stmt, idx, (text as NSString).utf8String, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            case let num as Int:
                sqlite3_bind_int64(stmt, idx, Int64(num))
            case let num as Double:
                sqlite3_bind_double(stmt, idx, num)
            case let num as Int64:
                sqlite3_bind_int64(stmt, idx, num)
            case is NSNull:
                sqlite3_bind_null(stmt, idx)
            default:
                logger.warning("Unsupported param type at index \(index): \(type(of: param))")
                sqlite3_bind_null(stmt, idx)
            }
        }
    }

    // MARK: - Column Helpers

    /// 从查询结果读取 String 列
    public static func stringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        guard let cStr = sqlite3_column_text(stmt, index) else { return nil }
        return String(cString: cStr)
    }

    /// 从查询结果读取 Int 列
    public static func intColumn(_ stmt: OpaquePointer, _ index: Int32) -> Int {
        Int(sqlite3_column_int64(stmt, index))
    }

    /// 从查询结果读取 Double 列
    public static func doubleColumn(_ stmt: OpaquePointer, _ index: Int32) -> Double {
        sqlite3_column_double(stmt, index)
    }

    /// 从查询结果读取可能为 NULL 的 String 列
    public static func optionalStringColumn(_ stmt: OpaquePointer, _ index: Int32) -> String? {
        if sqlite3_column_type(stmt, index) == SQLITE_NULL {
            return nil
        }
        return stringColumn(stmt, index)
    }

    // MARK: - Database Health

    /// 检测数据库是否损坏，如果损坏则删除重建
    public func checkIntegrity() -> Bool {
        guard let db else { return false }

        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(db, "PRAGMA integrity_check", -1, &stmt, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(stmt) }

        while sqlite3_step(stmt) == SQLITE_ROW {
            let result = String(cString: sqlite3_column_text(stmt, 0))
            if result != "ok" {
                logger.error("Database integrity check failed: \(result)")
                return false
            }
        }

        return true
    }

    /// 删除数据库文件并重新打开
    public func deleteAndRecreate() -> Bool {
        close()
        try? FileManager.default.removeItem(at: databaseURL)
        // 也删除 WAL 和 SHM 文件
        let walURL = databaseURL.appendingPathExtension("wal")
        let shmURL = databaseURL.appendingPathExtension("shm")
        try? FileManager.default.removeItem(at: walURL)
        try? FileManager.default.removeItem(at: shmURL)

        logger.info("Database deleted, recreating...")
        return open()
    }
}
