import SwiftUI
import AppCore
import JamShackUI
import Localization

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
                Picker(L10n.string(.fieldModeMidi, session.currentLanguage), selection: Binding(
                    get: { session.midiFusionMode },
                    set: { session.setMIDIFusionMode($0) }
                )) {
                    Text(L10n.string(.appOptionFusionne, session.currentLanguage)).tag(MIDIFusionMode.merged)
                    Text(L10n.string(.appOptionIndividuel, session.currentLanguage)).tag(MIDIFusionMode.individual)
                }
                #if os(iOS)
                .pickerStyle(.segmented)
                #endif
            } header: {
                Text(L10n.string(.fieldModeMidi, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintModeMidiDetail, session.currentLanguage))
            }
            Section {
                Button(L10n.string(.appButtonRafraichirListeMidi, session.currentLanguage)) { session.refreshTracks() }
                let sources = session.availableMIDISources()
                if sources.isEmpty {
                    Text(L10n.string(.appPlaceholderAucuneSourceMidi, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(sources, id: \.self) { name in
                        Text(name)
                    }
                }
            } header: {
                Text(L10n.string(.appHeadingSourcesMidiVisibles, session.currentLanguage))
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
