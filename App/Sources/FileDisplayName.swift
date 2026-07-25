import Foundation

extension String {
    /// Drops a trailing ".json" for display purposes only — every file list in this app
    /// (pieces/scenes/guides/soundtracks/compositions/LLM connections) comes from a
    /// JSON-backed folder, and showing the extension in every button/row is pure visual noise
    /// the user never needs to type back in — every load-by-name API still takes the real,
    /// full filename, this only changes what's SHOWN.
    var strippingJSONExtension: String {
        hasSuffix(".json") ? String(dropLast(5)) : self
    }
}
