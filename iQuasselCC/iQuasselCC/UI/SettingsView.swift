import SwiftUI

/// Client (app) settings.
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable private var s = AppSettings.shared

    var body: some View {
        Form {
            Section("Appearance") {
                Picker("Theme", selection: $s.theme) {
                    ForEach(ThemeChoice.allCases) { Text($0.label).tag($0) }
                }
                VStack(alignment: .leading) {
                    Text("Text size: \(Int(s.fontSize)) pt")
                    Slider(value: $s.fontSize, in: 11...24, step: 1)
                }
                Picker("Colourize nicknames", selection: $s.colorizeNicks) {
                    ForEach(ColorizeNicks.allCases) { Text($0.label).tag($0) }
                }
                Picker("Show nick prefixes", selection: $s.prefixMode) {
                    ForEach(PrefixMode.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show mIRC formatting", isOn: $s.showFormatting)
                Toggle("Nicknames in brackets", isOn: $s.nicksInBrackets)
                Toggle("Show real names", isOn: $s.showRealNames)
                Toggle("Show hostmasks", isOn: $s.showHostmask)
            }
            Section("Timestamps") {
                Toggle("Show timestamps", isOn: $s.showTimestamps)
                Toggle("24-hour clock", isOn: $s.use24h)
                Toggle("Show seconds", isOn: $s.showSeconds)
            }
            Section("Messages") {
                Toggle("Hide joins, parts and quits", isOn: $s.hideJoinPartQuit)
                Toggle("Hide nick changes", isOn: $s.hideNickChanges)
                Toggle("Hide mode changes", isOn: $s.hideModeChanges)
                Toggle("Hide date separators", isOn: $s.hideDayChange)
                Toggle("Show marker line", isOn: $s.showMarkerLine)
            }
            Section("Chat list") {
                Toggle("Hide inactive chats", isOn: $s.hideInactiveBuffersLocally)
                Toggle("Show nick list button", isOn: $s.showNickListButton)
            }
            Section("Input") {
                Toggle("Send with return key", isOn: $s.sendOnReturn)
                Toggle("Always show formatting bar", isOn: $s.showInputFormattingBar)
                Stepper("History size: \(s.inputHistorySize)", value: $s.inputHistorySize, in: 10...500, step: 10)
            }
            Section {
                Stepper("Initial: \(s.initialBacklog) messages", value: $s.initialBacklog, in: 20...1000, step: 20)
                Stepper("Load more: \(s.pageBacklog) messages", value: $s.pageBacklog, in: 20...500, step: 25)
            } header: {
                Text("Backlog")
            } footer: {
                Text("History is stored on your Quassel core and loaded on demand.")
            }
            Section {
                Toggle("Highlights", isOn: $s.notifyHighlights)
                Toggle("Private messages", isOn: $s.notifyQueries)
                Toggle("All channel messages", isOn: $s.notifyAllChannelMessages)
                Toggle("Sound", isOn: $s.notificationSound)
            } header: {
                Text("Notifications")
            } footer: {
                Text("iOS suspends network connections shortly after the app goes to the background, so notifications are delivered while iQuasselCC is open or recently used. Your core keeps you connected to IRC at all times.")
            }
            Section("Connection") {
                Toggle("Connect all cores on launch", isOn: $s.connectAllOnLaunch)
            }
            Section("About") {
                LabeledContent("App", value: "iQuasselCC")
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")
                Text("Quassel Core Client – not a stand-alone client. iQuasselCC connects to your own Quassel core, which stays connected to IRC for you.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}
