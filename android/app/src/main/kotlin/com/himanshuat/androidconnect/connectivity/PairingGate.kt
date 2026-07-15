package com.himanshuat.androidconnect.connectivity

import com.himanshuat.androidconnect.pairing.TrustStore

/**
 * Thread-safe policy consulted by the TLS trust manager (which runs on handshake threads) to decide
 * whether to accept a peer's self-signed cert: trusted-and-pinned, or allowed during pairing.
 * Mirrors the macOS PairingGate. See /protocol §4.
 */
class PairingGate(private val trust: TrustStore) {
    private val lock = Any()
    private var pairingMode = false
    private val allowed = mutableSetOf<String>()

    fun accepts(fingerprint: String): Boolean {
        if (fingerprint.isEmpty()) return false
        if (trust.isTrusted(fingerprint)) return true
        synchronized(lock) { return pairingMode || allowed.contains(fingerprint) }
    }

    fun setPairingMode(on: Boolean) = synchronized(lock) { pairingMode = on }

    fun allow(fingerprint: String) {
        if (fingerprint.isEmpty()) return
        synchronized(lock) { allowed.add(fingerprint) }
    }
}
