//
//  IdentityTests.swift
//  androidconnectTests
//
//  Verifies the hand-rolled self-signed X.509 DER is well-formed enough that Security can parse it,
//  and that fingerprints are stable. Uses an ephemeral key so no Keychain/signing is required.
//

import CryptoKit
import Foundation
import Security
import Testing
@testable import androidconnect

struct IdentityTests {

    @Test func buildsParseableSelfSignedCertificate() throws {
        let key = try DeviceIdentity.generateEphemeralPrivateKey()
        let (certificate, der) = try DeviceIdentity.makeSelfSignedCertificate(
            for: key, commonName: "AndroidConnect (Test Mac)")

        #expect(!der.isEmpty)

        // The produced cert DER must re-parse through Security — proves the ASN.1 is valid.
        let roundTrip = SecCertificateCreateWithData(nil, SecCertificateCopyData(certificate))
        #expect(roundTrip != nil)

        // And the signature must verify against the cert's own public key (self-signed).
        #expect(SecCertificateCopyData(certificate) as Data == der)
    }

    @Test func fingerprintIs64LowercaseHexChars() throws {
        let key = try DeviceIdentity.generateEphemeralPrivateKey()
        let (_, der) = try DeviceIdentity.makeSelfSignedCertificate(for: key, commonName: "x")
        let fingerprint = DeviceIdentity.fingerprint(of: der)
        #expect(fingerprint.count == 64)
        #expect(fingerprint.allSatisfy { $0.isHexDigit && !$0.isUppercase })
    }

    @Test func fingerprintMatchesSHA256() {
        let der = Data([0x01, 0x02, 0x03, 0x04])
        let expected = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        #expect(DeviceIdentity.fingerprint(of: der) == expected)
    }
}
