import Foundation

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
