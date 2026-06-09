import Foundation

/// 终端激活协议 — 跳转到指定 PID 对应的终端窗口
protocol TerminalActivating {
    /// 激活指定 PID 对应的终端窗口
    func activateTerminal(forPID pid: Int)
}
