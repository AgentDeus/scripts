import XCTest

final class ProtocolTests: XCTestCase {
    let features: Set<QuasselFeature> = [.longTime, .longMessageId, .senderPrefixes, .richMessages, .extendedFeatures,
                                         .synchronizedMarkerLine, .bufferActivitySync, .syncedCoreInfo]

    func data(_ hex: String) -> Data {
        let clean = hex.filter { $0.isHexDigit }
        var d = Data(capacity: clean.count / 2)
        var i = clean.startIndex
        while i < clean.endIndex {
            let j = clean.index(i, offsetBy: 2)
            d.append(UInt8(clean[i..<j], radix: 16)!)
            i = j
        }
        return d
    }

    func decode(_ hex: String) throws -> [QVariant] {
        var r = QDataStreamReader(data(hex), features: features)
        let list = try r.variantList()
        XCTAssertTrue(r.atEnd, "trailing bytes")
        return list
    }

    func handshakeMap(_ list: [QVariant]) -> [String: QVariant] {
        var m = [String: QVariant]()
        var i = 0
        while i + 1 < list.count { m[list[i].text] = list[i + 1]; i += 2 }
        return m
    }

    /// Every captured frame must decode and re-encode to the identical bytes.
    func testRoundTripAllFixtures() throws {
        let all: [(String, String)] = [
            ("ClientInitAck", Fixtures.ClientInitAck), ("ClientLoginAck", Fixtures.ClientLoginAck),
            ("SessionInit", Fixtures.SessionInit), ("backlog", Fixtures.backlog),
            ("displayMsgType1", Fixtures.displayMsgType1), ("displayMsgType4", Fixtures.displayMsgType4),
            ("displayMsgType32", Fixtures.displayMsgType32), ("displayMsgType128", Fixtures.displayMsgType128),
            ("initBufferSyncer", Fixtures.initBufferSyncer), ("initBufferViewManager", Fixtures.initBufferViewManager),
            ("initCoreInfo", Fixtures.initCoreInfo), ("initNetwork", Fixtures.initNetwork),
            ("joinIrcUsers", Fixtures.joinIrcUsers),
        ]
        for (name, hex) in all {
            let list = try decode(hex)
            var w = QDataStreamWriter(features: features)
            w.variantList(list)
            let hasMessages = name == "backlog" || name.hasPrefix("displayMsg")
            if hasMessages {
                // The core sends some empty message fields as null QByteArrays; we keep them as empty
                // strings, so compare the decoded messages instead of raw bytes.
                var r = QDataStreamReader(w.data, features: features)
                let again = try r.variantList()
                XCTAssertEqual(messages(again), messages(list), "message round trip mismatch for \(name)")
                XCTAssertFalse(messages(list).isEmpty)
            } else {
                XCTAssertEqual(w.data, data(hex), "round trip mismatch for \(name)")
            }
        }
    }

    private func messages(_ l: [QVariant]) -> [IrcMessage] {
        l.flatMap { v -> [IrcMessage] in
            if let m = v.messageValue { return [m] }
            if case .list(let inner) = v { return messages(inner) }
            return []
        }
    }

    func testClientInitAck() throws {
        let m = handshakeMap(try decode(Fixtures.ClientInitAck))
        XCTAssertEqual(m.str("MsgType"), "ClientInitAck")
        XCTAssertTrue(m.bool("Configured"))
        XCTAssertTrue(m.strings("FeatureList").contains("LongMessageId"))
    }

    func testSessionInit() throws {
        let m = handshakeMap(try decode(Fixtures.SessionInit))
        XCTAssertEqual(m.str("MsgType"), "SessionInit")
        let state = m["SessionState"]?.mapValue ?? [:]
        let buffers = (state["BufferInfos"]?.listValue ?? []).compactMap { $0.bufferInfoValue }
        XCTAssertTrue(buffers.contains { $0.name == "#test" && $0.type == .channel })
        XCTAssertTrue(buffers.contains { $0.type == .status })
        XCTAssertEqual(state["NetworkIds"]?.listValue.first?.int32Value, 1)
        let identity = state["Identities"]?.listValue.first?.mapValue ?? [:]
        XCTAssertEqual(identity.str("identityName"), "Default")
    }

    func testDisplayMessage() throws {
        let list = try decode(Fixtures.displayMsgType1)
        XCTAssertEqual(list[0].intValue, 2)
        XCTAssertEqual(list[1].text, "2displayMsg(Message)")
        let msg = try XCTUnwrap(list[2].messageValue)
        XCTAssertEqual(msg.type, .plain)
        XCTAssertTrue(msg.flags.contains(.highlight))
        XCTAssertEqual(msg.senderNick, "alice")
        XCTAssertEqual(msg.bufferInfo.name, "#test")
        XCTAssertTrue(msg.content.hasPrefix("probe: hello \u{02}bold\u{02}"))
        XCTAssertGreaterThan(msg.time.timeIntervalSince1970, 1_700_000_000)

        let action = try XCTUnwrap(try decode(Fixtures.displayMsgType4)[2].messageValue)
        XCTAssertEqual(action.type, .action)
        XCTAssertEqual(action.content, "waves")
    }

