import Foundation
import Observation

enum NetworkConnectionState: Int {
    case disconnected = 0, connecting, initializing, initialized, reconnecting, disconnecting

    var label: String {
        switch self {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting"
        case .initializing: return "Initializing"
        case .initialized: return "Connected"
        case .reconnecting: return "Reconnecting"
        case .disconnecting: return "Disconnecting"
        }
    }
}

struct NetworkServer: Identifiable, Hashable {
    var id = UUID()
    var host: String = ""
    var port: Int = 6697
    var password: String = ""
    var useSSL: Bool = true
    var sslVerify: Bool = true
    var sslVersion: Int = 0
    var useProxy: Bool = false
    var proxyType: Int = 0
    var proxyHost: String = "localhost"
    var proxyPort: Int = 8080
    var proxyUser: String = ""
    var proxyPass: String = ""

    init() {}

    init(map m: [String: QVariant]) {
        host = m.str("Host")
        port = m.int("Port", 6667)
        password = m.str("Password")
        useSSL = m.bool("UseSSL")
        sslVerify = m.bool("sslVerify")
        sslVersion = m.int("sslVersion")
        useProxy = m.bool("UseProxy")
        proxyType = m.int("ProxyType")
        proxyHost = m.str("ProxyHost", "localhost")
        proxyPort = m.int("ProxyPort", 8080)
        proxyUser = m.str("ProxyUser")
        proxyPass = m.str("ProxyPass")
    }

    var variant: QVariant {
        .server([
            "Host": .str(host),
            "Port": .uint(UInt32(clamping: port)),
            "Password": .str(password),
            "UseSSL": .bool(useSSL),
            "sslVerify": .bool(sslVerify),
            "sslVersion": .int(Int32(sslVersion)),
            "UseProxy": .bool(useProxy),
            "ProxyType": .int(Int32(proxyType)),
            "ProxyHost": .str(proxyHost.isEmpty ? "localhost" : proxyHost),
            "ProxyPort": .uint(UInt32(clamping: proxyPort)),
            "ProxyUser": .str(proxyUser),
            "ProxyPass": .str(proxyPass),
        ])
    }
}

/// Editable network settings (NetworkInfo on the wire).
struct NetworkSettings: Hashable {
    var networkId: NetworkId = 0
    var networkName: String = ""
    var identityId: IdentityId = 1
    var servers: [NetworkServer] = []
    var useRandomServer = false
    var perform: [String] = []
    var useAutoIdentify = false
    var autoIdentifyService = "NickServ"
    var autoIdentifyPassword = ""
    var useSasl = false
    var saslAccount = ""
    var saslPassword = ""
    var useAutoReconnect = true
    var autoReconnectInterval = 60
    var autoReconnectRetries = 20
    var unlimitedReconnectRetries = false
    var rejoinChannels = true
    var useCustomMessageRate = false
    var messageRateBurstSize = 5
    var messageRateDelay = 2200
    var unlimitedMessageRate = false
    var codecForServer = ""
    var codecForEncoding = ""
    var codecForDecoding = ""
    var skipCaps: [String] = []

    var variant: QVariant {
        .networkInfo([
            "NetworkId": .networkId(networkId),
            "NetworkName": .str(networkName),
            "Identity": .identityId(identityId),
            "ServerList": .list(servers.map { $0.variant }),
            "UseRandomServer": .bool(useRandomServer),
            "Perform": .strings(perform),
            "UseAutoIdentify": .bool(useAutoIdentify),
            "AutoIdentifyService": .str(autoIdentifyService),
            "AutoIdentifyPassword": .str(autoIdentifyPassword),
            "UseSasl": .bool(useSasl),
            "SaslAccount": .str(saslAccount),
            "SaslPassword": .str(saslPassword),
            "UseAutoReconnect": .bool(useAutoReconnect),
            "AutoReconnectInterval": .uint(UInt32(clamping: autoReconnectInterval)),
            "AutoReconnectRetries": .uShort(UInt16(clamping: autoReconnectRetries)),
            "UnlimitedReconnectRetries": .bool(unlimitedReconnectRetries),
            "RejoinChannels": .bool(rejoinChannels),
            "UseCustomMessageRate": .bool(useCustomMessageRate),
            "MessageRateBurstSize": .uint(UInt32(clamping: messageRateBurstSize)),
            "MessageRateDelay": .uint(UInt32(clamping: messageRateDelay)),
            "UnlimitedMessageRate": .bool(unlimitedMessageRate),
            "CodecForServer": .byteArray(Data(codecForServer.utf8)),
            "CodecForEncoding": .byteArray(Data(codecForEncoding.utf8)),
            "CodecForDecoding": .byteArray(Data(codecForDecoding.utf8)),
            "SkipCaps": .strings(skipCaps),
        ])
    }
}

