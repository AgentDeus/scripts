import Foundation
import Security

/// TCP transport based on Foundation streams. Quassel negotiates TLS *after* the
/// plain-text probe on the same socket (STARTTLS-style), which CFStream supports by
/// setting `kCFStreamPropertySSLSettings` on an already-open stream.
///
/// All callbacks are delivered on the transport's private thread.
final class StreamTransport: NSObject, StreamDelegate {
    enum Event {
        case connected
        case data(Data)
        case tlsEstablished(SecTrust?)
        case closed(Error?)
    }

    let host: String
    let port: Int
    var onEvent: ((Event) -> Void)?

    private var thread: Thread?
    private var input: InputStream?
    private var output: OutputStream?
    private var writeBuffer = Data()
    private var openedStreams = 0
    private var didConnect = false
    private var tlsStarting = false
    private var finished = false
    private let readChunk = 64 * 1024

    init(host: String, port: Int) {
        self.host = host
        self.port = port
    }

    func connect() {
        let t = Thread { [weak self] in self?.threadMain() }
        t.name = "iQuasselCC.transport.\(host)"
        t.qualityOfService = .userInitiated
        thread = t
        t.start()
    }

    func send(_ data: Data) {
        guard let t = thread else { return }
        perform(#selector(doSend(_:)), on: t, with: data as NSData, waitUntilDone: false)
    }

    func startTLS() {
        guard let t = thread else { return }
        perform(#selector(doStartTLS), on: t, with: nil, waitUntilDone: false)
    }

    func close() {
        guard let t = thread else { return }
        perform(#selector(doClose), on: t, with: nil, waitUntilDone: false)
    }

    // MARK: - Thread

    private func threadMain() {
        var i: InputStream?
        var o: OutputStream?
        Stream.getStreamsToHost(withName: host, port: port, inputStream: &i, outputStream: &o)
        guard let inp = i, let out = o else {
            finish(NSError(domain: "iQuasselCC", code: 1, userInfo: [NSLocalizedDescriptionKey: "Could not create socket"]))
            return
        }
        input = inp
        output = out
        for s in [inp, out] as [Stream] {
            s.delegate = self
            s.schedule(in: .current, forMode: .default)
        }
        inp.open()
        out.open()
        while !finished {
            if !RunLoop.current.run(mode: .default, before: Date(timeIntervalSinceNow: 1)) {
                // No sources left
                if finished { break }
                Thread.sleep(forTimeInterval: 0.05)
            }
        }
    }

    @objc private func doSend(_ data: NSData) {
        writeBuffer.append(data as Data)
        flush()
    }

    @objc private func doStartTLS() {
        guard let inp = input, let out = output else { return }
        let settings: [String: Any] = [
            kCFStreamSSLPeerName as String: host,
            // We validate the certificate ourselves (trust-on-first-use, like the Android client).
            kCFStreamSSLValidatesCertificateChain as String: false,
        ]
        let key = Stream.PropertyKey(kCFStreamPropertySSLSettings as String)
        tlsStarting = true
        _ = inp.setProperty(settings, forKey: key)
        _ = out.setProperty(settings, forKey: key)
        // Kick the handshake in case no further events arrive by themselves.
        flush()
    }

    @objc private func doClose() {
        finish(nil, notify: true)
    }

    private func finish(_ error: Error?, notify: Bool = true) {
        if finished { return }
        finished = true
        for s in [input, output].compactMap({ $0 }) as [Stream] {
            s.delegate = nil
            s.remove(from: .current, forMode: .default)
            s.close()
        }
        input = nil
        output = nil
        if notify { onEvent?(.closed(error)) }
    }

    private func checkTLSEstablished(_ stream: Stream) {
        guard tlsStarting else { return }
        let key = Stream.PropertyKey(kCFStreamPropertySSLPeerTrust as String)
        let other: Stream? = stream === input ? output : input
        let value = stream.property(forKey: key) ?? other?.property(forKey: key)
        tlsStarting = false
        var trust: SecTrust?
        if let v = value, CFGetTypeID(v as CFTypeRef) == SecTrustGetTypeID() {
            trust = (v as! SecTrust)
        }
        onEvent?(.tlsEstablished(trust))
    }

    private func flush() {
        guard let out = output, !writeBuffer.isEmpty, out.hasSpaceAvailable else { return }
        let written = writeBuffer.withUnsafeBytes { (ptr: UnsafeRawBufferPointer) -> Int in
            guard let base = ptr.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return out.write(base, maxLength: ptr.count)
        }
        if written > 0 {
            writeBuffer.removeSubrange(0..<written)
        } else if written < 0 {
            finish(out.streamError)
        }
    }

    func stream(_ aStream: Stream, handle eventCode: Stream.Event) {
        switch eventCode {
        case .openCompleted:
            openedStreams += 1
            if openedStreams == 2 && !didConnect {
                didConnect = true
                onEvent?(.connected)
            }
        case .hasBytesAvailable:
            checkTLSEstablished(aStream)
            guard let inp = input else { return }
            var buffer = [UInt8](repeating: 0, count: readChunk)
            var collected = Data()
            while inp.hasBytesAvailable {
                let n = inp.read(&buffer, maxLength: readChunk)
                if n > 0 {
                    collected.append(buffer, count: n)
                } else if n < 0 {
                    finish(inp.streamError)
                    return
                } else {
                    break
                }
            }
            if !collected.isEmpty { onEvent?(.data(collected)) }
        case .hasSpaceAvailable:
            checkTLSEstablished(aStream)
            flush()
        case .errorOccurred:
            finish(aStream.streamError ?? NSError(domain: "iQuasselCC", code: 2,
                                                  userInfo: [NSLocalizedDescriptionKey: "Connection error"]))
        case .endEncountered:
            finish(nil)
        default:
            break
        }
    }
}
