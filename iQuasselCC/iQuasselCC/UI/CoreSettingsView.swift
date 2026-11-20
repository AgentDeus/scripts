import SwiftUI

/// Settings stored on the Quassel core.
struct CoreSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession

    var body: some View {
        List {
            if !session.isConnected {
                Section { Text("Connect to the core to edit its settings.").foregroundStyle(.secondary) }
            }
            Section("IRC") {
                NavigationLink { NetworksListView(session: session) } label: {
                    Label("Networks", systemImage: "network")
                }
                NavigationLink { IdentitiesListView(session: session) } label: {
                    Label("Identities", systemImage: "person.crop.circle")
                }
            }
            Section("Client") {
                NavigationLink { ChatListsView(session: session) } label: {
                    Label("Chat lists", systemImage: "list.bullet.rectangle")
                }
                NavigationLink { IgnoreListView(session: session) } label: {
                    Label("Ignore list", systemImage: "nosign")
                }
                NavigationLink { HighlightRulesView(session: session) } label: {
                    Label("Highlight rules", systemImage: "highlighter")
                }
                NavigationLink { AliasesView(session: session) } label: {
                    Label("Aliases", systemImage: "text.badge.plus")
                }
            }
            Section("Core") {
                NavigationLink { CoreInfoView(session: session) } label: {
                    Label("Core info", systemImage: "info.circle")
                }
                if session.coreFeatures.contains(.passwordChange) {
                    NavigationLink { PasswordChangeView(session: session) } label: {
                        Label("Change password", systemImage: "key")
                    }
                }
            }
        }
        .navigationTitle("Core settings")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .disabled(!session.isConnected)
    }
}

// MARK: - Networks

struct NetworksListView: View {
    let session: CoreSession
    @State private var creating = false

    var body: some View {
        List {
            ForEach(session.sortedNetworks) { n in
                NavigationLink {
                    NetworkEditView(session: session, settings: n.settings, isNew: false)
                } label: {
                    HStack {
                        Circle().fill(n.isConnected ? Color.green : Color.gray).frame(width: 9, height: 9)
                        VStack(alignment: .leading) {
                            Text(n.networkName)
                            Text(n.connectionState.label + (n.isConnected ? " · \(n.myNick)" : ""))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .swipeActions {
                    if n.connectionState == .disconnected {
                        Button("Connect") { session.connectNetwork(n.id) }.tint(.green)
                    } else {
                        Button("Disconnect") { session.disconnectNetwork(n.id) }.tint(.orange)
                    }
                }
            }
        }
        .navigationTitle("Networks")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { newNetwork() } label: { Image(systemName: "plus") }
            }
        }
    }
}

extension NetworksListView {
    func newNetwork() -> NetworkEditView {
        var s = NetworkSettings()
        s.identityId = session.sortedIdentities.first?.id ?? 1
        s.servers = [NetworkServer()]
        return NetworkEditView(session: session, settings: s, isNew: true)
    }
}

struct NetworkEditView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession
    @State var settings: NetworkSettings
    let isNew: Bool
    @State private var channels = ""
    @State private var editingServer: Int?
    @State private var confirmDelete = false
    @State private var performText = ""

