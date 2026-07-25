import SwiftUI
import AppCore

/// Equivalent of the console's/CLI's "Run" view: the circle-of-fifths wheel on the left
/// (always present, same as `SessionUIBridge.state.wheel` itself — never gated behind an
/// active guide), and every currently-listening track on the right, each showing its held
/// notes on a `PitchKeyboardView` plus its recognized chord/mode labels — driven live by a
/// `SessionUIBridge`. The first screen that proves the full chain end to end (bridge
/// polling -> per-track adapter -> `PitchKeyboardView`); the wheel used to be its own tab,
/// merged in here so both are visible together without switching tabs.
public struct RunScreen: View {
    public let bridge: SessionUIBridge
    /// The `WebConsoleTrackState.id` (e.g. `"clavier"` for `.computerKeyboard`) allowed to be
    /// played by tapping/clicking its own keyboard — the "clavier virtuel" counterpart to the
    /// web console's clickable virtual-keyboard page. Every other track's keyboard stays
    /// read-only (tapping a MIDI-sourced track's display shouldn't inject a note into it).
    public let interactiveTrackID: String?
    public let onNoteOn: ((Int) -> Void)?
    public let onNoteOff: ((Int) -> Void)?

    public init(
        bridge: SessionUIBridge,
        interactiveTrackID: String? = nil,
        onNoteOn: ((Int) -> Void)? = nil,
        onNoteOff: ((Int) -> Void)? = nil
    ) {
        self.bridge = bridge
        self.interactiveTrackID = interactiveTrackID
        self.onNoteOn = onNoteOn
        self.onNoteOff = onNoteOff
    }

    public var body: some View {
        HStack(spacing: 0) {
            CircleOfFifthsWheelView(
                wheel: bridge.state.wheel,
                palette: bridge.state.palette,
                paletteTextColors: bridge.state.paletteTextColors,
                tracks: bridge.state.tracks
            )
                .padding()
                .frame(width: 525) // +75% over the original 300 — explicit user request.
            Divider()
            List(bridge.state.tracks, id: \.id) { track in
                let isInteractive = track.id == interactiveTrackID
                TrackRunRow(
                    track: track,
                    palette: bridge.state.palette,
                    paletteTextColors: bridge.state.paletteTextColors,
                    onNoteOn: isInteractive ? onNoteOn : nil,
                    onNoteOff: isInteractive ? onNoteOff : nil
                )
            }
            #if os(macOS)
            .listStyle(.inset)
            #endif
        }
    }
}

private struct TrackRunRow: View {
    let track: WebConsoleTrackState
    let palette: [String]
    let paletteTextColors: [String]
    let onNoteOn: ((Int) -> Void)?
    let onNoteOff: ((Int) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(track.label).font(.headline)
                if let owner = track.owner {
                    Text("(\(owner))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let chordLabel = track.chordLabel {
                    Text(chordLabel).font(.headline).foregroundStyle(Color.accentColor)
                }
            }
            if let modesLabel = track.modesLabel {
                Text(modesLabel).font(.caption).foregroundStyle(.secondary)
            }
            if let recognitionMode = track.recognitionMode {
                Text(recognitionMode).font(.caption2).foregroundStyle(.secondary)
            }
            AutoCenteredKeyboardView(
                heldPitches: track.heldPitches,
                chordRoot: track.chordRoot,
                chordTones: track.chordTones,
                modeTones: track.modeTones,
                palette: palette,
                paletteTextColors: paletteTextColors,
                onNoteOn: onNoteOn,
                onNoteOff: onNoteOff
            )
        }
        .padding(.vertical, 6)
    }
}
