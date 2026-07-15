//
//  Connection.swift
//  androidconnect
//
//  Wraps one NWConnection: TLS bring-up, frame in/out, message decode. Runs on its own queue and
//  reports events via a Sendable callback. See /protocol §2–3.
//

import Foundation
import Network

enum ConnectionEvent: Sendable {
    case ready(peerFingerprint: String)
    case message(Message)
    case binaryChunk(transferId: Data, data: Data)
    case closed
    case failed(String)
}

nonisolated final class Connection: @unchecked Sendable {
    let isServer: Bool
    private let connection: NWConnection
    private let queue: DispatchQueue
    private var buffer = Data()
    private var onEvent: (@Sendable (ConnectionEvent) -> Void)?
    private var peerFingerprint = ""

    init(_ connection: NWConnection, isServer: Bool, queue: DispatchQueue) {
        self.connection = connection
        self.isServer = isServer
        self.queue = queue
    }

    func start(onEvent: @escaping @Sendable (ConnectionEvent) -> Void) {
        self.onEvent = onEvent
        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.peerFingerprint = self.currentPeerFingerprint() ?? ""
                self.onEvent?(.ready(peerFingerprint: self.peerFingerprint))
                self.receiveLoop()
            case .failed(let error):
                self.onEvent?(.failed(error.localizedDescription))
            case .cancelled:
                self.onEvent?(.closed)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    func send(_ message: Message) {
        guard let payload = try? ProtocolCodec.encode(message) else { return }
        sendFrame(type: Framing.typeJSON, payload: payload)
    }

    func sendBinary(transferId: Data, data: Data) {
        sendFrame(type: Framing.typeBinary, payload: Framing.binaryPayload(transferId: transferId, data: data))
    }

    func cancel() {
        connection.cancel()
    }

    // MARK: - Private

    private func sendFrame(type: UInt8, payload: Data) {
        let frame = Framing.encode(type: type, payload: payload)
        connection.send(content: frame, completion: .contentProcessed { _ in })
    }

    private func receiveLoop() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.buffer.append(data)
                self.drainFrames()
            }
            if let error {
                self.onEvent?(.failed(error.localizedDescription))
                return
            }
            if isComplete {
                self.onEvent?(.closed)
                return
            }
            self.receiveLoop()
        }
    }

    private func drainFrames() {
        do {
            while let frame = try Framing.decode(from: &buffer) {
                switch frame.type {
                case Framing.typeJSON:
                    if let message = ProtocolCodec.decodeOrNil(frame.payload) {
                        onEvent?(.message(message))
                    }
                case Framing.typeBinary:
                    if let (transferId, data) = Framing.splitBinaryPayload(frame.payload) {
                        onEvent?(.binaryChunk(transferId: transferId, data: data))
                    }
                default:
                    break // unknown frame type — ignore per protocol
                }
            }
        } catch {
            onEvent?(.failed("bad frame: \(error)"))
            cancel()
        }
    }

    private func currentPeerFingerprint() -> String? {
        guard let metadata = connection.metadata(definition: NWProtocolTLS.definition)
            as? NWProtocolTLS.Metadata else { return nil }
        return TLSParams.peerLeafFingerprint(metadata.securityProtocolMetadata)
    }
}
