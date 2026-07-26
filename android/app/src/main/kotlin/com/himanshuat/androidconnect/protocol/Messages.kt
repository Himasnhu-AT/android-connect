package com.himanshuat.androidconnect.protocol

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

/**
 * The control-message catalog from /protocol/PROTOCOL.md §3.
 *
 * Serialized as JSON with a `t` discriminator via [ProtocolCodec]. Field names here MUST match the
 * protocol spec and the Swift `Message` enum exactly — this is the wire contract.
 */
@Serializable
sealed interface ControlMessage

// ── Session ──────────────────────────────────────────────────────────────────

@Serializable
@SerialName("hello")
data class Hello(
    val pv: Int,
    val id: String,
    val name: String,
    val plat: String,
    val appVersion: String? = null,
    val caps: List<String>,
) : ControlMessage

@Serializable
@SerialName("ping")
data class Ping(val nonce: String) : ControlMessage

@Serializable
@SerialName("pong")
data class Pong(val nonce: String) : ControlMessage

// ── Pairing ──────────────────────────────────────────────────────────────────

@Serializable
@SerialName("pairRequest")
data class PairRequest(
    val id: String,
    val name: String,
    val plat: String,
    val fp: String,
    val token: String? = null,
) : ControlMessage

@Serializable
@SerialName("pairResponse")
data class PairResponse(
    val accepted: Boolean,
    val id: String? = null,
    val name: String? = null,
    val plat: String? = null,
    val fp: String? = null,
    val reason: String? = null,
) : ControlMessage

// Identity proof — macOS can't verify a client cert as a TLS server, so the phone (the TLS client)
// proves possession of its identity key at the app layer: sign the Mac's nonce, return our cert.
@Serializable
@SerialName("authChallenge")
data class AuthChallenge(val nonce: String) : ControlMessage

@Serializable
@SerialName("authResponse")
data class AuthResponse(
    val cert: String,   // base64 DER of our TLS certificate
    val sig: String,    // base64 ECDSA-SHA256 signature over the nonce's UTF-8 bytes
) : ControlMessage

// ── Clipboard ────────────────────────────────────────────────────────────────

@Serializable
@SerialName("clipboard")
data class Clipboard(
    val contentType: String = "text",
    val text: String,
) : ControlMessage

// ── Notifications ────────────────────────────────────────────────────────────

@Serializable
data class NotifActionDef(
    val id: String,
    val title: String,
    val remoteInput: Boolean = false,
)

@Serializable
@SerialName("notifPosted")
data class NotifPosted(
    val key: String,
    val appName: String,
    val pkg: String,
    val title: String? = null,
    val text: String? = null,
    val `when`: Long? = null,
    val actions: List<NotifActionDef>? = null,
) : ControlMessage

@Serializable
@SerialName("notifRemoved")
data class NotifRemoved(val key: String) : ControlMessage

@Serializable
@SerialName("notifAction")
data class NotifAction(
    val key: String,
    val actionId: String,
    val reply: String? = null,
) : ControlMessage

@Serializable
@SerialName("notifDismiss")
data class NotifDismiss(val key: String) : ControlMessage

// ── File transfer ────────────────────────────────────────────────────────────

@Serializable
@SerialName("fileOffer")
data class FileOffer(
    val transferId: String,
    val name: String,
    val size: Long,
    val mime: String? = null,
) : ControlMessage

@Serializable
@SerialName("fileAccept")
data class FileAccept(val transferId: String) : ControlMessage

@Serializable
@SerialName("fileReject")
data class FileReject(val transferId: String, val reason: String? = null) : ControlMessage

@Serializable
@SerialName("fileComplete")
data class FileComplete(val transferId: String, val sha256: String? = null) : ControlMessage

@Serializable
@SerialName("fileError")
data class FileError(val transferId: String, val message: String) : ControlMessage

// ── Calls (control + caller ID only; audio stays on the phone) ───────────────

@Serializable
@SerialName("callState")
data class CallState(
    val callId: String,
    val state: String,      // ringing | active | dialing | disconnected
    val direction: String,  // incoming | outgoing
    val number: String? = null,
    val contactName: String? = null,
) : ControlMessage

@Serializable
@SerialName("callAction")
data class CallAction(
    val callId: String,
    val action: String,     // answer | decline | end | mute | unmute
) : ControlMessage
