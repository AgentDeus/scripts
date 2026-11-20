import SwiftUI

/// Drafts and sent-message history per buffer (kept in memory, like the Android client).
@Observable
final class InputDrafts {
    static let shared = InputDrafts()
    var drafts: [BufferId: String] = [:]
    var history: [BufferId: [String]] = [:]

    func insert(nick: String, into buffer: BufferId) {
        let current = drafts[buffer] ?? ""
        drafts[buffer] = current.isEmpty ? "\(nick): " : current + (current.hasSuffix(" ") ? "" : " ") + nick + " "
    }

    func remember(_ text: String, for buffer: BufferId) {
        var h = history[buffer] ?? []
        h.removeAll { $0 == text }
        h.append(text)
        let max = AppSettings.shared.inputHistorySize
        if h.count > max { h.removeFirst(h.count - max) }
        history[buffer] = h
    }
}

struct InputBar: View {
    @Environment(\.chatTheme) private var theme
    let session: CoreSession
    let buffer: BufferInfo
    var onSend: () -> Void

    @State private var drafts = InputDrafts.shared
    @State private var settings = AppSettings.shared
    @State private var showFormatting = false
    @State private var historyIndex: Int?
    @State private var completion: (prefix: String, matches: [String], index: Int)?
    @State private var showColors = false
    @FocusState private var focused: Bool

    private var text: Binding<String> {
        Binding(get: { drafts.drafts[buffer.bufferId] ?? "" },
                set: { new in
                    let old = drafts.drafts[buffer.bufferId] ?? ""
                    completion = nil
                    if settings.sendOnReturn, new.hasSuffix("\n"), new.count == old.count + 1 {
                        drafts.drafts[buffer.bufferId] = String(new.dropLast())
                        send()
                    } else {
                        drafts.drafts[buffer.bufferId] = new
                    }
                })
    }

    var body: some View {
        VStack(spacing: 0) {
            Divider()
            if showFormatting || settings.showInputFormattingBar {
                formattingBar
            }
            HStack(alignment: .bottom, spacing: 6) {
                Button {
                    withAnimation { showFormatting.toggle() }
                } label: {
                    Image(systemName: "textformat")
                        .frame(width: 34, height: 36)
                }
                .foregroundStyle(showFormatting ? theme.primary : theme.secondaryText)

                TextField(placeholder, text: text, axis: .vertical)
                    .lineLimit(1...6)
                    .focused($focused)
                    .submitLabel(.send)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(theme.surfaceVariant, in: RoundedRectangle(cornerRadius: 18))
                    .disabled(!session.isConnected)
                    .onKeyPress(.tab) { complete(); return .handled }
                    .onKeyPress(.upArrow) { historyUp(); return .handled }
                    .onKeyPress(.downArrow) { historyDown(); return .handled }

                if buffer.type.contains(.channel) || buffer.type.contains(.query) {
                    Button(action: complete) {
                        Image(systemName: "arrow.right.to.line")
                            .frame(width: 30, height: 36)
                    }
                    .foregroundStyle(theme.secondaryText)
                    .accessibilityLabel("Complete nickname")
                }

                Button(action: send) {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 17))
                        .frame(width: 36, height: 36)
                        .foregroundStyle(.white)
                        .background(canSend ? theme.primary : theme.inactive, in: Circle())
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
        }
        .background(theme.surface.ignoresSafeArea(edges: .bottom))
        .sheet(isPresented: $showColors) {
            colorPicker
                .presentationDetents([.height(300)])
        }
    }

    private var placeholder: String {
        if !session.isConnected { return "Not connected" }
        let net = session.networks[buffer.networkId]
        let nick = net?.myNick ?? ""
        return nick.isEmpty ? "Message" : "Message as \(nick)"
    }

