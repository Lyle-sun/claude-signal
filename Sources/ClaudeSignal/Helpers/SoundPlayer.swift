import Foundation
import AppKit
import os.log

/// 播放声音提醒，每会话独立冷却
final class SoundPlayer {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "SoundPlayer")

    /// 已响铃的会话 PID 集合
    private var alertedPIDs: Set<Int> = []

    /// 是否全局静音
    var isMuted: Bool = false

    /// 对指定会话播放提醒（首次进入 confirming 时）
    func alertIfNeeded(for session: SessionInfo, previousState: SignalState?) {
        guard !isMuted else { return }
        guard session.signalState == .confirming else { return }
        guard previousState != .confirming else { return }  // 不是首次进入
        guard !alertedPIDs.contains(session.pid) else { return }  // 该会话已响过

        alertedPIDs.insert(session.pid)

        if let sound = NSSound(named: "Sosumi") {
            sound.play()
            logger.info("Sound alert for PID \(session.pid)")
        }
    }

    /// 会话消失时清除冷却记录
    func removeSession(pid: Int) {
        alertedPIDs.remove(pid)
    }

    /// 清除所有冷却记录
    func reset() {
        alertedPIDs.removeAll()
    }
}
