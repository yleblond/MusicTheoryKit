import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// Fixed fill colors per `MelodicRole` — a hue set with NO overlap against
/// `FunctionalRoleColors`' own 4 colors (this colors NOTES relative to a chord, not chords
/// relative to the tonic), now that both palettes can appear side by side on
/// `ModeLibraryView`'s "accord"/"mélodie" mini keyboards at once — the two used to literally
/// share a hex value for `.stable`/`.home` (both `#2e7d32`) and `.contextual`/`.neutral` (both
/// `#1565c0`), which read as "the same role" across the two keyboards despite meaning entirely
/// different things, per explicit bug report.
public enum MelodicRoleColors {
    public static func fill(for role: MelodicRole) -> Color {
        switch role {
        case .stable: return Color(hex: "#00897b")
        case .chordTone: return Color(hex: "#3949ab")
        case .color: return Color(hex: "#fdd835")
        case .tension: return Color(hex: "#c62828")
        case .contextual: return Color(hex: "#546e7a")
        }
    }

    /// `.color`'s bright yellow is the only fill light enough to need dark text.
    public static func textColor(for role: MelodicRole) -> Color {
        role == .color ? .black : .white
    }
}

public func melodicRoleLabel(_ role: MelodicRole, language: AppLanguage) -> String {
    switch role {
    case .stable: return L10n.string(.appMelodicRoleStable, language)
    case .chordTone: return L10n.string(.appMelodicRoleChordTone, language)
    case .color: return L10n.string(.appMelodicRoleColor, language)
    case .tension: return L10n.string(.appMelodicRoleTension, language)
    case .contextual: return L10n.string(.appMelodicRoleContextual, language)
    }
}

/// A 3-step word (not a raw number, per this feature's own "les scores numériques ne doivent pas
/// être affichés par défaut" guidance) for a 0...1 score — shared by every field in
/// `MelodicNoteDetailView` (consonance/color/tension) so their wording stays consistent.
public func qualifierLabel(_ value: Double, language: AppLanguage) -> String {
    if value >= 0.6 { return L10n.string(.appQualifierEleve, language) }
    if value >= 0.35 { return L10n.string(.appQualifierMoyen, language) }
    return L10n.string(.appQualifierFaible, language)
}

/// "5"/"b7"/"9"/"#11"... — the short label under each note in the row, mirroring
/// `MelodicNoteProfile.chordToneType`/`extensionType`. Root/third/fifth/seventh get their
/// conventional numeral (not their generic slot name) so a dominant chord's 3rd reads as "3", not
/// as the word "third".
public func intervalLabel(for profile: MelodicNoteProfile) -> String {
    if let extensionType = profile.extensionType { return extensionType }
    switch profile.chordToneType {
    case .root: return "1"
    case .third: return profile.intervalFromChordRoot == 3 ? "b3" : "3"
    case .fifth: return profile.intervalFromChordRoot == 6 ? "b5" : (profile.intervalFromChordRoot == 8 ? "#5" : "5")
    case .seventh: return profile.intervalFromChordRoot == 11 ? "7" : "b7"
    case .other, nil: return "\(profile.intervalFromChordRoot)"
    }
}

/// The fuller "fiche" for whichever note is currently selected — name, structural facts in
/// plain words (never raw scores, see `qualifierLabel`'s own doc comment), the modal badge, and
/// up to 2 resolution candidates.
public struct MelodicNoteDetailView: View {
    public let profile: MelodicNoteProfile
    public let noteName: String
    public let language: AppLanguage

