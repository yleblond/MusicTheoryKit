import SwiftUI
import AppCore
import JamShackUI

/// Start/stop the microphone track — used as the "Microphone" sub-tab of the "JamShack" tab.
/// A plain `View`, not a `Form`/`Section` itself, so it composes cleanly inside another Form.
/// Three blocks once the microphone is active: (1) start/stop + recognition mode, side by
/// side; (2) calibration + live level meter, side by side; (3) a segmented choice between
/// "Notes recues" (the live keyboard + chord/mode text, default) and "Spectrometre" (the FFT
/// spectroscope, opt-in — see `spectrogramContent`'s own doc comment for why leaving that tab
/// always stops the capture).
struct MicrophoneControlsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @State private var microphoneError: String?
    @State private var spectroscopeEnabled = false
    @State private var calibratingPhase: ImprovSession.MicrophoneCalibrationPhase?
    @State private var displayMode: DisplayMode = .notesReceived

    private enum DisplayMode: Hashable {
        case notesReceived
        case spectrogram
    }

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
                HStack(alignment: .top, spacing: 20) {
                    VStack(alignment: .leading, spacing: 8) {
                        if microphoneTrack != nil {
                            Text("Microphone actif").foregroundStyle(.green)
                            Button("Arreter", role: .destructive) { session.stopTrack(.microphone) }
                        } else {
                            Button("Demarrer l'ecoute") {
                                microphoneError = nil
                                do {
                                    try session.startTrack(.microphone)
                                } catch {
                                    microphoneError = "\(error)"
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Reconnaissance").font(.caption).foregroundStyle(.secondary)
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
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text("Microphone")
            } footer: {
                Text("Detection d'accords/notes jouees a la voix ou a un instrument acoustique, par analyse spectrale (FFT). Monophonique : une seule note a la fois. Polyphonique : plusieurs notes simultanees, avec un delai de confirmation.")
            }
            if let microphoneTrack {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            calibrationRow(phase: .quiet, label: "Note faible", value: session.microphoneCalibration.quietRMS)
                            calibrationRow(phase: .loud, label: "Note forte", value: session.microphoneCalibration.loudRMS)
                            if calibratingPhase != nil {
                                Button("Annuler", role: .cancel) {
                                    session.cancelMicrophoneCalibrationCapture()
                                    calibratingPhase = nil
                                }
                            } else {
                                Button("Reinitialiser", role: .destructive) {
                                    do {
                                        try session.resetMicrophoneCalibration()
                                    } catch {
                                        microphoneError = "\(error)"
                                    }
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Niveau").font(.caption).foregroundStyle(.secondary)
                            let rawLevel = microphoneTrack.microphoneLevel ?? 0
                            ProgressView(value: Double(session.microphoneCalibration.normalized(rawLevel) ?? min(1, max(0, rawLevel))))
                                .tint(.accentColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text("Calibration & niveau")
                } footer: {
                    Text(calibratingPhase == nil
                        ? "Joue quelques notes faibles puis fortes pour calibrer le niveau affiche ci-dessus a ce microphone/instrument."
                        : "En cours de capture : jouez maintenant, puis appuyez sur \u{201c}Terminer la capture\u{201d}.")
                }
                Section {
                    Picker("Affichage", selection: $displayMode) {
                        Label("Notes recues", systemImage: "pianokeys").tag(DisplayMode.notesReceived)
                        Label("Spectrometre", systemImage: "waveform").tag(DisplayMode.spectrogram)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: displayMode) { _, newValue in
                        guard newValue != .spectrogram, spectroscopeEnabled else { return }
                        spectroscopeEnabled = false
                        session.setMicrophoneSpectrumCaptureEnabled(false)
                    }
                    switch displayMode {
                    case .notesReceived:
                        notesReceivedContent(microphoneTrack)
                    case .spectrogram:
                        spectrogramContent(microphoneTrack)
                    }
                } footer: {
                    if displayMode == .spectrogram {
                        Text("Spectre FFT en direct — trait rouge vertical a chaque note reperee, seuils de calibration en pointilles. Desactive par defaut (cout de calcul supplementaire) et arrete automatiquement en quittant cet onglet.")
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private func calibrationRow(phase: ImprovSession.MicrophoneCalibrationPhase, label: String, value: Float) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(String(format: "%.4f", value)).foregroundStyle(.secondary).font(.caption)
            Button(calibratingPhase == phase ? "Terminer la capture" : "Capturer") {
                if calibratingPhase == phase {
                    do {
                        try session.endMicrophoneCalibrationCapture()
                        calibratingPhase = nil
                    } catch {
                        microphoneError = "\(error)"
                    }
                } else {
                    session.beginMicrophoneCalibrationCapture(phase: phase)
                    calibratingPhase = phase
                }
            }
            .disabled(calibratingPhase != nil && calibratingPhase != phase)
        }
    }

    @ViewBuilder
    private func notesReceivedContent(_ track: WebConsoleTrackState) -> some View {
        AutoCenteredKeyboardView(
            heldPitches: track.heldPitches,
            palette: bridge.state.palette,
            paletteTextColors: bridge.state.paletteTextColors
        )
        if let chordLabel = track.chordLabel {
            Text(chordLabel).font(.headline).foregroundStyle(Color.accentColor)
        }
        if let modesLabel = track.modesLabel {
            Text(modesLabel).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// The spectroscope stays opt-in via its own `Toggle` (real per-window FFT-copy cost — see
    /// `MicrophonePitchListener.spectrumEnabled`'s doc comment) — but regardless of that
    /// toggle's own state, switching `displayMode` away from `.spectrogram` always stops
    /// capture too (the `onChange` in `body`): leaving this tab is as good a reason to stop as
    /// flipping the toggle off, and forgetting to flip it off before navigating away
    /// shouldn't leave the extra FFT work running unseen.
    @ViewBuilder
    private func spectrogramContent(_ track: WebConsoleTrackState) -> some View {
        Toggle("Activer le spectrometre", isOn: Binding(
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
                    markedPitches: track.heldPitches,
                    calibrationQuietMagnitude: session.microphoneCalibration.estimatedQuietPeakMagnitude,
                    calibrationLoudMagnitude: session.microphoneCalibration.estimatedLoudPeakMagnitude
                )
            }
        }
    }
}

#Preview {
    let session = ImprovSession()
    return MicrophoneControlsView(session: session, bridge: SessionUIBridge(session: session))
}
