import MusicTheoryKit
import PieceModel
@testable import AudioEngine
import MIDIEngine
@testable import AppCore
import RecognitionEngine
@testable import LLMEngine
@testable import NetEngine
@testable import SoundTrackModel
import Foundation

// Mirrors the same helper in Tests/AppCoreTests/ImprovSessionTests.swift — compares by
// description so a new SessionError case doesn't also require updating this.
extension ImprovSession.SessionError: Equatable {
    public static func == (lhs: ImprovSession.SessionError, rhs: ImprovSession.SessionError) -> Bool {
        lhs.description == rhs.description
    }
}

// Stand-in for the real XCTest suites in Tests/PieceModelTests (which this file mirrors
// case-for-case): this machine has no Xcode, only Command Line Tools, so `swift test`
// fails with "no such module 'XCTest'". Run with `swift run SanityChecks`. If you ever
// install full Xcode, prefer `swift test` (or Xcode's test navigator) and let this file
// go stale — it's a workaround, not a replacement.

// Unbuffered: if a check ever crashes the process (a real concurrency bug did, once —
// see ImprovSession.playbackStateQueue), the fully-buffered default would swallow every
// check printed before the crash, making the failure look like silent, output-less death.
setvbuf(stdout, nil, _IONBF, 0)

nonisolated(unsafe) var checks = 0
nonisolated(unsafe) var failures = 0

func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL [\(label)]: expected \(expected), got \(actual)")
    }
}

func checkNil<T>(_ actual: T?, _ label: String) {
    checks += 1
    if actual != nil {
        failures += 1
        print("FAIL [\(label)]: expected nil, got \(String(describing: actual))")
    }
}

func checkNotNil<T>(_ actual: T?, _ label: String) {
    checks += 1
    if actual == nil {
        failures += 1
        print("FAIL [\(label)]: expected non-nil")
    }
}

// MARK: - MusicTheoryKit ChordVocabulary (mirrors Tests/MusicTheoryKitTests/ChordTests.swift's
// vocabulary-size/triad checks — not the full 205-scale-library sweep, which was already
// verified in an earlier session before this file existed)

func testChordVocabularySizeIncludesTriads() {
    check(ChordVocabulary.seed.count, 13, "chord vocabulary size (9 seventh chords + 4 triads)")
}

func testChordVocabularyCMajorTriad() {
    let template = ChordVocabulary.byID("Ma")
    checkNotNil(template, "chord vocabulary has Ma triad")
    if let template {
        let chord = Chord(root: PitchClass(0), template: template)
        check(chord.pitchClassSet, Set([0, 4, 7].map(PitchClass.init)), "C major triad pitch classes")
        check(chord.displayName, "CMa", "C major triad display name")
    }
}

// MARK: - ModeReferenceTests

func testResolveValidScaleIDMatchesDirectConstruction() {
    let reference = ModeReference(tonic: 2, scaleID: "dorian")
    let resolved = reference.resolve()
    let expected = Mode(tonic: PitchClass(2), scale: ScaleLibrary.byID("dorian")!)
    check(resolved, expected, "resolve valid scaleID matches direct construction")
}

func testResolveUnknownScaleIDReturnsNil() {
    let reference = ModeReference(tonic: 0, scaleID: "not-a-real-scale")
    checkNil(reference.resolve(), "resolve unknown scaleID returns nil")
}

func testChordReferenceResolveValidTemplateID() {
    let reference = ChordReference(root: 0, chordTemplateID: "Ma7")
    let resolved = reference.resolve()
    let expected = Chord(root: PitchClass(0), template: ChordVocabulary.byID("Ma7")!)
    check(resolved, expected, "chord reference resolve valid template id")
    check(resolved?.pitchClasses, [0, 4, 7, 11].map(PitchClass.init), "chord reference resolved pitch classes")
}

func testChordReferenceResolveUnknownTemplateIDReturnsNil() {
    let reference = ChordReference(root: 0, chordTemplateID: "not-a-real-chord")
    checkNil(reference.resolve(), "chord reference resolve unknown template id returns nil")
}

func testModeTransitionStoresItsFields() {
    let toMode = ModeReference(tonic: 7, scaleID: "dorian")
    let pivot = ChordReference(root: 7, chordTemplateID: "mi7")
    let transition = ModeTransition(toMode: toMode, pivotChords: [pivot], atMeasure: 9)
    check(transition.toMode, toMode, "mode transition toMode")
    check(transition.pivotChords, [pivot], "mode transition pivotChords")
    check(transition.atMeasure, 9, "mode transition atMeasure")
}

// MARK: - EventsTests

func testChordEventDefaultsAndFields() {
    let chord = ChordReference(root: 0, chordTemplateID: "Ma7")
    let event = ChordEvent(measure: 3, beat: 2.5, durationBeats: 1.5, chord: chord)
    check(event.measure, 3, "chord event measure")
    check(event.beat, 2.5, "chord event beat")
    check(event.durationBeats, 1.5, "chord event durationBeats")
    check(event.chord, chord, "chord event chord")
    check(event.inversion, 0, "chord event default inversion")
    checkNil(event.bassOverride, "chord event default bassOverride")
    check(event.playingStyle, .simultaneous, "chord event default playingStyle")
}

func testChordEventDistinctInstancesGetDistinctIDsByDefault() {
    let chord = ChordReference(root: 0, chordTemplateID: "Ma7")
    let a = ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: chord)
    let b = ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: chord)
    checks += 1
    if a.id == b.id {
        failures += 1
        print("FAIL [chord event distinct default ids]: got equal ids \(a.id)")
    }
}

func testMelodyEventDefaultVelocity() {
    let event = MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)
    check(event.velocity, 100, "melody event default velocity")
    check(event.pitch, 60, "melody event pitch")
}

func testFragmentPlacementResolvedFragmentAppliesNoTransformsByDefault() {
    let fragment = MelodicFragment(name: "motif", referenceMode: .fromFirstNote, intervals: [4, 7], noteDurations: [1, 1, 1])
    let placement = FragmentPlacement(fragmentID: fragment.id, measure: 1, beat: 1, basePitch: 60)
    let resolved = placement.resolvedFragment(from: fragment)
    check(resolved.absolutePitches(basePitch: 60), fragment.absolutePitches(basePitch: 60), "fragment placement default no-op pitches")
    check(resolved.noteDurations, fragment.noteDurations, "fragment placement default no-op durations")
}

func testFragmentPlacementResolvedFragmentAppliesTransformsInOrder() {
    let fragment = MelodicFragment(name: "motif", referenceMode: .fromFirstNote, intervals: [4, 7], noteDurations: [1, 1, 1])
    let placement = FragmentPlacement(
        fragmentID: fragment.id,
        measure: 1,
        beat: 1,
        basePitch: 60,
        retrograde: true,
        inversionPivot: 0,
        accelerationFactor: 2.0
    )
    let resolved = placement.resolvedFragment(from: fragment)
    let expected = fragment.retrograded().inverted(aroundPivot: 0).accelerated(by: 2.0)
    check(resolved.absolutePitches(basePitch: 60), expected.absolutePitches(basePitch: 60), "fragment placement ordered transforms pitches")
    check(resolved.noteDurations, expected.noteDurations, "fragment placement ordered transforms durations")
}

// MARK: - RenderingTests

func makeSection(tracks: [Track] = []) -> Section {
    Section(
        name: "A",
        lengthInMeasures: 4,
        mode: ModeReference(tonic: 0, scaleID: "dorian"),
        tracks: tracks
    )
}

func makePiece(fragments: [MelodicFragment] = [], sections: [Section] = []) -> Piece {
    Piece(
        title: "test piece",
        tempoBPM: 120,
        key: ModeReference(tonic: 0, scaleID: "dorian"),
        fragments: fragments,
        sections: sections
    )
}

func testAbsoluteBeatAtStartOfSectionIsZero() {
    let section = makeSection()
    check(section.absoluteBeat(measure: 1, beat: 1, beatsPerMeasure: 4), 0, "absolute beat at section start")
}

func testAbsoluteBeatAdvancesByFullMeasures() {
    let section = makeSection()
    check(section.absoluteBeat(measure: 3, beat: 1, beatsPerMeasure: 4), 8, "absolute beat advances by full measures")
}

func testAbsoluteBeatWithinMeasureOffset() {
    let section = makeSection()
    check(section.absoluteBeat(measure: 2, beat: 2.5, beatsPerMeasure: 4), 5.5, "absolute beat within measure offset")
}

func testScheduledNotesFromMelodyEventsAreConvertedAndSorted() {
    let track = Track(
        name: "lead",
        instrument: "piano",
        melodyEvents: [
            MelodyEvent(measure: 2, beat: 1, durationBeats: 1, pitch: 67, velocity: 90),
            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100),
        ]
    )
    let section = makeSection(tracks: [track])
    let piece = makePiece(sections: [section])
    let notes = track.scheduledNotes(in: piece, section: section)

    check(notes.map(\.startBeat), [0, 4], "scheduled notes from melody events startBeats")
    check(notes.map(\.pitch), [60, 67], "scheduled notes from melody events pitches")
    check(notes.map(\.velocity), [100, 90], "scheduled notes from melody events velocities")
}

func testScheduledNotesFromFragmentPlacementResolvesTransformsAndAdvancesCursor() {
    let fragment = MelodicFragment(
        id: "motif-1",
        name: "motif",
        referenceMode: .fromPreviousNote,
        intervals: [2, 2],
        noteDurations: [1, 1, 1]
    )
    let placement = FragmentPlacement(
        fragmentID: "motif-1",
        measure: 1,
        beat: 1,
        basePitch: 60,
        accelerationFactor: 2.0,
        velocity: 80
    )
    let track = Track(name: "lead", instrument: "piano", fragmentPlacements: [placement])
    let section = makeSection(tracks: [track])
    let piece = makePiece(fragments: [fragment], sections: [section])

    let notes = track.scheduledNotes(in: piece, section: section)

    check(notes.map(\.pitch), [60, 62, 64], "scheduled notes fragment placement pitches")
    check(notes.map(\.durationBeats), [0.5, 0.5, 0.5], "scheduled notes fragment placement durations")
    check(notes.map(\.startBeat), [0, 0.5, 1.0], "scheduled notes fragment placement startBeats")
    check(notes.map(\.velocity), [80, 80, 80], "scheduled notes fragment placement velocities")
}

