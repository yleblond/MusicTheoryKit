#if os(macOS)
import XCTest
@testable import AppCore

/// Exercises the actual `JamShackMCPBridge` binary (not just the HTTP endpoint it talks to) —
/// this is the exact program Claude Desktop spawns via `"command"` in `claude_desktop_config
/// .json`, since Claude Desktop's config parser only accepts that stdio shape and rejects a
/// bare `"url"` entry outright (confirmed empirically — see `MCPServer.swift`'s own doc
/// comment). Spawns the real subprocess, writes a real JSON-RPC line to its stdin, reads back
/// what it writes to stdout, over a real pipe — as close to Claude Desktop's own usage as this
/// environment can exercise without Claude Desktop itself.
final class MCPBridgeTests: XCTestCase {
    /// `ProcessInfo.arguments[0]` isn't useful here — under `swift test`, that's the Xcode
    /// test driver's own path (`.../Xcode.app/Contents/Developer/usr/bin/...`), not this
    /// package's build directory. `#filePath` (this very source file's path, resolved at
    /// compile time) reliably locates the package root regardless of where it's checked out,
    /// from which `.build/debug/JamShackMCPBridge` is a fixed, well-known location — built by
    /// the exact same `swift build`/`swift test` invocation that compiles this test itself.
    private var bridgeExecutableURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // MCPBridgeTests.swift -> AppCoreTests/
            .deletingLastPathComponent() // AppCoreTests/ -> Tests/
            .deletingLastPathComponent() // Tests/ -> package root
            .appendingPathComponent(".build/debug/JamShackMCPBridge")
    }

    private func runBridge(sending line: String, mcpURL: String) throws -> String {
        let process = Process()
        process.executableURL = bridgeExecutableURL
        process.environment = ["JAMSHACK_MCP_URL": mcpURL]
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        try process.run()

        stdin.fileHandleForWriting.write(Data((line + "\n").utf8))
        // Signals EOF on the bridge's stdin once this one line has been handled — makes its
        // `readLine()` loop exit and the process terminate cleanly, so `waitUntilExit` returns.
        try stdin.fileHandleForWriting.close()

        let outputData = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: outputData, encoding: .utf8) ?? ""
    }

    func testBridgeRelaysToolsListThroughToTheRealMCPServer() throws {
        let session = makeTestSession()
        let server = MCPServer(session: session)
        let port: UInt16 = 18770
        try server.start(port: port)
        defer { server.stop() }

        // The bridge doesn't itself speak MCP's initialize handshake — it's a dumb relay, so a
        // client that skips straight to `tools/list` (as this test does) is exactly the
        // scenario it needs to handle correctly, same as any other message.
        let output = try runBridge(
            sending: #"{"jsonrpc":"2.0","id":"1","method":"tools/list","params":{}}"#,
            mcpURL: "http://127.0.0.1:\(port)/mcp"
        )

        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        let result = try XCTUnwrap(json["result"] as? [String: Any])
        let tools = try XCTUnwrap(result["tools"] as? [[String: Any]])
        XCTAssertEqual(tools.count, 89)
    }

    func testBridgeReturnsAJSONRPCErrorWhenTheServerIsUnreachable() throws {
        // No `MCPServer` started at all on this port — simulates JamShack not running, or its
        // MCP toggle being off, which is a real, expected situation this bridge must degrade
        // out of gracefully (a well-formed JSON-RPC error) rather than hanging or crashing.
        let output = try runBridge(
            sending: #"{"jsonrpc":"2.0","id":"42","method":"tools/list","params":{}}"#,
            mcpURL: "http://127.0.0.1:18771/mcp"
        )
        let line = output.trimmingCharacters(in: .whitespacesAndNewlines)
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(json["id"] as? String, "42")
        XCTAssertNotNil(json["error"])
    }
}
#endif
