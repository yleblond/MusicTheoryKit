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

    /// Sheet target for `MIDIKeyboardSplitEditorView` — identity is the same
    /// uniqueID-first/displayName-fallback pair the split itself is matched by
    /// (`ImprovSession.midiKeyboardSplit`), not the row's array offset.
    private struct SplitEditorTarget: Identifiable {
        let uniqueID: Int32?
        let displayName: String
        var id: String { uniqueID.map(String.init) ?? displayName }
    }
    @State private var splitEditorTarget: SplitEditorTarget?

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
                let sources = session.availableMIDISourceDescriptors()
                if sources.isEmpty {
                    Text(L10n.string(.appPlaceholderAucuneSourceMidi, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                } else {
                    ForEach(Array(sources.enumerated()), id: \.offset) { index, source in
                        let split = session.midiKeyboardSplit(uniqueID: source.uniqueID, displayName: source.name)
                        let activeZoneNames = (split?.isEnabled == true) ? split?.zones.map(\.name) ?? [] : []
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                IconAssignmentButton(
                                    currentIcon: session.midiDeviceIcon(uniqueID: source.uniqueID, displayName: source.name),
                                    defaultIcon: "pianokeys",
                                    canUseAI: session.currentLLMConnection != nil,
                                    language: session.currentLanguage,
                                    onSuggestAI: {
                                        let icon = try session.suggestIcon(kind: "clavier MIDI", name: source.name)
                                        try session.setMIDIDeviceIcon(uniqueID: source.uniqueID, displayName: source.name, iconSystemName: icon)
                                    },
                                    onPickManual: { icon in
                                        try? session.setMIDIDeviceIcon(uniqueID: source.uniqueID, displayName: source.name, iconSystemName: icon)
                                    },
                                    onError: { _ in }
                                )
                                Button {
                                    splitEditorTarget = SplitEditorTarget(uniqueID: source.uniqueID, displayName: source.name)
                                } label: {
                                    Image(systemName: "arrow.triangle.branch")
                                        .foregroundStyle(activeZoneNames.isEmpty ? Color.primary : Color.accentColor)
                                }
                                .buttonStyle(.borderless)
                                .help(activeZoneNames.isEmpty ? "Configurer un split de clavier" : "Split actif — modifier")
                                if let channel = session.observedChannel(forMIDISourceIndex: index) {
                                    Text(L10n.string(.appFormatCanalMidi, session.currentLanguage, source.name, channel + 1))
                                } else {
                                    Text(source.name)
                                }
                                if !activeZoneNames.isEmpty {
                                    Spacer()
                                    Text("Split actif")
                                        .font(.caption)
                                        .foregroundStyle(Color.accentColor)
                                }
                            }
                            if !activeZoneNames.isEmpty {
                                Text("→ " + activeZoneNames.joined(separator: ", "))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .padding(.leading, 28)
                            }
                        }
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
        .sheet(item: $splitEditorTarget) { target in
            MIDIKeyboardSplitEditorView(session: session, uniqueID: target.uniqueID, displayName: target.displayName)
        }
    }
}

#Preview {
    let session = ImprovSession()
    return JamShackMIDIView(session: session, bridge: SessionUIBridge(session: session))
}