func testScheduledNotesSkipsFragmentPlacementsWithUnknownFragmentID() {
    let placement = FragmentPlacement(fragmentID: "does-not-exist", measure: 1, beat: 1, basePitch: 60)
    let track = Track(name: "lead", instrument: "piano", fragmentPlacements: [placement])
    let section = makeSection(tracks: [track])
    let piece = makePiece(sections: [section])
    check(track.scheduledNotes(in: piece, section: section), [], "scheduled notes skips unknown fragment id")
}

func testScheduledNotesMergesAndSortsMelodyEventsAndFragmentPlacements() {
    let fragment = MelodicFragment(id: "motif-1", name: "motif", referenceMode: .fromFirstNote, intervals: [4], noteDurations: [1, 1])
    let track = Track(
        name: "lead",
        instrument: "piano",
        melodyEvents: [MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 72)],
        fragmentPlacements: [FragmentPlacement(fragmentID: "motif-1", measure: 1, beat: 1, basePitch: 60)]
    )
    let section = makeSection(tracks: [track])
    let piece = makePiece(fragments: [fragment], sections: [section])

    let notes = track.scheduledNotes(in: piece, section: section)

    check(notes.map(\.startBeat), [0, 1, 2], "scheduled notes merge sorted startBeats")
    check(notes.map(\.pitch), [60, 64, 72], "scheduled notes merge sorted pitches")
}

func testScheduledNotesCarryTheTracksInstrumentName() {
    let track = Track(name: "lead", instrument: "mcb.sf2", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)])
    let section = makeSection(tracks: [track])
    let piece = makePiece(sections: [section])
    let notes = track.scheduledNotes(in: piece, section: section)
    check(notes.map(\.instrumentName), ["mcb.sf2"], "scheduled notes carry the track's instrument name")
}

func testScheduledNotesTreatAnEmptyInstrumentAsDefault() {
    let track = Track(name: "lead", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)])
    let section = makeSection(tracks: [track])
    let piece = makePiece(sections: [section])
    let notes = track.scheduledNotes(in: piece, section: section)
    check(notes.map(\.instrumentName), [nil], "scheduled notes treat an empty instrument as default (nil)")
}

// MARK: - Chord rendering / Piece.renderedNotes (mirrors RenderingTests.swift additions)

func makeSectionWithChord(_ event: ChordEvent) -> Section {
    Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "dorian"), chordProgression: [event])
}

func testChordScheduledNotesSimultaneousDefaultIsRootPosition() {
    let section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7")))
    let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
    check(notes.map(\.pitch), [50, 53, 57, 60], "chord simultaneous root position pitches")
    check(notes.map(\.startBeat), [0, 0, 0, 0], "chord simultaneous startBeats")
    check(notes.map(\.durationBeats), [4, 4, 4, 4], "chord simultaneous durations")
}

func testChordScheduledNotesFirstInversionMovesRootUpAnOctave() {
    let section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7"), inversion: 1))
    let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
    check(notes.map(\.pitch).sorted(), [53, 57, 60, 62], "chord first inversion pitches")
}

func testChordScheduledNotesBassOverrideAddsSlashBassBelowChord() {
    let section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7"), bassOverride: 9))
    let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
    check(notes.map(\.pitch), [45, 50, 53, 60], "chord bass override pitches")
}

func testChordScheduledNotesArpeggioUpSpreadsNotesAcrossDuration() {
    let section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"), playingStyle: .arpeggioUp))
    let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
    check(notes.map(\.pitch), [48, 52, 55, 59], "chord arpeggioUp pitches")
    check(notes.map(\.startBeat), [0, 1, 2, 3], "chord arpeggioUp startBeats")
}

func testChordScheduledNotesUnknownTemplateProducesNoNotes() {
    let section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "not-a-chord")))
    check(section.chordScheduledNotes(beatsPerMeasure: 4), [], "chord unknown template produces no notes")
}

func testChordScheduledNotesCarryTheSectionsChordInstrument() {
    var section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7")))
    section.chordInstrument = "strings.sf2"
    let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
    check(notes.map(\.instrumentName), Array(repeating: "strings.sf2", count: notes.count), "chord scheduled notes carry the section's chord instrument")
}

func testChordScheduledNotesDefaultChordInstrumentIsNil() {
    let section = makeSectionWithChord(ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7")))
    let notes = section.chordScheduledNotes(beatsPerMeasure: 4)
    checks += 1
    if !notes.allSatisfy({ $0.instrumentName == nil }) {
        failures += 1
        print("FAIL [chord scheduled notes default chord instrument is nil]: \(notes)")
    }
}

func testPieceRenderedNotesCarryDistinctInstrumentNamesForChordsAndTracks() {
    let track = Track(name: "lead", instrument: "mcb.sf2", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 72)])
    var section = Section(
        name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
        chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))],
        tracks: [track]
    )
    section.chordInstrument = "strings.sf2"
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
    let notes = piece.renderedNotes()
    checks += 1
    if !notes.contains(where: { $0.pitch == 72 && $0.instrumentName == "mcb.sf2" }) {
        failures += 1
        print("FAIL [piece rendered notes: melody carries its track instrument]: \(notes)")
    }
    check(notes.filter { $0.pitch != 72 }.map(\.instrumentName), Array(repeating: "strings.sf2", count: 4), "piece rendered notes: chord tones carry the section's chord instrument")
}

func testPieceRenderedNotesCombinesChordsAndTracksInSeconds() {
    let track = Track(name: "lead", instrument: "piano", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 72)])
    let section = Section(
        name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
        chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))],
        tracks: [track]
    )
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
    let notes = piece.renderedNotes()
    check(notes.count, 5, "piece rendered notes count")
    checks += 1
    if !notes.contains(where: { $0.pitch == 72 && $0.durationSeconds == 0.5 }) {
        failures += 1
        print("FAIL [piece rendered notes contains melody note]: \(notes)")
    }
    checks += 1
    if !notes.contains(where: { $0.pitch == 48 && $0.durationSeconds == 2.0 }) {
        failures += 1
        print("FAIL [piece rendered notes contains chord tone]: \(notes)")
    }
}

func testPieceRenderedNotesOffsetsSecondSectionByFirstSectionsLength() {
    let sectionA = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"))
    let trackB = Track(name: "lead", instrument: "piano", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)])
    let sectionB = Section(name: "B", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [trackB])
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [sectionA, sectionB])
    let notes = piece.renderedNotes()
    check(notes.map(\.startSeconds), [2.0], "piece rendered notes second section offset")
}

func testHarmonicTimelineResolvesOneChordPerEventInSeconds() {
    let section = Section(
        name: "A", lengthInMeasures: 2, mode: ModeReference(tonic: 2, scaleID: "dorian"),
        chordProgression: [
            ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "mi7")),
            ChordEvent(measure: 2, beat: 1, durationBeats: 4, chord: ChordReference(root: 7, chordTemplateID: "7")),
        ]
    )
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
    let timeline = piece.harmonicTimeline()
    check(timeline.count, 2, "harmonic timeline event count")
    check(timeline.map(\.startSeconds), [0, 2.0], "harmonic timeline start seconds")
    check(timeline.map(\.endSeconds), [2.0, 4.0], "harmonic timeline end seconds")
    check(timeline.map(\.chord), [ChordReference(root: 2, chordTemplateID: "mi7"), ChordReference(root: 7, chordTemplateID: "7")], "harmonic timeline chords")
    check(timeline.map(\.mode), [ModeReference(tonic: 2, scaleID: "dorian"), ModeReference(tonic: 2, scaleID: "dorian")], "harmonic timeline mode carried per event")
}

func testHarmonicTimelineOffsetsSecondSectionAndCarriesItsOwnMode() {
    let sectionA = Section(
        name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
        chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))]
    )
    let sectionB = Section(
        name: "B", lengthInMeasures: 1, mode: ModeReference(tonic: 7, scaleID: "mixolydian"),
        chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 7, chordTemplateID: "7"))]
    )
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [sectionA, sectionB])
    let timeline = piece.harmonicTimeline()
    check(timeline.map(\.startSeconds), [0, 2.0], "harmonic timeline section offset")
    check(timeline[1].mode, ModeReference(tonic: 7, scaleID: "mixolydian"), "harmonic timeline second section mode")
}

func testHarmonicTimelineEmptyForAPieceWithNoChords() {
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [
        Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian")),
    ])
    check(piece.harmonicTimeline(), [], "harmonic timeline empty for chordless piece")
}

// MARK: - PieceTests

func testFragmentLookupByIDFindsMatch() {
    let fragment = MelodicFragment(id: "motif-1", name: "motif", referenceMode: .fromFirstNote, intervals: [4], noteDurations: [1, 1])
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "dorian"), fragments: [fragment])
    check(piece.fragment(id: "motif-1"), fragment, "fragment lookup by id finds match")
}

func testFragmentLookupByIDReturnsNilWhenMissing() {
    let piece = Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "dorian"))
    checkNil(piece.fragment(id: "missing"), "fragment lookup by id missing returns nil")
}

func testPieceRoundTripsThroughJSON() {
    let fragment = MelodicFragment(id: "motif-1", name: "motif", referenceMode: .fromPreviousNote, intervals: [2, 2], noteDurations: [1, 1, 1])
    let section = Section(
        name: "A",
        lengthInMeasures: 4,
        mode: ModeReference(tonic: 0, scaleID: "dorian"),
        modeTransition: ModeTransition(
            toMode: ModeReference(tonic: 7, scaleID: "dorian"),
            pivotChords: [ChordReference(root: 7, chordTemplateID: "mi7")],
            atMeasure: 3
        ),
        chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))],
        tracks: [
            Track(
                name: "lead",
                instrument: "piano",
                melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)],
                fragmentPlacements: [FragmentPlacement(fragmentID: "motif-1", measure: 1, beat: 1, basePitch: 60)]
            )
        ]
    )
    let piece = Piece(
        title: "Round Trip",
        composer: "Test Suite",
        tempoBPM: 96,
        key: ModeReference(tonic: 0, scaleID: "dorian"),
        fragments: [fragment],
        sections: [section]
    )

    do {
        let data = try JSONEncoder().encode(piece)
        let decoded = try JSONDecoder().decode(Piece.self, from: data)
        check(decoded, piece, "piece round trips through JSON")
    } catch {
        failures += 1
        checks += 1
        print("FAIL [piece round trips through JSON]: threw \(error)")
    }
}

// MARK: - Existing MelodicFragment coverage (sanity re-check against the XCTest file's cases)

