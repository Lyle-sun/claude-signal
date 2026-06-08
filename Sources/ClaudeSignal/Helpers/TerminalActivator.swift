import Foundation
import AppKit
import os.log

/// 激活终端窗口（Terminal.app / iTerm2），Warp 回退到复制命令
final class TerminalActivator {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "TerminalActivator")

    enum TerminalApp: String, CaseIterable {
        case terminal = "Terminal"
        case iterm = "iTerm"
        case warp = "Warp"
        case unknown

        static func detect(forPID pid: Int) -> TerminalApp {
            // 通过 ps 获取进程的父终端
            let task = Process()
            task.launchPath = "/bin/ps"
            task.arguments = ["-o", "comm=", "-p", "\(pid)"]

            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()

            let _ = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)

            // 检查父进程链中是否有已知终端
            if isParentProcess("Terminal", ofPID: pid) { return .terminal }
            if isParentProcess("iTerm2", ofPID: pid) { return .iterm }
            if isParentProcess("Warp", ofPID: pid) { return .warp }
            return .unknown
        }

        private static func isParentProcess(_ name: String, ofPID pid: Int) -> Bool {
            let task = Process()
            task.launchPath = "/usr/bin/pgrep"
            task.arguments = ["-P", "\(pid)", "-l"]

            let pipe = Pipe()
            task.standardOutput = pipe
            try? task.run()
            task.waitUntilExit()

            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? ""
            return output.contains(name)
        }
    }

    /// 激活指定 PID 对应的终端窗口
    func activateTerminal(forPID pid: Int) {
        let terminal = TerminalApp.detect(forPID: pid)

        switch terminal {
        case .terminal:
            activateViaAppleScript(appName: "Terminal", pid: pid)
        case .iterm:
            activateViaAppleScript(appName: "iTerm", pid: pid)
        case .warp:
            // Warp 不支持 AppleScript，回退到复制命令
            copyToClipboard(" Claude Code 需要确认 (PID \(pid))")
            logger.info("Warp detected: copied prompt to clipboard")
        case .unknown:
            // 尝试通用方式：激活 Terminal.app
            activateViaAppleScript(appName: "Terminal", pid: pid)
        }
    }

    private func activateViaAppleScript(appName: String, pid: Int) {
        let script = """
        tell application "\(appName)"
            activate
        end tell
        """

        if let nsScript = NSAppleScript(source: script) {
            var error: NSDictionary?
            nsScript.executeAndReturnError(&error)
            if let err = error {
                logger.error("AppleScript error: \(err.description)")
                // 回退到复制命令
                copyToClipboard("Claude Code 需要确认 (PID \(pid))")
            }
        }
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
