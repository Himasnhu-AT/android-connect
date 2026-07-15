//
//  ProtocolCodec.swift
//  androidconnect
//
//  JSON encode/decode for control messages, with a `t` discriminator. The exact JSON shape is the
//  wire contract shared with the Android `ProtocolCodec`.
//

import Foundation

nonisolated enum ProtocolCodec {
    static let protocolVersion = 1

    nonisolated static func encode(_ message: Message) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try encoder.encode(message)
    }

    nonisolated static func encodeToString(_ message: Message) throws -> String {
        String(decoding: try encode(message), as: UTF8.self)
    }

    nonisolated static func decode(_ data: Data) throws -> Message {
        try JSONDecoder().decode(Message.self, from: data)
    }

    /// Decodes, returning nil for malformed or unknown-type payloads (never throws).
    nonisolated static func decodeOrNil(_ data: Data) -> Message? {
        try? decode(data)
    }
}
