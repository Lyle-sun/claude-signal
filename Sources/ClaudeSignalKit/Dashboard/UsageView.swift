import SwiftUI

/// 用量分析视图 — token 用量 + 成本统计
@MainActor
struct UsageView: View {
    let store: UsageStore

    @State private var dailyUsage: [UsageStore.DailyUsage] = []
    @State private var projectUsage: [UsageStore.ProjectUsage] = []
    @State private var modelUsage: [UsageStore.ModelUsage] = []
    @State private var recentSessions: [UsageStore.RecentSessionUsage] = []
    @State private var summary: UsageStore.UsageSummary?
    @State private var selectedRange: UsageStore.DateRange = .last30Days
    @State private var selectedSection: UsageSection = .overview
    @State private var selectedTrendDate: String?
    @AppStorage("dashboardLanguage") private var dashboardLanguageRawValue = DashboardLanguage.chinese.rawValue

    private var language: DashboardLanguage {
        DashboardText.appLanguage(from: dashboardLanguageRawValue)
    }

    private enum UsageSection: CaseIterable {
        case overview
        case models
        case projects
        case trends
        case sessions

        func title(language: DashboardLanguage) -> String {
            switch (self, language) {
            case (.overview, .chinese): return "概览"
            case (.overview, .english): return "Overview"
            case (.models, .chinese): return "模型"
            case (.models, .english): return "Models"
            case (.projects, .chinese): return "项目"
            case (.projects, .english): return "Projects"
            case (.trends, .chinese): return "趋势"
            case (.trends, .english): return "Trends"
            case (.sessions, .chinese): return "会话"
            case (.sessions, .english): return "Sessions"
            }
        }
    }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    headerBar

                    if let s = summary {
                        rangeSummary(s)
                    }

                    if let s = summary, s.unknownModelRatio > 0 {
                        unknownModelWarning(ratio: s.unknownModelRatio)
                    }

                    sectionPicker

                    sectionContent

