import Foundation
import Observation

@Observable
final class BufferSyncer {
    var lastSeen: [BufferId: MsgId] = [:]
    var markerLines: [BufferId: MsgId] = [:]
    var activities: [BufferId: MessageType] = [:]
    var highlightCounts: [BufferId: Int] = [:]

    private static func pairs(_ v: QVariant?) -> [(BufferId, QVariant)] {
        let l = v?.listValue ?? []
        var out = [(BufferId, QVariant)]()
        var i = 0
        while i + 1 < l.count {
            out.append((l[i].int32Value, l[i + 1]))
            i += 2
        }
        return out
    }

    func applyInit(_ d: [String: QVariant]) {
        lastSeen = Dictionary(Self.pairs(d["LastSeenMsg"]).map { ($0.0, $0.1.int64Value ?? 0) }, uniquingKeysWith: { $1 })
        markerLines = Dictionary(Self.pairs(d["MarkerLines"]).map { ($0.0, $0.1.int64Value ?? 0) }, uniquingKeysWith: { $1 })
        activities = Dictionary(Self.pairs(d["Activities"]).map { ($0.0, MessageType(rawValue: UInt32(truncatingIfNeeded: $0.1.intValue))) }, uniquingKeysWith: { $1 })
        highlightCounts = Dictionary(Self.pairs(d["HighlightCounts"]).map { ($0.0, $0.1.intValue) }, uniquingKeysWith: { $1 })
    }

    /// Returns buffer ids that were removed (for `removeBuffer`), so the session can clean up.
    func handleSync(_ slot: String, _ p: [QVariant], session: CoreSession) {
        func arg(_ i: Int) -> QVariant { i < p.count ? p[i] : .invalid }
        let buf = arg(0).int32Value
        switch slot {
        case "setLastSeenMsg": lastSeen[buf] = arg(1).int64Value ?? 0
        case "setMarkerLine": markerLines[buf] = arg(1).int64Value ?? 0
        case "setBufferActivity": activities[buf] = MessageType(rawValue: UInt32(truncatingIfNeeded: arg(1).intValue))
        case "setHighlightCount": highlightCounts[buf] = arg(1).intValue
        case "markBufferAsRead":
            activities[buf] = []
            highlightCounts[buf] = 0
        case "removeBuffer":
            lastSeen.removeValue(forKey: buf)
            markerLines.removeValue(forKey: buf)
            activities.removeValue(forKey: buf)
            highlightCounts.removeValue(forKey: buf)
            session.bufferRemoved(buf)
        case "renameBuffer":
            session.bufferRenamed(buf, to: arg(1).text)
        case "mergeBuffersPermanently":
            session.bufferRemoved(arg(1).int32Value)
        default: break
        }
    }
}

@Observable
final class BufferViewConfig: Identifiable {
    let id: Int32
    var name = ""
    var networkId: NetworkId = 0
    var addNewBuffersAutomatically = true
    var sortAlphabetically = true
    var hideInactiveBuffers = false
    var hideInactiveNetworks = false
    var disableDecoration = false
    var allowedBufferTypes: BufferType = [.status, .channel, .query, .group]
    var minimumActivity = 0
    var showSearch = false
    var buffers: [BufferId] = []
    var removedBuffers = Set<BufferId>()
    var temporarilyRemovedBuffers = Set<BufferId>()
    var initialized = false

    init(id: Int32) { self.id = id }

    func applyInit(_ d: [String: QVariant]) {
        for (k, v) in d { set(k, v) }
        initialized = true
    }

    func set(_ k: String, _ v: QVariant) {
        switch k {
        case "bufferViewName": name = v.text
        case "networkId": networkId = v.int32Value
        case "addNewBuffersAutomatically": addNewBuffersAutomatically = v.boolValue
        case "sortAlphabetically": sortAlphabetically = v.boolValue
        case "hideInactiveBuffers": hideInactiveBuffers = v.boolValue
        case "hideInactiveNetworks": hideInactiveNetworks = v.boolValue
        case "disableDecoration": disableDecoration = v.boolValue
        case "allowedBufferTypes": allowedBufferTypes = BufferType(rawValue: Int16(truncatingIfNeeded: v.intValue))
        case "minimumActivity": minimumActivity = v.intValue
        case "showSearch": showSearch = v.boolValue
        case "BufferList": buffers = v.listValue.map { $0.int32Value }
        case "RemovedBuffers": removedBuffers = Set(v.listValue.map { $0.int32Value })
        case "TemporarilyRemovedBuffers": temporarilyRemovedBuffers = Set(v.listValue.map { $0.int32Value })
        default: break
        }
    }

