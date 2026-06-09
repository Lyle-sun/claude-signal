import Foundation
import os.log

/// 监控 ~/.claude/sessions/ 目录，读取会话状态
final class SessionMonitor: SessionMonitoring {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "SessionMonitor")

    /// Claude Code 数据根目录（可注入，默认 ~/.claude）
    let claudeDir: URL

    init(claudeDir: URL? = nil) {
        self.claudeDir = claudeDir ?? FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    private var sessionsDir: URL {
        claudeDir.appendingPathComponent("sessions")
    }

    /// 获取所有活跃的 Claude Code 会话
    func fetchSessions() -> [SessionInfo] {
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            logger.info("Sessions directory not found")
            return []
        }

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: sessionsDir,
            includingPropertiesForKeys: nil
        ) else {
            logger.error("Failed to list sessions directory")
            return []
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }

        return jsonFiles.compactMap { fileURL -> SessionInfo? in
            guard let pid = Int(fileURL.deletingPathExtension().lastPathComponent) else {
                return nil
            }

            // 僵尸检测：验证进程是否存活
            let isAlive = kill(pid_t(pid), 0) == 0
            if !isAlive {
                logger.debug("Stale session file: PID \(pid) no longer exists")
            }

            guard let data = try? Data(contentsOf: fileURL),
                  let sessionFile = try? JSONDecoder().decode(SessionFile.self, from: data) else {
                logger.warning("Failed to parse session file: \(fileURL.lastPathComponent)")
                return nil
            }

            return SessionInfo(
                pid: pid,
                sessionId: sessionFile.sessionId,
                cwd: sessionFile.cwd,
                status: sessionFile.status,
                waitingFor: sessionFile.waitingFor,
                contextTokens: 0,
                lastKnownTokens: nil,
                isStale: !isAlive,
                sessionName: sessionFile.name,
                startedAt: sessionFile.startedAt.map { Date(timeIntervalSince1970: Double($0) / 1000) }
            )
        }
        .filter { !$0.isStale }
    }

    /// 检查 ~/.claude/ 目录是否存在
    var isInstalled: Bool {
        FileManager.default.fileExists(atPath: claudeDir.path)
    }
}
