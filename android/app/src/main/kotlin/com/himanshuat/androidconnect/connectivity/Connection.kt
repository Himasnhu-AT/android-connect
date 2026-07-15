package com.himanshuat.androidconnect.connectivity

import com.himanshuat.androidconnect.pairing.DeviceIdentity
import com.himanshuat.androidconnect.protocol.ControlMessage
import com.himanshuat.androidconnect.protocol.Framing
import com.himanshuat.androidconnect.protocol.ProtocolCodec
import java.io.BufferedInputStream
import java.io.BufferedOutputStream
import java.io.OutputStream
import java.security.cert.X509Certificate
import javax.net.ssl.SSLSocket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Wraps one TLS socket: frame in/out + message decode, on IO coroutines. See /protocol §2–3.
 * Mirrors the macOS Connection.
 */
class Connection(
    private val socket: SSLSocket,
    val isServer: Boolean,
    private val scope: CoroutineScope,
) {
    private val input = BufferedInputStream(socket.inputStream)
    private val output: OutputStream = BufferedOutputStream(socket.outputStream)
    private val writeMutex = Mutex()

    /** SHA-256 of the peer's leaf cert — valid once the handshake has completed. */
    val peerFingerprint: String by lazy {
        val cert = socket.session.peerCertificates.firstOrNull() as? X509Certificate
        cert?.let { DeviceIdentity.fingerprintOfDer(it.encoded) }.orEmpty()
    }

    fun send(message: ControlMessage) {
        val payload = ProtocolCodec.encode(message)
        scope.launch(Dispatchers.IO) {
            runCatching { writeMutex.withLock { Framing.write(output, Framing.TYPE_JSON, payload) } }
        }
    }

    fun sendBinary(transferId: ByteArray, data: ByteArray) {
        val payload = Framing.binaryPayload(transferId, data)
        scope.launch(Dispatchers.IO) {
            runCatching { writeMutex.withLock { Framing.write(output, Framing.TYPE_BINARY, payload) } }
        }
    }

    fun receiveLoop(
        onMessage: (ControlMessage) -> Unit,
        onBinary: (ByteArray, ByteArray) -> Unit,
        onClosed: () -> Unit,
    ) {
        scope.launch(Dispatchers.IO) {
            try {
                while (isActive) {
                    val frame = Framing.read(input) ?: break
                    when (frame.type) {
                        Framing.TYPE_JSON -> ProtocolCodec.decodeOrNull(frame.payload)?.let(onMessage)
                        Framing.TYPE_BINARY -> {
                            val (id, data) = Framing.splitBinaryPayload(frame.payload)
                            onBinary(id, data)
                        }
                    }
                }
            } catch (_: Exception) {
                // socket closed or read error — fall through to onClosed
            }
            onClosed()
        }
    }

    fun close() {
        runCatching { socket.close() }
    }
}
