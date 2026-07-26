//
//  DeviceIdentity.swift
//  androidconnect
//
//  The Mac's persistent TLS identity: a P-256 key in the Keychain plus a self-signed certificate.
//  The SHA-256 of the cert DER is the fingerprint we pin during pairing (see /protocol §4).
//

import CryptoKit
import Foundation
import Security

/// Everything the transport needs to present this device over TLS. `@unchecked Sendable`: the CF
/// members are read-only and thread-safe for our use.
nonisolated struct Identity: @unchecked Sendable {
    let secIdentity: SecIdentity
    let certificate: SecCertificate
    let certificateDER: Data
    let fingerprint: String
    let deviceId: String
    let deviceName: String
}

enum IdentityError: Error {
    case publicKeyUnavailable
    case certificateBuildFailed
    case identityCreationFailed
    case keychain(OSStatus)
    case security(String)
}

nonisolated enum DeviceIdentity {
    private static let keyTag = Data("dev.freeholt.androidconnect.identity.key".utf8)
    private static let certLabel = "AndroidConnect Identity"
    private static let deviceIdKey = "ac.deviceId"

    // MARK: - Public

    /// Loads the persistent identity, creating the key/cert on first run.
    static func loadOrCreate(deviceName: String) throws -> Identity {
        let key = try loadPrivateKey() ?? generatePersistentPrivateKey()
        let certificate: SecCertificate
        if let existing = try loadCertificate() {
            certificate = existing
        } else {
            let (cert, _) = try makeSelfSignedCertificate(for: key, commonName: "AndroidConnect (\(deviceName))")
            try storeCertificate(cert)
            certificate = cert
        }
        guard let secIdentity = createIdentity(for: certificate) else {
            throw IdentityError.identityCreationFailed
        }
        let der = SecCertificateCopyData(certificate) as Data
        return Identity(
            secIdentity: secIdentity,
            certificate: certificate,
            certificateDER: der,
            fingerprint: fingerprint(of: der),
            deviceId: deviceId(),
            deviceName: deviceName,
        )
    }

    /// SHA-256 of DER bytes as lowercase hex — the pinned fingerprint format.
    static func fingerprint(of der: Data) -> String {
        SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
    }

    /// Verifies an ECDSA-SHA256 `signature` over `data` made by the key in `certDER`. Returns that
    /// cert's fingerprint if the signature is valid (proving the peer holds the key), else nil.
    /// This is how the Mac authenticates the phone, since it can't verify a client cert over TLS.
    static func verify(signature: Data, over data: Data, certDER: Data) -> String? {
        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData),
              let publicKey = SecCertificateCopyKey(certificate) else { return nil }
        let ok = SecKeyVerifySignature(
            publicKey, .ecdsaSignatureMessageX962SHA256, data as CFData, signature as CFData, nil)
        return ok ? fingerprint(of: certDER) : nil
    }

    // MARK: - Certificate construction (pure; unit-tested without the Keychain)

    static func makeSelfSignedCertificate(
        for privateKey: SecKey,
        commonName: String,
    ) throws -> (certificate: SecCertificate, der: Data) {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw IdentityError.publicKeyUnavailable
        }
        var error: Unmanaged<CFError>?
        guard let pubPoint = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            throw IdentityError.security("public key export failed")
        }

        // SubjectPublicKeyInfo { AlgorithmIdentifier { ecPublicKey, prime256v1 }, BIT STRING point }
        let spki = DER.sequence([
            DER.sequence([OID.ecPublicKey, OID.prime256v1]),
            DER.bitString(pubPoint),
        ])

        // Name = SEQUENCE { SET { SEQUENCE { commonName-OID, UTF8String } } }
        let name = DER.sequence([DER.set([DER.sequence([OID.commonName, DER.utf8String(commonName)])])])

        var serial = Data((0..<16).map { _ in UInt8.random(in: 0...255) })
        serial[serial.startIndex] = (serial[serial.startIndex] & 0x7F) | 0x01 // positive, minimal

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "yyMMddHHmmss'Z'"
        let now = Date()
        let validity = DER.sequence([
            DER.utcTime(formatter.string(from: now.addingTimeInterval(-86_400))),
            DER.utcTime(formatter.string(from: now.addingTimeInterval(3_650 * 86_400))),
        ])

        let sigAlg = DER.sequence([OID.ecdsaWithSHA256])
        let tbs = DER.sequence([
            DER.explicit(0, DER.integer(2)), // version v3
            DER.integer(serial),
            sigAlg,
            name,      // issuer == subject (self-signed)
            validity,
            name,
            spki,
        ])

        guard let signature = SecKeyCreateSignature(
            privateKey, .ecdsaSignatureMessageX962SHA256, tbs as CFData, &error,
        ) as Data? else {
            throw IdentityError.security("signing failed")
        }

        let certDER = DER.sequence([tbs, sigAlg, DER.bitString(signature)])
        guard let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw IdentityError.certificateBuildFailed
        }
        return (certificate, certDER)
    }

    /// Ephemeral (non-persistent) key — used by tests to exercise cert building without the Keychain.
    static func generateEphemeralPrivateKey() throws -> SecKey {
        try makeKey(persistent: false)
    }

    // MARK: - Keychain

    private static func generatePersistentPrivateKey() throws -> SecKey {
        try makeKey(persistent: true)
    }

    private static func makeKey(persistent: Bool) throws -> SecKey {
        var privateAttrs: [String: Any] = [:]
        if persistent {
            privateAttrs[kSecAttrIsPermanent as String] = true
            privateAttrs[kSecAttrApplicationTag as String] = keyTag
        }
        let attrs: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: privateAttrs,
        ]
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attrs as CFDictionary, &error) else {
            throw IdentityError.security("key generation failed")
        }
        return key
    }

    private static func loadPrivateKey() throws -> SecKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassKey,
            kSecAttrApplicationTag as String: keyTag,
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecReturnRef as String: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess: return (out as! SecKey)
        case errSecItemNotFound: return nil
        default: throw IdentityError.keychain(status)
        }
    }

    private static func loadCertificate() throws -> SecCertificate? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecAttrLabel as String: certLabel,
            kSecReturnRef as String: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        switch status {
        case errSecSuccess: return (out as! SecCertificate)
        case errSecItemNotFound: return nil
        default: throw IdentityError.keychain(status)
        }
    }

    private static func storeCertificate(_ certificate: SecCertificate) throws {
        let add: [String: Any] = [
            kSecClass as String: kSecClassCertificate,
            kSecValueRef as String: certificate,
            kSecAttrLabel as String: certLabel,
        ]
        let status = SecItemAdd(add as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else {
            throw IdentityError.keychain(status)
        }
    }

    private static func createIdentity(for certificate: SecCertificate) -> SecIdentity? {
        var identity: SecIdentity?
        let status = SecIdentityCreateWithCertificate(nil, certificate, &identity)
        return status == errSecSuccess ? identity : nil
    }

    private static func deviceId() -> String {
        if let existing = UserDefaults.standard.string(forKey: deviceIdKey) { return existing }
        let new = UUID().uuidString
        UserDefaults.standard.set(new, forKey: deviceIdKey)
        return new
    }
}
