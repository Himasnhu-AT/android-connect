//
//  ConnectionManager.swift
//  androidconnect
//
//  Orchestrates discovery + the (single, v1) live connection: advertise, browse, dial, TLS pinning,
//  the Hello handshake, and pairing. Drives observable UI state on the main actor.
//

import Foundation
import Network
import Observation
import os

private let netLog = Logger(subsystem: "dev.freeholt.androidconnect", category: "net")

@MainActor
@Observable
final class ConnectionManager {
    private(set) var discovered: [DiscoveredPeer] = []
    private(set) var connectedPeerName: String?
    private(set) var isPairing = false
    private(set) var statusText = "Starting…"
    private(set) var advertisedPort: UInt16 = 0
    private var pairingToken = ""

    let identity: Identity
    private(set) var pairedPeers: [PairedPeer] = []

    private let trust = TrustStore.shared
    private let gate: PairingGate
    private let queue = DispatchQueue(label: "dev.freeholt.androidconnect.net")
    private let discovery: Discovery
    private let clipboard = ClipboardService()
    private let notifications = NotificationService()
    let fileTransfer = FileTransferService()
    let callService = CallService()
    private var params: NWParameters?
    private var active: Connection?
    private var activeFingerprint = ""
    private var pendingNonce = ""
    private var lastPeerHello: Hello?
    private var pingTask: Task<Void, Never>?
    private var connectingId: String?

    init(identity: Identity) {
        self.identity = identity
        self.gate = PairingGate(trust: trust)
        self.discovery = Discovery(queue: queue)
    }

    func start() {
        refreshPaired()
        let gate = self.gate
        let params = TLSParams.make(identity: identity) { gate.accepts($0) }
        self.params = params
        let q = queue
        do {
            try discovery.startAdvertising(
                params: params,
                serviceName: identity.deviceId,
                txt: txtRecord(),
                onPort: { port in
                    netLog.log("listener up on port \(port, privacy: .public)")
                    Task { @MainActor [weak self] in self?.advertisedPort = port }
                },
            ) { nwConnection in
                netLog.log("inbound TCP connection accepted; starting TLS")
                let wrapper = Connection(nwConnection, isServer: true, queue: q)
                Task { @MainActor [weak self] in self?.adopt(wrapper) }
            }
            discovery.startBrowsing { peers in
                Task { @MainActor [weak self] in self?.updateDiscovered(peers.filter { $0.plat == "android" }) }
            }
            clipboard.onLocalChange = { [weak self] text in
                self?.active?.send(.clipboard(Clipboard(text: text)))
            }
            clipboard.start()
            fileTransfer.onSend = { [weak self] message in self?.active?.send(message) }
            fileTransfer.onSendBinary = { [weak self] transferId, chunk in
                self?.active?.sendBinary(transferId: transferId, data: chunk)
            }
            notifications.configure()
            notifications.onDismiss = { [weak self] key in
                self?.active?.send(.notifDismiss(NotifDismiss(key: key)))
            }
            notifications.onReply = { [weak self] key, actionId, text in
                self?.active?.send(.notifAction(NotifAction(key: key, actionId: actionId, reply: text)))
            }
            callService.onAction = { [weak self] callId, action in
                self?.active?.send(.callAction(CallAction(callId: callId, action: action)))
            }
            statusText = "Waiting for phone…"
        } catch {
            statusText = "Error: \(error.localizedDescription)"
        }
    }

    /// The Mac shows a pairing QR; while shown we accept any inbound peer and pin it.
    func setPairing(_ on: Bool) {
        isPairing = on
        gate.setPairingMode(on)
    }

    /// Dial a discovered peer and initiate pairing (client side).
    func pair(with peer: DiscoveredPeer) {
        guard let params else { return }
        gate.allow(peer.fingerprint)
        let connection = Connection(NWConnection(to: peer.endpoint, using: params), isServer: false, queue: queue)
        adopt(connection)
    }

    func unpair(_ peer: PairedPeer) {
        trust.remove(id: peer.id)
        refreshPaired()
        if connectedPeerName == peer.name {
            active?.cancel()
        }
    }

