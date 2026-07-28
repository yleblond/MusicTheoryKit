import SwiftUI
import AppCore
import JamShackUI
import Localization
import SoundFontModel

/// "Sons" sub-tab of the "JamShack" tab: curates `session.sampleFiles` (every .sf2/.dls/
/// .aupreset file found under "Sons (samples)", subfolders included — see
/// `ImprovSession.listSampleFiles`) into a small, named set worth actually picking from
/// elsewhere. Shows EVERY file/sound found, unlike `PiecesPlayView`/`GuideEditionView`/
/// `SceneLayoutView`'s sound pickers (which show only favorites, via
/// `session.favoriteSounds`) — this is the one screen where the full, possibly huge,
/// decompressed-library list needs to be visible at all, so favorites can be chosen from it in
/// the first place.
///
/// Two-column browser, not a flat list: a `.sf2` can bundle dozens of presets (a full General
/// MIDI bank), and a favorite/alias/test always applies to one SPECIFIC sound within a file,
/// never to the file as a whole — so the left column picks the FILE, the right column picks
/// (and curates) one of ITS sounds.
struct SoundsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge
    /// Whether this screen is genuinely the one visible right now — driven by `JamShackView`
    /// (its own `subTab == .sons`) combined with `ContentView`'s own active-tab check, NOT by
    /// `.onAppear`/`.onDisappear`: those are unreliable here, since `TabView` on macOS
    /// (`.sidebarAdaptable`) keeps every tab's content alive in the background rather than
    /// tearing it down on switch, so `.onDisappear` was never firing when leaving this screen
    /// for a DIFFERENT main tab (only when switching JamShack's own sub-tabs, which really does
    /// replace the view). Real bug this caused: test mode (and the tracks it pauses/resumes,
    /// including any scene's MIDI-sourced roles) stayed stuck active/paused indefinitely after
    /// leaving for another tab.
    let isActive: Bool

    @State private var fileSearchText = ""
    @State private var actionError: String?

    // MARK: - File/sound navigation
    @State private var selectedFilePath: String?
    @State private var soundRows: [SoundRow] = []
    @State private var soundSearchText = ""
    /// Identifies the row currently being alias-edited as `"<path>|<row.id>"` (not just
    /// `row.id`) so switching files can never collide with a same-shaped id in the new file's
    /// own row list (e.g. two different single-preset files both use `row.id == "_default"`).
    @State private var editingAliasFor: String?
    @State private var aliasDraft = ""

    // MARK: - Sound test mode
    @State private var isTestModeOn = false
    @State private var testSourceID: TrackID?
    /// Whether `testSourceID` was already listening BEFORE test mode picked it — so leaving
    /// test mode restores it to that same state instead of unconditionally stopping it (it
    /// might be the computer keyboard's always-on startup track, for instance).
    @State private var testSourceWasAlreadyListening = false
    /// Every other track that WAS listening when a test source was chosen — paused for the
    /// duration of the test (the user's explicit ask: avoid double-detection confusion from
    /// several tracks reacting to the same notes at once) and restarted once test mode ends
    /// or the source changes.
    @State private var pausedTrackIDs: Set<TrackID> = []
    /// The test source's own instrument, exactly as it was BEFORE testing touched it — restored
    /// on every source switch/test-mode exit so browsing sounds here can never permanently
    /// override what the active scene actually defines for that track (the user's own reported
    /// bug: a sound tried here stuck around after leaving this screen). `nil` name means no
    /// instrument was loaded at all, restored as "muted" (`testSourceOriginalSoundEnabled`)
    /// rather than left on whatever was last tested.
    @State private var testSourceOriginalInstrumentName: String?
    @State private var testSourceOriginalInstrumentPreset: SoundFontPresetIdentity?
    @State private var testSourceOriginalSoundEnabled = false
    /// Whether `ImprovSession.computerKeyboardInputEnabled` was already on before this screen
    /// turned test mode on (see `setTestMode`) — so leaving restores it to that same state
    /// instead of unconditionally turning it back off.
    @State private var computerKeyboardWasEnabledBeforeTestMode = false

    /// One row in the right-hand "sounds of the selected file" column — either a real preset
    /// read from a multi-preset `.sf2` (see `SoundFontPresetReader`), or the single stand-in
    /// row used for a `.dls`/`.aupreset` (no preset enumeration possible) and for a `.sf2` the
    /// reader couldn't parse (`preset == nil` either way means "this file's own default sound").
    private struct SoundRow: Identifiable {
        let preset: SoundFontPresetIdentity?
        let originalName: String
        var id: String {
            guard let preset else { return "_default" }
            return "\(preset.program):\(preset.bank)"
        }
    }

    /// Local, sound-capable tracks only — the same "clavier ordinateur / MIDI" choices the
    /// rest of the app already exposes as live-input sources. Excludes `.microphone` (can
    /// never have sound, feedback risk — see `TrackInfo.canHaveSound`'s doc comment) and
    /// `.webKeyboard`/`.remote` (not something to attach a local sample to for a quick test).
    private var testableSources: [TrackInfo] {
        session.tracks.filter { track in
            switch track.id {
            case .computerKeyboard, .midiMerged, .midiSource: return true
            default: return false
            }
        }
    }

    private var testTrackState: WebConsoleTrackState? {
        guard let wireID = testSourceID?.wireIDText else { return nil }
        return bridge.state.tracks.first { $0.id == wireID }
    }

    /// The test source's own track — read directly rather than cached separately, so
    /// `currentlyTestedPath`/`currentlyTestedPreset` can never drift from what's actually
    /// loaded (both `instrumentName`/`instrumentPreset` are only ever set by `setInstrument`).
    private var testTrack: TrackInfo? {
        guard let testSourceID else { return nil }
        return session.tracks.first { $0.id == testSourceID }
    }

    private var currentlyTestedPath: String? { testTrack?.instrumentName }
    private var currentlyTestedPreset: SoundFontPresetIdentity? { testTrack?.instrumentPreset }

    private var filteredFiles: [String] {
        guard !fileSearchText.isEmpty else { return session.sampleFiles }
        return session.sampleFiles.filter { $0.localizedCaseInsensitiveContains(fileSearchText) }
    }

    private var filteredSoundRows: [SoundRow] {
        guard !soundSearchText.isEmpty, let selectedFilePath else { return soundRows }
        return soundRows.filter { row in
            row.originalName.localizedCaseInsensitiveContains(soundSearchText)
                || (session.soundAlias(forPath: selectedFilePath, preset: row.preset)?
                    .localizedCaseInsensitiveContains(soundSearchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption).padding(.horizontal).padding(.top, 8)
            }
            // Left: pick a file. Middle: curate/test one of ITS sounds. Right: the test-mode
            // controls (source picker, keyboard, chord/mode commentary) — same "Form / Divider
            // / Form" split `SceneLayoutView` already uses for its instruments/roles columns,
            // extended to a third column here.
            HStack(alignment: .top, spacing: 0) {
                Form { filesColumnContent }
                Divider()
                Form { soundsColumnContent }
                Divider()
                Form { testModeSection }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
        // Test mode itself is now purely manual (the `Toggle` in `testModeSection`) — it no
        // longer turns ON just because this screen becomes visible (real bug reported: made the
        // screen's own arrival/departure feel like it was silently reaching into the active
        // scene's track state). Leaving is still handled here, not `.onAppear`/`.onDisappear`
        // (see `isActive`'s own doc comment for why those are unreliable): forcing test mode off
        // when the screen stops being active is what guarantees every paused track/instrument
        // this screen borrowed gets restored, even if the user navigates away without manually
        // switching the toggle off first.
        .onChange(of: isActive) { _, active in
            guard !active else { return }
            setTestMode(false)
        }
    }

    // MARK: - Files column

    @ViewBuilder
    private var filesColumnContent: some View {
        if session.sampleFiles.isEmpty {
            Section {
                Text(L10n.string(.appPlaceholderAucunSonTrouve, session.currentLanguage, L10n.string(.appLabelDossierSons, session.currentLanguage)))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.string(.appHeadingFichiersSoundfont, session.currentLanguage))
            }
        } else {
            Section {
                TextField(L10n.string(.appPlaceholderRechercherFichier, session.currentLanguage), text: $fileSearchText)
            } header: {
                Text(L10n.string(.appHeadingFichiersSoundfont, session.currentLanguage))
            }
            Section {
                ForEach(filteredFiles, id: \.self) { path in
                    fileRow(path)
                }
            } header: {
                Text(L10n.string(.appFormatFichiersCompte, session.currentLanguage, filteredFiles.count, session.sampleFiles.count))
            }
        }
    }

    @ViewBuilder
    private func fileRow(_ path: String) -> some View {
        Button {
            selectFile(path)
        } label: {
            HStack {
                Text(path)
                    .foregroundStyle(selectedFilePath == path ? Color.accentColor : .primary)
                Spacer()
                if path == currentlyTestedPath {
                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.blue)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func selectFile(_ path: String) {
        guard selectedFilePath != path else { return }
        selectedFilePath = path
        soundSearchText = ""
        editingAliasFor = nil
        aliasDraft = ""
        loadSoundRows(for: path)
    }

    /// `.sf2` is the only format `SoundFontPresetReader` can enumerate presets from — a
    /// `.dls`/`.aupreset`, or a `.sf2` it fails to parse, falls back to one stand-in row
    /// (`preset == nil`) representing that file's own single default sound, same as before
    /// multi-preset support existed.
    private func loadSoundRows(for path: String) {
        guard path.lowercased().hasSuffix(".sf2") else {
            soundRows = [SoundRow(preset: nil, originalName: displayFileName(path))]
            return
        }
        do {
            let presets = try session.soundFontPresets(forPath: path)
            soundRows = presets.isEmpty
                ? [SoundRow(preset: nil, originalName: displayFileName(path))]
                : presets.map { SoundRow(preset: $0.identity, originalName: $0.name) }
        } catch {
            actionError = "\(error)"
            soundRows = [SoundRow(preset: nil, originalName: displayFileName(path))]
        }
    }

    private func displayFileName(_ path: String) -> String {
        (path as NSString).lastPathComponent
    }

    // MARK: - Sounds column (the selected file's own sounds)

    @ViewBuilder
    private var soundsColumnContent: some View {
        if let selectedFilePath {
            Section {
                TextField(L10n.string(.appPlaceholderRechercherSonAlias, session.currentLanguage), text: $soundSearchText)
            } header: {
                Text(displayFileName(selectedFilePath))
            }
            Section {
                ForEach(filteredSoundRows) { row in
                    soundRow(selectedFilePath, row)
                }
            } header: {
                Text(L10n.string(.appFormatSonsCompte, session.currentLanguage, filteredSoundRows.count, soundRows.count))
            } footer: {
                Text(L10n.string(.appHintCocheEtoileFavoris, session.currentLanguage))
            }
        } else {
            Section {
                Text(L10n.string(.appPlaceholderChoisirFichierSons, session.currentLanguage)).foregroundStyle(.secondary)
            } header: {
                Text(L10n.string(.fieldSon, session.currentLanguage))
            }
        }
    }

    @ViewBuilder
    private func soundRow(_ path: String, _ row: SoundRow) -> some View {
        let editKey = "\(path)|\(row.id)"
        HStack {
            Button {
                toggleFavorite(path, row.preset)
            } label: {
                Image(systemName: session.isSoundFavorite(path, preset: row.preset) ? "star.fill" : "star")
                    .foregroundStyle(session.isSoundFavorite(path, preset: row.preset) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                if editingAliasFor == editKey {
                    TextField(L10n.string(.appFieldAlias, session.currentLanguage), text: $aliasDraft, onCommit: { commitAlias(path, row.preset, editKey) })
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                } else {
                    let alias = session.soundAlias(forPath: path, preset: row.preset)
                    Text(alias ?? row.originalName)
                    if alias != nil {
                        Text(row.originalName).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isTestModeOn, let testSourceID {
                let isCurrent = path == currentlyTestedPath && row.preset == currentlyTestedPreset
                Button {
                    testSound(path: path, preset: row.preset, testSourceID: testSourceID)
                } label: {
                    Image(systemName: isCurrent ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .foregroundStyle(isCurrent ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
            }

            Button {
                if editingAliasFor == editKey {
                    commitAlias(path, row.preset, editKey)
                } else {
                    aliasDraft = session.soundAlias(forPath: path, preset: row.preset) ?? ""
                    editingAliasFor = editKey
                }
            } label: {
                Image(systemName: editingAliasFor == editKey ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleFavorite(_ path: String, _ preset: SoundFontPresetIdentity?) {
        do {
            try session.setSoundFavorite(path, preset: preset, isFavorite: !session.isSoundFavorite(path, preset: preset))
        } catch {
            actionError = "\(error)"
        }
    }

    private func commitAlias(_ path: String, _ preset: SoundFontPresetIdentity?, _ editKey: String) {
        do {
            try session.setSoundAlias(path, preset: preset, alias: aliasDraft)
        } catch {
            actionError = "\(error)"
        }
        if editingAliasFor == editKey {
            editingAliasFor = nil
        }
        aliasDraft = ""
    }

    private func testSound(path: String, preset: SoundFontPresetIdentity?, testSourceID: TrackID) {
        do {
            try session.setInstrument(named: path, for: testSourceID, preset: preset)
        } catch {
            actionError = "\(error)"
        }
    }

    // MARK: - Test mode column

    @ViewBuilder
    private var testModeSection: some View {
        Section {
            Toggle(L10n.string(.appToggleModeTestSon, session.currentLanguage), isOn: Binding(
                get: { isTestModeOn },
                set: { setTestMode($0) }
            ))
            if isTestModeOn {
                Picker(L10n.string(.appFieldSourceTest, session.currentLanguage), selection: Binding(
                    get: { testSourceID },
                    set: { applyTestSource($0) }
                )) {
                    Text(L10n.string(.appOptionAucuneFem, session.currentLanguage)).tag(TrackID?.none)
                    ForEach(testableSources) { track in
                        Text(session.labelWithChannel(track)).tag(TrackID?.some(track.id))
                    }
                }
                if let track = testTrackState {
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
                } else {
                    Text(L10n.string(.appPlaceholderChoisirSourceTest, session.currentLanguage))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } header: {
            Text(L10n.string(.appHeadingTesterLeSon, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintTesterLeSon, session.currentLanguage))
        }
    }

    /// Idempotent (a repeated call with the same value is a no-op) — `.onAppear`/`.onDisappear`
    /// both call this unconditionally, so neither has to track whether the other already ran.
    private func setTestMode(_ enabled: Bool) {
        guard enabled != isTestModeOn else { return }
        isTestModeOn = enabled
        if enabled {
            computerKeyboardWasEnabledBeforeTestMode = session.computerKeyboardInputEnabled
            if !session.computerKeyboardInputEnabled {
                session.setComputerKeyboardInputEnabled(true)
            }
            // Computer keyboard as the default test source, per explicit user request — it's
            // also what makes the persistent keyboard bar appear (see `ContentView`).
            applyTestSource(.computerKeyboard)
        } else {
            applyTestSource(nil)
            if !computerKeyboardWasEnabledBeforeTestMode {
                session.setComputerKeyboardInputEnabled(false)
            }
        }
    }

    /// The one place `testSourceID` ever changes: restores the PREVIOUS source's own original
    /// sound (see `testSourceOriginalInstrumentName`'s doc comment) and whatever else was
    /// listening, then — if a new source was picked — snapshots ITS current sound so it can
    /// be restored the same way later, pauses every other currently-listening track, and
    /// starts/enables the new one. Symmetric handling of `nil` (test mode's own "Aucune" choice,
    /// and turning test mode off) is what makes leaving the sound list exactly as it was found
    /// always safe, not just on the common "toggle off" path.
    private func applyTestSource(_ newSource: TrackID?) {
        if let previous = testSourceID {
            if !testSourceWasAlreadyListening {
                session.stopTrack(previous)
            }
            if let testSourceOriginalInstrumentName {
                try? session.setInstrument(named: testSourceOriginalInstrumentName, for: previous, preset: testSourceOriginalInstrumentPreset)
            }
            try? session.setSoundEnabled(testSourceOriginalSoundEnabled, for: previous)
        }
        for id in pausedTrackIDs {
            do {
                try session.startTrack(id)
            } catch {
                actionError = "\(error)"
            }
        }
        pausedTrackIDs = []
        testSourceWasAlreadyListening = false
        testSourceID = newSource
        // The Picker used to reach `newSource` is a native pop-up control that otherwise keeps
        // SwiftUI keyboard focus for the rest of the session — see
        // `ImprovSession.requestComputerKeyboardFocus`'s own doc comment.
        session.requestComputerKeyboardFocus()

        guard let newSource else {
            testSourceOriginalInstrumentName = nil
            testSourceOriginalInstrumentPreset = nil
            testSourceOriginalSoundEnabled = false
            return
        }
        let newTrack = session.tracks.first { $0.id == newSource }
        testSourceOriginalInstrumentName = newTrack?.instrumentName
        testSourceOriginalInstrumentPreset = newTrack?.instrumentPreset
        testSourceOriginalSoundEnabled = newTrack?.soundEnabled ?? false
        testSourceWasAlreadyListening = newTrack?.isListening ?? false
        pausedTrackIDs = Set(session.tracks.filter { $0.isListening && $0.id != newSource }.map(\.id))
        for id in pausedTrackIDs {
            session.stopTrack(id)
        }
        do {
            try session.startTrack(newSource)
            try session.setSoundEnabled(true, for: newSource)
        } catch {
            actionError = "\(error)"
        }
    }
}

#Preview {
    let session = ImprovSession()
    return SoundsView(session: session, bridge: SessionUIBridge(session: session), isActive: true)
}
