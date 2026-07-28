import Foundation
import MusicTheoryKit

public enum LLMError: Error, CustomStringConvertible {
    case unsupportedProvider(String)
    case missingAPIKey(String)
    case invalidBaseURL(String)
    case httpError(Int, String)
    case invalidResponse
    case network(Error)
    case modelUnavailable(String)

    public var description: String {
        switch self {
        case .unsupportedProvider(let provider): return "unsupported LLM provider \"\(provider)\" (expected \"ollama\", \"openai-compatible\", \"anthropic\", or \"foundation-models\")"
        case .missingAPIKey(let envVar): return "environment variable \(envVar) is not set"
        case .invalidBaseURL(let url): return "invalid base URL: \(url)"
        case .httpError(let status, let body): return "HTTP \(status): \(body)"
        case .invalidResponse: return "the LLM's response did not have the expected shape"
        case .network(let error): return "network error: \(error)"
        case .modelUnavailable(let reason): return "the on-device model is unavailable: \(reason)"
        }
    }
}

public protocol LLMProvider {
    func generate(prompt: String, connection: LLMConnection) throws -> String
}

/// Blocks the calling thread until `URLSession`'s completion-handler API returns — the CLI
/// this feeds into is plain synchronous code (no async `main`), so bridging here keeps
/// every call site simple instead of threading `async`/`await` through the whole app.
func syncDataTask(_ request: URLRequest) throws -> (Data, URLResponse) {
    let semaphore = DispatchSemaphore(value: 0)
    // `nonisolated(unsafe)`: genuinely safe — the completion handler writes exactly once,
    // then signals the semaphore, which is the only thing gating the read below.
    nonisolated(unsafe) var result: Result<(Data, URLResponse), Error> = .failure(LLMError.invalidResponse)
    URLSession.shared.dataTask(with: request) { data, response, error in
        if let error {
            result = .failure(LLMError.network(error))
        } else if let data, let response {
            result = .success((data, response))
        }
        semaphore.signal()
    }.resume()
    semaphore.wait()
    return try result.get()
}

func checkHTTPStatus(_ data: Data, _ response: URLResponse) throws {
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
        let status = (response as? HTTPURLResponse)?.statusCode ?? -1
        throw LLMError.httpError(status, String(data: data, encoding: .utf8) ?? "")
    }
}

/// Ollama's native `/api/generate` endpoint — no API key, meant for a local server.
public struct OllamaProvider: LLMProvider {
    public init() {}

    public func generate(prompt: String, connection: LLMConnection) throws -> String {
        guard let url = URL(string: connection.baseURL + "/api/generate") else {
            throw LLMError.invalidBaseURL(connection.baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": connection.model,
            "prompt": prompt,
            "stream": false,
        ])

        let (data, response) = try syncDataTask(request)
        try checkHTTPStatus(data, response)
        struct OllamaResponse: Decodable { let response: String }
        return try JSONDecoder().decode(OllamaResponse.self, from: data).response
    }
}

/// The OpenAI `/v1/chat/completions` shape — also spoken by many local servers (LM Studio,
/// llama.cpp's server, etc.), so one implementation covers all of them.
public struct OpenAICompatibleProvider: LLMProvider {
    public init() {}

    public func generate(prompt: String, connection: LLMConnection) throws -> String {
        guard let url = URL(string: connection.baseURL + "/v1/chat/completions") else {
            throw LLMError.invalidBaseURL(connection.baseURL)
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let envVar = connection.apiKeyEnvVar {
            guard let key = APIKeyStore.resolve(envVar) else { throw LLMError.missingAPIKey(envVar) }
            request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": connection.model,
            "messages": [["role": "user", "content": prompt]],
        ])

        let (data, response) = try syncDataTask(request)
        try checkHTTPStatus(data, response)
        struct ChatResponse: Decodable {
            struct Choice: Decodable {
                struct Message: Decodable { let content: String }
                let message: Message
            }
            let choices: [Choice]
        }
        guard let content = try JSONDecoder().decode(ChatResponse.self, from: data).choices.first?.message.content else {
            throw LLMError.invalidResponse
        }
        return content
    }
}

/// Anthropic's native Messages API (`/v1/messages`) — used for a real "anthropic-claude"
/// subscription, as opposed to the generic OpenAI-compatible chat-completions shape.
/// Auth is `x-api-key` (not `Authorization: Bearer`), plus a required `anthropic-version`
/// header; the response carries the assistant's reply as an array of content blocks
/// rather than OpenAI's `choices[0].message.content`.
public struct AnthropicProvider: LLMProvider {
    static let apiVersion = "2023-06-01"
    static let defaultMaxTokens = 4096

    public init() {}