    var body: some View {
        Form {
            Section("Network") {
                TextField("Name", text: $settings.networkName)
                Picker("Identity", selection: $settings.identityId) {
                    ForEach(session.sortedIdentities) { i in Text(i.settings.identityName).tag(i.id) }
                }
                if isNew {
                    TextField("Channels to join (space separated)", text: $channels)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            Section {
                ForEach(settings.servers.indices, id: \.self) { i in
                    Button {
                        editingServer = i
                    } label: {
                        HStack {
                            Image(systemName: settings.servers[i].useSSL ? "lock.fill" : "lock.open")
                            Text("\(settings.servers[i].host):\(String(settings.servers[i].port))")
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { settings.servers.remove(atOffsets: $0) }
                .onMove { settings.servers.move(fromOffsets: $0, toOffset: $1) }
                Button {
                    settings.servers.append(NetworkServer())
                    editingServer = settings.servers.count - 1
                } label: { Label("Add server", systemImage: "plus") }
                Toggle("Use random server", isOn: $settings.useRandomServer)
            } header: { Text("Servers") }

            Section("Authentication") {
                Toggle("SASL", isOn: $settings.useSasl)
                if settings.useSasl {
                    TextField("Account", text: $settings.saslAccount)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $settings.saslPassword)
                }
                Toggle("Auto identify (NickServ)", isOn: $settings.useAutoIdentify)
                if settings.useAutoIdentify {
                    TextField("Service", text: $settings.autoIdentifyService)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $settings.autoIdentifyPassword)
                }
            }
            Section("Auto reconnect") {
                Toggle("Reconnect automatically", isOn: $settings.useAutoReconnect)
                if settings.useAutoReconnect {
                    Stepper("Interval: \(settings.autoReconnectInterval) s", value: $settings.autoReconnectInterval, in: 5...3600, step: 5)
                    Toggle("Unlimited retries", isOn: $settings.unlimitedReconnectRetries)
                    if !settings.unlimitedReconnectRetries {
                        Stepper("Retries: \(settings.autoReconnectRetries)", value: $settings.autoReconnectRetries, in: 1...999)
                    }
                    Toggle("Rejoin channels", isOn: $settings.rejoinChannels)
                }
            }
            Section {
                TextEditor(text: $performText)
                    .font(.body.monospaced())
                    .frame(minHeight: 90)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
            } header: {
                Text("Commands on connect")
            } footer: {
                Text("One command per line, e.g. /msg NickServ identify …")
            }
            Section("Rate limit") {
                Toggle("Custom rate limits", isOn: $settings.useCustomMessageRate)
                if settings.useCustomMessageRate {
                    Toggle("Unlimited", isOn: $settings.unlimitedMessageRate)
                    if !settings.unlimitedMessageRate {
                        Stepper("Burst size: \(settings.messageRateBurstSize)", value: $settings.messageRateBurstSize, in: 1...100)
                        Stepper("Delay: \(settings.messageRateDelay) ms", value: $settings.messageRateDelay, in: 0...10000, step: 100)
                    }
                }
            }
            Section("Encodings") {
                TextField("Server encoding", text: $settings.codecForServer)
                TextField("Send encoding", text: $settings.codecForEncoding)
                TextField("Receive encoding", text: $settings.codecForDecoding)
            }
            if !isNew {
                Section {
                    if let n = session.networks[settings.networkId] {
                        if n.connectionState == .disconnected {
                            Button("Connect") { session.connectNetwork(n.id) }
                        } else {
                            Button("Disconnect") { session.disconnectNetwork(n.id) }
                        }
                    }
                    Button("Delete network", role: .destructive) { confirmDelete = true }
                }
            }
        }
        .navigationTitle(isNew ? "New network" : settings.networkName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    settings.perform = performText.split(separator: "\n").map(String.init)
                    if isNew {
                        session.createNetwork(settings, channels: channels.split(separator: " ").map(String.init))
                    } else {
                        session.updateNetwork(settings)
                    }
                    dismiss()
                }
                .disabled(settings.networkName.isEmpty || settings.servers.isEmpty)
            }
        }
        .onAppear { performText = settings.perform.joined(separator: "\n") }
        .sheet(item: Binding(get: { editingServer.map { IndexBox(value: $0) } }, set: { editingServer = $0?.value })) { box in
            NavigationStack {
                ServerEditView(server: settings.servers.indices.contains(box.value) ? settings.servers[box.value] : NetworkServer()) { s in
                    if settings.servers.indices.contains(box.value) { settings.servers[box.value] = s }
                }
            }
        }
        .confirmationDialog("Delete \(settings.networkName)?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                session.removeNetwork(settings.networkId)
                dismiss()
            }
        } message: {
            Text("All chats and history of this network will be deleted from the core.")
        }
    }
}

