import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// This device's own non-loopback IPv4 addresses (e.g. "192.168.1.42") — the address another
/// device on the same LAN needs to reach a server this process is listening on (WebConsole's
/// HTTP server, the virtual keyboard, the jam-session server). `localhost`/`127.0.0.1` only
/// ever resolves from the SAME device, so a server meant to be opened from someone else's
/// phone/laptop browser needs this instead.
public enum LocalNetworkAddress {
    public static func ipv4Addresses() -> [String] {
        var addresses: [String] = []
        var ifaddrPtr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddrPtr) == 0, let first = ifaddrPtr else { return [] }
        defer { freeifaddrs(ifaddrPtr) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = Int32(current.pointee.ifa_flags)
            guard (flags & IFF_UP) == IFF_UP, (flags & IFF_LOOPBACK) == 0 else { continue }
            guard var addr = current.pointee.ifa_addr?.pointee, addr.sa_family == UInt8(AF_INET) else { continue }

            var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            let status = getnameinfo(&addr, socklen_t(addr.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
            if status == 0 {
                let address = hostname.withUnsafeBufferPointer { String(cString: $0.baseAddress!) }
                addresses.append(address)
            }
        }
        return addresses
    }
}
