import SwiftUI
import AppCore
import JamShackUI
import MusicTheoryKit
import Localization

/// Detached-window counterpart of `ContentView`'s always-visible bottom keyboard bar (see
/// `AuxiliaryWindowID.computerKeyboard`) — same view, same wiring, just hosted in its own
/// `WindowGroup` instead of the main window.
struct ComputerKeyboardWindow: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        SessionGatedView { session, bridge in
            ComputerKeyboardInputBar(
                heldPitches: session.tracks.first { $0.id == .computerKeyboard }?.heldPitches ?? [],
                palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors,
                // Same rule as `ContentView.mainKeyboardBarLabel(session:)` — kept inline here
                // since this is the only other call site.
                label: appModel.mainKeyboardMode != nil
                    ? L10n.string(.appLabelNotesDuMode, session.currentLanguage)
                    : L10n.string(.appLabelClavierPrincipalActif, session.currentLanguage),
                octaveShift: session.computerKeyboardOctaveShift,
                onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) },
                modeTones: appModel.mainKeyboardMode?.pitchClasses.map(\.value) ?? [],
                showModeColoring: appModel.mainKeyboardMode != nil,
                chordRoot: appModel.mainKeyboardChord?.root,
                chordTones: appModel.mainKeyboardChord?.tones ?? [],
                referenceChordPitches: Set(PitchSequencing.ascendingPitches(forPitchClasses: appModel.mainKeyboardChord?.tones ?? [], startingAbove: 47)),
                showsPhysicalKeyLabels: session.theoryLiveInputSourceID == .computerKeyboard
            )
            .computerKeyboardInput(
                // Same both-conditions gate `ContentView`'s own bar uses (see
                // `ImprovSession.setComputerKeyboardInputEnabled`'s own doc comment) — this
                // detached window is "the same view, same wiring," so it must never let typing
                // stay live here after the main window's own toggle/source say it shouldn't.
                isActive: session.computerKeyboardInputEnabled && session.theoryLiveInputSourceID == .computerKeyboard,
                focusRequestToken: session.computerKeyboardFocusRequestToken,
                octaveShift: session.computerKeyboardOctaveShift,
                onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) }
            )
            .padding()
        }
        .onAppear { appModel.markWindowOpen(.computerKeyboard) }
        .onDisappear { appModel.markWindowClosed(.computerKeyboard) }
    }
}
