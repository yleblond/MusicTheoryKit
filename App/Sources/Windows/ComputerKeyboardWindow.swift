import SwiftUI
import AppCore
import JamShackUI
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
                label: L10n.string(.appLabelClavierOrdinateurActif, session.currentLanguage),
                octaveShift: session.computerKeyboardOctaveShift,
                onNoteOn: { pitch in session.pressKey(pitch: pitch) },
                onNoteOff: { pitch in session.releaseKey(pitch: pitch) },
                onShiftOctave: { steps in session.shiftComputerKeyboardOctave(by: steps) }
            )
            .computerKeyboardInput(
                isActive: session.computerKeyboardInputEnabled,
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