    public init(profile: MelodicNoteProfile, noteName: String, language: AppLanguage) {
        self.profile = profile
        self.noteName = noteName
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(noteName).font(.headline)
                Text(melodicRoleLabel(profile.defaultRole, language: language))
                    .font(.caption).bold()
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(MelodicRoleColors.fill(for: profile.defaultRole), in: Capsule())
                    .foregroundStyle(MelodicRoleColors.textColor(for: profile.defaultRole))
                if (profile.modalIdentity >= 0.5) {
                    Image(systemName: "diamond.fill").font(.caption2).foregroundStyle(FunctionalRoleColors.modalCharacteristicAccent)
                }
            }
            HStack(spacing: 16) {
                labeledQualifier(.appFieldConsonance, value: profile.consonance)
                labeledQualifier(.appFieldCouleurMelodique, value: profile.colorStrength)
                labeledQualifier(.appFieldTensionMelodique, value: profile.resolutionTendency)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func labeledQualifier(_ key: L10nKey, value: Double) -> some View {
        Text("\(L10n.string(key, language)) : \(qualifierLabel(value, language: language))")
    }
}

/// The resolution-candidates list, extracted out of `MelodicNoteDetailView` so it can sit
/// elsewhere in a caller's own layout (e.g. after the "recently played" history, per explicit
/// request) — laid out in one horizontal row (a `VStack` before) since there are never more than
/// a couple of candidates and a row reads faster than a stack of one-per-line entries.
public struct MelodicResolutionsRowView: View {
    public let profile: MelodicNoteProfile
    public let language: AppLanguage
    public let resolutionNoteName: (PitchClass) -> String

    public init(profile: MelodicNoteProfile, language: AppLanguage, resolutionNoteName: @escaping (PitchClass) -> String) {
        self.profile = profile
        self.language = language
        self.resolutionNoteName = resolutionNoteName
    }

    public var body: some View {
        if !profile.resolutions.isEmpty {
            HStack(spacing: 12) {
                Text(L10n.string(.appLabelResolutionsPossibles, language)).font(.caption).bold()
                ForEach(Array(profile.resolutions.enumerated()), id: \.offset) { _, resolution in
                    HStack(spacing: 4) {
                        Image(systemName: resolution.direction == .up ? "arrow.up" : "arrow.down")
                        Text(resolutionNoteName(resolution.targetNote))
                    }
                    .font(.caption)
                }
            }
        }
    }
}

/// Always-visible color/role key for the melodic-vocabulary palette — kept as its own view
/// (rather than merged with `FunctionalMapLegendView`) since the two legends' role sets/colors
/// are genuinely distinct. The fuller explanation used to live behind this view's own "?"
/// popover; see `TheoryLegendContent`'s own doc comment for where it lives now.
public struct MelodicMapLegendView: View {
    public let language: AppLanguage
    /// See `FunctionalMapLegendView.axis`'s own doc comment — same `.horizontal`/`.vertical`
    /// choice, for the same reason (a narrow column needs one role per line).
    public var axis: Axis

    public init(language: AppLanguage, axis: Axis = .horizontal) {
        self.language = language
        self.axis = axis
    }

    public var body: some View {
        Group {
            if axis == .horizontal {
                HStack(spacing: 12) { legendRows }
            } else {
                VStack(alignment: .leading, spacing: 6) { legendRows }
            }
        }
    }

    @ViewBuilder
    private var legendRows: some View {
        ForEach(MelodicRole.allCases, id: \.self) { role in
            HStack(spacing: 4) {
                Circle().fill(MelodicRoleColors.fill(for: role)).frame(width: 10, height: 10)
                Text(melodicRoleLabel(role, language: language)).font(.caption)
            }
        }
        HStack(spacing: 4) {
            Image(systemName: "diamond.fill").foregroundStyle(FunctionalRoleColors.modalCharacteristicAccent).font(.system(size: 9))
            Text(L10n.string(.appLabelCaracteristiqueModale, language)).font(.caption)
        }
    }
}

/// Public so `TheoryLegendContent` can compose it into the combined legend window/sheet.
public struct MelodicMapHelpContent: View {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(L10n.string(.appHelpMelodicMapTitle, language)).font(.headline)
            Group {
                Text(L10n.string(.appHelpMelodicMapStable, language))
                Text(L10n.string(.appHelpMelodicMapChordTone, language))
                Text(L10n.string(.appHelpMelodicMapColor, language))
                Text(L10n.string(.appHelpMelodicMapTension, language))
                Text(L10n.string(.appHelpMelodicMapContextual, language))
                Text(L10n.string(.appHelpFunctionalMapModal, language))
            }
            .font(.callout)
            Divider()
            Text(L10n.string(.appHelpMelodicMapPrinciple, language)).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: 340, alignment: .leading)
    }
}
