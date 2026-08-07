import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// Fixed fill colors per `MelodicRole` — deliberately a DIFFERENT palette from
/// `FunctionalRoleColors` (this colors NOTES relative to a chord, not accords relative to the
/// tonic) even where a hue is shared, per this feature's own spec: "les deux systèmes peuvent
/// utiliser des couleurs visuellement apparentées, mais doivent avoir des légendes et des
/// sémantiques distinctes."
public enum MelodicRoleColors {
    public static func fill(for role: MelodicRole) -> Color {
        switch role {
        case .stable: return Color(hex: "#2e7d32")
        case .chordTone: return Color(hex: "#e8710a")
        case .color: return Color(hex: "#f9d71c")
        case .tension: return Color(hex: "#d32f2f")
        case .contextual: return Color(hex: "#1565c0")
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

/// One note of `MelodicVocabularyAnalysis.notes`, as a tappable chip — plain SwiftUI (not
/// `Canvas`, unlike the harmonic graphs): this is a simple linear row, so real `Button`s are both
/// less code AND natively accessible to VoiceOver, unlike a hand-rolled hit-testing surface.
public struct MelodicNoteChipView: View {
    public let profile: MelodicNoteProfile
    public let noteName: String
    public let isSelected: Bool
    public let onTap: () -> Void

    public init(profile: MelodicNoteProfile, noteName: String, isSelected: Bool, onTap: @escaping () -> Void) {
        self.profile = profile
        self.noteName = noteName
        self.isSelected = isSelected
        self.onTap = onTap
    }

    public var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Image(systemName: "diamond.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(FunctionalRoleColors.modalCharacteristicAccent)
                    .opacity((profile.modalIdentity >= 0.5) ? 1 : 0)
                ZStack {
                    Circle()
                        .fill(MelodicRoleColors.fill(for: profile.defaultRole))
                        .frame(width: 40, height: 40)
                        .overlay(Circle().stroke(Color.white, lineWidth: isSelected ? 3 : 0))
                        .overlay(
                            Circle().stroke(FunctionalRoleColors.modalCharacteristicAccent, lineWidth: (profile.modalIdentity >= 0.5) ? 2 : 0)
                                .padding(-3)
                        )
                    Text(intervalLabel(for: profile))
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(MelodicRoleColors.textColor(for: profile.defaultRole))
                }
                Text(noteName).font(.caption).bold()
            }
        }
        .buttonStyle(.plain)
    }
}

/// The fuller "fiche" for whichever note is currently selected — name, structural facts in
/// plain words (never raw scores, see `qualifierLabel`'s own doc comment), the modal badge, and
/// up to 2 resolution candidates.
public struct MelodicNoteDetailView: View {
    public let profile: MelodicNoteProfile
    public let noteName: String
    public let language: AppLanguage
    public let resolutionNoteName: (PitchClass) -> String

    public init(profile: MelodicNoteProfile, noteName: String, language: AppLanguage, resolutionNoteName: @escaping (PitchClass) -> String) {
        self.profile = profile
        self.noteName = noteName
        self.language = language
        self.resolutionNoteName = resolutionNoteName
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
            if !profile.resolutions.isEmpty {
                VStack(alignment: .leading, spacing: 2) {
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

    private func labeledQualifier(_ key: L10nKey, value: Double) -> some View {
        Text("\(L10n.string(key, language)) : \(qualifierLabel(value, language: language))")
    }
}

/// Always-visible color/role key for the melodic-vocabulary palette — kept as its own view
/// (rather than merged with `FunctionalMapLegendView`) since the two legends' role sets/colors
/// are genuinely distinct. The fuller explanation used to live behind this view's own "?"
/// popover; see `TheoryLegendContent`'s own doc comment for where it lives now.
public struct MelodicMapLegendView: View {
    public let language: AppLanguage

    public init(language: AppLanguage) {
        self.language = language
    }

    public var body: some View {
        HStack(spacing: 12) {
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
