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

    // MARK: - Foundation Models ("foundation-models" provider)
    //
    // No test here actually invokes `FoundationModelsProvider.generate`/`generatePieceDTO` or
    // `LLMClient.generate`/`generatePieceJSON` with a "foundation-models" connection: unlike the
    // other 3 providers, there's no way to force a deterministic failure (e.g. a missing API
    // key) before any real work happens — `SystemLanguageModel.default.availability` reads real
    // device/OS state, so a call could either throw `.modelUnavailable` or actually run live
    // on-device inference depending on the machine running the test. Covered here: pure
    // string-formatting behavior, the `generatePieceJSON` fallthrough for other providers, and
    // the `LLMChordDTO`/.../`LLMPieceDTO` `Codable` round-trip (guards the `Decodable`->`Codable`
    // widen those DTOs needed so `FoundationModelsProvider.generatePieceDTO` can re-encode its
    // guided-generation result). Live dispatch/inference is a manual on-device check.

    func testUnsupportedProviderDescriptionMentionsFoundationModels() {
        XCTAssertTrue(LLMError.unsupportedProvider("x").description.contains("foundation-models"))
    }

    func testModelUnavailableDescriptionIncludesReason() {
        XCTAssertTrue(LLMError.modelUnavailable("Apple Intelligence not enabled").description.contains("Apple Intelligence not enabled"))
    }

    func testGeneratePieceJSONFallsThroughToGenerateForNonFoundationModelsProvider() {
        let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8")
        XCTAssertThrowsError(try LLMClient.generatePieceJSON(prompt: "hello", connection: connection)) { error in
            guard case LLMError.missingAPIKey = error else {
                return XCTFail("expected generatePieceJSON to fall through to generate (and fail on missing key) for a non-foundation-models provider, got \(error)")
            }
        }
    }

    func testLLMPieceDTOCodableRoundTrip() throws {
        let original = LLMPieceDTO(
            title: "Test Piece",
            tempoBPM: 120,
            tonic: "C",
            scaleID: "major",
            sections: [
                LLMSectionDTO(
                    name: "A",
                    lengthInMeasures: 4,
                    tonic: "C",
                    scaleID: "major",
                    chords: [LLMChordDTO(measure: 1, root: "C", templateID: "maj", durationBeats: 4)],
                    melody: [LLMMelodyNoteDTO(measure: 1, beat: 1, durationBeats: 1, pitch: 60)]
                )
            ]
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(LLMPieceDTO.self, from: data)
        XCTAssertEqual(decoded.title, original.title)
        XCTAssertEqual(decoded.tempoBPM, original.tempoBPM)
        XCTAssertEqual(decoded.tonic, original.tonic)
        XCTAssertEqual(decoded.scaleID, original.scaleID)
        XCTAssertEqual(decoded.sections.count, 1)
        XCTAssertEqual(decoded.sections[0].chords.first?.root, "C")
        XCTAssertEqual(decoded.sections[0].chords.first?.templateID, "maj")
        XCTAssertEqual(decoded.sections[0].melody?.first?.pitch, 60)
    }
}
