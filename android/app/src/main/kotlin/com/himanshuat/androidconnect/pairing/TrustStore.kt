package com.himanshuat.androidconnect.pairing

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** A device this phone has paired with. Identity is the pinned cert [fingerprint]. */
@Serializable
data class PairedPeer(
    val id: String,
    val name: String,
    val plat: String,
    val fingerprint: String,
)

/**
 * Persists paired peers so reconnects are silent (see /protocol §4). A peer is trusted iff its
 * presented cert fingerprint is pinned here. Backed by SharedPreferences (excluded from backup).
 */
class TrustStore(context: Context) {
    private val prefs = context.applicationContext
        .getSharedPreferences(PREFS, Context.MODE_PRIVATE)
    private val json = Json { ignoreUnknownKeys = true }

    @Synchronized
    fun all(): List<PairedPeer> {
        val raw = prefs.getString(KEY, null) ?: return emptyList()
        return runCatching { json.decodeFromString<List<PairedPeer>>(raw) }.getOrDefault(emptyList())
    }

    @Synchronized
    fun add(peer: PairedPeer) {
        val updated = all().filterNot { it.id == peer.id } + peer
        prefs.edit().putString(KEY, json.encodeToString(updated)).apply()
    }

    @Synchronized
    fun remove(id: String) {
        val updated = all().filterNot { it.id == id }
        prefs.edit().putString(KEY, json.encodeToString(updated)).apply()
    }

    fun isTrusted(fingerprint: String): Boolean = all().any { it.fingerprint == fingerprint }

    fun peer(fingerprint: String): PairedPeer? = all().firstOrNull { it.fingerprint == fingerprint }

    private companion object {
        const val PREFS = "trust_store"
        const val KEY = "peers"
    }
}
