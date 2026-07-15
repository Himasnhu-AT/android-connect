//
//  TrustStore.swift
//  androidconnect
//
//  Persists paired peers so reconnects are silent (see /protocol §4). A peer is trusted iff its
//  presented cert fingerprint is pinned here. Backed by UserDefaults (small, JSON-encoded).
//

import Foundation

nonisolated struct PairedPeer: Codable, Equatable, Sendable, Identifiable {
    var id: String          // peer device UUID
    var name: String
    var plat: String
    var fingerprint: String
}

nonisolated final class TrustStore: @unchecked Sendable {
    static let shared = TrustStore()

    private let key = "ac.trustStore.peers"
    private let defaults: UserDefaults
    private let lock = NSLock()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func all() -> [PairedPeer] {
        lock.lock(); defer { lock.unlock() }
        guard let data = defaults.data(forKey: key),
              let peers = try? JSONDecoder().decode([PairedPeer].self, from: data)
        else { return [] }
        return peers
    }

    func add(_ peer: PairedPeer) {
        lock.lock(); defer { lock.unlock() }
        var peers = decodeLocked()
        peers.removeAll { $0.id == peer.id }
        peers.append(peer)
        encodeLocked(peers)
    }

    func remove(id: String) {
        lock.lock(); defer { lock.unlock() }
        var peers = decodeLocked()
        peers.removeAll { $0.id == id }
        encodeLocked(peers)
    }

    func isTrusted(fingerprint: String) -> Bool {
        all().contains { $0.fingerprint == fingerprint }
    }

    func peer(fingerprint: String) -> PairedPeer? {
        all().first { $0.fingerprint == fingerprint }
    }

    // Callers already hold `lock`.
    private func decodeLocked() -> [PairedPeer] {
        guard let data = defaults.data(forKey: key),
              let peers = try? JSONDecoder().decode([PairedPeer].self, from: data)
        else { return [] }
        return peers
    }

    private func encodeLocked(_ peers: [PairedPeer]) {
        if let data = try? JSONEncoder().encode(peers) {
            defaults.set(data, forKey: key)
        }
    }
}