struct IndexBox: Identifiable {
    let value: Int
    var id: Int { value }
}

struct ServerEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var server: NetworkServer
    var onSave: (NetworkServer) -> Void
    @State private var port = ""
    @State private var proxyPort = ""

    var body: some View {
        Form {
            Section("Server") {
                TextField("Hostname", text: $server.host)
                    .textInputAutocapitalization(.never).autocorrectionDisabled().keyboardType(.URL)
                TextField("Port", text: $port).keyboardType(.numberPad)
                SecureField("Password", text: $server.password)
            }
            Section("Security") {
                Toggle("Use TLS", isOn: $server.useSSL)
                if server.useSSL { Toggle("Verify certificate", isOn: $server.sslVerify) }
            }
            Section("Proxy") {
                Toggle("Use proxy", isOn: $server.useProxy)
                if server.useProxy {
                    Picker("Type", selection: $server.proxyType) {
                        Text("SOCKS5").tag(1)
                        Text("HTTP").tag(3)
                    }
                    TextField("Host", text: $server.proxyHost)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("Port", text: $proxyPort).keyboardType(.numberPad)
                    TextField("User", text: $server.proxyUser)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    SecureField("Password", text: $server.proxyPass)
                }
            }
        }
        .navigationTitle("Server")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            port = String(server.port)
            proxyPort = String(server.proxyPort)
        }
        .onChange(of: server.useSSL) { _, ssl in
            if ssl && port == "6667" { port = "6697" } else if !ssl && port == "6697" { port = "6667" }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    server.port = Int(port) ?? 6697
                    server.proxyPort = Int(proxyPort) ?? 8080
                    onSave(server)
                    dismiss()
                }
                .disabled(server.host.isEmpty)
            }
        }
    }
}

// MARK: - Identities

struct IdentitiesListView: View {
    let session: CoreSession

