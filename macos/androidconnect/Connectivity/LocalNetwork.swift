//
//  LocalNetwork.swift
//  androidconnect
//
//  Finds this Mac's LAN IPv4 so the pairing QR can carry a directly-dialable host:port
//  (bypassing mDNS resolution on the phone).
//

import Darwin
import Foundation

nonisolated enum LocalNetwork {
    /// Best-guess primary IPv4 (prefers en0 / Wi-Fi), or nil if offline.
    static func primaryIPv4() -> String? {
        var address: String?
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return nil }
        defer { freeifaddrs(ifaddrPtr) }

        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let flags = Int32(ptr.pointee.ifa_flags)
            guard (flags & (IFF_UP | IFF_RUNNING)) == (IFF_UP | IFF_RUNNING),
                  (flags & IFF_LOOPBACK) == 0,
                  let addr = ptr.pointee.ifa_addr,
                  addr.pointee.sa_family == UInt8(AF_INET)
            else { continue }

            let name = String(cString: ptr.pointee.ifa_name)
            guard name.hasPrefix("en") else { continue }

            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: host)
            if name == "en0" { break } // Wi-Fi is usually en0 — prefer it
        }
        return address
    }
}