@Observable
final class IrcUser {
    let networkId: NetworkId
    var nick: String
    var user = ""
    var host = ""
    var realName = ""
    var account = ""
    var away = false
    var awayMessage = ""
    var server = ""
    var ircOperator = ""
    var userModes = ""
    var idleTime: Date?
    var loginTime: Date?
    var channels = Set<String>()

    init(networkId: NetworkId, nick: String) {
        self.networkId = networkId
        self.nick = nick
    }

    var hostmask: String { "\(nick)!\(user)@\(host)" }

    func apply(_ m: [String: QVariant]) {
        for (k, v) in m { set(k, v) }
    }

    func set(_ key: String, _ v: QVariant) {
        switch key {
        case "nick": if let s = v.stringValue, !s.isEmpty { nick = s }
        case "user": user = v.text
        case "host": host = v.text
        case "realName": realName = v.text
        case "account": account = v.text
        case "away": away = v.boolValue
        case "awayMessage": awayMessage = v.text
        case "server": server = v.text
        case "ircOperator": ircOperator = v.text
        case "userModes": userModes = v.text
        case "idleTime": idleTime = v.dateValue
        case "loginTime": loginTime = v.dateValue
        case "channels": channels = Set(v.stringListValue.map { $0.lowercased() })
        default: break
        }
    }
}

@Observable
final class IrcChannel {
    let networkId: NetworkId
    var name: String
    var topic = ""
    var password = ""
    var encrypted = false
    /// lower-cased nick -> mode characters (display nick lives in Network.users)
    var userModes: [String: String] = [:]
    var chanModes: [String: QVariant] = [:]

    init(networkId: NetworkId, name: String) {
        self.networkId = networkId
        self.name = name
    }

    func apply(_ m: [String: QVariant]) {
        if let n = m["name"]?.stringValue, !n.isEmpty { name = n }
        topic = m.str("topic")
        password = m.str("password")
        encrypted = m.bool("encrypted")
        var modes = [String: String]()
        for (k, v) in m["UserModes"]?.mapValue ?? [:] { modes[k.lowercased()] = v.text }
        userModes = modes
        chanModes = m["ChanModes"]?.mapValue ?? [:]
    }

    var modeString: String {
        var s = chanModes["D"]?.text ?? ""
        for (k, v) in (chanModes["C"]?.mapValue ?? [:]) { s += k; _ = v }
        for (k, _) in (chanModes["B"]?.mapValue ?? [:]) { s += k }
        return s.isEmpty ? "" : "+" + s
    }
}

@Observable
final class Network: Identifiable {
    let id: NetworkId
    var networkName = ""
    var currentServer = ""
    var myNick = ""
    var latency = 0
    var isConnected = false
    var connectionState: NetworkConnectionState = .disconnected
    var identityId: IdentityId = 0
    var supports: [String: String] = [:]
    var caps: [String: String] = [:]
    var capsEnabled: [String] = []
    var settings = NetworkSettings()
    var users: [String: IrcUser] = [:]
    var channels: [String: IrcChannel] = [:]
    var initialized = false

    init(id: NetworkId) {
        self.id = id
        settings.networkId = id
    }

    // MARK: PREFIX handling

    var prefixModes: [Character] {
        let p = supports["PREFIX"] ?? "(ov)@+"
        guard let open = p.firstIndex(of: "("), let close = p.firstIndex(of: ")") else { return ["o", "v"] }
        return Array(p[p.index(after: open)..<close])
    }

    var prefixChars: [Character] {
        let p = supports["PREFIX"] ?? "(ov)@+"
        guard let close = p.firstIndex(of: ")") else { return ["@", "+"] }
        return Array(p[p.index(after: close)...])
    }

    func prefixes(forModes modes: String) -> String {
        let pm = prefixModes, pc = prefixChars
        var out = ""
        for (i, m) in pm.enumerated() where modes.contains(m) && i < pc.count { out.append(pc[i]) }
        return out
    }

    /// Lower is more important; users without prefix get `prefixModes.count`.
    func rank(forModes modes: String) -> Int {
        for (i, m) in prefixModes.enumerated() where modes.contains(m) { return i }
        return prefixModes.count
    }

    var channelTypes: String { supports["CHANTYPES"] ?? "#&!+" }

    func isChannelName(_ s: String) -> Bool {
        guard let f = s.first else { return false }
        return channelTypes.contains(f)
    }

    // MARK: Users and channels

    func user(_ nick: String) -> IrcUser? { users[nick.lowercased()] }

