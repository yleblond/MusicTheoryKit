import SwiftUI
import AppCore
import MusicTheoryKit
import JamShackUI
import Localization

/// Standardized tonic+scale picker for MusicLab/Théorie screens — a compact badge showing the
/// FULL mode name (tonic + scale together, e.g. "La Majeur", never a bare scale name on its own)
/// that opens a popover to change either half. Introduced 2026-08-18 (backlog item 44) to replace
/// the tonic-`Picker` + scale-`Picker` pair each of Modes/Progressions/Tonnetz/Intonations rolled
/// independently — Dissonances had no tonic control at all, which is exactly what let its
/// "Gamme" legend disagree with the examined chord's own root (item 40, see
/// `DissonancesLibraryView.legendMode`'s own doc comment).
///
/// `tonic`/`scaleID` are generic `Binding`s so a call site can point them at the app-wide
/// `AppModel.sharedMode` (the 4 screens above) or at fully independent local `@State`
/// (Dissonances' legend) — this component has no opinion on which.
struct ModePickerBadge: View {
    let session: ImprovSession
    @Binding var tonic: Int
    @Binding var scaleID: String
    /// Which scales this call site allows picking, already filtered/ordered by the caller (e.g.
    /// `ScaleLibrary.scales(inFamily: 1)` for the 7-classic-modes-only screens, `ScaleLibrary.all`
    /// for Modes/Dissonances) — grouped by family for display, same grouping `ModeLibraryView`'s
    /// own list already uses. This component never widens or narrows a screen's own restriction.
    let allowedScales: [ScaleDefinition]
    var isEnabled: Bool = true
    /// `false` (default) sizes the badge to its own content — same "compact control" sizing as a
    /// normal `Picker`, so it never competes for space with sibling controls sharing its row (the
    /// 'octave' stepper in Modes, the toggles in Tonnetz, the reset button in Intonations — all
    /// broke exactly this way when this defaulted to always-greedy). Pass `true` only where the
    /// badge is meant to stretch and fill whatever width its container offers — currently
    /// Dissonances' "Gamme" legend (reaches the graph's own right edge) and Progressions/
    /// Exploration (their own row/column has no sibling to crowd out, so filling it is harmless
    /// and was the already-shipped, already-approved look — kept byte-for-byte via this flag
    /// rather than changed as a side effect of fixing the other three screens).
    var fillsAvailableWidth: Bool = false

    @State private var isPresented = false

    private var mode: Mode {
        Mode(tonic: PitchClass(tonic), scale: ScaleLibrary.byID(scaleID) ?? allowedScales.first ?? ScaleLibrary.all[0])
    }

    var body: some View {
        Button {
            isPresented = true
        } label: {
            HStack(spacing: 4) {
                Text(mode.displayName)
                if fillsAvailableWidth {
                    // Lets a call site stretch this button to fill available width (e.g.
                    // `DissonancesLibraryView.scalePickerRow`) while the chevron stays pinned
                    // trailing — only added when opted in, see `fillsAvailableWidth`'s own doc
                    // comment for why this isn't the default.
                    Spacer(minLength: 4)
                }
                // `chevron.up.chevron.down` — the same affordance macOS's own `.menu`-style
                // `Picker` renders, signaling "this reveals a value picker" (unlike an ellipsis,
                // which conventionally means "more actions/context menu" on Apple platforms) —
                // added per explicit request so users notice this badge is tappable.
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .disabled(!isEnabled)
        .popover(isPresented: $isPresented) {
            ModePickerPopoverContent(session: session, tonic: $tonic, scaleID: $scaleID, allowedScales: allowedScales)
        }
    }
}

/// The popover's own content — tonic (dropdown + 2-octave mini keyboard, the keyboard highlighted
/// by whichever scale is currently picked) above a family-grouped, sorted list of `allowedScales`.
/// Kept as its own `private` type (not inlined in `ModePickerBadge.body`) so the popover only gets
/// built while actually presented.
private struct ModePickerPopoverContent: View {
    let session: ImprovSession
    @Binding var tonic: Int
    @Binding var scaleID: String
    let allowedScales: [ScaleDefinition]

    private var currentScale: ScaleDefinition {
        ScaleLibrary.byID(scaleID) ?? allowedScales.first ?? ScaleLibrary.all[0]
    }

    /// Absolute pitch classes (0...11) of `currentScale` anchored at `tonic` — feeds the mini
    /// keyboard's `modeTones`, same "tonic + scale offsets" derivation `Mode.pitchClasses` already
    /// does, computed directly here so the keyboard updates live as `tonic` changes via its own
    /// taps without waiting on a `Mode` round-trip.
    private var modeTonePitchClasses: [Int] {
        currentScale.pitchClassesFromRoot.map { ((tonic + $0) % 12 + 12) % 12 }
    }

    /// Same family grouping/order `ModeLibraryView.familyGroups` uses, restricted to whatever
    /// `allowedScales` this call site passed in.
    private var groupedScales: [(family: ScaleFamily, scales: [ScaleDefinition])] {
        Set(allowedScales.map(\.familyID)).sorted().map { id in
            (ScaleFamilies.family(id), allowedScales.filter { $0.familyID == id })
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(L10n.string(.fieldTonique, session.currentLanguage)).font(.headline)
                Spacer()
                Picker("", selection: $tonic) {
                    ForEach(0..<12, id: \.self) { pitchClass in
                        Text(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false)).tag(pitchClass)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .fixedSize()
            }
            PitchKeyboardView(
                minMidi: 60, maxMidi: 83,
                modeTones: modeTonePitchClasses,
                showModeColoring: true,
                onNoteOn: { pitch in tonic = ((pitch % 12) + 12) % 12 },
                height: 100
            )
            Divider()
            Text(L10n.string(.fieldGamme, session.currentLanguage)).font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(groupedScales, id: \.family.id) { group in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.family.name).font(.caption).foregroundStyle(.secondary)
                            ForEach(group.scales, id: \.id) { scale in
                                Button {
                                    scaleID = scale.id
                                } label: {
                                    HStack {
                                        Text(scale.popularName)
                                            .foregroundStyle(scale.id == scaleID ? Color.accentColor : .primary)
                                        Spacer()
                                    }
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .frame(maxHeight: 240)
        }
        .padding()
        .frame(minWidth: 280)
    }
}