    func testBacklog() throws {
        let list = try decode(Fixtures.backlog)
        XCTAssertEqual(list[1].text, "BacklogManager")
        XCTAssertEqual(list[3].text, "receiveBacklog")
        let msgs = list[9].listValue.compactMap { $0.messageValue }
        XCTAssertEqual(msgs.count, 3)
    }

    func testNetworkInitData() throws {
        let list = try decode(Fixtures.initNetwork)
        XCTAssertEqual(list[0].intValue, 4)
        var data = [String: QVariant]()
        var i = 3
        while i + 1 < list.count { data[list[i].text] = list[i + 1]; i += 2 }
        let net = Network(id: 1)
        net.applyInit(data)
        XCTAssertEqual(net.networkName, "Local")
        XCTAssertTrue(net.isConnected)
        XCTAssertEqual(net.myNick, "probe")
        XCTAssertEqual(net.prefixChars, ["~", "&", "@", "%", "+"])
        let chan = try XCTUnwrap(net.channel("#test"))
        XCTAssertEqual(chan.userModes["probe"], "o")
        XCTAssertEqual(net.prefixes(forModes: "o"), "@")
        XCTAssertEqual(net.settings.servers.first?.host, "127.0.0.1")

        // Live join of another user
        let join = try decode(Fixtures.joinIrcUsers)
        net.handleChannelSync(name: "#test", slot: join[3].text, Array(join.dropFirst(4)))
        XCTAssertNotNil(net.user("alice"))
        XCTAssertEqual(chan.userModes.count, 2)
        net.handleUserSync(nick: "alice", slot: "setNick", [.str("alice2")])
        XCTAssertNotNil(net.user("alice2"))
        XCTAssertNotNil(chan.userModes["alice2"])
        net.handleUserSync(nick: "alice2", slot: "quit", [])
        XCTAssertNil(net.user("alice2"))
        XCTAssertEqual(chan.userModes.count, 1)
    }

    func testBufferSyncerInit() throws {
        let list = try decode(Fixtures.initBufferSyncer)
        XCTAssertEqual(list[1].text, "BufferSyncer")
        XCTAssertEqual(list[3].text, "Activities")
        XCTAssertEqual(list[4].listValue.count % 2, 0)
    }

    func testOutgoingSyncEncoding() throws {
        // Equivalent of: Sync BacklogManager "" requestBacklog(BufferId 2, MsgId -1, MsgId -1, 3, 0)
        var w = QDataStreamWriter(features: features)
        w.variantList([.int(1), .bytes("BacklogManager"), .bytes(""), .bytes("requestBacklog"),
                       .bufferId(2), .msgId(-1), .msgId(-1), .int(3), .int(0)])
        var r = QDataStreamReader(w.data, features: features)
        let back = try r.variantList()
        XCTAssertEqual(back.count, 9)
        XCTAssertEqual(back[4].int32Value, 2)
        XCTAssertEqual(back[5].int64Value, -1)
        // MsgId must be 64 bit with LongMessageId
        XCTAssertEqual(w.data.count, 4 + (5 + 4) + (5 + 4 + 14) + (5 + 4) + (5 + 4 + 14) +
                       (5 + 4 + 9 + 4) + 2 * (5 + 4 + 6 + 8) + 2 * (5 + 4))
    }

    func testInvalidVariantRoundTrip() throws {
        var w = QDataStreamWriter(features: [])
        w.variantList([.invalid, .int(5)])
        var r = QDataStreamReader(w.data, features: [])
        let l = try r.variantList()
        XCTAssertTrue(l[0].isNull)
        XCTAssertEqual(l[1].intValue, 5)
        XCTAssertTrue(r.atEnd)
    }

    func testDateTimeConversion() {
        let d = Date(timeIntervalSince1970: 1_795_178_372.5)
        let q = QDateTimeValue(date: d)
        XCTAssertEqual(q.date!.timeIntervalSince1970, d.timeIntervalSince1970, accuracy: 0.001)
    }

    func testFeatureBits() {
        XCTAssertEqual(QuasselFeature.legacyBits([.synchronizedMarkerLine, .bufferActivitySync]), 0x0801)
        XCTAssertEqual(QuasselFeature.fromLegacy(0x100000), [.longMessageId])
    }
}