    @discardableResult
    func ensureUser(_ maskOrNick: String) -> IrcUser {
        let nick = IrcMask.nick(maskOrNick)
        if let u = users[nick.lowercased()] {
            let user = IrcMask.user(maskOrNick), host = IrcMask.host(maskOrNick)
            if !user.isEmpty { u.user = user }
            if !host.isEmpty { u.host = host }
            return u
        }
        let u = IrcUser(networkId: id, nick: nick)
        u.user = IrcMask.user(maskOrNick)
        u.host = IrcMask.host(maskOrNick)
        users[nick.lowercased()] = u
        return u
    }

    func channel(_ name: String) -> IrcChannel? { channels[name.lowercased()] }

    @discardableResult
    func ensureChannel(_ name: String) -> IrcChannel {
        if let c = channels[name.lowercased()] { return c }
        let c = IrcChannel(networkId: id, name: name)
        channels[name.lowercased()] = c
        return c
    }

    /// Display nick for a lower-cased key from IrcChannel.userModes.
    func displayNick(_ key: String) -> String { users[key]?.nick ?? key }

    func renameUser(from old: String, to new: String) {
        let oldKey = old.lowercased(), newKey = new.lowercased()
        guard let u = users.removeValue(forKey: oldKey) else { return }
        u.nick = new
        users[newKey] = u
        // O(1) lookup per channel; only mutate channels that contain the user (mutations notify observers).
        for c in channels.values {
            guard let modes = c.userModes[oldKey] else { continue }
            c.userModes.removeValue(forKey: oldKey)
            c.userModes[newKey] = modes
        }
        if myNick.lowercased() == oldKey { myNick = new }
    }

    func removeUser(_ nick: String) {
        let key = nick.lowercased()
        if users[key] != nil { users.removeValue(forKey: key) }
        for c in channels.values where c.userModes[key] != nil {
            c.userModes.removeValue(forKey: key)
        }
    }

    func partUser(_ nick: String, channel name: String) {
        guard let c = channel(name) else { return }
        if c.userModes[nick.lowercased()] != nil { c.userModes.removeValue(forKey: nick.lowercased()) }
        if let u = user(nick) {
            u.channels.remove(name.lowercased())
            if u.channels.isEmpty && nick.lowercased() != myNick.lowercased() {
                users.removeValue(forKey: nick.lowercased())
            }
        }
        if nick.lowercased() == myNick.lowercased() {
            channels.removeValue(forKey: name.lowercased())
        }
    }

    // MARK: Sync

    func applyInit(_ d: [String: QVariant]) {
        for (k, v) in d where k != "IrcUsersAndChannels" { setProperty(k, v) }
        if let uc = d["IrcUsersAndChannels"]?.mapValue {
            users = [:]
            channels = [:]
            applyUsersAndChannels(uc)
        }
        initialized = true
    }

    private func applyUsersAndChannels(_ uc: [String: QVariant]) {
        let usersData = uc["Users"]?.mapValue ?? [:]
        if let nicks = usersData["nick"]?.listValue {
            // Column-oriented representation (Quassel >= 0.13)
            for i in 0..<nicks.count {
                var m = [String: QVariant]()
                for (k, col) in usersData {
                    let l = col.listValue
                    if i < l.count { m[k] = l[i] }
                }
                let u = ensureUser(nicks[i].text)
                u.apply(m)
            }
        } else {
            for (_, v) in usersData {
                let m = v.mapValue
                ensureUser(m.str("nick")).apply(m)
            }
        }
        let chanData = uc["Channels"]?.mapValue ?? [:]
        if let names = chanData["name"]?.listValue {
            for i in 0..<names.count {
                var m = [String: QVariant]()
                for (k, col) in chanData {
                    let l = col.listValue
                    if i < l.count { m[k] = l[i] }
                }
                ensureChannel(names[i].text).apply(m)
            }
        } else {
            for (_, v) in chanData {
                let m = v.mapValue
                ensureChannel(m.str("name")).apply(m)
            }
        }
    }

