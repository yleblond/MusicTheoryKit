import SwiftUI
import AppCore
import JamShackUI
import Localization

/// Start/stop the microphone track — used as the "Microphone" sub-tab of the "JamShack" tab.
/// A plain `View`, not a `Form`/`Section` itself, so it composes cleanly inside another Form.
/// Two blocks once the microphone is active: (1) start/stop + recognition mode, side by side;
/// (2) a segmented choice between "Calibration" (the calibration rows + level meter, moved in
/// here per explicit user request so it's a peer of the other three rather than always-visible
/// above them), "Notes recues" (the live keyboard + chord/mode text, default), "Spectrometre"
/// (the live FFT spectroscope — a single-frame reading), and "Spectrogramme" (the same FFT
/// capture plotted as a scrolling time/frequency waterfall) — the latter two share one opt-in
/// capture toggle (see `spectrometerContent`/`spectrographContent`'s own doc comments for why
/// leaving both tabs always stops the capture).
struct MicrophoneControlsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @State private var microphoneError: String?
    @State private var spectroscopeEnabled = false
    @State private var calibratingPhase: ImprovSession.MicrophoneCalibrationPhase?
    @State private var displayMode: DisplayMode = .notesReceived

    /// The scrolling waterfall's history buffer — accumulated by `spectrographContent`'s own
    /// `Timer` (started/stopped implicitly by that view's presence in the hierarchy, see its
    /// doc comment), capped at `spectrogramCapacity` columns so memory stays bounded regardless
    /// of how long this mode is left running.
    @State private var spectrogramHistory: [SpectrogramView.Column] = []
    private static let spectrogramCapacity = 240 // ~24s at the 100ms tick rate used below

    private enum DisplayMode: Hashable {
        /// Calibration rows + level meter — a peer tab now, not an always-visible block above
        /// the other three (per explicit user request).
        case calibration
        case notesReceived
        /// The existing single-frame live FFT view (French: "Spectrometre" — an instrument
        /// reading, not a recording of it over time).
        case spectrometer
        /// The new scrolling waterfall (French: "Spectrogramme" — the chart a spectrograph
        /// produces; renamed from the user's own tentative "spectrographe" to the more standard
        /// term for the resulting graph, not the instrument).
        case spectrograph
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
                    Picker(L10n.string(.appFieldAffichage, session.currentLanguage), selection: $displayMode) {
                        Label(L10n.string(.appLabelCalibrationCourt, session.currentLanguage), systemImage: "slider.horizontal.3").tag(DisplayMode.calibration)
                        Label(L10n.string(.appLabelNotesRecues, session.currentLanguage), systemImage: "pianokeys").tag(DisplayMode.notesReceived)
                        Label(L10n.string(.appLabelSpectrometre, session.currentLanguage), systemImage: "waveform").tag(DisplayMode.spectrometer)
                        Label(L10n.string(.appLabelSpectrogramme, session.currentLanguage), systemImage: "square.stack.3d.up").tag(DisplayMode.spectrograph)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: displayMode) { _, newValue in
                        guard newValue != .spectrometer, newValue != .spectrograph, spectroscopeEnabled else { return }
                        spectroscopeEnabled = false
                        session.setMicrophoneSpectrumCaptureEnabled(false)
                    }
                    // Shared between both spectrum-based modes — one underlying FFT capture
                    // pipeline (`session.setMicrophoneSpectrumCaptureEnabled`) feeds either
                    // visualization, so one toggle governs both rather than duplicating it.
                    if displayMode == .spectrometer || displayMode == .spectrograph {
                        Toggle(L10n.string(.appToggleActiverSpectrometre, session.currentLanguage), isOn: Binding(
                            get: { spectroscopeEnabled },
                            set: { newValue in
                                spectroscopeEnabled = newValue
                                session.setMicrophoneSpectrumCaptureEnabled(newValue)
                            }
                        ))
                    }
                    switch displayMode {
                    case .calibration:
                        calibrationContent(microphoneTrack)
                    case .notesReceived:
                        notesReceivedContent(microphoneTrack)
                    case .spectrometer:
                        spectrometerContent(microphoneTrack)
                    case .spectrograph:
                        spectrographContent(microphoneTrack)
                    }
                } footer: {
                    switch displayMode {
                    case .calibration:
                        Text(calibratingPhase == nil
                            ? L10n.string(.appHintCalibrationNiveau, session.currentLanguage)
                            : L10n.string(.appFormatEnCoursDeCapture, session.currentLanguage, L10n.string(.appButtonTerminerCapture, session.currentLanguage)))
                    case .spectrometer:
                        Text(L10n.string(.appHintSpectreFFT, session.currentLanguage))
                    case .spectrograph:
                        Text(L10n.string(.appHintSpectrogramme, session.currentLanguage))
                    case .notesReceived:
                        EmptyView()
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
    private func calibrationContent(_ track: WebConsoleTrackState) -> some View {
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
                CalibratedLevelMeterView(
                    rawLevel: track.microphoneLevel ?? 0,
                    quietRMS: session.microphoneCalibration.quietRMS,
                    loudRMS: session.microphoneCalibration.loudRMS
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)
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

    /// The spectroscope stays opt-in via the shared `Toggle` above (real per-window FFT-copy
    /// cost — see `MicrophonePitchListener.spectrumEnabled`'s doc comment) — but regardless of
    /// that toggle's own state, switching `displayMode` back to `.notesReceived` always stops
    /// capture too (the `onChange` in `body`): leaving both spectrum tabs is as good a reason to
    /// stop as flipping the toggle off, and forgetting to flip it off before navigating away
    /// shouldn't leave the extra FFT work running unseen.
    @ViewBuilder
    private func spectrometerContent(_ track: WebConsoleTrackState) -> some View {
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

    /// The waterfall equivalent of `spectrometerContent`. Unlike that single-frame view (which
    /// re-fetches and redraws fresh each `TimelineView` tick with no memory of earlier ticks),
    /// this one needs to ACCUMULATE snapshots across ticks — genuine `@State` mutation over
    /// time.
    ///
    /// **Real bug fixed here, not guessed**: the first version used a Combine
    /// `Timer.publish(...)` built INLINE inside this view's body and attached via `.onReceive`.
    /// `Timer.publish(...)` called inline is a fresh `Publisher` VALUE every single time this
    /// view's body is evaluated (which happens far more often than every 100ms — e.g. whenever
    /// `bridge.state` changes elsewhere in this same screen) — confirmed via a real screenshot
    /// showing the waterfall staying static/empty rather than scrolling. `.task` (no explicit
    /// `id:`) is keyed to this view's IDENTITY, not re-run on every body re-evaluation — it
    /// starts once when the view first appears and is cancelled once when it disappears, which
    /// is the actual "start/stop tied to being on this tab" guarantee this needed. The buffer
    /// itself lives on the parent view, so it's preserved (not reset) across a mode switch away
    /// and back.
    @ViewBuilder
    private func spectrographContent(_ track: WebConsoleTrackState) -> some View {
        if spectroscopeEnabled {
            SpectrogramView(
                history: spectrogramHistory,
                markedPitches: track.heldPitches,
                calibrationQuietMagnitude: session.microphoneCalibration.estimatedQuietPeakMagnitude,
                calibrationLoudMagnitude: session.microphoneCalibration.estimatedLoudPeakMagnitude
            )
            .frame(minHeight: 280)
            .task {
                while !Task.isCancelled {
                    if let snapshot = session.currentMicrophoneSpectrum() {
                        spectrogramHistory.append(.init(magnitudes: snapshot.magnitudes, binHz: snapshot.binHz))
                        if spectrogramHistory.count > Self.spectrogramCapacity {
                            spectrogramHistory.removeFirst(spectrogramHistory.count - Self.spectrogramCapacity)
                        }
                    }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
    }
}

#Preview {
    let session = ImprovSession()
    return MicrophoneControlsView(session: session, bridge: SessionUIBridge(session: session))
}
