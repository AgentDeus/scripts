import SwiftUI

enum ChatSheet: Identifiable {
    case settings, coreSettings, accounts, joinChannel, bufferInfo(BufferId), user(NetworkId, String), setup
    case search(BufferId)

    var id: String {
        switch self {
        case .settings: return "settings"
        case .coreSettings: return "core"
        case .accounts: return "accounts"
        case .joinChannel: return "join"
        case .bufferInfo(let b): return "info\(b)"
        case .user(let n, let nick): return "user\(n)/\(nick)"
        case .setup: return "setup"
        case .search(let b): return "search\(b)"
        }
    }
}

struct MainChatView: View {
    @Environment(SessionManager.self) private var manager
    @Environment(\.chatTheme) private var theme
    let session: CoreSession

    @State private var leftOpen = false
    @State private var rightOpen = false
    @State private var sheet: ChatSheet?
    @State private var settings = AppSettings.shared

    private var selectedBufferId: BufferId? { manager.selectedBuffer[session.id] }
    private var selectedBuffer: BufferInfo? { selectedBufferId.flatMap { session.buffers[$0] } }

    var body: some View {
        DrawerContainer(leftOpen: $leftOpen, rightOpen: $rightOpen,
                        rightEnabled: selectedBuffer?.type.contains(.channel) ?? false) {
            NavigationStack {
                chatContent
                    .toolbar { toolbar }
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbarBackground(theme.primary, for: .navigationBar)
                    .toolbarBackground(.visible, for: .navigationBar)
                    .toolbarColorScheme(.dark, for: .navigationBar)
            }
        } left: {
            BufferListView(session: session, onSelect: { b in
                select(b)
                leftOpen = false
            }, onAction: { s in
                leftOpen = false
                sheet = s
            })
        } right: {
            if let b = selectedBuffer {
                NickListView(session: session, buffer: b) { nick in
                    rightOpen = false
                    sheet = .user(b.networkId, nick)
                }
            }
        }
        .sheet(item: $sheet) { s in sheetView(s) }
        .alert(certificateTitle, isPresented: certificateBinding, presenting: pendingCertificate) { info in
            Button("Accept always") { session.acceptCertificate(info, permanently: true) }
            Button("Accept once") { session.acceptCertificate(info, permanently: false) }
            Button("Reject", role: .cancel) { session.rejectCertificate() }
        } message: { info in
            Text("The core's certificate is not trusted by iOS.\n\n\(info.subject)\n\nSHA-256:\n\(info.sha256)\n\nSHA-1:\n\(info.sha1)")
        }
        .onChange(of: session.phase) { _, p in
            if p == .needsSetup { sheet = .setup }
        }
        .environment(\.openURL, OpenURLAction { url in handle(url) })
        .onAppear {
            if selectedBufferId == nil { leftOpen = true }
        }
    }

    // MARK: Content

    @ViewBuilder private var chatContent: some View {
        VStack(spacing: 0) {
            ConnectionBanner(session: session)
            if let b = selectedBuffer {
                ChatView(session: session, buffer: b)
                    .id(b.bufferId)
            } else {
                emptyState
            }
        }
        .background(theme.background.ignoresSafeArea())
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Spacer()
            Image(systemName: "bubble.left.and.bubble.right")
                .font(.system(size: 54))
                .foregroundStyle(theme.secondaryText)
            Text(session.isConnected ? "Select a chat" : phaseLabel(session.phase))
                .font(.title3)
                .foregroundStyle(theme.text)
            Button {
                leftOpen = true
            } label: {
                Label("Open chat list", systemImage: "line.3.horizontal")
            }
            .buttonStyle(.bordered)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    @ToolbarContentBuilder private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { leftOpen.toggle() } label: {
                Image(systemName: "line.3.horizontal")
                    .overlay(alignment: .topTrailing) {
                        if hasUnreadElsewhere {
                            Circle().fill(theme.accent).frame(width: 8, height: 8).offset(x: 5, y: -4)
                        }
                    }
            }
            .foregroundStyle(theme.onPrimary)
        }
        ToolbarItem(placement: .principal) {
            Button {
                if let b = selectedBuffer { sheet = .bufferInfo(b.bufferId) }
            } label: {
                VStack(spacing: 0) {
                    Text(selectedBuffer.map { session.bufferName($0) } ?? session.account.displayName)
                        .font(.headline)
                        .lineLimit(1)
                        .foregroundStyle(theme.onPrimary)
                    if let sub = subtitle, !sub.isEmpty {
                        Text(sub)
                            .font(.caption)
                            .lineLimit(1)
                            .foregroundStyle(theme.onPrimary.opacity(0.8))
                    }
                }
                .frame(maxWidth: 240)
            }
        }
        ToolbarItemGroup(placement: .topBarTrailing) {
            if let b = selectedBuffer, b.type.contains(.channel), settings.showNickListButton {
                Button { rightOpen.toggle() } label: { Image(systemName: "person.2") }
                    .foregroundStyle(theme.onPrimary)
            }
            Menu {
                bufferMenu
                Divider()
                Button { sheet = .settings } label: { Label("Settings", systemImage: "gearshape") }
                Button { sheet = .coreSettings } label: { Label("Core settings", systemImage: "server.rack") }
                Button { sheet = .accounts } label: { Label("Cores", systemImage: "rectangle.stack") }
                Divider()
                if session.phase.isActive {
                    Button(role: .destructive) { manager.disconnect(session.id) } label: {
                        Label("Disconnect from core", systemImage: "bolt.slash")
                    }
                } else {
                    Button { session.connect() } label: { Label("Reconnect", systemImage: "bolt") }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .foregroundStyle(theme.onPrimary)
            }
        }
    }