func testMelodicFragmentAbsolutePitchesAndTransforms() {
    let fromFirst = MelodicFragment(name: "test", referenceMode: .fromFirstNote, intervals: [4, 7, 12], noteDurations: [1, 1, 1, 1])
    check(fromFirst.absolutePitches(basePitch: 60), [60, 64, 67, 72], "fromFirstNote absolute pitches")

    let fromPrev = MelodicFragment(name: "test", referenceMode: .fromPreviousNote, intervals: [4, 3, 5], noteDurations: [1, 1, 1, 1])
    check(fromPrev.absolutePitches(basePitch: 60), [60, 64, 67, 72], "fromPreviousNote absolute pitches")

    let retro = fromPrev.retrograded()
    let fromPrevPitches = fromPrev.absolutePitches(basePitch: 60)
    check(retro.absolutePitches(basePitch: fromPrevPitches.last!), Array(fromPrevPitches.reversed()), "retrograde reverses pitches")

    let doubleInverted = fromPrev.inverted().inverted()
    check(doubleInverted.absolutePitches(basePitch: 60), fromPrev.absolutePitches(basePitch: 60), "double inversion round trips")

    let accelerated = fromPrev.accelerated(by: 2.0)
    check(accelerated.noteDurations, fromPrev.noteDurations.map { $0 / 2.0 }, "acceleration scales durations")
}

// MARK: - MIDIRawParserTests (mirrors Tests/MIDIEngineTests/MIDIRawParserTests.swift)

func testMIDIParsesNoteOn() {
    check(MIDIRawParser.parseNoteEvents([0x90, 60, 100]), [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0)], "midi parses note on")
}

func testMIDIParsesNoteOnOnNonZeroChannel() {
    check(MIDIRawParser.parseNoteEvents([0x93, 60, 100]), [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 3)], "midi parses note on non-zero channel")
}

func testMIDIParsesNoteOff() {
    check(MIDIRawParser.parseNoteEvents([0x80, 60, 0]), [MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0)], "midi parses note off")
}

func testMIDINoteOnWithZeroVelocityIsTreatedAsNoteOff() {
    check(MIDIRawParser.parseNoteEvents([0x90, 60, 0]), [MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0)], "midi note-on velocity 0 is note-off")
}

func testMIDIParsesMultipleMessagesInOneBuffer() {
    let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0x90, 64, 90, 0x80, 60, 0])
    check(events, [
        MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0),
        MIDINoteEvent(kind: .noteOn, pitch: 64, velocity: 90, channel: 0),
        MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0),
    ], "midi parses multiple messages in one buffer")
}

func testMIDIIgnoresNonNoteMessages() {
    let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0xB0, 7, 127, 0x90, 64, 90])
    check(events, [
        MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0),
        MIDINoteEvent(kind: .noteOn, pitch: 64, velocity: 90, channel: 0),
    ], "midi ignores non-note messages")
}

func testMIDITruncatedTrailingMessageIsDropped() {
    check(MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0x90, 64]), [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0)], "midi drops truncated trailing message")
}

func testMIDIEmptyBufferProducesNoEvents() {
    check(MIDIRawParser.parseNoteEvents([]), [], "midi empty buffer produces no events")
}

// MARK: - FFTPitchAnalyzerTests (mirrors Tests/AudioEngineTests/FFTPitchAnalyzerTests.swift)

func sineWaveForFFTTests(frequencyHz: Double, sampleRate: Double, count: Int, amplitude: Float = 1.0) -> [Float] {
    (0..<count).map { i in
        amplitude * Float(sin(2.0 * Double.pi * frequencyHz * Double(i) / sampleRate))
    }
}

/// Sums several sine waves at equal amplitude into one signal — a synthetic stand-in for a
/// chord (several simultaneous notes) without needing real audio input.
func mixedSineWavesForFFTTests(frequenciesHz: [Double], sampleRate: Double, count: Int, amplitude: Float = 1.0) -> [Float] {
    var mix = [Float](repeating: 0, count: count)
    for frequency in frequenciesHz {
        let wave = sineWaveForFFTTests(frequencyHz: frequency, sampleRate: sampleRate, count: count, amplitude: amplitude)
        for i in 0..<count { mix[i] += wave[i] }
    }
    return mix
}

func checkClose(_ actual: Double, _ expected: Double, accuracy: Double, _ label: String) {
    checks += 1
    if abs(actual - expected) > accuracy {
        failures += 1
        print("FAIL [\(label)]: expected \(expected) +/- \(accuracy), got \(actual)")
    }
}

func testFFTDetectsA440SineWave() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = sineWaveForFFTTests(frequencyHz: 440, sampleRate: 44100, count: 4096)
    guard let detected = analyzer.dominantFrequency(in: samples, sampleRate: 44100) else {
        failures += 1; checks += 1
        print("FAIL [FFT detects A440]: got nil")
        return
    }
    checkClose(detected, 440, accuracy: 2.0, "FFT detects A440")
}

func testFFTDetectsMiddleCSineWave() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = sineWaveForFFTTests(frequencyHz: 261.63, sampleRate: 44100, count: 4096)
    guard let detected = analyzer.dominantFrequency(in: samples, sampleRate: 44100) else {
        failures += 1; checks += 1
        print("FAIL [FFT detects middle C]: got nil")
        return
    }
    checkClose(detected, 261.63, accuracy: 2.0, "FFT detects middle C")
}

func testFFTReturnsNilForSilence() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    checkNil(analyzer.dominantFrequency(in: [Float](repeating: 0, count: 4096), sampleRate: 44100), "FFT returns nil for silence")
}

func testFFTReturnsNilForLowAmplitudeNoise() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = (0..<4096).map { _ in Float.random(in: -0.0001...0.0001) }
    checkNil(analyzer.dominantFrequency(in: samples, sampleRate: 44100), "FFT returns nil for low-amplitude noise")
}

func testFFTReturnsNilWhenSampleCountDoesNotMatchSize() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    checkNil(analyzer.dominantFrequency(in: [Float](repeating: 0, count: 100), sampleRate: 44100), "FFT returns nil for wrong sample count")
}

func testFFTRespectsMinAndMaxHzRange() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = sineWaveForFFTTests(frequencyHz: 100, sampleRate: 44100, count: 4096)
    checkNil(analyzer.dominantFrequency(in: samples, sampleRate: 44100, minHz: 200, maxHz: 2000), "FFT respects min/max Hz range")
}

func testMidiPitchFromFrequencyMatchesKnownNotes() {
    check(DetectedPitch.midiPitch(forFrequencyHz: 440.0), 69, "midiPitch(forFrequencyHz:) A4")
    check(DetectedPitch.midiPitch(forFrequencyHz: 261.63), 60, "midiPitch(forFrequencyHz:) middle C")
    check(DetectedPitch.midiPitch(forFrequencyHz: 220.0), 57, "midiPitch(forFrequencyHz:) A3")
}

func testRMSOfSilenceIsZero() {
    check(FFTPitchAnalyzer.rms(of: [Float](repeating: 0, count: 4096)), 0, "rms of silence is zero")
}

func testRMSOfFullScaleSineIsAboutOneOverSqrtTwo() {
    let samples = sineWaveForFFTTests(frequencyHz: 440, sampleRate: 44100, count: 4096)
    checkClose(Double(FFTPitchAnalyzer.rms(of: samples)), 1.0 / 2.0.squareRoot(), accuracy: 0.01, "rms of full-scale sine")
}

func testRMSScalesWithAmplitude() {
    // amplitude 0.001 sine -> rms ~= 0.001/sqrt(2) =~ 0.0007, comfortably below the 0.003
    // detection floor (unlike e.g. amplitude 0.01, whose rms of ~0.007 clears it).
    let quiet = sineWaveForFFTTests(frequencyHz: 440, sampleRate: 44100, count: 4096, amplitude: 0.001)
    checks += 1
    if FFTPitchAnalyzer.rms(of: quiet) >= FFTPitchAnalyzer.minimumRMSForDetection {
        failures += 1
        print("FAIL [rms scales with amplitude]: quiet sine's rms was not below the detection floor")
    }
}

func testDetectsAllThreeNotesOfACMajorTriad() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    // C4, E4, G4 — each at a fraction of full amplitude so the mix doesn't clip.
    let samples = mixedSineWavesForFFTTests(frequenciesHz: [261.63, 329.63, 392.00], sampleRate: 44100, count: 4096, amplitude: 0.3)
    let detected = analyzer.dominantFrequencies(in: samples, sampleRate: 44100).sorted()
    check(detected.count, 3, "C major triad detects 3 peaks")
    if detected.count == 3 {
        checkClose(detected[0], 261.63, accuracy: 3.0, "C major triad detects C4")
        checkClose(detected[1], 329.63, accuracy: 3.0, "C major triad detects E4")
        checkClose(detected[2], 392.00, accuracy: 3.0, "C major triad detects G4")
    }
}

func testDominantFrequenciesReturnsEmptyForSilence() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    check(analyzer.dominantFrequencies(in: [Float](repeating: 0, count: 4096), sampleRate: 44100), [], "dominantFrequencies empty for silence")
}

func testDominantFrequenciesRespectsMaxPeaks() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = mixedSineWavesForFFTTests(frequenciesHz: [261.63, 329.63, 392.00, 440.00], sampleRate: 44100, count: 4096, amplitude: 0.25)
    let detected = analyzer.dominantFrequencies(in: samples, sampleRate: 44100, maxPeaks: 2)
    check(detected.count, 2, "dominantFrequencies respects maxPeaks")
}

func testDominantFrequenciesMergesPeaksCloserThanMinSemitoneSeparation() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    // 440Hz and 445Hz are well under a semitone apart (a semitone above 440Hz is ~466Hz).
    let samples = mixedSineWavesForFFTTests(frequenciesHz: [440, 445], sampleRate: 44100, count: 4096, amplitude: 0.5)
    let detected = analyzer.dominantFrequencies(in: samples, sampleRate: 44100, minSemitoneSeparation: 1.0)
    check(detected.count, 1, "dominantFrequencies merges close peaks")
}

func testDominantFrequencyMatchesFirstOfDominantFrequencies() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = mixedSineWavesForFFTTests(frequenciesHz: [261.63, 392.00], sampleRate: 44100, count: 4096, amplitude: 0.4)
    let single = analyzer.dominantFrequency(in: samples, sampleRate: 44100)
    let multi = analyzer.dominantFrequencies(in: samples, sampleRate: 44100, maxPeaks: 1)
    check(single, multi.first, "dominantFrequency matches first of dominantFrequencies")
}

// MARK: - ImprovSessionTests (mirrors Tests/AppCoreTests/ImprovSessionTests.swift)

