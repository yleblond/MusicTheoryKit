#if os(macOS)
import XCTest
@testable import AppCore

/// Real end-to-end coverage of the embedded MCP server: an actual HTTP request over a real
/// loopback socket, through `MCPServer`'s bridge into the MCP Swift SDK's transport, all the
/// way to `ImprovSession.handleMenuAction`/`handleMenuListsRequest`'s already-existing dispatch.
/// Not a unit test of an isolated function — this is the one piece of the whole feature that
/// can't be manually verified against a real Claude Desktop from this environment, so it's
/// exercised here instead of only trusting the pieces compile.
final class MCPServerTests: XCTestCase {
    /// A fixed, high, unlikely-to-collide port per test — `makeTestSession()` gives each test
    /// its own in-memory store, but `MCPServer.start(port:)` binds a real OS socket, which two
    /// tests running concurrently on the SAME port would genuinely conflict over.
    private func post(_ body: String, port: UInt16, path: String = "/mcp") throws -> (status: Int, data: Data) {
        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)\(path)")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = Data(body.utf8)

        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: (Int, Data) = (0, Data())
        nonisolated(unsafe) var requestError: Error?
        URLSession.shared.dataTask(with: request) { data, response, error in
            requestError = error
            result = ((response as? HTTPURLResponse)?.statusCode ?? 0, data ?? Data())
            semaphore.signal()
        }.resume()
        semaphore.wait()
        if let requestError { throw requestError }
        return result
    }

    private func initializeSession(port: UInt16) throws {
        let (status, _) = try post(
            """
            {"jsonrpc":"2.0","id":"1","method":"initialize","params":{"protocolVersion":"2025-11-25","capabilities":{},"clientInfo":{"name":"xctest","version":"1.0"}}}
            """,
            port: port
        )
        XCTAssertEqual(status, 200)
    }

    func testListToolsReturnsEveryMenuActionAndReadTool() throws {
        let session = makeTestSession()
        let server = MCPServer(session: session)
        let port: UInt16 = 18765
        try server.start(port: port)
        defer { server.stop() }

        try initializeSession(port: port)

        let (status, data) = try post(
            """
            {"jsonrpc":"2.0","id":"2","method":"tools/list","params":{}}
            """,
            port: port
        )
        XCTAssertEqual(status, 200)

        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        // 84 menu actions (verified against `performMenuAction`'s own switch, see
        // `MCPToolDefinitions.swift`'s own doc comment) + 5 read tools.
        XCTAssertEqual(tools.count, 89)
        let toolNames = Set(tools.compactMap { $0["name"] as? String })
        XCTAssertTrue(toolNames.contains("get_menu_lists"))
        XCTAssertTrue(toolNames.contains("track-on"))
        XCTAssertTrue(toolNames.contains("scene-save"))
    }

    func testCallToolDispatchesToRealMenuActionAndActuallyChangesSessionState() throws {
        let session = makeTestSession()
        let server = MCPServer(session: session)
        let port: UInt16 = 18766
        try server.start(port: port)
        defer { server.stop() }

        try initializeSession(port: port)

        XCTAssertEqual(session.midiFusionMode, .individual)

        let (status, data) = try post(
            """
            {"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"midi-mode-merged","arguments":{}}}
            """,
            port: port
        )
        XCTAssertEqual(status, 200)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        XCTAssertTrue(text.contains("\"ok\":true"))

        // The real, non-mocked effect of `performMenuAction`'s "midi-mode-merged" case — proves
        // this tool call reached the actual `ImprovSession`, not just a stub response.
        XCTAssertEqual(session.midiFusionMode, .merged)
    }

    func testCallToolGetMenuListsReturnsRealSessionData() throws {
        let session = makeTestSession()
        let server = MCPServer(session: session)
        let port: UInt16 = 18767
        try server.start(port: port)
        defer { server.stop() }

        try initializeSession(port: port)

        let (status, data) = try post(
            """
            {"jsonrpc":"2.0","id":"2","method":"tools/call","params":{"name":"get_menu_lists","arguments":{}}}
            """,
            port: port
        )
        XCTAssertEqual(status, 200)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        // `WebConsoleMenuLists`'s own field name — confirms this is really the same JSON
        // `handleMenuListsRequest` already produces for WebConsole, not a reimplementation.
        XCTAssertTrue(text.contains("midiFusionMode"))
    }

    func testOptionsRequestReturnsCORSHeaders() throws {
        let session = makeTestSession()
        let server = MCPServer(session: session)
        let port: UInt16 = 18768
        try server.start(port: port)
        defer { server.stop() }

        var request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp")!)
        request.httpMethod = "OPTIONS"
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var response: HTTPURLResponse?
        URLSession.shared.dataTask(with: request) { _, resp, _ in
            response = resp as? HTTPURLResponse
            semaphore.signal()
        }.resume()
        semaphore.wait()

        let allowOrigin = response?.value(forHTTPHeaderField: "Access-Control-Allow-Origin")
        XCTAssertEqual(allowOrigin, "*")
    }
}
#endif
