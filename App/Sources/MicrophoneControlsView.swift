import SwiftUI
import AppCore
import JamShackUI

/// Start/stop the microphone track — used as the "Microphone" sub-tab of the "JamShack" tab.
/// A plain `View`, not a `Form`/`Section` itself, so it composes cleanly inside another Form.
/// While active, also shows the live input level, the notes currently being detected, the
/// recognized chord/mode in text form (re-added per explicit user request — this screen
/// originally omitted it on an earlier request, since the Live screen already shows
/// chord/mode recognition; both asks are honored by showing it here too now, not by
/// reversing the Live screen's own scope), and an opt-in (off by default) spectroscope —
/// the live FFT spectrum with a vertical marker at each detected note.
struct MicrophoneControlsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @State private var microphoneError: String?
    @State private var spectroscopeEnabled = false

    /// `bridge.state.tracks` only ever contains currently-listening tracks (see
    /// `WebConsoleTrackState`'s own doc comment) — reading through the bridge here instead of
    /// `session.tracks` directly avoids binding to state mutated off the main thread.
    private var microphoneTrack: WebConsoleTrackState? {
        bridge.state.tracks.first { $0.id == "micro" }
    }

    /// The 4 fixed presets the CLI's own `track <id> mode ...` menu offers (see
    /// `recognitionModePresets` in `Sources/JamShack/main.swift`) — an arbitrary custom window
    /// count is reachable from the CLI/API but not exposed here, same "cover the common
    /// choices, not every knob" scope as the rest of this screen.
    private static let recognitionModePresets: [MicrophoneRecognitionMode] = [
        .monophonicHeuristic, .monophonicHPS, .default, .polyphonicSliding(windows: 3),
    ]

    private static func label(for mode: MicrophoneRecognitionMode) -> String {
        switch mode {
        case .monophonicHeuristic: return "Monophonique (heuristique)"
        case .monophonicHPS: return "Monophonique (HPS)"
        case .polyphonicLatched(let windows): return "Polyphonique verrouille (N=\(windows))"
        case .polyphonicSliding(let windows): return "Polyphonique glissant (K=\(windows))"
        }
    }

    /// Read directly from `session.tracks` (not the bridge) — unlike `heldPitches`/
    /// `microphoneLevel` (touched every audio callback), this only ever changes via an
    /// explicit call to `setMicrophoneRecognitionMode` from this same screen's own Picker, on
    /// the main thread — the same "safe to read directly" convention already used for
    /// `session.midiFusionMode`/`session.currentScene` elsewhere in this app.
    private var currentRecognitionMode: MicrophoneRecognitionMode {
        session.tracks.first { $0.id == .microphone }?.microphoneRecognitionMode ?? .default
    }

    var body: some View {
        Form {
            Section {
                if let microphoneError {
                    Text(microphoneError).foregroundStyle(.red).font(.caption)
                }
                if microphoneTrack != nil {
                    Text("Microphone actif").foregroundStyle(.green)
                    Button("Arreter", role: .destructive) { session.stopTrack(.microphone) }
                } else {
                    Button("Demarrer l'ecoute du microphone") {
                        microphoneError = nil
                        do {
                            try session.startTrack(.microphone)
                        } catch {
                            microphoneError = "\(error)"
                        }
                    }
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("Detection d'accords/notes jouees a la voix ou a un instrument acoustique, par analyse spectrale (FFT).")
            }
            Section {
                Picker("Mode", selection: Binding(
                    get: { currentRecognitionMode },
                    set: { newMode in
                        do {
                            try session.setMicrophoneRecognitionMode(newMode, for: .microphone)
                        } catch {
                            microphoneError = "\(error)"
                        }
                    }
                )) {
                    ForEach(Self.recognitionModePresets, id: \.self) { mode in
                        Text(Self.label(for: mode)).tag(mode)
                    }
                }
            } header: {
                Text("Mode de reconnaissance / filtrage")
            } footer: {
                Text("Monophonique : une seule note a la fois (voix, instrument solo). Polyphonique : plusieurs notes simultanees, avec un delai de confirmation (verrouille = strict, glissant = tolere un echantillon rate).")
            }
            if let microphoneTrack {
                Section {
                    ProgressView(value: Double(min(1, max(0, microphoneTrack.microphoneLevel ?? 0))))
                        .tint(.accentColor)
                } header: {
                    Text("Niveau")
                }
                Section {
                    AutoCenteredKeyboardView(
                        heldPitches: microphoneTrack.heldPitches,
                        palette: bridge.state.palette,
                        paletteTextColors: bridge.state.paletteTextColors
                    )
                    if let chordLabel = microphoneTrack.chordLabel {
                        Text(chordLabel).font(.headline).foregroundStyle(Color.accentColor)
                    }
                    if let modesLabel = microphoneTrack.modesLabel {
                        Text(modesLabel).font(.caption).foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Notes recues")
                }
                spectroscopeSection(microphoneTrack)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private func spectroscopeSection(_ track: WebConsoleTrackState) -> some View {
        Section {
            Toggle("Spectroscope", isOn: Binding(
                get: { spectroscopeEnabled },
                set: { newValue in
                    spectroscopeEnabled = newValue
                    session.setMicrophoneSpectrumCaptureEnabled(newValue)
                }
            ))
            if spectroscopeEnabled {
                TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                    let snapshot = session.currentMicrophoneSpectrum()
                    SpectrumView(
                        magnitudes: snapshot?.magnitudes ?? [],
                        binHz: snapshot?.binHz ?? 1,
                        markedPitches: track.heldPitches
                    )
                }
            }
        } header: {
            Text("Spectroscope")
        } footer: {
            Text("Spectre FFT en direct — trait rouge vertical a chaque note reperee. Desactive par defaut (cout de calcul supplementaire).")
        }
    }
}

#Preview {
    let session = ImprovSession()
    return MicrophoneControlsView(session: session, bridge: SessionUIBridge(session: session))
}
