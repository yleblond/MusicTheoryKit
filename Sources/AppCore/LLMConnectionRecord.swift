import Foundation
import SwiftData
import LLMEngine

/// The SwiftData-backed counterpart of `LLMConnection` (`LLMEngine/LLMConnection.swift`,
/// unchanged — it stays the stable value type `LLMProvider`/`LLMClient` and every test
/// actually work with). Same split as `FMPieceDTO`/`LLMPieceDTO` elsewhere in this project:
/// the storage-engine-facing type is kept separate from the stable contract type, connected
/// by an explicit conversion, rather than making the contract type itself a `@Model`.
@Model
final class LLMConnectionRecord {
    var id: UUID = UUID()
    var name: String = ""
    var provider: String = ""
    var baseURL: String = ""
    var model: String = ""
    var apiKeyEnvVar: String?

    init(_ connection: LLMConnection) {
        id = UUID()
        name = connection.name
        provider = connection.provider
        baseURL = connection.baseURL
        model = connection.model
        apiKeyEnvVar = connection.apiKeyEnvVar
    }

    var asLLMConnection: LLMConnection {
        LLMConnection(name: name, provider: provider, baseURL: baseURL, model: model, apiKeyEnvVar: apiKeyEnvVar)
    }
}