                    if summary == nil && dailyUsage.isEmpty && modelUsage.isEmpty && projectUsage.isEmpty {
                        emptyState
                    }
                }
                .frame(
                    maxWidth: .infinity,
                    minHeight: max(proxy.size.height - 40, 0),
                    alignment: .topLeading
                )
                .padding(20)
            }
        }
        .background(Color(NSColor.windowBackgroundColor))
        .onAppear { loadData() }
        .onChange(of: selectedRange) { _ in loadData() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            loadData()
        }
    }

    private var headerBar: some View {
        HStack(alignment: .top, spacing: 18) {
            headerTitle
            Spacer(minLength: 12)
            rangePicker
        }
    }

    private var headerTitle: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(language == .chinese ? "用量分析" : "Usage Analytics")
                .font(.title3)
                .fontWeight(.semibold)
            Text(language == .chinese ? "范围内的 Token、成本、模型和项目消耗" : "Tokens, cost, models, and project consumption in the selected range")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var rangePicker: some View {
        HStack(spacing: 8) {
            Text(language == .chinese ? "范围" : "Range")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .trailing)
            Picker("范围", selection: $selectedRange) {
                ForEach(UsageStore.DateRange.allCases, id: \.rawValue) { range in
                    Text(DashboardText.dateRange(range, language: language)).tag(range)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 248)
        }
        .fixedSize(horizontal: true, vertical: false)
    }

    private var sectionPicker: some View {
        HStack(spacing: 10) {
            sectionPickerLabel
            sectionPickerControl
        }
        .padding(.vertical, 0)
    }

    private var sectionPickerLabel: some View {
        Text(language == .chinese ? "视图" : "View")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(width: 34, alignment: .trailing)
    }

    private var sectionPickerControl: some View {
        Picker("视图", selection: $selectedSection) {
            ForEach(UsageSection.allCases, id: \.self) { section in
                Text(section.title(language: language)).tag(section)
            }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 244)
    }

    @ViewBuilder
    private var sectionContent: some View {
        switch selectedSection {
        case .overview:
            overviewSection
        case .models:
            if !modelUsage.isEmpty {
                modelUsageTable
            } else {
                emptySection(language == .chinese ? "暂无模型用量" : "No model usage")
            }
        case .projects:
            if !projectUsage.isEmpty {
                projectUsageTable
            } else {
                emptySection(language == .chinese ? "暂无项目用量" : "No project usage")
            }
        case .trends:
            if !dailyUsage.isEmpty {
                trendSection
            } else {
                emptySection(language == .chinese ? "暂无趋势数据" : "No trend data")
            }
        case .sessions:
            if !recentSessions.isEmpty {
                recentSessionTable
            } else {
                emptySection(language == .chinese ? "暂无会话明细" : "No session details")
            }
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !modelUsage.isEmpty || !projectUsage.isEmpty {
                consumptionPreview
            }

            if !dailyUsage.isEmpty {
                overviewTrend
            }
        }
    }

    // MARK: - 范围摘要

    private func rangeSummary(_ s: UsageStore.UsageSummary) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language == .chinese ? "范围摘要" : "Range Summary")
                    .font(.headline)
                Spacer()
                Text(DashboardText.dateRange(selectedRange, language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 150), spacing: 10, alignment: .leading)],
                alignment: .leading,
                spacing: 10
            ) {
                statCard(title: language == .chinese ? "总 Token" : "Total Tokens", value: formatTokens(s.totalInputTokens + s.totalOutputTokens + s.totalCacheReadTokens), icon: "sum", color: .teal)
                statCard(title: language == .chinese ? "总费用" : "Total Cost", value: formatCost(s.totalCost), icon: "dollarsign.circle", color: .green)
                statCard(title: language == .chinese ? "消息数" : "Messages", value: "\(s.totalMessages)", icon: "message", color: .indigo)
                statCard(title: language == .chinese ? "会话数" : "Sessions", value: "\(s.totalSessions)", icon: "terminal", color: .purple)
                statCard(title: language == .chinese ? "Token/消息" : "Tokens/Msg", value: formatTokens(s.averageTokensPerMessage), icon: "divide.circle", color: .orange)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    private func statCard(title: String, value: String, icon: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title3)
                .fontWeight(.semibold)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: 7))
    }

    private func inlineStat(_ title: String, _ value: String, color: Color = .secondary) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .foregroundStyle(.secondary)
            Text(value)
                .foregroundStyle(color)
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
        }
        .font(.caption)
    }

    // MARK: - 未知模型警告

    private func unknownModelWarning(ratio: Double) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)
            Text(language == .chinese ? "费用估算可能不准确 — \(Int(ratio * 100))% 的消息使用未知模型" : "Cost estimate may be inaccurate — \(Int(ratio * 100))% of messages use unknown models")
                .font(.subheadline)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.yellow.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - 趋势

    private var overviewTrend: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language == .chinese ? "Token 趋势（按日）" : "Token Trend by Day")
                    .font(.headline)
                Spacer()
                Button {
                    selectedSection = .trends
                } label: {
                    Label(language == .chinese ? "查看趋势" : "View Trends", systemImage: "arrow.right")
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            tokenTrendChart
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var trendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language == .chinese ? "趋势" : "Trends")
                    .font(.headline)
                Spacer()
                Text(language == .chinese ? "\(dailyUsage.first?.date ?? "") - \(dailyUsage.last?.date ?? "") · 按日" : "\(dailyUsage.first?.date ?? "") - \(dailyUsage.last?.date ?? "") · Daily")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            tokenTrendChart

            Text(language == .chinese ? "每日明细" : "Daily Details")
                .font(.subheadline)
                .fontWeight(.semibold)

            HStack {
                Text(language == .chinese ? "日期" : "Date")
                    .frame(width: 90, alignment: .leading)
                Spacer()
                Text("Token")
                    .frame(width: 60, alignment: .trailing)
                Text(language == .chinese ? "消息" : "Msgs")
                    .frame(width: 40, alignment: .trailing)
                Text(language == .chinese ? "费用" : "Cost")
                    .frame(width: 70, alignment: .trailing)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            Divider()

            ForEach(dailyUsage.reversed(), id: \.date) { day in
                HStack {
                    Text(day.date)
                        .frame(width: 90, alignment: .leading)
                    Spacer()
                    Text(formatTokens(day.totalTokens))
                        .monospacedDigit()
                        .frame(width: 60, alignment: .trailing)
                    Text("\(day.messageCount)")
                        .frame(width: 40, alignment: .trailing)
                    Text(formatCost(day.cost.totalCost))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .trailing)
                }
                .font(.subheadline)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var tokenTrendChart: some View {
        let maxTokens = max(dailyUsage.map(\.totalTokens).max() ?? 0, 1)

        return VStack(spacing: 6) {
            if let selected = selectedTrendUsage {
                selectedTrendSummary(selected)
            }

            ZStack {
                Canvas { context, size in
                    guard !dailyUsage.isEmpty else { return }

                    let points = trendPoints(in: size, maxTokens: maxTokens)
                    let selectedIndex = dailyUsage.firstIndex { $0.date == (selectedTrendDate ?? dailyUsage.last?.date) }

                    var area = Path()
                    if let first = points.first {
                        area.move(to: CGPoint(x: first.x, y: size.height))
                        for point in points {
                            area.addLine(to: point)
                        }
                        if let last = points.last {
                            area.addLine(to: CGPoint(x: last.x, y: size.height))
                        }
                        area.closeSubpath()
                        context.fill(area, with: .color(Color.teal.opacity(0.16)))
                    }

                    var line = Path()
                    if let first = points.first {
                        line.move(to: first)
                        for point in points.dropFirst() {
                            line.addLine(to: point)
                        }
                        context.stroke(line, with: .color(Color.teal), lineWidth: 2)
                    }

                    if let selectedIndex, points.indices.contains(selectedIndex) {
                        let selectedPoint = points[selectedIndex]
                        var guide = Path()
                        guide.move(to: CGPoint(x: selectedPoint.x, y: 0))
                        guide.addLine(to: CGPoint(x: selectedPoint.x, y: size.height))
                        context.stroke(guide, with: .color(Color.secondary.opacity(0.28)), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    }

                    for (index, point) in points.enumerated() {
                        let isSelected = index == selectedIndex
                        let size: CGFloat = isSelected ? 9 : 5
                        let marker = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
                        context.fill(Path(ellipseIn: marker), with: .color(Color.teal))
                        if isSelected {
                            context.stroke(Path(ellipseIn: marker.insetBy(dx: -2, dy: -2)), with: .color(Color.teal.opacity(0.35)), lineWidth: 2)
                        }
                    }
                }
                .frame(height: 128)

                HStack(spacing: 0) {
                    ForEach(dailyUsage, id: \.date) { day in
                        Rectangle()
                            .fill(Color.clear)
                            .contentShape(Rectangle())
                            .help("\(day.date): \(formatTokens(day.totalTokens))")
                            .onTapGesture {
                                selectedTrendDate = day.date
                            }
                            .frame(maxWidth: .infinity)
                    }
                }
            }

            trendDateAxis
        }
        .padding(.vertical, 4)
    }

    private var selectedTrendUsage: UsageStore.DailyUsage? {
        if let selectedTrendDate,
           let selected = dailyUsage.first(where: { $0.date == selectedTrendDate }) {
            return selected
        }
        return dailyUsage.last
    }

    private func selectedTrendSummary(_ day: UsageStore.DailyUsage) -> some View {
        HStack(spacing: 12) {
            Text(shortDateLabel(day.date))
                .fontWeight(.semibold)
                .monospacedDigit()
            Divider()
                .frame(height: 12)
            inlineStat("Token", formatTokens(day.totalTokens), color: .teal)
            inlineStat(language == .chinese ? "消息" : "Msgs", "\(day.messageCount)")
            inlineStat(language == .chinese ? "费用" : "Cost", formatCost(day.cost.totalCost), color: .green)
            inlineStat("Input", formatTokens(day.inputTokens))
            inlineStat("Output", formatTokens(day.outputTokens))
            inlineStat("Cache", formatTokens(day.cacheReadTokens))
            Spacer()
        }
        .font(.caption)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    private func trendPoints(in size: CGSize, maxTokens: Int) -> [CGPoint] {
        guard !dailyUsage.isEmpty else { return [] }
        if dailyUsage.count == 1 {
            let y = size.height - (CGFloat(dailyUsage[0].totalTokens) / CGFloat(maxTokens) * size.height)
            return [CGPoint(x: size.width / 2, y: y)]
        }

        return dailyUsage.enumerated().map { index, day in
            let x = CGFloat(index) / CGFloat(dailyUsage.count - 1) * size.width
            let ratio = CGFloat(day.totalTokens) / CGFloat(maxTokens)
            let y = size.height - max(0, min(ratio, 1)) * size.height
            return CGPoint(x: x, y: y)
        }
    }

    private var trendDateAxis: some View {
        HStack(alignment: .top, spacing: 3) {
            ForEach(Array(dailyUsage.enumerated()), id: \.element.date) { index, day in
                Text(shouldShowDateLabel(index: index) ? shortDateLabel(day.date) : "")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity)
            }
        }
        .frame(height: 16)
    }

    // MARK: - 最近会话

    private var recentSessionTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language == .chinese ? "最近会话" : "Recent Sessions")
                    .font(.headline)
                Spacer()
                Text(language == .chinese ? "\(recentSessions.count) 条" : "\(recentSessions.count) rows")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 0) {
                recentSessionHeader
                Divider()
                ForEach(recentSessions, id: \.sessionId) { session in
                    recentSessionRow(session)
                    Divider()
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
    }

    private var recentSessionHeader: some View {
        HStack {
            Text(language == .chinese ? "时间" : "Time")
                .frame(width: 90, alignment: .leading)
            Text(language == .chinese ? "项目" : "Project")
                .frame(minWidth: 80, alignment: .leading)
            Spacer(minLength: 4)
            Text(language == .chinese ? "模型" : "Model")
                .frame(minWidth: 60, alignment: .leading)
            Spacer(minLength: 4)
            Text("Input")
                .frame(width: 72, alignment: .trailing)
            Text("Output")
                .frame(width: 72, alignment: .trailing)
            Text(language == .chinese ? "总 Token" : "Tokens")
                .frame(width: 80, alignment: .trailing)
            Text(language == .chinese ? "费用" : "Cost")
                .frame(width: 72, alignment: .trailing)
            Text(language == .chinese ? "消息" : "Msgs")
                .frame(width: 44, alignment: .trailing)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.vertical, 4)
    }

    private func recentSessionRow(_ session: UsageStore.RecentSessionUsage) -> some View {
        HStack {
            Text(formatRecentSessionTime(session))
                .frame(width: 90, alignment: .leading)
            Text(slugToName(session.projectSlug))
                .lineLimit(1)
                .frame(minWidth: 80, alignment: .leading)
            Spacer(minLength: 4)
            Text(session.model)
                .lineLimit(1)
                .foregroundStyle(.secondary)
                .frame(minWidth: 60, alignment: .leading)
            Spacer(minLength: 4)
            Text(formatTokens(session.inputTokens))
                .frame(width: 72, alignment: .trailing)
            Text(formatTokens(session.outputTokens))
                .frame(width: 72, alignment: .trailing)
            Text(formatTokens(session.totalTokens))
                .fontWeight(.semibold)
                .foregroundStyle(.teal)
                .frame(width: 80, alignment: .trailing)
            Text(formatCost(session.cost.totalCost))
                .frame(width: 72, alignment: .trailing)
            Text("\(session.messageCount)")
                .frame(width: 44, alignment: .trailing)
        }
        .font(.subheadline)
        .monospacedDigit()
        .padding(.vertical, 5)
    }

    // MARK: - 消耗构成

    private var consumptionPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language == .chinese ? "消耗构成" : "Consumption Mix")
                    .font(.headline)
                Spacer()
                HStack(spacing: 12) {
                    Button {
                        selectedSection = .models
                    } label: {
                        Label(language == .chinese ? "模型" : "Models", systemImage: "cpu")
                    }
                    Button {
                        selectedSection = .projects
                    } label: {
                        Label(language == .chinese ? "项目" : "Projects", systemImage: "folder")
                    }
                }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            HStack(alignment: .top, spacing: 12) {
                if !modelUsage.isEmpty {
                    modelPreview
                }
                if !projectUsage.isEmpty {
                    projectPreview
                }
            }
        }
    }

    private var modelPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language == .chinese ? "模型 Top 5" : "Top 5 Models")
                .font(.subheadline)
                .fontWeight(.semibold)

            let total = max(modelUsage.map(\.totalTokens).reduce(0, +), 1)
            ForEach(modelUsage.prefix(5), id: \.model) { model in
                compactUsageRow(
                    title: model.model,
                    value: formatTokens(model.totalTokens),
                    ratio: Double(model.totalTokens) / Double(total),
                    detail: language == .chinese ? "\(model.messageCount) 消息 · \(formatCost(model.cost.totalCost))" : "\(model.messageCount) msgs · \(formatCost(model.cost.totalCost))"
                )
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var projectPreview: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language == .chinese ? "项目 Top 5" : "Top 5 Projects")
                .font(.subheadline)
                .fontWeight(.semibold)

            let total = max(projectUsage.map(\.totalTokens).reduce(0, +), 1)
            ForEach(projectUsage.prefix(5), id: \.projectSlug) { project in
                compactUsageRow(
                    title: slugToName(project.projectSlug),
                    value: formatTokens(project.totalTokens),
                    ratio: Double(project.totalTokens) / Double(total),
                    detail: language == .chinese ? "\(project.sessionCount) 会话 · \(project.messageCount) 消息" : "\(project.sessionCount) sessions · \(project.messageCount) msgs"
                )
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func compactUsageRow(title: String, value: String, ratio: Double, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .lineLimit(1)
                Spacer()
                Text(value)
                    .fontWeight(.semibold)
                    .foregroundStyle(.teal)
                    .monospacedDigit()
            }
            .font(.subheadline)

            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.14))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.teal.opacity(0.72))
                            .frame(width: geo.size.width * min(max(ratio, 0), 1))
                    }
                }
                .frame(height: 6)

                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }

    private var projectUsageTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language == .chinese ? "项目用量" : "Project Usage")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text("Top 10")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            let totalTokens = max(projectUsage.map(\.totalTokens).reduce(0, +), 1)
            ForEach(projectUsage.prefix(10), id: \.projectSlug) { project in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(slugToName(project.projectSlug))
                            .lineLimit(1)
                        Spacer()
                        Text(formatTokens(project.totalTokens))
                            .fontWeight(.semibold)
                            .foregroundStyle(.teal)
                            .monospacedDigit()
                    }

                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.gray.opacity(0.14))
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.teal.opacity(0.72))
                                    .frame(width: geo.size.width * (Double(project.totalTokens) / Double(totalTokens)))
                            }
                        }
                        .frame(height: 6)

                        Text(language == .chinese ? "\(project.sessionCount) 会话" : "\(project.sessionCount) sessions")
                            .foregroundStyle(.secondary)
                        Text(language == .chinese ? "\(project.messageCount) 消息" : "\(project.messageCount) msgs")
                            .foregroundStyle(.secondary)
                        Text(formatCost(project.cost.totalCost))
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                    .font(.caption)
                }
                .padding(.vertical, 3)
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    // MARK: - 模型用量

    private var modelUsageTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(language == .chinese ? "模型用量" : "Model Usage")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                Text(language == .chinese ? "按 \(DashboardText.dateRange(selectedRange, language: language))" : DashboardText.dateRange(selectedRange, language: language))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            VStack(spacing: 8) {
                ForEach(modelUsage, id: \.model) { model in
                    modelUsageRow(model)
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private func modelUsageRow(_ model: UsageStore.ModelUsage) -> some View {
        let total = max(modelUsage.map(\.totalTokens).reduce(0, +), 1)
        let ratio = Double(model.totalTokens) / Double(total)

        return VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                HStack(spacing: 7) {
                    Circle()
                        .fill(model.isKnown ? Color.green : Color.orange)
                        .frame(width: 7, height: 7)
                    Text(model.model)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                    if !model.isKnown {
                        Text(language == .chinese ? "未知定价" : "Unknown Price")
                            .font(.caption2)
                            .foregroundStyle(.orange)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.orange.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 5))
                    }
                }

                Spacer()

                Text(formatTokens(model.totalTokens))
                    .font(.headline)
                    .foregroundStyle(.teal)
                    .monospacedDigit()
            }

            HStack(spacing: 10) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.gray.opacity(0.16))
                        RoundedRectangle(cornerRadius: 2)
                            .fill(Color.teal.opacity(0.76))
                            .frame(width: geo.size.width * min(max(ratio, 0), 1))
                    }
                }
                .frame(height: 7)

                Text("\(Int((ratio * 100).rounded()))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 38, alignment: .trailing)
            }

            HStack(spacing: 16) {
                inlineStat("Input", formatTokens(model.inputTokens))
                inlineStat("Output", formatTokens(model.outputTokens))
                inlineStat("Cache", formatTokens(model.cacheReadTokens))
                inlineStat(language == .chinese ? "费用" : "Cost", formatCost(model.cost.totalCost), color: .green)
                inlineStat(language == .chinese ? "消息" : "Msgs", "\(model.messageCount)")
                Spacer()
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color.black.opacity(0.05), lineWidth: 1)
        }
    }

    // MARK: - 空状态

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text(language == .chinese ? "暂无用量数据" : "No Usage Data")
                .font(.title2)
                .fontWeight(.semibold)
            Text(language == .chinese ? "索引器处理完 Claude Code 会话后，用量数据将在此显示。" : "Usage appears here after the indexer processes Claude Code sessions.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func emptySection(_ text: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 30))
                .foregroundStyle(.secondary)
            Text(text)
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(40)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    // MARK: - Helpers

    private func loadData() {
        dailyUsage = store.fetchDailyUsage(range: selectedRange)
        projectUsage = store.fetchProjectUsage(range: selectedRange)
        modelUsage = store.fetchModelUsage(range: selectedRange)
        recentSessions = store.fetchRecentSessionUsage(range: selectedRange, limit: 30)
        summary = store.fetchSummary(range: selectedRange)

        if let selectedTrendDate,
           dailyUsage.contains(where: { $0.date == selectedTrendDate }) {
            return
        }
        selectedTrendDate = dailyUsage.last?.date
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 1 {
            return String(format: "$%.2f", cost)
        } else if cost >= 0.01 {
            return String(format: "$%.4f", cost)
        } else {
            return String(format: "$%.6f", cost)
        }
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1000)
        } else {
            return "\(tokens)"
        }
    }

    private func slugToName(_ slug: String) -> String {
        let parts = slug.split(separator: "-").map(String.init)
        let nonEmpty = parts.filter { !$0.isEmpty }
        return nonEmpty.last ?? slug
    }

    private func shouldShowDateLabel(index: Int) -> Bool {
        let count = dailyUsage.count
        guard count > 0 else { return false }
        if index == 0 || index == count - 1 { return true }
        if count <= 7 { return true }
        if count <= 31 { return index % 5 == 0 }
        return index % 15 == 0
    }

    private func shortDateLabel(_ date: String) -> String {
        let parts = date.split(separator: "-")
        guard parts.count == 3 else { return date }
        return "\(parts[1])-\(parts[2])"
    }

    private func percentile90(_ values: [Int]) -> Int {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.9)) - 1)
        return sorted[index]
    }

    private func formatRecentSessionTime(_ session: UsageStore.RecentSessionUsage) -> String {
        if let startTime = session.startTime {
            let formatter = DateFormatter()
            formatter.dateFormat = "MM-dd HH:mm"
            formatter.timeZone = TimeZone.current
            return formatter.string(from: Date(timeIntervalSince1970: Double(startTime)))
        }
        return session.date
    }
}

