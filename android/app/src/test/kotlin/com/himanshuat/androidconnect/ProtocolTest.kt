package com.himanshuat.androidconnect

import com.himanshuat.androidconnect.protocol.AuthChallenge
import com.himanshuat.androidconnect.protocol.AuthResponse
import com.himanshuat.androidconnect.protocol.CallState
import com.himanshuat.androidconnect.protocol.Clipboard
import com.himanshuat.androidconnect.protocol.ControlMessage
import com.himanshuat.androidconnect.protocol.FileOffer
import com.himanshuat.androidconnect.protocol.Frame
import com.himanshuat.androidconnect.protocol.Framing
import com.himanshuat.androidconnect.protocol.Hello
import com.himanshuat.androidconnect.protocol.NotifActionDef
import com.himanshuat.androidconnect.protocol.NotifPosted
import com.himanshuat.androidconnect.protocol.Ping
import com.himanshuat.androidconnect.protocol.ProtocolCodec
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProtocolTest {

    private fun roundTrip(msg: ControlMessage) {
        val decoded = ProtocolCodec.decode(ProtocolCodec.encode(msg))
        assertEquals(msg, decoded)
    }

    @Test fun `every message type round-trips`() {
        roundTrip(Hello(pv = 1, id = "mac-1", name = "MacBook", plat = "macos", caps = listOf("clipboard", "files")))
        roundTrip(Ping("n1"))
        roundTrip(AuthChallenge("bm9uY2U="))
        roundTrip(AuthResponse(cert = "Y2VydERFUg==", sig = "c2lnbmF0dXJl"))
        roundTrip(Clipboard(text = "hello world"))
        roundTrip(FileOffer(transferId = "t1", name = "photo.jpg", size = 12345, mime = "image/jpeg"))
        roundTrip(
            NotifPosted(
                key = "k1", appName = "Messages", pkg = "com.google.android.apps.messaging",
                title = "Mom", text = "call me", actions = listOf(NotifActionDef("reply", "Reply", remoteInput = true)),
            ),
        )
        roundTrip(CallState(callId = "c1", state = "ringing", direction = "incoming", number = "+15551234567"))
    }

    @Test fun `discriminator is t and comes first`() {
        assertEquals("""{"t":"ping","nonce":"abc"}""", ProtocolCodec.encodeToString(Ping("abc")))
    }

    @Test fun `required-with-default fields are on the wire`() {
        // clipboard.contentType defaults to "text" but must still be serialized (schema-required).
        assertTrue(ProtocolCodec.encodeToString(Clipboard(text = "x")).contains(""""contentType":"text""""))
    }

    @Test fun `null optionals are omitted`() {
        val json = ProtocolCodec.encodeToString(
            Hello(pv = 1, id = "a", name = "b", plat = "android", caps = emptyList()),
        )
        assertFalse(json.contains("appVersion"))
    }

    @Test fun `unknown or malformed payloads decode to null`() {
        assertNull(ProtocolCodec.decodeOrNull("""{"t":"somethingNew","x":1}""".encodeToByteArray()))
        assertNull(ProtocolCodec.decodeOrNull("not json".encodeToByteArray()))
    }

    @Test fun `frames round-trip through a stream in order`() {
        val jsonPayload = ProtocolCodec.encode(Clipboard(text = "copy me"))
        val transferId = ByteArray(Framing.TRANSFER_ID_LEN) { it.toByte() }
        val binPayload = Framing.binaryPayload(transferId, byteArrayOf(1, 2, 3, 4, 5))

        val buffer = ByteArrayOutputStream()
        Framing.write(buffer, Framing.TYPE_JSON, jsonPayload)
        Framing.write(buffer, Framing.TYPE_BINARY, binPayload)

        val input = ByteArrayInputStream(buffer.toByteArray())
        val f1 = Framing.read(input)
        val f2 = Framing.read(input)
        val f3 = Framing.read(input) // clean EOF

        assertEquals(Frame(Framing.TYPE_JSON, jsonPayload), f1)
        assertEquals(Frame(Framing.TYPE_BINARY, binPayload), f2)
        assertNull(f3)

        // and the binary payload splits back cleanly
        val (id, data) = Framing.splitBinaryPayload(f2!!.payload)
        assertTrue(id.contentEquals(transferId))
        assertTrue(data.contentEquals(byteArrayOf(1, 2, 3, 4, 5)))
    }
}
