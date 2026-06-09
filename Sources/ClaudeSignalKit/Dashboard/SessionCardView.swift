import SwiftUI

/// 会话卡片视图 — 视觉层级：主信息 / 当前轮用量 / context 进度
struct SessionCardView: View {
    let session: SessionInfo
    let terminalActivator: TerminalActivating
    @State private var isHoveringTerminalButton = false
    @AppStorage("dashboardLanguage") private var dashboardLanguageRawValue = DashboardLanguage.chinese.rawValue

    private var language: DashboardLanguage {
        DashboardText.appLanguage(from: dashboardLanguageRawValue)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 2)
                .fill(Color(session.signalState.nsColor))
                .frame(width: 4)
                .opacity(session.signalState.needsAction ? 1 : 0.45)
                .padding(.vertical, 2)

            VStack(alignment: .leading, spacing: 7) {
                headerRow
                detailRow
                metricsRow
                contextProgressRow
            }
        }
        .padding(10)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .stroke(cardBorderColor, lineWidth: session.signalState.needsAction ? 1.2 : 1)
        }
    }

    // MARK: - Rows

    private var headerRow: some View {
        HStack(spacing: 8) {
            Text(session.projectName)
                .font(.system(.body, weight: .semibold))
                .lineLimit(1)

            modelBadge

            Spacer(minLength: 8)

            terminalButton
            statusBadge
        }
    }

    private var detailRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "folder")
                .font(.caption2)
                .foregroundStyle(.tertiary)

            Text(session.cwd)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if let waiting = session.waitingFor {
                Divider()
                    .frame(height: 10)

                Label(waiting, systemImage: "exclamationmark.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .lineLimit(1)
            }
        }
    }

    private var metricsRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 14) {
                metricItem(icon: "gauge.with.dots.needle.67percent", label: "Context", value: session.contextPercentDescription)
                metricItem(icon: "arrow.down.circle", label: "Input", value: formatTokens(session.lastInputTokens))
                metricItem(icon: "arrow.up.circle", label: "Output", value: formatTokens(session.lastOutputTokens))
                metricItem(icon: "bolt.horizontal.circle", label: "Cached", value: formatTokens(session.lastCacheReadTokens))
                metricItem(icon: "clock", label: language == .chinese ? "时长" : "Duration", value: durationText)
            }

            LazyVGrid(
                columns: [GridItem(.adaptive(minimum: 112), spacing: 10, alignment: .leading)],
                alignment: .leading,
                spacing: 5
            ) {
                metricItem(icon: "gauge.with.dots.needle.67percent", label: "Context", value: session.contextPercentDescription)
                metricItem(icon: "arrow.down.circle", label: "Input", value: formatTokens(session.lastInputTokens))
                metricItem(icon: "arrow.up.circle", label: "Output", value: formatTokens(session.lastOutputTokens))
                metricItem(icon: "bolt.horizontal.circle", label: "Cached", value: formatTokens(session.lastCacheReadTokens))
                metricItem(icon: "clock", label: language == .chinese ? "时长" : "Duration", value: durationText)
            }
        }
    }

    private var contextProgressRow: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.gray.opacity(0.16))
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: geo.size.width * min(session.contextPercent, 1.0))
                }
            }
            .frame(height: 4)

            Text(session.contextDescription)
                .font(.caption2)
                .foregroundStyle(contextValueColor)
                .monospacedDigit()
        }
    }

    private var modelBadge: some View {
        Label(session.modelName ?? (language == .chinese ? "未知模型" : "Unknown Model"), systemImage: "cpu")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.75))
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }

    private var terminalButton: some View {
        Button {
            terminalActivator.activateTerminal(forPID: session.pid)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "terminal")
                    .font(.system(size: 11, weight: .medium))
                Text(language == .chinese ? "会话定位" : "Locate")
                    .font(.caption2)
            }
            .foregroundStyle(isHoveringTerminalButton ? .primary : Color.accentColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(NSColor.controlAccentColor).opacity(isHoveringTerminalButton ? 0.16 : 0.09))
            )
            .overlay {
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.accentColor.opacity(isHoveringTerminalButton ? 0.38 : 0.24), lineWidth: 1)
            }
        }
        .buttonStyle(.plain)
        .help(language == .chinese ? "定位此会话所在的终端" : "Locate this session's terminal")
        .onHover { isHoveringTerminalButton = $0 }
    }

    // MARK: - Status Badge

    @ViewBuilder
    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(Color(session.signalState.nsColor))
                .frame(width: 8, height: 8)

            Text(DashboardText.signalState(session.signalState, language: language))
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Colors

    private var cardBackground: Color {
        if session.signalState.needsAction {
            return Color(session.signalState.nsColor).opacity(0.055)
        }
        return Color(NSColor.controlBackgroundColor).opacity(0.55)
    }

    private var cardBorderColor: Color {
        if session.signalState.needsAction {
            return Color(session.signalState.nsColor).opacity(0.45)
        }
        return Color.gray.opacity(0.18)
    }

    private func metricItem(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(width: 12)
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Text(value)
                .fontWeight(.medium)
                .foregroundStyle(.primary)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .font(.caption2)
    }

    private func formatTokens(_ tokens: Int?) -> String {
        guard let tokens else { return "-" }
        if tokens >= 1_000_000 {
            return String(format: "%.1fM", Double(tokens) / 1_000_000)
        } else if tokens >= 1000 {
            return String(format: "%.1fK", Double(tokens) / 1000)
        } else {
            return "\(tokens)"
        }
    }

    private var durationText: String {
        if session.startedAt == nil {
            return language == .chinese ? "未知" : "Unknown"
        }
        return session.durationDescription
    }

    private var progressColor: Color {
        if session.contextPercent > 1.0 { return .red }
        if session.contextPercent > 0.75 { return .yellow }
        return .green
    }

    private var contextValueColor: Color {
        if session.contextPercent > 1.0 { return .red }
        if session.contextPercent > 0.75 { return .orange }
        return .secondary
    }
}
