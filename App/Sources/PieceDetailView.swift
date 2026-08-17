import SwiftUI
import AppCore
import JamShackUI
import ScoreImport
import PieceModel
import SoundFontModel
import RecognitionEngine
import Localization

/// Screen 2 of the Morceaux tab ("Détail") — replaces the old `PiecesPlayView`/`ScoreScreenView`
/// pair with one tabbed screen: name + play/stop button, then "Infos" (file metadata + per-track
/// sound assignment) and "Play" (notation with live highlighting of whatever's currently
/// sounding). Detachable into its own window on macOS/visionOS, same pattern as the Théorie tabs
/// (`TonnetzLibraryView`'s own `detachButton` mirrored below).
struct PieceDetailView: View {
    let session: ImprovSession
    let onBackToCatalog: () -> Void
    var isDetachedWindow = false

    private enum DetailTab { case infos, play, analyse }

    @State private var actionError: String?
    @State private var selectedTab: DetailTab = .infos
    /// `session.loadSample` does real disk I/O (and, for a sample under an iCloud-synced
    /// folder not yet downloaded locally, a real network wait) — must not run on the main
    /// thread. Also the currently-loading sound's id, so only that one row shows a spinner.
    @State private var loadingSoundID: String?

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    var body: some View {
        VStack(spacing: 0) {
            header
            if let actionError {
                Text(actionError).foregroundStyle(.red).font(.caption).padding(.horizontal)
            }
            tabBar
            Divider()
            Group {
                switch selectedTab {
                case .infos: infosTab
                case .play: playTab
                case .analyse: analyseTab
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// A plain, deterministic horizontal switcher — NOT `TabView` + `.tabViewStyle(.sidebarAdaptable)`
    /// (tried first, matching `ContentView`'s own top-level tab sets): unlike there, this view is
    /// nested inside the Morceaux catalog→detail flow rather than being the window's own top-level
    /// content, and in that narrower/nested context `.sidebarAdaptable` rendered as an actual
    /// vertical sidebar with a wide unexplained gap before the tab content — not the horizontal
    /// pills it reliably gives `ContentView`. A manually-drawn row of buttons has no such
    /// adaptive, context-dependent behavior to fight.
    private var tabBar: some View {
        HStack(spacing: 4) {
            tabBarButton(.infos, label: L10n.string(.appTabInfos, session.currentLanguage), systemImage: "info.circle")
            tabBarButton(.play, label: L10n.string(.appHeadingJouer, session.currentLanguage), systemImage: "play.circle")
            tabBarButton(.analyse, label: L10n.string(.appTabAnalyse, session.currentLanguage), systemImage: "function")
            Spacer()
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    private func tabBarButton(_ tab: DetailTab, label: String, systemImage: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Label(label, systemImage: systemImage)
                .font(.subheadline.weight(selectedTab == tab ? .semibold : .regular))
                .padding(.vertical, 6)
                .padding(.horizontal, 12)
                .background(selectedTab == tab ? Color.accentColor.opacity(0.15) : Color.clear)
                .foregroundStyle(selectedTab == tab ? Color.accentColor : Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var header: some View {
        HStack {
            // No "back to catalog" in the detached window — it's a standalone window, not part
            // of the catalog→detail flow; "réintégrer" (below) is its way back.
            if !isDetachedWindow {
                Button {
                    onBackToCatalog()
                } label: {
                    Image(systemName: "chevron.left")
                }
                .accessibilityLabel(L10n.string(.appHeadingDossierMorceaux, session.currentLanguage))
            }
            if let piece = session.piece {
                Text(piece.title).font(.headline)
            }
            Spacer()
            if session.piece != nil {
                PlaybackControlButton(
                    isPlaying: session.isPlaying,
                    language: session.currentLanguage,
                    onPlay: {
                        do {
                            try session.play()
                        } catch {
                            actionError = "\(error)"
                        }
                    },
                    onStop: { session.stopPlayback() }
                )
            }
            #if os(macOS) || os(visionOS)
            detachButton
            #endif
        }
        .padding([.horizontal, .top])
    }

    #if os(macOS) || os(visionOS)
    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: AuxiliaryWindowID.compositionPieceDetail.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: AuxiliaryWindowID.compositionPieceDetail.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif

    // MARK: - Infos tab

    @ViewBuilder
    private var infosTab: some View {
        Form {
            if let piece = session.piece {
                Section {
                    if let composer = piece.composer, !composer.isEmpty {
                        Text(composer).font(.subheadline).foregroundStyle(.secondary)
                    }
                    Text(L10n.string(.appFormatFragmentsBPM, session.currentLanguage, "\(piece.fragments.count)", String(format: "%.0f", piece.tempoBPM)))
                        .font(.caption).foregroundStyle(.secondary)
                }
                ForEach(Array(piece.sections.enumerated()), id: \.offset) { sectionIndex, section in
                    Section {
                        ForEach(Array(section.tracks.enumerated()), id: \.offset) { trackIndex, track in
                            trackSoundRow(sectionIndex: sectionIndex, trackIndex: trackIndex, track: track)
                        }
                        chordSoundRow(sectionIndex: sectionIndex, section: section)
                    } header: {
                        Text(piece.sections.count > 1 ? section.name : L10n.string(.appHeadingPisteMIDI, session.currentLanguage))
                    }
                }
                playbackObservationSection(piece: piece)
                defaultSoundSection
            } else {
                Text(L10n.string(.appPlaceholderAucunMorceauChargeOnglet, session.currentLanguage)).foregroundStyle(.secondary)
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }

    @ViewBuilder
    private func trackSoundRow(sectionIndex: Int, trackIndex: Int, track: Track) -> some View {
        HStack {
            Text(track.name)
            Spacer()
            Menu(currentSoundLabel(instrument: track.instrument, preset: track.instrumentPreset)) {
                Button(L10n.string(.appButtonAucun, session.currentLanguage)) {
                    trySetTrackInstrument(sectionIndex: sectionIndex, trackIndex: trackIndex, sound: nil)
                }
                ForEach(session.favoriteSounds) { sound in
                    Button {
                        trySetTrackInstrument(sectionIndex: sectionIndex, trackIndex: trackIndex, sound: sound)
                    } label: {
                        Label(sound.displayName, systemImage: sound.iconSystemName ?? "music.note")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func chordSoundRow(sectionIndex: Int, section: PieceModel.Section) -> some View {
        HStack {
            Text(L10n.string(.appHeadingAccordsSection, session.currentLanguage))
            Spacer()
            Menu(currentSoundLabel(instrument: section.chordInstrument, preset: section.chordInstrumentPreset)) {
                Button(L10n.string(.appButtonAucun, session.currentLanguage)) {
                    trySetChordInstrument(sectionIndex: sectionIndex, sound: nil)
                }
                ForEach(session.favoriteSounds) { sound in
                    Button {
                        trySetChordInstrument(sectionIndex: sectionIndex, sound: sound)
                    } label: {
                        Label(sound.displayName, systemImage: sound.iconSystemName ?? "music.note")
                    }
                }
            }
        }
    }

    private func currentSoundLabel(instrument: String?, preset: SoundFontPresetIdentity?) -> String {
        guard let instrument, !instrument.isEmpty else { return L10n.string(.appButtonAucun, session.currentLanguage) }
        return session.displayName(forSamplePath: instrument, preset: preset)
    }

    private func trySetTrackInstrument(sectionIndex: Int, trackIndex: Int, sound: ImprovSession.FavoriteSound?) {
        do {
            try session.setPieceTrackInstrument(sectionIndex: sectionIndex, trackIndex: trackIndex, instrumentName: sound?.path, preset: sound?.preset)
        } catch {
            actionError = "\(error)"
        }
    }

    private func trySetChordInstrument(sectionIndex: Int, sound: ImprovSession.FavoriteSound?) {
        do {
            try session.setPieceChordInstrument(sectionIndex: sectionIndex, instrumentName: sound?.path, preset: sound?.preset)
        } catch {
            actionError = "\(error)"
        }
    }

    /// The fallback sound for any track/chord progression left at "Aucun" above — unchanged from
    /// the old `PiecesPlayView.soundSection`, just relocated here.
    @ViewBuilder
    private var defaultSoundSection: some View {
        Section {
            if session.favoriteSounds.isEmpty {
                Text(L10n.string(.appPlaceholderAucunSonFavori, session.currentLanguage)).font(.caption).foregroundStyle(.secondary)
            } else {
                ForEach(session.favoriteSounds) { sound in
                    if loadingSoundID == sound.id {
                        HStack { Label(sound.displayName, systemImage: sound.iconSystemName ?? "music.note"); Spacer(); ProgressView().controlSize(.small) }
                    } else {
                        Button {
                            loadDefaultSample(sound)
                        } label: {
                            Label(sound.displayName, systemImage: sound.iconSystemName ?? "music.note")
                        }
                        .disabled(loadingSoundID != nil)
                    }
                }
            }
        } header: {
            Text(L10n.string(.appHeadingSonDeLecture, session.currentLanguage))
        } footer: {
            Text(L10n.string(.appHintSonParDefaut, session.currentLanguage))
        }
    }

    private func loadDefaultSample(_ sound: ImprovSession.FavoriteSound) {
        guard loadingSoundID == nil else { return }
        loadingSoundID = sound.id
        Task {
            let outcome = await Task.detached {
                Result { try session.loadSample(named: sound.path, preset: sound.preset) }
            }.value
            loadingSoundID = nil
            if case .failure(let error) = outcome { actionError = "\(error)" }
        }
    }

    /// Lets Music Lab (Théorie: Tonnetz, Modes, Accords, Progressions...) observe this piece's
    /// own playback instead of a live track — either combined ("tout le morceau") or one/several
    /// specific tracks. See `ImprovSession.theoryDisplayState`'s own doc comment: unlike a live
    /// track, playback's chord/mode are always the piece's ground truth, never re-recognized.
    @ViewBuilder
    private func playbackObservationSection(piece: Piece) -> some View {
        Section {
            Toggle(L10n.string(.appLabelObserverToutLeMorceau, session.currentLanguage), isOn: Binding(
                get: { session.piecePlaybackObservationScope == .wholePiece },
                set: { session.setPiecePlaybackObservationScope($0 ? .wholePiece : nil) }
            ))
            ForEach(orderedTrackNames(in: piece), id: \.self) { trackName in
                Toggle(observationLabel(for: trackName), isOn: Binding(
                    get: { observedTrackNames.contains(trackName) },
                    set: { isOn in
                        var names = observedTrackNames
                        if isOn { names.insert(trackName) } else { names.remove(trackName) }
                        session.setPiecePlaybackObservationScope(names.isEmpty ? nil : .tracks(names))
                    }
                ))
            }
        } header: {
            Text(L10n.string(.appHeadingObserverMusicLab, session.currentLanguage))
        }
    }

    private var observedTrackNames: Set<String> {
        if case .tracks(let names) = session.piecePlaybackObservationScope { return names }
        return []
    }

    /// Every track name across every section, first-seen order, deduplicated — the same track
    /// name (e.g. "Piano") can legitimately repeat across sections, but should appear once here —
    /// plus `Section.chordProgressionObservationName` last, when any section actually has a chord
    /// progression to observe. Without this, the chord progression (shown as its own "Accords" row
    /// in "Pistes MIDI" just above) would be the one row in that list with no matching toggle
    /// here, reading as "the last one is missing" even though every real Track IS listed.
    private func orderedTrackNames(in piece: Piece) -> [String] {
        var seen = Set<String>()
        var names = piece.sections.flatMap(\.tracks).map(\.name).filter { seen.insert($0).inserted }
        if piece.sections.contains(where: { !$0.chordProgression.isEmpty }) {
            names.append(Section.chordProgressionObservationName)
        }
        return names
    }

    private func observationLabel(for trackName: String) -> String {
        trackName == Section.chordProgressionObservationName
            ? L10n.string(.appHeadingAccordsSection, session.currentLanguage)
            : trackName
    }

    // MARK: - Play tab

    @ViewBuilder
    private var playTab: some View {
        if let piece = session.piece {
            // No outer ScrollView: the WKWebView (score.html) already scrolls its own content
            // when it overflows this frame — nesting a SwiftUI ScrollView around it risks
            // gesture conflicts between the two scroll surfaces.
            ScoreEngravingView(score: ScoreEngravingAdapter.build(from: piece), highlightedPitches: session.playbackHeldPitches, elapsedSeconds: session.playbackElapsedSeconds)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
        } else {
            VStack {
                Spacer()
                Text(L10n.string(.appPlaceholderAucunMorceauChargeOnglet, session.currentLanguage)).foregroundStyle(.secondary)
                Spacer()
            }
        }
    }

    // MARK: - Analyse tab

    private struct MeasureAnalysisGroup: Identifiable {
        var id: Int { measure }
        let measure: Int
        let entries: [HarmonicAnalysisEntry]
        var hasLowConfidenceEntry: Bool { entries.contains { $0.confidence == .low } }
    }

    /// Groups the flat entry list by measure, preserving first-appearance order (not a numeric
    /// sort — a merged `ChordEvent`'s recorded `measure` is always its own start, so groups
    /// already come out in ascending order from `HarmonicAnalysisReport.build`).
    private func groupedByMeasure(_ entries: [HarmonicAnalysisEntry]) -> [MeasureAnalysisGroup] {
        var order: [Int] = []
        var byMeasure: [Int: [HarmonicAnalysisEntry]] = [:]
        for entry in entries {
            if byMeasure[entry.measure] == nil { order.append(entry.measure) }
            byMeasure[entry.measure, default: []].append(entry)
        }
        return order.map { MeasureAnalysisGroup(measure: $0, entries: byMeasure[$0] ?? []) }
    }

    @ViewBuilder
    private var analyseTab: some View {
        if let piece = session.piece {
            let groups = groupedByMeasure(HarmonicAnalysisReport.build(from: piece))
            if groups.isEmpty {
                emptyAnalysePlaceholder
            } else {
                List {
                    Section {
                        HStack {
                            Text(L10n.string(.appHeadingMesure, session.currentLanguage)).frame(width: 44, alignment: .leading)
                            Text(L10n.string(.appHeadingAccords, session.currentLanguage)).frame(maxWidth: .infinity, alignment: .leading)
                            Text(L10n.string(.appHeadingChiffrage, session.currentLanguage)).frame(maxWidth: .infinity, alignment: .leading)
                            Color.clear.frame(width: 20)
                        }
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    }
                    ForEach(groups) { group in
                        HStack(alignment: .top) {
                            Text("\(group.measure)").font(.subheadline.monospacedDigit()).frame(width: 44, alignment: .leading)
                            Text(group.entries.map(\.chordSymbol).joined(separator: " \u{2192} ")).frame(maxWidth: .infinity, alignment: .leading)
                            Text(group.entries.map(\.romanNumeral).joined(separator: " \u{2192} ")).frame(maxWidth: .infinity, alignment: .leading)
                            if group.hasLowConfidenceEntry {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .foregroundStyle(.orange)
                                    .imageScale(.small)
                                    .frame(width: 20)
                                    .help(L10n.string(.appLabelConfianceFaible, session.currentLanguage))
                                    .accessibilityLabel(L10n.string(.appLabelConfianceFaible, session.currentLanguage))
                            } else {
                                Color.clear.frame(width: 20)
                            }
                        }
                    }
                }
                #if os(macOS)
                .listStyle(.inset)
                #endif
            }
        } else {
            emptyAnalysePlaceholder
        }
    }

    @ViewBuilder
    private var emptyAnalysePlaceholder: some View {
        VStack {
            Spacer()
            Text(L10n.string(.appPlaceholderAucunMorceauChargeOnglet, session.currentLanguage)).foregroundStyle(.secondary)
            Spacer()
        }
    }
}

#Preview {
    PieceDetailView(session: ImprovSession(), onBackToCatalog: {})
}