    var body: some View {
        List {
            ForEach(session.sortedIdentities) { i in
                NavigationLink {
                    IdentityEditView(session: session, identity: i.settings, isNew: false)
                } label: {
                    VStack(alignment: .leading) {
                        Text(i.settings.identityName)
                        Text(i.settings.nicks.joined(separator: ", ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .navigationTitle("Identities")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { newIdentity() } label: { Image(systemName: "plus") }
            }
        }
    }
}

extension IdentitiesListView {
    func newIdentity() -> IdentityEditView {
        var s = IdentitySettings()
        s.identityName = "New identity"
        s.nicks = [session.sortedIdentities.first?.settings.nicks.first ?? "iquassel"]
        s.realName = session.sortedIdentities.first?.settings.realName ?? ""
        return IdentityEditView(session: session, identity: s, isNew: true)
    }
}

struct IdentityEditView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession
    @State var identity: IdentitySettings
    let isNew: Bool
    @State private var newNick = ""
    @State private var confirmDelete = false

    var body: some View {
        Form {
            Section("Identity") {
                TextField("Name", text: $identity.identityName)
                TextField("Real name", text: $identity.realName)
                TextField("Ident", text: $identity.ident)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Section {
                ForEach(identity.nicks.indices, id: \.self) { i in
                    TextField("Nick", text: Binding(get: { identity.nicks.indices.contains(i) ? identity.nicks[i] : "" },
                                                    set: { if identity.nicks.indices.contains(i) { identity.nicks[i] = $0 } }))
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                }
                .onDelete { identity.nicks.remove(atOffsets: $0) }
                .onMove { identity.nicks.move(fromOffsets: $0, toOffset: $1) }
                HStack {
                    TextField("Add nick", text: $newNick)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                    Button("Add") {
                        identity.nicks.append(newNick)
                        newNick = ""
                    }
                    .disabled(newNick.isEmpty)
                }
            } header: {
                Text("Nicknames")
            } footer: {
                Text("Tried in order when connecting.")
            }
            Section("Away") {
                Toggle("Away nick", isOn: $identity.awayNickEnabled)
                if identity.awayNickEnabled {
                    TextField("Away nick", text: $identity.awayNick).textInputAutocapitalization(.never)
                }
                Toggle("Default away reason", isOn: $identity.awayReasonEnabled)
                if identity.awayReasonEnabled { TextField("Away reason", text: $identity.awayReason) }
                Toggle("Away when all clients detach", isOn: $identity.detachAwayEnabled)
                if identity.detachAwayEnabled {
                    Toggle("Custom detach reason", isOn: $identity.detachAwayReasonEnabled)
                    if identity.detachAwayReasonEnabled { TextField("Reason", text: $identity.detachAwayReason) }
                }
            }
            Section("Messages") {
                TextField("Part reason", text: $identity.partReason)
                TextField("Quit reason", text: $identity.quitReason)
                TextField("Kick reason", text: $identity.kickReason)
            }
            if !isNew && session.identities.count > 1 {
                Section { Button("Delete identity", role: .destructive) { confirmDelete = true } }
            }
        }
        .navigationTitle(isNew ? "New identity" : identity.identityName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    identity.nicks.removeAll { $0.trimmingCharacters(in: .whitespaces).isEmpty }
                    if isNew { session.createIdentity(identity) } else { session.updateIdentity(identity) }
                    dismiss()
                }
                .disabled(identity.identityName.isEmpty || identity.nicks.allSatisfy { $0.isEmpty })
            }
        }
        .confirmationDialog("Delete identity?", isPresented: $confirmDelete) {
            Button("Delete", role: .destructive) {
                session.removeIdentity(identity.identityId)
                dismiss()
            }
        }
    }
}

// MARK: - Chat lists

struct ChatListsView: View {
    let session: CoreSession

    var body: some View {
        List {
            ForEach(session.sortedBufferViews) { v in
                NavigationLink { ChatListEditView(session: session, config: v, isNew: false) } label: {
                    VStack(alignment: .leading) {
                        Text(v.name)
                        Text("\(v.buffers.count) chats").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .onDelete { idx in
                for i in idx { session.deleteBufferView(session.sortedBufferViews[i].id) }
            }
            if session.bufferViews.isEmpty {
                Text("No chat lists yet. Without a chat list, all chats are shown.")
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Chat lists")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                NavigationLink { newChatList() } label: { Image(systemName: "plus") }
            }
        }
    }
}

extension ChatListsView {
    func newChatList() -> ChatListEditView {
        let v = BufferViewConfig(id: -1)
        v.name = session.bufferViews.isEmpty ? "All Chats" : "New chat list"
        v.buffers = session.buffers.values.filter { !$0.type.contains(.status) }.map { $0.bufferId }
        return ChatListEditView(session: session, config: v, isNew: true)
    }
}

struct ChatListEditView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession
    let config: BufferViewConfig
    let isNew: Bool

    @State private var name = ""
    @State private var networkId: NetworkId = 0
    @State private var channels = true
    @State private var queries = true
    @State private var status = true
    @State private var addNew = true
    @State private var sortAlpha = true
    @State private var hideInactive = false
    @State private var hideInactiveNetworks = false
    @State private var minimumActivity = 0

    var body: some View {
        Form {
            Section("Chat list") {
                TextField("Name", text: $name)
                Picker("Network", selection: $networkId) {
                    Text("All networks").tag(Int32(0))
                    ForEach(session.sortedNetworks) { n in Text(n.networkName).tag(n.id) }
                }
            }
            Section("Show") {
                Toggle("Channels", isOn: $channels)
                Toggle("Private chats", isOn: $queries)
                Toggle("Network status", isOn: $status)
                Picker("Minimum activity", selection: $minimumActivity) {
                    Text("Show all").tag(0)
                    Text("Other activity").tag(1)
                    Text("New messages").tag(2)
                    Text("Highlights").tag(4)
                }
            }
            Section("Behaviour") {
                Toggle("Add new chats automatically", isOn: $addNew)
                Toggle("Sort alphabetically", isOn: $sortAlpha)
                Toggle("Hide inactive chats", isOn: $hideInactive)
                Toggle("Hide inactive networks", isOn: $hideInactiveNetworks)
            }
        }
        .navigationTitle(isNew ? "New chat list" : config.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            name = config.name
            networkId = config.networkId
            channels = config.allowedBufferTypes.contains(.channel)
            queries = config.allowedBufferTypes.contains(.query)
            status = config.allowedBufferTypes.contains(.status)
            addNew = config.addNewBuffersAutomatically
            sortAlpha = config.sortAlphabetically
            hideInactive = config.hideInactiveBuffers
            hideInactiveNetworks = config.hideInactiveNetworks
            minimumActivity = config.minimumActivity
        }
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let target = isNew ? config : copy(config)
                    target.name = name
                    target.networkId = networkId
                    var types: BufferType = [.group]
                    if channels { types.insert(.channel) }
                    if queries { types.insert(.query) }
                    if status { types.insert(.status) }
                    target.allowedBufferTypes = types
                    target.addNewBuffersAutomatically = addNew
                    target.sortAlphabetically = sortAlpha
                    target.hideInactiveBuffers = hideInactive
                    target.hideInactiveNetworks = hideInactiveNetworks
                    target.minimumActivity = minimumActivity
                    if isNew { session.createBufferView(target) } else { session.updateBufferView(target) }
                    dismiss()
                }
                .disabled(name.isEmpty)
            }
        }
    }

    private func copy(_ c: BufferViewConfig) -> BufferViewConfig {
        let n = BufferViewConfig(id: c.id)
        n.applyInit(c.propertyMap)
        return n
    }
}

// MARK: - Ignore list

struct IgnoreListView: View {
    let session: CoreSession
    @State private var items: [IgnoreEntry] = []
    @State private var editing: IgnoreEntry?
    @State private var dirty = false

