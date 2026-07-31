import Foundation

/// A tiny stdio<->HTTP bridge for Claude Desktop — see this target's own comment in
/// `Package.swift` for why it exists at all (Claude Desktop's `claude_desktop_config.json`
/// parser only accepts a `"command"` stdio entry, never a bare `"url"` one, confirmed
/// empirically: it silently rejected `{"url": "http://127.0.0.1:8765/mcp"}` as "not a valid MCP
/// server configuration"). Deliberately dumb: reads one newline-delimited JSON-RPC message from
/// stdin, POSTs its exact bytes to the already-running JamShack app's embedded MCP HTTP
/// endpoint, writes the HTTP response body back as one line on stdout. Never parses a message
/// itself beyond pulling out `id` for a locally-synthesized error response when the HTTP call
/// itself fails (e.g. JamShack isn't running, or its MCP toggle is off) — everything else (tool
/// list, dispatch into `ImprovSession`) lives entirely in the app process this bridges to.
let defaultMCPURL = URL(string: "http://127.0.0.1:8765/mcp")!
let mcpURL = ProcessInfo.processInfo.environment["JAMSHACK_MCP_URL"].flatMap(URL.init(string:)) ?? defaultMCPURL
let urlSession = URLSession(configuration: .ephemeral)
let stdout = FileHandle.standardOutput

func writeLine(_ text: String) {
    var data = Data(text.utf8)
    data.append(UInt8(ascii: "\n"))
    stdout.write(data)
}

/// Pulls the JSON-RPC `id` out of an otherwise-unparsed message — the only bit of the protocol
/// this bridge needs to understand, so a failed HTTP call can still produce a well-formed
/// JSON-RPC error response (matched to the right request id) instead of just going silent.
func extractID(from line: String) -> Any {
    guard let data = line.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
          let id = json["id"] else { return NSNull() }
    return id
}

func errorResponseLine(id: Any, message: String) -> String {
    let payload: [String: Any] = [
        "jsonrpc": "2.0",
        "id": id,
        "error": ["code": -32000, "message": message],
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload),
          let text = String(data: data, encoding: .utf8) else {
        return "{\"jsonrpc\":\"2.0\",\"id\":null,\"error\":{\"code\":-32000,\"message\":\"internal bridge error\"}}"
    }
    return text
}

/// One POST attempt against the JamShack MCP endpoint — `error` is only ever a transport-level
/// failure (connection refused, host down, etc.), never a non-2xx HTTP status, since
/// `URLSession` reports those as a normal (if unhappy) response, not an `error`. That's exactly
/// the class of failure `postWithRetry` below retries: "nothing is listening there (yet)", not
/// "something answered badly".
func postOnce(_ body: Data) -> (data: Data?, error: Error?) {
    var request = URLRequest(url: mcpURL)
    request.httpMethod = "POST"
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    request.httpBody = body

    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var responseData: Data?
    nonisolated(unsafe) var requestError: Error?
    urlSession.dataTask(with: request) { data, _, error in
        responseData = data
        requestError = error
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return (responseData, requestError)
}

/// Retries a connection failure for a few seconds before giving up — confirmed empirically:
/// Claude Desktop spawns this bridge and immediately sends its `initialize` handshake at
/// Claude Desktop's OWN launch, which routinely wins the race against JamShack.app still
/// starting up (loading scenes/guides, then finally reaching `startMCPServerIfEnabled()` — see
/// `ContentView.swift`) and hasn't bound the port yet. A single failed attempt there used to
/// surface as "Could not attach to MCP server jamshack" even though the very next real query,
/// moments later once JamShack has finished launching, worked fine. 20 attempts / 250ms apart
/// (5s total) comfortably covers a cold app launch without making a genuinely-not-running
/// JamShack hang Claude Desktop for long.
func postWithRetry(_ body: Data) -> (data: Data?, error: Error?) {
    var result = postOnce(body)
    var attempt = 1
    while result.error != nil, attempt < 20 {
        usleep(250_000)
        result = postOnce(body)
        attempt += 1
    }
    return result
}

while let line = readLine(strippingNewline: true) {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { continue }

    let (responseData, requestError) = postWithRetry(Data(trimmed.utf8))

    if let requestError {
        writeLine(errorResponseLine(
            id: extractID(from: trimmed),
            message: "JamShack MCP endpoint unreachable (\(requestError.localizedDescription)). Vérifie que JamShack tourne et que le serveur MCP est activé (Réglages > I.A.)."
        ))
        continue
    }
    // A 202 Accepted (notifications, and any response `handleRequest` already routed to a
    // waiting request elsewhere) has no body — nothing to write back, matching stdio's own
    // "notifications get no reply line" contract.
    if let responseData, !responseData.isEmpty, let text = String(data: responseData, encoding: .utf8) {
        writeLine(text)
    }
}
