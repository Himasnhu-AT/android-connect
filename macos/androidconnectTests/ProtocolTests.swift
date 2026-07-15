//
//  ProtocolTests.swift
//  androidconnectTests
//
//  Verifies the Swift protocol codec matches the wire contract in /protocol (and the Android side).
//

import Foundation
import Testing
@testable import androidconnect

struct ProtocolTests {

    @Test func messagesRoundTrip() throws {
        let messages: [Message] = [
            .hello(Hello(pv: 1, id: "mac-1", name: "MacBook", plat: "macos", caps: ["clipboard", "files"])),
            .ping(Ping(nonce: "n1")),
            .clipboard(Clipboard(text: "hello world")),
            .fileOffer(FileOffer(transferId: "t1", name: "photo.jpg", size: 12345, mime: "image/jpeg")),
            .notifPosted(NotifPosted(key: "k1", appName: "Messages", pkg: "com.example",
                                     title: "Mom", text: "call me",
                                     actions: [NotifActionDef(id: "reply", title: "Reply", remoteInput: true)])),
            .callState(CallState(callId: "c1", state: "ringing", direction: "incoming", number: "+15551234567")),
        ]
        for m in messages {
            let data = try ProtocolCodec.encode(m)
            #expect(try ProtocolCodec.decode(data) == m)
        }
    }

    @Test func decodesAndroidWireFormat() throws {
        // The exact bytes the Android ProtocolCodec emits for Ping("abc").
        let json = Data(#"{"t":"ping","nonce":"abc"}"#.utf8)
        #expect(try ProtocolCodec.decode(json) == .ping(Ping(nonce: "abc")))
    }

    @Test func clipboardContentTypeOnWire() throws {
        let s = try ProtocolCodec.encodeToString(.clipboard(Clipboard(text: "x")))
        #expect(s.contains(#""contentType":"text""#))
    }

    @Test func nullOptionalsOmitted() throws {
        let s = try ProtocolCodec.encodeToString(
            .hello(Hello(pv: 1, id: "a", name: "b", plat: "macos", caps: [])))
        #expect(!s.contains("appVersion"))
    }

    @Test func unknownTypeIsRejected() {
        let json = Data(#"{"t":"somethingNew","x":1}"#.utf8)
        #expect(ProtocolCodec.decodeOrNil(json) == nil)
    }

    @Test func framesRoundTripInOrder() throws {
        let jsonPayload = try ProtocolCodec.encode(.clipboard(Clipboard(text: "copy me")))
        let transferId = Data((0..<16).map { UInt8($0) })
        let binPayload = Framing.binaryPayload(transferId: transferId, data: Data([1, 2, 3, 4, 5]))

        var stream = Data()
        stream.append(Framing.encode(type: Framing.typeJSON, payload: jsonPayload))
        stream.append(Framing.encode(type: Framing.typeBinary, payload: binPayload))

        var buffer = stream
        let f1 = try Framing.decode(from: &buffer)
        let f2 = try Framing.decode(from: &buffer)
        let f3 = try Framing.decode(from: &buffer)

        #expect(f1 == Frame(type: Framing.typeJSON, payload: jsonPayload))
        #expect(f2 == Frame(type: Framing.typeBinary, payload: binPayload))
        #expect(f3 == nil)

        let split = Framing.splitBinaryPayload(try #require(f2).payload)
        #expect(split?.transferId == transferId)
        #expect(split?.data == Data([1, 2, 3, 4, 5]))
    }
}
