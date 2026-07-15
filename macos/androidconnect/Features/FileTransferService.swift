//
//  FileTransferService.swift
//  androidconnect
//
//  File/photo transfer over the binary-chunk frame (type 0x01) + fileOffer/Accept/Complete control
//  messages. The transferId is 16 random bytes, rendered as 32-char hex in control messages and used
//  raw in binary frames. See /protocol §3.
//

import AppKit
import Foundation
import Observation
import Security

@MainActor
@Observable
final class FileTransferService {
    struct Transfer: Identifiable, Equatable {
        let id: String        // hex transferId
        let name: String
        let size: Int
        var transferred: Int
        let incoming: Bool
        var done: Bool
        var failed: Bool
        var progress: Double {
            if done { return 1 }
            return size > 0 ? min(1, Double(transferred) / Double(size)) : 0
        }
    }

    private(set) var transfers: [Transfer] = []

    /// Injected by ConnectionManager to route to the active connection.
    var onSend: ((Message) -> Void)?
    var onSendBinary: ((_ transferId: Data, _ chunk: Data) -> Void)?

    private var incomingHandles: [String: FileHandle] = [:]
    private var pendingOutgoing: [String: URL] = [:]
    private let ioQueue = DispatchQueue(label: "dev.freeholt.androidconnect.filetransfer")

    // MARK: - Sending

    func sendFile(url: URL) {
        let name = url.lastPathComponent
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let id = Self.newTransferIdHex()
        pendingOutgoing[id] = url
        transfers.append(Transfer(id: id, name: name, size: size, transferred: 0, incoming: false, done: false, failed: false))
        onSend?(.fileOffer(FileOffer(transferId: id, name: name, size: size, mime: nil)))
    }

    func handleAccept(_ transferId: String) {
        guard let url = pendingOutgoing.removeValue(forKey: transferId) else { return }
        streamFile(idHex: transferId, url: url)
    }

    func handleReject(_ transferId: String) {
        pendingOutgoing.removeValue(forKey: transferId)
        markFailed(transferId)
    }

    // MARK: - Receiving

    func handleOffer(_ offer: FileOffer) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = offer.name
        panel.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else {
            onSend?(.fileReject(FileReject(transferId: offer.transferId, reason: "declined")))
            return
        }
        FileManager.default.createFile(atPath: url.path, contents: nil)
        guard let handle = try? FileHandle(forWritingTo: url) else {
            onSend?(.fileReject(FileReject(transferId: offer.transferId, reason: "cannot write")))
            return
        }
        incomingHandles[offer.transferId] = handle
        transfers.append(Transfer(id: offer.transferId, name: offer.name, size: offer.size, transferred: 0, incoming: true, done: false, failed: false))
        onSend?(.fileAccept(FileAccept(transferId: offer.transferId)))
    }

    func handleChunk(transferId: Data, data: Data) {
        let id = Self.hex(transferId)
        guard let handle = incomingHandles[id] else { return }
        do {
            try handle.write(contentsOf: data)
            bump(id, by: data.count)
        } catch {
            markFailed(id)
        }
    }

    func handleComplete(_ transferId: String) {
        if let handle = incomingHandles.removeValue(forKey: transferId) {
            try? handle.close()
        }
        markDone(transferId)
    }

    // MARK: - Streaming (background)

    private func streamFile(idHex: String, url: URL) {
        guard let idBytes = Self.data(fromHex: idHex) else { markFailed(idHex); return }
        let onSendBinary = self.onSendBinary
        let progress: @Sendable (Int) -> Void = { n in Task { @MainActor [weak self] in self?.bump(idHex, by: n) } }
        let complete: @Sendable () -> Void = {
            Task { @MainActor [weak self] in
                self?.onSend?(.fileComplete(FileComplete(transferId: idHex, sha256: nil)))
                self?.markDone(idHex)
            }
        }
        let fail: @Sendable () -> Void = { Task { @MainActor [weak self] in self?.markFailed(idHex) } }

        ioQueue.async {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            guard let handle = try? FileHandle(forReadingFrom: url) else { fail(); return }
            defer { try? handle.close() }
            while true {
                let chunk = handle.readData(ofLength: Framing.maxChunk)
                if chunk.isEmpty { break }
                onSendBinary?(idBytes, chunk)
                progress(chunk.count)
            }
            complete()
        }
    }

    // MARK: - Transfer bookkeeping

    private func bump(_ id: String, by count: Int) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[index].transferred += count
    }

    private func markDone(_ id: String) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[index].done = true
    }

    private func markFailed(_ id: String) {
        guard let index = transfers.firstIndex(where: { $0.id == id }) else { return }
        transfers[index].failed = true
    }

    // MARK: - transferId helpers (16 bytes ⇄ hex)

    private static func newTransferIdHex() -> String {
        var bytes = [UInt8](repeating: 0, count: Framing.transferIDLen)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return hex(Data(bytes))
    }

    private static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private static func data(fromHex hex: String) -> Data? {
        guard hex.count % 2 == 0 else { return nil }
        var data = Data(capacity: hex.count / 2)
        var index = hex.startIndex
        while index < hex.endIndex {
            let next = hex.index(index, offsetBy: 2)
            guard let byte = UInt8(hex[index..<next], radix: 16) else { return nil }
            data.append(byte)
            index = next
        }
        return data
    }
}