/// 今日独立视图 — 当日消耗 + 近 90 日参考
@MainActor
struct TodayUsageView: View {
    let store: UsageStore

    @State private var todayUsage: UsageStore.DailyUsage?
    @State private var p90DailyUsage: [UsageStore.DailyUsage] = []
    @State private var recentTodaySessions: [UsageStore.RecentSessionUsage] = []
    @AppStorage("dashboardLanguage") private var dashboardLanguageRawValue = DashboardLanguage.chinese.rawValue

    private var language: DashboardLanguage {
        DashboardText.appLanguage(from: dashboardLanguageRawValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header

                if let todayUsage {
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: 128), spacing: 10, alignment: .leading)],
                        alignment: .leading,
                        spacing: 10
                    ) {
                        compactStat(language == .chinese ? "总 Token" : "Total Tokens", formatTokens(todayUsage.totalTokens), icon: "sum", tint: .teal)
                        compactStat("Input", formatTokens(todayUsage.inputTokens), icon: "arrow.down.circle", tint: .blue)
                        compactStat("Output", formatTokens(todayUsage.outputTokens), icon: "arrow.up.circle", tint: .orange)
                        compactStat("Cache", formatTokens(todayUsage.cacheReadTokens), icon: "bolt.horizontal.circle", tint: .purple)
                        compactStat(language == .chinese ? "消息" : "Messages", "\(todayUsage.messageCount)", icon: "message", tint: .indigo)
                        compactStat(language == .chinese ? "成本" : "Cost", formatCost(todayUsage.cost.totalCost), icon: "dollarsign.circle", tint: .green)
                    }

                    p90Reference(todayUsage)

                    if !recentTodaySessions.isEmpty {
                        todaySessionTable
                    }
                } else {
                    emptyState
                }
            }
            .padding(20)
        }
        .onAppear { loadData() }
        .onReceive(Timer.publish(every: 30, on: .main, in: .common).autoconnect()) { _ in
            loadData()
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(language == .chinese ? "今日" : "Today")
                    .font(.title3)
                    .fontWeight(.semibold)
                Text(language == .chinese ? "当日消耗独立视图，不受用量页范围筛选影响" : "A dedicated daily view, independent of the usage range filter")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(todayDateString)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
    }

    private func compactStat(_ title: String, _ value: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 9) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(tint)
                .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.68))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.16), lineWidth: 1)
        }
    }

    private func p90Reference(_ todayUsage: UsageStore.DailyUsage) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(language == .chinese ? "近 90 日参考" : "Last 90 Days Reference")
                    .font(.headline)
                Spacer()
                Text("P90")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            p90Row(title: "Token", value: todayUsage.totalTokens, baseline: percentile90(p90DailyUsage.map(\.totalTokens)), valueText: formatTokens(todayUsage.totalTokens))
            p90Row(title: language == .chinese ? "消息" : "Messages", value: todayUsage.messageCount, baseline: percentile90(p90DailyUsage.map(\.messageCount)), valueText: language == .chinese ? "\(todayUsage.messageCount) 条" : "\(todayUsage.messageCount)")
            p90Row(
                title: language == .chinese ? "成本" : "Cost",
                value: Int((todayUsage.cost.totalCost * 1_000_000).rounded()),
                baseline: percentile90(p90DailyUsage.map { Int(($0.cost.totalCost * 1_000_000).rounded()) }),
                valueText: formatCost(todayUsage.cost.totalCost)
            )
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func p90Row(title: String, value: Int, baseline: Int, valueText: String) -> some View {
        let ratio = baseline > 0 ? min(Double(value) / Double(baseline), 1.0) : 0

        return HStack(spacing: 12) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 52, alignment: .leading)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.14))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(ratio > 0.9 ? Color.orange : Color.teal)
                        .frame(width: geo.size.width * ratio)
                }
            }
            .frame(height: 8)

            Text("\(Int((ratio * 100).rounded()))%")
                .font(.caption)
                .foregroundStyle(ratio > 0.9 ? .orange : .secondary)
                .monospacedDigit()
                .frame(width: 38, alignment: .trailing)

            Text("\(valueText) / \(baselineText(title: title, baseline: baseline))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 130, alignment: .leading)
        }
    }

    private var todaySessionTable: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(language == .chinese ? "今日会话" : "Today's Sessions")
                .font(.headline)

            ForEach(recentTodaySessions, id: \.sessionId) { session in
                HStack {
                    Text(slugToName(session.projectSlug))
                        .lineLimit(1)
                    Spacer()
                    Text(formatTokens(session.totalTokens))
                        .fontWeight(.semibold)
                        .foregroundStyle(.teal)
                    Text(language == .chinese ? "\(session.messageCount) 条" : "\(session.messageCount) msgs")
                        .foregroundStyle(.secondary)
                }
                .font(.subheadline)
                .monospacedDigit()
                Divider()
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 44))
                .foregroundStyle(.secondary)
            Text(language == .chinese ? "今天暂无用量数据" : "No Usage Today")
                .font(.title3)
                .fontWeight(.semibold)
            Text(language == .chinese ? "Claude Code 产生新会话后，今日统计会显示在这里。" : "Today's stats appear here after Claude Code creates new sessions.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(48)
    }

    private func loadData() {
        todayUsage = store.fetchDailyUsage(range: .today).first
        p90DailyUsage = store.fetchDailyUsage(range: .last90Days)
        recentTodaySessions = store.fetchRecentSessionUsage(range: .today, limit: 12)
    }

    private var todayDateString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone.current
        return formatter.string(from: Date())
    }

    private func baselineText(title: String, baseline: Int) -> String {
        if title == "成本" || title == "Cost" {
            return formatCost(Double(baseline) / 1_000_000)
        }
        if title == "消息" || title == "Messages" {
            return language == .chinese ? "\(baseline) 条" : "\(baseline)"
        }
        return formatTokens(baseline)
    }

    private func percentile90(_ values: [Int]) -> Int {
        let sorted = values.filter { $0 > 0 }.sorted()
        guard !sorted.isEmpty else { return 0 }
        let index = min(sorted.count - 1, Int(ceil(Double(sorted.count) * 0.9)) - 1)
        return sorted[index]
    }

    private func formatCost(_ cost: Double) -> String {
        if cost >= 1 {
            return String(format: "$%.2f", cost)
        } else if cost >= 0.01 {
            return String(format: "$%.4f", cost)
        }
        return String(format: "$%.6f", cost)
    }

    private func formatTokens(_ tokens: Int) -> String {
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1000)
        }
        return "\(tokens)"
    }

    private func slugToName(_ slug: String) -> String {
        let parts = slug.split(separator: "-").map(String.init)
        let nonEmpty = parts.filter { !$0.isEmpty }
        return nonEmpty.last ?? slug
    }
}
