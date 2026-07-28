import LLMEngine

/// The built-in LLM connection catalog — seeds a fresh install (see
/// `ImprovSession.migrateLLMConnectionsFromJSONIfNeeded`) and backs the "Ajouter depuis un
/// modele" action in `JamShackLLMView`. A plain static array today; swapping it for a
/// server-fetched catalog later would only touch this one file, not the seeding/add mechanics
/// that consume it.
public enum LLMConnectionTemplates {
    public static let builtIn: [LLMConnection] = [
        LLMConnection(name: "Ollama (local)", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3"),
        LLMConnection(name: "OpenAI-compatible (needs OPENAI_API_KEY)", provider: "openai-compatible", baseURL: "https://api.openai.com", model: "gpt-4o-mini", apiKeyEnvVar: "OPENAI_API_KEY"),
        LLMConnection(name: "Anthropic Claude (needs ANTHROPIC_API_KEY)", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8", apiKeyEnvVar: "ANTHROPIC_API_KEY"),
        LLMConnection(name: "Foundation Models (on-device)", provider: "foundation-models", baseURL: "n/a (on-device)", model: "system"),
    ]
}
