//
//  DER.swift
//  androidconnect
//
//  Minimal DER (ASN.1) encoder — just enough to build a self-signed P-256 X.509 certificate for the
//  TLS identity. Keeps the app dependency-free (no swift-certificates). See DeviceIdentity.
//

import Foundation

nonisolated enum DER {
    /// Tag + definite length + value.
    static func tlv(_ tag: UInt8, _ value: Data) -> Data {
        var out = Data([tag])
        out.append(encodeLength(value.count))
        out.append(value)
        return out
    }

    static func sequence(_ items: [Data]) -> Data {
        tlv(0x30, items.reduce(Data(), +))
    }

    static func set(_ items: [Data]) -> Data {
        tlv(0x31, items.reduce(Data(), +))
    }

    /// INTEGER from big-endian magnitude bytes (assumed already non-negative & minimally encoded).
    static func integer(_ magnitude: Data) -> Data {
        tlv(0x02, magnitude)
    }

    static func integer(_ value: Int) -> Data {
        var v = value
        var bytes: [UInt8] = []
        repeat {
            bytes.insert(UInt8(v & 0xFF), at: 0)
            v >>= 8
        } while v != 0
        if bytes[0] & 0x80 != 0 { bytes.insert(0x00, at: 0) } // keep positive
        return tlv(0x02, Data(bytes))
    }

    static func bitString(_ data: Data) -> Data {
        tlv(0x03, Data([0x00]) + data) // 0 unused bits
    }

    static func utf8String(_ string: String) -> Data {
        tlv(0x0C, Data(string.utf8))
    }

    static func utcTime(_ string: String) -> Data {
        tlv(0x17, Data(string.utf8))
    }

    static func null() -> Data {
        Data([0x05, 0x00])
    }

    /// Context-specific, constructed, EXPLICIT `[tagNumber]`.
    static func explicit(_ tagNumber: UInt8, _ value: Data) -> Data {
        tlv(0xA0 | tagNumber, value)
    }

    /// OBJECT IDENTIFIER from dotted components, e.g. `[1, 2, 840, 10045, 2, 1]`.
    static func oid(_ components: [UInt]) -> Data {
        precondition(components.count >= 2)
        var bytes: [UInt8] = [UInt8(components[0] * 40 + components[1])]
        for component in components.dropFirst(2) {
            bytes.append(contentsOf: base128(component))
        }
        return tlv(0x06, Data(bytes))
    }

    private static func base128(_ value: UInt) -> [UInt8] {
        var v = value
        var stack: [UInt8] = [UInt8(v & 0x7F)]
        v >>= 7
        while v > 0 {
            stack.append(UInt8((v & 0x7F) | 0x80))
            v >>= 7
        }
        return stack.reversed()
    }

    private static func encodeLength(_ length: Int) -> Data {
        if length < 0x80 { return Data([UInt8(length)]) }
        var len = length
        var bytes: [UInt8] = []
        while len > 0 {
            bytes.insert(UInt8(len & 0xFF), at: 0)
            len >>= 8
        }
        return Data([UInt8(0x80 | bytes.count)] + bytes)
    }
}

// Common OIDs for an EC / ECDSA-SHA256 self-signed cert.
nonisolated enum OID {
    static let ecPublicKey = DER.oid([1, 2, 840, 10045, 2, 1])
    static let prime256v1 = DER.oid([1, 2, 840, 10045, 3, 1, 7])
    static let ecdsaWithSHA256 = DER.oid([1, 2, 840, 10045, 4, 3, 2])
    static let commonName = DER.oid([2, 5, 4, 3])
}
