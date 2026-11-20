import Foundation
import Security
import CryptoKit

/// SignalProxy message as received from / sent to the core.
enum SignalProxyMessage {
    case sync(className: String, objectName: String, slot: String, params: [QVariant])
    case rpcCall(name: String, params: [QVariant])
    case initRequest(className: String, objectName: String)
    case initData(className: String, objectName: String, data: [String: QVariant])
    case heartBeat(QVariant)
    case heartBeatReply(QVariant)
}

struct CoreCertificateInfo: Equatable {
    var sha256: String
    var sha1: String
    var subject: String
    var trustedBySystem: Bool
}

enum ConnectionPhase: Equatable {
    case disconnected
    case connecting
    case negotiating
    case awaitingCertificateDecision(CoreCertificateInfo)
    case handshaking
    case needsSetup
    case loggingIn
    case initializing
    case connected
    case failed(String)

    var isActive: Bool {
        switch self {
        case .disconnected, .failed: return false
        default: return true
        }
    }
}

protocol CoreConnectionDelegate: AnyObject {
    /// All delegate calls arrive on the main thread.
    func connection(_ c: CoreConnection, phaseChanged phase: ConnectionPhase)
    func connection(_ c: CoreConnection, initAck: [String: QVariant])
    func connection(_ c: CoreConnection, sessionInit state: [String: QVariant])
    func connection(_ c: CoreConnection, received message: SignalProxyMessage)
    func connection(_ c: CoreConnection, setupResult error: String?)
}

/// Handles the Quassel wire protocol: probing, TLS, handshake and DataStream framing.
final class CoreConnection {
    struct Config {
        var host: String
        var port: Int
        var user: String
        var password: String
        var useTLS: Bool
        var trustedFingerprint: String?
    }

    static let clientVersion = "iQuasselCC v1.0"
    static let clientDate = "2026-11-20"

    weak var delegate: CoreConnectionDelegate?
    let config: Config

    private(set) var features: Set<QuasselFeature> = []
    private(set) var coreFeatureList: [String] = []

    private var transport: StreamTransport?
    private var buffer = Data()
    private var probing = true
    private var tlsNegotiated = false
    private var handshakeDone = false
    private var pendingTrust: SecTrust?
    private var heartbeatTimer: DispatchSourceTimer?
    private var timeoutTimer: DispatchSourceTimer?
    private let queue = DispatchQueue(label: "iQuasselCC.connection")
    private var closedByUs = false
    private var phase: ConnectionPhase = .disconnected

    init(config: Config) {
        self.config = config
    }

    // MARK: - Public API (call from main thread)

    func connect() {
        closedByUs = false
        setPhase(.connecting)
        let t = StreamTransport(host: config.host, port: config.port)
        t.onEvent = { [weak self] ev in self?.queue.async { self?.handle(ev) } }
        transport = t
        t.connect()
        startTimeout(seconds: 20)
    }

    func disconnect() {
        closedByUs = true
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        timeoutTimer?.cancel()
        transport?.close()
        transport = nil
        setPhase(.disconnected)
    }

    /// Continue after the user decided about an untrusted certificate.
    func resolveCertificate(accept: Bool) {
        queue.async {
            guard self.pendingTrust != nil else { return }
            self.pendingTrust = nil
            if accept {
                self.sendClientInit()
            } else {
                self.fail("Certificate rejected")
            }
        }
    }

    func sendSetup(adminUser: String, password: String, backend: String, backendProperties: [String: QVariant],
                   authenticator: String, authProperties: [String: QVariant]) {
        let data: [String: QVariant] = [
            "AdminUser": .str(adminUser),
            "AdminPasswd": .str(password),
            "Backend": .str(backend),
            "ConnectionProperties": .map(backendProperties),
            "Authenticator": .str(authenticator),
            "AuthProperties": .map(authProperties),
        ]
        queue.async { self.sendHandshake(["MsgType": .str("CoreSetupData"), "SetupData": .map(data)]) }
    }

    func send(_ message: SignalProxyMessage) {
        queue.async { self.write(self.encode(message)) }
    }

    func sync(_ className: String, _ objectName: String, _ slot: String, _ params: [QVariant] = []) {
        send(.sync(className: className, objectName: objectName, slot: slot, params: params))
    }

    func rpc(_ name: String, _ params: [QVariant] = []) {
        send(.rpcCall(name: name, params: params))
    }

    func requestInit(_ className: String, _ objectName: String) {
        send(.initRequest(className: className, objectName: objectName))
    }

    // MARK: - Internals (connection queue)

    private func setPhase(_ p: ConnectionPhase) {
        DispatchQueue.main.async {
            self.phase = p
            self.delegate?.connection(self, phaseChanged: p)
        }
    }

