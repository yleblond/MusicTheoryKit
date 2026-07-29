import XCTest
@testable import LLMEngine

/// Exercises the real system Keychain (no mock/injection point exists, same as this project's
/// other tests that touch real OS facilities directly) — every test uses its own unique
/// `envVar` and cleans up via `persist(nil, forEnvVar:)` in a `defer`, so nothing is left
/// behind on the developer's login keychain across runs.
final class APIKeyStoreTests: XCTestCase {

    func testPersistThenPersistedKeyRoundTrips() {
        let envVar = "APIKeyStoreTests_RoundTrip_\(UUID().uuidString)"
        defer { APIKeyStore.persist(nil, forEnvVar: envVar) }

        XCTAssertNil(APIKeyStore.persistedKey(forEnvVar: envVar))
        APIKeyStore.persist("sk-test-123", forEnvVar: envVar)
        XCTAssertEqual(APIKeyStore.persistedKey(forEnvVar: envVar), "sk-test-123")
    }

    func testPersistNilOrEmptyDeletesTheKeychainItem() {
        let envVar = "APIKeyStoreTests_Delete_\(UUID().uuidString)"
        defer { APIKeyStore.persist(nil, forEnvVar: envVar) }

        APIKeyStore.persist("sk-test-123", forEnvVar: envVar)
        XCTAssertNotNil(APIKeyStore.persistedKey(forEnvVar: envVar))

        APIKeyStore.persist("", forEnvVar: envVar)
        XCTAssertNil(APIKeyStore.persistedKey(forEnvVar: envVar))
    }

    func testPersistedEnvVarsIncludesOnlyCurrentlyPersistedSlots() {
        let envVar = "APIKeyStoreTests_Enumerate_\(UUID().uuidString)"
        defer { APIKeyStore.persist(nil, forEnvVar: envVar) }

        XCTAssertFalse(APIKeyStore.persistedEnvVars().contains(envVar))
        APIKeyStore.persist("sk-test-123", forEnvVar: envVar)
        XCTAssertTrue(APIKeyStore.persistedEnvVars().contains(envVar))
    }

    /// `resolve(_:)` itself is unchanged by the Keychain-persistence addition — still an
    /// in-memory override (set by `persist`/`set`) over the real environment variable, not a
    /// live Keychain lookup on every call (see `APIKeyStore`'s own doc comment for why).
    func testResolvePrefersPersistedOverrideOverEnvironmentVariable() {
        let envVar = "APIKeyStoreTests_Resolve_\(UUID().uuidString)"
        defer { APIKeyStore.persist(nil, forEnvVar: envVar) }

        XCTAssertNil(APIKeyStore.resolve(envVar))
        APIKeyStore.persist("sk-test-override", forEnvVar: envVar)
        XCTAssertEqual(APIKeyStore.resolve(envVar), "sk-test-override")
    }
}
