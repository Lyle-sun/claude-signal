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
        Form {
            Section(language == .chinese ? "外观" : "Appearance") {
                Picker(language == .chinese ? "语言" : "Language", selection: $dashboardLanguageRawValue) {
                    ForEach(DashboardLanguage.allCases) { language in
                        Text(language.displayName).tag(language.rawValue)
                    }
                }
                .pickerStyle(.segmented)
            }

            Section(language == .chinese ? "监控" : "Monitoring") {
                LabeledContent(language == .chinese ? "Context 窗口上限" : "Context Window Limit") {
                    TextField("", value: $contextWindowLimit, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 100)
                    Text("tokens")
                        .foregroundStyle(.secondary)
                }

                LabeledContent(language == .chinese ? "警告阈值" : "Warning Threshold") {
                    Slider(value: $warningThresholdPercent, in: 50...95, step: 5) {
                        Text("\(Int(warningThresholdPercent))%")
                    }
                    Text(language == .chinese ? "占 Context 窗口比例" : "of context window")
                        .foregroundStyle(.secondary)
                }

                LabeledContent(language == .chinese ? "轮询间隔" : "Polling Interval") {
                    Slider(value: $pollIntervalSeconds, in: 1...10, step: 0.5) {
                        Text(language == .chinese ? "\(String(format: "%.1f", pollIntervalSeconds))秒" : "\(String(format: "%.1f", pollIntervalSeconds))s")
                    }
                }
            }

            Section(language == .chinese ? "通知" : "Notifications") {
                Toggle(language == .chinese ? "声音提醒" : "Sound Alerts", isOn: $soundEnabled)

                if soundEnabled {
                    Text(language == .chinese ? "会话需要确认或 Context 超限时播放声音。" : "Play a sound when a session needs confirmation or exceeds context.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section(language == .chinese ? "关于" : "About") {
                LabeledContent(language == .chinese ? "版本" : "Version") {
                    Text("0.2.0")
                        .foregroundStyle(.secondary)
                }
                LabeledContent(language == .chinese ? "数据位置" : "Data Location") {
                    Text("~/Library/Application Support/ClaudeSignal/")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                }
            }
        }
        .formStyle(.grouped)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
