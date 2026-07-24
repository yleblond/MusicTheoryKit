import XCTest
@testable import NetEngine

final class LocalNetworkAddressTests: XCTestCase {
    func testIPv4AddressesLookLikeValidDottedQuads() {
        // Can't assert a specific address (depends on the machine/CI's actual network
        // interfaces, possibly none in a sandboxed CI runner), only that whatever comes back
        // is well-formed and never the loopback address a real LAN peer couldn't use anyway.
        for address in LocalNetworkAddress.ipv4Addresses() {
            let parts = address.split(separator: ".")
            XCTAssertEqual(parts.count, 4, "\(address) should be a dotted-quad IPv4 address")
            for part in parts {
                XCTAssertNotNil(UInt8(part), "\(address)'s octet \(part) should fit in 0...255")
            }
            XCTAssertNotEqual(address, "127.0.0.1", "loopback isn't reachable from another device")
        }
    }
}
