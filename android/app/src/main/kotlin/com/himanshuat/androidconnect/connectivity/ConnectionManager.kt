package com.himanshuat.androidconnect.connectivity

import android.content.Context
import android.util.Log
import com.himanshuat.androidconnect.LocalPrefs
import com.himanshuat.androidconnect.pairing.DeviceIdentity
import com.himanshuat.androidconnect.pairing.PairedPeer
import android.net.Uri
import com.himanshuat.androidconnect.features.CallHandler
import com.himanshuat.androidconnect.features.ClipboardHandler
import com.himanshuat.androidconnect.features.FileTransferHandler
import com.himanshuat.androidconnect.features.NotificationSink
import com.himanshuat.androidconnect.pairing.TrustStore
import com.himanshuat.androidconnect.protocol.AuthChallenge
import com.himanshuat.androidconnect.protocol.AuthResponse
import com.himanshuat.androidconnect.protocol.CallAction
import com.himanshuat.androidconnect.protocol.Clipboard
import com.himanshuat.androidconnect.protocol.ControlMessage
import com.himanshuat.androidconnect.protocol.FileAccept
import com.himanshuat.androidconnect.protocol.FileComplete
import com.himanshuat.androidconnect.protocol.FileOffer
import com.himanshuat.androidconnect.protocol.FileReject
import com.himanshuat.androidconnect.protocol.Hello
import com.himanshuat.androidconnect.protocol.NotifAction
import com.himanshuat.androidconnect.protocol.NotifDismiss
import com.himanshuat.androidconnect.protocol.PairRequest
import com.himanshuat.androidconnect.protocol.PairResponse
import com.himanshuat.androidconnect.protocol.Ping
import com.himanshuat.androidconnect.protocol.Pong
import com.himanshuat.androidconnect.protocol.ProtocolCodec
import java.util.Base64
import java.util.UUID
import javax.net.ssl.SSLServerSocket
import javax.net.ssl.SSLSocket
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/**
 * Orchestrates discovery + the (single, v1) live connection: advertise, browse, dial, TLS pinning,
 * the Hello handshake, and pairing. Exposes observable state as StateFlows. Mirrors the macOS
 * ConnectionManager. See /protocol §1–4.
 */
class ConnectionManager(context: Context) {
    private val appContext = context.applicationContext
    private val prefs = LocalPrefs(appContext)
    private val trust = TrustStore(appContext)
    private val gate = PairingGate(trust)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    val deviceId: String = prefs.deviceId
    val deviceName: String get() = prefs.deviceName

    private val identity = DeviceIdentity.loadOrCreate(deviceId, "AndroidConnect ($deviceName)")
    private val transport = TlsTransport(identity) { gate.accepts(it) }
    private val discovery = NsdDiscovery(appContext)
    private val clipboard = ClipboardHandler(appContext)
    val fileTransfer = FileTransferHandler(appContext, scope)
    private val callHandler = CallHandler(appContext)

    val fingerprint: String get() = identity.fingerprint

    /** Set by NotificationRelayService while it's connected, so the Mac can reply/dismiss. */
    var notificationSink: NotificationSink? = null

    /** Forward a locally-observed notification (or its removal) to the Mac. */
    fun sendNotification(message: ControlMessage) {
        active?.send(message)
    }

    private val _discovered = MutableStateFlow<List<DiscoveredPeer>>(emptyList())
    val discovered: StateFlow<List<DiscoveredPeer>> = _discovered.asStateFlow()
    private val _paired = MutableStateFlow(trust.all())
    val paired: StateFlow<List<PairedPeer>> = _paired.asStateFlow()
    private val _status = MutableStateFlow("Starting…")
    val status: StateFlow<String> = _status.asStateFlow()
    private val _pairingMode = MutableStateFlow(false)
    val pairingMode: StateFlow<Boolean> = _pairingMode.asStateFlow()

    private var serverSocket: SSLServerSocket? = null
    private var active: Connection? = null
    private var activeFingerprint = ""
    private var lastPeerHello: Hello? = null
    private var started = false
    private var connectingId: String? = null
    private var pingJob: Job? = null

