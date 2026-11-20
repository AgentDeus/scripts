import Foundation

/// Qt meta type ids as they appear on the wire (Quassel uses QDataStream version Qt_4_2).
enum QType: UInt32 {
    case invalid = 0
    case bool = 1
    case int = 2
    case uint = 3
    case longLong = 4
    case uLongLong = 5
    case double = 6
    case char = 7
    case map = 8
    case list = 9
    case string = 10
    case stringList = 11
    case byteArray = 12
    case date = 14
    case time = 15
    case dateTime = 16
    case userType = 127
    case long = 129
    case short = 130
    case sChar = 131
    case uLong = 132
    case uShort = 133
    case uChar = 134
    case float = 135
}

/// A Qt `QDateTime` as transported by Quassel (julian day + msecs + spec).
struct QDateTimeValue: Equatable {
    var julianDay: UInt32
    var msecs: UInt32
    var spec: UInt8

    static let invalid = QDateTimeValue(julianDay: 0, msecs: 0xFFFF_FFFF, spec: 0xFF)

    var isValid: Bool { julianDay != 0 && msecs != 0xFFFF_FFFF }

    var date: Date? {
        guard isValid else { return nil }
        // Julian day 2440588 == 1970-01-01
        let days = Double(Int64(julianDay) - 2_440_588)
        let seconds = days * 86_400 + Double(msecs) / 1000
        if spec == 0 {
            // Local time on the core; best effort: interpret as local time here.
            return Date(timeIntervalSince1970: seconds - Double(TimeZone.current.secondsFromGMT()))
        }
        return Date(timeIntervalSince1970: seconds)
    }

    init(julianDay: UInt32, msecs: UInt32, spec: UInt8) {
        self.julianDay = julianDay
        self.msecs = msecs
        self.spec = spec
    }

    init(date: Date) {
        let ms = Int64((date.timeIntervalSince1970 * 1000).rounded())
        let dayMs: Int64 = 86_400_000
        var days = ms / dayMs
        var rem = ms % dayMs
        if rem < 0 { rem += dayMs; days -= 1 }
        julianDay = UInt32(days + 2_440_588)
        msecs = UInt32(rem)
        spec = 1 // UTC
    }
}

/// Dynamic value mirroring Qt's QVariant, restricted to what Quassel uses.
indirect enum QVariant {
    case invalid
    case bool(Bool)
    case int(Int32)
    case uint(UInt32)
    case longLong(Int64)
    case uLongLong(UInt64)
    case double(Double)
    case char(UInt16)
    case short(Int16)
    case uShort(UInt16)
    case sChar(Int8)
    case uChar(UInt8)
    case string(String?)
    case stringList([String?])
    case byteArray(Data?)
    case list([QVariant])
    case map([String: QVariant])
    case date(UInt32)
    case time(UInt32)
    case dateTime(QDateTimeValue)
    case user(String, QUserValue)
}

/// Payload of Quassel's custom (user) types.
indirect enum QUserValue {
    case bufferId(Int32)
    case networkId(Int32)
    case identityId(Int32)
    case msgId(Int64)
    case peerPtr(Int64)
    case bufferInfo(BufferInfo)
    case message(IrcMessage)
    case map([String: QVariant]) // Identity, NetworkInfo, Network::Server
}

// MARK: - Convenience constructors

extension QVariant {
    static func str(_ s: String?) -> QVariant { .string(s) }
    static func strings(_ s: [String]) -> QVariant { .stringList(s.map { Optional($0) }) }
    static func bytes(_ s: String) -> QVariant { .byteArray(Data(s.utf8)) }
    static func bufferId(_ v: Int32) -> QVariant { .user("BufferId", .bufferId(v)) }
    static func networkId(_ v: Int32) -> QVariant { .user("NetworkId", .networkId(v)) }
    static func identityId(_ v: Int32) -> QVariant { .user("IdentityId", .identityId(v)) }
    static func msgId(_ v: Int64) -> QVariant { .user("MsgId", .msgId(v)) }
    static func bufferInfo(_ v: BufferInfo) -> QVariant { .user("BufferInfo", .bufferInfo(v)) }
    static func identity(_ m: [String: QVariant]) -> QVariant { .user("Identity", .map(m)) }
    static func networkInfo(_ m: [String: QVariant]) -> QVariant { .user("NetworkInfo", .map(m)) }
    static func server(_ m: [String: QVariant]) -> QVariant { .user("Network::Server", .map(m)) }
}

