import SwiftUI

/// 全局信号状态，优先级：confirming > critical > warning > running > idle > error
enum SignalState: Int, Comparable {
    case error = 0       // 检测失败
    case idle = 1        // 无会话 / session.idle
    case running = 2     // session.busy
    case warning = 3     // context > 150K
    case critical = 4    // context > 200K
    case confirming = 5  // session.waiting

    // MARK: - Comparable

    static func < (lhs: SignalState, rhs: SignalState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Menu Bar Icon (SF Symbol, template rendering)

    /// 菜单栏图标 SF Symbol 名称
    var sfSymbolName: String {
        switch self {
        case .idle:        return "circle"
        case .running:     return "circle.fill"
        case .confirming:  return "exclamationmark.triangle.fill"
        case .warning:     return "exclamationmark.circle.fill"
        case .critical:    return "xmark.circle.fill"
        case .error:       return "xmark.octagon.fill"
        }
    }

    /// 脉冲动画时的交替图标（仅 confirming 使用）
    var pulseAlternateSymbol: String? {
        switch self {
        case .confirming:  return "exclamationmark.triangle"
        default:           return nil
        }
    }

    // MARK: - Color (for popover use, not menu bar icon)

    /// 状态颜色
    var color: Color {
        switch self {
        case .idle:        return .gray.opacity(0.5)
        case .running:     return .green
        case .confirming:  return .red
        case .warning:     return .yellow
        case .critical:    return .red
        case .error:       return .gray
        }
    }

    /// NSColor 版本（菜单栏图标用）
    var nsColor: NSColor {
        switch self {
        case .idle:        return NSColor(calibratedRed: 0.92, green: 0.89, blue: 0.85, alpha: 0.63)
        case .running:     return NSColor.systemGreen
        case .confirming:  return NSColor.systemRed
        case .warning:     return NSColor.systemYellow
        case .critical:    return NSColor.systemPurple
        case .error:       return NSColor(calibratedRed: 0.92, green: 0.89, blue: 0.85, alpha: 0.63)
        }
    }

    // MARK: - Description

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

    /// Emoji（仅 popover 内使用）
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