    fun start() {
        if (started) return
        started = true
        _paired.value = trust.all()
        scope.launch {
            try {
                val server = transport.serverSocket(0)
                serverSocket = server
                discovery.register(deviceId, server.localPort, txt())
                discovery.discover { peers -> updateDiscovered(peers.filter { it.plat == "macos" }) }
                clipboard.onLocalChange = { text -> active?.send(Clipboard(text = text)) }
                clipboard.start()
                fileTransfer.onSend = { message -> active?.send(message) }
                fileTransfer.onSendBinary = { transferId, chunk -> active?.sendBinary(transferId, chunk) }
                callHandler.onCallState = { state -> active?.send(state) }
                callHandler.start()
                _status.value = "Waiting for Mac…"
                acceptLoop(server)
            } catch (e: Exception) {
                _status.value = "Error: ${e.message}"
            }
        }
    }

    private fun acceptLoop(server: SSLServerSocket) {
        scope.launch(Dispatchers.IO) {
            while (isActive) {
                val socket = try {
                    server.accept() as SSLSocket
                } catch (_: Exception) {
                    break
                }
                launch {
                    try {
                        Log.i(TAG, "inbound TCP from ${socket.inetAddress?.hostAddress}; starting TLS")
                        socket.startHandshake()
                        Log.i(TAG, "inbound TLS handshake OK")
                        adopt(Connection(socket, isServer = true, scope))
                    } catch (e: Exception) {
                        Log.e(TAG, "inbound handshake FAILED: ${e.javaClass.simpleName}: ${e.message}", e)
                        runCatching { socket.close() }
                    }
                }
            }
        }
    }

    fun setPairing(on: Boolean) {
        _pairingMode.value = on
        gate.setPairingMode(on)
    }

    // The phone is always the TLS client — it dials the Mac (the Mac can't verify a client cert as a
    // TLS server, and on many networks only phone→Mac connections get through). It proves its own
    // identity to the Mac at the app layer via [AuthChallenge]/[AuthResponse].
    fun pair(peer: DiscoveredPeer) = dial(peer.host, peer.port, peer.fingerprint)

    /** Pair from a scanned `ac://pair?host=&port=&fp=&token=` QR (bypasses mDNS resolution). */
    fun pairViaQr(url: String) {
        val uri = Uri.parse(url)
        val host = uri.getQueryParameter("host") ?: return
        val port = uri.getQueryParameter("port")?.toIntOrNull() ?: return
        val fingerprint = uri.getQueryParameter("fp") ?: return
        dial(host, port, fingerprint)
    }

    private fun dial(host: String, port: Int, fingerprint: String) {
        gate.allow(fingerprint)
        scope.launch(Dispatchers.IO) {
            try {
                Log.i(TAG, "dialing $host:$port (pinning fp=$fingerprint)")
                adopt(Connection(transport.connect(host, port), isServer = false, scope))
                Log.i(TAG, "dial handshake OK → peerFp=$activeFingerprint")
            } catch (e: Exception) {
                Log.e(TAG, "dial to $host:$port FAILED: ${e.javaClass.simpleName}: ${e.message}", e)
                connectingId = null // let auto-reconnect retry after a failed dial
                _status.value = "Couldn't connect: ${e.message}"
            }
        }
    }

    fun unpair(peer: PairedPeer) {
        trust.remove(peer.id)
        _paired.value = trust.all()
        if (lastPeerHello?.id == peer.id) active?.close()
    }

    /** User picked a file to send to the paired Mac. */
    fun sendFile(uri: Uri) = fileTransfer.sendFile(uri)

    fun stop() {
        clipboard.stop()
        callHandler.stop()
        discovery.stop()
        active?.close()
        runCatching { serverSocket?.close() }
        scope.cancel()
    }

    private fun adopt(connection: Connection) {
        active?.close()
        active = connection
        connectingId = null
        activeFingerprint = connection.peerFingerprint
        lastPeerHello = null
        connection.send(hello())
        // We prove our identity in response to the Mac's authChallenge (below), not via a pairRequest.
        connection.receiveLoop(
            onMessage = { handleMessage(it, connection) },
            onBinary = { id, data -> fileTransfer.handleChunk(id, data) },
            onClosed = {
                if (active === connection) {
                    pingJob?.cancel()
                    active = null
                    connectingId = null
                    _status.value = if (trust.all().isEmpty()) "Waiting for Mac…" else "Reconnecting…"
                    maybeAutoConnect()
                }
            },
        )
        startPingLoop(connection)
    }

