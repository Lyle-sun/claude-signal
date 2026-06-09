import Foundation

/// 声音提醒协议
protocol SoundPlaying: AnyObject {
    /// 是否全局静音
    var isMuted: Bool { get set }

    /// 对指定会话播放提醒（首次进入 needsAction 状态时）
    func alertIfNeeded(for session: SessionInfo, previousState: SignalState?)

    /// 会话消失时清除冷却记录
    func removeSession(pid: Int)

    /// 会话离开 confirming 状态时重置冷却（允许重新触发）
    func sessionLeftConfirming(pid: Int)

    /// 清除所有冷却记录
    func reset()
}
