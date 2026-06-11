import SwiftUI

/// 设置视图
@MainActor
struct SettingsView: View {
    @AppStorage("contextWindowLimit") private var contextWindowLimit = 200_000
    @AppStorage("pollIntervalSeconds") private var pollIntervalSeconds = 2.0
    @AppStorage("soundEnabled") private var soundEnabled = true
    @AppStorage("warningThresholdPercent") private var warningThresholdPercent = 75.0
    @AppStorage("dashboardLanguage") private var dashboardLanguageRawValue = DashboardLanguage.chinese.rawValue

    private var language: DashboardLanguage {
        DashboardText.appLanguage(from: dashboardLanguageRawValue)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                settingsSection(title: language == .chinese ? "外观" : "Appearance") {
                    settingsRow(title: language == .chinese ? "语言" : "Language") {
                        Picker("", selection: $dashboardLanguageRawValue) {
                            ForEach(DashboardLanguage.allCases) { language in
                                Text(language.displayName).tag(language.rawValue)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 220)
                    }
                }

                settingsSection(title: language == .chinese ? "监控" : "Monitoring") {
                    settingsRow(title: language == .chinese ? "Context 窗口上限" : "Context Window Limit") {
                        TextField("", value: $contextWindowLimit, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 100)
                        Text("tokens")
                            .foregroundStyle(.secondary)
                    }

                    settingsRow(title: language == .chinese ? "警告阈值" : "Warning Threshold") {
                        Slider(value: $warningThresholdPercent, in: 50...95, step: 5)
                            .frame(maxWidth: 220)
                        Text("\(Int(warningThresholdPercent))%")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    settingsRow(title: language == .chinese ? "轮询间隔" : "Polling Interval") {
                        Slider(value: $pollIntervalSeconds, in: 1...10, step: 0.5)
                            .frame(maxWidth: 220)
                        Text(language == .chinese ? "\(String(format: "%.1f", pollIntervalSeconds))秒" : "\(String(format: "%.1f", pollIntervalSeconds))s")
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                settingsSection(title: language == .chinese ? "通知" : "Notifications") {
                    Toggle(language == .chinese ? "声音提醒" : "Sound Alerts", isOn: $soundEnabled)

                    if soundEnabled {
                        Text(language == .chinese ? "会话需要确认或 Context 超限时播放声音。" : "Play a sound when a session needs confirmation or exceeds context.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                settingsSection(title: language == .chinese ? "关于" : "About") {
                    settingsRow(title: language == .chinese ? "版本" : "Version") {
                        Text("0.2.0")
                            .foregroundStyle(.secondary)
                    }

                    settingsRow(title: language == .chinese ? "数据位置" : "Data Location") {
                        Text("~/Library/Application Support/ClaudeSignal/")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.windowBackgroundColor))
    }

    private func settingsSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)

            VStack(alignment: .leading, spacing: 12) {
                content()
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(NSColor.controlBackgroundColor).opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
            }
        }
    }

    private func settingsRow<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 150, alignment: .leading)

            HStack(spacing: 8) {
                content()
            }

            Spacer(minLength: 0)
        }
    }
}
