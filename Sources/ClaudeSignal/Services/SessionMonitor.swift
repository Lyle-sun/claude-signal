import Foundation
import os.log

/// 监控 ~/.claude/sessions/ 目录，读取会话状态
final class SessionMonitor {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "SessionMonitor")

    private var claudeDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude")
    }

    private var sessionsDir: URL {
        claudeDir.appendingPathComponent("sessions")
    }

    /// 获取所有活跃的 Claude Code 会话
    func fetchSessions() -> [SessionInfo] {
        guard FileManager.default.fileExists(atPath: sessionsDir.path) else {
            logger.info("Sessions directory not found: \(self.sessionsDir.path)")
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
                isStale: !isAlive
            )
        }
        .filter { !$0.isStale }  // 过滤掉僵尸会话
    }

    /// 检查 ~/.claude/ 目录是否存在
    var claudeDirExists: Bool {
        FileManager.default.fileExists(atPath: claudeDir.path)
    }
}
