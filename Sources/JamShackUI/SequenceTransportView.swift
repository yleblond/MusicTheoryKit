import SwiftUI
import Localization

/// Which way a mode's notes play — only meaningful for the Mode Library (a chord or a
/// progression has no "direction", just a fixed sequence).
public enum SequencePlayDirection: String, CaseIterable, Sendable {
    case ascending, descending, both
}

/// A playback bar shared by the Chord/Mode/Progression Library detail screens: an optional
/// Asc/Desc/Asc-et-Desc control (Mode Library only — pass `direction: nil` to omit it) and a
/// start/stop button. The instrument picker itself is NOT part of this view — it's hoisted to
/// `TheoryView`'s shared header (one choice for all three screens, see `FavoriteSoundPickerView`
/// there) rather than duplicated per screen.
public struct SequenceTransportView: View {
    public let direction: Binding<SequencePlayDirection>?
    public let isPlaying: Bool
    public let language: AppLanguage
    public let onPlay: () -> Void
    public let onStop: () -> Void

    public init(
        direction: Binding<SequencePlayDirection>? = nil,
        isPlaying: Bool,
        language: AppLanguage,
        onPlay: @escaping () -> Void,
        onStop: @escaping () -> Void
    ) {
        self.direction = direction
        self.isPlaying = isPlaying
        self.language = language
        self.onPlay = onPlay
        self.onStop = onStop
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let direction {
                Picker("", selection: direction) {
                    Text(L10n.string(.appButtonAscendant, language)).tag(SequencePlayDirection.ascending)
                    Text(L10n.string(.appButtonDescendant, language)).tag(SequencePlayDirection.descending)
                    Text(L10n.string(.appButtonAscEtDescendant, language)).tag(SequencePlayDirection.both)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            HStack {
                if isPlaying {
                    Button(L10n.string(.appButtonArreter, language), role: .destructive, action: onStop)
                } else {
                    Button(L10n.string(.appButtonDemarrer, language), action: onPlay)
                }
                Spacer()
            }
        }
    }
}