    var body: some View {
        List {
            ForEach(items) { e in
                Button { editing = e } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(e.rule).foregroundStyle(e.isActive ? .primary : .secondary)
                            Text(["Sender", "Message", "CTCP"][min(max(e.type, 0), 2)] + " · " +
                                 (e.strictness == 2 ? "Permanent" : "Dynamic") + " · " +
                                 ["Global", "Network", "Channel"][min(max(e.scope, 0), 2)])
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !e.isActive { Image(systemName: "pause.circle").foregroundStyle(.secondary) }
                    }
                }
                .foregroundStyle(.primary)
            }
            .onDelete { items.remove(atOffsets: $0); dirty = true }
        }
        .navigationTitle("Ignore list")
        .onAppear { if !dirty { items = session.ignoreListManager.ignoreList } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = IgnoreEntry() } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Save to core") { session.updateIgnoreList(items); dirty = false }
                    .disabled(!dirty)
            }
        }
        .sheet(item: $editing) { e in
            NavigationStack {
                IgnoreEditView(entry: e) { saved in
                    if let i = items.firstIndex(where: { $0.id == saved.id }) { items[i] = saved } else { items.append(saved) }
                    dirty = true
                }
            }
        }
    }
}

struct IgnoreEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var entry: IgnoreEntry
    var onSave: (IgnoreEntry) -> Void

    var body: some View {
        Form {
            TextField("Rule (e.g. nick!*@*)", text: $entry.rule)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Picker("Type", selection: $entry.type) {
                Text("Sender").tag(0); Text("Message").tag(1); Text("CTCP").tag(2)
            }
            Toggle("Regular expression", isOn: $entry.isRegEx)
            Picker("Strictness", selection: $entry.strictness) {
                Text("Dynamic (hide)").tag(1); Text("Permanent (drop)").tag(2)
            }
            Picker("Scope", selection: $entry.scope) {
                Text("Global").tag(0); Text("Network").tag(1); Text("Channel").tag(2)
            }
            if entry.scope != 0 {
                TextField("Scope rule", text: $entry.scopeRule)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            }
            Toggle("Active", isOn: $entry.isActive)
        }
        .navigationTitle("Ignore rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onSave(entry); dismiss() }.disabled(entry.rule.isEmpty)
            }
        }
    }
}

