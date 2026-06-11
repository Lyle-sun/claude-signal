import SwiftUI

/// 仪表盘主视图 — 自定义侧边栏 + 内容区（兼容 macOS 12）
@MainActor
struct DashboardView: View {
    @ObservedObject var aggregator: SignalAggregator
    let usageStore: UsageStore?

    @State private var selectedTab: Tab = .sessions
    @AppStorage("dashboardLanguage") private var dashboardLanguageRawValue = DashboardLanguage.chinese.rawValue

    private var language: DashboardLanguage {
        DashboardText.appLanguage(from: dashboardLanguageRawValue)
    }

    enum Tab: CaseIterable, Identifiable {
        case sessions
        case today
        case usage
        case settings

        var id: Self { self }

        var icon: String {
            switch self {
            case .sessions: return "terminal"
            case .today: return "calendar"
            case .usage: return "chart.bar"
            case .settings: return "gearshape"
            }
        }

        func title(language: DashboardLanguage) -> String {
            switch (self, language) {
            case (.sessions, .chinese): return "会话"
            case (.sessions, .english): return "Sessions"
            case (.today, .chinese): return "今日"
            case (.today, .english): return "Today"
            case (.usage, .chinese): return "用量"
            case (.usage, .english): return "Usage"
            case (.settings, .chinese): return "设置"
            case (.settings, .english): return "Settings"
            }
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 160)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 600, minHeight: 400)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Label(tab.title(language: language), systemImage: tab.icon)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(selectedTab == tab ? Color.accentColor : Color.clear)
                        .foregroundColor(selectedTab == tab ? .white : .primary)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
        .padding(10)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.7))
    }

    @ViewBuilder
    private var detailView: some View {
        switch selectedTab {
        case .sessions:
            sessionsView
        case .today:
            if let usageStore {
                TodayUsageView(store: usageStore)
            } else {
                usageUnavailableView
            }
        case .usage:
            if let usageStore {
                UsageView(store: usageStore)
            } else {
                usageUnavailableView
            }
        case .settings:
            SettingsView()
        }
    }

    private var usageUnavailableView: some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 32))
                .foregroundStyle(.yellow)
            Text(language == .chinese ? "用量数据不可用（usageStore 为 nil）" : "Usage data is unavailable.")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 会话视图

    private var sessionsView: some View {
        Group {
            if aggregator.sessions.isEmpty {
                emptyState
            } else {
                sessionList
            }
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text(language == .chinese ? "无活跃会话" : "No Active Sessions")
                .font(.title2)
                .fontWeight(.semibold)

            Text(language == .chinese ? "启动 Claude Code 后，会话将在此显示。" : "Sessions will appear here after Claude Code starts.")
                .foregroundStyle(.secondary)

            Text(language == .chinese ? "在终端中运行 Claude Code 开始监控。" : "Run Claude Code in a terminal to start monitoring.")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - 会话列表

    private var sessionList: some View {
        VStack(spacing: 0) {
            // 标题栏摘要
            headerBar

            Divider()

            // 会话列表
            List(aggregator.sessions.sorted(by: sessionSortOrder)) { session in
                SessionCardView(session: session)
                    .listRowInsets(EdgeInsets(top: 5, leading: 12, bottom: 5, trailing: 12))
                    .listRowBackground(Color.clear)
            }
            .listStyle(.sidebar)

            // 底部状态栏
            statusBar
        }
    }

    // MARK: - 标题栏

    private var headerBar: some View {
        HStack {
            Circle()
                .fill(Color(aggregator.globalState.nsColor))
                .frame(width: 10, height: 10)

            Text("Claude Signal")
                .font(.headline)

            Spacer()

            Text(DashboardText.signalState(aggregator.globalState, language: language))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - 状态栏

    private var statusBar: some View {
        HStack {
            let confirming = aggregator.sessions.filter { $0.signalState == .confirming }.count
            let running = aggregator.sessions.filter { $0.signalState == .running }.count

            if confirming > 0 {
                Label(language == .chinese ? "\(confirming) 个等待确认" : "\(confirming) waiting for confirmation", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if running > 0 {
                Label(language == .chinese ? "\(running) 个运行中" : "\(running) running", systemImage: "circle.fill")
                    .foregroundStyle(.green)
            }

            let idle = aggregator.sessions.filter { $0.signalState == .idle }.count
            if idle > 0 && confirming == 0 {
                Text(language == .chinese ? "\(aggregator.sessions.count) 个会话空闲 — 无需关注" : "\(aggregator.sessions.count) sessions idle")
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 16)
        .padding(.vertical, 6)
        .background(.bar)
    }

    // MARK: - 排序

    private func sessionSortOrder(_ a: SessionInfo, _ b: SessionInfo) -> Bool {
        if a.signalState != b.signalState {
            return a.signalState > b.signalState
        }
        // 二级排序：最近活动优先（用 contextTokens 近似）
        return a.contextTokens > b.contextTokens
    }
}
