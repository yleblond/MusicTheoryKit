import SwiftUI
import AppCore
import JamShackUI
import Localization

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

    private static func label(for mode: MicrophoneRecognitionMode, _ language: AppLanguage) -> String {
        switch mode {
        case .monophonicHeuristic: return L10n.string(.optionMonoHeuristique, language)
        case .monophonicHPS: return L10n.string(.optionMonoHPS, language)
        case .polyphonicLatched(let windows): return "\(L10n.string(.optionPolyLatched, language)) (N=\(windows))"
        case .polyphonicSliding(let windows): return "\(L10n.string(.optionPolySliding, language)) (K=\(windows))"
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
                            Text(L10n.string(.appLabelMicrophoneActif, session.currentLanguage)).foregroundStyle(.green)
                            Button(L10n.string(.appButtonArreter, session.currentLanguage), role: .destructive) { session.stopTrack(.microphone) }
                        } else {
                            Button(L10n.string(.appButtonDemarrerEcoute, session.currentLanguage)) {
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
                        Text(L10n.string(.appHeadingReconnaissance, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                        Picker(L10n.string(.fieldModeReconnaissance, session.currentLanguage), selection: Binding(
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
                                Text(Self.label(for: mode, session.currentLanguage)).tag(mode)
                            }
                        }
                        .labelsHidden()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } header: {
                Text(L10n.string(.appHeadingMicrophone, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintDetectionMicrophone, session.currentLanguage))
            }
            if let microphoneTrack {
                Section {
                    HStack(alignment: .top, spacing: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            calibrationRow(phase: .quiet, label: L10n.string(.appLabelNoteFaible, session.currentLanguage), value: session.microphoneCalibration.quietRMS)
                            calibrationRow(phase: .loud, label: L10n.string(.appLabelNoteForte, session.currentLanguage), value: session.microphoneCalibration.loudRMS)
                            if calibratingPhase != nil {
                                Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) {
                                    session.cancelMicrophoneCalibrationCapture()
                                    calibratingPhase = nil
                                }
                            } else {
                                Button(L10n.string(.appButtonReinitialiser, session.currentLanguage), role: .destructive) {
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
                            Text(L10n.string(.appHeadingNiveau, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
                            let rawLevel = microphoneTrack.microphoneLevel ?? 0
                            ProgressView(value: Double(session.microphoneCalibration.normalized(rawLevel) ?? min(1, max(0, rawLevel))))
                                .tint(.accentColor)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } header: {
                    Text(L10n.string(.appHeadingCalibrationNiveau, session.currentLanguage))
                } footer: {
                    Text(calibratingPhase == nil
                        ? L10n.string(.appHintCalibrationNiveau, session.currentLanguage)
                        : L10n.string(.appFormatEnCoursDeCapture, session.currentLanguage, L10n.string(.appButtonTerminerCapture, session.currentLanguage)))
                }
                Section {
                    Picker(L10n.string(.appFieldAffichage, session.currentLanguage), selection: $displayMode) {
                        Label(L10n.string(.appLabelNotesRecues, session.currentLanguage), systemImage: "pianokeys").tag(DisplayMode.notesReceived)
                        Label(L10n.string(.appLabelSpectrometre, session.currentLanguage), systemImage: "waveform").tag(DisplayMode.spectrogram)
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
                        Text(L10n.string(.appHintSpectreFFT, session.currentLanguage))
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
            Button(calibratingPhase == phase ? L10n.string(.appButtonTerminerCapture, session.currentLanguage) : L10n.string(.appButtonCapturer, session.currentLanguage)) {
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
        Toggle(L10n.string(.appToggleActiverSpectrometre, session.currentLanguage), isOn: Binding(
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
