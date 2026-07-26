import XCTest
@testable import AppCore

final class NetworkRoleTests: XCTestCase {
    func testIsServerRoleIsTrueForBothServerTransports() {
        XCTAssertTrue(NetworkRole.server(port: 7777).isServerRole)
        XCTAssertTrue(NetworkRole.gameCenterServer.isServerRole)
        XCTAssertFalse(NetworkRole.standalone.isServerRole)
        XCTAssertFalse(NetworkRole.client(description: "x").isServerRole)
        XCTAssertFalse(NetworkRole.gameCenterClient(description: "x").isServerRole)
    }

    func testIsClientRoleIsTrueForBothClientTransports() {
        XCTAssertTrue(NetworkRole.client(description: "x").isClientRole)
        XCTAssertTrue(NetworkRole.gameCenterClient(description: "x").isClientRole)
        XCTAssertFalse(NetworkRole.standalone.isClientRole)
        XCTAssertFalse(NetworkRole.server(port: 7777).isClientRole)
        XCTAssertFalse(NetworkRole.gameCenterServer.isClientRole)
    }
}
