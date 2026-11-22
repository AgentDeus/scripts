import Foundation
import Observation

@Observable
final class BufferMessages {
    var messages: [IrcMessage] = []
    var loading = false
    var reachedStart = false
    var initialLoaded = false

    /// Maximum messages kept in memory per chat. Older history is not loaded beyond this.
    static let maxKept = 2000
    /// The oldest message id we already asked the core about (prevents re-requesting the same page).
    @ObservationIgnored var requestedBefore: MsgId?

    var isFull: Bool { messages.count >= Self.maxKept }

    func merge(_ new: [IrcMessage]) {
        guard !new.isEmpty else { return }
        var byId = [MsgId: IrcMessage](minimumCapacity: messages.count + new.count)
        for m in messages { byId[m.msgId] = m }
        for m in new { byId[m.msgId] = m }
        var sorted = byId.values.sorted { $0.msgId < $1.msgId }
        // Trim only from the old end and never below what was just loaded as history,
        // otherwise "load more" would fetch the same page again forever.
        if sorted.count > Self.maxKept + 500 { sorted.removeFirst(sorted.count - Self.maxKept - 500) }
        messages = sorted
    }

    func append(_ m: IrcMessage) {
        if let last = messages.last, last.msgId >= m.msgId {
            if !messages.contains(where: { $0.msgId == m.msgId }) { merge([m]) }
        } else {
            messages.append(m)
            if messages.count > Self.maxKept + 500 {
                messages.removeFirst(messages.count - Self.maxKept)
                reachedStart = false
            }
        }
    }

    /// Drop old messages of chats that are not on screen to keep memory and diffing cheap.
    func shrink(to n: Int) {
        guard messages.count > n else { return }
        messages.removeFirst(messages.count - n)
        reachedStart = false
        requestedBefore = nil
    }
}

/// Live state of one connected Quassel core.
@Observable
final class CoreSession: Identifiable, CoreConnectionDelegate {
    let id: UUID
    var account: Account

    var phase: ConnectionPhase = .disconnected
    var lastError: String?
    var setupError: String?
    var storageBackends: [[String: QVariant]] = []
    var authenticators: [[String: QVariant]] = []
    var coreFeatures: Set<QuasselFeature> = []
    var coreFeatureNames: [String] = []

    var networks: [NetworkId: Network] = [:]
    var buffers: [BufferId: BufferInfo] = [:]
    var identities: [IdentityId: Identity] = [:]
    var bufferViews: [Int32: BufferViewConfig] = [:]
    var bufferViewIdsLoaded = false
    let bufferSyncer = BufferSyncer()
    let aliasManager = MapSyncObject(className: "AliasManager")
    let ignoreListManager = MapSyncObject(className: "IgnoreListManager")
    let highlightRuleManager = MapSyncObject(className: "HighlightRuleManager")
    let coreInfo = MapSyncObject(className: "CoreInfo")
    /// Not observed: the stores are observable themselves, and creating one while a view renders
    /// must not invalidate every other view.
    @ObservationIgnored var messageStores: [BufferId: BufferMessages] = [:]
    var statusMessage: String?
    var passwordChangeResult: Bool?

    /// Buffer currently on screen (for read markers and notifications).
    @ObservationIgnored var visibleBuffer: BufferId?

    @ObservationIgnored private var link: CoreConnection?
    @ObservationIgnored private var reconnectAttempts = 0
    @ObservationIgnored private var reconnectWork: DispatchWorkItem?
    @ObservationIgnored private var userDisconnected = false
    @ObservationIgnored var onCertificateAccepted: ((String) -> Void)?

    init(account: Account) {
        self.id = account.id
        self.account = account
    }

    var isConnected: Bool { phase == .connected }

    var sortedNetworks: [Network] {
        networks.values.sorted { $0.networkName.localizedCaseInsensitiveCompare($1.networkName) == .orderedAscending }
    }

    var sortedIdentities: [Identity] { identities.values.sorted { $0.id < $1.id } }