    /// Payload for the QR the Mac displays (phone scans it). Carries a directly-dialable host:port +
    /// the fingerprint to pin. Returns nil until the listener port + LAN IP are known. See /protocol §4.
    func pairingPayload() -> String? {
        guard advertisedPort != 0, let host = LocalNetwork.primaryIPv4() else { return nil }
        if pairingToken.isEmpty { pairingToken = UUID().uuidString }
        return "ac://pair?host=\(host)&port=\(advertisedPort)&fp=\(identity.fingerprint)&token=\(pairingToken)"
    }

    // MARK: - Connection lifecycle

    private func adopt(_ connection: Connection) {
        active?.cancel()
        active = connection
        activeFingerprint = ""
        lastPeerHello = nil
        connection.start { event in
            Task { @MainActor [weak self] in self?.handle(event, on: connection) }
        }
    }

    private func handle(_ event: ConnectionEvent, on connection: Connection) {
        guard active === connection else { return }
        switch event {
        case .ready:
            connectingId = nil
            activeFingerprint = ""            // no TLS client cert; set once the phone proves itself
            let nonce = Self.makeNonce()
            pendingNonce = nonce
            netLog.log("TLS up (server) — sent hello + authChallenge")
            connection.send(.hello(makeHello()))
            connection.send(.authChallenge(AuthChallenge(nonce: nonce)))
            startPingLoop(connection)
        case .message(let message):
            handleMessage(message, on: connection)
        case .binaryChunk(let transferId, let data):
            fileTransfer.handleChunk(transferId: transferId, data: data)
        case .closed:
            netLog.log("connection closed (isServer=\(connection.isServer, privacy: .public))")
            teardownActive()
        case .failed(let reason):
            netLog.error("connection FAILED (isServer=\(connection.isServer, privacy: .public)): \(reason, privacy: .public)")
            teardownActive()
        }
    }

    private func teardownActive() {
        pingTask?.cancel()
        active = nil
        connectingId = nil
        connectedPeerName = nil
        statusText = pairedPeers.isEmpty ? "Waiting for phone…" : "Reconnecting…"
        maybeAutoConnect()
    }

    /// Update the nearby list and, if a paired phone is visible and we're idle, reconnect silently.
    private func updateDiscovered(_ peers: [DiscoveredPeer]) {
        netLog.log("discovered \(peers.count, privacy: .public) phone(s): \(peers.map { "\($0.name)[\($0.fingerprint.prefix(8))]" }.joined(separator: ", "), privacy: .public)")
        discovered = peers
        maybeAutoConnect()
    }

    /// The Mac is always the TLS *server*: the phone dials us. (macOS Network.framework can't verify
    /// a client cert, so it can't be the TLS client in a mutual scheme; and on many Wi-Fi networks
    /// only phone→Mac connections get through.) So we never dial — the phone drives (re)connection.
    private func maybeAutoConnect() {}

