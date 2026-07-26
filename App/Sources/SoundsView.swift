import SwiftUI
import AppCore
import JamShackUI
import Localization

/// "Sons" sub-tab of the "JamShack" tab: curates `session.sampleFiles` (every .sf2/.dls/
/// .aupreset file found under "Sons (samples)", subfolders included — see
/// `ImprovSession.listSampleFiles`) into a small, named set worth actually picking from
/// elsewhere. Shows EVERY sound found, unlike `PiecesPlayView`/`RecordingPlayView`/
/// `SceneLayoutView`'s sound pickers (which show only favorites, via
/// `session.favoriteSampleFiles`) — this is the one screen where the full, possibly huge,
/// decompressed-library list needs to be visible at all, so favorites can be chosen from it in
/// the first place.
struct SoundsView: View {
    let session: ImprovSession
    let bridge: SessionUIBridge

    @State private var searchText = ""
    @State private var actionError: String?
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

    /// The sample path currently loaded onto the test source, if any — read straight from the
    /// live track's own `instrumentName` (set by `setInstrument`) rather than a separately
    /// tracked flag, so it can never drift out of sync with what's actually loaded. Drives the
    /// blue "currently testing this one" marker on that sound's row.
    private var currentlyTestedPath: String? {
        guard let testSourceID else { return nil }
        return session.tracks.first { $0.id == testSourceID }?.instrumentName
    }

    private var filteredSounds: [String] {
        guard !searchText.isEmpty else { return session.sampleFiles }
        return session.sampleFiles.filter { path in
            path.localizedCaseInsensitiveContains(searchText)
                || (session.soundAlias(forPath: path)?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption).padding(.horizontal).padding(.top, 8)
            }
            // Left: search + the sound list itself. Right: the test-mode controls (source
            // picker, keyboard, chord/mode commentary) — same side-by-side "Form / Divider /
            // Form" split `SceneLayoutView` already uses for its instruments/roles columns.
            HStack(alignment: .top, spacing: 0) {
                Form { soundListContent }
                Divider()
                Form { testModeSection }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
        }
        .onDisappear {
            if isTestModeOn { setTestMode(false) }
        }
    }

    @ViewBuilder
    private var soundListContent: some View {
        if session.sampleFiles.isEmpty {
            Section {
                Text(L10n.string(.appPlaceholderAucunSonTrouve, session.currentLanguage, L10n.string(.appLabelDossierSons, session.currentLanguage)))
                    .foregroundStyle(.secondary)
            } header: {
                Text(L10n.string(.appTabSons, session.currentLanguage))
            }
        } else {
            Section {
                TextField(L10n.string(.appPlaceholderRechercherSonAlias, session.currentLanguage), text: $searchText)
            } header: {
                Text(L10n.string(.appTabSons, session.currentLanguage))
            }
            Section {
                ForEach(filteredSounds, id: \.self) { path in
                    soundRow(path)
                }
            } header: {
                Text(L10n.string(.appFormatSonsCompte, session.currentLanguage, filteredSounds.count, session.sampleFiles.count))
            } footer: {
                Text(L10n.string(.appHintCocheEtoileFavoris, session.currentLanguage))
            }
        }
    }

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
                        Text(track.label).tag(TrackID?.some(track.id))
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

    private func setTestMode(_ enabled: Bool) {
        isTestModeOn = enabled
        if !enabled {
            applyTestSource(nil)
        }
    }

    /// The one place `testSourceID` ever changes: restores whatever the PREVIOUS source/other
    /// tracks were doing, then — if a new source was picked — pauses every other currently-
    /// listening track and starts/enables the new one. Symmetric handling of `nil` (test
    /// mode's own "Aucune" choice, and turning test mode off) is what makes leaving the sound
    /// list exactly as it was found always safe, not just on the common "toggle off" path.
    private func applyTestSource(_ newSource: TrackID?) {
        if let previous = testSourceID, !testSourceWasAlreadyListening {
            session.stopTrack(previous)
        }
        for id in pausedTrackIDs {
            try? session.startTrack(id)
        }
        pausedTrackIDs = []
        testSourceWasAlreadyListening = false
        testSourceID = newSource

        guard let newSource else { return }
        testSourceWasAlreadyListening = session.tracks.first { $0.id == newSource }?.isListening ?? false
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

    @ViewBuilder
    private func soundRow(_ path: String) -> some View {
        HStack {
            Button {
                toggleFavorite(path)
            } label: {
                Image(systemName: session.isSoundFavorite(path) ? "star.fill" : "star")
                    .foregroundStyle(session.isSoundFavorite(path) ? .yellow : .secondary)
            }
            .buttonStyle(.borderless)

            VStack(alignment: .leading, spacing: 2) {
                if editingAliasFor == path {
                    TextField(L10n.string(.appFieldAlias, session.currentLanguage), text: $aliasDraft, onCommit: { commitAlias(path) })
                        #if os(macOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                } else {
                    Text(session.soundAlias(forPath: path) ?? path)
                    if session.soundAlias(forPath: path) != nil {
                        Text(path).font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }

            Spacer()

            if isTestModeOn, let testSourceID {
                Button {
                    do {
                        try session.setInstrument(named: path, for: testSourceID)
                    } catch {
                        actionError = "\(error)"
                    }
                } label: {
                    Image(systemName: path == currentlyTestedPath ? "speaker.wave.2.fill" : "speaker.wave.2")
                        .foregroundStyle(path == currentlyTestedPath ? .blue : .secondary)
                }
                .buttonStyle(.borderless)
            }

            Button {
                if editingAliasFor == path {
                    commitAlias(path)
                } else {
                    aliasDraft = session.soundAlias(forPath: path) ?? ""
                    editingAliasFor = path
                }
            } label: {
                Image(systemName: editingAliasFor == path ? "checkmark.circle" : "pencil")
            }
            .buttonStyle(.borderless)
        }
    }

    private func toggleFavorite(_ path: String) {
        do {
            try session.setSoundFavorite(path, isFavorite: !session.isSoundFavorite(path))
        } catch {
            actionError = "\(error)"
        }
    }

    private func commitAlias(_ path: String) {
        do {
            try session.setSoundAlias(path, alias: aliasDraft)
        } catch {
            actionError = "\(error)"
        }
        editingAliasFor = nil
        aliasDraft = ""
    }
}

#Preview {
    let session = ImprovSession()
    return SoundsView(session: session, bridge: SessionUIBridge(session: session))
}