func testLoadDemoPieceSetsPieceAndLogsIt() {
    let session = ImprovSession()
    checkNil(session.piece, "improv session starts with no piece")
    session.loadDemoPiece()
    check(session.piece?.title, "ii-V-I demo", "improv session load-demo sets piece title")
    checks += 1
    if !session.log.contains(where: { $0.contains("ii-V-I demo") }) {
        failures += 1
        print("FAIL [improv session load-demo logs it]: \(session.log)")
    }
}

func testPlayWithoutAPieceLoadedThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.play()
        failures += 1
        print("FAIL [improv session play without piece throws]: did not throw")
    } catch {
        // expected
    }
}

func testPlayTracksPlaybackStateSynchronouslyThenClearsItWhenFinished() {
    do {
        let session = ImprovSession()
        try session.start()

        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 1, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))]
        )
        // A very fast tempo so playback finishes almost immediately and this check doesn't
        // need to sleep long to observe the "cleared after finishing" half of the behavior.
        let piece = Piece(title: "fast", tempoBPM: 6000, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadPiece(fromJSONFile: tempFile.path)

        try session.play()
        check(session.isPlaying, true, "play sets isPlaying")
        check(session.playbackTimeline.count, 1, "play populates playbackTimeline")
        check(session.playbackTimeline.first?.chord, ChordReference(root: 0, chordTemplateID: "Ma7"), "playbackTimeline carries the chord")
        check(session.playbackCurrentChordIndex, 0, "play starts at chord index 0")

        Thread.sleep(forTimeInterval: 0.5)
        check(session.isPlaying, false, "playback finished clears isPlaying")
        checkNil(session.playbackCurrentChordIndex, "playback finished clears playbackCurrentChordIndex")
        check(session.playbackHeldPitches, [], "playback finished clears playbackHeldPitches")
    } catch {
        failures += 1
        print("FAIL [play tracks playback state]: threw \(error)")
    }
}

func loadTemporaryPiece(_ piece: Piece, into session: ImprovSession) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try JSONEncoder().encode(piece).write(to: url)
    try session.loadPiece(fromJSONFile: url.path)
}

func testSetPieceTrackInstrumentUpdatesTrackAndLogs() {
    do {
        let session = ImprovSession()
        let track = Track(name: "lead", instrument: "")
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 0, instrumentName: "mcb.sf2")

        check(session.piece?.sections[0].tracks[0].instrument, "mcb.sf2", "setPieceTrackInstrument updates the track's instrument")
        checks += 1
        if !session.log.contains(where: { $0.contains("mcb.sf2") }) {
            failures += 1
            print("FAIL [setPieceTrackInstrument logs it]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument updates track and logs]: threw \(error)")
    }
}

func testSetPieceTrackInstrumentNilRevertsToEmptyString() {
    do {
        let session = ImprovSession()
        let track = Track(name: "lead", instrument: "mcb.sf2")
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 0, instrumentName: nil)

        check(session.piece?.sections[0].tracks[0].instrument, "", "setPieceTrackInstrument(nil) reverts to empty string")
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument nil reverts]: threw \(error)")
    }
}

func testSetPieceTrackInstrumentWithInvalidSectionIndexThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.setPieceTrackInstrument(sectionIndex: 99, trackIndex: 0, instrumentName: "mcb.sf2")
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid section throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .invalidPieceSectionIndex {
            failures += 1
            print("FAIL [setPieceTrackInstrument invalid section throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid section throws]: unexpected error \(error)")
    }
}

func testSetPieceTrackInstrumentWithInvalidTrackIndexThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 99, instrumentName: "mcb.sf2")
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid track throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .invalidPieceTrackIndex {
            failures += 1
            print("FAIL [setPieceTrackInstrument invalid track throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid track throws]: unexpected error \(error)")
    }
}

func testSetPieceChordInstrumentUpdatesSectionAndLogs() {
    do {
        let session = ImprovSession()
        session.loadDemoPiece()
        try session.setPieceChordInstrument(sectionIndex: 0, instrumentName: "strings.sf2")
        check(session.piece?.sections[0].chordInstrument, "strings.sf2", "setPieceChordInstrument updates the section's chord instrument")
        checks += 1
        if !session.log.contains(where: { $0.contains("strings.sf2") }) {
            failures += 1
            print("FAIL [setPieceChordInstrument logs it]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceChordInstrument updates section and logs]: threw \(error)")
    }
}

func testSetPieceChordInstrumentWithInvalidSectionIndexThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.setPieceChordInstrument(sectionIndex: 99, instrumentName: "strings.sf2")
        failures += 1
        print("FAIL [setPieceChordInstrument invalid section throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .invalidPieceSectionIndex {
            failures += 1
            print("FAIL [setPieceChordInstrument invalid section throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceChordInstrument invalid section throws]: unexpected error \(error)")
    }
}

func testPlayWarnsWhenATracksInstrumentFileIsNotFound() {
    do {
        let session = ImprovSession()
        try session.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try session.listSampleFiles(in: folder.path)

        let track = Track(name: "lead", instrument: "does-not-exist.sf2", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)])
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "fast", tempoBPM: 6000, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.play()

        checks += 1
        if !session.log.contains(where: { $0.contains("does-not-exist.sf2") && $0.contains("introuvable") }) {
            failures += 1
            print("FAIL [play warns on missing track instrument]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [play warns when instrument file is not found]: threw \(error)")
    }
}

func testPlayWithoutAnyTrackInstrumentLogsNoInstrumentWarning() {
    do {
        let session = ImprovSession()
        try session.start()
        session.loadDemoPiece()
        try session.play()
        Thread.sleep(forTimeInterval: 0.1)
        checks += 1
        if session.log.contains(where: { $0.hasPrefix("Instrument:") }) {
            failures += 1
            print("FAIL [play without instruments logs no warning]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [play without any track instrument]: threw \(error)")
    }
}

func testStartTrackOnAnUnlistedMIDIPortThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        // Default fusion mode is `.merged`, so `.midiSource(0)` isn't one of `tracks` yet.
        try session.startTrack(.midiSource(0))
        failures += 1
        print("FAIL [start-track on unlisted MIDI port throws]: did not throw")
    } catch ImprovSession.SessionError.unknownTrack {
        // expected
    } catch {
        failures += 1
        print("FAIL [start-track on unlisted MIDI port throws]: wrong error \(error)")
    }
}

func testDefaultMIDIFusionModeIsMergedWithASingleMIDITrack() {
    let session = ImprovSession()
    check(session.midiFusionMode, MIDIFusionMode.merged, "default MIDI fusion mode is merged")
    check(session.tracks.contains { $0.id == .midiMerged }, true, "merged mode lists a single midiMerged track")
    check(session.tracks.contains { $0.id == .computerKeyboard }, true, "tracks always include the computer keyboard")
    check(session.tracks.contains { $0.id == .microphone }, true, "tracks always include the microphone")
}

func testSetMIDIFusionModeSwitchesTrackList() {
    let session = ImprovSession()
    session.setMIDIFusionMode(.individual)
    check(session.midiFusionMode, MIDIFusionMode.individual, "setMIDIFusionMode updates midiFusionMode")
    check(session.tracks.contains { $0.id == .midiMerged }, false, "individual mode drops the midiMerged track")
    check(session.tracks.contains { $0.id == .computerKeyboard }, true, "individual mode still lists the computer keyboard")
    check(session.tracks.contains { $0.id == .microphone }, true, "individual mode still lists the microphone")
}

func testMicrophoneTrackCannotHaveSound() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.setSoundEnabled(true, for: .microphone)
        failures += 1
        print("FAIL [microphone track cannot have sound]: did not throw")
    } catch ImprovSession.SessionError.trackCannotHaveSound {
        // expected
    } catch {
        failures += 1
        print("FAIL [microphone track cannot have sound]: wrong error \(error)")
    }
}

func testNetMessageRoundTripsThroughJSON() {
    checks += 1
    do {
        let original = NetMessage(kind: .noteEvent, clientID: "abc", trackID: "clavier", isNoteOn: true, pitch: 60, velocity: 100, channel: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetMessage.self, from: data)
        check(decoded, original, "NetMessage round-trips through JSON")
    } catch {
        failures += 1
        print("FAIL [NetMessage round trip]: threw \(error)")
    }
}
testNetMessageRoundTripsThroughJSON()

// A real client/server pair over real loopback TCP, both `ImprovSession` instances living
// in this one process — not a mock, and not a pty-driven external test: exercises the
// actual `NetworkServer`/`NetworkClient`/`FramedConnection` wire path end to end. Port
// 17891 is arbitrary; a rerun failing specifically with "address already in use" points at
// the OS not having released it yet from a previous run, not a logic bug.
func testCollaborativeServerClientSyncsTracksAndRecognition() {
    checks += 1
    do {
        let server = ImprovSession()
        try server.start()
        let client = ImprovSession()
        try client.start()
        let port = 17891

        try server.startServer(port: port)
        try client.connectToServer(host: "127.0.0.1", port: port)
        Thread.sleep(forTimeInterval: 0.3) // TCP handshake + hello

        try server.startTrack(.computerKeyboard)
        for pitch in [62, 66, 69] { server.pressKey(pitch: pitch) } // D F# A -> D major

        try client.startTrack(.computerKeyboard)
        for pitch in [60, 64, 67] { client.pressKey(pitch: pitch) } // C E G -> C major

        Thread.sleep(forTimeInterval: 0.6) // noteEvent -> server recognizes -> next sync tick -> client merges

        let clientTrackOnServer = TrackID.remote(clientID: client.localClientID, trackID: "clavier")
        if let mirrored = server.tracks.first(where: { $0.id == clientTrackOnServer }) {
            check(mirrored.recognizedChord?.chordTemplateID, "Ma", "server recognizes the client's forwarded C major triad")
        } else {
            failures += 1
            print("FAIL [server/client sync]: server never saw the client's 'clavier' track")
        }

        let serverTrackOnClient = TrackID.remote(clientID: server.localClientID, trackID: "clavier")
        if let mirrored = client.tracks.first(where: { $0.id == serverTrackOnClient }) {
            let hasChordText = mirrored.remoteChordDisplay?.contains("Ma") ?? false
            check(hasChordText, true, "client mirrors the server's own track with a display-string chord")
        } else {
            failures += 1
            print("FAIL [server/client sync]: client never saw the server's own 'clavier' track")
        }

        server.stopServer()
        client.disconnectFromServer()
        Thread.sleep(forTimeInterval: 0.1)
        check(server.tracks.contains { if case .remote = $0.id { return true }; return false }, false, "stopServer clears every remote track")
        check(client.tracks.contains { if case .remote = $0.id { return true }; return false }, false, "disconnectFromServer clears every remote track")
    } catch {
        failures += 1
        print("FAIL [server/client sync]: threw \(error)")
    }
}
testCollaborativeServerClientSyncsTracksAndRecognition()

