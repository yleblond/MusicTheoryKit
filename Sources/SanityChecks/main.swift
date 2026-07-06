import MusicTheoryKit
import PieceModel
import MIDIEngine
@testable import AppCore
import RecognitionEngine
import Foundation

// Stand-in for the real XCTest suites in Tests/PieceModelTests (which this file mirrors
// case-for-case): this machine has no Xcode, only Command Line Tools, so `swift test`
// fails with "no such module 'XCTest'". Run with `swift run SanityChecks`. If you ever
// install full Xcode, prefer `swift test` (or Xcode's test navigator) and let this file
// go stale — it's a workaround, not a replacement.

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

// MARK: - Run

testChordVocabularySizeIncludesTriads()
testChordVocabularyCMajorTriad()

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

testChordScheduledNotesSimultaneousDefaultIsRootPosition()
testChordScheduledNotesFirstInversionMovesRootUpAnOctave()
testChordScheduledNotesBassOverrideAddsSlashBassBelowChord()
testChordScheduledNotesArpeggioUpSpreadsNotesAcrossDuration()
testChordScheduledNotesUnknownTemplateProducesNoNotes()
testPieceRenderedNotesCombinesChordsAndTracksInSeconds()
testPieceRenderedNotesOffsetsSecondSectionByFirstSectionsLength()

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
testSaveThenLoadRoundTripsThePieceThroughJSON()
testLoadingAMissingFileThrows()

testRecognizesBareMajorTriadAsATriadNotA7thChord()
testRecognizesRootPositionSeventhChord()
testRecognizesChordRegardlessOfOctaveOrOrder()
testReleasingANoteUpdatesTheHeldChord()
testFewerThanTwoHeldNotesRecognizesNoChord()
testRecognizesCMajorFromItsScaleNotes()
testDecayMakesOldNotesStopCounting()
testNoRecentActivityRecognizesNoModes()
testResetClearsHeldNotesAndHistory()

func testHandlingIncomingMIDIEventsDetectsChordWhileListenOnly() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.startListening(listenOnly: true)
        for pitch in [60, 64, 67, 71] {
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0))
        }
        if session.recognizedChord?.root != PitchClass(0) || session.recognizedChord?.chordTemplateID != "Ma7" {
            failures += 1
            print("FAIL [session handles MIDI events, detects chord]: \(String(describing: session.recognizedChord))")
        }
        session.stopListening()
        if session.recognizedChord != nil {
            failures += 1
            print("FAIL [session clears chord on stopListening]: \(String(describing: session.recognizedChord))")
        }
    } catch {
        failures += 1
        print("FAIL [session handles MIDI events, detects chord]: threw \(error)")
    }
}
testHandlingIncomingMIDIEventsDetectsChordWhileListenOnly()

print("\(checks) checks, \(failures) failures")
if failures > 0 {
    exit(1)
}
