import SwiftUI

struct PopoverView: View {
    let sessions: [SessionInfo]
    let globalState: SignalState
    let isMuted: Bool
    let onJump: (Int) -> Void
    let onToggleMute: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Header
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 10)

            Divider()

            // Content
            if sessions.isEmpty {
                emptyState
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(sessions) { session in
                            SessionCard(session: session) {
                                onJump(session.pid)
                            }
                        }
                    }
                    .padding(12)
                }
            }

            Divider()

            // Footer
            footer
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            // 状态指示灯
            Circle()
                .fill(globalState.color)
                .frame(width: 10, height: 10)
                .overlay(
                    Circle()
                        .strokeBorder(Color.primary.opacity(0.1), lineWidth: 0.5)
                )

            Text("Claude Signal")
                .font(.system(size: 13, weight: .semibold))

            Spacer()

            Text(globalState.description)
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "circle.dashed")
                .font(.system(size: 24))
                .foregroundColor(.secondary)
                .padding(.bottom, 4)

            Text("无 Claude Code 会话")
                .font(.system(size: 13, weight: .medium))

            Text("启动 Claude Code 后自动检测")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 24)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                onToggleMute()
            } label: {
                Label(
                    isMuted ? "已静音" : "声音",
                    systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill"
                )
                .font(.system(size: 11))
            }
            .buttonStyle(.plain)
            .foregroundColor(isMuted ? .secondary : .primary)

            Spacer()

            Button("退出") {
                onQuit()
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundColor(.secondary)
        }
    }
}

// MARK: - Session Card

struct SessionCard: View {
    let session: SessionInfo
    let onJump: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // 项目名 + 状态
            HStack(spacing: 6) {
                Circle()
                    .fill(session.signalState.color)
                    .frame(width: 8, height: 8)

                Text(session.projectName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)

                Spacer()

                if session.signalState == .confirming {
                    Text("待确认")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .clipShape(Capsule())
                }
            }

            // Context 进度条
            contextBar

            // 等待信息
            if let waiting = session.waitingFor {
                HStack(spacing: 4) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.orange)
                    Text(waiting)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            // 操作按钮
            HStack {
                Spacer()
                Button {
                    onJump()
                } label: {
                    Label("跳转到终端", systemImage: "terminal.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
                .foregroundColor(.accentColor)
            }
        }
        .padding(10)
        .background(Color(nsColor: .controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5)
        )
    }

    // MARK: - Context Progress Bar

    private var contextBar: some View {
        VStack(alignment: .leading, spacing: 3) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    // 背景轨道
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.primary.opacity(0.08))

                    // 进度填充
                    RoundedRectangle(cornerRadius: 2)
                        .fill(progressColor)
                        .frame(width: max(2, geo.size.width * min(session.contextPercent, 1.0)))
                }
            }
            .frame(height: 4)

            HStack {
                Text("Context")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)

                Spacer()

                Text(session.contextDescription)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(contextPercentColor)
            }
        }
    }

    private var progressColor: Color {
        let pct = session.contextPercent
        if pct > 1.0 { return .red }
        if pct > 0.75 { return .yellow }
        return .green.opacity(0.8)
    }

    private var contextPercentColor: Color {
        let pct = session.contextPercent
        if pct > 1.0 { return .red }
        if pct > 0.75 { return .orange }
        return .secondary
    }
}
