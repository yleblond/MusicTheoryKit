import Foundation
import WebConsole

#if os(macOS)
import MCP
/// Embeds a Model Context Protocol server directly in the app — macOS only. See the approved
/// implementation plan for why iOS is structurally out of scope: Claude's iOS app only supports
/// "remote" MCP connectors, whose actual HTTP calls are made server-side by Anthropic's own
/// cloud backend, never reachable at a loopback/LAN address on the same device the way Claude
/// Desktop (a direct local HTTP client, no cloud intermediary) can reach this.
///
/// Reuses `WebConsole.HTTPServer`/`HTTPConnection` — the exact same hand-rolled
/// `Network.framework` HTTP/1.1 server WebConsole itself already uses — as the raw transport,
/// bridging each request through to the MCP Swift SDK's `StatelessHTTPServerTransport`
/// (Streamable HTTP, request/response only — no SSE streaming, no session id: this server never
/// sends unsolicited notifications/requests to the client, so the simpler stateless transport is
/// sufficient). Bound to loopback (`127.0.0.1`) ONLY, unlike WebConsole (which binds all
/// interfaces): MCP tools allow far more powerful control of the app (compose/save/delete) than
/// WebConsole's own browser UI, with no authentication at all — there's no legitimate reason for
/// a different device on the LAN to reach this.
///
/// Every tool call dispatches directly, in-process, to `ImprovSession.handleMenuAction`/
/// `handleMenuListsRequest`/`buildPieceDetail`/etc. — the exact same entry points WebConsole's
/// own `/menu-action`/`/menu-lists`/detail routes already call, reusing their JSON encoding
/// as-is rather than re-implementing any business logic (see `MCPToolDefinitions.swift` for the
/// hand-ported tool list this dispatches from).
///
/// **Confirmed empirically: Claude Desktop cannot connect to this endpoint directly.** Its
/// `claude_desktop_config.json` parser only accepts the stdio shape (a `"command"` field it
/// spawns as a subprocess) — a bare `{"url": "http://127.0.0.1:.../mcp"}` entry is rejected
/// outright ("not a valid MCP server configuration"), before any HTTP request or CORS
/// preflight is even attempted. This endpoint is still fully functional Streamable HTTP MCP
/// (verified by `MCPServerTests`, real HTTP requests over a real socket) — `JamShackMCPBridge`
/// (a separate executable target, see `Package.swift`) is the actual thing Claude Desktop
/// spawns, translating stdio's newline-delimited JSON-RPC framing to/from an HTTP POST against
/// this exact endpoint. The CORS headers below (`Access-Control-Allow-Origin` etc.) turned out
/// not to be the blocker, but are harmless to keep — a genuine browser-based Streamable HTTP
/// client would still need them.
///
/// Concurrency note: WebConsole and the virtual keyboard already run as two independent
/// `HTTPServer` instances, each with its own private serial queue, both calling into
/// `ImprovSession` without any shared cross-queue lock — an accepted, pre-existing multi-front-
/// door design, not something this type introduces. `mcpCallLock` below only guarantees this
/// server's OWN tool calls never overlap each other (mirroring one `HTTPServer` queue's own
/// single-threaded guarantee for its own traffic) — it does not (and, consistent with the
/// existing WebConsole/virtual-keyboard precedent, does not need to) serialize against those
/// other two front doors.
public final class MCPServer: @unchecked Sendable {
    /// Shared with `ImprovSession.startMCPServerNow()` (which actually binds this port) and the
    /// "I.A." settings panel (which shows it in the Claude Desktop config snippet) — one source
    /// of truth rather than the same number hardcoded in two places.
    public static let defaultPort: UInt16 = 8765

    private weak var session: ImprovSession?
    private var httpServer: WebConsole.HTTPServer?
    private let transport = MCP.StatelessHTTPServerTransport()
    private let server: MCP.Server
    /// Serializes this server's own tool calls against each other — see this type's own doc
    /// comment for why that's the right (and sufficient) scope for this lock.
    private let mcpCallLock = NSLock()

    private static let corsHeaders = [
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Methods": "POST, GET, OPTIONS",
        "Access-Control-Allow-Headers": "Content-Type, Accept, Mcp-Session-Id, Mcp-Protocol-Version",
    ]

    public init(session: ImprovSession) {
        self.session = session
        server = MCP.Server(
            name: "jamshack",
            version: "1.0.0",
            instructions: "Contrôle l'application musicale JamShack : pistes, scènes, guides musicaux, enregistrements, morceaux, composition IA, et Jam Session.",
            capabilities: .init(tools: .init(listChanged: false))
        )
    }

    public func start(port: UInt16) throws {
        let registeredServer = server
        let allTools = Self.buildTools()
        Task {
            await registeredServer.withMethodHandler(MCP.ListTools.self) { _ in
                MCP.ListTools.Result(tools: allTools)
            }
            await registeredServer.withMethodHandler(MCP.CallTool.self) { [weak self] params in
                guard let self else {
                    return MCP.CallTool.Result(content: [.text(text: "server unavailable", annotations: nil, _meta: nil)], isError: true)
                }
                return self.callTool(named: params.name, arguments: params.arguments ?? [:])
            }
            try? await registeredServer.start(transport: self.transport)
        }

        let httpServer = WebConsole.HTTPServer(onRequest: { [weak self] request in
            self?.handle(request) ?? .notFound()
        })
        try httpServer.start(port: port, host: "127.0.0.1")
        self.httpServer = httpServer
    }

