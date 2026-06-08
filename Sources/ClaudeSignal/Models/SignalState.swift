import SwiftUI

/// 全局信号状态，优先级：confirming > critical > warning > running > idle > error
enum SignalState: Int, Comparable {
    case error = 0       // 检测失败 → 灰灯 xmark.octagon
    case idle = 1        // 无会话 / session.idle → 灰灯 circle
    case running = 2     // session.busy → 绿灯 play.fill
    case warning = 3     // context > 150K → 黄灯 exclamationmark.circle.fill
    case critical = 4    // context > 200K → 红灯 xmark.circle.fill
    case confirming = 5  // session.waiting → 红灯 exclamationmark.triangle.fill

    // MARK: - Comparable

    static func < (lhs: SignalState, rhs: SignalState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Visual Properties

    /// SF Symbol 名称
    var sfSymbolName: String {
        switch self {
        case .idle:        return "circle"
        case .running:     return "play.fill"
        case .confirming:  return "exclamationmark.triangle.fill"
        case .warning:     return "exclamationmark.circle.fill"
        case .critical:    return "xmark.circle.fill"
        case .error:       return "xmark.octagon"
        }
    }

    /// 图标颜色
    var color: Color {
        switch self {
        case .idle:        return .gray.opacity(0.4)
        case .running:     return .green
        case .confirming:  return .red
        case .warning:     return .yellow
        case .critical:    return .red
        case .error:       return .gray
        }
    }

    /// 人类可读描述
    var description: String {
        switch self {
        case .idle:        return "空闲"
        case .running:     return "运行中"
        case .confirming:  return "等待确认"
        case .warning:     return "Context 接近上限"
        case .critical:    return "Context 超限"
        case .error:       return "检测错误"
        }
    }

    /// 是否需要用户操作
    var needsAction: Bool {
        self == .confirming || self == .critical
    }

    /// 菜单栏 emoji 图标（macOS 暗色模式下 NSStatusBarButton 强制 template 渲染，自定义颜色不生效，用 emoji 替代）
    var emoji: String {
        switch self {
        case .idle:        return "⚪"
        case .running:     return "🟢"
        case .confirming:  return "🔴"
        case .warning:     return "🟡"
        case .critical:    return "🔴"
        case .error:       return "⚠️"
        }
    }
}
