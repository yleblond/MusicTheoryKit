import SwiftUI
import AppCore
import JamShackUI
import Localization

/// Start/stop the microphone track — used as the "Microphone" sub-tab of the "JamShack" tab.
/// A plain `View`, not a `Form`/`Section` itself, so it composes cleanly inside another Form.
/// Start/stop lives in its own always-visible block; everything else is a segmented choice
/// between "Calibration" (calibration rows + level meter), "Notes recues" (the live keyboard +
/// chord/mode text + the recognition-mode picker, default), "Spectrometre" (the live FFT
/// spectroscope — a single-frame reading), and "Spectrogramme" (the same FFT capture plotted as
/// a scrolling time/frequency waterfall) — the latter two share one opt-in capture toggle (see
/// `spectrometerContent`/`spectrographContent`'s own doc comments for why leaving both tabs
/// always stops the capture).
struct MicrophoneControlsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    /// `true` when this instance IS the detached window's own content (see `MicrophoneWindow`)
    /// — swaps the button below from "Ouvrir dans une fenetre" (`openWindow`) to "Reintegrer"
    /// (`dismissWindow`).
    var isDetachedWindow: Bool = false

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

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
    /// The current frame's peak spectrum magnitude — kept alongside the history buffer so
    /// `SpectrogramColorScaleView`'s live indicator has something to point at without re-fetching
    /// a snapshot outside the polling loop that already owns that cadence.
    @State private var spectrogramCurrentPeakMagnitude: Float?
    /// Shared by both the spectrometre and spectrogramme graphs so they read as a matched pair
    /// (per explicit user request) — 280 * 1.3, also per explicit user request ("agrandir de
    /// 30% en hauteur").
    private static let spectrumGraphHeight: CGFloat = 364

    /// Backed by `session.spectrogramSettings` (persisted, shared with the "Couleurs" sub-tab)
    /// rather than local `@State` — a previous version kept these as plain `@State`, lost every
    /// time this view was recreated (e.g. switching sub-tabs and back).
    private var spectrogramShowNotes: Binding<Bool> {
        Binding(
            get: { session.spectrogramSettings.showNoteOverlay },
            set: { try? session.setSpectrogramShowNoteOverlay($0) }
        )
    }
    private var spectrogramPalette: Binding<SpectrogramPalette> {
        Binding(
            get: { SpectrogramPalette(rawValue: session.spectrogramSettings.palette) ?? .thermal },
            set: { try? session.setSpectrogramPalette($0.rawValue) }
        )
    }

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
                #if os(macOS) || os(visionOS)
                if isDetachedWindow {
                    Button {
                        dismissWindow(id: AuxiliaryWindowID.microphone.rawValue)
                    } label: {
                        Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
                    }
                } else {
                    Button {
                        openWindow(id: AuxiliaryWindowID.microphone.rawValue)
                    } label: {
                        Label(L10n.string(.appButtonOuvrirDansUneFenetre, session.currentLanguage), systemImage: "rectangle.on.rectangle")
                    }
                }
                #endif
            } header: {
                Text(L10n.string(.appHeadingMicrophone, session.currentLanguage))
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
                    case .notesReceived:
                        Text(L10n.string(.appHintDetectionMicrophone, session.currentLanguage))
                    case .spectrometer:
                        Text(L10n.string(.appHintSpectreFFT, session.currentLanguage))
                    case .spectrograph:
                        Text(L10n.string(.appHintSpectrogramme, session.currentLanguage))
                    }
                }
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        // Only ever stopped by `onChange(of: displayMode)` before this (see that handler's own
        // doc comment) — nothing stopped it if the whole screen disappeared instead (e.g. this
        // window closing, once detachable — see `MicrophoneWindow`), silently leaving FFT
        // capture running. Safe unconditionally: only one instance of this view is ever visible
        // at a time (main tab XOR detached window, true detach — see `ContentView`), so there's
        // no other instance's capture request to stomp.
        .onDisappear {
            if spectroscopeEnabled {
                spectroscopeEnabled = false
                session.setMicrophoneSpectrumCaptureEnabled(false)
            }
        }
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
                // Same height as the spectrogramme, per explicit user request — the two are
                // views of the same underlying capture and read as a pair.
                .frame(minHeight: Self.spectrumGraphHeight)
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
            Toggle(L10n.string(.appToggleAfficherNotesSpectrogramme, session.currentLanguage), isOn: spectrogramShowNotes)
            Picker(L10n.string(.appFieldPaletteSpectrogramme, session.currentLanguage), selection: spectrogramPalette) {
                Text(L10n.string(.appPaletteThermique, session.currentLanguage)).tag(SpectrogramPalette.thermal)
                Text(L10n.string(.appPaletteBleu, session.currentLanguage)).tag(SpectrogramPalette.blue)
                Text(L10n.string(.appPaletteNiveauxDeGris, session.currentLanguage)).tag(SpectrogramPalette.grayscale)
            }
            HStack(alignment: .top, spacing: 4) {
                SpectrogramView(
                    history: spectrogramHistory,
                    totalColumns: Self.spectrogramCapacity,
                    markedPitches: track.heldPitches,
                    calibrationQuietMagnitude: session.microphoneCalibration.estimatedQuietPeakMagnitude,
                    calibrationLoudMagnitude: session.microphoneCalibration.estimatedLoudPeakMagnitude,
                    showNoteOverlay: spectrogramShowNotes.wrappedValue,
                    palette: spectrogramPalette.wrappedValue
                )
                SpectrogramColorScaleView(
                    currentPeakMagnitude: spectrogramCurrentPeakMagnitude,
                    calibrationQuietMagnitude: session.microphoneCalibration.estimatedQuietPeakMagnitude,
                    calibrationLoudMagnitude: session.microphoneCalibration.estimatedLoudPeakMagnitude,
                    palette: spectrogramPalette.wrappedValue
                )
            }
            .frame(minHeight: Self.spectrumGraphHeight)
            .task {
                while !Task.isCancelled {
                    if let snapshot = session.currentMicrophoneSpectrum() {
                        // Read held pitches FRESH from the bridge here, not from the `track`
                        // parameter — that parameter is only re-evaluated when this view's
                        // PARENT re-renders (roughly every ~250ms via `bridge.state`'s own
                        // polling), but this loop is a single long-lived task that keeps running
                        // between those re-renders, so it would otherwise capture one stale
                        // snapshot of held pitches for its whole lifetime.
                        let heldPitches = bridge.state.tracks.first { $0.id == "micro" }?.heldPitches ?? []
                        spectrogramHistory.append(.init(magnitudes: snapshot.magnitudes, binHz: snapshot.binHz, heldPitches: heldPitches))
                        if spectrogramHistory.count > Self.spectrogramCapacity {
                            spectrogramHistory.removeFirst(spectrogramHistory.count - Self.spectrogramCapacity)
                        }
                        spectrogramCurrentPeakMagnitude = snapshot.magnitudes.max()
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
