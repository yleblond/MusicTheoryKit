import Foundation
import SwiftData

/// The raw input to a text-based composition — title, pasted text, and style indications —
/// saved/loaded as its own small JSON file so a description can be reused later without
/// retyping it. Deliberately separate from `Piece` (the *composed* result) and from a saved
/// prompt (the *fully-built LLM request*): this is just the three fields the "Decrire le
/// morceau..." wizard collects, one level upstream of both.
struct CompositionDescription: Codable {
    var title: String?
    var sourceText: String
    var additionalInstructions: String?
}

/// The SwiftData-backed counterpart of `CompositionDescription` — same split as
/// `LLMConnectionRecord`/`LLMConnection`. `name` is the addressable "save as" name (mirrors the
/// old filename, minus extension) — deliberately NOT the same as `CompositionDescription
/// .title` (an independent, optional field the wizard collects; a description can be saved
/// under a name different from its own internal title, same as every other file-based category
/// before this migration).
@Model
final class CompositionDescriptionRecord {
    var id: String = ""
    var name: String = ""
    var encodedDescription: Data = Data()

    init(name: String, description: CompositionDescription) {
        id = UUID().uuidString
        self.name = name
        encodedDescription = (try? JSONEncoder().encode(description)) ?? Data()
    }

    var asCompositionDescription: CompositionDescription? {
        try? JSONDecoder().decode(CompositionDescription.self, from: encodedDescription)
    }
}