    public func stop() {
        httpServer?.stop()
        httpServer = nil
        let registeredServer = server
        Task { await registeredServer.stop() }
    }

    // MARK: - HTTP <-> MCP bridge

    /// `WebConsole.HTTPServer`'s `onRequest` is a plain synchronous closure (it must return a
    /// response before `HTTPConnection` can send it) — bridged to the MCP transport's `async`
    /// actor method via a semaphore, blocking only THIS server's own connection-handling thread
    /// (never the main thread), same shape as this codebase's other "synchronous call site over
    /// an async operation" bridges (e.g. `LLMProvider`'s `syncDataTask`).
    private func handle(_ request: WebConsole.HTTPRequest) -> WebConsole.HTTPResponse {
        if request.method.uppercased() == "OPTIONS" {
            return WebConsole.HTTPResponse(status: 204, contentType: "text/plain", body: Data(), extraHeaders: Self.corsHeaders)
        }
        let mcpRequest = MCP.HTTPRequest(method: request.method, headers: request.headers, body: request.body, path: request.path)
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var mcpResponse: MCP.HTTPResponse?
        Task {
            mcpResponse = await self.transport.handleRequest(mcpRequest)
            semaphore.signal()
        }
        semaphore.wait()
        guard let mcpResponse else {
            return .text("Internal error", contentType: "text/plain", status: 500, extraHeaders: Self.corsHeaders)
        }
        var headers = mcpResponse.headers
        let contentType = headers.removeValue(forKey: HTTPHeaderName.contentType) ?? "application/json"
        for (name, value) in Self.corsHeaders { headers[name] = value }
        return WebConsole.HTTPResponse(status: mcpResponse.statusCode, contentType: contentType, body: mcpResponse.bodyData ?? Data(), extraHeaders: headers)
    }

    // MARK: - Tool dispatch

    private func callTool(named name: String, arguments: [String: MCP.Value]) -> MCP.CallTool.Result {
        guard let session else {
            return MCP.CallTool.Result(content: [.text(text: "session unavailable", annotations: nil, _meta: nil)], isError: true)
        }
        mcpCallLock.lock()
        defer { mcpCallLock.unlock() }

        let data: Data
        switch name {
        case "get_menu_lists":
            data = session.handleMenuListsRequest().body
        case "get_piece_detail":
            data = (try? JSONEncoder().encode(session.buildPieceDetail())) ?? Data()
        case "get_composition_description":
            data = (try? JSONEncoder().encode(session.buildCompositionDetail())) ?? Data()
        case "get_guide_sequence_detail":
            data = (try? JSONEncoder().encode(session.buildGuideDetail())) ?? Data()
        case "get_soundtrack_detail":
            data = (try? JSONEncoder().encode(session.buildSoundTrackDetail())) ?? Data()
        default:
            var query: [String: String] = ["action": name]
            for (key, value) in arguments {
                if let stringValue = value.mcpQueryStringValue {
                    query[key] = stringValue
                }
            }
            data = session.handleMenuAction(query).body
        }
        let text = String(data: data, encoding: .utf8) ?? "{}"
        return MCP.CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    }

    // MARK: - Tool list generation

    private static func buildTools() -> [MCP.Tool] {
        let menuActionTools = MCPToolDefinitions.menuActions.map { definition -> MCP.Tool in
            var properties: [String: MCP.Value] = [:]
            var required: [MCP.Value] = []
            for field in definition.fields {
                properties[field.name] = ["type": "string", "description": .string(field.description)]
                if !field.optional { required.append(.string(field.name)) }
            }
            let schema: MCP.Value = ["type": "object", "properties": .object(properties), "required": .array(required)]
            return MCP.Tool(name: definition.action, description: definition.description, inputSchema: schema)
        }
        let readTools: [MCP.Tool] = [
            MCP.Tool(name: "get_menu_lists", description: "Liste l'état courant de l'app : pistes, fichiers disponibles par catégorie, connexions LLM, palettes, gammes, rôles de scène.", inputSchema: ["type": "object", "properties": [:]]),
            MCP.Tool(name: "get_piece_detail", description: "Détail complet du morceau actuellement chargé (sections, fragments, accords).", inputSchema: ["type": "object", "properties": [:]]),
            MCP.Tool(name: "get_composition_description", description: "Détail de la description de composition texte actuellement active.", inputSchema: ["type": "object", "properties": [:]]),
            MCP.Tool(name: "get_guide_sequence_detail", description: "Détail du guide musical actuellement chargé (étapes, mode, progression d'accords, étape courante).", inputSchema: ["type": "object", "properties": [:]]),
            MCP.Tool(name: "get_soundtrack_detail", description: "Détail de l'enregistrement actuellement chargé (pistes, durée, événements).", inputSchema: ["type": "object", "properties": [:]]),
        ]
        return menuActionTools + readTools
    }
}

private extension MCP.Value {
    /// Converts an MCP tool-call argument to the plain string `performMenuAction`'s
    /// `[String: String]` query dict expects — every field in `MCPToolDefinitions` is declared
    /// as a JSON Schema string, but a client could still send a number/bool for a numeric-
    /// looking field (e.g. `count`, `port`), so this tolerates every `Value` case rather than
    /// only `.string`.
    var mcpQueryStringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return String(value)
        case .bool(let value): return String(value)
        case .null, .data, .array, .object: return nil
        }
    }
}
#endif