    func handleSync(_ slot: String, _ p: [QVariant]) {
        func arg(_ i: Int) -> QVariant { i < p.count ? p[i] : .invalid }
        switch slot {
        case "addBuffer":
            let b = arg(0).int32Value
            let pos = arg(1).intValue
            buffers.removeAll { $0 == b }
            removedBuffers.remove(b)
            temporarilyRemovedBuffers.remove(b)
            buffers.insert(b, at: max(0, min(pos, buffers.count)))
        case "moveBuffer":
            let b = arg(0).int32Value
            guard buffers.contains(b) else { return }
            buffers.removeAll { $0 == b }
            buffers.insert(b, at: max(0, min(arg(1).intValue, buffers.count)))
        case "removeBuffer":
            let b = arg(0).int32Value
            buffers.removeAll { $0 == b }
            removedBuffers.remove(b)
            temporarilyRemovedBuffers.insert(b)
        case "removeBufferPermanently":
            let b = arg(0).int32Value
            buffers.removeAll { $0 == b }
            temporarilyRemovedBuffers.remove(b)
            removedBuffers.insert(b)
        case "setBufferViewName": name = arg(0).text
        case "update": for (k, v) in arg(0).mapValue { set(k, v) }
        default:
            if slot.hasPrefix("set"), slot.count > 3 {
                var key = String(slot.dropFirst(3))
                key = key.prefix(1).lowercased() + key.dropFirst()
                set(key, arg(0))
            }
        }
    }

    /// Property map for create / update requests.
    var propertyMap: [String: QVariant] {
        [
            "bufferViewName": .str(name),
            "networkId": .networkId(networkId),
            "addNewBuffersAutomatically": .bool(addNewBuffersAutomatically),
            "sortAlphabetically": .bool(sortAlphabetically),
            "hideInactiveBuffers": .bool(hideInactiveBuffers),
            "hideInactiveNetworks": .bool(hideInactiveNetworks),
            "disableDecoration": .bool(disableDecoration),
            "allowedBufferTypes": .int(Int32(allowedBufferTypes.rawValue)),
            "minimumActivity": .int(Int32(minimumActivity)),
            "showSearch": .bool(showSearch),
            "BufferList": .list(buffers.map { .bufferId($0) }),
            "RemovedBuffers": .list(removedBuffers.map { .bufferId($0) }),
            "TemporarilyRemovedBuffers": .list(temporarilyRemovedBuffers.map { .bufferId($0) }),
        ]
    }
}

/// Editable identity values.
struct IdentitySettings: Hashable {
    var identityId: IdentityId = -1
    var identityName = "Default"
    var realName = ""
    var nicks: [String] = []
    var ident = ""
    var awayNick = ""
    var awayNickEnabled = false
    var awayReason = "Gone fishing."
    var awayReasonEnabled = true
    var autoAwayEnabled = false
    var autoAwayTime = 10
    var autoAwayReason = ""
    var autoAwayReasonEnabled = false
    var detachAwayEnabled = false
    var detachAwayReason = ""
    var detachAwayReasonEnabled = false
    var kickReason = "Kindergarten is elsewhere!"
    var partReason = "iQuasselCC – Quassel Core Client"
    var quitReason = "iQuasselCC – Quassel Core Client"

    init() {}