    @ViewBuilder private var bufferMenu: some View {
        if let b = selectedBuffer {
            Button { sheet = .search(b.bufferId) } label: { Label("Search", systemImage: "magnifyingglass") }
            if b.type.contains(.channel) {
                if session.isBufferActive(b) {
                    Button { session.part(b) } label: { Label("Part", systemImage: "arrow.left.square") }
                } else {
                    Button { session.joinChannel(b.networkId, b.name) } label: {
                        Label("Join", systemImage: "arrow.right.square")
                    }
                }
            }
            if b.type.contains(.query) {
                Button { session.sendInput(b, "/whois \(b.name) \(b.name)") } label: {
                    Label("Whois", systemImage: "person.text.rectangle")
                }
            }
            Button { session.markRead(b.bufferId) } label: { Label("Mark as read", systemImage: "checkmark.circle") }
            Button { sheet = .bufferInfo(b.bufferId) } label: { Label("Info", systemImage: "info.circle") }
        }
    }

    private var subtitle: String? {
        guard let b = selectedBuffer else { return session.isConnected ? nil : phaseLabel(session.phase) }
        let net = session.networks[b.networkId]
        if b.type.contains(.channel) {
            let topic = IrcFormat.strip(net?.channel(b.name)?.topic ?? "")
            return topic.isEmpty ? net?.networkName : topic
        }
        if b.type.contains(.query) {
            if let u = net?.user(b.name) {
                if u.away { return "Away: \(u.awayMessage)" }
                return u.realName.isEmpty ? net?.networkName : IrcFormat.strip(u.realName)
            }
            return net?.networkName
        }
        if b.type.contains(.status), let n = net {
            return n.isConnected ? n.currentServer : n.connectionState.label
        }
        return nil
    }

    private var hasUnreadElsewhere: Bool {
        session.bufferSyncer.highlightCounts.contains { $0.key != selectedBufferId && $0.value > 0 }
    }

    // MARK: Actions

    private func select(_ b: BufferInfo) {
        if let old = selectedBufferId, old != b.bufferId { session.setMarkerLine(old) }
        manager.select(buffer: b.bufferId, in: session.id)
    }

    private func handle(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "iquasselcc" else { return .systemAction }
        let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = q.first?.value ?? ""
        guard let b = selectedBuffer else { return .handled }
        switch url.host {
        case "join":
            if let existing = session.buffers.values.first(where: {
                $0.networkId == b.networkId && $0.name.lowercased() == value.lowercased()
            }) {
                if !session.isBufferActive(existing) { session.joinChannel(b.networkId, value) }
                select(existing)
            } else {
                session.joinChannel(b.networkId, value)
            }
        case "nick":
            sheet = .user(b.networkId, value)
        default:
            break
        }
        return .handled
    }

    private var pendingCertificate: CoreCertificateInfo? {
        if case .awaitingCertificateDecision(let info) = session.phase { return info }
        return nil
    }

    private var certificateTitle: String { "Untrusted certificate" }

    private var certificateBinding: Binding<Bool> {
        Binding(get: { pendingCertificate != nil }, set: { _ in })
    }

    @ViewBuilder private func sheetView(_ s: ChatSheet) -> some View {
        Group {
            switch s {
            case .settings:
                NavigationStack { SettingsView() }
            case .coreSettings:
                NavigationStack { CoreSettingsView(session: session) }
            case .accounts:
                NavigationStack { AccountsView(isSheet: true) }
            case .joinChannel:
                NavigationStack { JoinChannelView(session: session) }
            case .bufferInfo(let id):
                if let b = session.buffers[id] {
                    NavigationStack { BufferInfoView(session: session, buffer: b) }
                }
            case .user(let net, let nick):
                NavigationStack {
                    UserInfoView(session: session, networkId: net, nick: nick) { b in
                        sheet = nil
                        select(b)
                    }
                }
            case .setup:
                NavigationStack { CoreSetupView(session: session) }
            case .search(let id):
                if let b = session.buffers[id] {
                    NavigationStack { SearchView(session: session, buffer: b) }
                }
            }
        }
        .environment(manager)
        .environment(\.chatTheme, theme)
    }
}

/// Thin banner showing the core connection state, like the Android client's status bar.
struct ConnectionBanner: View {
    let session: CoreSession
    @Environment(\.chatTheme) private var theme

    var body: some View {
        switch session.phase {
        case .connected:
            if let n = disconnectedNetworkWarning {
                bar(text: n, color: .orange, spinner: false)
            }
        case .failed(let reason):
            HStack {
                Image(systemName: "exclamationmark.triangle.fill")
                Text(reason).lineLimit(2)
                Spacer()
                Button("Retry") { session.connect() }
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.red.opacity(0.85))
        case .disconnected:
            HStack {
                Text("Disconnected from core")
                Spacer()
                Button("Connect") { session.connect() }.buttonStyle(.bordered).tint(.white)
            }
            .font(.footnote)
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color.gray)
        default:
            bar(text: phaseLabel(session.phase), color: theme.primary.opacity(0.85), spinner: true)
        }
    }

    private var disconnectedNetworkWarning: String? { nil }

    private func bar(text: String, color: Color, spinner: Bool) -> some View {
        HStack(spacing: 8) {
            if spinner { ProgressView().tint(.white).controlSize(.small) }
            Text(text)
            Spacer()
        }
        .font(.footnote)
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color)
    }
}
