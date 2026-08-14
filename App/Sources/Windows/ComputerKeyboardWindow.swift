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
            // Same `mainKeyboardPresentation(session:)`/`mainKeyboardBarLabel(session:)`
            // `ContentView`'s own embedded bar calls — previously this window hand-rolled a
            // simplified subset (mode/chord coloring only, no Studio `.live`/Guide-gating, no
            // `isClickable` gate), so it could disagree with the embedded bar about what the
            // main keyboard should look like once Théorie screens (or Studio) were detached.
            let mainKeyboard = appModel.mainKeyboardPresentation(session: session)
            ComputerKeyboardInputBar(
                heldPitches: mainKeyboard.heldPitches,
                palette: bridge.state.palette, paletteTextColors: bridge.state.paletteTextColors,
                label: appModel.mainKeyboardBarLabel(session: session),
                octaveShift: session.computerKeyboardOctaveShift,
                onNoteOn: { pitch in guard mainKeyboard.isClickable else { return }; session.pressKey(pitch: pitch) },
                onNoteOff: { pitch in guard mainKeyboard.isClickable else { return }; session.releaseKey(pitch: pitch) },
                onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) },
                modeTones: mainKeyboard.modeTones, showModeColoring: mainKeyboard.showModeColoring,
                chordRoot: mainKeyboard.chordRoot, chordTones: mainKeyboard.chordTones, referenceChordPitches: mainKeyboard.referenceChordPitches,
                showsPhysicalKeyLabels: session.theoryLiveInputSourceID == .computerKeyboard
            )
            .opacity(mainKeyboard.isClickable ? 1 : 0.5)
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
