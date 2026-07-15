package com.himanshuat.androidconnect.protocol

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Encodes/decodes [ControlMessage] as JSON with a `t` discriminator, per /protocol/PROTOCOL.md.
 * The exact JSON shape is the wire contract shared with the macOS `Message` enum.
 */
object ProtocolCodec {
    const val PROTOCOL_VERSION = 1

    val json = Json {
        classDiscriminator = "t"     // {"t":"hello", ...}
        encodeDefaults = true        // emit required-with-default fields (e.g. clipboard.contentType)
        explicitNulls = false        // but omit null optionals
        ignoreUnknownKeys = true     // forward-compat: skip fields/messages we don't know
    }

    fun encode(msg: ControlMessage): ByteArray =
        json.encodeToString<ControlMessage>(msg).encodeToByteArray()

    fun encodeToString(msg: ControlMessage): String =
        json.encodeToString<ControlMessage>(msg)

    fun decode(bytes: ByteArray): ControlMessage =
        json.decodeFromString<ControlMessage>(bytes.decodeToString())

    /** Decodes, returning null for malformed or unknown-type payloads (never throws). */
    fun decodeOrNull(bytes: ByteArray): ControlMessage? =
        try {
            decode(bytes)
        } catch (_: Exception) {
            null
        }
}
