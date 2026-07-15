//
//  Discovery.swift
//  androidconnect
//
//  mDNS/Bonjour advertise (NWListener) + browse (NWBrowser) for `_androidconnect._tcp`.
//  TXT record carries id/name/plat/fp/pv (see /protocol §1).
//

import Foundation
import Network

nonisolated struct DiscoveredPeer: Sendable, Equatable, Identifiable {
    var id: String
    var name: String
    var plat: String
    var fingerprint: String
    var endpoint: NWEndpoint
}

nonisolated final class Discovery: @unchecked Sendable {
    private let queue: DispatchQueue
    private var listener: NWListener?
    private var browser: NWBrowser?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    func startAdvertising(
        params: NWParameters,
        serviceName: String,
        txt: [String: String],
        onPort: @escaping @Sendable (UInt16) -> Void,
        onInbound: @escaping @Sendable (NWConnection) -> Void,
    ) throws {
        let listener = try NWListener(using: params)
        var record = NWTXTRecord()
        for (key, value) in txt { record[key] = value }
        listener.service = NWListener.Service(name: serviceName, type: TLSParams.serviceType, txtRecord: record)
        listener.newConnectionHandler = { connection in onInbound(connection) }
        listener.stateUpdateHandler = { [weak listener] state in
            if case .ready = state, let port = listener?.port?.rawValue {
                onPort(port)
            }
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    func startBrowsing(onChange: @escaping @Sendable ([DiscoveredPeer]) -> Void) {
        let browser = NWBrowser(
            for: .bonjourWithTXTRecord(type: TLSParams.serviceType, domain: nil),
            using: NWParameters(),
        )
        browser.browseResultsChangedHandler = { results, _ in
            onChange(results.compactMap(Self.peer(from:)))
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        listener?.cancel()
        browser?.cancel()
        listener = nil
        browser = nil
    }

    private static func peer(from result: NWBrowser.Result) -> DiscoveredPeer? {
        guard case let .bonjour(record) = result.metadata else { return nil }
        return DiscoveredPeer(
            id: record["id"] ?? "",
            name: record["name"] ?? "Unknown device",
            plat: record["plat"] ?? "",
            fingerprint: record["fp"] ?? "",
            endpoint: result.endpoint,
        )
    }
}
