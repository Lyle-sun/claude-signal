import Foundation

enum DashboardLanguage: String, CaseIterable, Identifiable {
    case chinese = "zh-Hans"
    case english = "en"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .chinese: return "中文"
        case .english: return "English"
        }
    }
}

enum DashboardText {
    static func appLanguage(from rawValue: String) -> DashboardLanguage {
        DashboardLanguage(rawValue: rawValue) ?? .chinese
    }

    static func dateRange(_ range: UsageStore.DateRange, language: DashboardLanguage) -> String {
        switch (range, language) {
        case (.today, .chinese): return "今日"
        case (.today, .english): return "Today"
        case (.last7Days, .chinese): return "近 7 天"
        case (.last7Days, .english): return "Last 7 Days"
        case (.last30Days, .chinese): return "近 30 天"
        case (.last30Days, .english): return "Last 30 Days"
        case (.last90Days, .chinese): return "近 90 天"
        case (.last90Days, .english): return "Last 90 Days"
        }
    }

    static func signalState(_ state: SignalState, language: DashboardLanguage) -> String {
        if language == .chinese {
            return state.description
        }

        switch state {
        case .idle: return "Idle"
        case .running: return "Running"
        case .confirming: return "Needs Confirmation"
        case .warning: return "Warning"
        case .critical: return "Context Exceeded"
        case .error: return "Error"
        }
    }
}
