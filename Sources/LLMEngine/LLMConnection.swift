/// A named LLM endpoint to call, stored as a plain JSON file so connections can be listed
/// and picked from a folder the same way sample instruments and pieces are. Never holds a
/// secret directly — `apiKeyEnvVar` names an environment variable to read the key from at
/// call time, so the descriptor file itself is safe to keep around (even if the folder
/// later ends up under version control).
public struct LLMConnection: Codable, Equatable, Sendable {
    public var name: String
    /// "ollama", "openai-compatible" (covers OpenAI itself, and the many local servers —
    /// LM Studio, llama.cpp's server, etc. — that speak the same `/v1/chat/completions` shape),
    /// or "anthropic" (Claude's native `/v1/messages` API).
    public var provider: String
    public var baseURL: String
    public var model: String
    public var apiKeyEnvVar: String?

    public init(name: String, provider: String, baseURL: String, model: String, apiKeyEnvVar: String? = nil) {
        self.name = name
        self.provider = provider
        self.baseURL = baseURL
        self.model = model
        self.apiKeyEnvVar = apiKeyEnvVar
    }
}