    var sortedBufferViews: [BufferViewConfig] {
        bufferViews.values.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func store(for buffer: BufferId) -> BufferMessages {
        if let s = messageStores[buffer] { return s }
        let s = BufferMessages()
        messageStores[buffer] = s
        return s
    }

    // MARK: - Connection lifecycle

    func connect() {
        reconnectWork?.cancel()
        userDisconnected = false
        link?.delegate = nil
        link?.disconnect()
        resetState()
        let cfg = CoreConnection.Config(host: account.host, port: account.port, user: account.user,
                                        password: account.password, useTLS: account.requireTLS,
                                        trustedFingerprint: account.trustedFingerprint)
        let c = CoreConnection(config: cfg)
        c.delegate = self
        link = c
        lastError = nil
        c.connect()
    }

    func disconnect() {
        userDisconnected = true
        reconnectWork?.cancel()
        link?.delegate = nil
        link?.disconnect()
        link = nil
        phase = .disconnected
    }

    /// Called when the app returns to foreground.
    func ensureConnected() {
        if userDisconnected { return }
        switch phase {
        case .disconnected, .failed: connect()
        default: break
        }
    }

    @ObservationIgnored private var requestedViewAdds = Set<String>()

    /// Like the official clients: chats that are not in a chat list yet (e.g. a private chat someone
    /// opened while no client was connected) are added to lists that add new chats automatically,
    /// and temporarily hidden chats with new messages come back.
    func syncBuffersIntoViews() {
        for v in bufferViews.values where v.initialized {
            for b in buffers.values {
                if v.networkId != 0 && v.networkId != b.networkId { continue }
                if !v.allowedBufferTypes.isEmpty && v.allowedBufferTypes.intersection(b.type).isEmpty { continue }
                if v.buffers.contains(b.bufferId) || v.removedBuffers.contains(b.bufferId) { continue }
                let key = "\(v.id)/\(b.bufferId)"
                if requestedViewAdds.contains(key) { continue }
                if v.temporarilyRemovedBuffers.contains(b.bufferId) {
                    let act = bufferSyncer.activities[b.bufferId] ?? []
                    guard !act.intersection(.conversation).isEmpty else { continue }
                } else if !v.addNewBuffersAutomatically {
                    continue
                }
                requestedViewAdds.insert(key)
                syncView(v.id, "requestAddBuffer", [.bufferId(b.bufferId), .int(Int32(v.buffers.count))])
            }
        }
    }

    private func resetState() {
        requestedViewAdds = []
        networks = [:]
        buffers = [:]
        identities = [:]
        bufferViews = [:]
        bufferViewIdsLoaded = false
        // Keep message caches so that reconnecting is cheap; they are refreshed from the backlog.
        for s in messageStores.values { s.initialLoaded = false; s.loading = false }
    }

    private func scheduleReconnect() {
        guard !userDisconnected, account.autoConnect else { return }
        reconnectAttempts += 1
        let delay = min(60.0, pow(2.0, Double(min(reconnectAttempts, 6))))
        let work = DispatchWorkItem { [weak self] in self?.connect() }
        reconnectWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    func acceptCertificate(_ info: CoreCertificateInfo, permanently: Bool) {
        if permanently {
            account.trustedFingerprint = info.sha256
            onCertificateAccepted?(info.sha256)
        }
        link?.resolveCertificate(accept: true)
    }

    func rejectCertificate() {
        userDisconnected = true
        link?.resolveCertificate(accept: false)
    }

    func setupCore(adminUser: String, password: String, backend: String, properties: [String: QVariant]) {
        setupError = nil
        link?.sendSetup(adminUser: adminUser, password: password, backend: backend,
                              backendProperties: properties, authenticator: "Database", authProperties: [:])
    }

    // MARK: - CoreConnectionDelegate

    func connection(_ c: CoreConnection, phaseChanged phase: ConnectionPhase) {
        guard c === link else { return }
        self.phase = phase
        switch phase {
        case .failed(let reason):
            lastError = reason
            scheduleReconnect()
        case .connected:
            reconnectAttempts = 0
        default: break
        }
    }

    func connection(_ c: CoreConnection, initAck: [String: QVariant]) {
        coreFeatures = c.features
        coreFeatureNames = c.coreFeatureList
        storageBackends = (initAck["StorageBackends"]?.listValue ?? []).map { $0.mapValue }
        authenticators = (initAck["Authenticators"]?.listValue ?? []).map { $0.mapValue }
    }

    func connection(_ c: CoreConnection, setupResult error: String?) {
        setupError = error
    }

    func connection(_ c: CoreConnection, sessionInit state: [String: QVariant]) {
        coreFeatures = c.features
        for v in state["BufferInfos"]?.listValue ?? [] {
            if let b = v.bufferInfoValue { buffers[b.bufferId] = b }
        }
        for v in state["Identities"]?.listValue ?? [] {
            let i = Identity(map: v.mapValue)
            identities[i.id] = i
        }
        for v in state["NetworkIds"]?.listValue ?? [] {
            let id = v.int32Value
            networks[id] = Network(id: id)
            c.requestInit("Network", String(id))
        }
        c.requestInit("BufferSyncer", "")
        c.requestInit("BufferViewManager", "")
        c.requestInit("AliasManager", "")
        c.requestInit("IgnoreListManager", "")
        c.requestInit("HighlightRuleManager", "")
        if coreFeatures.contains(.syncedCoreInfo) { c.requestInit("CoreInfo", "") }
        // Refresh backlog of buffers that were open before a reconnect.
        for (bid, s) in messageStores where !s.messages.isEmpty {
            loadInitialBacklog(bid, force: true)
        }
    }

    func connection(_ c: CoreConnection, received message: SignalProxyMessage) {
        guard c === link else { return }
        switch message {
        case let .initData(className, objectName, data):
            handleInitData(className, objectName, data)
        case let .sync(className, objectName, slot, params):
            handleSync(className, objectName, slot, params)
        case let .rpcCall(name, params):
            handleRpc(name, params)
        default:
            break
        }
    }

    // MARK: - Incoming

    private func handleInitData(_ className: String, _ objectName: String, _ d: [String: QVariant]) {
        switch className {
        case "Network":
            let id = Int32(objectName) ?? 0
            let n = networks[id] ?? Network(id: id)
            n.applyInit(d)
            networks[id] = n
        case "BufferSyncer":
            bufferSyncer.applyInit(d)
            syncBuffersIntoViews()
        case "BufferViewManager":
            let ids = (d["BufferViewIds"] ?? d["bufferViewIds"])?.listValue ?? []
            for v in ids {
                let id = v.int32Value
                if bufferViews[id] == nil { bufferViews[id] = BufferViewConfig(id: id) }
                link?.requestInit("BufferViewConfig", String(id))
            }
            bufferViewIdsLoaded = true
        case "BufferViewConfig":
            let id = Int32(objectName) ?? 0
            let v = bufferViews[id] ?? BufferViewConfig(id: id)
            v.applyInit(d)
            bufferViews[id] = v
            syncBuffersIntoViews()
        case "AliasManager": aliasManager.applyInit(d)
        case "IgnoreListManager": ignoreListManager.applyInit(d)
        case "HighlightRuleManager": highlightRuleManager.applyInit(d)
        case "CoreInfo": coreInfo.applyInit(d)
        case "IrcUser":
            let (nid, nick) = splitObjectName(objectName)
            networks[nid]?.ensureUser(nick).apply(d)
        case "IrcChannel":
            let (nid, name) = splitObjectName(objectName)
            networks[nid]?.ensureChannel(name).apply(d)
        case "Identity":
            let i = Identity(map: d)
            identities[i.id] = i
        default:
            break
        }
    }

    private func splitObjectName(_ s: String) -> (NetworkId, String) {
        guard let slash = s.firstIndex(of: "/") else { return (0, s) }
        return (Int32(s[..<slash]) ?? 0, String(s[s.index(after: slash)...]))
    }

    private func handleSync(_ className: String, _ objectName: String, _ slot: String, _ p: [QVariant]) {
        switch className {
        case "Network":
            networks[Int32(objectName) ?? 0]?.handleSync(slot, p)
        case "IrcUser":
            let (nid, nick) = splitObjectName(objectName)
            networks[nid]?.handleUserSync(nick: nick, slot: slot, p)
        case "IrcChannel":
            let (nid, name) = splitObjectName(objectName)
            networks[nid]?.handleChannelSync(name: name, slot: slot, p)
        case "BufferSyncer":
            bufferSyncer.handleSync(slot, p, session: self)
        case "BufferViewManager":
            let id = p.first?.int32Value ?? 0
            switch slot {
            case "addBufferViewConfig":
                bufferViews[id] = BufferViewConfig(id: id)
                link?.requestInit("BufferViewConfig", String(id))
            case "deleteBufferViewConfig":
                bufferViews.removeValue(forKey: id)
            case "addBufferViewConfigs":
                for v in p.first?.listValue ?? [] {
                    let vid = v.int32Value
                    bufferViews[vid] = BufferViewConfig(id: vid)
                    link?.requestInit("BufferViewConfig", String(vid))
                }
            default: break
            }
        case "BufferViewConfig":
            bufferViews[Int32(objectName) ?? 0]?.handleSync(slot, p)
        case "Identity":
            identities[Int32(objectName) ?? 0]?.handleSync(slot, p)
        case "BacklogManager":
            if slot == "receiveBacklog" || slot == "receiveBacklogFiltered" {
                receiveBacklog(p)
            }
        case "AliasManager": aliasManager.handleSync(slot, p)
        case "IgnoreListManager": ignoreListManager.handleSync(slot, p)
        case "HighlightRuleManager": highlightRuleManager.handleSync(slot, p)
        case "CoreInfo": coreInfo.handleSync(slot, p)
        default: break
        }
    }

    private func handleRpc(_ name: String, _ p: [QVariant]) {
        let first = p.first ?? .invalid
        switch name {
        case "2displayMsg(Message)":
            if let m = first.messageValue { receiveLive(m) }
        case "2displayStatusMsg(QString,QString)":
            statusMessage = p.count > 1 ? "\(p[0].text): \(p[1].text)" : first.text
        case "2bufferInfoUpdated(BufferInfo)":
            if let b = first.bufferInfoValue {
                buffers[b.bufferId] = b
                syncBuffersIntoViews()
            }
        case "2identityCreated(Identity)":
            let i = Identity(map: first.mapValue)
            identities[i.id] = i
        case "2identityRemoved(IdentityId)":
            identities.removeValue(forKey: first.int32Value)
        case "2networkCreated(NetworkId)":
            let id = first.int32Value
            networks[id] = Network(id: id)
            link?.requestInit("Network", String(id))
        case "2networkRemoved(NetworkId)":
            let id = first.int32Value
            networks.removeValue(forKey: id)
            for (bid, b) in buffers where b.networkId == id { buffers.removeValue(forKey: bid) }
        case "2passwordChanged(PeerPtr,bool)":
            passwordChangeResult = p.count > 1 ? p[1].boolValue : first.boolValue
        case "__objectRenamed__":
            // IrcUser renames are handled through setNick; nothing else needed.
            break
        default:
            break
        }
    }

    // MARK: - Messages

    private func receiveLive(_ m0: IrcMessage) {
        var m = m0
        if buffers[m.bufferInfo.bufferId] == nil || buffers[m.bufferInfo.bufferId]?.name != m.bufferInfo.name {
            buffers[m.bufferInfo.bufferId] = m.bufferInfo
        }
        if isLocalHighlight(m) { m.flags.insert(.highlight) }
        let s = store(for: m.bufferInfo.bufferId)
        if s.initialLoaded || !s.messages.isEmpty || visibleBuffer == m.bufferInfo.bufferId {
            s.append(m)
        }
        handleBufferVisibility(for: m)
        if visibleBuffer == m.bufferInfo.bufferId, AppLifecycle.shared.isActive {
            scheduleMarkRead(m.bufferInfo.bufferId)
        } else {
            Notifier.shared.notifyIfNeeded(m, session: self)
        }
    }

    func isLocalHighlight(_ m: IrcMessage) -> Bool {
        guard !m.flags.contains(.selfMsg), m.type.intersection(.conversation) != [] else { return false }
        if m.bufferInfo.type == .query && m.type.contains(.plain) == false && m.type.contains(.action) == false {
            return false
        }
        guard let net = networks[m.bufferInfo.networkId], !net.myNick.isEmpty else { return false }
        let content = IrcFormat.strip(m.content).lowercased()
        let nick = net.myNick.lowercased()
        var search = content.startIndex
        while let r = content.range(of: nick, range: search..<content.endIndex) {
            let before = r.lowerBound == content.startIndex ? nil : content[content.index(before: r.lowerBound)]
            let after = r.upperBound == content.endIndex ? nil : content[r.upperBound]
            func isWordChar(_ c: Character?) -> Bool {
                guard let c = c else { return false }
                return c.isLetter || c.isNumber || "_-[]\\`^{}|".contains(c)
            }
            if !isWordChar(before) && !isWordChar(after) { return true }
            search = r.upperBound
        }
        return false
    }

    /// Re-add hidden buffers / add new buffers to chat lists like the official clients do.
    private func handleBufferVisibility(for m: IrcMessage) {
        guard !m.flags.contains(.backlog) else { return }
        let b = m.bufferInfo
        for v in bufferViews.values where v.initialized {
            if v.networkId != 0 && v.networkId != b.networkId { continue }
            if !v.allowedBufferTypes.contains(b.type) && !v.allowedBufferTypes.isEmpty { continue }
            if v.buffers.contains(b.bufferId) || v.removedBuffers.contains(b.bufferId) { continue }
            if v.temporarilyRemovedBuffers.contains(b.bufferId) {
                if m.type.intersection(.conversation) != [] {
                    syncView(v.id, "requestAddBuffer", [.bufferId(b.bufferId), .int(Int32(v.buffers.count))])
                }
            } else if v.addNewBuffersAutomatically {
                syncView(v.id, "requestAddBuffer", [.bufferId(b.bufferId), .int(Int32(v.buffers.count))])
            }
        }
    }

    private func receiveBacklog(_ p: [QVariant]) {
        guard p.count >= 6 else { return }
        let bid = p[0].int32Value
        let limit = p[3].intValue
        let msgs = p[5].listValue.compactMap { $0.messageValue }.map { m -> IrcMessage in
            var m = m
            if isLocalHighlight(m) { m.flags.insert(.highlight) }
            return m
        }
        let s = store(for: bid)
        s.merge(msgs)
        s.loading = false
        s.initialLoaded = true
        if msgs.count < limit { s.reachedStart = true }
        for m in msgs where buffers[m.bufferInfo.bufferId] == nil { buffers[m.bufferInfo.bufferId] = m.bufferInfo }
    }

    func loadInitialBacklog(_ buffer: BufferId, force: Bool = false) {
        let s = store(for: buffer)
        guard force || (!s.initialLoaded && !s.loading) else { return }
        s.loading = true
        let amount = Int32(AppSettings.shared.initialBacklog)
        link?.sync("BacklogManager", "", "requestBacklog",
                         [.bufferId(buffer), .msgId(-1), .msgId(-1), .int(amount), .int(0)])
    }

    func loadMoreBacklog(_ buffer: BufferId) {
        let s = store(for: buffer)
        guard !s.loading, !s.reachedStart, !s.isFull, isConnected else { return }
        guard let first = s.messages.first else { loadInitialBacklog(buffer); return }
        guard s.requestedBefore != first.msgId else { return }
        s.requestedBefore = first.msgId
        s.loading = true
        let amount = Int32(AppSettings.shared.pageBacklog)
        link?.sync("BacklogManager", "", "requestBacklog",
                         [.bufferId(buffer), .msgId(-1), .msgId(first.msgId), .int(amount), .int(0)])
    }

    // MARK: - Buffer helpers

    func statusBuffer(for network: NetworkId) -> BufferInfo? {
        buffers.values.first { $0.networkId == network && $0.type.contains(.status) }
    }

    func bufferName(_ b: BufferInfo) -> String {
        if b.type.contains(.status) { return networks[b.networkId]?.networkName ?? "Status" }
        return b.name
    }

    func isBufferActive(_ b: BufferInfo) -> Bool {
        guard let net = networks[b.networkId] else { return false }
        if b.type.contains(.status) { return net.isConnected }
        if b.type.contains(.channel) { return net.channel(b.name) != nil }
        if b.type.contains(.query) { return net.isConnected && net.user(b.name) != nil }
        return net.isConnected
    }

    func activity(_ b: BufferId) -> MessageType {
        guard let a = bufferSyncer.activities[b] else { return [] }
        return a
    }

    // MARK: - Outgoing actions

    func sendInput(_ buffer: BufferInfo, _ text: String) {
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            link?.rpc("2sendInput(BufferInfo,QString)", [.bufferInfo(buffer), .str(String(line))])
        }
    }

    @ObservationIgnored private var pendingRead = Set<BufferId>()

    /// Coalesces read-marker updates so busy channels don't send a sync per incoming line.
    func scheduleMarkRead(_ buffer: BufferId) {
        guard !pendingRead.contains(buffer) else { return }
        pendingRead.insert(buffer)
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
            self?.pendingRead.remove(buffer)
            self?.markRead(buffer)
        }
    }

