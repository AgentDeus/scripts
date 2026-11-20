import SwiftUI

/// Right drawer: members of the current channel sorted by their prefix (op, voice, …).
struct NickListView: View {
    @Environment(\.chatTheme) private var theme
    let session: CoreSession
    let buffer: BufferInfo
    var onSelect: (String) -> Void

    @State private var filter = ""
    private var settings: AppSettings { AppSettings.shared }

    private struct Entry: Identifiable {
        let nick: String
        let modes: String
        let prefix: String
        let rank: Int
        let away: Bool
        let realName: String
        var id: String { nick }
    }

    private var entries: [Entry] {
        guard let net = session.networks[buffer.networkId], let chan = net.channel(buffer.name) else { return [] }
        return chan.userModes.map { key, modes in
            let u = net.users[key]
            let nick = u?.nick ?? key
            return Entry(nick: nick, modes: modes, prefix: net.prefixes(forModes: modes), rank: net.rank(forModes: modes),
                         away: u?.away ?? false, realName: u?.realName ?? "")
        }
        .filter { filter.isEmpty || $0.nick.localizedCaseInsensitiveContains(filter) }
        .sorted { $0.rank != $1.rank ? $0.rank < $1.rank : $0.nick.lowercased() < $1.nick.lowercased() }
    }

    var body: some View {
        let list = entries
        VStack(spacing: 0) {
            HStack {
                Text("\(list.count) users").font(.headline).foregroundStyle(theme.onPrimary)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(theme.primary.ignoresSafeArea(edges: .top))

            HStack {
                Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
                TextField("Search", text: $filter)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            }
            .padding(8)
            .background(theme.surfaceVariant, in: RoundedRectangle(cornerRadius: 8))
            .padding(10)

            List(list) { e in
                HStack(spacing: 6) {
                    Text(e.prefix.isEmpty ? " " : String(e.prefix.prefix(1)))
                        .font(.system(.body, design: .monospaced).bold())
                        .foregroundStyle(theme.accent)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(e.nick)
                            .foregroundStyle(e.away ? theme.awayNick
                                             : theme.nickColor(e.nick, isSelf: false, mode: settings.colorizeNicks))
                            .italic(e.away)
                        if settings.showRealNames && !e.realName.isEmpty {
                            Text(IrcFormat.strip(e.realName)).font(.caption).foregroundStyle(theme.secondaryText).lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .contentShape(Rectangle())
                .onTapGesture { onSelect(e.nick) }
                .listRowBackground(theme.surface)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 32)
        }
        .background(theme.surface)
    }
}

/// Details and actions for an IRC user (whois data synced by the core).
struct UserInfoView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.chatTheme) private var theme
    let session: CoreSession
    let networkId: NetworkId
    let nick: String
    var openBuffer: (BufferInfo) -> Void

    private var network: Network? { session.networks[networkId] }
    private var user: IrcUser? { network?.user(nick) }
    private var currentChannel: BufferInfo? {
        // Channel actions apply to the currently open buffer if it is a channel.
        nil
    }

    var body: some View {
        List {
            Section {
                HStack(spacing: 14) {
                    Text(String(nick.prefix(1)).uppercased())
                        .font(.title.bold())
                        .foregroundStyle(.white)
                        .frame(width: 56, height: 56)
                        .background(theme.nickColor(nick, isSelf: false, mode: .all), in: Circle())
                    VStack(alignment: .leading) {
                        Text(nick).font(.title3.bold())
                        if let u = user, !u.realName.isEmpty {
                            Text(IrcFormat.strip(u.realName)).foregroundStyle(.secondary)
                        }
                        if let u = user, u.away {
                            Label("Away\(u.awayMessage.isEmpty ? "" : ": " + u.awayMessage)", systemImage: "moon.fill")
                                .font(.caption).foregroundStyle(.orange)
                        }
                    }
                }
                .padding(.vertical, 4)
            }
            Section("Actions") {
                Button {
                    if let b = session.buffers.values.first(where: {
                        $0.networkId == networkId && $0.type.contains(.query) && $0.name.lowercased() == nick.lowercased()
                    }) {
                        openBuffer(b)
                    } else {
                        session.openQuery(networkId, nick: nick)
                        dismiss()
                    }
                } label: { Label("Open query", systemImage: "bubble.left") }
                Button {
                    if let s = session.statusBuffer(for: networkId) { session.sendInput(s, "/whois \(nick) \(nick)") }
                } label: { Label("Whois", systemImage: "person.text.rectangle") }
                Button {
                    if let s = session.statusBuffer(for: networkId) { session.sendInput(s, "/ctcp \(nick) VERSION") }
                } label: { Label("CTCP Version", systemImage: "questionmark.circle") }
                Button(role: .destructive) {
                    var list = session.ignoreListManager.ignoreList
                    list.append(IgnoreEntry(type: 0, rule: "\(nick)!*@*", isRegEx: false, strictness: 2, scope: 0,
                                            scopeRule: "", isActive: true))
                    session.updateIgnoreList(list)
                    dismiss()
                } label: { Label("Ignore", systemImage: "nosign") }
            }
            if let u = user {
                let channels = u.channels.sorted()
                if !channels.isEmpty, let net = network {
                    Section("Channel moderation") {
                        ForEach(channels, id: \.self) { c in
                            Menu {
                                ForEach(["op", "deop", "halfop", "dehalfop", "voice", "devoice"], id: \.self) { cmd in
                                    Button("/\(cmd)") { send(c, "/\(cmd) \(nick)") }
                                }
                                Button("Kick", role: .destructive) { send(c, "/kick \(nick)") }
                                Button("Ban", role: .destructive) { send(c, "/ban \(nick)") }
                            } label: {
                                HStack {
                                    Text(net.channel(c)?.name ?? c)
                                    Spacer()
                                    let modes = net.channel(c)?.userModes[nick.lowercased()] ?? ""
                                    Text(net.prefixes(forModes: modes)).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
                Section("Details") {
                    row("Hostmask", "\(u.user)@\(u.host)")
                    row("Account", u.account)
                    row("Server", u.server)
                    row("Operator", u.ircOperator)
                    row("User modes", u.userModes)
                    if let d = u.loginTime { row("Logged in", d.formatted()) }
                    if let d = u.idleTime { row("Idle since", d.formatted()) }
                }
            } else {
                Section {
                    Text("This user is not in any channel you share. Use Whois to request details.")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle(nick)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }

    private func send(_ channel: String, _ cmd: String) {
        if let b = session.buffers.values.first(where: {
            $0.networkId == networkId && $0.type.contains(.channel) && $0.name.lowercased() == channel.lowercased()
        }) {
            session.sendInput(b, cmd)
        }
    }

    @ViewBuilder private func row(_ title: String, _ value: String) -> some View {
        if !value.isEmpty && value != "@" {
            LabeledContent(title) {
                Text(value).textSelection(.enabled).multilineTextAlignment(.trailing)
            }
        }
    }
}
