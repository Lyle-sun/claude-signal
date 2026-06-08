import SwiftUI

/// 菜单栏下拉菜单内容（Phase 1）
struct MenuBarView: View {
    @ObservedObject var aggregator: SignalAggregator
    let soundPlayer: SoundPlayer
    let terminalActivator: TerminalActivator

    var body: some View {
        if aggregator.sessions.isEmpty {
            emptyState
        } else {
            sessionsList
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        Group {
            if !aggregator.claudeCodeInstalled {
                Text("Claude Code 未检测到")
                    .font(.headline)
                Text("请先安装 Claude Code CLI")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("无 Claude Code 会话")
                    .font(.headline)
                Text("启动 Claude Code 后自动检测")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Divider()
            toggleMuteButton
            quitButton
        }
    }

    // MARK: - Sessions List

    private var sessionsList: some View {
        Group {
            ForEach(aggregator.sessions) { session in
                sessionRow(session)
            }

            Divider()
            toggleMuteButton
            quitButton
        }
    }

    private func sessionRow(_ session: SessionInfo) -> some View {
        Group {
            HStack {
                Circle()
                    .fill(session.signalState.color)
                    .frame(width: 8, height: 8)

                VStack(alignment: .leading) {
                    Text(session.displayName)
                        .font(.headline)
                    if let waitingFor = session.waitingFor {
                        Text("等待: \(waitingFor)")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Text(session.contextDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button("跳转") {
                    terminalActivator.activateTerminal(forPID: session.pid)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    // MARK: - Common Controls

    private var toggleMuteButton: some View {
        Button {
            soundPlayer.isMuted.toggle()
        } label: {
            if soundPlayer.isMuted {
                Label("取消静音", systemImage: "speaker.slash")
            } else {
                Label("静音", systemImage: "speaker.wave.2")
            }
        }
    }

    private var quitButton: some View {
        Button("退出 Claude Signal") {
            NSApplication.shared.terminate(nil)
        }
    }
}