    func markRead(_ buffer: BufferId) {
        guard let last = messageStores[buffer]?.messages.last?.msgId else {
            if (bufferSyncer.activities[buffer] ?? []) != [] {
                link?.sync("BufferSyncer", "", "requestMarkBufferAsRead", [.bufferId(buffer)])
            }
            return
        }
        if (bufferSyncer.lastSeen[buffer] ?? 0) < last {
            link?.sync("BufferSyncer", "", "requestSetLastSeenMsg", [.bufferId(buffer), .msgId(last)])
        }
        if (bufferSyncer.activities[buffer] ?? []) != [] || (bufferSyncer.highlightCounts[buffer] ?? 0) > 0 {
            link?.sync("BufferSyncer", "", "requestMarkBufferAsRead", [.bufferId(buffer)])
            bufferSyncer.activities[buffer] = []
            bufferSyncer.highlightCounts[buffer] = 0
        }
    }

    func setMarkerLine(_ buffer: BufferId) {
        guard let last = messageStores[buffer]?.messages.last?.msgId else { return }
        if (bufferSyncer.markerLines[buffer] ?? 0) < last {
            link?.sync("BufferSyncer", "", "requestSetMarkerLine", [.bufferId(buffer), .msgId(last)])
            bufferSyncer.markerLines[buffer] = last
        }
    }

