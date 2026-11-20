import SwiftUI

struct BufferInfoView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession
    let buffer: BufferInfo
    @State private var editingTopic = false
    @State private var newTopic = ""

    var body: some View {
        let net = session.networks[buffer.networkId]
        let chan = net?.channel(buffer.name)
        List {
            Section {
                LabeledContent("Name", value: session.bufferName(buffer))
                LabeledContent("Network", value: net?.networkName ?? "")
                LabeledContent("Type", value: typeName)
                if let c = chan {
                    LabeledContent("Users", value: "\(c.userModes.count)")
                    if !c.modeString.isEmpty { LabeledContent("Modes", value: c.modeString) }
                }
                if buffer.type.contains(.status), let n = net {
                    LabeledContent("State", value: n.connectionState.label)
                    LabeledContent("Server", value: n.currentServer)
                    LabeledContent("Nick", value: n.myNick)
                    if n.latency > 0 { LabeledContent("Lag", value: "\(n.latency) ms") }
                }
            }
            if let c = chan {
                Section("Topic") {
                    if c.topic.isEmpty {
                        Text("No topic set").foregroundStyle(.secondary)
                    } else {
                        Text(IrcFormat.attributed(c.topic, channelTypes: net?.channelTypes ?? "#"))
                            .textSelection(.enabled)
                    }
                    Button("Edit topic") {
                        newTopic = IrcFormat.strip(c.topic)
                        editingTopic = true
                    }
                }
            }
            Section {
                if buffer.type.contains(.channel) {
                    if session.isBufferActive(buffer) {
                        Button("Part channel") { session.part(buffer); dismiss() }
                    } else {
                        Button("Join channel") { session.joinChannel(buffer.networkId, buffer.name); dismiss() }
                    }
                }
                if buffer.type.contains(.status), let n = net {
                    if n.isConnected || n.connectionState != .disconnected {
                        Button("Disconnect network") { session.disconnectNetwork(n.id) }
                    } else {
                        Button("Connect network") { session.connectNetwork(n.id) }
                    }
                }
                Button("Mark as read") { session.markRead(buffer.bufferId) }
            }
        }
        .navigationTitle(session.bufferName(buffer))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        .alert("Topic", isPresented: $editingTopic) {
            TextField("Topic", text: $newTopic)
            Button("Set") { session.sendInput(buffer, "/topic \(buffer.name) \(newTopic)") }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var typeName: String {
        if buffer.type.contains(.status) { return "Network status" }
        if buffer.type.contains(.channel) { return "Channel" }
        if buffer.type.contains(.query) { return "Private chat" }
        return "Group"
    }
}

struct JoinChannelView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession
    @State private var network: NetworkId = 0
    @State private var channel = "#"
    @State private var password = ""
    @State private var nick = ""

    var body: some View {
        Form {
            Picker("Network", selection: $network) {
                ForEach(session.sortedNetworks) { n in
                    Text(n.networkName).tag(n.id)
                }
            }
            Section("Join channel") {
                TextField("#channel", text: $channel)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Key (optional)", text: $password)
                Button("Join") {
                    session.joinChannel(network, channel.trimmingCharacters(in: .whitespaces), password: password)
                    dismiss()
                }
                .disabled(channel.count < 2 || network == 0)
            }
            Section("Open private chat") {
                TextField("Nickname", text: $nick)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Open query") {
                    session.openQuery(network, nick: nick.trimmingCharacters(in: .whitespaces))
                    dismiss()
                }
                .disabled(nick.isEmpty || network == 0)
            }
        }
        .navigationTitle("Join")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear { if network == 0 { network = session.sortedNetworks.first?.id ?? 0 } }
    }
}

