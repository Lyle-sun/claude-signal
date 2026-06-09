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
        let tty = ttyPath(forPID: pid) ?? parentTTYPath(forPID: pid)
        logger.info("Activating terminal for PID \(pid), terminal=\(terminal.rawValue, privacy: .public), tty=\(tty ?? "nil", privacy: .public)")

        switch terminal {
        case .terminal:
            if let tty, activateTerminalTab(tty: tty) {
                return
            }
            activateApplication(appName: "Terminal", pid: pid)
        case .iterm:
            if let tty, activateITermSession(tty: tty) {
                return
            }
            if activateApplication(appName: "iTerm2", pid: pid) {
                return
            }
            activateApplication(appName: "iTerm", pid: pid)
        case .warp:
            // Warp 不支持 AppleScript，回退到复制命令
            _ = activateApplication(appName: "Warp", pid: pid)
            copyToClipboard("Claude Code 需要确认 (PID \(pid))")
            logger.info("Warp detected: copied prompt to clipboard")
        case .unknown:
            if let tty, activateITermSession(tty: tty) {
                return
            }
            if let tty, activateTerminalTab(tty: tty) {
                return
            }
            if activateApplication(appName: "iTerm2", pid: pid) {
                return
            }
            if activateApplication(appName: "iTerm", pid: pid) {
                return
            }
            activateApplication(appName: "Terminal", pid: pid)
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

    private func parentTTYPath(forPID pid: Int) -> String? {
        var currentPID = pid
        var visited = Set<Int>()

        for _ in 0..<20 {
            guard currentPID > 1, !visited.contains(currentPID) else { break }
            visited.insert(currentPID)

            let output = Self.runCommand(
                "/bin/ps",
                arguments: ["-p", "\(currentPID)", "-o", "pid=,ppid=,tty="]
            ).trimmingCharacters(in: .whitespacesAndNewlines)

            guard !output.isEmpty else { break }
            let parts = output.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count >= 3, let parentPID = Int(parts[1]) else { break }

            let tty = String(parts[2])
            if !tty.isEmpty, tty != "??" {
                return tty.hasPrefix("/dev/") ? tty : "/dev/\(tty)"
            }

            currentPID = parentPID
        }

        return nil
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

    @discardableResult
    private func activateApplication(appName: String, pid: Int) -> Bool {
        if activateViaAppleScript(appName: appName, pid: pid) {
            return true
        }

        if activateViaWorkspace(appName: appName) {
            return true
        }

        let result = Self.runCommandResult("/usr/bin/open", arguments: ["-a", appName])
        if result.exitCode == 0 {
            return true
        }

        logger.error("Failed to activate \(appName, privacy: .public): \(result.output, privacy: .public)")
        copyToClipboard("Claude Code 需要确认 (PID \(pid))")
        return false
    }

    private func activateViaAppleScript(appName: String, pid: Int) -> Bool {
        let script = """
        tell application "\(appName)"
            activate
        end tell
        """

        guard let nsScript = NSAppleScript(source: script) else {
            return false
        }

        var error: NSDictionary?
        nsScript.executeAndReturnError(&error)
        if let err = error {
            logger.error("AppleScript error: \(err.description)")
            return false
        }
        return true
    }

    private func activateViaWorkspace(appName: String) -> Bool {
        let normalized = appName.lowercased()
        let aliases: Set<String>
        switch normalized {
        case "iterm", "iterm2":
            aliases = ["iterm", "iterm2"]
        default:
            aliases = [normalized]
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: { runningApp in
            let name = runningApp.localizedName?.lowercased()
            return name.map { aliases.contains($0) } ?? false
        }) else {
            return false
        }

        return app.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
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
        runCommandResult(launchPath, arguments: arguments).output
    }

    private static func runCommandResult(_ launchPath: String, arguments: [String]) -> (output: String, exitCode: Int32) {
        let task = Process()
        task.launchPath = launchPath
        task.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        task.standardOutput = outputPipe
        task.standardError = errorPipe

        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            return (error.localizedDescription, -1)
        }

        let output = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let error = errorPipe.fileHandleForReading.readDataToEndOfFile()
        let combined = output + error
        return (String(data: combined, encoding: .utf8) ?? "", task.terminationStatus)
    }

    private func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