// MARK: - Highlight rules

struct HighlightRulesView: View {
    let session: CoreSession
    @State private var items: [HighlightRule] = []
    @State private var highlightNick = 0
    @State private var caseSensitive = false
    @State private var editing: HighlightRule?
    @State private var dirty = false

    var body: some View {
        List {
            Section("Highlight my nick") {
                Picker("Nick", selection: $highlightNick) {
                    Text("Current nick").tag(0); Text("All nicks of identity").tag(1); Text("None").tag(2)
                }
                .onChange(of: highlightNick) { _, _ in dirty = true }
                Toggle("Case sensitive", isOn: $caseSensitive)
                    .onChange(of: caseSensitive) { _, _ in dirty = true }
            }
            Section("Custom rules") {
                ForEach(items) { r in
                    Button { editing = r } label: {
                        VStack(alignment: .leading) {
                            Text(r.name).foregroundStyle(r.isEnabled ? .primary : .secondary)
                            if !r.channel.isEmpty || !r.sender.isEmpty {
                                Text([r.sender, r.channel].filter { !$0.isEmpty }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { items.remove(atOffsets: $0); dirty = true }
            }
        }
        .navigationTitle("Highlight rules")
        .onAppear {
            if !dirty {
                items = session.highlightRuleManager.highlightRules
                highlightNick = session.highlightRuleManager.highlightNick
                caseSensitive = session.highlightRuleManager.nicksCaseSensitive
                DispatchQueue.main.async { dirty = false }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) { Button { editing = HighlightRule() } label: { Image(systemName: "plus") } }
            ToolbarItem(placement: .bottomBar) {
                Button("Save to core") {
                    session.updateHighlightRules(items, highlightNick: highlightNick, caseSensitive: caseSensitive)
                    dirty = false
                }
                .disabled(!dirty)
            }
        }
        .sheet(item: $editing) { r in
            NavigationStack {
                HighlightEditView(rule: r) { saved in
                    if let i = items.firstIndex(where: { $0.id == saved.id }) { items[i] = saved } else { items.append(saved) }
                    dirty = true
                }
            }
        }
    }
}

struct HighlightEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var rule: HighlightRule
    var onSave: (HighlightRule) -> Void

    var body: some View {
        Form {
            TextField("Words or pattern", text: $rule.name)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Toggle("Regular expression", isOn: $rule.isRegEx)
            Toggle("Case sensitive", isOn: $rule.isCaseSensitive)
            Toggle("Enabled", isOn: $rule.isEnabled)
            Toggle("Inverse (exception)", isOn: $rule.isInverse)
            TextField("Only from sender", text: $rule.sender)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            TextField("Only in channel", text: $rule.channel)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
        }
        .navigationTitle("Highlight rule")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onSave(rule); dismiss() }.disabled(rule.name.isEmpty)
            }
        }
    }
}

// MARK: - Aliases

struct AliasesView: View {
    let session: CoreSession
    @State private var items: [AliasEntry] = []
    @State private var editing: AliasEntry?
    @State private var dirty = false

