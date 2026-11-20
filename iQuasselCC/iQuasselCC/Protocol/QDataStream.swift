import Foundation

enum QDataStreamError: Error, LocalizedError {
    case endOfData
    case unknownType(UInt32)
    case unknownUserType(String)

    var errorDescription: String? {
        switch self {
        case .endOfData: return "Unexpected end of data"
        case .unknownType(let t): return "Unknown QVariant type \(t)"
        case .unknownUserType(let n): return "Unknown user type \(n)"
        }
    }
}

/// Big-endian reader implementing the subset of QDataStream (Qt_4_2) used by Quassel.
struct QDataStreamReader {
    private let data: [UInt8]
    private(set) var offset = 0
    let features: Set<QuasselFeature>

    init(_ data: Data, features: Set<QuasselFeature>) {
        self.data = [UInt8](data)
        self.features = features
    }

    var atEnd: Bool { offset >= data.count }

    mutating func bytes(_ n: Int) throws -> ArraySlice<UInt8> {
        guard n >= 0, offset + n <= data.count else { throw QDataStreamError.endOfData }
        let s = data[offset..<(offset + n)]
        offset += n
        return s
    }

    mutating func u8() throws -> UInt8 { try bytes(1).first! }
    mutating func i8() throws -> Int8 { Int8(bitPattern: try u8()) }

    mutating func u16() throws -> UInt16 {
        let b = try bytes(2)
        return b.reduce(0) { ($0 << 8) | UInt16($1) }
    }
    mutating func i16() throws -> Int16 { Int16(bitPattern: try u16()) }

    mutating func u32() throws -> UInt32 {
        let b = try bytes(4)
        return b.reduce(0) { ($0 << 8) | UInt32($1) }
    }
    mutating func i32() throws -> Int32 { Int32(bitPattern: try u32()) }

    mutating func u64() throws -> UInt64 {
        let b = try bytes(8)
        return b.reduce(0) { ($0 << 8) | UInt64($1) }
    }
    mutating func i64() throws -> Int64 { Int64(bitPattern: try u64()) }

    mutating func double() throws -> Double { Double(bitPattern: try u64()) }
    mutating func float() throws -> Float { Float(bitPattern: try u32()) }

    mutating func byteArray() throws -> Data? {
        let len = try u32()
        if len == 0xFFFF_FFFF { return nil }
        return Data(try bytes(Int(len)))
    }

    mutating func utf8String() throws -> String? {
        try byteArray().map { String(decoding: $0, as: UTF8.self) }
    }

    mutating func qString() throws -> String? {
        let len = try u32()
        if len == 0xFFFF_FFFF { return nil }
        let b = try bytes(Int(len))
        var units = [UInt16]()
        units.reserveCapacity(b.count / 2)
        var i = b.startIndex
        while i + 1 < b.endIndex {
            units.append(UInt16(b[i]) << 8 | UInt16(b[i + 1]))
            i += 2
        }
        return String(decoding: units, as: UTF16.self)
    }

    mutating func variantList() throws -> [QVariant] {
        let n = try u32()
        var out = [QVariant]()
        out.reserveCapacity(Int(min(n, 100_000)))
        for _ in 0..<n { out.append(try variant()) }
        return out
    }

    mutating func variantMap() throws -> [String: QVariant] {
        let n = try u32()
        var out = [String: QVariant]()
        for _ in 0..<n {
            let k = try qString() ?? ""
            out[k] = try variant()
        }
        return out
    }

    mutating func dateTime() throws -> QDateTimeValue {
        let jd = try u32()
        let ms = try u32()
        let spec = try u8()
        return QDateTimeValue(julianDay: jd, msecs: ms, spec: spec)
    }