func testRecordingCapturesFilteredTrackEvents() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.startTrack(.computerKeyboard)
        try session.startTrack(.microphone)
        try session.startRecording(title: "Test", tracks: [.computerKeyboard])
        session.pressKey(pitch: 60, track: .computerKeyboard) // should be captured
        session.pressKey(pitch: 64, track: .microphone) // filtered out, should not be captured
        Thread.sleep(forTimeInterval: 0.05)
        let soundTrack = try session.stopRecording()
        check(soundTrack.events.count, 1, "recording captures only the filtered track's events")
        check(soundTrack.events.first?.trackID, "clavier", "captured event carries the correct wire track id")
        check(soundTrack.events.first?.pitch, 60, "captured event carries the correct pitch")
    } catch {
        failures += 1
        print("FAIL [recording captures filtered track events]: threw \(error)")
    }
}
testRecordingCapturesFilteredTrackEvents()

func testStartRecordingTwiceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startRecording(title: "A")
        do {
            try session.startRecording(title: "B")
            failures += 1
            print("FAIL [start recording twice throws]: did not throw")
        } catch ImprovSession.SessionError.alreadyRecording {
            // expected
        }
    } catch {
        failures += 1
        print("FAIL [start recording twice throws]: threw \(error)")
    }
}
testStartRecordingTwiceThrows()

func testStopRecordingWithoutStartingThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        _ = try session.stopRecording()
        failures += 1
        print("FAIL [stop recording without starting throws]: did not throw")
    } catch ImprovSession.SessionError.notRecording {
        // expected
    } catch {
        failures += 1
        print("FAIL [stop recording without starting throws]: wrong error \(error)")
    }
}
testStopRecordingWithoutStartingThrows()

func testSoundTrackSaveThenLoadRoundTrips() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.startRecording(title: "RoundTrip")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveSoundTrack(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadSoundTrack(fromJSONFile: tempFile.path)
        check(reloaded.currentSoundTrack?.events.count, session.currentSoundTrack?.events.count, "soundtrack round trips through JSON")
    } catch {
        failures += 1
        print("FAIL [soundtrack save/load round trip]: threw \(error)")
    }
}
testSoundTrackSaveThenLoadRoundTrips()

func testPlaySoundTrackTracksPlaybackStateThenClearsItWhenFinished() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startRecording(title: "Play")
        session.pressKey(pitch: 60)
        Thread.sleep(forTimeInterval: 0.05)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.playSoundTrack()
        check(session.isPlayingSoundTrack, true, "playSoundTrack sets isPlayingSoundTrack")

        Thread.sleep(forTimeInterval: (session.currentSoundTrack?.durationSeconds ?? 0) + 0.4)
        check(session.isPlayingSoundTrack, false, "soundtrack playback finished clears isPlayingSoundTrack")
        check(session.soundTrackHeldPitches, [], "soundtrack playback finished clears soundTrackHeldPitches")
    } catch {
        failures += 1
        print("FAIL [play soundtrack tracks playback state]: threw \(error)")
    }
}
testPlaySoundTrackTracksPlaybackStateThenClearsItWhenFinished()

func testPlaySoundTrackWithoutARecordingThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.playSoundTrack()
        failures += 1
        print("FAIL [play soundtrack without a recording throws]: did not throw")
    } catch ImprovSession.SessionError.noSoundTrackRecorded {
        // expected
    } catch {
        failures += 1
        print("FAIL [play soundtrack without a recording throws]: wrong error \(error)")
    }
}
testPlaySoundTrackWithoutARecordingThrows()

func testComposeSoundTrackToPiecesWithAFakeGeneratorProducesValidatedPieces() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.listPieceFiles(in: folder.path) // establishes pieceFolder for saving candidates

        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "From Recording", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let paths = try session.composeSoundTrackToPieces(candidateCount: 1) { prompt, connection in
            if !prompt.contains("ON") { failures += 1; print("FAIL [compose soundtrack to pieces]: prompt doesn't mention the recorded events") }
            return fakeResponse
        }
        check(paths.count, 1, "composeSoundTrackToPieces saved exactly one candidate")
        check(session.piece?.title, "From Recording", "composeSoundTrackToPieces sets the current piece to the last candidate")
        check(FileManager.default.fileExists(atPath: paths[0]), true, "the candidate piece file was actually written")
    } catch {
        failures += 1
        print("FAIL [compose soundtrack to pieces]: threw \(error)")
    }
}
testComposeSoundTrackToPiecesWithAFakeGeneratorProducesValidatedPieces()

func testComposeSoundTrackToPiecesWithATitleOverridesTheLLMsOwnTitle() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.listPieceFiles(in: folder.path)
        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "LLM Chosen Title", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let paths = try session.composeSoundTrackToPieces(candidateCount: 1, title: "My Own Title") { _, _ in fakeResponse }
        check(session.piece?.title, "My Own Title", "composeSoundTrackToPieces title override wins over the LLM's own title")
        checks += 1
        if !(paths.first?.hasSuffix("My Own Title.json") ?? false) {
            failures += 1
            print("FAIL [compose soundtrack title override filename]: \(paths)")
        }
    } catch {
        failures += 1
        print("FAIL [compose soundtrack to pieces with title override]: threw \(error)")
    }
}
testComposeSoundTrackToPiecesWithATitleOverridesTheLLMsOwnTitle()

func testCurrentTextCompositionPromptWithoutSourceTextOrOverrideThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        _ = try session.currentTextCompositionPrompt()
        failures += 1
        print("FAIL [currentTextCompositionPrompt without source text throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .noSourceText {
            failures += 1
            print("FAIL [currentTextCompositionPrompt without source text throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [currentTextCompositionPrompt without source text throws]: unexpected error \(error)")
    }
}
testCurrentTextCompositionPromptWithoutSourceTextOrOverrideThrows()

func testCurrentSoundTrackCompositionPromptWithoutARecordingOrOverrideThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        _ = try session.currentSoundTrackCompositionPrompt()
        failures += 1
        print("FAIL [currentSoundTrackCompositionPrompt without recording throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .noSoundTrackRecorded {
            failures += 1
            print("FAIL [currentSoundTrackCompositionPrompt without recording throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [currentSoundTrackCompositionPrompt without recording throws]: unexpected error \(error)")
    }
}
testCurrentSoundTrackCompositionPromptWithoutARecordingOrOverrideThrows()

func testSetPromptsFolderCreatesBothSubfoldersAndListsFiles() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)

        var isDirectory: ObjCBool = false
        checks += 1
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("Texte").path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            failures += 1
            print("FAIL [setPromptsFolder creates Texte subfolder]")
        }
        checks += 1
        if !FileManager.default.fileExists(atPath: root.appendingPathComponent("Soundtrack").path, isDirectory: &isDirectory) || !isDirectory.boolValue {
            failures += 1
            print("FAIL [setPromptsFolder creates Soundtrack subfolder]")
        }
        check(session.textPromptFiles, [], "setPromptsFolder starts with no text prompt files")
        check(session.soundTrackPromptFiles, [], "setPromptsFolder starts with no soundtrack prompt files")
    } catch {
        failures += 1
        print("FAIL [setPromptsFolder creates subfolders and lists files]: threw \(error)")
    }
}
testSetPromptsFolderCreatesBothSubfoldersAndListsFiles()

func testSaveAndUseTextCompositionPromptRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSourceText("a poem about the sea")

        try session.saveTextCompositionPrompt(as: "my-prompt")
        check(session.textPromptFiles, ["my-prompt.txt"], "saveTextCompositionPrompt adds the file to textPromptFiles")

        session.setSourceText("a totally different poem")
        checkNil(session.activeTextCompositionPrompt, "no override active before useTextCompositionPrompt")
        try session.useTextCompositionPrompt(atIndex: 0)
        checks += 1
        if !(session.activeTextCompositionPrompt?.contains("a poem about the sea") ?? false) {
            failures += 1
            print("FAIL [useTextCompositionPrompt loads the saved prompt]: \(session.activeTextCompositionPrompt ?? "nil")")
        }
        checks += 1
        if !(try session.currentTextCompositionPrompt()).contains("a poem about the sea") {
            failures += 1
            print("FAIL [currentTextCompositionPrompt prefers the active override over sourceText]")
        }

        session.resetTextCompositionPrompt()
        checkNil(session.activeTextCompositionPrompt, "resetTextCompositionPrompt clears the override")
        checks += 1
        if !(try session.currentTextCompositionPrompt()).contains("a totally different poem") {
            failures += 1
            print("FAIL [currentTextCompositionPrompt rebuilds from sourceText after reset]")
        }
    } catch {
        failures += 1
        print("FAIL [save and use text composition prompt round trips]: threw \(error)")
    }
}
testSaveAndUseTextCompositionPromptRoundTrips()

func testSaveAndUseSoundTrackCompositionPromptRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        try session.startRecording(title: "ForPrompt")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.saveSoundTrackCompositionPrompt(as: "my-soundtrack-prompt")
        check(session.soundTrackPromptFiles, ["my-soundtrack-prompt.txt"], "saveSoundTrackCompositionPrompt adds the file to soundTrackPromptFiles")

        try session.useSoundTrackCompositionPrompt(named: "my-soundtrack-prompt.txt")
        checkNotNil(session.activeSoundTrackCompositionPrompt, "useSoundTrackCompositionPrompt sets the active override")

        session.resetSoundTrackCompositionPrompt()
        checkNil(session.activeSoundTrackCompositionPrompt, "resetSoundTrackCompositionPrompt clears the override")
    } catch {
        failures += 1
        print("FAIL [save and use soundtrack composition prompt round trips]: threw \(error)")
    }
}
testSaveAndUseSoundTrackCompositionPromptRoundTrips()

func testUseTextCompositionPromptWithInvalidIndexThrows() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checks += 1
        do {
            try session.useTextCompositionPrompt(atIndex: 0)
            failures += 1
            print("FAIL [useTextCompositionPrompt invalid index throws]: did not throw")
        } catch let error as ImprovSession.SessionError {
            if error != .invalidTextPromptIndex {
                failures += 1
                print("FAIL [useTextCompositionPrompt invalid index throws]: wrong error \(error)")
            }
        }
    } catch {
        failures += 1
        print("FAIL [use text composition prompt with invalid index]: threw \(error)")
    }
}
testUseTextCompositionPromptWithInvalidIndexThrows()