    private func startTimeout(seconds: Int) {
        timeoutTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + .seconds(seconds))
        t.setEventHandler { [weak self] in
            guard let self = self, !self.handshakeDone, self.pendingTrust == nil else { return }
            self.fail("Connection timed out")
        }
        timeoutTimer = t
        t.resume()
    }

    private func fail(_ reason: String) {
        heartbeatTimer?.cancel()
        heartbeatTimer = nil
        timeoutTimer?.cancel()
        closedByUs = true
        transport?.close()
        transport = nil
        setPhase(.failed(reason))
    }

    private func handle(_ ev: StreamTransport.Event) {
        switch ev {
        case .connected:
            setPhase(.negotiating)
            var w = QDataStreamWriter(features: [])
            var magic: UInt32 = 0x42B3_3F00
            if config.useTLS { magic |= 0x01 }
            w.u32(magic)
            w.u32(0x8000_0002) // DataStream protocol, last in list
            transport?.send(w.data)
        case .data(let d):
            buffer.append(d)
            processBuffer()
        case .tlsEstablished(let trust):
            evaluate(trust: trust)
        case .closed(let err):
            heartbeatTimer?.cancel()
            heartbeatTimer = nil
            if closedByUs { return }
            transport = nil
            fail(err?.localizedDescription ?? "Connection closed by core")
        }
    }

    private func processBuffer() {
        if probing {
            guard buffer.count >= 4 else { return }
            var r = QDataStreamReader(buffer.prefix(4), features: [])
            let reply = (try? r.u32()) ?? 0
            buffer.removeFirst(4)
            probing = false
            let proto = reply & 0xFF
            let connFeatures = (reply >> 24) & 0xFF
            guard proto == 0x02 else {
                fail(proto == 0x01 ? "Core only supports the legacy protocol, which is not supported"
                                   : "Core rejected the protocol")
                return
            }
            if connFeatures & 0x01 != 0 {
                tlsNegotiated = true
                transport?.startTLS()
            } else if config.useTLS && config.trustedFingerprint != nil {
                // We trusted a certificate before but now the core refuses TLS: warn.
                fail("Core did not offer encryption although it was used before")
                return
            } else {
                sendClientInit()
            }
        }
        // Parse all complete frames using an offset, then drop the consumed bytes once
        // (removing from the front of Data per frame is quadratic on big initial syncs).
        let bytes = [UInt8](buffer)
        var offset = 0
        var batch = [SignalProxyMessage]()
        while bytes.count - offset >= 4 {
            let len = Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            guard bytes.count - offset >= 4 + len else { break }
            let payload = Data(bytes[(offset + 4)..<(offset + 4 + len)])
            offset += 4 + len
            var r = QDataStreamReader(payload, features: features)
            do {
                let list = try r.variantList()
                if handshakeDone {
                    guard let msg = decode(list) else { continue }
                    if case .heartBeat(let v) = msg {
                        write(encode(.heartBeatReply(v)))
                    } else {
                        batch.append(msg)
                    }
                } else {
                    handleHandshake(list)
                }
            } catch {
                NSLog("iQuasselCC: failed to decode message: \(error)")
            }
        }
        if offset > 0 { buffer = Data(bytes[offset...]) }
        if !batch.isEmpty {
            // One main-thread hop per network read instead of one per message.
            DispatchQueue.main.async {
                for m in batch { self.delegate?.connection(self, received: m) }
            }
        }
    }

    // MARK: TLS

    private func evaluate(trust: SecTrust?) {
        guard let trust = trust else {
            fail("TLS handshake failed")
            return
        }
        let info = CoreConnection.certificateInfo(trust: trust, host: config.host)
        if info.trustedBySystem || (config.trustedFingerprint.map { $0.lowercased() == info.sha256.lowercased() } ?? false) {
            sendClientInit()
            return
        }
        pendingTrust = trust
        setPhase(.awaitingCertificateDecision(info))
    }

    static func certificateInfo(trust: SecTrust, host: String) -> CoreCertificateInfo {
        SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString))
        var error: CFError?
        let ok = SecTrustEvaluateWithError(trust, &error)
        var sha256 = "", sha1 = "", subject = ""
        let leaf = (SecTrustCopyCertificateChain(trust) as? [SecCertificate])?.first
        if let cert = leaf {
            let der = SecCertificateCopyData(cert) as Data
            sha256 = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined(separator: ":")
            sha1 = Insecure.SHA1.hash(data: der).map { String(format: "%02x", $0) }.joined(separator: ":")
            subject = (SecCertificateCopySubjectSummary(cert) as String?) ?? ""
        }
        return CoreCertificateInfo(sha256: sha256, sha1: sha1, subject: subject, trustedBySystem: ok)
    }

    // MARK: Handshake

    private func sendClientInit() {
        setPhase(.handshaking)
        let feats = QuasselFeature.clientSupported
        sendHandshake([
            "MsgType": .str("ClientInit"),
            "ClientVersion": .str(CoreConnection.clientVersion),
            "ClientDate": .str(CoreConnection.clientDate),
            "Features": .uint(QuasselFeature.legacyBits(feats)),
            "FeatureList": .strings(feats.map { $0.rawValue }.sorted()),
        ])
    }

    private func sendLogin() {
        setPhase(.loggingIn)
        sendHandshake(["MsgType": .str("ClientLogin"), "User": .str(config.user), "Password": .str(config.password)])
    }

    private func sendHandshake(_ map: [String: QVariant]) {
        var list = [QVariant]()
        for (k, v) in map.sorted(by: { $0.key < $1.key }) {
            list.append(.bytes(k))
            list.append(v)
        }
        write(list)
    }

    private func handleHandshake(_ list: [QVariant]) {
        var map = [String: QVariant]()
        var i = 0
        while i + 1 < list.count {
            map[list[i].text] = list[i + 1]
            i += 2
        }
        let type = map.str("MsgType")
        switch type {
        case "ClientInitAck":
            let coreList = map.strings("FeatureList")
            coreFeatureList = coreList
            let coreSet: Set<QuasselFeature>
            if map["FeatureList"] != nil {
                coreSet = Set(coreList.compactMap { QuasselFeature(rawValue: $0) })
            } else {
                coreSet = QuasselFeature.fromLegacy(UInt32(truncatingIfNeeded: map.int("CoreFeatures")))
            }
            features = coreSet.intersection(QuasselFeature.clientSupported)
            DispatchQueue.main.async { self.delegate?.connection(self, initAck: map) }
            if map.bool("Configured", true) {
                sendLogin()
            } else {
                setPhase(.needsSetup)
            }
        case "ClientInitReject":
            fail(map.str("Error", "Core rejected the client"))
        case "CoreSetupAck":
            DispatchQueue.main.async { self.delegate?.connection(self, setupResult: nil) }
            sendLogin()
        case "CoreSetupReject":
            let err = map.str("Error", "Setup failed")
            DispatchQueue.main.async { self.delegate?.connection(self, setupResult: err) }
        case "ClientLoginAck":
            setPhase(.initializing)
        case "ClientLoginReject":
            fail(map.str("Error", "Login failed").replacingOccurrences(of: "<br>", with: " ")
                .replacingOccurrences(of: "<b>", with: "").replacingOccurrences(of: "</b>", with: ""))
        case "SessionInit":
            handshakeDone = true
            timeoutTimer?.cancel()
            let state = map["SessionState"]?.mapValue ?? [:]
            DispatchQueue.main.async { self.delegate?.connection(self, sessionInit: state) }
            setPhase(.connected)
            startHeartbeat()
        default:
            NSLog("iQuasselCC: unknown handshake message \(type)")
        }
    }

    private func startHeartbeat() {
        heartbeatTimer?.cancel()
        let t = DispatchSource.makeTimerSource(queue: queue)
        t.schedule(deadline: .now() + 30, repeating: 30)
        t.setEventHandler { [weak self] in
            self?.write(self?.encode(.heartBeat(.dateTime(QDateTimeValue(date: Date())))) ?? [])
        }
        heartbeatTimer = t
        t.resume()
    }

    // MARK: SignalProxy

    private func decode(_ list: [QVariant]) -> SignalProxyMessage? {
        guard let first = list.first, let type = first.int64Value else { return nil }
        let rest = Array(list.dropFirst())
        switch type {
        case 1:
            guard rest.count >= 3 else { return nil }
            return .sync(className: rest[0].text, objectName: rest[1].text, slot: rest[2].text,
                         params: Array(rest.dropFirst(3)))
        case 2:
            guard rest.count >= 1 else { return nil }
            return .rpcCall(name: rest[0].text, params: Array(rest.dropFirst()))
        case 3:
            guard rest.count >= 2 else { return nil }
            return .initRequest(className: rest[0].text, objectName: rest[1].text)
        case 4:
            guard rest.count >= 2 else { return nil }
            let params = Array(rest.dropFirst(2))
            var data = [String: QVariant]()
            if params.count == 1, case .map(let m) = params[0] {
                data = m
            } else {
                var i = 0
                while i + 1 < params.count {
                    data[params[i].text] = params[i + 1]
                    i += 2
                }
            }
            return .initData(className: rest[0].text, objectName: rest[1].text, data: data)
        case 5:
            return .heartBeat(rest.first ?? .invalid)
        case 6:
            return .heartBeatReply(rest.first ?? .invalid)
        default:
            return nil
        }
    }

    private func encode(_ msg: SignalProxyMessage) -> [QVariant] {
        switch msg {
        case let .sync(c, o, s, p):
            return [.int(1), .bytes(c), .bytes(o), .bytes(s)] + p
        case let .rpcCall(n, p):
            return [.int(2), .bytes(n)] + p
        case let .initRequest(c, o):
            return [.int(3), .bytes(c), .bytes(o)]
        case let .initData(c, o, d):
            var l: [QVariant] = [.int(4), .bytes(c), .bytes(o)]
            for (k, v) in d { l.append(.bytes(k)); l.append(v) }
            return l
        case .heartBeat(let v):
            return [.int(5), v]
        case .heartBeatReply(let v):
            return [.int(6), v]
        }
    }

    private func write(_ list: [QVariant]) {
        guard !list.isEmpty, let t = transport else { return }
        var payload = QDataStreamWriter(features: features)
        payload.variantList(list)
        var framed = QDataStreamWriter(features: [])
        framed.u32(UInt32(payload.data.count))
        t.send(framed.data + payload.data)
    }
}