    mutating func variant() throws -> QVariant {
        let rawType = try u32()
        _ = try u8() // is-null flag
        guard let type = QType(rawValue: rawType) else { throw QDataStreamError.unknownType(rawType) }
        switch type {
        case .invalid:
            // Qt writes an (empty) QString after invalid variants for pre-Qt5 stream versions.
            _ = try qString()
            return .invalid
        case .bool: return .bool(try u8() != 0)
        case .int: return .int(try i32())
        case .uint: return .uint(try u32())
        case .longLong, .long: return .longLong(try i64())
        case .uLongLong, .uLong: return .uLongLong(try u64())
        case .double: return .double(try double())
        case .float: return .double(Double(try float()))
        case .char: return .char(try u16())
        case .map: return .map(try variantMap())
        case .list: return .list(try variantList())
        case .string: return .string(try qString())
        case .stringList:
            let n = try u32()
            var l = [String?]()
            for _ in 0..<n { l.append(try qString()) }
            return .stringList(l)
        case .byteArray: return .byteArray(try byteArray())
        case .date: return .date(try u32())
        case .time: return .time(try u32())
        case .dateTime: return .dateTime(try dateTime())
        case .short: return .short(try i16())
        case .uShort: return .uShort(try u16())
        case .sChar: return .sChar(try i8())
        case .uChar: return .uChar(try u8())
        case .userType:
            var name = try byteArray().map { String(decoding: $0, as: UTF8.self) } ?? ""
            while name.hasSuffix("\0") { name.removeLast() }
            return .user(name, try userValue(name))
        }
    }

    mutating func msgId() throws -> MsgId {
        features.contains(.longMessageId) ? try i64() : Int64(try i32())
    }

    mutating func bufferInfo() throws -> BufferInfo {
        let id = try i32()
        let net = try i32()
        let type = try i16()
        let group = try u32()
        let name = try utf8String() ?? ""
        return BufferInfo(bufferId: id, networkId: net, type: BufferType(rawValue: type), groupId: group, name: name)
    }

    mutating func message() throws -> IrcMessage {
        let id = try msgId()
        let time: Date
        if features.contains(.longTime) {
            time = Date(timeIntervalSince1970: Double(try i64()) / 1000)
        } else {
            time = Date(timeIntervalSince1970: Double(try u32()))
        }
        let type = MessageType(rawValue: try u32())
        let flags = MessageFlags(rawValue: try u8())
        let info = try bufferInfo()
        let sender = try utf8String() ?? ""
        var prefixes = ""
        if features.contains(.senderPrefixes) { prefixes = try utf8String() ?? "" }
        var realName = "", avatar = ""
        if features.contains(.richMessages) {
            realName = try utf8String() ?? ""
            avatar = try utf8String() ?? ""
        }
        let content = try utf8String() ?? ""
        return IrcMessage(msgId: id, time: time, type: type, flags: flags, bufferInfo: info, sender: sender,
                          senderPrefixes: prefixes, realName: realName, avatarUrl: avatar, content: content)
    }

    mutating func userValue(_ name: String) throws -> QUserValue {
        switch name {
        case "BufferId": return .bufferId(try i32())
        case "NetworkId": return .networkId(try i32())
        case "IdentityId": return .identityId(try i32())
        case "MsgId": return .msgId(try msgId())
        case "PeerPtr": return .peerPtr(try i64())
        case "BufferInfo": return .bufferInfo(try bufferInfo())
        case "Message": return .message(try message())
        case "Identity", "NetworkInfo", "Network::Server", "CertIdentity":
            return .map(try variantMap())
        default:
            throw QDataStreamError.unknownUserType(name)
        }
    }
}

/// Big-endian writer mirroring `QDataStreamReader`.
struct QDataStreamWriter {
    private(set) var data = Data()
    let features: Set<QuasselFeature>

    init(features: Set<QuasselFeature>) { self.features = features }

    mutating func u8(_ v: UInt8) { data.append(v) }
    mutating func u16(_ v: UInt16) { data.append(contentsOf: [UInt8(v >> 8), UInt8(v & 0xFF)]) }
    mutating func u32(_ v: UInt32) {
        data.append(contentsOf: [UInt8(v >> 24), UInt8((v >> 16) & 0xFF), UInt8((v >> 8) & 0xFF), UInt8(v & 0xFF)])
    }
    mutating func u64(_ v: UInt64) {
        u32(UInt32(v >> 32))
        u32(UInt32(v & 0xFFFF_FFFF))
    }
    mutating func i16(_ v: Int16) { u16(UInt16(bitPattern: v)) }
    mutating func i32(_ v: Int32) { u32(UInt32(bitPattern: v)) }
    mutating func i64(_ v: Int64) { u64(UInt64(bitPattern: v)) }

