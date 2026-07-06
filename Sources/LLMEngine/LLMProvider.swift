import Foundation

public enum LLMError: Error, CustomStringConvertible {
    case unsupportedProvider(String)
    case missingAPIKey(String)
    case invalidBaseURL(String)
    case httpError(Int, String)
    case invalidResponse
    case network(Error)

    public var description: String {
        switch self {
        case .unsupportedProvider(let provider): return "unsupported LLM provider \"\(provider)\" (expected \"ollama\", \"openai-compatible\", or \"anthropic\")"
        case .missingAPIKey(let envVar): return "environment variable \(envVar) is not set"
        case .invalidBaseURL(let url): return "invalid base URL: \(url)"
        case .httpError(let status, let body): return "HTTP \(status): \(body)"
        case .invalidResponse: return "the LLM's response did not have the expected shape"
        case .network(let error): return "network error: \(error)"
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
            guard let key = ProcessInfo.processInfo.environment[envVar] else { throw LLMError.missingAPIKey(envVar) }
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
        guard let key = ProcessInfo.processInfo.environment[envVar] else { throw LLMError.missingAPIKey(envVar) }

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

public enum LLMClient {
    public static func generate(prompt: String, connection: LLMConnection) throws -> String {
        switch connection.provider {
        case "ollama": return try OllamaProvider().generate(prompt: prompt, connection: connection)
        case "openai-compatible": return try OpenAICompatibleProvider().generate(prompt: prompt, connection: connection)
        case "anthropic": return try AnthropicProvider().generate(prompt: prompt, connection: connection)
        default: throw LLMError.unsupportedProvider(connection.provider)
        }
    }
}
