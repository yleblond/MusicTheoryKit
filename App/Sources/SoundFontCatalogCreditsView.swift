import SwiftUI
import AppCore
import Localization

/// Every installed soundfont whose catalog license requires visible attribution (CC-BY-style, or
/// MIT's own "reproduce the copyright notice" condition) — MIT entries can set
/// `attributionRequired: true` too; this screen doesn't distinguish by SPDX id, only by the flag
/// each catalog entry was curated with. See `KnowledgeBase/SoundfontMgt/
/// SPEC-catalogue-soundfonts.md` §11.2.
struct SoundFontCatalogCreditsView: View {
    let session: ImprovSession

    @Environment(\.dismiss) private var dismiss

    private var creditedEntries: [SoundFontCatalogEntry] {
        let installedIds = Set(session.soundFonts.compactMap { entry -> String? in
            guard case .curated(_, let id, _) = entry.origin, !id.isEmpty else { return nil }
            return id
        })
        return CuratedSoundFontCatalog.entries
            .filter { installedIds.contains($0.id) && $0.license.attributionRequired }
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    var body: some View {
        NavigationStack {
            Form {
                if creditedEntries.isEmpty {
                    Section {
                        Text(L10n.string(.appPlaceholderAucunCredit, session.currentLanguage))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(creditedEntries) { entry in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.displayName)
                                Text("\(L10n.string(.appFormatCatalogueParAuteur, session.currentLanguage, entry.author)) — \(entry.license.name)")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let url = entry.license.url {
                                    Link(L10n.string(.appButtonEnSavoirPlus, session.currentLanguage), destination: url)
                                        .font(.caption2)
                                }
                            }
                        }
                    } footer: {
                        Text(L10n.string(.appHintCredits, session.currentLanguage))
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(L10n.string(.appHeadingCredits, session.currentLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string(.appButtonFermer, session.currentLanguage)) { dismiss() }
                }
            }
        }
    }
}