    private var canSend: Bool {
        session.isConnected && !text.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func send() {
        let t = text.wrappedValue
        guard canSend else { return }
        session.sendInput(buffer, t)
        drafts.remember(t, for: buffer.bufferId)
        drafts.drafts[buffer.bufferId] = ""
        historyIndex = nil
        onSend()
        focused = true
    }

    // MARK: History

    private func historyUp() {
        let h = drafts.history[buffer.bufferId] ?? []
        guard !h.isEmpty else { return }
        let i = max(0, (historyIndex ?? h.count) - 1)
        historyIndex = i
        drafts.drafts[buffer.bufferId] = h[i]
    }

    private func historyDown() {
        let h = drafts.history[buffer.bufferId] ?? []
        guard let cur = historyIndex else { return }
        if cur + 1 < h.count {
            historyIndex = cur + 1
            drafts.drafts[buffer.bufferId] = h[cur + 1]
        } else {
            historyIndex = nil
            drafts.drafts[buffer.bufferId] = ""
        }
    }

    // MARK: Nick completion (tab completion like the desktop / Android clients)

    private func complete() {
        let current = text.wrappedValue
        let net = session.networks[buffer.networkId]
        if var c = completion, !c.matches.isEmpty {
            c.index = (c.index + 1) % c.matches.count
            completion = nil
            drafts.drafts[buffer.bufferId] = apply(c.prefix, c.matches[c.index])
            completion = c
            return
        }
        let parts = current.split(separator: " ", omittingEmptySubsequences: false)
        let word = parts.last.map(String.init) ?? ""
        guard !word.isEmpty else { return }
        let before = parts.dropLast().joined(separator: " ")
        let prefix = before.isEmpty ? "" : before + " "
        var candidates: [String] = []
        if let net = net, buffer.type.contains(.channel), let chan = net.channel(buffer.name) {
            candidates = chan.userModes.keys.sorted { $0.lowercased() < $1.lowercased() }
            candidates += net.channels.values.map { $0.name }
        } else if buffer.type.contains(.query) {
            candidates = [buffer.name, net?.myNick ?? ""]
        }
        let matches = candidates.filter { $0.lowercased().hasPrefix(word.lowercased()) && !$0.isEmpty }
        guard !matches.isEmpty else { return }
        completion = nil
        drafts.drafts[buffer.bufferId] = apply(prefix, matches[0])
        completion = (prefix, matches, 0)
    }

    private func apply(_ prefix: String, _ nick: String) -> String {
        let isChannel = session.networks[buffer.networkId]?.isChannelName(nick) ?? false
        if prefix.isEmpty && !isChannel { return nick + ": " }
        return prefix + nick + " "
    }

    // MARK: Formatting

    private var formattingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                fmt("bold", IrcFormat.bold)
                fmt("italic", IrcFormat.italic)
                fmt("underline", IrcFormat.underline)
                fmt("strikethrough", IrcFormat.strike)
                fmt("chevron.left.forwardslash.chevron.right", IrcFormat.monospace)
                Button { showColors = true } label: {
                    Image(systemName: "paintpalette").frame(width: 38, height: 34)
                }
                fmt("eraser", IrcFormat.reset)
                Divider().frame(height: 22)
                Button { historyUp() } label: { Image(systemName: "chevron.up").frame(width: 38, height: 34) }
                Button { historyDown() } label: { Image(systemName: "chevron.down").frame(width: 38, height: 34) }
                Button {
                    drafts.drafts[buffer.bufferId] = (text.wrappedValue) + "\n"
                } label: { Image(systemName: "return").frame(width: 38, height: 34) }
                .accessibilityLabel("New line")
            }
            .padding(.horizontal, 8)
        }
        .foregroundStyle(theme.text)
        .frame(height: 38)
    }

    private func fmt(_ icon: String, _ code: Character) -> some View {
        Button {
            drafts.drafts[buffer.bufferId] = text.wrappedValue + String(code)
        } label: {
            Image(systemName: icon).frame(width: 38, height: 34)
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Text colour").font(.headline)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 8), spacing: 8) {
                ForEach(0..<16, id: \.self) { i in
                    Button {
                        drafts.drafts[buffer.bufferId] = text.wrappedValue + String(IrcFormat.color) + String(format: "%02d", i)
                        showColors = false
                    } label: {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(MircColors.color(i) ?? .clear)
                            .frame(height: 34)
                            .overlay(RoundedRectangle(cornerRadius: 6).stroke(.secondary.opacity(0.4)))
                            .overlay(Text("\(i)").font(.caption2).foregroundStyle([1, 2, 5, 6, 12, 14].contains(i) ? Color.white : Color.black))
                    }
                }
            }
            Button("Remove colour") {
                drafts.drafts[buffer.bufferId] = text.wrappedValue + String(IrcFormat.color)
                showColors = false
            }
        }
        .padding()
    }
}
