import Foundation
import SwiftData

/// Which "Composition IA" prompt-part category a `PromptSnippetRecord` belongs to — the
/// SwiftData-era replacement for the 3 fixed subfolders (`Cadrage Composition Descriptive`/
/// `Cadrage Composition Soundtrack`/`Indications Soundtracks`) `setPromptsFolder` used to
/// create. All 3 categories share the exact same shape (a name + a plain text body), so one
/// record type with a discriminator column avoids 3 near-identical `@Model` classes.
enum PromptSnippetCategory: String, Codable {
    case textFraming, soundTrackFraming, soundTrackInstructions
}

/// The SwiftData-backed counterpart of a saved framing sentence or soundtrack style
/// indication — see `PromptSnippetCategory`'s own doc comment for why one record type covers
/// all 3 categories. `name` is the addressable "save as" name (mirrors the old `.txt` filename,
/// minus the extension).
@Model
final class PromptSnippetRecord {
    var category: String = PromptSnippetCategory.textFraming.rawValue
    var name: String = ""
    var text: String = ""

    init(category: PromptSnippetCategory, name: String, text: String) {
        self.category = category.rawValue
        self.name = name
        self.text = text
    }
}
