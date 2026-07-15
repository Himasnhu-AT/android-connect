//
//  Frame.swift
//  androidconnect
//
//  Transport framing: `[uint32 BE length][uint8 type][payload]`, length counts type+payload.
//  See /protocol/PROTOCOL.md §2. Mirrors the Kotlin `Framing`.
//

import Foundation

nonisolated struct Frame: Equatable, Sendable {
    let type: UInt8
    let payload: Data
}

nonisolated enum FrameError: Error, Equatable {
    case illegalLength(Int)
}

nonisolated enum Framing {
    static let typeJSON: UInt8 = 0x00
    static let typeBinary: UInt8 = 0x01

    static let maxFrame = 1 << 20        // 1 MiB
    static let maxChunk = 64 * 1024      // binary chunk cap so control frames interleave
    static let transferIDLen = 16

    /// Serializes one frame.
    nonisolated static func encode(type: UInt8, payload: Data) -> Data {
        precondition(payload.count + 1 <= maxFrame, "frame too large")
        let len = UInt32(payload.count + 1)
        var out = Data(capacity: 5 + payload.count)
        out.append(UInt8(truncatingIfNeeded: len >> 24))
        out.append(UInt8(truncatingIfNeeded: len >> 16))
        out.append(UInt8(truncatingIfNeeded: len >> 8))
        out.append(UInt8(truncatingIfNeeded: len))
        out.append(type)
        out.append(payload)
        return out
    }

    /// Pops one complete frame off the front of `buffer`, or returns nil if a whole frame isn't
    /// buffered yet. Throws on an illegal length so the caller can drop the connection.
    nonisolated static func decode(from buffer: inout Data) throws -> Frame? {
        guard buffer.count >= 5 else { return nil }
        let head = [UInt8](buffer.prefix(5))
        let len = (Int(head[0]) << 24) | (Int(head[1]) << 16) | (Int(head[2]) << 8) | Int(head[3])
        guard len >= 1, len <= maxFrame else { throw FrameError.illegalLength(len) }
        let total = 4 + len
        guard buffer.count >= total else { return nil }
        let type = head[4]
        let payloadStart = buffer.index(buffer.startIndex, offsetBy: 5)
        let payloadEnd = buffer.index(buffer.startIndex, offsetBy: total)
        let payload = Data(buffer[payloadStart..<payloadEnd])
        buffer.removeSubrange(buffer.startIndex..<payloadEnd)
        return Frame(type: type, payload: payload)
    }

    /// Builds a binary-chunk payload: `[16-byte transferId][data]`.
    nonisolated static func binaryPayload(transferId: Data, data: Data) -> Data {
        precondition(transferId.count == transferIDLen, "transferId must be \(transferIDLen) bytes")
        return transferId + data
    }

    /// Splits a binary-chunk payload back into `(transferId, data)`, or nil if too short.
    nonisolated static func splitBinaryPayload(_ payload: Data) -> (transferId: Data, data: Data)? {
        guard payload.count >= transferIDLen else { return nil }
        let idEnd = payload.index(payload.startIndex, offsetBy: transferIDLen)
        return (Data(payload[payload.startIndex..<idEnd]), Data(payload[idEnd...]))
    }
}
