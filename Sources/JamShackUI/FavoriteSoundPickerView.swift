import SwiftUI
import AppCore
import Localization

/// A picker over `ImprovSession.favoriteSounds`, with an "Aucun" option and an empty-state
/// message — the same ~6-line block already hand-rolled at several call sites (e.g.
/// `GuideEditionView`'s "Ecouter le guide" section), extracted here so the Chord/Mode/
/// Progression Library screens (and any future one) share a single implementation. Takes the
/// favorites list and a binding directly rather than an `ImprovSession`, so it stays UI-only.
public struct FavoriteSoundPickerView: View {
    public let favoriteSounds: [ImprovSession.FavoriteSound]
    @Binding public var selectedID: String?
    public let language: AppLanguage

    public init(favoriteSounds: [ImprovSession.FavoriteSound], selectedID: Binding<String?>, language: AppLanguage) {
        self.favoriteSounds = favoriteSounds
        self._selectedID = selectedID
        self.language = language
    }

    public var body: some View {
        if favoriteSounds.isEmpty {
            Text(L10n.string(.appPlaceholderAucunSonFavori, language)).font(.caption).foregroundStyle(.secondary)
        } else {
            Picker(L10n.string(.fieldSon, language), selection: $selectedID) {
                Text(L10n.string(.appButtonAucun, language)).tag(String?.none)
                ForEach(favoriteSounds) { sound in
                    Text(sound.displayName).tag(String?.some(sound.id))
                }
            }
        }
    }
}