    public func generate(prompt: String, connection: LLMConnection) throws -> String {
        guard let url = URL(string: connection.baseURL + "/v1/messages") else {
            throw LLMError.invalidBaseURL(connection.baseURL)
        }
        guard let envVar = connection.apiKeyEnvVar else { throw LLMError.missingAPIKey("ANTHROPIC_API_KEY") }
        guard let key = APIKeyStore.resolve(envVar) else { throw LLMError.missingAPIKey(envVar) }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(key, forHTTPHeaderField: "x-api-key")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "anthropic-version")
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": connection.model,
            "max_tokens": Self.defaultMaxTokens,
            "messages": [["role": "user", "content": prompt]],
        ])

        let (data, response) = try syncDataTask(request)
        try checkHTTPStatus(data, response)
        struct MessagesResponse: Decodable {
            struct ContentBlock: Decodable { let type: String; let text: String? }
            let content: [ContentBlock]
        }
        let text = try JSONDecoder().decode(MessagesResponse.self, from: data)
            .content.first(where: { $0.type == "text" })?.text
        guard let text else { throw LLMError.invalidResponse }
        return text
    }
}

/// Apple's on-device Apple Intelligence model (`import FoundationModels`, iOS/macOS 26+).
/// Guarded by `canImport` so the package still builds without the framework — an older
/// Xcode/SDK, or a non-Apple platform. No network, no API key: `LLMConnection.baseURL` is
/// unused for this provider (kept as a non-misleading placeholder in its JSON descriptor).
#if canImport(FoundationModels)
import FoundationModels

@available(iOS 26, macOS 26, *)
public struct FoundationModelsProvider: LLMProvider {
    public init() {}

    public func generate(prompt: String, connection: LLMConnection) throws -> String {
        try Self.checkAvailability()
        return try syncAwait {
            try await LanguageModelSession().respond(to: prompt).content
        }
    }

    /// Guided generation: constrains the model's output token-by-token to `FMPieceDTO`'s
    /// schema instead of hoping a free-text completion happens to match it. Used only by
    /// the piece-composition path (`LLMClient.generatePieceJSON`) — never by `generate`,
    /// which stays free-text so generic prompts (e.g. the "test connection" ping) aren't
    /// forced into a Piece-shaped schema they have nothing to do with.
    func generatePieceDTO(prompt: String, connection: LLMConnection) throws -> LLMPieceDTO {
        try Self.checkAvailability()
        let fmDTO: FMPieceDTO = try syncAwait {
            try await LanguageModelSession().respond(to: prompt, generating: FMPieceDTO.self).content
        }
        return fmDTO.toLLMPieceDTO()
    }

    private static func checkAvailability() throws {
        switch SystemLanguageModel.default.availability {
        case .available: return
        case .unavailable(let reason): throw LLMError.modelUnavailable("\(reason)")
        // Apple keeps adding unavailability reasons over time — degrade with a clear error
        // on any future case this was compiled without knowledge of, rather than crash.
        @unknown default: throw LLMError.modelUnavailable("unknown availability state")
        }
    }
}

// `@Generable`/`@Guide` (Foundation Models' guided-generation macros) themselves carry a
// macOS/iOS 26 availability floor, so they can't be attached to `LLMPieceComposer`'s shared
// `LLMChordDTO`/`LLMSectionDTO`/`LLMPieceDTO` family — those are plain Codable structs used
// unconditionally by all 4 providers, including on iOS 17/macOS 14 (see LLMPieceComposer.swift).
// This mirror family exists solely so guided generation has a schema to target; `toLLM...DTO()`
// converts the result into the shared shape so `compose(from:)`'s vocabulary validation (scale/
// chord IDs against `ScaleLibrary`/`ChordVocabulary`) applies identically to every provider.
//
// `@Guide(.anyOf:)` does accept a runtime-computed `[String]` (confirmed by building this
// file) — so `scaleID`/`templateID` are guide-constrained to the theory library's actual
// vocabulary directly, on top of (not instead of) `compose(from:)`'s runtime validation.

@available(iOS 26, macOS 26, *)
@Generable
struct FMChordDTO {
    var measure: Int
    var root: String
    @Guide(.anyOf(ChordVocabulary.seed.map(\.id)))
    var templateID: String
    var durationBeats: Double?
}

@available(iOS 26, macOS 26, *)
@Generable
struct FMMelodyNoteDTO {
    var measure: Int
    var beat: Double
    var durationBeats: Double
    @Guide(.range(0...127))
    var pitch: Int
}

@available(iOS 26, macOS 26, *)
@Generable
struct FMSectionDTO {
    var name: String
    var lengthInMeasures: Int
    var tonic: String
    @Guide(.anyOf(ScaleLibrary.all.map(\.id)))
    var scaleID: String
    var chords: [FMChordDTO]
    var melody: [FMMelodyNoteDTO]?
}

