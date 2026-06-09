import Foundation

/// 会话监控协议 — 读取 AI CLI 工具的会话状态文件
protocol SessionMonitoring {
    /// 获取所有活跃会话
    func fetchSessions() -> [SessionInfo]

    /// 数据目录是否存在
    var isInstalled: Bool { get }
}
