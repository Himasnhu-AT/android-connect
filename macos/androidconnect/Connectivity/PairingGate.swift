//
//  PairingGate.swift
//  androidconnect
//
//  Thread-safe policy consulted by the TLS verify block (which runs off the main actor) to decide
//  whether to accept a peer's self-signed cert: trusted-and-pinned, or allowed during pairing.
//

import Foundation

nonisolated final class PairingGate: @unchecked Sendable {
    private let trust: TrustStore
    private let lock = NSLock()
    private var pairingMode = false
    private var allowed = Set<String>()

    init(trust: TrustStore) {
        self.trust = trust
    }

    /// Called from the TLS handshake with the peer's leaf-cert fingerprint.
    func accepts(_ fingerprint: String) -> Bool {
        guard !fingerprint.isEmpty else { return false }
        if trust.isTrusted(fingerprint: fingerprint) { return true }
        lock.lock(); defer { lock.unlock() }
        return pairingMode || allowed.contains(fingerprint)
    }

    /// While on, accept any inbound peer (TOFU) — used when the Mac is showing a pairing QR.
    func setPairingMode(_ on: Bool) {
        lock.lock(); defer { lock.unlock() }
        pairingMode = on
    }

    /// Allow one specific fingerprint (e.g. the one we're about to dial for pairing).
    func allow(_ fingerprint: String) {
        guard !fingerprint.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        allowed.insert(fingerprint)
    }
}
