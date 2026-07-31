import Foundation

/// The single FR/EN/DE source of truth for every `L10nKey`. French is the authored reference
/// (must exactly match what used to be a literal at each call site); English and German are
/// translations. Shared by the terminal (`JamShack/main.swift`) and the web surfaces
/// (`WebConsole/StaticAssets.swift`, `WebConsole/VirtualKeyboardAssets.swift` — the latter two
/// via a generated `L10N` JS object, see `l10nJSTable()`), so a label written once here never
/// needs to be hand-copied per surface per language.
///
/// Loaded from the bundled `Resources/L10nTable.json` rather than a Swift dictionary literal:
/// the previous ~650-entry literal made Release (`-O`, whole-module optimization) builds of this
/// target dramatically slower than Debug — the type checker/SIL optimizer's cost on one giant
/// literal expression, not present when parsing the equivalent JSON once at first access.
enum L10nTable {
    static let table: [L10nKey: [AppLanguage: String]] = {
        guard let url = Bundle.module.url(forResource: "L10nTable", withExtension: "json") else {
            fatalError("L10nTable.json resource missing from the Localization bundle")
        }
        guard let data = try? Data(contentsOf: url),
              let raw = try? JSONDecoder().decode([String: [String: String]].self, from: data) else {
            fatalError("L10nTable.json is malformed")
        }
        var result: [L10nKey: [AppLanguage: String]] = [:]
        result.reserveCapacity(raw.count)
        for (keyString, translations) in raw {
            guard let key = L10nKey(rawValue: keyString) else { continue }
            var languageMap: [AppLanguage: String] = [:]
            languageMap.reserveCapacity(translations.count)
            for (languageString, text) in translations {
                guard let language = AppLanguage(rawValue: languageString) else { continue }
                languageMap[language] = text
            }
            result[key] = languageMap
        }
        return result
    }()
}
