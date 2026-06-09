import AppKit

/// 全局信号状态，优先级：confirming > critical > warning > running > idle > error
/// rawValue 顺序即优先级顺序，不可随意调整
public enum SignalState: Int, Comparable {
    case error = 0       // 检测失败
    case idle = 1        // 无会话 / session.idle
    case running = 2     // session.busy
    case warning = 3     // context > warning threshold
    case critical = 4    // context > context window limit
    case confirming = 5  // session.waiting

    // MARK: - Comparable

    public static func < (lhs: SignalState, rhs: SignalState) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    // MARK: - Menu Bar Icon (SF Symbol, template rendering)

    /// 菜单栏图标 SF Symbol 名称
    public var sfSymbolName: String {
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
    public var pulseAlternateSymbol: String? {
        switch self {
        case .confirming:  return "exclamationmark.triangle"
        default:           return nil
        }
    }

    // MARK: - NSColor (AppKit + SwiftUI 共用)

    /// NSColor 版本（菜单栏图标 + SwiftUI 均可使用）
    public var nsColor: NSColor {
        switch self {
        case .idle:        return NSColor(calibratedRed: 0.92, green: 0.89, blue: 0.85, alpha: 0.63)
        case .running:     return NSColor.systemGreen
        case .confirming:  return NSColor.systemRed
        case .warning:     return NSColor.systemYellow
        case .critical:    return NSColor.systemPurple
        case .error:       return NSColor.systemOrange
        }
    }

    // MARK: - Description

    /// 人类可读描述
    public var description: String {
        switch self {
        case .idle:        return "空闲"
        case .running:     return "运行中"
        case .confirming:  return "等待确认"
        case .warning:     return "Context 接近上限"
        case .critical:    return "Context 已超限"
        case .error:       return "检测异常"
        }
    }

    /// 是否需要用户操作
    public var needsAction: Bool {
        self == .confirming || self == .critical
    }

    /// Emoji（仅 popover/dashboard 内使用）
    public var emoji: String {
        switch self {
        case .idle:        return "⚪"
        case .running:     return "🟢"
        case .confirming:  return "🔴"
        case .warning:     return "🟡"
        case .critical:    return "🟣"
        case .error:       return "⚠️"
        }
    }
}