    func joinChannel(_ network: NetworkId, _ channel: String, password: String = "") {
        guard let status = statusBuffer(for: network) else { return }
        sendInput(status, "/join \(channel)\(password.isEmpty ? "" : " " + password)")
    }

    func openQuery(_ network: NetworkId, nick: String) {
        guard let status = statusBuffer(for: network) else { return }
        sendInput(status, "/query \(nick)")
    }

    func part(_ b: BufferInfo) {
        sendInput(b, "/part")
    }

    func hideBuffer(_ b: BufferId, in view: Int32, permanently: Bool) {
        syncView(view, permanently ? "requestRemoveBufferPermanently" : "requestRemoveBuffer", [.bufferId(b)])
    }

    func unhideBuffer(_ b: BufferId, in view: Int32) {
        let pos = Int32(bufferViews[view]?.buffers.count ?? 0)
        syncView(view, "requestAddBuffer", [.bufferId(b), .int(pos)])
    }

    func deleteBuffer(_ b: BufferId) {
        link?.sync("BufferSyncer", "", "requestRemoveBuffer", [.bufferId(b)])
    }

    func renameBuffer(_ b: BufferId, to name: String) {
        link?.sync("BufferSyncer", "", "requestRenameBuffer", [.bufferId(b), .str(name)])
    }

