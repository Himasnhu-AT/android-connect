//
//  TLSParams.swift
//  androidconnect
//
//  Builds Network.framework parameters for our mutually-authenticated TLS with custom
//  fingerprint pinning (self-signed certs, no CA). See /protocol §4.
//

import Foundation
import Network
import Security

nonisolated enum TLSParams {
    static let serviceType = "_androidconnect._tcp"

    /// TLS parameters that present `identity` and accept the peer only if `accept(fingerprint)`
    /// returns true. `accept` runs during the handshake with the peer's leaf-cert fingerprint.
    static func make(
        identity: Identity,
        accept: @escaping @Sendable (String) -> Bool,
    ) -> NWParameters {
        let tls = NWProtocolTLS.Options()
        let sec = tls.securityProtocolOptions

        if let secIdentity = sec_identity_create(identity.secIdentity) {
            sec_protocol_options_set_local_identity(sec, secIdentity)
        }
        // Server-auth only. macOS Network.framework cannot verify a peer *client* certificate as a
        // TLS server (the verify block is never invoked for it — it just fails the handshake), so we
        // don't request one. The phone (always the TLS client) verifies OUR cert by fingerprint via
        // its own trust manager, then proves its own identity at the app layer (authChallenge, §4).
        sec_protocol_options_set_peer_authentication_required(sec, false)
        sec_protocol_options_set_min_tls_protocol_version(sec, .TLSv12)
        _ = accept  // retained for API symmetry; unused now that we don't verify a client cert

        let params = NWParameters(tls: tls)
        params.includePeerToPeer = true
        return params
    }

    /// SHA-256 (hex) of the peer's leaf certificate, from the TLS handshake metadata.
    static func peerLeafFingerprint(_ metadata: sec_protocol_metadata_t) -> String? {
        var fingerprint: String?
        sec_protocol_metadata_access_peer_certificate_chain(metadata) { secCertificate in
            guard fingerprint == nil else { return } // leaf is the first cert
            let certificate = sec_certificate_copy_ref(secCertificate).takeRetainedValue()
            let der = SecCertificateCopyData(certificate) as Data
            fingerprint = DeviceIdentity.fingerprint(of: der)
        }
        return fingerprint
    }
}