    /** Update the nearby list and, if a paired Mac is visible and we're idle, reconnect silently. */
    private fun updateDiscovered(peers: List<DiscoveredPeer>) {
        _discovered.value = peers
        maybeAutoConnect()
    }

    /** Silent reconnect: the phone dials any trusted Mac it discovers (the phone is always client). */
    private fun maybeAutoConnect() {
        if (active != null || connectingId != null) return
        val peer = _discovered.value.firstOrNull { trust.isTrusted(it.fingerprint) } ?: return
        connectingId = peer.id
        pair(peer)
    }

    private fun startPingLoop(connection: Connection) {
        pingJob?.cancel()
        pingJob = scope.launch(Dispatchers.IO) {
            while (isActive && active === connection) {
                delay(PING_INTERVAL_MS)
                if (active === connection) connection.send(Ping(UUID.randomUUID().toString()))
            }
        }
    }

    private fun handleMessage(message: ControlMessage, connection: Connection) {
        when (message) {
            is Hello -> {
                lastPeerHello = message
                _status.value =
                    if (trust.isTrusted(activeFingerprint)) "Connected to ${message.name}"
                    else "Pairing ${message.name}…"
            }

            is Ping -> connection.send(Pong(message.nonce))

            is AuthChallenge -> {
                // Prove we hold our identity key: sign the Mac's nonce and return our certificate.
                Log.i(TAG, "answering authChallenge")
                val sig = identity.sign(message.nonce.toByteArray())
                connection.send(
                    AuthResponse(
                        cert = Base64.getEncoder().encodeToString(identity.certificateDer),
                        sig = Base64.getEncoder().encodeToString(sig),
                    ),
                )
            }

            is Clipboard -> clipboard.apply(message.text)

            is FileOffer -> fileTransfer.handleOffer(message)
            is FileAccept -> fileTransfer.handleAccept(message.transferId)
            is FileReject -> fileTransfer.handleReject(message.transferId)
            is FileComplete -> fileTransfer.handleComplete(message.transferId)

            is NotifAction -> notificationSink?.act(message.key, message.actionId, message.reply)
            is NotifDismiss -> notificationSink?.dismiss(message.key)

            is CallAction -> callHandler.action(message.action)

            is PairRequest -> {
                if (_pairingMode.value || gate.accepts(activeFingerprint)) {
                    // Bind trust to the REAL TLS cert fingerprint, not the claimed one.
                    trust.add(PairedPeer(message.id, message.name, message.plat, activeFingerprint))
                    _paired.value = trust.all()
                    connection.send(
                        PairResponse(
                            accepted = true, id = deviceId, name = deviceName,
                            plat = "android", fp = identity.fingerprint,
                        ),
                    )
                    setPairing(false)
                    _status.value = "Connected to ${message.name}"
                } else {
                    connection.send(PairResponse(accepted = false, reason = "not accepting pairs"))
                }
            }

            is PairResponse -> {
                val hello = lastPeerHello
                if (message.accepted && hello != null) {
                    trust.add(PairedPeer(hello.id, hello.name, hello.plat, activeFingerprint))
                    _paired.value = trust.all()
                    _status.value = "Connected to ${hello.name}"
                } else {
                    _status.value = "Pairing rejected"
                }
            }

            else -> Unit // feature messages arrive in later milestones
        }
    }

    private fun hello() = Hello(
        pv = ProtocolCodec.PROTOCOL_VERSION,
        id = deviceId,
        name = deviceName,
        plat = "android",
        appVersion = "0.1.0",
        caps = listOf("clipboard", "files", "notifications", "calls"),
    )

    private fun txt() = mapOf(
        "id" to deviceId,
        "name" to deviceName,
        "plat" to "android",
        "fp" to identity.fingerprint,
        "pv" to ProtocolCodec.PROTOCOL_VERSION.toString(),
    )

    private companion object {
        const val PING_INTERVAL_MS = 20_000L
        const val TAG = "ACDebug"
    }
}