func testComposeFromTextUsesTheActiveOverridePromptVerbatim() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.setPromptsFolder(folder.path)
        session.setSourceText("ignored once a prompt override is active")
        try session.saveTextCompositionPrompt(as: "custom")
        session.setSourceText("also ignored")
        try session.useTextCompositionPrompt(named: "custom.txt")

        let fakeResponse = """
        { "title": "Override", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { prompt, _ in
            checks += 1
            if !prompt.contains("ignored once a prompt override is active") || prompt.contains("also ignored") {
                failures += 1
                print("FAIL [composeFromText uses the active override prompt verbatim]: \(prompt)")
            }
            return fakeResponse
        }
        check(session.piece?.title, "Override", "composeFromText with an active override still composes correctly")
    } catch {
        failures += 1
        print("FAIL [compose from text uses active override prompt]: threw \(error)")
    }
}
testComposeFromTextUsesTheActiveOverridePromptVerbatim()

func testSaveThenLoadRoundTripsThePieceThroughJSON() {
    let session = ImprovSession()
    session.loadDemoPiece()
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: tempFile) }
    do {
        try session.savePiece(toJSONFile: tempFile.path)
        let reloadedSession = ImprovSession()
        try reloadedSession.loadPiece(fromJSONFile: tempFile.path)
        check(reloadedSession.piece, session.piece, "improv session save/load round trips through JSON")
    } catch {
        checks += 1
        failures += 1
        print("FAIL [improv session save/load round trip]: threw \(error)")
    }
}

func testLoadingAMissingFileThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.loadPiece(fromJSONFile: "/no/such/file.json")
        failures += 1
        print("FAIL [improv session load missing file throws]: did not throw")
    } catch {
        // expected
    }
}

func testListPieceFilesFindsJSONFilesAndIgnoresOthers() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("b.json"))
        try Data().write(to: folder.appendingPathComponent("a.json"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = ImprovSession()
        try session.listPieceFiles(in: folder.path)
        if session.pieceFiles != ["a.json", "b.json"] {
            failures += 1
            print("FAIL [list piece files finds json, ignores others]: \(session.pieceFiles)")
        }
    } catch {
        failures += 1
        print("FAIL [list piece files finds json, ignores others]: threw \(error)")
    }
}

func testUsePieceByIndexAndNameLoadFromTheListedFolder() {
    checks += 2
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = ImprovSession()
        writer.loadDemoPiece()
        try writer.savePiece(toJSONFile: folder.appendingPathComponent("demo.json").path)

        let session = ImprovSession()
        try session.listPieceFiles(in: folder.path)
        try session.loadPiece(atIndex: 0)
        if session.piece?.title != "ii-V-I demo" {
            failures += 1
            print("FAIL [use-piece by index]: \(String(describing: session.piece?.title))")
        }

        let byName = ImprovSession()
        try byName.listPieceFiles(in: folder.path)
        try byName.loadPiece(named: "demo.json")
        if byName.piece?.title != "ii-V-I demo" {
            failures += 1
            print("FAIL [use-piece by name]: \(String(describing: byName.piece?.title))")
        }
    } catch {
        failures += 2
        print("FAIL [use-piece by index/name]: threw \(error)")
    }
}

func testSaveWithoutEverLoadingOrSavingThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.savePiece()
        failures += 1
        print("FAIL [bare save without a current file throws]: did not throw")
    } catch {
        // expected
    }
}

func testSaveAsThenBareSaveRoundTripToTheSameFile() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = ImprovSession()
        session.loadDemoPiece()
        try session.listPieceFiles(in: folder.path)
        try session.savePiece(as: "my-piece")

        let expectedPath = folder.appendingPathComponent("my-piece.json").path
        if session.currentPieceFilePath != expectedPath || !FileManager.default.fileExists(atPath: expectedPath) {
            failures += 1
            print("FAIL [save-as then bare save]: currentPieceFilePath=\(String(describing: session.currentPieceFilePath))")
        }
        try session.savePiece() // re-save to the same resolved path, should not throw
    } catch {
        failures += 1
        print("FAIL [save-as then bare save]: threw \(error)")
    }
}

func testSaveAsWithoutAPieceFolderListedThrowsForABareName() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.savePiece(as: "my-piece")
        failures += 1
        print("FAIL [save-as bare name without folder throws]: did not throw")
    } catch {
        // expected
    }
}

// MARK: - RecognitionEngineTests (mirrors Tests/RecognitionEngineTests/RecognitionEngineTests.swift)

func testRecognizesBareMajorTriadAsATriadNotA7thChord() {
    let engine = RecognitionEngine()
    for pitch in [60, 64, 67] { engine.noteOn(pitch: pitch) } // C E G
    let chord = engine.recognizeChord()
    check(chord?.root, PitchClass(0), "recognition triad root")
    check(chord?.chordTemplateID, "Ma", "recognition triad template")
    check(chord?.confidence, 1.0, "recognition triad confidence")
}

func testRecognizesRootPositionSeventhChord() {
    let engine = RecognitionEngine()
    for pitch in [60, 64, 67, 71] { engine.noteOn(pitch: pitch) } // C E G B -> Cmaj7
    let chord = engine.recognizeChord()
    check(chord?.root, PitchClass(0), "recognition chord root")
    check(chord?.chordTemplateID, "Ma7", "recognition chord template")
    check(chord?.confidence, 1.0, "recognition chord confidence")
}

func testRecognizesChordRegardlessOfOctaveOrOrder() {
    let engine = RecognitionEngine()
    for pitch in [38, 53, 69, 72] { engine.noteOn(pitch: pitch) } // D2 F3 A4 C5 -> Dm7, spread octaves
    let chord = engine.recognizeChord()
    check(chord?.root, PitchClass(2), "recognition chord root across octaves")
    check(chord?.chordTemplateID, "mi7", "recognition chord template across octaves")
}

func testReleasingANoteUpdatesTheHeldChord() {
    let engine = RecognitionEngine()
    for pitch in [60, 64, 67, 71] { engine.noteOn(pitch: pitch) }
    engine.noteOff(pitch: 71) // drop the 7th -> now a bare C major triad
    let chord = engine.recognizeChord(minimumConfidence: 0.9)
    check(chord?.chordTemplateID, "Ma", "recognition retains triad after note-off")
    check(chord?.confidence, 1.0, "recognition triad confidence after note-off")
}

func testFewerThanTwoHeldNotesRecognizesNoChord() {
    let engine = RecognitionEngine()
    engine.noteOn(pitch: 60)
    checkNil(engine.recognizeChord(), "recognition needs at least two held notes")
}

func testRecognizesCMajorFromItsScaleNotes() {
    let engine = RecognitionEngine()
    let base = Date()
    for (i, pitch) in [60, 62, 64, 65, 67, 69, 71].enumerated() {
        engine.noteOn(pitch: pitch, at: base.addingTimeInterval(Double(i) * 0.1))
    }
    let modes = engine.recognizeModes(at: base.addingTimeInterval(0.7))
    checks += 1
    if !modes.contains(where: { $0.tonic == PitchClass(0) && $0.scaleID == "ionian" }) {
        failures += 1
        print("FAIL [recognition C major from scale notes]: \(modes)")
    }
}

func testDecayMakesOldNotesStopCounting() {
    let engine = RecognitionEngine(modeHalfLife: 1.0)
    let base = Date()
    for (i, pitch) in [60, 62, 64, 65, 67, 69, 71].enumerated() {
        engine.noteOn(pitch: pitch, at: base.addingTimeInterval(Double(i) * 0.1))
    }
    engine.noteOn(pitch: 66, at: base.addingTimeInterval(30))
    let modes = engine.recognizeModes(at: base.addingTimeInterval(30), activityThreshold: 0.01)
    checks += 1
    if modes.contains(where: { $0.tonic == PitchClass(0) && $0.scaleID == "ionian" }) {
        failures += 1
        print("FAIL [recognition decay drops stale notes]: \(modes)")
    }
}

func testNoRecentActivityRecognizesNoModes() {
    let engine = RecognitionEngine()
    check(engine.recognizeModes(), [], "recognition with no activity yields no modes")
}

func testResetClearsHeldNotesAndHistory() {
    let engine = RecognitionEngine()
    engine.noteOn(pitch: 60)
    engine.noteOn(pitch: 64)
    engine.reset()
    checkNil(engine.recognizeChord(), "recognition reset clears chord")
    check(engine.recognizeModes(activityThreshold: 0), [], "recognition reset clears mode history")
}

// MARK: - LLMPieceComposerTests (mirrors Tests/LLMEngineTests/LLMPieceComposerTests.swift)

func testParsesNaturalNoteNames() {
    check(parsePitchClass("C"), 0, "parsePitchClass C")
    check(parsePitchClass("D"), 2, "parsePitchClass D")
    check(parsePitchClass("B"), 11, "parsePitchClass B")
}

func testParsesSharpsAndFlats() {
    check(parsePitchClass("C#"), 1, "parsePitchClass C#")
    check(parsePitchClass("Db"), 1, "parsePitchClass Db")
    check(parsePitchClass("Cb"), 11, "parsePitchClass Cb")
    check(parsePitchClass("B#"), 0, "parsePitchClass B#")
}

func testRejectsGarbagePitchClass() {
    checkNil(parsePitchClass("H"), "parsePitchClass rejects H")
    checkNil(parsePitchClass(""), "parsePitchClass rejects empty")
    checkNil(parsePitchClass("C##"), "parsePitchClass rejects C##")
}

func testExtractJSONStripsMarkdownFence() {
    let fenced = "```json\n{\"a\":1}\n```"
    check(LLMPieceComposer.extractJSON(from: fenced), "{\"a\":1}", "extractJSON strips fence")
}

func minimalValidDTOJSON(chords: String = "[{\"measure\":1,\"root\":\"D\",\"templateID\":\"mi7\"}]") -> String {
    """
    { "title": "Test", "tempoBPM": 100, "tonic": "C", "scaleID": "ionian",
      "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "C", "scaleID": "ionian", "chords": \(chords) } ] }
    """
}

func testValidResponseProducesAPiece() {
    let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: minimalValidDTOJSON())
    check(piece?.title, "Test", "llm compose valid response title")
    check(piece?.key, ModeReference(tonic: 0, scaleID: "ionian"), "llm compose valid response key")
    check(piece?.sections.first?.chordProgression.first?.chord, ChordReference(root: 2, chordTemplateID: "mi7"), "llm compose valid response chord")
    check(warnings, [], "llm compose valid response has no warnings")
}

func testInvalidTopLevelKeyRejectsEverything() {
    let json = "{ \"title\": \"T\", \"tempoBPM\": 100, \"tonic\": \"Z\", \"scaleID\": \"not-real\", \"sections\": [] }"
    let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
    checkNil(piece, "llm compose invalid key rejects everything")
    checks += 1
    if warnings.isEmpty {
        failures += 1
        print("FAIL [llm compose invalid key has warnings]: empty")
    }
}

func testInvalidChordIsDroppedButValidOnesSurvive() {
    let json = minimalValidDTOJSON(chords: "[{\"measure\":1,\"root\":\"D\",\"templateID\":\"mi7\"},{\"measure\":2,\"root\":\"Q\",\"templateID\":\"nope\"}]")
    let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
    check(piece?.sections.first?.chordProgression.count, 1, "llm compose drops invalid chord, keeps valid")
    checks += 1
    if !warnings.contains(where: { $0.contains("dropped chord") }) {
        failures += 1
        print("FAIL [llm compose warns about dropped chord]: \(warnings)")
    }
}

func testSectionWithNoValidChordsIsDropped() {
    let json = minimalValidDTOJSON(chords: "[{\"measure\":1,\"root\":\"Z\",\"templateID\":\"nope\"}]")
    let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
    checkNil(piece, "llm compose section with no valid chords is dropped")
    checks += 1
    if !warnings.contains(where: { $0.contains("no valid chords") }) {
        failures += 1
        print("FAIL [llm compose warns about no valid chords]: \(warnings)")
    }
}

func testMelodyNotesOutOfMIDIRangeAreDropped() {
    let json = """
    { "title": "Test", "tempoBPM": 100, "tonic": "C", "scaleID": "ionian",
      "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "C", "scaleID": "ionian",
        "chords": [{"measure":1,"root":"C","templateID":"Ma7"}],
        "melody": [{"measure":1,"beat":1,"durationBeats":1,"pitch":60},{"measure":1,"beat":2,"durationBeats":1,"pitch":200}]
      } ] }
    """
    let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: json)
    check(piece?.sections.first?.tracks.first?.melodyEvents.count, 1, "llm compose drops out-of-range melody note")
    checks += 1
    if !warnings.contains(where: { $0.contains("out-of-range") }) {
        failures += 1
        print("FAIL [llm compose warns about out-of-range note]: \(warnings)")
    }
}

func testTempoIsClampedToAReasonableRange() {
    let json = """
    { "title": "T", "tempoBPM": 999, "tonic": "C", "scaleID": "ionian",
      "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "C", "scaleID": "ionian",
        "chords": [{"measure":1,"root":"C","templateID":"Ma7"}] } ] }
    """
    let (piece, _) = LLMPieceComposer.parseAndValidate(responseText: json)
    check(piece?.tempoBPM, 240, "llm compose clamps tempo")
}

func testUnparsableJSONReturnsNilWithAWarning() {
    let (piece, warnings) = LLMPieceComposer.parseAndValidate(responseText: "not json at all")
    checkNil(piece, "llm compose unparsable json returns nil")
    checks += 1
    if warnings.isEmpty {
        failures += 1
        print("FAIL [llm compose unparsable json has warnings]: empty")
    }
}

func testBuildPromptEmbedsSourceTextAndVocabulary() {
    let prompt = LLMPieceComposer.buildPrompt(sourceText: "Roses are red")
    checks += 3
    if !prompt.contains("Roses are red") { failures += 1; print("FAIL [prompt contains source text]") }
    if !prompt.contains("ionian") { failures += 1; print("FAIL [prompt contains scale vocabulary]") }
    if !prompt.contains("Ma7") { failures += 1; print("FAIL [prompt contains chord vocabulary]") }
}

// MARK: - Run

testChordVocabularySizeIncludesTriads()
testChordVocabularyCMajorTriad()

testParsesNaturalNoteNames()
testParsesSharpsAndFlats()
testRejectsGarbagePitchClass()
testExtractJSONStripsMarkdownFence()
testValidResponseProducesAPiece()
testInvalidTopLevelKeyRejectsEverything()
testInvalidChordIsDroppedButValidOnesSurvive()
testSectionWithNoValidChordsIsDropped()
testMelodyNotesOutOfMIDIRangeAreDropped()
testTempoIsClampedToAReasonableRange()
testUnparsableJSONReturnsNilWithAWarning()
testBuildPromptEmbedsSourceTextAndVocabulary()

testResolveValidScaleIDMatchesDirectConstruction()
testResolveUnknownScaleIDReturnsNil()
testChordReferenceResolveValidTemplateID()
testChordReferenceResolveUnknownTemplateIDReturnsNil()
testModeTransitionStoresItsFields()

testChordEventDefaultsAndFields()
testChordEventDistinctInstancesGetDistinctIDsByDefault()
testMelodyEventDefaultVelocity()
testFragmentPlacementResolvedFragmentAppliesNoTransformsByDefault()
testFragmentPlacementResolvedFragmentAppliesTransformsInOrder()

testAbsoluteBeatAtStartOfSectionIsZero()
testAbsoluteBeatAdvancesByFullMeasures()
testAbsoluteBeatWithinMeasureOffset()
testScheduledNotesFromMelodyEventsAreConvertedAndSorted()
testScheduledNotesFromFragmentPlacementResolvesTransformsAndAdvancesCursor()
testScheduledNotesSkipsFragmentPlacementsWithUnknownFragmentID()
testScheduledNotesMergesAndSortsMelodyEventsAndFragmentPlacements()
testScheduledNotesCarryTheTracksInstrumentName()
testScheduledNotesTreatAnEmptyInstrumentAsDefault()

testChordScheduledNotesSimultaneousDefaultIsRootPosition()
testChordScheduledNotesFirstInversionMovesRootUpAnOctave()
testChordScheduledNotesBassOverrideAddsSlashBassBelowChord()
testChordScheduledNotesArpeggioUpSpreadsNotesAcrossDuration()
testChordScheduledNotesUnknownTemplateProducesNoNotes()
testChordScheduledNotesCarryTheSectionsChordInstrument()
testChordScheduledNotesDefaultChordInstrumentIsNil()
testPieceRenderedNotesCombinesChordsAndTracksInSeconds()
testPieceRenderedNotesCarryDistinctInstrumentNamesForChordsAndTracks()
testPieceRenderedNotesOffsetsSecondSectionByFirstSectionsLength()
testHarmonicTimelineResolvesOneChordPerEventInSeconds()
testHarmonicTimelineOffsetsSecondSectionAndCarriesItsOwnMode()
testHarmonicTimelineEmptyForAPieceWithNoChords()

testFragmentLookupByIDFindsMatch()
testFragmentLookupByIDReturnsNilWhenMissing()
testPieceRoundTripsThroughJSON()

testMelodicFragmentAbsolutePitchesAndTransforms()

testMIDIParsesNoteOn()
testMIDIParsesNoteOnOnNonZeroChannel()
testMIDIParsesNoteOff()
testMIDINoteOnWithZeroVelocityIsTreatedAsNoteOff()
testMIDIParsesMultipleMessagesInOneBuffer()
testMIDIIgnoresNonNoteMessages()
testMIDITruncatedTrailingMessageIsDropped()
testMIDIEmptyBufferProducesNoEvents()

testLoadDemoPieceSetsPieceAndLogsIt()
testPlayWithoutAPieceLoadedThrows()
testPlayTracksPlaybackStateSynchronouslyThenClearsItWhenFinished()
testSetPieceTrackInstrumentUpdatesTrackAndLogs()
testSetPieceTrackInstrumentNilRevertsToEmptyString()
testSetPieceTrackInstrumentWithInvalidSectionIndexThrows()
testSetPieceTrackInstrumentWithInvalidTrackIndexThrows()
testSetPieceChordInstrumentUpdatesSectionAndLogs()
testSetPieceChordInstrumentWithInvalidSectionIndexThrows()
testPlayWarnsWhenATracksInstrumentFileIsNotFound()
testPlayWithoutAnyTrackInstrumentLogsNoInstrumentWarning()
testStartTrackOnAnUnlistedMIDIPortThrows()
testDefaultMIDIFusionModeIsMergedWithASingleMIDITrack()
testSetMIDIFusionModeSwitchesTrackList()
testMicrophoneTrackCannotHaveSound()
testSaveThenLoadRoundTripsThePieceThroughJSON()
testLoadingAMissingFileThrows()
testListPieceFilesFindsJSONFilesAndIgnoresOthers()
testUsePieceByIndexAndNameLoadFromTheListedFolder()
testSaveWithoutEverLoadingOrSavingThrows()
testSaveAsThenBareSaveRoundTripToTheSameFile()
testSaveAsWithoutAPieceFolderListedThrowsForABareName()

testRecognizesBareMajorTriadAsATriadNotA7thChord()
testRecognizesRootPositionSeventhChord()
testRecognizesChordRegardlessOfOctaveOrOrder()
testReleasingANoteUpdatesTheHeldChord()
testFewerThanTwoHeldNotesRecognizesNoChord()
testRecognizesCMajorFromItsScaleNotes()
testDecayMakesOldNotesStopCounting()
testNoRecentActivityRecognizesNoModes()
testResetClearsHeldNotesAndHistory()

func testHandlingIncomingMIDIEventsDetectsChordPerTrack() {
    checks += 1
    do {
        let session = ImprovSession()
        // Sound stays off on this track, so this never touches the (unstarted) audio engine.
        try session.startTrack(.midiMerged)
        for pitch in [60, 64, 67, 71] {
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0), track: .midiMerged)
        }
        let recognizedChord = session.tracks.first { $0.id == .midiMerged }?.recognizedChord
        if recognizedChord?.root != PitchClass(0) || recognizedChord?.chordTemplateID != "Ma7" {
            failures += 1
            print("FAIL [session handles MIDI events, detects chord]: \(String(describing: recognizedChord))")
        }
        session.stopTrack(.midiMerged)
        let chordAfterStop = session.tracks.first { $0.id == .midiMerged }?.recognizedChord
        if chordAfterStop != nil {
            failures += 1
            print("FAIL [session clears chord on stopTrack]: \(String(describing: chordAfterStop))")
        }
    } catch {
        failures += 1
        print("FAIL [session handles MIDI events, detects chord]: threw \(error)")
    }
}
testHandlingIncomingMIDIEventsDetectsChordPerTrack()

func testNewPieceStartsBlank() {
    let session = ImprovSession()
    session.newPiece(title: "My Poem Piece")
    check(session.piece?.title, "My Poem Piece", "new piece title")
    check(session.piece?.sections, [], "new piece starts with no sections")
    checkNil(session.currentPieceFilePath, "new piece has no current file")
}

func testSetSourceTextStoresItAndLogs() {
    let session = ImprovSession()
    session.setSourceText("Roses are red")
    check(session.sourceText, "Roses are red", "source text stored")
    checks += 1
    if !session.log.contains(where: { $0.contains("Source text set") }) {
        failures += 1
        print("FAIL [source text logs it]: \(session.log)")
    }
}

func testListLLMConnectionsFindsJSONFiles() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        if session.llmConnections != ["ollama.json"] {
            failures += 1
            print("FAIL [list llm connections finds json]: \(session.llmConnections)")
        }
    } catch {
        failures += 1
        print("FAIL [list llm connections finds json]: threw \(error)")
    }
}

func testUseLLMConnectionByIndexAndNameLoadFromTheListedFolder() {
    checks += 2
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        if session.currentLLMConnection != connection {
            failures += 1
            print("FAIL [use-llm by index]: \(String(describing: session.currentLLMConnection))")
        }

        let byName = ImprovSession()
        try byName.listLLMConnections(in: folder.path)
        try byName.useLLMConnection(named: "ollama.json")
        if byName.currentLLMConnection != connection {
            failures += 1
            print("FAIL [use-llm by name]: \(String(describing: byName.currentLLMConnection))")
        }
    } catch {
        failures += 2
        print("FAIL [use-llm by index/name]: threw \(error)")
    }
}

func testComposeFromTextWithoutSourceTextThrows() {
    checks += 1
    do {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "x", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("x.json"))
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        try session.composeFromText()
        failures += 1
        print("FAIL [compose without source text throws]: did not throw")
    } catch let error as ImprovSession.SessionError where error == .noSourceText {
        // expected
    } catch {
        failures += 1
        print("FAIL [compose without source text throws]: wrong error \(error)")
    }
}

func testComposeFromTextWithoutAConnectionThrows() {
    let session = ImprovSession()
    session.setSourceText("a poem")
    checks += 1
    do {
        try session.composeFromText()
        failures += 1
        print("FAIL [compose without connection throws]: did not throw")
    } catch let error as ImprovSession.SessionError where error == .noLLMConnectionSelected {
        // expected
    } catch {
        failures += 1
        print("FAIL [compose without connection throws]: wrong error \(error)")
    }
}

func testComposeFromTextWithAFakeGeneratorProducesAValidatedPiece() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "The Sea", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { _, _ in fakeResponse }

        if session.piece?.title != "The Sea" {
            failures += 1
            print("FAIL [compose with fake generator]: \(String(describing: session.piece?.title))")
        }
    } catch {
        failures += 1
        print("FAIL [compose with fake generator]: threw \(error)")
    }
}

func testComposeFromTextWithInvalidResponseThrowsWithWarnings() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        try session.composeFromText { _, _ in "not json at all" }
        failures += 1
        print("FAIL [compose with invalid response throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if case .llmComposeFailed = error {
            // expected
        } else {
            failures += 1
            print("FAIL [compose with invalid response throws llmComposeFailed]: got \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [compose with invalid response throws]: threw \(error)")
    }
}

func testComposeFromTextWithATitleOverridesTheLLMsOwnTitle() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "LLM Chosen Title", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText(title: "My Own Title") { _, _ in fakeResponse }
        check(session.piece?.title, "My Own Title", "composeFromText title override wins over the LLM's own title")
    } catch {
        failures += 1
        print("FAIL [compose from text with title override]: threw \(error)")
    }
}
testComposeFromTextWithATitleOverridesTheLLMsOwnTitle()

func testSetAdditionalCompositionInstructionsAreIncludedInThePrompt() {
    do {
        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        let prompt = try session.currentTextCompositionPrompt()
        checks += 1
        if !prompt.contains("romantique, mode mineur") || !prompt.contains("a poem about the sea") {
            failures += 1
            print("FAIL [additional composition instructions included in prompt]: \(prompt)")
        }
    } catch {
        failures += 1
        print("FAIL [additional composition instructions included in prompt]: threw \(error)")
    }
}
testSetAdditionalCompositionInstructionsAreIncludedInThePrompt()

func testSetAdditionalCompositionInstructionsEmptyStringClearsThem() {
    let session = ImprovSession()
    session.setAdditionalCompositionInstructions("romantique")
    check(session.additionalCompositionInstructions, "romantique", "setAdditionalCompositionInstructions stores the text")
    session.setAdditionalCompositionInstructions("")
    checkNil(session.additionalCompositionInstructions, "setAdditionalCompositionInstructions('') clears them")
}
testSetAdditionalCompositionInstructionsEmptyStringClearsThem()

func testSetCompositionTitleEmptyStringClearsIt() {
    let session = ImprovSession()
    session.setCompositionTitle("Ma Ballade")
    check(session.compositionTitle, "Ma Ballade", "setCompositionTitle stores the title")
    session.setCompositionTitle("")
    checkNil(session.compositionTitle, "setCompositionTitle('') clears it")
    session.setCompositionTitle(nil)
    checkNil(session.compositionTitle, "setCompositionTitle(nil) clears it")
}
testSetCompositionTitleEmptyStringClearsIt()

func testComposeFromTextSendsAdditionalInstructionsInThePrompt() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "The Sea", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { prompt, _ in
            checks += 1
            if !prompt.contains("romantique, mode mineur") {
                failures += 1
                print("FAIL [compose from text sends additional instructions]: \(prompt)")
            }
            return fakeResponse
        }
    } catch {
        failures += 1
        print("FAIL [compose from text sends additional instructions]: threw \(error)")
    }
}
testComposeFromTextSendsAdditionalInstructionsInThePrompt()

testNewPieceStartsBlank()
testSetSourceTextStoresItAndLogs()
testListLLMConnectionsFindsJSONFiles()
testUseLLMConnectionByIndexAndNameLoadFromTheListedFolder()
testComposeFromTextWithoutSourceTextThrows()
testComposeFromTextWithoutAConnectionThrows()
testComposeFromTextWithAFakeGeneratorProducesAValidatedPiece()
testComposeFromTextWithInvalidResponseThrowsWithWarnings()

// MARK: - LLMProviderTests (mirrors Tests/LLMEngineTests/LLMProviderTests.swift)

func testAnthropicProviderThrowsMissingAPIKeyWhenConnectionHasNoEnvVar() {
    checks += 1
    let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8")
    do {
        _ = try AnthropicProvider().generate(prompt: "hello", connection: connection)
        failures += 1
        print("FAIL [anthropic no envVar throws]: did not throw")
    } catch LLMError.missingAPIKey(let envVar) where envVar == "ANTHROPIC_API_KEY" {
        // expected
    } catch {
        failures += 1
        print("FAIL [anthropic no envVar throws]: wrong error \(error)")
    }
}

func testAnthropicProviderThrowsMissingAPIKeyWhenEnvVarIsUnset() {
    checks += 1
    let envVar = "ANTHROPIC_API_KEY_DOES_NOT_EXIST_IN_ENVIRONMENT"
    let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8", apiKeyEnvVar: envVar)
    do {
        _ = try AnthropicProvider().generate(prompt: "hello", connection: connection)
        failures += 1
        print("FAIL [anthropic unset envVar throws]: did not throw")
    } catch LLMError.missingAPIKey(let reportedVar) where reportedVar == envVar {
        // expected
    } catch {
        failures += 1
        print("FAIL [anthropic unset envVar throws]: wrong error \(error)")
    }
}

func testLLMClientDispatchesAnthropicProviderByName() {
    checks += 1
    let connection = LLMConnection(name: "Claude", provider: "anthropic", baseURL: "https://api.anthropic.com", model: "claude-opus-4-8")
    do {
        _ = try LLMClient.generate(prompt: "hello", connection: connection)
        failures += 1
        print("FAIL [LLMClient dispatches anthropic]: did not throw")
    } catch LLMError.missingAPIKey {
        // expected — proves the anthropic case ran instead of falling through
    } catch {
        failures += 1
        print("FAIL [LLMClient dispatches anthropic]: wrong error \(error)")
    }
}

func testLLMClientThrowsUnsupportedProviderForUnknownName() {
    checks += 1
    let connection = LLMConnection(name: "Mystery", provider: "mystery-provider", baseURL: "https://example.com", model: "x")
    do {
        _ = try LLMClient.generate(prompt: "hello", connection: connection)
        failures += 1
        print("FAIL [LLMClient unsupported provider throws]: did not throw")
    } catch LLMError.unsupportedProvider(let provider) where provider == "mystery-provider" {
        // expected
    } catch {
        failures += 1
        print("FAIL [LLMClient unsupported provider throws]: wrong error \(error)")
    }
}

func testUnsupportedProviderDescriptionMentionsAnthropic() {
    check(LLMError.unsupportedProvider("x").description.contains("anthropic"), true, "unsupportedProvider description mentions anthropic")
}

testAnthropicProviderThrowsMissingAPIKeyWhenConnectionHasNoEnvVar()
testAnthropicProviderThrowsMissingAPIKeyWhenEnvVarIsUnset()
testLLMClientDispatchesAnthropicProviderByName()
testLLMClientThrowsUnsupportedProviderForUnknownName()
testUnsupportedProviderDescriptionMentionsAnthropic()

testFFTDetectsA440SineWave()
testFFTDetectsMiddleCSineWave()
testFFTReturnsNilForSilence()
testFFTReturnsNilForLowAmplitudeNoise()
testFFTReturnsNilWhenSampleCountDoesNotMatchSize()
testFFTRespectsMinAndMaxHzRange()
testMidiPitchFromFrequencyMatchesKnownNotes()
testRMSOfSilenceIsZero()
testRMSOfFullScaleSineIsAboutOneOverSqrtTwo()
testRMSScalesWithAmplitude()
testDetectsAllThreeNotesOfACMajorTriad()
testDominantFrequenciesReturnsEmptyForSilence()
testDominantFrequenciesRespectsMaxPeaks()
testDominantFrequenciesMergesPeaksCloserThanMinSemitoneSeparation()
testDominantFrequencyMatchesFirstOfDominantFrequencies()

print("\(checks) checks, \(failures) failures")
if failures > 0 {
    exit(1)
}
