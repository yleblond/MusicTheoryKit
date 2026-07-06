import XCTest
@testable import LLMEngine

final class LLMProviderTests: XCTestCase {

    // MARK: - AnthropicProvider (no network call is made on these paths)

    func testAnthropicProviderThrowsMissingAPIKeyWhenConnectionHasNoEnvVar() {
        let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8")
        XCTAssertThrowsError(try AnthropicProvider().generate(prompt: "hello", connection: connection)) { error in
            guard case LLMError.missingAPIKey(let envVar) = error else {
                return XCTFail("expected missingAPIKey, got \(error)")
            }
            XCTAssertEqual(envVar, "ANTHROPIC_API_KEY")
        }
    }

    func testAnthropicProviderThrowsMissingAPIKeyWhenEnvVarIsUnset() {
        let envVar = "ANTHROPIC_API_KEY_DOES_NOT_EXIST_IN_ENVIRONMENT"
        XCTAssertNil(ProcessInfo.processInfo.environment[envVar])
        let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8", apiKeyEnvVar: envVar)
        XCTAssertThrowsError(try AnthropicProvider().generate(prompt: "hello", connection: connection)) { error in
            guard case LLMError.missingAPIKey(let reportedVar) = error else {
                return XCTFail("expected missingAPIKey, got \(error)")
            }
            XCTAssertEqual(reportedVar, envVar)
        }
    }

    func testAnthropicProviderThrowsInvalidBaseURLOnMalformedURL() {
        let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "", model: "claude-opus-4-8", apiKeyEnvVar: "ANTHROPIC_API_KEY_DOES_NOT_EXIST")
        XCTAssertThrowsError(try AnthropicProvider().generate(prompt: "hello", connection: connection)) { error in
            guard case LLMError.missingAPIKey = error else {
                return XCTFail("expected missingAPIKey (checked before URL construction), got \(error)")
            }
        }
    }

    // MARK: - LLMClient.generate dispatch

    func testLLMClientDispatchesAnthropicProviderByName() {
        let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8")
        XCTAssertThrowsError(try LLMClient.generate(prompt: "hello", connection: connection)) { error in
            guard case LLMError.missingAPIKey = error else {
                return XCTFail("expected the anthropic provider to run (and fail on missing key), got \(error)")
            }
        }
    }

    func testLLMClientThrowsUnsupportedProviderForUnknownName() {
        let connection = LLMConnection(name: "Mystery", provider: "mystery-provider", baseURL: "https://example.com", model: "x")
        XCTAssertThrowsError(try LLMClient.generate(prompt: "hello", connection: connection)) { error in
            guard case LLMError.unsupportedProvider(let provider) = error else {
                return XCTFail("expected unsupportedProvider, got \(error)")
            }
            XCTAssertEqual(provider, "mystery-provider")
        }
    }

    func testUnsupportedProviderDescriptionMentionsAnthropic() {
        XCTAssertTrue(LLMError.unsupportedProvider("x").description.contains("anthropic"))
    }
}