    private func startPingLoop(_ connection: Connection) {
        pingTask?.cancel()
        pingTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(20))
                guard !Task.isCancelled else { break }
                let stillActive = await MainActor.run { [weak self] in self?.active === connection }
                guard stillActive == true else { break }
                connection.send(.ping(Ping(nonce: UUID().uuidString)))
            }
        }
    }

    private func handleMessage(_ message: Message, on connection: Connection) {
        // Until the phone proves its identity (authResponse sets activeFingerprint), honor only the
        // handshake messages — nothing acts on an unauthenticated peer.
        switch message {
        case .hello, .ping, .pong, .authResponse: break
        default: guard !activeFingerprint.isEmpty else { return }
        }
        switch message {
        case .hello(let hello):
            lastPeerHello = hello
            connectedPeerName = hello.name
            statusText = trust.isTrusted(fingerprint: activeFingerprint) ? "Connected to \(hello.name)" : "Pairing \(hello.name)…"

        case .ping(let ping):
            connection.send(.pong(Pong(nonce: ping.nonce)))

        case .pairRequest(let request):
            if isPairing || gate.accepts(activeFingerprint) {
                // Bind trust to the REAL TLS cert fingerprint, not the claimed one.
                trust.add(PairedPeer(id: request.id, name: request.name, plat: request.plat, fingerprint: activeFingerprint))
                refreshPaired()
                connection.send(.pairResponse(PairResponse(
                    accepted: true, id: identity.deviceId, name: identity.deviceName,
                    plat: "macos", fp: identity.fingerprint)))
                setPairing(false)
                connectedPeerName = request.name
                statusText = "Connected to \(request.name)"
            } else {
                connection.send(.pairResponse(PairResponse(accepted: false, reason: "not accepting pairs")))
            }

        case .pairResponse(let response):
            if response.accepted, let hello = lastPeerHello {
                trust.add(PairedPeer(id: hello.id, name: hello.name, plat: hello.plat, fingerprint: activeFingerprint))
                refreshPaired()
                statusText = "Connected to \(hello.name)"
            } else {
                statusText = "Pairing rejected"
            }

        case .authResponse(let response):
            handleAuthResponse(response, on: connection)

        case .clipboard(let clip):
            clipboard.apply(clip.text)

        case .fileOffer(let offer):
            fileTransfer.handleOffer(offer)
        case .fileAccept(let accept):
            fileTransfer.handleAccept(accept.transferId)
        case .fileReject(let reject):
            fileTransfer.handleReject(reject.transferId)
        case .fileComplete(let complete):
            fileTransfer.handleComplete(complete.transferId)

        case .notifPosted(let posted):
            notifications.show(posted)
        case .notifRemoved(let removed):
            notifications.remove(removed.key)

        case .callState(let state):
            callService.update(state)

        default:
            break // callAction/notifAction are Mac→phone only; ignore if echoed back
        }
    }

    /// User picked a file to send to the paired phone.
    func sendFile(_ url: URL) {
        fileTransfer.sendFile(url: url)
    }

    private func refreshPaired() {
        pairedPeers = trust.all()
    }

    /// The phone answered our challenge: verify it holds its identity key, then pair or reconnect.
    private func handleAuthResponse(_ response: AuthResponse, on connection: Connection) {
        guard let certDER = Data(base64Encoded: response.cert),
              let signature = Data(base64Encoded: response.sig),
              let fingerprint = DeviceIdentity.verify(
                  signature: signature, over: Data(pendingNonce.utf8), certDER: certDER)
        else {
            netLog.error("auth FAILED — bad signature; dropping connection")
            connection.cancel()
            return
        }
        activeFingerprint = fingerprint
        netLog.log("phone identity verified fp=\(fingerprint, privacy: .public)")

        let name = lastPeerHello?.name ?? "phone"
        if trust.isTrusted(fingerprint: fingerprint) {
            connectedPeerName = name
            statusText = "Connected to \(name)"
        } else if isPairing || gate.accepts(fingerprint) {
            if let hello = lastPeerHello {
                trust.add(PairedPeer(id: hello.id, name: hello.name, plat: hello.plat, fingerprint: fingerprint))
                refreshPaired()
            }
            connection.send(.pairResponse(PairResponse(
                accepted: true, id: identity.deviceId, name: identity.deviceName,
                plat: "macos", fp: identity.fingerprint)))
            setPairing(false)
            connectedPeerName = name
            statusText = "Connected to \(name)"
        } else {
            connection.send(.pairResponse(PairResponse(accepted: false, reason: "Mac isn't ready to pair")))
            netLog.log("phone not trusted and not in pairing mode — rejected")
            connection.cancel()
        }
    }

    private static func makeNonce() -> String {
        Data((0..<32).map { _ in UInt8.random(in: 0...255) }).base64EncodedString()
    }

    private func makeHello() -> Hello {
        Hello(
            pv: ProtocolCodec.protocolVersion,
            id: identity.deviceId,
            name: identity.deviceName,
            plat: "macos",
            appVersion: "0.1.0",
            caps: ["clipboard", "files", "notifications", "calls"],
        )
    }

    private func txtRecord() -> [String: String] {
        [
            "id": identity.deviceId,
            "name": identity.deviceName,
            "plat": "macos",
            "fp": identity.fingerprint,
            "pv": String(ProtocolCodec.protocolVersion),
        ]
    }
}