    func setProperty(_ key: String, _ v: QVariant) {
        switch key {
        case "networkName": networkName = v.text; settings.networkName = v.text
        case "currentServer": currentServer = v.text
        case "myNick": myNick = v.text
        case "latency": latency = v.intValue
        case "isConnected", "connected": isConnected = v.boolValue
        case "connectionState": connectionState = NetworkConnectionState(rawValue: v.intValue) ?? .disconnected
        case "identityId", "identity": identityId = v.int32Value; settings.identityId = v.int32Value
        case "Supports":
            supports = v.mapValue.mapValues { $0.text }
        case "Caps":
            caps = v.mapValue.mapValues { $0.text }
        case "CapsEnabled":
            capsEnabled = v.stringListValue
        case "ServerList", "serverList":
            settings.servers = v.listValue.map { NetworkServer(map: $0.mapValue) }
        case "useRandomServer": settings.useRandomServer = v.boolValue
        case "perform": settings.perform = v.stringListValue
        case "useAutoIdentify": settings.useAutoIdentify = v.boolValue
        case "autoIdentifyService": settings.autoIdentifyService = v.text
        case "autoIdentifyPassword": settings.autoIdentifyPassword = v.text
        case "useSasl": settings.useSasl = v.boolValue
        case "saslAccount": settings.saslAccount = v.text
        case "saslPassword": settings.saslPassword = v.text
        case "useAutoReconnect": settings.useAutoReconnect = v.boolValue
        case "autoReconnectInterval": settings.autoReconnectInterval = v.intValue
        case "autoReconnectRetries": settings.autoReconnectRetries = v.intValue
        case "unlimitedReconnectRetries": settings.unlimitedReconnectRetries = v.boolValue
        case "rejoinChannels": settings.rejoinChannels = v.boolValue
        case "useCustomMessageRate": settings.useCustomMessageRate = v.boolValue
        case "msgRateBurstSize": settings.messageRateBurstSize = v.intValue
        case "msgRateMessageDelay": settings.messageRateDelay = v.intValue
        case "unlimitedMessageRate": settings.unlimitedMessageRate = v.boolValue
        case "codecForServer": settings.codecForServer = v.text
        case "codecForEncoding": settings.codecForEncoding = v.text
        case "codecForDecoding": settings.codecForDecoding = v.text
        case "skipCaps": settings.skipCaps = v.stringListValue
        default: break
        }
    }

    /// Handles a sync call addressed to this network.
    func handleSync(_ slot: String, _ p: [QVariant]) {
        func arg(_ i: Int) -> QVariant { i < p.count ? p[i] : .invalid }
        switch slot {
        case "addIrcUser": ensureUser(arg(0).text)
        case "addIrcChannel": ensureChannel(arg(0).text)
        case "addSupport": supports[arg(0).text] = arg(1).text
        case "removeSupport": supports.removeValue(forKey: arg(0).text)
        case "addCap": caps[arg(0).text] = arg(1).text
        case "acknowledgeCap": if !capsEnabled.contains(arg(0).text) { capsEnabled.append(arg(0).text) }
        case "removeCap":
            caps.removeValue(forKey: arg(0).text)
            capsEnabled.removeAll { $0 == arg(0).text }
        case "clearCaps": caps = [:]; capsEnabled = []
        case "setConnected": isConnected = arg(0).boolValue
            if !isConnected { users = [:]; channels = [:] }
        case "setNetworkInfo": applyNetworkInfo(arg(0).mapValue)
        case "update": for (k, v) in arg(0).mapValue { setProperty(k, v) }
        case "setIdentity": setProperty("identityId", arg(0))
        case "setServerList": setProperty("ServerList", arg(0))
        case "setCodecForServer": setProperty("codecForServer", arg(0))
        case "setCodecForEncoding": setProperty("codecForEncoding", arg(0))
        case "setCodecForDecoding": setProperty("codecForDecoding", arg(0))
        case "setMessageRateBurstSize": setProperty("msgRateBurstSize", arg(0))
        case "setMessageRateDelay": setProperty("msgRateMessageDelay", arg(0))
        default:
            if slot.hasPrefix("set"), slot.count > 3 {
                var key = String(slot.dropFirst(3))
                key = key.prefix(1).lowercased() + key.dropFirst()
                setProperty(key, arg(0))
            }
        }
    }

    func applyNetworkInfo(_ m: [String: QVariant]) {
        let map: [String: String] = [
            "NetworkName": "networkName", "Identity": "identityId", "ServerList": "ServerList",
            "UseRandomServer": "useRandomServer", "Perform": "perform", "UseAutoIdentify": "useAutoIdentify",
            "AutoIdentifyService": "autoIdentifyService", "AutoIdentifyPassword": "autoIdentifyPassword",
            "UseSasl": "useSasl", "SaslAccount": "saslAccount", "SaslPassword": "saslPassword",
            "UseAutoReconnect": "useAutoReconnect", "AutoReconnectInterval": "autoReconnectInterval",
            "AutoReconnectRetries": "autoReconnectRetries", "UnlimitedReconnectRetries": "unlimitedReconnectRetries",
            "RejoinChannels": "rejoinChannels", "UseCustomMessageRate": "useCustomMessageRate",
            "MessageRateBurstSize": "msgRateBurstSize", "MessageRateDelay": "msgRateMessageDelay",
            "UnlimitedMessageRate": "unlimitedMessageRate", "CodecForServer": "codecForServer",
            "CodecForEncoding": "codecForEncoding", "CodecForDecoding": "codecForDecoding", "SkipCaps": "skipCaps",
        ]
        for (k, v) in m { if let key = map[k] { setProperty(key, v) } }
    }

