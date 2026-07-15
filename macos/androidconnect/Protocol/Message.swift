//
//  Message.swift
//  androidconnect
//
//  The control-message catalog from /protocol/PROTOCOL.md §3. Mirrors the Kotlin `ControlMessage`
//  hierarchy exactly — this is the wire contract. JSON with a `t` discriminator.
//

import Foundation

// Each payload carries its own `t` so encoding a payload emits the discriminator; the `Message`
// enum reads `t` to pick the right case on decode. All types are `nonisolated` value types so the
// networking layer can encode/decode them off the main actor.

nonisolated struct Hello: Codable, Equatable, Sendable {
    var t = "hello"
    var pv: Int
    var id: String
    var name: String
    var plat: String
    var appVersion: String?
    var caps: [String]
}

nonisolated struct Ping: Codable, Equatable, Sendable {
    var t = "ping"
    var nonce: String
}

nonisolated struct Pong: Codable, Equatable, Sendable {
    var t = "pong"
    var nonce: String
}

nonisolated struct PairRequest: Codable, Equatable, Sendable {
    var t = "pairRequest"
    var id: String
    var name: String
    var plat: String
    var fp: String
    var token: String?
}

nonisolated struct PairResponse: Codable, Equatable, Sendable {
    var t = "pairResponse"
    var accepted: Bool
    var id: String?
    var name: String?
    var plat: String?
    var fp: String?
    var reason: String?
}

nonisolated struct Clipboard: Codable, Equatable, Sendable {
    var t = "clipboard"
    var contentType = "text"
    var text: String
}

nonisolated struct NotifActionDef: Codable, Equatable, Sendable {
    var id: String
    var title: String
    var remoteInput = false
}

nonisolated struct NotifPosted: Codable, Equatable, Sendable {
    var t = "notifPosted"
    var key: String
    var appName: String
    var pkg: String
    var title: String?
    var text: String?
    var when: Int?
    var actions: [NotifActionDef]?
}

nonisolated struct NotifRemoved: Codable, Equatable, Sendable {
    var t = "notifRemoved"
    var key: String
}

nonisolated struct NotifAction: Codable, Equatable, Sendable {
    var t = "notifAction"
    var key: String
    var actionId: String
    var reply: String?
}

nonisolated struct NotifDismiss: Codable, Equatable, Sendable {
    var t = "notifDismiss"
    var key: String
}

nonisolated struct FileOffer: Codable, Equatable, Sendable {
    var t = "fileOffer"
    var transferId: String
    var name: String
    var size: Int
    var mime: String?
}

nonisolated struct FileAccept: Codable, Equatable, Sendable {
    var t = "fileAccept"
    var transferId: String
}

nonisolated struct FileReject: Codable, Equatable, Sendable {
    var t = "fileReject"
    var transferId: String
    var reason: String?
}

nonisolated struct FileComplete: Codable, Equatable, Sendable {
    var t = "fileComplete"
    var transferId: String
    var sha256: String?
}

nonisolated struct FileError: Codable, Equatable, Sendable {
    var t = "fileError"
    var transferId: String
    var message: String
}

nonisolated struct CallState: Codable, Equatable, Sendable {
    var t = "callState"
    var callId: String
    var state: String       // ringing | active | dialing | disconnected
    var direction: String   // incoming | outgoing
    var number: String?
    var contactName: String?
}

nonisolated struct CallAction: Codable, Equatable, Sendable {
    var t = "callAction"
    var callId: String
    var action: String      // answer | decline | end | mute | unmute
}

/// A decoded control message. Encodes/decodes with a `t` discriminator (see [ProtocolCodec]).
nonisolated enum Message: Codable, Equatable, Sendable {
    case hello(Hello)
    case ping(Ping)
    case pong(Pong)
    case pairRequest(PairRequest)
    case pairResponse(PairResponse)
    case clipboard(Clipboard)
    case notifPosted(NotifPosted)
    case notifRemoved(NotifRemoved)
    case notifAction(NotifAction)
    case notifDismiss(NotifDismiss)
    case fileOffer(FileOffer)
    case fileAccept(FileAccept)
    case fileReject(FileReject)
    case fileComplete(FileComplete)
    case fileError(FileError)
    case callState(CallState)
    case callAction(CallAction)

    private enum TypeKey: String, CodingKey { case t }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: TypeKey.self)
        let t = try container.decode(String.self, forKey: .t)
        switch t {
        case "hello": self = .hello(try Hello(from: decoder))
        case "ping": self = .ping(try Ping(from: decoder))
        case "pong": self = .pong(try Pong(from: decoder))
        case "pairRequest": self = .pairRequest(try PairRequest(from: decoder))
        case "pairResponse": self = .pairResponse(try PairResponse(from: decoder))
        case "clipboard": self = .clipboard(try Clipboard(from: decoder))
        case "notifPosted": self = .notifPosted(try NotifPosted(from: decoder))
        case "notifRemoved": self = .notifRemoved(try NotifRemoved(from: decoder))
        case "notifAction": self = .notifAction(try NotifAction(from: decoder))
        case "notifDismiss": self = .notifDismiss(try NotifDismiss(from: decoder))
        case "fileOffer": self = .fileOffer(try FileOffer(from: decoder))
        case "fileAccept": self = .fileAccept(try FileAccept(from: decoder))
        case "fileReject": self = .fileReject(try FileReject(from: decoder))
        case "fileComplete": self = .fileComplete(try FileComplete(from: decoder))
        case "fileError": self = .fileError(try FileError(from: decoder))
        case "callState": self = .callState(try CallState(from: decoder))
        case "callAction": self = .callAction(try CallAction(from: decoder))
        default:
            throw DecodingError.dataCorrupted(
                .init(codingPath: decoder.codingPath, debugDescription: "unknown message type: \(t)"))
        }
    }

    func encode(to encoder: Encoder) throws {
        switch self {
        case .hello(let m): try m.encode(to: encoder)
        case .ping(let m): try m.encode(to: encoder)
        case .pong(let m): try m.encode(to: encoder)
        case .pairRequest(let m): try m.encode(to: encoder)
        case .pairResponse(let m): try m.encode(to: encoder)
        case .clipboard(let m): try m.encode(to: encoder)
        case .notifPosted(let m): try m.encode(to: encoder)
        case .notifRemoved(let m): try m.encode(to: encoder)
        case .notifAction(let m): try m.encode(to: encoder)
        case .notifDismiss(let m): try m.encode(to: encoder)
        case .fileOffer(let m): try m.encode(to: encoder)
        case .fileAccept(let m): try m.encode(to: encoder)
        case .fileReject(let m): try m.encode(to: encoder)
        case .fileComplete(let m): try m.encode(to: encoder)
        case .fileError(let m): try m.encode(to: encoder)
        case .callState(let m): try m.encode(to: encoder)
        case .callAction(let m): try m.encode(to: encoder)
        }
    }
}