// MARK: - Accessors (lenient, like QVariant::toX)

extension QVariant {
    var isNull: Bool {
        switch self {
        case .invalid: return true
        case .string(let s): return s == nil
        case .byteArray(let d): return d == nil
        default: return false
        }
    }

    var int64Value: Int64? {
        switch self {
        case .bool(let b): return b ? 1 : 0
        case .int(let v): return Int64(v)
        case .uint(let v): return Int64(v)
        case .longLong(let v): return v
        case .uLongLong(let v): return Int64(truncatingIfNeeded: v)
        case .double(let v): return Int64(v)
        case .short(let v): return Int64(v)
        case .uShort(let v): return Int64(v)
        case .sChar(let v): return Int64(v)
        case .uChar(let v): return Int64(v)
        case .char(let v): return Int64(v)
        case .string(let s): return s.flatMap { Int64($0) }
        case .byteArray(let d): return d.flatMap { String(data: $0, encoding: .utf8) }.flatMap { Int64($0) }
        case .user(_, let u):
            switch u {
            case .bufferId(let v), .networkId(let v), .identityId(let v): return Int64(v)
            case .msgId(let v), .peerPtr(let v): return v
            default: return nil
            }
        default: return nil
        }
    }

    var intValue: Int { Int(int64Value ?? 0) }
    var int32Value: Int32 { Int32(truncatingIfNeeded: int64Value ?? 0) }

    var boolValue: Bool {
        switch self {
        case .bool(let b): return b
        case .string(let s): return s == "true" || s == "1"
        default: return (int64Value ?? 0) != 0
        }
    }

    var doubleValue: Double {
        if case .double(let d) = self { return d }
        return Double(int64Value ?? 0)
    }

    /// QString or QByteArray (UTF-8) or QChar as String.
    var stringValue: String? {
        switch self {
        case .string(let s): return s
        case .byteArray(let d): return d.map { String(decoding: $0, as: UTF8.self) }
        case .char(let c): return String(utf16CodeUnits: [c], count: 1)
        case .int, .uint, .longLong, .uLongLong, .short, .uShort, .uChar, .sChar:
            return String(int64Value ?? 0)
        case .bool(let b): return b ? "true" : "false"
        case .double(let d): return String(d)
        default: return nil
        }
    }

    var text: String { stringValue ?? "" }

    var stringListValue: [String] {
        switch self {
        case .stringList(let l): return l.map { $0 ?? "" }
        case .list(let l): return l.map { $0.text }
        case .string(let s): return s.map { [$0] } ?? []
        default: return []
        }
    }

    var listValue: [QVariant] {
        switch self {
        case .list(let l): return l
        case .stringList(let l): return l.map { .string($0) }
        default: return []
        }
    }

    var mapValue: [String: QVariant] {
        switch self {
        case .map(let m): return m
        case .user(_, .map(let m)): return m
        default: return [:]
        }
    }

    var dataValue: Data? {
        switch self {
        case .byteArray(let d): return d
        case .string(let s): return s.map { Data($0.utf8) }
        default: return nil
        }
    }

    var dateValue: Date? {
        switch self {
        case .dateTime(let dt): return dt.date
        case .longLong(let ms): return Date(timeIntervalSince1970: Double(ms) / 1000)
        case .int(let s): return s > 0 ? Date(timeIntervalSince1970: Double(s)) : nil
        case .uint(let s): return s > 0 ? Date(timeIntervalSince1970: Double(s)) : nil
        default: return nil
        }
    }

    var bufferInfoValue: BufferInfo? {
        if case .user(_, .bufferInfo(let b)) = self { return b }
        return nil
    }

    var messageValue: IrcMessage? {
        if case .user(_, .message(let m)) = self { return m }
        return nil
    }
}

extension Dictionary where Key == String, Value == QVariant {
    func str(_ k: String, _ def: String = "") -> String { self[k]?.stringValue ?? def }
    func int(_ k: String, _ def: Int = 0) -> Int { self[k]?.int64Value.map { Int($0) } ?? def }
    func bool(_ k: String, _ def: Bool = false) -> Bool { self[k].map { $0.boolValue } ?? def }
    func strings(_ k: String) -> [String] { self[k]?.stringListValue ?? [] }
}