    func mergeBuffers(_ b1: BufferId, _ b2: BufferId) {
        link?.sync("BufferSyncer", "", "requestMergeBuffersPermanently", [.bufferId(b1), .bufferId(b2)])
    }

    func bufferRemoved(_ b: BufferId) {
        buffers.removeValue(forKey: b)
        messageStores.removeValue(forKey: b)
        for v in bufferViews.values {
            v.buffers.removeAll { $0 == b }
            v.removedBuffers.remove(b)
            v.temporarilyRemovedBuffers.remove(b)
        }
    }

    func bufferRenamed(_ b: BufferId, to name: String) {
        buffers[b]?.name = name
    }

    func connectNetwork(_ id: NetworkId) { link?.sync("Network", String(id), "requestConnect") }
    func disconnectNetwork(_ id: NetworkId) { link?.sync("Network", String(id), "requestDisconnect") }

    func createNetwork(_ s: NetworkSettings, channels: [String]) {
        var s = s
        s.networkId = 0
        link?.rpc("2createNetwork(NetworkInfo,QStringList)", [s.variant, .strings(channels)])
    }

    func updateNetwork(_ s: NetworkSettings) {
        link?.sync("Network", String(s.networkId), "requestSetNetworkInfo", [s.variant])
    }

    func removeNetwork(_ id: NetworkId) {
        link?.rpc("2removeNetwork(NetworkId)", [.networkId(id)])
    }