@available(iOS 26, macOS 26, *)
@Generable
struct FMPieceDTO {
    var title: String
    @Guide(.range(30...240))
    var tempoBPM: Double
    var tonic: String
    @Guide(.anyOf(ScaleLibrary.all.map(\.id)))
    var scaleID: String
    var sections: [FMSectionDTO]
}

@available(iOS 26, macOS 26, *)
private extension FMChordDTO {
    func toLLMChordDTO() -> LLMChordDTO {
        LLMChordDTO(measure: measure, root: root, templateID: templateID, durationBeats: durationBeats)
    }
}

@available(iOS 26, macOS 26, *)
private extension FMMelodyNoteDTO {
    func toLLMMelodyNoteDTO() -> LLMMelodyNoteDTO {
        LLMMelodyNoteDTO(measure: measure, beat: beat, durationBeats: durationBeats, pitch: pitch)
    }
}

@available(iOS 26, macOS 26, *)
private extension FMSectionDTO {
    func toLLMSectionDTO() -> LLMSectionDTO {
        LLMSectionDTO(
            name: name,
            lengthInMeasures: lengthInMeasures,
            tonic: tonic,
            scaleID: scaleID,
            chords: chords.map { $0.toLLMChordDTO() },
            melody: melody?.map { $0.toLLMMelodyNoteDTO() }
        )
    }
}

@available(iOS 26, macOS 26, *)
private extension FMPieceDTO {
    func toLLMPieceDTO() -> LLMPieceDTO {
        LLMPieceDTO(
            title: title,
            tempoBPM: tempoBPM,
            tonic: tonic,
            scaleID: scaleID,
            sections: sections.map { $0.toLLMSectionDTO() }
        )
    }
}

/// Blocks the calling thread until an `async` operation completes — the `syncDataTask`
/// counterpart for non-networking async APIs. Deliberately NOT just `Task { await ... }`:
/// every call site of `LLMClient.generate`/`generatePieceJSON` already runs inside a
/// `Task.detached { ... }` (see `JamShackLLMView`, `ImprovSession.composeFromText`, etc.), so
/// a plain `Task` scheduling `operation()` would compete for the same finite Swift-concurrency
/// cooperative-pool thread that this function's `semaphore.wait()` is itself blocking — a
/// classic self-deadlock risk if the pool is momentarily saturated. Waiting on a dedicated
/// `Thread` instead (not part of the cooperative pool) decouples the two, so the pool's
/// capacity to actually run `operation()` is never reduced by this bridge.
@available(iOS 26, macOS 26, *)
func syncAwait<T: Sendable>(_ operation: @escaping @Sendable () async throws -> T) throws -> T {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: Result<T, Error>!
    Thread.detachNewThread {
        let inner = DispatchSemaphore(value: 0)
        Task {
            defer { inner.signal() }
            do { result = .success(try await operation()) } catch { result = .failure(error) }
        }
        inner.wait()
        semaphore.signal()
    }
    semaphore.wait()
    return try result.get()
}
#endif

public enum LLMClient {
    public static func generate(prompt: String, connection: LLMConnection) throws -> String {
        switch connection.provider {
        case "ollama": return try OllamaProvider().generate(prompt: prompt, connection: connection)
        case "openai-compatible": return try OpenAICompatibleProvider().generate(prompt: prompt, connection: connection)
        case "anthropic": return try AnthropicProvider().generate(prompt: prompt, connection: connection)
        case "foundation-models":
            #if canImport(FoundationModels)
            if #available(iOS 26, macOS 26, *) {
                return try FoundationModelsProvider().generate(prompt: prompt, connection: connection)
            } else {
                throw LLMError.modelUnavailable("Foundation Models requires iOS 26 / macOS 26 or later")
            }
            #else
            throw LLMError.modelUnavailable("Foundation Models is not available in this build")
            #endif
        default: throw LLMError.unsupportedProvider(connection.provider)
        }
    }

    /// Same contract as `generate` (prompt in, JSON text out) but — for providers that support
    /// it — the text is produced via guided generation against `LLMPieceDTO`'s schema instead
    /// of a free-text completion that merely hopes to match it. Every other provider (and
    /// Foundation Models on an OS too old to have it) falls through to `generate` unchanged.
    /// This is `composeFromText`/`composeSoundTrackToPieces`'s default `generate` — the
    /// generic "test connection" ping intentionally keeps calling `generate` directly instead.
    public static func generatePieceJSON(prompt: String, connection: LLMConnection) throws -> String {
        #if canImport(FoundationModels)
        if connection.provider == "foundation-models", #available(iOS 26, macOS 26, *) {
            let dto = try FoundationModelsProvider().generatePieceDTO(prompt: prompt, connection: connection)
            return String(data: try JSONEncoder().encode(dto), encoding: .utf8) ?? ""
        }
        #endif
        return try generate(prompt: prompt, connection: connection)
    }
}
