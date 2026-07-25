import Foundation

/// Persisted API keys for LLM connections, keyed by the connection's `apiKeyEnvVar` (e.g.
/// "ANTHROPIC_API_KEY") — lets the GUI (JamShack > LLM) type a key once instead of needing a
/// real shell environment variable set before every launch, which the CLI can rely on but a
/// sandboxed double-clicked app can't. Mirrors `LumiSettingsFile`'s "singleton value file"
/// shape, persisted to `llm-api-keys.json` in the settings folder.
///
/// SECURITY CAVEAT, deliberately accepted for now (tracked in `Docs/BACKLOG.md`): this is
/// PLAIN TEXT JSON, not Keychain-backed. Anyone with filesystem access to the settings folder
/// (e.g. iCloud Drive, synced to every device on the account) can read the key. Good enough
/// to unblock GUI usage today; a Keychain-backed version is backlogged, not implemented here.
public struct LLMAPIKeysFile: Codable, Equatable {
    public var keysByEnvVar: [String: String]

    public init(keysByEnvVar: [String: String] = [:]) {
        self.keysByEnvVar = keysByEnvVar
    }
}