    func createIdentity(_ s: IdentitySettings) {
        var s = s
        s.identityId = -1
        link?.rpc("2createIdentity(Identity,QVariantMap)", [.identity(s.map), .map([:])])
    }

    func updateIdentity(_ s: IdentitySettings) {
        link?.sync("Identity", String(s.identityId), "requestUpdate", [.map(s.map)])
    }

    func removeIdentity(_ id: IdentityId) {
        link?.rpc("2removeIdentity(IdentityId)", [.identityId(id)])
    }

    func syncView(_ view: Int32, _ slot: String, _ params: [QVariant]) {
        link?.sync("BufferViewConfig", String(view), slot, params)
    }

    func createBufferView(_ v: BufferViewConfig) {
        link?.sync("BufferViewManager", "", "requestCreateBufferView", [.map(v.propertyMap)])
    }

    func updateBufferView(_ v: BufferViewConfig) {
        syncView(v.id, "requestUpdate", [.map(v.propertyMap)])
    }

    func deleteBufferView(_ id: Int32) {
        link?.sync("BufferViewManager", "", "requestDeleteBufferView", [.int(id)])
    }

    func updateAliases(_ a: [AliasEntry]) {
        link?.sync("AliasManager", "", "requestUpdate", [.map(MapSyncObject.aliasesUpdate(a))])
    }

    func updateIgnoreList(_ l: [IgnoreEntry]) {
        link?.sync("IgnoreListManager", "", "requestUpdate", [.map(MapSyncObject.ignoreUpdate(l))])
    }

    func updateHighlightRules(_ l: [HighlightRule], highlightNick: Int, caseSensitive: Bool) {
        link?.sync("HighlightRuleManager", "", "requestUpdate",
                         [.map(MapSyncObject.highlightUpdate(l, highlightNick: highlightNick, caseSensitive: caseSensitive))])
    }

    func changePassword(old: String, new: String) {
        passwordChangeResult = nil
        link?.rpc("2changePassword(PeerPtr,QString,QString,QString)",
                        [.user("PeerPtr", .peerPtr(0)), .str(account.user), .str(old), .str(new)])
    }

    func setAway(_ network: NetworkId?, message: String?) {
        let targets = network.map { [$0] } ?? Array(networks.keys)
        for n in targets {
            guard let status = statusBuffer(for: n) else { continue }
            sendInput(status, message.map { "/away \($0)" } ?? "/back")
        }
    }
}
