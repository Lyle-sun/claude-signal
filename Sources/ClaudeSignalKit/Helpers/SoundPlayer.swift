import Foundation
import AppKit
import os.log

/// 播放声音提醒，每会话独立冷却
/// 跟踪 (pid, SignalState) 对：会话从非 confirming 进入 confirming 时触发
final class SoundPlayer: SoundPlaying {
    private let logger = Logger(subsystem: "com.claude-signal.app", category: "SoundPlayer")

    /// 已响铃的会话 PID 集合（本次 confirming 持续期间）
    private var alertedPIDs: Set<Int> = []

    /// 是否全局静音
    var isMuted: Bool = false

    /// 对指定会话播放提醒
    /// - 当会话进入 confirming 状态时触发声音
    /// - 当会话离开 confirming 再重新进入，会再次触发（per-session 冷却重置）
    func alertIfNeeded(for session: SessionInfo, previousState: SignalState?) {
        guard !isMuted else { return }
        guard session.signalState == .confirming else { return }
        // 只有从非 confirming 状态首次进入时才触发
        guard previousState != .confirming else { return }

        // 如果之前已经为这个 PID 响过铃且会话一直处于 confirming，跳过
        // 但如果会话曾经离开 confirming（previousSessionStates 已在 LighthouseController 中清除），
        // 则 alertedPIDs 中不会有此 PID，会重新触发
        guard !alertedPIDs.contains(session.pid) else { return }

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

    /// 会话离开 confirming 状态时清除该 PID 的响铃记录
    /// 这样如果会话再次进入 confirming，会重新触发声音
    func sessionLeftConfirming(pid: Int) {
        alertedPIDs.remove(pid)
    }

    /// 清除所有冷却记录
    func reset() {
        alertedPIDs.removeAll()
    }
}
