import Foundation

/// A small in-memory override layer sitting in front of `ProcessInfo.processInfo.environment`
/// for API keys. The CLI (a plain unsandboxed process launched from a shell) can rely on a
/// real environment variable being set before launch; a sandboxed GUI app launched by
/// double-click has no practical way to do that, so `ImprovSession` (AppCore) loads a
/// persisted key here at startup/whenever it changes, and every `LLMProvider` resolves
/// through `resolve(_:)` instead of reading the environment directly — an override wins if
/// present, otherwise the real environment variable is still checked (so the CLI's own
/// existing env-var workflow keeps working unchanged).
///
/// Lives in `LLMEngine` (not `AppCore`) so the providers that need it (`OpenAICompatibleProvider`/
/// `AnthropicProvider`, both in this module) can call it directly without a dependency
/// pointing the wrong way — `AppCore` already depends on `LLMEngine`, not the reverse.
public enum APIKeyStore {
    private static let lock = NSLock()
    // `nonisolated(unsafe)`: genuinely safe — every access is gated by `lock` below, the
    // same pattern `LLMProvider.swift`'s `syncDataTask` already uses for its own shared
    // mutable state.
    nonisolated(unsafe) private static var overridesByEnvVar: [String: String] = [:]

    /// `nil` or empty clears any stored override for `envVar`, falling back to the real
    /// environment variable again.
    public static func set(_ key: String?, forEnvVar envVar: String) {
        lock.lock()
        defer { lock.unlock() }
        if let key, !key.isEmpty {
            overridesByEnvVar[envVar] = key
        } else {
            overridesByEnvVar.removeValue(forKey: envVar)
        }
    }

    public static func resolve(_ envVar: String) -> String? {
        lock.lock()
        let override = overridesByEnvVar[envVar]
        lock.unlock()
        return override ?? ProcessInfo.processInfo.environment[envVar]
    }
}
