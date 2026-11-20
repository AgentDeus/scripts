import SwiftUI

/// A row in the message list: either a message, a date separator or the marker line.
private enum ChatRow: Identifiable {
    case message(IrcMessage)
    case day(Date)
    case marker

    var id: String {
        switch self {
        case .message(let m): return "m\(m.msgId)"
        case .day(let d): return "d\(Int(d.timeIntervalSince1970))"
        case .marker: return "marker"
        }
    }
}

struct ChatView: View {
    @Environment(\.chatTheme) private var theme
    @Environment(\.scenePhase) private var scenePhase
    let session: CoreSession
    let buffer: BufferInfo

    private var settings: AppSettings { AppSettings.shared }
    @State private var atBottom = true
    @State private var scrollToBottomToken = 0
    /// Auto "load more" only fires after the user really scrolled to the top, once per arrival of the loader.
    @State private var loaderArmed = false

    private var store: BufferMessages { session.store(for: buffer.bufferId) }

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ZStack(alignment: .bottomTrailing) {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            topLoader
                            ForEach(rows) { row in
                                rowView(row)
                                    .id(row.id)
                            }
                            Color.clear
                                .frame(height: 1)
                                .id("bottom")
                                .onAppear { atBottom = true }
                                .onDisappear { atBottom = false }
                        }
                        .padding(.vertical, 4)
                    }
                    .defaultScrollAnchor(.bottom)
                    .scrollDismissesKeyboard(.interactively)
                    .onChange(of: store.messages.last?.msgId) { _, _ in
                        if atBottom {
                            withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo("bottom", anchor: .bottom) }
                            if scenePhase == .active { session.scheduleMarkRead(buffer.bufferId) }
                        }
                    }
                    .onChange(of: scrollToBottomToken) { _, _ in
                        withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
                    }

                    if !atBottom {
                        Button {
                            scrollToBottomToken += 1
                        } label: {
                            Image(systemName: "arrow.down")
                                .font(.headline)
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(theme.primary, in: Circle())
                                .shadow(radius: 3)
                        }
                        .padding(14)
                        .transition(.scale.combined(with: .opacity))
                    }
                }
            }
            InputBar(session: session, buffer: buffer) {
                scrollToBottomToken += 1
            }
        }
        .background(theme.background)
        .onAppear {
            session.visibleBuffer = buffer.bufferId
            session.loadInitialBacklog(buffer.bufferId)
            session.markRead(buffer.bufferId)
            Notifier.shared.clear(account: session.id, buffer: buffer.bufferId)
            loaderArmed = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { loaderArmed = true }
        }
        .onDisappear {
            if session.visibleBuffer == buffer.bufferId { session.visibleBuffer = nil }
            session.setMarkerLine(buffer.bufferId)
            // Keep chats we are not looking at small, so switching back is fast.
            session.store(for: buffer.bufferId).shrink(to: AppSettings.shared.initialBacklog)
        }
        .onChange(of: session.isConnected) { _, c in
            if c { session.loadInitialBacklog(buffer.bufferId) }
        }
    }

    @ViewBuilder private var topLoader: some View {
        if store.loading {
            HStack { Spacer(); ProgressView(); Spacer() }.padding(8)
        } else if store.reachedStart {
            Text("Beginning of history")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(8)
        } else if store.isFull {
            Text("Showing the latest \(BufferMessages.maxKept) messages")
                .font(.caption)
                .foregroundStyle(theme.secondaryText)
                .frame(maxWidth: .infinity)
                .padding(8)
        } else if !store.messages.isEmpty {
            Button {
                session.loadMoreBacklog(buffer.bufferId)
            } label: {
                Text("Load older messages")
                    .font(.caption)
                    .frame(maxWidth: .infinity)
                    .padding(8)
            }
            .onAppear {
                guard loaderArmed, !atBottom else { return }
                loaderArmed = false
                session.loadMoreBacklog(buffer.bufferId)
            }
            .onDisappear { loaderArmed = true }
        }
    }

    private var rows: [ChatRow] {
        let hidden = settings.hiddenTypes.union(.dayChange).union(.markerline)
        let marker = settings.showMarkerLine ? session.bufferSyncer.markerLines[buffer.bufferId] : nil
        let msgs = store.messages
        var out = [ChatRow]()
        out.reserveCapacity(msgs.count + 8)
        let cal = Calendar.current
        var lastDay: Date?
        for (i, m) in msgs.enumerated() {
            if !m.type.intersection(hidden).isEmpty && m.type.intersection(.conversation).isEmpty { continue }
            if m.flags.contains(.ignored) { continue }
            let day = cal.startOfDay(for: m.time)
            if !settings.hideDayChange && lastDay != day {
                out.append(.day(day))
            }
            lastDay = day
            out.append(.message(m))
            if let mk = marker, m.msgId == mk, i < msgs.count - 1 {
                out.append(.marker)
            }
        }
        return out
    }

    @ViewBuilder private func rowView(_ row: ChatRow) -> some View {
        switch row {
        case .message(let m):
            MessageRow(message: m, session: session, buffer: buffer)
        case .day(let d):
            HStack {
                Rectangle().fill(theme.secondaryText.opacity(0.3)).frame(height: 1)
                Text(d, format: .dateTime.weekday(.wide).day().month(.wide).year())
                    .font(.caption.weight(.medium))
                    .foregroundStyle(theme.secondaryText)
                    .fixedSize()
                Rectangle().fill(theme.secondaryText.opacity(0.3)).frame(height: 1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        case .marker:
            Rectangle()
                .fill(theme.markerLine)
                .frame(height: 2)
                .padding(.vertical, 2)
        }
    }
}

struct MessageRow: View {
    @Environment(\.chatTheme) private var theme
    let message: IrcMessage
    let session: CoreSession
    let buffer: BufferInfo
    private var settings: AppSettings { AppSettings.shared }

    private var timeFormat: Date.FormatStyle {
        var f = Date.FormatStyle().hour(settings.use24h ? .twoDigits(amPM: .omitted) : .defaultDigits(amPM: .abbreviated))
            .minute(.twoDigits)
        if settings.showSeconds { f = f.second(.twoDigits) }
        return f
    }

    /// Formatting a message (colours, links) is expensive, so the result is cached per message and style.
    private var rendered: AttributedString {
        let s = settings
        let key = "\(session.id.uuidString)|\(message.msgId)|\(s.theme.rawValue)|\(theme.isDark)|\(s.colorizeNicks.rawValue)|\(s.prefixMode.rawValue)|\(s.nicksInBrackets)|\(s.showFormatting)|\(s.showRealNames)|\(s.showHostmask)" as NSString
        if let hit = RenderCache.shared.object(forKey: key) { return hit.value }
        let r = MessageRenderer(theme: theme, settings: s, network: session.networks[message.bufferInfo.networkId])
            .render(message)
        RenderCache.shared.setObject(RenderBox(r), forKey: key)
        return r
    }

    var body: some View {
        let isHighlight = message.flags.contains(.highlight) && !message.flags.contains(.selfMsg)
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if settings.showTimestamps {
                Text(message.time, format: timeFormat)
                    .font(.system(size: settings.fontSize * 0.8).monospacedDigit())
                    .foregroundStyle(theme.timestamp)
            }
            Text(rendered)
                .font(.system(size: settings.fontSize))
                .foregroundStyle(theme.text)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 2.5)
        .background(isHighlight ? theme.highlightBackground : (message.flags.contains(.selfMsg) ? theme.selfBackground : .clear))
        .contextMenu {
            Button {
                UIPasteboard.general.string = MessageRenderer.plainText(message)
            } label: { Label("Copy", systemImage: "doc.on.doc") }
            Button {
                UIPasteboard.general.string = IrcFormat.strip(message.content)
            } label: { Label("Copy text only", systemImage: "text.quote") }
            if !message.senderNick.isEmpty && MessageRenderer.isConversation(message) {
                Button {
                    InputDrafts.shared.insert(nick: message.senderNick, into: buffer.bufferId)
                } label: { Label("Reply to \(message.senderNick)", systemImage: "arrowshape.turn.up.left") }
                Button {
                    session.openQuery(buffer.networkId, nick: message.senderNick)
                } label: { Label("Query \(message.senderNick)", systemImage: "person.fill") }
                Button {
                    session.sendInput(buffer, "/whois \(message.senderNick) \(message.senderNick)")
                } label: { Label("Whois", systemImage: "person.text.rectangle") }
            }
            ShareLink(item: MessageRenderer.plainText(message)) { Label("Share", systemImage: "square.and.arrow.up") }
        }
    }
}

final class RenderBox {
    let value: AttributedString
    init(_ v: AttributedString) { value = v }
}

enum RenderCache {
    static let shared: NSCache<NSString, RenderBox> = {
        let c = NSCache<NSString, RenderBox>()
        c.countLimit = 6000
        return c
    }()
}
