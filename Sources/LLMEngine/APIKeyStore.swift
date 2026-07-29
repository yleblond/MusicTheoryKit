import Foundation
#if canImport(Security)
import Security
#endif

/// A small in-memory override layer sitting in front of `ProcessInfo.processInfo.environment`
/// for API keys. The CLI (a plain unsandboxed process launched from a shell) can rely on a
/// real environment variable being set before launch; a sandboxed GUI app launched by
/// double-click has no practical way to do that, so `ImprovSession` (AppCore) loads every
/// `Keychain`-persisted key here at startup/whenever it changes, and every `LLMProvider`
/// resolves through `resolve(_:)` instead of reading the environment directly — an override
/// wins if present, otherwise the real environment variable is still checked (so the CLI's own
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
    /// environment variable again. In-memory only — does NOT touch the Keychain, see
    /// `persist(_:forEnvVar:)` for the entry point that does both.
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

    // MARK: - Keychain-backed persistence (App SwiftUI's own keys, not the CLI's real env vars)

    /// `kSecAttrService` for every item this stores — scopes lookups/deletes to just this
    /// app's own keys, same purpose `LLMConnectionRecord`'s dedicated CloudKit container serves
    /// for its own data. `kSecAttrAccount` (the per-call `envVar`) is the per-key identifier
    /// within this service.
    private static let keychainService = "com.jamshack.JamShackApp.llmAPIKeys"

    /// Writes (or, if `key` is `nil`/empty, deletes) the Keychain item for `envVar`, AND
    /// updates the in-memory override the same way `set(_:forEnvVar:)` does — the one call
    /// `ImprovSession.setLLMAPIKey` needs instead of having to call both itself.
    /// `kSecAttrSynchronizable: true` opts into iCloud Keychain sync (when the user has that
    /// enabled) — the direct Keychain equivalent of `LLMConnectionRecord`'s CloudKit sync,
    /// appropriate here specifically because these are secrets (unlike CloudKit records,
    /// which are readable via CKQuery/Console, an iCloud Keychain item stays under the OS's own
    /// secret-storage protections while still syncing across the user's devices). Falls back
    /// to a LOCAL (non-synchronizable) item if that add fails — confirmed empirically
    /// (`SecItemAdd` returns `errSecMissingEntitlement`/-34018) for any process without a
    /// proper iCloud-Keychain-sync entitlement, which includes the CLI executable and every
    /// `swift test`/`swift run` invocation — same graceful-degradation shape as
    /// `ImprovSession.modelContainer`'s CloudKit-private → local-only fallback, never a silent
    /// no-op.
    public static func persist(_ key: String?, forEnvVar envVar: String) {
        set(key, forEnvVar: envVar)
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: envVar,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
        ]
        SecItemDelete(query as CFDictionary)
        guard let key, !key.isEmpty else { return }
        var syncedQuery = query
        syncedQuery[kSecAttrSynchronizable as String] = true
        syncedQuery[kSecValueData as String] = Data(key.utf8)
        guard SecItemAdd(syncedQuery as CFDictionary, nil) == errSecSuccess else {
            var localQuery = query
            localQuery[kSecAttrSynchronizable as String] = false
            localQuery[kSecValueData as String] = Data(key.utf8)
            SecItemAdd(localQuery as CFDictionary, nil)
            return
        }
        #endif
    }

    /// The Keychain-persisted key for `envVar`, or `nil` if none was ever saved — used only to
    /// migrate/prefill (e.g. `ImprovSession.migrateLLMAPIKeysFromJSONIfNeeded`, the SwiftUI
    /// "JamShack > LLM" tab's own prefill); `resolve(_:)` remains the entry point every
    /// `LLMProvider` actually calls at request time.
    public static func persistedKey(forEnvVar envVar: String) -> String? {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: envVar,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
        #else
        return nil
        #endif
    }

    /// Every env-var slot with a Keychain-persisted key — used once, at startup, to push every
    /// persisted key into the in-memory override (mirrors the old
    /// `LLMAPIKeysFile.keysByEnvVar.keys` enumeration this replaces).
    public static func persistedEnvVars() -> [String] {
        #if canImport(Security)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrSynchronizable as String: kSecAttrSynchronizableAny,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitAll,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let items = result as? [[String: Any]] else { return [] }
        return items.compactMap { $0[kSecAttrAccount as String] as? String }
        #else
        return []
        #endif
    }
}