    var body: some View {
        List {
            ForEach(items) { a in
                Button { editing = a } label: {
                    VStack(alignment: .leading) {
                        Text("/" + a.name).font(.body.monospaced())
                        Text(a.expansion).font(.caption.monospaced()).foregroundStyle(.secondary).lineLimit(2)
                    }
                }
                .foregroundStyle(.primary)
            }
            .onDelete { items.remove(atOffsets: $0); dirty = true }
        }
        .navigationTitle("Aliases")
        .onAppear { if !dirty { items = session.aliasManager.aliases } }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { editing = AliasEntry(name: "", expansion: "") } label: { Image(systemName: "plus") }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Save to core") { session.updateAliases(items); dirty = false }.disabled(!dirty)
            }
        }
        .sheet(item: $editing) { a in
            NavigationStack {
                AliasEditView(alias: a) { saved in
                    if let i = items.firstIndex(where: { $0.id == saved.id }) { items[i] = saved } else { items.append(saved) }
                    dirty = true
                }
            }
        }
    }
}

struct AliasEditView: View {
    @Environment(\.dismiss) private var dismiss
    @State var alias: AliasEntry
    var onSave: (AliasEntry) -> Void

    var body: some View {
        Form {
            TextField("Name", text: $alias.name)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
            Section {
                TextEditor(text: $alias.expansion)
                    .font(.body.monospaced())
                    .frame(minHeight: 80)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
            } header: {
                Text("Expansion")
            } footer: {
                Text("Use $0 for all arguments, $1, $2… for single ones, $nick and $channel. Separate commands with ;")
            }
        }
        .navigationTitle("Alias")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { onSave(alias); dismiss() }.disabled(alias.name.isEmpty || alias.expansion.isEmpty)
            }
        }
    }
}

// MARK: - Core info / password

struct CoreInfoView: View {
    let session: CoreSession

    var body: some View {
        let data = session.coreInfo.data["coreData"]?.mapValue ?? [:]
        List {
            Section("Core") {
                LabeledContent("Version", value: stripHTML(data.str("quasselVersion", "unknown")))
                if let ts = Double(data.str("quasselBuildDate")) {
                    LabeledContent("Build date", value: Date(timeIntervalSince1970: ts).formatted(date: .abbreviated, time: .omitted))
                } else if !data.str("quasselBuildDate").isEmpty {
                    LabeledContent("Build date", value: data.str("quasselBuildDate"))
                }
                if let start = data["startTime"]?.dateValue {
                    LabeledContent("Up since", value: start.formatted(date: .abbreviated, time: .shortened))
                }
                LabeledContent("Address", value: "\(session.account.host):\(String(session.account.port))")
            }
            let clients = (data["sessionConnectedClientData"]?.listValue ?? []).map { $0.mapValue }
            Section("Connected clients (\(clients.count))") {
                ForEach(clients.indices, id: \.self) { i in
                    let c = clients[i]
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stripHTML(c.str("clientVersion"))).font(.subheadline)
                        Text(c.str("remoteAddress") + (c.bool("secure") ? " · encrypted" : " · unencrypted"))
                            .font(.caption).foregroundStyle(.secondary)
                        if let d = c["connectedSince"]?.dateValue {
                            Text("Since \(d.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Section("Negotiated features (\(session.coreFeatures.count))") {
                Text(session.coreFeatures.map { $0.rawValue }.sorted().joined(separator: ", "))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Core info")
    }

    private func stripHTML(_ s: String) -> String {
        s.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }
}

struct PasswordChangeView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession
    @State private var old = ""
    @State private var new1 = ""
    @State private var new2 = ""
    @State private var sent = false

    var body: some View {
        Form {
            SecureField("Current password", text: $old)
            SecureField("New password", text: $new1)
            SecureField("Repeat new password", text: $new2)
            if sent {
                if let ok = session.passwordChangeResult {
                    Text(ok ? "Password changed." : "The core rejected the password change.")
                        .foregroundStyle(ok ? .green : .red)
                } else {
                    ProgressView()
                }
            }
            Button("Change password") {
                session.changePassword(old: old, new: new1)
                sent = true
            }
            .disabled(old.isEmpty || new1.isEmpty || new1 != new2)
        }
        .navigationTitle("Change password")
        .onChange(of: session.passwordChangeResult) { _, ok in
            if ok == true { session.account.password = new1 }
        }
    }
}
