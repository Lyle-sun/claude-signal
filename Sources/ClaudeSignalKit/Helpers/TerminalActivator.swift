import Foundation
import AppKit
import os.log

/// 激活终端窗口（Terminal.app / iTerm2），Warp 回退到复制命令
final class TerminalActivator: TerminalActivating {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "TerminalActivator")

    enum TerminalApp: String, CaseIterable {
        case terminal = "Terminal"
        case iterm = "iTerm2"
        case warp = "Warp"
        case unknown

        static func detect(forPID pid: Int) -> TerminalApp {
            let chain = parentProcessChain(startingAt: pid).joined(separator: "\n")
            if chain.contains("iTerm.app") || chain.contains("iTerm2") || chain.contains("iTermServer") {
                return .iterm
            }
            if chain.contains("Terminal.app") || chain.contains("/Terminal ") {
                return .terminal
            }
            if chain.contains("Warp.app") || chain.contains("/Warp ") {
                return .warp
            }
            return .unknown
        }

        private static func parentProcessChain(startingAt pid: Int) -> [String] {
            var currentPID = pid
            var chain: [String] = []
            var visited = Set<Int>()

            for _ in 0..<20 {
                guard currentPID > 1, !visited.contains(currentPID) else { break }
                visited.insert(currentPID)

                let output = TerminalActivator.runCommand(
                    "/bin/ps",
                    arguments: ["-p", "\(currentPID)", "-o", "pid=,ppid=,comm=,args="]
                ).trimmingCharacters(in: .whitespacesAndNewlines)

                guard !output.isEmpty else { break }
                chain.append(output)

                let parts = output.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
                guard parts.count >= 2, let parentPID = Int(parts[1]) else { break }
                currentPID = parentPID
            }

            return chain
        }
    }

    /// 激活指定 PID 对应的终端窗口
    func activateTerminal(forPID pid: Int) {
        let terminal = TerminalApp.detect(forPID: pid)
        let tty = ttyPath(forPID: pid)

        switch terminal {
        case .terminal:
            if let tty, activateTerminalTab(tty: tty) {
                return
            }
            activateViaAppleScript(appName: "Terminal", pid: pid)
        case .iterm:
            if let tty, activateITermSession(tty: tty) {
                return
            }
            activateViaAppleScript(appName: "iTerm2", pid: pid)
        case .warp:
            // Warp 不支持 AppleScript，回退到复制命令
            copyToClipboard(" Claude Code 需要确认 (PID \(pid))")
            logger.info("Warp detected: copied prompt to clipboard")
        case .unknown:
            if let tty, activateITermSession(tty: tty) {
                return
            }
            if let tty, activateTerminalTab(tty: tty) {
                return
            }
            activateViaAppleScript(appName: "Terminal", pid: pid)
        }
    }

    private func ttyPath(forPID pid: Int) -> String? {
        let output = Self.runCommand("/bin/ps", arguments: ["-p", "\(pid)", "-o", "tty="])
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !output.isEmpty, output != "??" else { return nil }
        if output.hasPrefix("/dev/") {
            return output
        }
        return "/dev/\(output)"
    }

    private func activateITermSession(tty: String) -> Bool {
        let script = """
        tell application "iTerm2"
            repeat with w in windows
                repeat with t in tabs of w
                    repeat with s in sessions of t
                        if tty of s is "\(escapeAppleScriptString(tty))" then
                            select w
                            select t
                            select s
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end repeat
            return false
        end tell
        """

        return executeBoolAppleScript(script)
    }

    private func activateTerminalTab(tty: String) -> Bool {
        let script = """
        tell application "Terminal"
            repeat with w in windows
                repeat with t in tabs of w
                    if tty of t is "\(escapeAppleScriptString(tty))" then
                        set selected of t to true
                        set index of w to 1
                        activate
                        return true
                    end if
                end repeat
            end repeat
            return false
        end tell
        """

        return executeBoolAppleScript(script)
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

    private func executeBoolAppleScript(_ script: String) -> Bool {
        guard let nsScript = NSAppleScript(source: script) else { return false }

        var error: NSDictionary?
        let result = nsScript.executeAndReturnError(&error)
        if let err = error {
            logger.error("AppleScript error: \(err.description)")
            return false
        }

        return result.booleanValue
    }

    private func escapeAppleScriptString(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func runCommand(_ launchPath: String, arguments: [String]) -> String {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments

        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return ""
        }

        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