    init(map m: [String: QVariant]) {
        identityId = m["identityId"]?.int32Value ?? -1
        identityName = m.str("identityName")
        realName = m.str("realName")
        nicks = m.strings("nicks")
        ident = m.str("ident")
        awayNick = m.str("awayNick")
        awayNickEnabled = m.bool("awayNickEnabled")
        awayReason = m.str("awayReason")
        awayReasonEnabled = m.bool("awayReasonEnabled")
        autoAwayEnabled = m.bool("autoAwayEnabled")
        autoAwayTime = m.int("autoAwayTime", 10)
        autoAwayReason = m.str("autoAwayReason")
        autoAwayReasonEnabled = m.bool("autoAwayReasonEnabled")
        detachAwayEnabled = m.bool("detachAwayEnabled")
        detachAwayReason = m.str("detachAwayReason")
        detachAwayReasonEnabled = m.bool("detachAwayReasonEnabled")
        kickReason = m.str("kickReason")
        partReason = m.str("partReason")
        quitReason = m.str("quitReason")
    }

    var map: [String: QVariant] {
        [
            "identityId": .identityId(identityId),
            "identityName": .str(identityName),
            "realName": .str(realName),
            "nicks": .strings(nicks),
            "ident": .str(ident),
            "awayNick": .str(awayNick),
            "awayNickEnabled": .bool(awayNickEnabled),
            "awayReason": .str(awayReason),
            "awayReasonEnabled": .bool(awayReasonEnabled),
            "autoAwayEnabled": .bool(autoAwayEnabled),
            "autoAwayTime": .int(Int32(autoAwayTime)),
            "autoAwayReason": .str(autoAwayReason),
            "autoAwayReasonEnabled": .bool(autoAwayReasonEnabled),
            "detachAwayEnabled": .bool(detachAwayEnabled),
            "detachAwayReason": .str(detachAwayReason),
            "detachAwayReasonEnabled": .bool(detachAwayReasonEnabled),
            "kickReason": .str(kickReason),
            "partReason": .str(partReason),
            "quitReason": .str(quitReason),
        ]
    }
}

@Observable
final class Identity: Identifiable {
    let id: IdentityId
    var settings: IdentitySettings

    init(map: [String: QVariant]) {
        settings = IdentitySettings(map: map)
        id = settings.identityId
    }

    func handleSync(_ slot: String, _ p: [QVariant]) {
        guard let first = p.first else { return }
        if slot == "update" {
            var m = settings.map
            for (k, v) in first.mapValue { m[k] = v }
            settings = IdentitySettings(map: m)
        } else if slot.hasPrefix("set"), slot.count > 3 {
            var key = String(slot.dropFirst(3))
            key = key.prefix(1).lowercased() + key.dropFirst()
            if key == "id" { return }
            var m = settings.map
            m[key] = first
            settings = IdentitySettings(map: m)
        }
    }
}

/// Generic synced object storing its state as a property map
/// (AliasManager, IgnoreListManager, HighlightRuleManager, CoreInfo, NetworkConfig).
@Observable
final class MapSyncObject {
    let className: String
    var data: [String: QVariant] = [:]
    var initialized = false

    init(className: String) { self.className = className }

    func applyInit(_ d: [String: QVariant]) {
        for (k, v) in d { data[k] = v }
        initialized = true
    }

    func handleSync(_ slot: String, _ p: [QVariant]) {
        guard let first = p.first else { return }
        switch slot {
        case "update", "setCoreData":
            if slot == "setCoreData" { data["coreData"] = first } else {
                for (k, v) in first.mapValue { data[k] = v }
            }
        default:
            if slot.hasPrefix("set"), slot.count > 3 {
                var key = String(slot.dropFirst(3))
                key = key.prefix(1).lowercased() + key.dropFirst()
                data[key] = first
            }
        }
    }
}

// MARK: - Typed views on map objects

struct AliasEntry: Identifiable, Hashable {
    var id = UUID()
    var name: String
    var expansion: String
}

struct IgnoreEntry: Identifiable, Hashable {
    var id = UUID()
    var type = 0          // 0 sender, 1 message, 2 ctcp
    var rule = ""
    var isRegEx = false
    var strictness = 1    // 1 soft, 2 hard
    var scope = 0         // 0 global, 1 network, 2 channel
    var scopeRule = ""
    var isActive = true
}