    mutating func byteArray(_ d: Data?) {
        guard let d = d else { u32(0xFFFF_FFFF); return }
        u32(UInt32(d.count))
        data.append(d)
    }

    mutating func utf8(_ s: String) { byteArray(Data(s.utf8)) }

    mutating func qString(_ s: String?) {
        guard let s = s else { u32(0xFFFF_FFFF); return }
        let units = Array(s.utf16)
        u32(UInt32(units.count * 2))
        var bytes = [UInt8]()
        bytes.reserveCapacity(units.count * 2)
        for u in units { bytes.append(UInt8(u >> 8)); bytes.append(UInt8(u & 0xFF)) }
        data.append(contentsOf: bytes)
    }

    mutating func variantList(_ l: [QVariant]) {
        u32(UInt32(l.count))
        for v in l { variant(v) }
    }

    mutating func variantMap(_ m: [String: QVariant]) {
        u32(UInt32(m.count))
        // QDataStream writes QMap entries from the last key to the first.
        for (k, v) in m.sorted(by: { $0.key > $1.key }) {
            qString(k)
            variant(v)
        }
    }

    private mutating func header(_ t: QType, null: Bool = false) {
        u32(t.rawValue)
        u8(null ? 1 : 0)
    }

    mutating func variant(_ v: QVariant) {
        switch v {
        case .invalid: header(.invalid, null: true); qString(nil)
        case .bool(let b): header(.bool); u8(b ? 1 : 0)
        case .int(let i): header(.int); i32(i)
        case .uint(let i): header(.uint); u32(i)
        case .longLong(let i): header(.longLong); i64(i)
        case .uLongLong(let i): header(.uLongLong); u64(i)
        case .double(let d): header(.double); u64(d.bitPattern)
        case .char(let c): header(.char); u16(c)
        case .short(let s): header(.short); i16(s)
        case .uShort(let s): header(.uShort); u16(s)
        case .sChar(let s): header(.sChar); u8(UInt8(bitPattern: s))
        case .uChar(let s): header(.uChar); u8(s)
        case .string(let s): header(.string); qString(s)
        case .stringList(let l):
            header(.stringList)
            u32(UInt32(l.count))
            for s in l { qString(s) }
        case .byteArray(let d): header(.byteArray); byteArray(d)
        case .list(let l): header(.list); variantList(l)
        case .map(let m): header(.map); variantMap(m)
        case .date(let d): header(.date); u32(d)
        case .time(let t): header(.time); u32(t)
        case .dateTime(let dt):
            header(.dateTime)
            u32(dt.julianDay); u32(dt.msecs); u8(dt.spec == 3 ? 1 : dt.spec)
        case .user(let name, let value):
            header(.userType)
            var n = Data(name.utf8)
            n.append(0)
            byteArray(n)
            userValue(value)
        }
    }

    mutating func bufferInfo(_ b: BufferInfo) {
        i32(b.bufferId)
        i32(b.networkId)
        i16(b.type.rawValue)
        u32(b.groupId)
        utf8(b.name)
    }

    mutating func msgId(_ id: MsgId) {
        if features.contains(.longMessageId) { i64(id) } else { i32(Int32(truncatingIfNeeded: id)) }
    }

    mutating func userValue(_ v: QUserValue) {
        switch v {
        case .bufferId(let i), .networkId(let i), .identityId(let i): i32(i)
        case .msgId(let i): msgId(i)
        case .peerPtr(let i): i64(i)
        case .bufferInfo(let b): bufferInfo(b)
        case .map(let m): variantMap(m)
        case .message(let m):
            msgId(m.msgId)
            if features.contains(.longTime) {
                i64(Int64(m.time.timeIntervalSince1970 * 1000))
            } else {
                u32(UInt32(max(0, m.time.timeIntervalSince1970)))
            }
            u32(m.type.rawValue)
            u8(m.flags.rawValue)
            bufferInfo(m.bufferInfo)
            utf8(m.sender)
            if features.contains(.senderPrefixes) { utf8(m.senderPrefixes) }
            if features.contains(.richMessages) { utf8(m.realName); utf8(m.avatarUrl) }
            utf8(m.content)
        }
    }
}
