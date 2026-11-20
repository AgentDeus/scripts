import SwiftUI

/// List of saved cores ("accounts"), like the Android client's account selection screen.
struct AccountsView: View {
    @Environment(SessionManager.self) private var manager
    @Environment(\.chatTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    var isSheet = false
    @State private var editing: Account?
    @State private var creating = false
    @State private var deleting: Account?

    var body: some View {
        List {
            if manager.store.accounts.isEmpty {
                Section {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Welcome to iQuasselCC")
                            .font(.title3.bold())
                        Text("iQuasselCC is a Quassel Core Client – not a stand-alone IRC client. Add the Quassel core you want to connect to.")
                            .foregroundStyle(.secondary)
                        Button {
                            creating = true
                        } label: {
                            Label("Add core", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)
                        .padding(.top, 4)
                    }
                    .padding(.vertical, 8)
                }
            }
            Section(manager.store.accounts.isEmpty ? "" : "Cores") {
                ForEach(manager.store.accounts) { a in
                    AccountRow(account: a, session: manager.sessions[a.id],
                               isActive: manager.activeSessionId == a.id)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            manager.connect(a)
                            if isSheet { dismiss() }
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) { deleting = a } label: { Label("Delete", systemImage: "trash") }
                            Button { editing = a } label: { Label("Edit", systemImage: "pencil") }
                                .tint(.orange)
                        }
                        .swipeActions(edge: .leading) {
                            if manager.sessions[a.id] != nil {
                                Button { manager.disconnect(a.id) } label: {
                                    Label("Disconnect", systemImage: "bolt.slash")
                                }
                                .tint(.gray)
                            } else {
                                Button { manager.connect(a, activate: false) } label: {
                                    Label("Connect", systemImage: "bolt")
                                }
                                .tint(.green)
                            }
                        }
                        .contextMenu {
                            Button { manager.connect(a) } label: { Label("Open", systemImage: "bubble.left.and.bubble.right") }
                            if manager.sessions[a.id] != nil {
                                Button { manager.disconnect(a.id) } label: { Label("Disconnect", systemImage: "bolt.slash") }
                            } else {
                                Button { manager.connect(a, activate: false) } label: {
                                    Label("Connect in background", systemImage: "bolt")
                                }
                            }
                            Button { editing = a } label: { Label("Edit", systemImage: "pencil") }
                            Button(role: .destructive) { deleting = a } label: { Label("Delete", systemImage: "trash") }
                        }
                }
            }
            Section {
                Text("You can stay connected to several cores at once. Swipe right on a core to connect it in the background, then switch between cores from the chat list drawer.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("iQuasselCC")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { creating = true } label: { Image(systemName: "plus") }
            }
            if isSheet {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            } else if manager.activeSession == nil, !manager.sessions.isEmpty {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Chats") { manager.activeSessionId = manager.sessions.keys.first }
                }
            }
        }
        .sheet(isPresented: $creating) {
            NavigationStack { AccountEditView(account: Account(), isNew: true) }
        }
        .sheet(item: $editing) { a in
            NavigationStack { AccountEditView(account: a, isNew: false) }
        }
        .confirmationDialog("Delete \(deleting?.displayName ?? "")?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Delete", role: .destructive) {
                if let d = deleting { manager.remove(d) }
                deleting = nil
            }
        } message: {
            Text("This only removes the core from this device. Nothing on the core is changed.")
        }
    }
}

private struct AccountRow: View {
    let account: Account
    let session: CoreSession?
    let isActive: Bool
    @Environment(\.chatTheme) private var theme

    var statusColor: Color {
        guard let s = session else { return .gray }
        switch s.phase {
        case .connected: return .green
        case .failed: return .red
        case .disconnected: return .gray
        default: return .orange
        }
    }

    var statusText: String {
        guard let s = session else { return "Not connected" }
        return phaseLabel(s.phase)
    }

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Image(systemName: "server.rack")
                    .font(.title2)
                    .frame(width: 40, height: 40)
                    .background(theme.primary.opacity(0.15), in: Circle())
                    .foregroundStyle(theme.primary)
                Circle().fill(statusColor).frame(width: 11, height: 11)
                    .overlay(Circle().stroke(Color(.systemBackground), lineWidth: 2))
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack {
                    Text(account.displayName).font(.headline)
                    if isActive { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.primary).font(.caption) }
                }
                Text("\(account.user)@\(account.host):\(String(account.port))")
                    .font(.subheadline).foregroundStyle(.secondary)
                Text(statusText).font(.caption).foregroundStyle(statusColor)
            }
            Spacer()
            if account.requireTLS {
                Image(systemName: account.trustedFingerprint == nil ? "lock" : "lock.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

func phaseLabel(_ p: ConnectionPhase) -> String {
    switch p {
    case .disconnected: return "Disconnected"
    case .connecting: return "Connecting…"
    case .negotiating: return "Negotiating protocol…"
    case .awaitingCertificateDecision: return "Waiting for certificate approval"
    case .handshaking: return "Handshake…"
    case .needsSetup: return "Core needs setup"
    case .loggingIn: return "Logging in…"
    case .initializing: return "Synchronizing…"
    case .connected: return "Connected"
    case .failed(let r): return r
    }
}

struct AccountEditView: View {
    @Environment(SessionManager.self) private var manager
    @Environment(\.dismiss) private var dismiss
    @State var account: Account
    let isNew: Bool
    @State private var password = ""
    @State private var portText = ""

    var body: some View {
        Form {
            Section("Core") {
                TextField("Name (optional)", text: $account.name)
                TextField("Hostname", text: $account.host)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                TextField("Port", text: $portText)
                    .keyboardType(.numberPad)
                Toggle("Require encryption (TLS)", isOn: $account.requireTLS)
            }
            Section("Login") {
                TextField("Username", text: $account.user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                SecureField("Password", text: $password)
            }
            Section("Behaviour") {
                Toggle("Connect automatically", isOn: $account.autoConnect)
            }
            if let fp = account.trustedFingerprint {
                Section {
                    Text(fp).font(.caption.monospaced()).textSelection(.enabled)
                    Button("Forget trusted certificate", role: .destructive) { account.trustedFingerprint = nil }
                } header: {
                    Text("Trusted certificate (SHA-256)")
                }
            }
        }
        .navigationTitle(isNew ? "Add core" : "Edit core")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            password = isNew ? "" : account.password
            portText = String(account.port)
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    account.port = Int(portText) ?? 4242
                    account.host = account.host.trimmingCharacters(in: .whitespaces)
                    manager.store.upsert(account)
                    account.password = password
                    if let s = manager.sessions[account.id] { s.account = account }
                    dismiss()
                }
                .disabled(account.host.isEmpty || account.user.isEmpty)
            }
        }
    }
}