/// Searches the loaded history of a buffer (and loads more on demand).
struct SearchView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.chatTheme) private var theme
    let session: CoreSession
    let buffer: BufferInfo
    @State private var query = ""

    var body: some View {
        let store = session.store(for: buffer.bufferId)
        let results = query.count < 2 ? [] : store.messages.reversed().filter {
            IrcFormat.strip($0.content).localizedCaseInsensitiveContains(query)
                || $0.senderNick.localizedCaseInsensitiveContains(query)
        }
        List {
            ForEach(results) { m in
                VStack(alignment: .leading, spacing: 2) {
                    Text(m.time.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption).foregroundStyle(.secondary)
                    Text(MessageRenderer(theme: theme, settings: AppSettings.shared,
                                         network: session.networks[buffer.networkId]).render(m))
                }
            }
            Section {
                if store.reachedStart {
                    Text("Searched all \(store.messages.count) messages").font(.footnote).foregroundStyle(.secondary)
                } else {
                    Button(store.loading ? "Loading…" : "Search older messages (\(store.messages.count) loaded)") {
                        session.loadMoreBacklog(buffer.bufferId)
                    }
                    .disabled(store.loading)
                }
            }
        }
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Search \(session.bufferName(buffer))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
    }
}

/// First-run wizard for an unconfigured core.
struct CoreSetupView: View {
    @Environment(\.dismiss) private var dismiss
    let session: CoreSession
    @State private var user = ""
    @State private var password = ""
    @State private var password2 = ""
    @State private var backend = ""
    @State private var fields: [String: String] = [:]

    private var backends: [[String: QVariant]] { session.storageBackends }

    private var selected: [String: QVariant]? {
        backends.first { ($0["BackendId"]?.text ?? $0.str("DisplayName")) == backend }
    }

    var body: some View {
        Form {
            Section {
                Text("This core has not been configured yet. Create the administrator account and choose a storage backend.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Section("Administrator") {
                TextField("Username", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
                SecureField("Repeat password", text: $password2)
            }
            Section("Storage backend") {
                Picker("Backend", selection: $backend) {
                    ForEach(backends.indices, id: \.self) { i in
                        let b = backends[i]
                        Text(b.str("DisplayName")).tag(b["BackendId"]?.text ?? b.str("DisplayName"))
                    }
                }
                if let b = selected {
                    Text(b.str("Description")).font(.footnote).foregroundStyle(.secondary)
                    ForEach(setupFields(b), id: \.key) { f in
                        TextField(f.label, text: Binding(get: { fields[f.key] ?? f.def }, set: { fields[f.key] = $0 }))
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
            }
            if let e = session.setupError {
                Section { Text(e).foregroundStyle(.red) }
            }
            Section {
                Button("Configure core") {
                    var props = [String: QVariant]()
                    if let b = selected {
                        for f in setupFields(b) {
                            let v = fields[f.key] ?? f.def
                            props[f.key] = f.isInt ? .int(Int32(v) ?? 0) : .str(v)
                        }
                    }
                    session.setupCore(adminUser: user, password: password, backend: backend, properties: props)
                }
                .disabled(user.isEmpty || password.isEmpty || password != password2 || backend.isEmpty)
            }
        }
        .navigationTitle("Core setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        .onAppear {
            user = session.account.user
            if backend.isEmpty {
                let def = backends.first { $0.bool("IsDefault") } ?? backends.first
                backend = def.map { $0["BackendId"]?.text ?? $0.str("DisplayName") } ?? "SQLite"
            }
        }
        .onChange(of: session.phase) { _, p in
            if p != .needsSetup && p.isActive { dismiss() }
        }
    }

    private struct Field { let key: String; let label: String; let def: String; let isInt: Bool }

    private func setupFields(_ b: [String: QVariant]) -> [Field] {
        // Newer cores send "SetupData" (list of maps), older ones "SetupKeys" + "SetupDefaults".
        let data = b["SetupData"]?.listValue ?? []
        if !data.isEmpty {
            return data.map { v in
                let m = v.mapValue
                let def = m["DefaultValue"] ?? .invalid
                var isInt = false
                if case .int = def { isInt = true }
                if case .uint = def { isInt = true }
                return Field(key: m.str("FieldName"), label: m.str("DisplayName", m.str("FieldName")),
                             def: def.text, isInt: isInt)
            }
        }
        let defaults = b["SetupDefaults"]?.mapValue ?? [:]
        return (b["SetupKeys"]?.stringListValue ?? []).map { k in
            let def = defaults[k] ?? .invalid
            var isInt = false
            if case .int = def { isInt = true }
            return Field(key: k, label: k, def: def.text, isInt: isInt)
        }
    }
}
