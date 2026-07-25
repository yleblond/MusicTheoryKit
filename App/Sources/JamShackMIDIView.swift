import SwiftUI
import AppCore
import JamShackUI

/// MIDI settings sub-tab of the "JamShack" tab: fusion mode (one merged track vs. one track
/// per visible port), a manual refresh of the visible-source list (this app doesn't watch
/// for CoreMIDI hot-plug notifications — see `ImprovSession.refreshTracks`'s doc comment),
/// the list itself — mirrors the CLI's `midi-mode`/`refresh-midi` commands, both part of its
/// own `catJamShack` menu category — and a keyboard per currently-listening MIDI track
/// showing the notes actually coming in, no chord/mode recognition overlay (that already has
/// its own home, the Live screen).
struct JamShackMIDIView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    /// `bridge.state.tracks` only ever contains currently-listening tracks (see
    /// `WebConsoleTrackState`'s own doc comment) — matches `.midiMerged` ("midi") and every
    /// `.midiSource(n)` ("midi:1", "midi:2"...), see `TrackID.wireIDText`.
    private var midiTracks: [WebConsoleTrackState] {
        bridge.state.tracks.filter { $0.id == "midi" || $0.id.hasPrefix("midi:") }
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode MIDI", selection: Binding(
                    get: { session.midiFusionMode },
                    set: { session.setMIDIFusionMode($0) }
                )) {
                    Text("Fusionne").tag(MIDIFusionMode.merged)
                    Text("Individuel").tag(MIDIFusionMode.individual)
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            } header: {
                Text("Mode MIDI")
            } footer: {
                Text("Fusionne : toutes les entrees MIDI comptent comme une seule piste. Individuel : une piste par port MIDI visible.")
            }
            Section {
                Button("Rafraichir la liste MIDI") { session.refreshTracks() }
                let sources = session.availableMIDISources()
                if sources.isEmpty {
                    Text("Aucune source MIDI visible.").font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { name in
                        Text(name)
                    }
                }
            } header: {
                Text("Sources MIDI visibles")
            }
            ForEach(midiTracks, id: \.id) { track in
                Section {
                    AutoCenteredKeyboardView(
                        heldPitches: track.heldPitches,
                        palette: bridge.state.palette,
                        paletteTextColors: bridge.state.paletteTextColors
                    )
                } header: {
                    Text(track.label)
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

#Preview {
    let session = ImprovSession()
    return JamShackMIDIView(session: session, bridge: SessionUIBridge(session: session))
}
