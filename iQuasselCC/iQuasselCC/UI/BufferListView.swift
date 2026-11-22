import SwiftUI

/// Left drawer: core switcher, chat list (buffer view) selector and the buffers grouped by network.
struct BufferListView: View {
    @Environment(SessionManager.self) private var manager
    @Environment(\.chatTheme) private var theme
    let session: CoreSession
    var onSelect: (BufferInfo) -> Void
    var onAction: (ChatSheet) -> Void

    @State private var filter = ""
    @State private var collapsed = Set<NetworkId>()
    @State private var showHidden = false
    @State private var renaming: BufferInfo?
    @State private var renameText = ""
    @State private var deleting: BufferInfo?

    private var view: BufferViewConfig? {
        if let id = manager.selectedView[session.id], let v = session.bufferViews[id] { return v }
        return session.sortedBufferViews.first
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField
            List {
                ForEach(visibleNetworks) { net in
                    networkSection(net)
                }
                if hiddenBuffers.count > 0 {
                    Section {
                        Button {
                            showHidden.toggle()
                        } label: {
                            Label(showHidden ? "Hide hidden chats" : "Show hidden chats (\(hiddenBuffers.count))",
                                  systemImage: showHidden ? "eye.slash" : "eye")
                                .font(.footnote)
                        }
                        if showHidden {
                            ForEach(hiddenBuffers, id: \.bufferId) { b in
                                HStack {
                                    Text(session.bufferName(b)).foregroundStyle(theme.inactive)
                                    Spacer()
                                    Text(session.networks[b.networkId]?.networkName ?? "")
                                        .font(.caption).foregroundStyle(theme.secondaryText)
                                }
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(b) }
                                .swipeActions {
                                    if let v = view {
                                        Button("Unhide") { session.unhideBuffer(b.bufferId, in: v.id) }.tint(.green)
                                    }
                                }
                                .contextMenu {
                                    if let v = view {
                                        Button { session.unhideBuffer(b.bufferId, in: v.id) } label: {
                                            Label("Unhide", systemImage: "eye")
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .listRowBackground(theme.surface)
                }
                if session.isConnected && session.networks.isEmpty {
                    Section {
                        Text("This core has no networks yet.")
                            .foregroundStyle(theme.secondaryText)
                        Button { onAction(.coreSettings) } label: { Label("Add network", systemImage: "plus") }
                    }
                    .listRowBackground(theme.surface)
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .environment(\.defaultMinListRowHeight, 34)
            footer
        }
        .background(theme.surface)
        .alert("Rename chat", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let r = renaming { session.renameBuffer(r.bufferId, to: renameText) }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog("Delete \(deleting.map { session.bufferName($0) } ?? "")?",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            titleVisibility: .visible) {
            Button("Delete chat and its history", role: .destructive) {
                if let d = deleting { session.deleteBuffer(d.bufferId) }
                deleting = nil
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Menu {
                ForEach(manager.store.accounts) { a in
                    Button {
                        manager.connect(a)
                    } label: {
                        if manager.sessions[a.id] != nil {
                            Label(a.displayName, systemImage: a.id == session.id ? "checkmark.circle.fill" : "bolt.fill")
                        } else {
                            Text(a.displayName)
                        }
                    }
                }
                Divider()
                Button { onAction(.accounts) } label: { Label("Manage cores…", systemImage: "rectangle.stack") }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack")
                        .font(.title3)
                        .frame(width: 38, height: 38)
                        .background(.white.opacity(0.18), in: Circle())
                    VStack(alignment: .leading, spacing: 1) {
                        Text(session.account.displayName).font(.headline).lineLimit(1)
                        Text(session.isConnected ? "\(session.account.user)@\(session.account.host)" : phaseLabel(session.phase))
                            .font(.caption).opacity(0.85).lineLimit(1)
                    }
                    Spacer()
                    if manager.sessions.count > 1 {
                        Text("\(manager.sessions.count)")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(.white.opacity(0.25), in: Capsule())
                    }
                    Image(systemName: "chevron.up.chevron.down").font(.caption)
                }
                .foregroundStyle(theme.onPrimary)
            }

            if !session.bufferViews.isEmpty {
                Menu {
                    ForEach(session.sortedBufferViews) { v in
                        Button {
                            manager.selectedView[session.id] = v.id
                        } label: {
                            if v.id == view?.id { Label(v.name, systemImage: "checkmark") } else { Text(v.name) }
                        }
                    }
                    Divider()
                    Button { onAction(.coreSettings) } label: { Label("Edit chat lists…", systemImage: "list.bullet") }
                } label: {
                    HStack {
                        Image(systemName: "list.bullet")
                        Text(view?.name ?? "All Chats").font(.subheadline.weight(.medium))
                        Image(systemName: "chevron.down").font(.caption2)
                        Spacer()
                    }
                    .foregroundStyle(theme.onPrimary.opacity(0.9))
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
        .padding(.bottom, 10)
        .background(theme.primary.ignoresSafeArea(edges: .top))
    }

    private var searchField: some View {
        HStack {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryText)
            TextField("Filter chats", text: $filter)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            if !filter.isEmpty {
                Button { filter = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .foregroundStyle(theme.secondaryText)
            }
        }
        .padding(8)
        .background(theme.surfaceVariant, in: RoundedRectangle(cornerRadius: 8))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    private var footer: some View {
        HStack {
            Button { onAction(.joinChannel) } label: { Label("Join", systemImage: "plus.bubble") }
            Spacer()
            Button { onAction(.coreSettings) } label: { Image(systemName: "server.rack") }
            Button { onAction(.settings) } label: { Image(systemName: "gearshape") }
                .padding(.leading, 14)
        }
        .font(.subheadline)
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(theme.surfaceVariant.ignoresSafeArea(edges: .bottom))
    }

    // MARK: Data

    private var visibleNetworks: [Network] {
        session.sortedNetworks.filter { net in
            if let v = view {
                if v.networkId != 0 && v.networkId != net.id { return false }
                if v.hideInactiveNetworks && !net.isConnected { return false }
            }
            return true
        }
    }

    private func inView(_ b: BufferInfo) -> Bool {
        guard let v = view else { return true }
        if v.networkId != 0 && v.networkId != b.networkId { return false }
        if v.buffers.contains(b.bufferId) { return true }
        // New chats show up right away, even before the core confirms adding them to the list.
        return v.addNewBuffersAutomatically && !v.removedBuffers.contains(b.bufferId)
            && !v.temporarilyRemovedBuffers.contains(b.bufferId)
    }

    private var hiddenBuffers: [BufferInfo] {
        guard let v = view else { return [] }
        return session.buffers.values
            .filter { v.temporarilyRemovedBuffers.contains($0.bufferId) || v.removedBuffers.contains($0.bufferId) }
            .filter { v.networkId == 0 || v.networkId == $0.networkId }
            .sorted { session.bufferName($0).lowercased() < session.bufferName($1).lowercased() }
    }

    private func buffers(for net: Network) -> [BufferInfo] {
        var list = session.buffers.values.filter { $0.networkId == net.id && !$0.type.contains(.status) && inView($0) }
        if let v = view {
            if !v.allowedBufferTypes.isEmpty {
                list = list.filter { !v.allowedBufferTypes.intersection($0.type).isEmpty }
            }
            if v.hideInactiveBuffers || AppSettings.shared.hideInactiveBuffersLocally {
                list = list.filter { session.isBufferActive($0) || (session.bufferSyncer.highlightCounts[$0.bufferId] ?? 0) > 0 }
            }
            if v.minimumActivity > 0 {
                list = list.filter { session.activity($0.bufferId).rawValue >= UInt32(v.minimumActivity) || $0.bufferId == manager.selectedBuffer[session.id] }
            }
        } else if AppSettings.shared.hideInactiveBuffersLocally {
            list = list.filter { session.isBufferActive($0) }
        }
        if !filter.isEmpty {
            list = list.filter { $0.name.localizedCaseInsensitiveContains(filter) }
        }
        if let v = view, !v.sortAlphabetically {
            let order = Dictionary(v.buffers.enumerated().map { ($1, $0) }, uniquingKeysWith: { a, _ in a })
            return list.sorted { (order[$0.bufferId] ?? .max) < (order[$1.bufferId] ?? .max) }
        }
        func key(_ b: BufferInfo) -> String {
            let n = b.name.lowercased()
            return String(n.drop(while: { "#&!+".contains($0) }))
        }
        return list.sorted {
            let c = $0.type.contains(.channel), d = $1.type.contains(.channel)
            if c != d { return c }
            return key($0) < key($1)
        }
    }

    @ViewBuilder private func networkSection(_ net: Network) -> some View {
        let items = buffers(for: net)
        let status = session.statusBuffer(for: net.id)
        Section {
            if !collapsed.contains(net.id) {
                ForEach(items, id: \.bufferId) { b in
                    bufferRow(b)
                }
            }
        } header: {
            HStack(spacing: 8) {
                Image(systemName: collapsed.contains(net.id) ? "chevron.right" : "chevron.down")
                    .font(.caption2)
                    .frame(width: 12)
                    .onTapGesture { toggle(net.id) }
                Circle()
                    .fill(net.isConnected ? Color.green : (net.connectionState == .disconnected ? Color.gray : .orange))
                    .frame(width: 7, height: 7)
                Text(net.networkName)
                    .font(.subheadline.bold())
                    .foregroundStyle(statusColor(status, network: net))
                Spacer()
                if let s = status, let count = session.bufferSyncer.highlightCounts[s.bufferId], count > 0 {
                    badge(count)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if let s = status { onSelect(s) } else { toggle(net.id) }
            }
            .contextMenu {
                if net.isConnected || net.connectionState != .disconnected {
                    Button { session.disconnectNetwork(net.id) } label: { Label("Disconnect", systemImage: "bolt.slash") }
                } else {
                    Button { session.connectNetwork(net.id) } label: { Label("Connect", systemImage: "bolt") }
                }
                Button { onAction(.joinChannel) } label: { Label("Join channel", systemImage: "plus.bubble") }
                Button { toggle(net.id) } label: {
                    Label(collapsed.contains(net.id) ? "Expand" : "Collapse", systemImage: "rectangle.compress.vertical")
                }
            }
            .padding(.vertical, 4)
            .textCase(nil)
        }
        .listRowBackground(theme.surface)
        .listRowSeparator(.hidden)
    }

    private func toggle(_ id: NetworkId) {
        if collapsed.contains(id) { collapsed.remove(id) } else { collapsed.insert(id) }
    }

    private func statusColor(_ b: BufferInfo?, network: Network) -> Color {
        guard network.isConnected else { return theme.inactive }
        guard let b = b else { return theme.text }
        return activityColor(b) ?? theme.text
    }

    private func activityColor(_ b: BufferInfo) -> Color? {
        if (session.bufferSyncer.highlightCounts[b.bufferId] ?? 0) > 0 { return theme.activityHighlight }
        let a = session.activity(b.bufferId)
        if !a.intersection(.conversation).isEmpty { return theme.activityMessage }
        if !a.isEmpty { return theme.activityOther }
        return nil
    }

    private func badge(_ n: Int) -> some View {
        Text("\(n)")
            .font(.caption2.bold())
            .foregroundStyle(.black)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(theme.activityHighlight, in: Capsule())
    }

    @ViewBuilder private func bufferRow(_ b: BufferInfo) -> some View {
        let active = session.isBufferActive(b)
        let selected = manager.selectedBuffer[session.id] == b.bufferId
        let net = session.networks[b.networkId]
        let user = b.type.contains(.query) ? net?.user(b.name) : nil
        HStack(spacing: 10) {
            Image(systemName: b.type.contains(.channel) ? "number" : (b.type.contains(.query) ? "person.fill" : "bubble.left"))
                .font(.caption)
                .frame(width: 22, height: 22)
                .foregroundStyle(active ? theme.onPrimary : theme.secondaryText)
                .background(active ? (user?.away == true ? theme.inactive : theme.nickColor(b.name, isSelf: false, mode: .all)) : theme.surfaceVariant,
                            in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                Text(b.name)
                    .lineLimit(1)
                    .foregroundStyle(active ? (activityColor(b) ?? theme.text) : theme.inactive)
                    .fontWeight((session.activity(b.bufferId).intersection(.conversation).isEmpty) ? .regular : .semibold)
                if b.type.contains(.channel), let c = net?.channel(b.name), !c.topic.isEmpty {
                    Text(IrcFormat.strip(c.topic))
                        .font(.caption)
                        .lineLimit(1)
                        .foregroundStyle(theme.secondaryText)
                }
            }
            Spacer()
            if let n = session.bufferSyncer.highlightCounts[b.bufferId], n > 0 {
                badge(n)
            }
        }
        .padding(.leading, 16)
        .contentShape(Rectangle())
        .onTapGesture { onSelect(b) }
        .listRowBackground(selected ? theme.primary.opacity(0.15) : theme.surface)
        .listRowSeparator(.hidden)
        .swipeActions(edge: .trailing) {
            if let v = view {
                Button { session.hideBuffer(b.bufferId, in: v.id, permanently: false) } label: {
                    Label("Hide", systemImage: "eye.slash")
                }
                .tint(.gray)
            }
            if b.type.contains(.channel) {
                if active {
                    Button { session.part(b) } label: { Label("Part", systemImage: "arrow.left.square") }.tint(.orange)
                } else {
                    Button { session.joinChannel(b.networkId, b.name) } label: { Label("Join", systemImage: "arrow.right.square") }
                        .tint(.green)
                }
            }
        }
        .swipeActions(edge: .leading) {
            Button { session.markRead(b.bufferId) } label: { Label("Read", systemImage: "checkmark") }.tint(.blue)
        }
        .contextMenu {
            if b.type.contains(.channel) {
                if active {
                    Button { session.part(b) } label: { Label("Part", systemImage: "arrow.left.square") }
                } else {
                    Button { session.joinChannel(b.networkId, b.name) } label: { Label("Join", systemImage: "arrow.right.square") }
                }
            }
            Button { session.markRead(b.bufferId) } label: { Label("Mark as read", systemImage: "checkmark.circle") }
            if let v = view {
                Button { session.hideBuffer(b.bufferId, in: v.id, permanently: false) } label: {
                    Label("Hide temporarily", systemImage: "eye.slash")
                }
                Button { session.hideBuffer(b.bufferId, in: v.id, permanently: true) } label: {
                    Label("Hide permanently", systemImage: "eye.slash.fill")
                }
            }
            if b.type.contains(.query) {
                Button { renameText = b.name; renaming = b } label: { Label("Rename", systemImage: "pencil") }
            }
            if !active {
                Button(role: .destructive) { deleting = b } label: { Label("Delete", systemImage: "trash") }
            }
            Button { onAction(.bufferInfo(b.bufferId)) } label: { Label("Info", systemImage: "info.circle") }
        }
    }
}