    func handleUserSync(nick: String, slot: String, _ p: [QVariant]) {
        func arg(_ i: Int) -> QVariant { i < p.count ? p[i] : .invalid }
        let u = ensureUser(nick)
        switch slot {
        case "setNick": renameUser(from: u.nick, to: arg(0).text)
        case "joinChannel":
            u.channels.insert(arg(0).text.lowercased())
            let c = ensureChannel(arg(0).text)
            if c.userModes[u.nick.lowercased()] == nil {
                c.userModes[u.nick.lowercased()] = ""
            }
        case "partChannel": partUser(u.nick, channel: arg(0).text)
        case "quit": removeUser(u.nick)
        case "addUserModes": u.userModes = Set(u.userModes + arg(0).text).sorted().map(String.init).joined()
        case "removeUserModes": u.userModes = u.userModes.filter { !arg(0).text.contains($0) }
        case "updateHostmask":
            let m = arg(0).text
            u.user = IrcMask.user(m); u.host = IrcMask.host(m)
        case "update": u.apply(arg(0).mapValue)
        default:
            if slot.hasPrefix("set"), slot.count > 3 {
                var key = String(slot.dropFirst(3))
                key = key.prefix(1).lowercased() + key.dropFirst()
                u.set(key, arg(0))
            }
        }
    }

    func handleChannelSync(name: String, slot: String, _ p: [QVariant]) {
        func arg(_ i: Int) -> QVariant { i < p.count ? p[i] : .invalid }
        let c = ensureChannel(name)
        func key(for nick: String) -> String { nick.lowercased() }
        switch slot {
        case "joinIrcUsers":
            let nicks = arg(0).stringListValue
            let modes = arg(1).stringListValue
            for (i, n) in nicks.enumerated() {
                let u = ensureUser(n)
                u.channels.insert(c.name.lowercased())
                c.userModes[key(for: u.nick)] = i < modes.count ? modes[i] : ""
            }
        case "part": partUser(arg(0).text, channel: c.name)
        case "setTopic": c.topic = arg(0).text
        case "setPassword": c.password = arg(0).text
        case "setEncrypted": c.encrypted = arg(0).boolValue
        case "addUserMode":
            let k = key(for: arg(0).text)
            let cur = c.userModes[k] ?? ""
            let add = arg(1).text
            if !cur.contains(add) { c.userModes[k] = cur + add }
        case "removeUserMode":
            let k = key(for: arg(0).text)
            let rem = arg(1).text
            c.userModes[k] = (c.userModes[k] ?? "").filter { !rem.contains($0) }
        case "setUserModes":
            c.userModes[key(for: arg(0).text)] = arg(1).text
        case "addChannelMode":
            let mode = arg(0).text, value = arg(1).stringValue
            applyChanMode(c, mode: mode, value: value, add: true)
        case "removeChannelMode":
            applyChanMode(c, mode: arg(0).text, value: arg(1).stringValue, add: false)
        case "update": c.apply(arg(0).mapValue)
        default: break
        }
    }

    private func applyChanMode(_ c: IrcChannel, mode: String, value: String?, add: Bool) {
        let chanModes = (supports["CHANMODES"] ?? "beI,k,l,imnpst").split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        func group(_ i: Int) -> String { i < chanModes.count ? chanModes[i] : "" }
        if group(0).contains(mode) {
            var a = c.chanModes["A"]?.mapValue ?? [:]
            var l = a[mode]?.stringListValue ?? []
            if add { if let v = value { l.append(v) } } else { l.removeAll { $0 == value } }
            a[mode] = .strings(l)
            c.chanModes["A"] = .map(a)
        } else if group(1).contains(mode) || group(2).contains(mode) {
            let g = group(1).contains(mode) ? "B" : "C"
            var m = c.chanModes[g]?.mapValue ?? [:]
            if add { m[mode] = .str(value ?? "") } else { m.removeValue(forKey: mode) }
            c.chanModes[g] = .map(m)
        } else {
            var d = c.chanModes["D"]?.text ?? ""
            if add { if !d.contains(mode) { d += mode } } else { d = d.filter { !mode.contains($0) } }
            c.chanModes["D"] = .str(d)
        }
    }
}