struct HighlightRule: Identifiable, Hashable {
    var id = UUID()
    var ruleId: Int = 0
    var name = ""
    var isRegEx = false
    var isCaseSensitive = false
    var isEnabled = true
    var isInverse = false
    var sender = ""
    var channel = ""
}

extension MapSyncObject {
    private func columns(_ key: String) -> [String: [QVariant]] {
        (data[key]?.mapValue ?? [:]).mapValues { $0.listValue }
    }

    var aliases: [AliasEntry] {
        let c = columns("Aliases")
        let names = c["names"] ?? [], exp = c["expansions"] ?? []
        return names.indices.map { AliasEntry(name: names[$0].text, expansion: $0 < exp.count ? exp[$0].text : "") }
    }

    static func aliasesUpdate(_ a: [AliasEntry]) -> [String: QVariant] {
        ["Aliases": .map(["names": .strings(a.map { $0.name }), "expansions": .strings(a.map { $0.expansion })])]
    }

    var ignoreList: [IgnoreEntry] {
        let c = columns("IgnoreList")
        let rules = c["ignoreRule"] ?? []
        func col(_ k: String, _ i: Int) -> QVariant { let l = c[k] ?? []; return i < l.count ? l[i] : .invalid }
        return rules.indices.map { i in
            IgnoreEntry(type: col("ignoreType", i).intValue, rule: rules[i].text, isRegEx: col("isRegEx", i).boolValue,
                        strictness: col("strictness", i).intValue, scope: col("scope", i).intValue,
                        scopeRule: col("scopeRule", i).text, isActive: col("isActive", i).boolValue)
        }
    }

    static func ignoreUpdate(_ l: [IgnoreEntry]) -> [String: QVariant] {
        ["IgnoreList": .map([
            "ignoreType": .list(l.map { .int(Int32($0.type)) }),
            "ignoreRule": .strings(l.map { $0.rule }),
            "isRegEx": .list(l.map { .bool($0.isRegEx) }),
            "strictness": .list(l.map { .int(Int32($0.strictness)) }),
            "scope": .list(l.map { .int(Int32($0.scope)) }),
            "scopeRule": .strings(l.map { $0.scopeRule }),
            "isActive": .list(l.map { .bool($0.isActive) }),
        ])]
    }

    var highlightRules: [HighlightRule] {
        let c = columns("HighlightRuleList")
        let names = c["name"] ?? []
        func col(_ k: String, _ i: Int) -> QVariant { let l = c[k] ?? []; return i < l.count ? l[i] : .invalid }
        return names.indices.map { i in
            HighlightRule(ruleId: col("id", i).intValue, name: names[i].text, isRegEx: col("isRegEx", i).boolValue,
                          isCaseSensitive: col("isCaseSensitive", i).boolValue, isEnabled: col("isEnabled", i).boolValue,
                          isInverse: col("isInverse", i).boolValue, sender: col("sender", i).text,
                          channel: col("channel", i).text)
        }
    }

    var highlightNick: Int { data["highlightNick"]?.intValue ?? 0 }
    var nicksCaseSensitive: Bool { data["nicksCaseSensitive"]?.boolValue ?? false }

    static func highlightUpdate(_ l: [HighlightRule], highlightNick: Int, caseSensitive: Bool) -> [String: QVariant] {
        var rules = l
        for i in rules.indices where rules[i].ruleId == 0 {
            rules[i].ruleId = (rules.map { $0.ruleId }.max() ?? 0) + 1
        }
        return [
            "HighlightRuleList": .map([
                "id": .list(rules.map { .int(Int32($0.ruleId)) }),
                "name": .strings(rules.map { $0.name }),
                "isRegEx": .list(rules.map { .bool($0.isRegEx) }),
                "isCaseSensitive": .list(rules.map { .bool($0.isCaseSensitive) }),
                "isEnabled": .list(rules.map { .bool($0.isEnabled) }),
                "isInverse": .list(rules.map { .bool($0.isInverse) }),
                "sender": .strings(rules.map { $0.sender }),
                "channel": .strings(rules.map { $0.channel }),
            ]),
            "highlightNick": .int(Int32(highlightNick)),
            "nicksCaseSensitive": .bool(caseSensitive),
        ]
    }
}
