import Foundation

typealias BufferId = Int32
typealias NetworkId = Int32
typealias IdentityId = Int32
typealias MsgId = Int64

struct BufferType: OptionSet, Hashable {
    let rawValue: Int16
    static let invalid: BufferType = []
    static let status = BufferType(rawValue: 0x01)
    static let channel = BufferType(rawValue: 0x02)
    static let query = BufferType(rawValue: 0x04)
    static let group = BufferType(rawValue: 0x08)
}

struct BufferInfo: Hashable, Identifiable {
    var bufferId: BufferId
    var networkId: NetworkId
    var type: BufferType
    var groupId: UInt32
    var name: String

    var id: BufferId { bufferId }

    static func status(network: NetworkId) -> BufferInfo {
        BufferInfo(bufferId: -1, networkId: network, type: .status, groupId: 0, name: "")
    }
}

struct MessageType: OptionSet, Hashable {
    let rawValue: UInt32
    static let plain = MessageType(rawValue: 0x00001)
    static let notice = MessageType(rawValue: 0x00002)
    static let action = MessageType(rawValue: 0x00004)
    static let nick = MessageType(rawValue: 0x00008)
    static let mode = MessageType(rawValue: 0x00010)
    static let join = MessageType(rawValue: 0x00020)
    static let part = MessageType(rawValue: 0x00040)
    static let quit = MessageType(rawValue: 0x00080)
    static let kick = MessageType(rawValue: 0x00100)
    static let kill = MessageType(rawValue: 0x00200)
    static let server = MessageType(rawValue: 0x00400)
    static let info = MessageType(rawValue: 0x00800)
    static let error = MessageType(rawValue: 0x01000)
    static let dayChange = MessageType(rawValue: 0x02000)
    static let topic = MessageType(rawValue: 0x04000)
    static let netsplitJoin = MessageType(rawValue: 0x08000)
    static let netsplitQuit = MessageType(rawValue: 0x10000)
    static let invite = MessageType(rawValue: 0x20000)
    static let markerline = MessageType(rawValue: 0x40000)

    /// Message types that count as "real" chat activity.
    static let conversation: MessageType = [.plain, .notice, .action]
    static let joinPartQuit: MessageType = [.join, .part, .quit, .netsplitJoin, .netsplitQuit]
}

struct MessageFlags: OptionSet, Hashable {
    let rawValue: UInt8
    static let selfMsg = MessageFlags(rawValue: 0x01)
    static let highlight = MessageFlags(rawValue: 0x02)
    static let redirected = MessageFlags(rawValue: 0x04)
    static let serverMsg = MessageFlags(rawValue: 0x08)
    static let statusMsg = MessageFlags(rawValue: 0x10)
    static let ignored = MessageFlags(rawValue: 0x20)
    static let backlog = MessageFlags(rawValue: 0x80)
}

struct IrcMessage: Identifiable, Hashable {
    var msgId: MsgId
    var time: Date
    var type: MessageType
    var flags: MessageFlags
    var bufferInfo: BufferInfo
    var sender: String
    var senderPrefixes: String
    var realName: String
    var avatarUrl: String
    var content: String

    var id: MsgId { msgId }

    var senderNick: String { IrcMask.nick(sender) }
}

enum IrcMask {
    static func nick(_ mask: String) -> String {
        if let i = mask.firstIndex(of: "!") { return String(mask[..<i]) }
        return mask
    }
    static func user(_ mask: String) -> String {
        guard let e = mask.firstIndex(of: "!") else { return "" }
        let rest = mask[mask.index(after: e)...]
        if let a = rest.firstIndex(of: "@") { return String(rest[..<a]) }
        return String(rest)
    }
    static func host(_ mask: String) -> String {
        if let a = mask.firstIndex(of: "@") { return String(mask[mask.index(after: a)...]) }
        return ""
    }
}

/// Protocol features negotiated with the core. Names are as sent in "FeatureList".
enum QuasselFeature: String, CaseIterable {
    case synchronizedMarkerLine = "SynchronizedMarkerLine"
    case saslAuthentication = "SaslAuthentication"
    case saslExternal = "SaslExternal"
    case hideInactiveNetworks = "HideInactiveNetworks"
    case passwordChange = "PasswordChange"
    case capNegotiation = "CapNegotiation"
    case verifyServerSSL = "VerifyServerSSL"
    case customRateLimits = "CustomRateLimits"
    case dccFileTransfer = "DccFileTransfer"
    case awayFormatTimestamp = "AwayFormatTimestamp"
    case authenticators = "Authenticators"
    case bufferActivitySync = "BufferActivitySync"
    case coreSideHighlights = "CoreSideHighlights"
    case senderPrefixes = "SenderPrefixes"
    case remoteDisconnect = "RemoteDisconnect"
    case extendedFeatures = "ExtendedFeatures"
    case longTime = "LongTime"
    case richMessages = "RichMessages"
    case backlogFilterType = "BacklogFilterType"
    case ecdsaCertfpKeys = "EcdsaCertfpKeys"
    case longMessageId = "LongMessageId"
    case syncedCoreInfo = "SyncedCoreInfo"
    case loadBacklogForwards = "LoadBacklogForwards"
    case skipIrcCaps = "SkipIrcCaps"

    /// Legacy bit used in the "Features" uint field.
    var legacyBit: UInt32 {
        switch self {
        case .synchronizedMarkerLine: return 0x0001
        case .saslAuthentication: return 0x0002
        case .saslExternal: return 0x0004
        case .hideInactiveNetworks: return 0x0008
        case .passwordChange: return 0x0010
        case .capNegotiation: return 0x0020
        case .verifyServerSSL: return 0x0040
        case .customRateLimits: return 0x0080
        case .dccFileTransfer: return 0x0100
        case .awayFormatTimestamp: return 0x0200
        case .authenticators: return 0x0400
        case .bufferActivitySync: return 0x0800
        case .coreSideHighlights: return 0x1000
        case .senderPrefixes: return 0x2000
        case .remoteDisconnect: return 0x4000
        case .extendedFeatures: return 0x8000
        case .longTime: return 0x10000
        case .richMessages: return 0x20000
        case .backlogFilterType: return 0x40000
        case .ecdsaCertfpKeys: return 0x80000
        case .longMessageId: return 0x100000
        case .syncedCoreInfo: return 0x200000
        case .loadBacklogForwards: return 0
        case .skipIrcCaps: return 0
        }
    }

    /// Everything this client understands.
    static let clientSupported: Set<QuasselFeature> = [
        .synchronizedMarkerLine, .saslAuthentication, .saslExternal, .hideInactiveNetworks,
        .passwordChange, .capNegotiation, .verifyServerSSL, .customRateLimits,
        .awayFormatTimestamp, .authenticators, .bufferActivitySync, .coreSideHighlights,
        .senderPrefixes, .remoteDisconnect, .extendedFeatures, .longTime, .richMessages,
        .backlogFilterType, .ecdsaCertfpKeys, .longMessageId, .syncedCoreInfo,
        .loadBacklogForwards, .skipIrcCaps,
    ]

    static func legacyBits(_ set: Set<QuasselFeature>) -> UInt32 {
        set.reduce(0) { $0 | $1.legacyBit }
    }

    static func fromLegacy(_ bits: UInt32) -> Set<QuasselFeature> {
        Set(allCases.filter { $0.legacyBit != 0 && bits & $0.legacyBit != 0 })
    }
}
