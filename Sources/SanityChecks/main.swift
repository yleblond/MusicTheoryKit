import MusicTheoryKit
import PieceModel
@testable import AudioEngine
import MIDIEngine
@testable import AppCore
import RecognitionEngine
@testable import LLMEngine
@testable import NetEngine
@testable import SoundTrackModel
@testable import WebConsole
import Localization
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

// MARK: - CircleOfFifths / PitchClassPalette

func testCircleOfFifthsPhysicalOrderIsFixedAscendingFifthsFromC() {
    let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
    check(wheel.columns.map { $0.pitchClass.value }, [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5], "circle of fifths physical column order (C,G,D,A,E,B,F#,Db,Ab,Eb,Bb,F)")
}

func testCircleOfFifthsCTonicModeNamePositions() {
    let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
    let named = wheel.columns.filter { $0.modeName != nil }
    // NOT the 7 diatonic columns (see `CircleOfFifthsColumn.modeName`'s doc comment): each
    // mode name sits at "the interval up to its own parent" from the tonic, so only I/IV/V
    // (Ionian/Lydian/Mixolydian) coincide with a diatonic column here — Locrian/Phrygian/
    // Aeolian/Dorian land on Db/Ab/Eb/Bb, none of which are diatonic to C major.
    check(named.map { $0.pitchClass.value }, [0, 7, 1, 8, 3, 10, 5], "circle of fifths C tonic mode-name columns in physical order (C,G,Db,Ab,Eb,Bb,F)")
    check(named.map(\.modeName), ["Ionian", "Lydian", "Locrian", "Phrygian", "Aeolian", "Dorian", "Mixolydian"], "circle of fifths C tonic mode names")
    check(wheel.activeColumnIndex, 0, "circle of fifths C tonic active column is C itself")
}

func testCircleOfFifthsCTonicDiatonicCellsMatchExpectedQualityAndDegree() {
    let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
    // Looked up by the CELL's own chord root (not its column's pitch class) — only the major
    // ring is rooted on its column; minor/diminished are the column's relative-minor/
    // leading-tone-diminished (see `CircleOfFifthsCell`'s doc comment).
    func cell(_ root: Int, _ quality: ChordQuality) -> CircleOfFifthsCell {
        wheel.columns.flatMap(\.cells).first { $0.pitchClass.value == root && $0.quality == quality }!
    }
    check(cell(0, .major).relativeDegree, "I", "circle of fifths C major cell is I")
    check(cell(0, .major).isDiatonic, true, "circle of fifths C major cell is diatonic in C")
    check(cell(5, .major).relativeDegree, "IV", "circle of fifths F major cell is IV in C")
    check(cell(7, .major).relativeDegree, "V", "circle of fifths G major cell is V in C")
    // D minor (ii of C) is the relative minor of F major — rooted at column F, not column D.
    check(cell(2, .minor).relativeDegree, "ii", "circle of fifths D minor cell (at column F) is ii in C")
    check(cell(2, .minor).isDiatonic, true, "circle of fifths D minor cell is diatonic in C")
    check(cell(2, .major).isDiatonic, false, "circle of fifths D major cell is NOT diatonic in C")
    // B diminished (vii° of C) is the leading-tone diminished of C major — rooted at column C.
    check(cell(11, .diminished).relativeDegree, "vii\u{00B0}", "circle of fifths B diminished cell (at column C) is vii° in C")
    check(cell(11, .diminished).isDiatonic, true, "circle of fifths B diminished cell is diatonic in C")
    check(cell(10, .major).relativeDegree, "bVII", "circle of fifths Bb major cell is bVII in C")
    check(cell(6, .major).relativeDegree, "bV", "circle of fifths F# major cell is bV in C (major ring spells the tritone flat)")
}

func testCircleOfFifthsMinorAndDiminishedRingsHaveTheirOwnSpelling() {
    // Each ring spells its accidental degrees independently — NOT `majorDegreeLabels`
    // lowercased. Same tritone (F#/Gb, column F#) as the case above: "bV" on the major ring,
    // "#iv" on the minor ring, "#iv°" on the diminished ring — three different spellings.
    let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
    func cell(_ root: Int, _ quality: ChordQuality) -> CircleOfFifthsCell {
        wheel.columns.flatMap(\.cells).first { $0.pitchClass.value == root && $0.quality == quality }!
    }
    check(cell(6, .minor).relativeDegree, "#iv", "circle of fifths F# minor cell is #iv in C (minor ring spells the tritone sharp)")
    check(cell(6, .diminished).relativeDegree, "#iv\u{00B0}", "circle of fifths F# diminished cell is #iv° in C")
    // The minor ring's two sharp-not-flat anomalies (offsets 1 and 8: sharp here, flat on the
    // major ring) — C#m (not Dbm) is iii's relative-minor-of-relative-minor at column E/vi,
    // G#m (not Abm) at column B/vii.
    check(cell(1, .minor).relativeDegree, "#i", "circle of fifths C# minor cell is #i in C (minor ring, not bii)")
    check(cell(8, .minor).relativeDegree, "#v", "circle of fifths G# minor cell is #v in C (minor ring, not bvi)")
    // The diminished ring uses sharps for every accidental offset (never flats).
    check(cell(1, .diminished).relativeDegree, "#i\u{00B0}", "circle of fifths C# diminished cell is #i° in C")
    check(cell(3, .diminished).relativeDegree, "#ii\u{00B0}", "circle of fifths D# diminished cell is #ii° in C")
    check(cell(8, .diminished).relativeDegree, "#v\u{00B0}", "circle of fifths G# diminished cell is #v° in C")
    check(cell(10, .diminished).relativeDegree, "#vi\u{00B0}", "circle of fifths A# diminished cell is #vi° in C")
}

func testCircleOfFifthsMinorAndDiminishedCellsAreOffsetFromTheirColumn() {
    let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
    func column(_ pitchClass: Int) -> CircleOfFifthsColumn { wheel.columns.first { $0.pitchClass.value == pitchClass }! }
    // Column C: major=C(I), minor=Am(vi, relative minor of C), diminished=B°(vii°, leading tone).
    check(column(0).cells.first { $0.quality == .major }!.pitchClass, PitchClass(0), "circle of fifths column C major cell rooted on C")
    check(column(0).cells.first { $0.quality == .minor }!.pitchClass, PitchClass(9), "circle of fifths column C minor cell rooted on A (relative minor)")
    check(column(0).cells.first { $0.quality == .diminished }!.pitchClass, PitchClass(11), "circle of fifths column C diminished cell rooted on B (leading tone)")
    // Column F: major=F(IV), minor=Dm(ii), diminished=E°.
    check(column(5).cells.first { $0.quality == .minor }!.pitchClass, PitchClass(2), "circle of fifths column F minor cell rooted on D")
    check(column(5).cells.first { $0.quality == .diminished }!.pitchClass, PitchClass(4), "circle of fifths column F diminished cell rooted on E")
}

func testCircleOfFifthsActiveTonicPutsDegreeIOnTheModesOwnTonicNotTheParents() {
    // "A Lydian": parent is E (Lydian is degree 4, so E's major scale collection). Without
    // `activeTonic`, "I" used to land on E (the parent) — correct only for Ionian, off by
    // one degree for Lydian/Mixolydian, and completely wrong (opposite end of the label
    // table) for Locrian — see the two cases below.
    let aLydian = Mode(tonic: PitchClass(9), scale: ScaleLibrary.byID("lydian")!)
    let parentOfA = CircleOfFifths.parentTonic(for: aLydian)
    check(parentOfA, PitchClass(4), "circle of fifths A Lydian's parent is E")
    let lydianWheel = CircleOfFifths.wheel(tonic: parentOfA!, activeTonic: aLydian.tonic)
    let aMajorCell = lydianWheel.columns.flatMap(\.cells).first { $0.pitchClass == PitchClass(9) && $0.quality == .major }!
    check(aMajorCell.relativeDegree, "I", "circle of fifths A Lydian: degree I lands on A itself, not the parent E")
    check(aMajorCell.isDiatonic, true, "circle of fifths A Lydian: A major cell is still diatonic (it's E major's own IV)")

    // "D Locrian": parent is Eb (Locrian is degree 7, the farthest possible from its parent —
    // without `activeTonic` this used to be the most visibly broken case ("completely
    // offset"), since D's degree label relative to Eb sits at the opposite end of the table.
    // D Locrian's own tonic triad is diminished (not major/minor), so "I" belongs on D's
    // *diminished* cell specifically.
    let dLocrian = Mode(tonic: PitchClass(2), scale: ScaleLibrary.byID("locrian")!)
    let parentOfD = CircleOfFifths.parentTonic(for: dLocrian)
    check(parentOfD, PitchClass(3), "circle of fifths D Locrian's parent is Eb")
    let locrianWheel = CircleOfFifths.wheel(tonic: parentOfD!, activeTonic: dLocrian.tonic)
    let dDiminishedCell = locrianWheel.columns.flatMap(\.cells).first { $0.pitchClass == PitchClass(2) && $0.quality == .diminished }!
    check(dDiminishedCell.relativeDegree, "i\u{00B0}", "circle of fifths D Locrian: degree i° lands on D itself, not the parent Eb")
    check(dDiminishedCell.isDiatonic, true, "circle of fifths D Locrian: D diminished cell is still diatonic (it's Eb major's own vii°)")

    // Omitting `activeTonic` must keep behaving exactly as before (defaults to `tonic`) —
    // every other caller (e.g. the terminal's guide-screen neighbor line, which never looks
    // at `relativeDegree`) shouldn't need to change.
    let unspecified = CircleOfFifths.wheel(tonic: PitchClass(0))
    let cMajorCell = unspecified.columns.flatMap(\.cells).first { $0.pitchClass == PitchClass(0) && $0.quality == .major }!
    check(cMajorCell.relativeDegree, "I", "circle of fifths wheel(tonic:) without activeTonic still puts I on the tonic itself")
}

func testCircleOfFifthsShapeAlternatesByCellPitchClassParity() {
    let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
    for cell in wheel.columns.flatMap(\.cells) {
        let expected: ChordShape = cell.pitchClass.value % 2 == 0 ? .square : .circle
        check(cell.shape, expected, "circle of fifths shape parity for cell pitch class \(cell.pitchClass.value)")
    }
}

func testCircleOfFifthsDDorianParentTonicMatchesCIonian() {
    let mode = Mode(tonic: PitchClass(2), scale: ScaleLibrary.byID("dorian")!)
    check(CircleOfFifths.parentTonic(for: mode), PitchClass(0), "circle of fifths D dorian parent tonic matches C ionian")
}

func testCircleOfFifthsParentTonicNonFamily1ReturnsNil() {
    let mode = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("altered")!)
    checkNil(CircleOfFifths.parentTonic(for: mode), "circle of fifths non-family-1 scale has no parent tonic")
}

func testPitchClassPaletteHas12DistinctEntries() {
    check(PitchClassPalette.hex.count, 12, "pitch class palette has 12 entries")
    check(Set(PitchClassPalette.hex).count, 12, "pitch class palette entries are distinct")
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

func testMIDIRunningStatusNoteOnIsParsedWithoutARepeatedStatusByte() {
    let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 64, 90, 67, 80])
    check(events, [
        MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0),
        MIDINoteEvent(kind: .noteOn, pitch: 64, velocity: 90, channel: 0),
        MIDINoteEvent(kind: .noteOn, pitch: 67, velocity: 80, channel: 0),
    ], "midi running-status note-on parsed without a repeated status byte")
}

func testMIDIRunningStatusNoteOffIsParsedWithoutARepeatedStatusByte() {
    let events = MIDIRawParser.parseNoteEvents([0x80, 60, 0, 64, 0])
    check(events, [
        MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0),
        MIDINoteEvent(kind: .noteOff, pitch: 64, velocity: 0, channel: 0),
    ], "midi running-status note-off parsed without a repeated status byte")
}

func testMIDINonNoteStatusByteResetsRunningStatus() {
    let events = MIDIRawParser.parseNoteEvents([0x90, 60, 100, 0xB0, 7, 127])
    check(events, [MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0)], "midi non-note status byte resets running status")
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

/// A fundamental plus its own harmonics at independently chosen amplitudes — a synthetic
/// stand-in for a real instrument tone whose harmonic series isn't flat, unlike
/// `mixedSineWavesForFFTTests`'s equal-amplitude chord stand-in. `harmonicAmplitudes[0]` is the
/// fundamental's own amplitude, `[1]` the 2nd harmonic's, etc.
func harmonicRichWaveForFFTTests(fundamentalHz: Double, harmonicAmplitudes: [Float], sampleRate: Double, count: Int) -> [Float] {
    var mix = [Float](repeating: 0, count: count)
    for (index, amplitude) in harmonicAmplitudes.enumerated() {
        let wave = sineWaveForFFTTests(frequencyHz: fundamentalHz * Double(index + 1), sampleRate: sampleRate, count: count, amplitude: amplitude)
        for i in 0..<count { mix[i] += wave[i] }
    }
    return mix
}

func testFFTDominantFrequencyLocksOntoStrongSecondHarmonicWhenFundamentalIsWeak() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = harmonicRichWaveForFFTTests(fundamentalHz: 220, harmonicAmplitudes: [0.25, 0.5], sampleRate: 44100, count: 4096)
    guard let detected = analyzer.dominantFrequency(in: samples, sampleRate: 44100) else {
        failures += 1; checks += 1
        print("FAIL [dominantFrequency locks onto strong 2nd harmonic]: got nil")
        return
    }
    checkClose(detected, 440, accuracy: 3.0, "dominantFrequency locks onto strong 2nd harmonic")
}

func testMonophonicFundamentalHeuristicRecoversWeakFundamentalUnderStrongSecondHarmonic() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = harmonicRichWaveForFFTTests(fundamentalHz: 220, harmonicAmplitudes: [0.25, 0.5], sampleRate: 44100, count: 4096)
    guard let detected = analyzer.monophonicFundamentalHeuristic(in: samples, sampleRate: 44100) else {
        failures += 1; checks += 1
        print("FAIL [monophonicFundamentalHeuristic recovers weak fundamental]: got nil")
        return
    }
    checkClose(detected, 220, accuracy: 3.0, "monophonicFundamentalHeuristic recovers weak fundamental")
}

func testMonophonicFundamentalHeuristicMatchesPlainPeakForAPureTone() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = sineWaveForFFTTests(frequencyHz: 440, sampleRate: 44100, count: 4096)
    guard let detected = analyzer.monophonicFundamentalHeuristic(in: samples, sampleRate: 44100) else {
        failures += 1; checks += 1
        print("FAIL [monophonicFundamentalHeuristic pure tone]: got nil")
        return
    }
    checkClose(detected, 440, accuracy: 2.0, "monophonicFundamentalHeuristic matches plain peak for a pure tone")
}

func testMonophonicFundamentalHeuristicReturnsNilForSilence() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    checkNil(analyzer.monophonicFundamentalHeuristic(in: [Float](repeating: 0, count: 4096), sampleRate: 44100), "monophonicFundamentalHeuristic returns nil for silence")
}

func testMonophonicFundamentalHPSRecoversWeakFundamentalUnderStrongSecondHarmonic() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = harmonicRichWaveForFFTTests(fundamentalHz: 220, harmonicAmplitudes: [0.25, 0.5], sampleRate: 44100, count: 4096)
    guard let detected = analyzer.monophonicFundamentalHPS(in: samples, sampleRate: 44100) else {
        failures += 1; checks += 1
        print("FAIL [monophonicFundamentalHPS recovers weak fundamental]: got nil")
        return
    }
    checkClose(detected, 220, accuracy: 3.0, "monophonicFundamentalHPS recovers weak fundamental")
}

func testMonophonicFundamentalHPSMatchesPlainPeakForAPureTone() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    let samples = sineWaveForFFTTests(frequencyHz: 440, sampleRate: 44100, count: 4096)
    guard let detected = analyzer.monophonicFundamentalHPS(in: samples, sampleRate: 44100) else {
        failures += 1; checks += 1
        print("FAIL [monophonicFundamentalHPS pure tone]: got nil")
        return
    }
    checkClose(detected, 440, accuracy: 2.0, "monophonicFundamentalHPS matches plain peak for a pure tone")
}

func testMonophonicFundamentalHPSReturnsNilForSilence() {
    let analyzer = FFTPitchAnalyzer(size: 4096)
    checkNil(analyzer.monophonicFundamentalHPS(in: [Float](repeating: 0, count: 4096), sampleRate: 44100), "monophonicFundamentalHPS returns nil for silence")
}

// MARK: - MicrophonePitchStabilizerTests (mirrors Tests/AudioEngineTests/MicrophonePitchStabilizerTests.swift)

func testPassthroughConfirmsEveryWindowImmediately() {
    let stabilizer = MicrophonePitchStabilizer(policy: .passthrough)
    check(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)], "passthrough confirms note-on immediately")
    check(stabilizer.ingest([60, 64]), [StabilizedTransition(pitch: 64, kind: .noteOn)], "passthrough confirms added note immediately")
    check(stabilizer.ingest([]), [
        StabilizedTransition(pitch: 60, kind: .noteOff), StabilizedTransition(pitch: 64, kind: .noteOff),
    ], "passthrough confirms note-offs immediately")
}

func testLatchedRejectsFlickerShorterThanN() {
    let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 3))
    check(stabilizer.ingest([60]), [], "latched(3) holds after 1 window")
    check(stabilizer.ingest([]), [], "latched(3) holds after a dropout before reaching N")
    check(stabilizer.ingest([60]), [], "latched(3) still holds, flicker never reached N consecutive")
    check(stabilizer.confirmedPitches, [], "latched(3) never confirmed a flickering note")
}

func testLatchedConfirmsNoteOnAfterNConsecutiveWindows() {
    let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 3))
    check(stabilizer.ingest([60]), [], "latched(3) window 1/3")
    check(stabilizer.ingest([60]), [], "latched(3) window 2/3")
    check(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)], "latched(3) confirms on window 3/3")
    check(stabilizer.confirmedPitches, [60], "latched(3) confirmedPitches after confirmation")
}

func testLatchedConfirmsNoteOffOnlyAfterNConsecutiveAbsences() {
    let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 2))
    _ = stabilizer.ingest([60])
    check(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)], "latched(2) confirms on")
    check(stabilizer.ingest([]), [], "latched(2) one dropout does not yet confirm off")
    check(stabilizer.confirmedPitches, [60], "latched(2) still confirmed after one dropout")
    check(stabilizer.ingest([]), [StabilizedTransition(pitch: 60, kind: .noteOff)], "latched(2) confirms off after 2 consecutive absences")
    check(stabilizer.confirmedPitches, [], "latched(2) confirmedPitches empty after off")
}

func testSlidingConfirmsByMajorityNotConsecutive() {
    let stabilizer = MicrophonePitchStabilizer(policy: .sliding(windows: 3))
    check(stabilizer.ingest([60]), [], "sliding(3) 1/1 present, no majority of 3 yet")
    check(stabilizer.ingest([]), [], "sliding(3) 1/2 present, no majority yet")
    check(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)], "sliding(3) 2/3 present reaches majority")
}

func testSlidingToleratesOneDroppedWindow() {
    let stabilizer = MicrophonePitchStabilizer(policy: .sliding(windows: 3))
    _ = stabilizer.ingest([60])
    _ = stabilizer.ingest([60])
    check(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)], "sliding(3) confirms after 3/3")
    check(stabilizer.ingest([]), [], "sliding(3) tolerates one dropped window (2/3 still majority present)")
    check(stabilizer.confirmedPitches, [60], "sliding(3) stays confirmed through one dropped window")
}

func testWindowsOfOneMatchesPassthroughForBothPolicies() {
    let latched = MicrophonePitchStabilizer(policy: .latched(windows: 1))
    let sliding = MicrophonePitchStabilizer(policy: .sliding(windows: 1))
    let passthrough = MicrophonePitchStabilizer(policy: .passthrough)
    let sequence: [Set<Int>] = [[60], [60, 64], [64], []]
    for observed in sequence {
        check(latched.ingest(observed), passthrough.ingest(observed), "latched(1) matches passthrough")
    }
    for observed in sequence {
        check(sliding.ingest(observed), passthrough.ingest(observed), "sliding(1) matches passthrough")
    }
}

func testMultiplePitchesTrackedIndependently() {
    let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 2))
    // 60 is present in every window (confirms after 2 consecutive); 64 alternates
    // present/absent — present in 2 of 3 windows overall, but never twice IN A ROW, so under
    // `.latched` (unlike `.sliding`'s majority rule) it never confirms at all.
    check(stabilizer.ingest([60, 64]), [], "independent tracking window 1")
    check(stabilizer.ingest([60]), [StabilizedTransition(pitch: 60, kind: .noteOn)], "only the stable pitch (60) confirms")
    check(stabilizer.ingest([60, 64]), [], "flickering pitch (64) still never confirms")
    check(stabilizer.confirmedPitches, [60], "confirmedPitches only contains the stable pitch")
}

func testStabilizerResetClearsHistoryAndConfirmedPitches() {
    let stabilizer = MicrophonePitchStabilizer(policy: .latched(windows: 2))
    _ = stabilizer.ingest([60])
    _ = stabilizer.ingest([60])
    check(stabilizer.confirmedPitches, [60], "confirmed before reset")
    stabilizer.reset()
    check(stabilizer.confirmedPitches, [], "confirmedPitches cleared after reset")
    check(stabilizer.ingest([60]), [], "reset stabilizer needs the full N again, not just one more window")
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
        // A huge index, not 0: default fusion mode is `.individual` now, and this machine
        // does have at least one real MIDI source visible to CoreMIDI, so `.midiSource(0)`
        // can legitimately already be a listed track — the point of this test is "an index
        // with no matching track throws", which an index this large guarantees regardless
        // of how many real MIDI ports happen to be attached.
        try session.startTrack(.midiSource(9999))
        failures += 1
        print("FAIL [start-track on unlisted MIDI port throws]: did not throw")
    } catch ImprovSession.SessionError.unknownTrack {
        // expected
    } catch {
        failures += 1
        print("FAIL [start-track on unlisted MIDI port throws]: wrong error \(error)")
    }
}

func testDefaultMIDIFusionModeIsIndividual() {
    // Individual (one track per visible MIDI port), not merged — see `midiFusionMode`'s own
    // doc comment for why: a per-port track is what lets the LUMI run-mode integration
    // single out the LUMI's own track by name. This machine has no MIDI hardware attached,
    // so `.midiSource` tracks are simply absent rather than assertable one way or the other.
    let session = ImprovSession()
    check(session.midiFusionMode, MIDIFusionMode.individual, "default MIDI fusion mode is individual")
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

func testSetMicrophoneRecognitionModeRejectsNonMicrophoneTrack() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.setMicrophoneRecognitionMode(.monophonicHPS, for: .computerKeyboard)
        failures += 1
        print("FAIL [setMicrophoneRecognitionMode rejects non-microphone track]: did not throw")
    } catch ImprovSession.SessionError.recognitionModeOnlyForMicrophone {
        // expected
    } catch {
        failures += 1
        print("FAIL [setMicrophoneRecognitionMode rejects non-microphone track]: wrong error \(error)")
    }
}

func testSetMicrophoneRecognitionModeRejectsInvalidWindowCount() {
    let session = ImprovSession()
    for mode: MicrophoneRecognitionMode in [.polyphonicLatched(windows: 0), .polyphonicSliding(windows: 0)] {
        checks += 1
        do {
            try session.setMicrophoneRecognitionMode(mode, for: .microphone)
            failures += 1
            print("FAIL [setMicrophoneRecognitionMode rejects invalid window count]: did not throw for \(mode)")
        } catch ImprovSession.SessionError.invalidRecognitionWindowCount {
            // expected
        } catch {
            failures += 1
            print("FAIL [setMicrophoneRecognitionMode rejects invalid window count]: wrong error \(error)")
        }
    }
}

func testSetMicrophoneRecognitionModeSurvivesTrackRestart() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.monophonicHPS, for: .microphone)
        try session.startTrack(.microphone)
        check(session.tracks.first { $0.id == .microphone }?.microphoneRecognitionMode, .monophonicHPS, "mode set before listening survives startTrack")
        try session.setMicrophoneRecognitionMode(.polyphonicSliding(windows: 4), for: .microphone)
        let track = session.tracks.first { $0.id == .microphone }
        check(track?.microphoneRecognitionMode, .polyphonicSliding(windows: 4), "mode changed while listening takes effect")
        check(track?.isListening, true, "track still listening after a live mode change (restart)")
    } catch {
        failures += 1
        print("FAIL [setMicrophoneRecognitionMode survives track restart]: threw \(error)")
    }
}

func testMicrophonePolyLatchedDoesNotConfirmAFlickeringNote() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.polyphonicLatched(windows: 3), for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        if session.tracks.first(where: { $0.id == .microphone })!.heldPitches.contains(60) {
            failures += 1
            print("FAIL [poly-latched does not confirm a flickering note]: pitch 60 was confirmed")
        }
    } catch {
        failures += 1
        print("FAIL [poly-latched does not confirm a flickering note]: threw \(error)")
    }
}

func testMicrophonePolySlidingConfirmsUnderMajorityDespiteOneDropout() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.polyphonicSliding(windows: 3), for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        if !session.tracks.first(where: { $0.id == .microphone })!.heldPitches.contains(60) {
            failures += 1
            print("FAIL [poly-sliding confirms under majority despite one dropout]: pitch 60 was not confirmed")
        }
    } catch {
        failures += 1
        print("FAIL [poly-sliding confirms under majority despite one dropout]: threw \(error)")
    }
}

func testMicrophoneMonophonicModeConfirmsImmediately() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.monophonicHeuristic, for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        if !session.tracks.first(where: { $0.id == .microphone })!.heldPitches.contains(60) {
            failures += 1
            print("FAIL [monophonic mode confirms immediately]: pitch 60 was not confirmed after one window")
        }
    } catch {
        failures += 1
        print("FAIL [monophonic mode confirms immediately]: threw \(error)")
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
        server.localClientName = "Alice"
        let client = ImprovSession()
        try client.start()
        client.localClientName = "Bob"
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
            check(mirrored.ownerName, "Bob", "server labels the client's track with the client's pseudo")
        } else {
            failures += 1
            print("FAIL [server/client sync]: server never saw the client's 'clavier' track")
        }

        let serverTrackOnClient = TrackID.remote(clientID: server.localClientID, trackID: "clavier")
        if let mirrored = client.tracks.first(where: { $0.id == serverTrackOnClient }) {
            let hasChordText = mirrored.remoteChordDisplay?.contains("Ma") ?? false
            check(hasChordText, true, "client mirrors the server's own track with a display-string chord")
            check(mirrored.ownerName, "Alice", "client labels the server's own track with the server's pseudo")
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

// Mirrors Tests/AppCoreTests/ImprovSessionTests.swift's web-console guard-clause tests.
func testStartWebConsoleSetsPortAndStopClearsIt() {
    checks += 1
    do {
        let session = ImprovSession()
        checkNil(session.webConsolePort, "webConsolePort starts nil")
        try session.startWebConsole(port: 18391)
        check(session.webConsolePort, 18391, "webConsolePort set after start")
        session.stopWebConsole()
        checkNil(session.webConsolePort, "webConsolePort cleared after stop")
    } catch {
        failures += 1
        print("FAIL [web console start/stop]: threw \(error)")
    }
}
testStartWebConsoleSetsPortAndStopClearsIt()

func testStartWebConsoleTwiceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startWebConsole(port: 18392)
        defer { session.stopWebConsole() }
        do {
            try session.startWebConsole(port: 18393)
            failures += 1
            print("FAIL [web console double start]: did not throw")
        } catch ImprovSession.SessionError.webConsoleAlreadyActive {
            // expected
        } catch {
            failures += 1
            print("FAIL [web console double start]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [web console double start]: setup threw \(error)")
    }
}
testStartWebConsoleTwiceThrows()

func testStartWebConsoleInvalidPortThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startWebConsole(port: 999_999)
        failures += 1
        print("FAIL [web console invalid port]: did not throw")
    } catch {
        // expected
    }
    checkNil(session.webConsolePort, "webConsolePort stays nil after a failed start")
}
testStartWebConsoleInvalidPortThrows()

// A real HTTP round trip over real loopback TCP against the actual `HTTPServer` — not a
// mock — exercising the exact bug this feature hit during manual verification: an
// `HTTPConnection` created as a local in `newConnectionHandler` with only weak-self
// callbacks was deallocated before it could ever answer, and `HTTPServer.stop()`'s
// `[weak self]` queue.async raced the caller's immediate `= nil` and never actually
// cancelled the listener. Port 18394 is arbitrary, same caveat as the collaborative test's
// own fixed port.
// Mirrors Tests/WebConsoleTests/HTTPWireFormatTests.swift.
func testParseRequestLineExtractsMethodAndPath() {
    let request = HTTPWireFormat.parseRequestLine("GET /state HTTP/1.1\r\nHost: localhost\r\n")
    check(request?.method, "GET", "parseRequestLine extracts the method")
    check(request?.path, "/state", "parseRequestLine extracts the path")
}
testParseRequestLineExtractsMethodAndPath()

func testParseRequestLineRejectsMalformedLine() {
    // Deliberately lenient (no method whitelist, no HTTP-version check — see its doc
    // comment): the only real guard is "at least a method and a path", so only a line with
    // fewer than two space-separated tokens counts as malformed here.
    checkNil(HTTPWireFormat.parseRequestLine("GET"), "parseRequestLine rejects a line with no path")
    checkNil(HTTPWireFormat.parseRequestLine(""), "parseRequestLine rejects an empty line")
}
testParseRequestLineRejectsMalformedLine()

func testResponseHeadIncludesContentLengthAndCloseConnection() {
    let response = HTTPResponse.text("hello", contentType: "text/plain")
    let head = HTTPWireFormat.responseHead(for: response)
    check(head.hasPrefix("HTTP/1.1 200 OK\r\n"), true, "responseHead starts with the status line")
    check(head.contains("Content-Type: text/plain\r\n"), true, "responseHead includes Content-Type")
    check(head.contains("Content-Length: 5\r\n"), true, "responseHead includes Content-Length")
    check(head.contains("Connection: close\r\n"), true, "responseHead includes Connection: close")
    check(head.hasSuffix("\r\n\r\n"), true, "responseHead ends with the blank line terminating headers")
}
testResponseHeadIncludesContentLengthAndCloseConnection()

func testNotFoundResponseIs404() {
    check(HTTPResponse.notFound().status, 404, "HTTPResponse.notFound() is a 404")
}
testNotFoundResponseIs404()

func syncGET(_ url: String, timeout: TimeInterval = 2) -> (status: Int, contentType: String?, body: String)? {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: (Int, String?, String)?
    URLSession.shared.dataTask(with: URL(string: url)!) { data, response, _ in
        if let http = response as? HTTPURLResponse, let data {
            result = (http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), String(data: data, encoding: .utf8) ?? "")
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + timeout)
    return result
}

func testWebConsoleServesPageScriptAndState() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startWebConsole(port: 18394)
        try session.startTrack(.computerKeyboard)
        session.pressKey(pitch: 60)
        session.pressKey(pitch: 64)
        session.pressKey(pitch: 67)
        Thread.sleep(forTimeInterval: 0.3) // let the 150ms refresh timer tick at least once

        if let page = syncGET("http://127.0.0.1:18394/") {
            check(page.status, 200, "GET / returns 200")
            check(page.contentType?.contains("text/html") ?? false, true, "GET / is HTML")
        } else {
            failures += 1
            print("FAIL [web console GET /]: no response")
        }

        if let script = syncGET("http://127.0.0.1:18394/app.js") {
            check(script.status, 200, "GET /app.js returns 200")
            check(script.contentType ?? "", "application/javascript", "GET /app.js content type")
        } else {
            failures += 1
            print("FAIL [web console GET /app.js]: no response")
        }

        if let state = syncGET("http://127.0.0.1:18394/state") {
            check(state.status, 200, "GET /state returns 200")
            check(state.body.contains("\"chordRoot\":0"), true, "GET /state reflects the C major triad just played")
            check(state.body.contains("\"id\":\"clavier\""), true, "GET /state includes the listening track")
        } else {
            failures += 1
            print("FAIL [web console GET /state]: no response")
        }

        if let notFound = syncGET("http://127.0.0.1:18394/nope") {
            check(notFound.status, 404, "GET /nope returns 404")
        } else {
            failures += 1
            print("FAIL [web console GET /nope]: no response")
        }

        session.stopWebConsole()
        Thread.sleep(forTimeInterval: 0.2)
        check(syncGET("http://127.0.0.1:18394/state", timeout: 1) == nil, true, "stopWebConsole actually releases the port")
    } catch {
        failures += 1
        print("FAIL [web console HTTP round trip]: threw \(error)")
    }
}
testWebConsoleServesPageScriptAndState()

// No `.webKeyboard(clientID:)` track is pre-created at all anymore — unlike the computer
// keyboard, it's created on demand per browser the first time that browser's `clientID`
// shows up in a request (see `ensureWebKeyboardTrack`), so `startVirtualKeyboard` on its own
// leaves `tracks` unchanged; only an actual `GET` with `?client=...` creates one, and
// `stopVirtualKeyboard` drops every such track regardless of client.
func testStartVirtualKeyboardSetsPortAndStopRemovesAnyConnectedClientTracks() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        checkNil(session.virtualKeyboardPort, "virtualKeyboardPort starts nil")
        try session.startVirtualKeyboard(port: 18395)
        check(session.virtualKeyboardPort, 18395, "virtualKeyboardPort set after start")
        check(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false }, false, "starting the server alone creates no .webKeyboard track yet")
        _ = syncGET("http://127.0.0.1:18395/note-on?pitch=60&client=test-client-1&name=Alice")
        check(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false }, true, "a request with ?client=... creates its track on demand")
        session.stopVirtualKeyboard()
        checkNil(session.virtualKeyboardPort, "virtualKeyboardPort cleared after stop")
        check(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false }, false, "stopVirtualKeyboard removes every connected client's track")
    } catch {
        failures += 1
        print("FAIL [virtual keyboard start/stop]: threw \(error)")
    }
}
testStartVirtualKeyboardSetsPortAndStopRemovesAnyConnectedClientTracks()

func testStartVirtualKeyboardTwiceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startVirtualKeyboard(port: 18396)
        defer { session.stopVirtualKeyboard() }
        do {
            try session.startVirtualKeyboard(port: 18397)
            failures += 1
            print("FAIL [virtual keyboard double start]: did not throw")
        } catch ImprovSession.SessionError.virtualKeyboardAlreadyActive {
            // expected
        } catch {
            failures += 1
            print("FAIL [virtual keyboard double start]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [virtual keyboard double start]: setup threw \(error)")
    }
}
testStartVirtualKeyboardTwiceThrows()

// Real HTTP round trip over real loopback TCP — note-on/note-off through the actual
// `GET /note-on`/`GET /note-off` routes (not `session.pressKey` directly), since the whole
// point is verifying the HTTP-to-session wiring, mirroring `testWebConsoleServesPageScriptAndState`.
func testVirtualKeyboardServesPageAndAcceptsNoteOnOff() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18398)

        if let page = syncGET("http://127.0.0.1:18398/") {
            check(page.status, 200, "GET / returns 200")
            check(page.contentType?.contains("text/html") ?? false, true, "GET / is HTML")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /]: no response")
        }

        if let script = syncGET("http://127.0.0.1:18398/app.js") {
            check(script.status, 200, "GET /app.js returns 200")
            check(script.contentType ?? "", "application/javascript", "GET /app.js content type")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /app.js]: no response")
        }

        if let noClient = syncGET("http://127.0.0.1:18398/state") {
            check(noClient.status, 400, "GET /state with no ?client=... returns 400")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state no client]: no response")
        }

        let alice = "&client=alice-uuid&name=Alice"
        if let before = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(before.body.contains("\"heldPitches\":[]"), true, "GET /state starts with no held pitches")
            check(before.body.contains("\"label\":\"Alice\""), true, "GET /state reports the chosen alias as the track's label")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state before note-on]: no response")
        }

        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=60" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=64" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=67" + alice)
        Thread.sleep(forTimeInterval: 0.2)

        if let held = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(held.body.contains("\"chordRoot\":0"), true, "GET /note-on drove the session — C major triad recognized")
            check(held.body.contains("\"id\":\"clavier-web:alice-uuid\""), true, "GET /state reports this client's own dedicated track id")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state after note-on]: no response")
        }

        // A second, unrelated client (different `?client=...`) must get its OWN independent
        // track — no cross-talk between the two connected browsers.
        let bob = "&client=bob-uuid&name=Bob"
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=62" + bob)
        Thread.sleep(forTimeInterval: 0.2)
        if let bobState = syncGET("http://127.0.0.1:18398/state?dummy=1" + bob), let aliceState = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(bobState.body.contains("\"heldPitches\":[62]"), true, "the second client's own track only has its own note held")
            check(aliceState.body.contains("\"heldPitches\":[60,64,67]") || aliceState.body.contains("\"heldPitches\":[60,67,64]") || aliceState.body.contains("\"heldPitches\":[64,60,67]") || aliceState.body.contains("\"heldPitches\":[64,67,60]") || aliceState.body.contains("\"heldPitches\":[67,60,64]") || aliceState.body.contains("\"heldPitches\":[67,64,60]"), true, "the first client's track is untouched by the second client's note")
        } else {
            failures += 1
            print("FAIL [virtual keyboard two clients]: no response")
        }

        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=60" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=64" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=67" + alice)
        Thread.sleep(forTimeInterval: 0.2)

        if let released = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(released.body.contains("\"heldPitches\":[]"), true, "GET /note-off released every note")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state after note-off]: no response")
        }

        // The Escape "panic button" route — simulates a note stuck held (as if its matching
        // note-off had raced and lost, see `releaseAllKeys`'s doc comment) and confirms
        // GET /release-all clears it without needing to know which pitch was stuck.
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=72" + alice)
        Thread.sleep(forTimeInterval: 0.2)
        _ = syncGET("http://127.0.0.1:18398/release-all?dummy=1" + alice)
        Thread.sleep(forTimeInterval: 0.2)
        if let afterReleaseAll = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(afterReleaseAll.body.contains("\"heldPitches\":[]"), true, "GET /release-all clears a stuck-held note")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state after release-all]: no response")
        }

        if let badPitch = syncGET("http://127.0.0.1:18398/note-on?pitch=notanumber" + alice) {
            check(badPitch.status, 400, "GET /note-on with a non-numeric pitch returns 400")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /note-on bad pitch]: no response")
        }

        session.stopVirtualKeyboard()
        Thread.sleep(forTimeInterval: 0.2)
        check(syncGET("http://127.0.0.1:18398/state" + alice, timeout: 1) == nil, true, "stopVirtualKeyboard actually releases the port")
    } catch {
        failures += 1
        print("FAIL [virtual keyboard HTTP round trip]: threw \(error)")
    }
}
testVirtualKeyboardServesPageAndAcceptsNoteOnOff()

func testVirtualKeyboardStateAlwaysIncludesWheelButOnlyGuideWhileActive() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18399)
        let client = "&client=guide-client&name=Guidee"

        if let noGuide = syncGET("http://127.0.0.1:18399/state?dummy=1" + client) {
            // Synthesized `Encodable` conformance uses `encodeIfPresent` for `Optional`
            // properties — a `nil` field is OMITTED from the JSON entirely, not written as
            // an explicit `null`, so the absence check is on the key itself.
            check(noGuide.body.contains("\"guide\""), false, "no guide running — guide key is omitted")
            // `wheel` is now always present (like the read-only console's own) — the virtual
            // keyboard page shows it, and lets you click chords on it, whether or not a guide
            // is running; only rendering the mode-relative parts is gated client-side.
            check(noGuide.body.contains("\"wheel\""), true, "no guide running — wheel key is still present")
        } else {
            failures += 1
            print("FAIL [virtual keyboard no guide]: no response")
        }

        session.newGuideSequence(title: "Test")
        try session.addGuideStep(ModeReference(tonic: 9, scaleID: "lydian")) // A Lydian
        try session.startGuide()
        Thread.sleep(forTimeInterval: 0.1)

        if let withGuide = syncGET("http://127.0.0.1:18399/state?dummy=1" + client) {
            check(withGuide.body.contains("\"isActive\":true"), true, "guide running — guide.isActive is true")
            check(withGuide.body.contains("\"activeModeName\":\"Lydian\""), true, "guide running — wheel reflects the guide's own mode, not this track's")
        } else {
            failures += 1
            print("FAIL [virtual keyboard with guide]: no response")
        }

        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [virtual keyboard guide/wheel]: threw \(error)")
    }
}
testVirtualKeyboardStateAlwaysIncludesWheelButOnlyGuideWhileActive()

func testVirtualKeyboardGuideAdvanceMovesTheSharedGuideStep() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18410)
        let client = "&client=advance-client&name=Advancer"

        session.newGuideSequence(title: "Advance Test")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.startGuide()
        check(session.currentGuideStepIndex, 0, "guide starts at step 0")

        if let advanced = syncGET("http://127.0.0.1:18410/guide-advance?delta=1" + client) {
            check(advanced.status, 200, "GET /guide-advance?delta=1 succeeds")
        } else {
            failures += 1
            print("FAIL [guide-advance forward]: no response")
        }
        check(session.currentGuideStepIndex, 1, "GET /guide-advance?delta=1 moves the shared guide forward")

        if let back = syncGET("http://127.0.0.1:18410/guide-advance?delta=-1" + client) {
            check(back.status, 200, "GET /guide-advance?delta=-1 succeeds")
        } else {
            failures += 1
            print("FAIL [guide-advance backward]: no response")
        }
        check(session.currentGuideStepIndex, 0, "GET /guide-advance?delta=-1 moves the shared guide backward")

        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [virtual keyboard guide-advance]: threw \(error)")
    }
}
testVirtualKeyboardGuideAdvanceMovesTheSharedGuideStep()

func testVirtualKeyboardStateExposesCurrentStepChordProgression() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18411)
        let client = "&client=progression-client&name=Progressor"

        session.newGuideSequence(title: "Progression Test")
        // C Ionian + "ii-V-I (jazz)" resolves to Dmi, GMa, CMa (see `RomanNumeralChord` —
        // roman-numeral case IS the quality, taken literally as a plain triad; no 7ths):
        // exercises both the label formatting and the major/minor quality mapping.
        let progression = ChordProgressionTemplate(name: "ii-V-I (jazz)", degrees: ["ii", "V", "I"])
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: progression)
        try session.startGuide()
        Thread.sleep(forTimeInterval: 0.1)

        if let withProgression = syncGET("http://127.0.0.1:18411/state?dummy=1" + client) {
            check(withProgression.body.contains("\"currentChordProgressionName\":\"ii-V-I (jazz)\""), true, "guide state exposes the attached progression's name")
            check(withProgression.body.contains("\"label\":\"Dmi\""), true, "progression entry 0 (ii) resolves to Dmi")
            check(withProgression.body.contains("\"label\":\"GMa\""), true, "progression entry 1 (V) resolves to GMa")
            check(withProgression.body.contains("\"label\":\"CMa\""), true, "progression entry 2 (I) resolves to CMa")
            check(withProgression.body.contains("\"quality\":\"minor\""), true, "Dmi entry carries quality \"minor\" for wheel matching")
            check(withProgression.body.contains("\"quality\":\"major\""), true, "G7/CMa entries carry quality \"major\" for wheel matching")
        } else {
            failures += 1
            print("FAIL [virtual keyboard chord progression]: no response")
        }

        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [virtual keyboard chord progression]: threw \(error)")
    }
}
testVirtualKeyboardStateExposesCurrentStepChordProgression()

func testReleaseAllKeysClearsHeldPitchesForOneTrackOnly() {
    let session = ImprovSession()
    session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
    checks += 1
    do {
        try session.startTrack(.computerKeyboard)
        try session.startTrack(.midiMerged)
        session.pressKey(pitch: 60, track: .computerKeyboard)
        session.pressKey(pitch: 64, track: .midiMerged)
        session.pressKey(pitch: 67, track: .midiMerged)
        session.releaseAllKeys(track: .midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.heldPitches.isEmpty, true, "releaseAllKeys clears every held pitch on the targeted track")
        check(session.tracks.first { $0.id == .computerKeyboard }?.heldPitches, Set([60]), "releaseAllKeys leaves an unrelated track's held pitches untouched")
    } catch {
        failures += 1
        print("FAIL [releaseAllKeys]: threw \(error)")
    }
}
testReleaseAllKeysClearsHeldPitchesForOneTrackOnly()

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

func testSetPromptsFolderCreatesAllFiveSubfoldersAndListsFiles() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)

        var isDirectory: ObjCBool = false
        for subfolder in ["Cadrage Composition Descriptive", "Cadrage Composition Soundtrack", "composition Descriptive", "Indications Soundtracks", "Export"] {
            checks += 1
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(subfolder).path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                failures += 1
                print("FAIL [setPromptsFolder creates \(subfolder) subfolder]")
            }
        }
        check(session.textFramingFiles, [], "setPromptsFolder starts with no text framing files")
        check(session.soundTrackFramingFiles, [], "setPromptsFolder starts with no soundtrack framing files")
        check(session.soundTrackInstructionsFiles, [], "setPromptsFolder starts with no soundtrack instructions files")
        check(session.compositionFolder, root.appendingPathComponent("composition Descriptive").path, "setPromptsFolder derives compositionFolder")
        check(session.compositionFiles, [], "setPromptsFolder starts with no composition description files")
    } catch {
        failures += 1
        print("FAIL [setPromptsFolder creates subfolders and lists files]: threw \(error)")
    }
}
testSetPromptsFolderCreatesAllFiveSubfoldersAndListsFiles()

func testExportTextCompositionPromptWritesCurrentPromptToExportSubfolder() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSourceText("a poem about the sea")

        try session.exportTextCompositionPrompt(as: "my-export")
        let exported = try String(contentsOf: root.appendingPathComponent("Export/my-export.txt"), encoding: .utf8)
        check(exported, try session.currentTextCompositionPrompt(), "exported file matches currentTextCompositionPrompt()")
        checks += 1
        if !exported.contains("a poem about the sea") {
            failures += 1
            print("FAIL [exportTextCompositionPrompt]: exported text missing source text")
        }
    } catch {
        failures += 1
        print("FAIL [exportTextCompositionPrompt writes to Export subfolder]: threw \(error)")
    }
}
testExportTextCompositionPromptWritesCurrentPromptToExportSubfolder()

func testExportSoundTrackCompositionPromptWritesCurrentPromptToExportSubfolder() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        try session.startRecording(title: "ForExport")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.exportSoundTrackCompositionPrompt(as: "my-soundtrack-export")
        let exported = try String(contentsOf: root.appendingPathComponent("Export/my-soundtrack-export.txt"), encoding: .utf8)
        check(exported, try session.currentSoundTrackCompositionPrompt(), "exported file matches currentSoundTrackCompositionPrompt()")
    } catch {
        failures += 1
        print("FAIL [exportSoundTrackCompositionPrompt writes to Export subfolder]: threw \(error)")
    }
}
testExportSoundTrackCompositionPromptWritesCurrentPromptToExportSubfolder()

func testSaveAndUseSoundTrackCompositionInstructionsRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checkNil(session.currentSoundTrackCompositionInstructions(), "no instructions set initially")

        session.setSoundTrackCompositionInstructions("romantique, mode mineur")
        try session.saveSoundTrackCompositionInstructions(as: "my-instructions")
        check(session.soundTrackInstructionsFiles, ["my-instructions.txt"], "saveSoundTrackCompositionInstructions adds the file")

        session.resetSoundTrackCompositionInstructions()
        checkNil(session.currentSoundTrackCompositionInstructions(), "reset clears instructions")

        try session.useSoundTrackCompositionInstructions(atIndex: 0)
        check(session.activeSoundTrackCompositionInstructions, "romantique, mode mineur", "useSoundTrackCompositionInstructions reloads the saved value")
    } catch {
        failures += 1
        print("FAIL [save and use soundtrack composition instructions round trips]: threw \(error)")
    }
}
testSaveAndUseSoundTrackCompositionInstructionsRoundTrips()

func testSaveSoundTrackCompositionInstructionsWithoutAnySetThrows() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checks += 1
        do {
            try session.saveSoundTrackCompositionInstructions(as: "nothing-to-save")
            failures += 1
            print("FAIL [saveSoundTrackCompositionInstructions without any set throws]: did not throw")
        } catch ImprovSession.SessionError.noSoundTrackCompositionInstructions {
            // expected
        } catch {
            failures += 1
            print("FAIL [saveSoundTrackCompositionInstructions without any set throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [save soundtrack composition instructions without any set]: threw \(error)")
    }
}
testSaveSoundTrackCompositionInstructionsWithoutAnySetThrows()

func testUseSoundTrackCompositionInstructionsWithInvalidIndexThrows() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checks += 1
        do {
            try session.useSoundTrackCompositionInstructions(atIndex: 0)
            failures += 1
            print("FAIL [useSoundTrackCompositionInstructions invalid index throws]: did not throw")
        } catch let error as ImprovSession.SessionError {
            if error != .invalidSoundTrackInstructionsIndex {
                failures += 1
                print("FAIL [useSoundTrackCompositionInstructions invalid index throws]: wrong error \(error)")
            }
        }
    } catch {
        failures += 1
        print("FAIL [use soundtrack composition instructions with invalid index]: threw \(error)")
    }
}
testUseSoundTrackCompositionInstructionsWithInvalidIndexThrows()

func testCurrentSoundTrackCompositionPromptIncludesActiveInstructions() {
    do {
        let session = ImprovSession()
        try session.startRecording(title: "ForInstructions")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()
        session.setSoundTrackCompositionInstructions("romantique, mode mineur")
        let prompt = try session.currentSoundTrackCompositionPrompt()
        checks += 1
        if !prompt.contains("romantique, mode mineur") {
            failures += 1
            print("FAIL [currentSoundTrackCompositionPrompt includes active instructions]")
        }
    } catch {
        failures += 1
        print("FAIL [currentSoundTrackCompositionPrompt includes active instructions]: threw \(error)")
    }
}
testCurrentSoundTrackCompositionPromptIncludesActiveInstructions()

// Mirrors ImprovSessionTests.swift's framing-sentence tests.
func testCurrentFramingSentenceDefaultsToTheBuiltInConstants() {
    let session = ImprovSession()
    check(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence, "text framing defaults to the built-in constant")
    check(session.currentSoundTrackFramingSentence(), LLMPieceComposer.defaultSoundTrackFramingSentence, "soundtrack framing defaults to the built-in constant")
}
testCurrentFramingSentenceDefaultsToTheBuiltInConstants()

func testSetTextFramingSentenceIsReflectedInTheFullPrompt() {
    do {
        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setTextFramingSentence("Custom framing sentence.")
        check(session.currentTextFramingSentence(), "Custom framing sentence.", "setTextFramingSentence updates currentTextFramingSentence")
        checks += 1
        if !(try session.currentTextCompositionPrompt()).contains("Custom framing sentence.") {
            failures += 1
            print("FAIL [setTextFramingSentence reflected in full prompt]")
        }
    } catch {
        failures += 1
        print("FAIL [setTextFramingSentence reflected in full prompt]: threw \(error)")
    }
}
testSetTextFramingSentenceIsReflectedInTheFullPrompt()

func testSetTextFramingSentenceEmptyStringRevertsToDefault() {
    let session = ImprovSession()
    session.setTextFramingSentence("Custom.")
    check(session.currentTextFramingSentence(), "Custom.", "setTextFramingSentence sets a custom value")
    session.setTextFramingSentence("")
    check(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence, "empty setTextFramingSentence reverts to default")
}
testSetTextFramingSentenceEmptyStringRevertsToDefault()

func testSaveAndUseTextFramingSentenceRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setTextFramingSentence("A distinctive custom framing sentence.")

        try session.saveTextFramingSentence(as: "my-framing")
        check(session.textFramingFiles, ["my-framing.txt"], "saveTextFramingSentence adds the file to textFramingFiles")

        session.resetTextFramingSentence()
        check(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence, "resetTextFramingSentence reverts to default")

        try session.useTextFramingSentence(atIndex: 0)
        check(session.activeTextFramingSentence, "A distinctive custom framing sentence.", "useTextFramingSentence reloads the saved sentence")
    } catch {
        failures += 1
        print("FAIL [save and use text framing sentence round trips]: threw \(error)")
    }
}
testSaveAndUseTextFramingSentenceRoundTrips()

func testSaveAndUseSoundTrackFramingSentenceRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSoundTrackFramingSentence("A distinctive soundtrack framing sentence.")

        try session.saveSoundTrackFramingSentence(as: "my-soundtrack-framing")
        check(session.soundTrackFramingFiles, ["my-soundtrack-framing.txt"], "saveSoundTrackFramingSentence adds the file to soundTrackFramingFiles")

        session.resetSoundTrackFramingSentence()
        try session.useSoundTrackFramingSentence(named: "my-soundtrack-framing.txt")
        check(session.activeSoundTrackFramingSentence, "A distinctive soundtrack framing sentence.", "useSoundTrackFramingSentence reloads the saved sentence")
    } catch {
        failures += 1
        print("FAIL [save and use soundtrack framing sentence round trips]: threw \(error)")
    }
}
testSaveAndUseSoundTrackFramingSentenceRoundTrips()

func testUseTextFramingSentenceWithInvalidIndexThrows() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checks += 1
        do {
            try session.useTextFramingSentence(atIndex: 0)
            failures += 1
            print("FAIL [useTextFramingSentence invalid index throws]: did not throw")
        } catch let error as ImprovSession.SessionError {
            if error != .invalidTextFramingIndex {
                failures += 1
                print("FAIL [useTextFramingSentence invalid index throws]: wrong error \(error)")
            }
        }
    } catch {
        failures += 1
        print("FAIL [use text framing sentence with invalid index]: threw \(error)")
    }
}
testUseTextFramingSentenceWithInvalidIndexThrows()

// Mirrors ImprovSessionTests.swift's composition-description tests.
func testSaveThenLoadCompositionDescriptionRoundTrips() {
    do {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.listCompositionFiles(in: folder.path)

        session.setCompositionTitle("My Ballad")
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        try session.saveCompositionDescription(as: "my-description")
        check(session.compositionFiles, ["my-description.json"], "saveCompositionDescription adds the file to compositionFiles")

        let reloaded = ImprovSession()
        try reloaded.listCompositionFiles(in: folder.path)
        try reloaded.loadCompositionDescription(atIndex: 0)
        check(reloaded.compositionTitle, "My Ballad", "loadCompositionDescription restores the title")
        check(reloaded.sourceText, "a poem about the sea", "loadCompositionDescription restores the source text")
        check(reloaded.additionalCompositionInstructions, "romantique, mode mineur", "loadCompositionDescription restores the indications")
    } catch {
        failures += 1
        print("FAIL [save then load composition description round trips]: threw \(error)")
    }
}
testSaveThenLoadCompositionDescriptionRoundTrips()

func testLoadCompositionDescriptionAtInvalidIndexThrows() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = ImprovSession()
        try session.listCompositionFiles(in: folder.path)
        checks += 1
        do {
            try session.loadCompositionDescription(atIndex: 0)
            failures += 1
            print("FAIL [loadCompositionDescription invalid index throws]: did not throw")
        } catch let error as ImprovSession.SessionError {
            if error != .invalidCompositionIndex {
                failures += 1
                print("FAIL [loadCompositionDescription invalid index throws]: wrong error \(error)")
            }
        }
    } catch {
        failures += 1
        print("FAIL [load composition description at invalid index]: threw \(error)")
    }
}
testLoadCompositionDescriptionAtInvalidIndexThrows()

func testSaveCompositionDescriptionWithoutSourceTextThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.saveCompositionDescription(as: "/tmp/whatever")
        failures += 1
        print("FAIL [saveCompositionDescription without sourceText throws]: did not throw")
    } catch ImprovSession.SessionError.noSourceText {
        // expected
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription without sourceText throws]: wrong error \(error)")
    }
}
testSaveCompositionDescriptionWithoutSourceTextThrows()

func testSaveCompositionDescriptionWithoutFolderListedThrows() {
    let session = ImprovSession()
    session.setSourceText("a poem")
    checks += 1
    do {
        try session.saveCompositionDescription(as: "bare-name")
        failures += 1
        print("FAIL [saveCompositionDescription without folder listed throws]: did not throw")
    } catch ImprovSession.SessionError.noCompositionFolderListed {
        // expected
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription without folder listed throws]: wrong error \(error)")
    }
}
testSaveCompositionDescriptionWithoutFolderListedThrows()

func testSaveCompositionDescriptionWithoutHavingSavedOnceThrows() {
    let session = ImprovSession()
    session.setSourceText("a poem")
    checks += 1
    do {
        try session.saveCompositionDescription()
        failures += 1
        print("FAIL [saveCompositionDescription without prior save throws]: did not throw")
    } catch ImprovSession.SessionError.noCurrentCompositionFile {
        // expected
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription without prior save throws]: wrong error \(error)")
    }
}
testSaveCompositionDescriptionWithoutHavingSavedOnceThrows()

func testSaveCompositionDescriptionReSavesToTheSameFile() {
    do {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.listCompositionFiles(in: folder.path)
        session.setSourceText("first version")
        try session.saveCompositionDescription(as: "iterate")

        session.setSourceText("second version")
        try session.saveCompositionDescription()

        let reloaded = ImprovSession()
        try reloaded.loadCompositionDescription(fromJSONFile: folder.appendingPathComponent("iterate.json").path)
        check(reloaded.sourceText, "second version", "saveCompositionDescription() re-saves to the same file")
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription re-saves to the same file]: threw \(error)")
    }
}
testSaveCompositionDescriptionReSavesToTheSameFile()

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

// MARK: - GuideSequence / ImprovSession guide-mode tests

func testNewGuideSequenceThenAddStepsThenStartAndAdvance() {
    do {
        let session = ImprovSession()
        checkNil(session.currentGuide, "improv session starts with no guide sequence")
        session.newGuideSequence(title: "Practice")
        check(session.currentGuide?.title, "Practice", "newGuideSequence sets title")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 2, scaleID: "dorian"))
        check(session.currentGuide?.steps.count, 2, "addGuideStep appends steps")

        checkNil(session.currentGuideStepIndex, "guide not started has no current step index")
        checkNil(session.currentGuideStepMode(), "guide not started has no current mode")

        try session.startGuide()
        check(session.currentGuideStepIndex, 0, "startGuide defaults to step 0")
        check(session.currentGuideStepMode()?.displayName, "C Major", "guide step 0 mode")

        session.advanceGuideStep(by: 1)
        check(session.currentGuideStepIndex, 1, "advanceGuideStep(+1) moves to step 1")
        check(session.currentGuideStepMode()?.displayName, "D Dorian", "guide step 1 mode")

        session.advanceGuideStep(by: 1)
        check(session.currentGuideStepIndex, 1, "advanceGuideStep clamps at the last step")

        session.advanceGuideStep(by: -5)
        check(session.currentGuideStepIndex, 0, "advanceGuideStep clamps at the first step")

        session.stopGuide()
        checkNil(session.currentGuideStepIndex, "stopGuide clears the current step index")
    } catch {
        failures += 1
        print("FAIL [guide sequence start/advance]: threw \(error)")
    }
}

func testAddGuideStepWithoutASequenceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        failures += 1
        print("FAIL [addGuideStep without sequence throws]: did not throw")
    } catch {
        // expected
    }
}

func testAddGuideStepWithUnknownScaleIDThrowsAndDoesNotAppendAStep() {
    let session = ImprovSession()
    session.newGuideSequence(title: "Practice")
    checks += 1
    do {
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "majeur")) // not a real ScaleLibrary id
        failures += 1
        print("FAIL [addGuideStep unknown scaleID throws]: did not throw")
    } catch {
        // expected
    }
    check(session.currentGuide?.steps.count, 0, "addGuideStep with an unresolvable reference doesn't leave a dangling step")
}

func testTrackIDWireIDTextRoundTrips() {
    for id: TrackID in [.midiMerged, .computerKeyboard, .webKeyboard(clientID: "abc-123"), .microphone, .midiSource(0), .midiSource(3)] {
        guard let wireText = id.wireIDText else {
            failures += 1; checks += 1
            print("FAIL [TrackID wireIDText round trip]: \(id) has no wireIDText")
            continue
        }
        check(TrackID(wireIDText: wireText), id, "TrackID(wireIDText:) inverts wireIDText for \(id)")
    }
    checkNil(TrackID(wireIDText: "not-a-real-id"), "TrackID(wireIDText:) rejects an unrecognized string")
}

func testSceneSaveAndLoadRoundTripsTrackListeningAndSound() {
    do {
        let session = ImprovSession()
        try session.start()
        try session.startTrack(.computerKeyboard)
        try session.setSoundEnabled(true, for: .computerKeyboard)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveScene(title: "Test Scene", toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.start()
        let before = reloaded.tracks.first { $0.id == .computerKeyboard }
        check(before?.isListening, false, "fresh session's computer-keyboard track starts not listening")

        try reloaded.loadScene(fromJSONFile: tempFile.path)
        let after = reloaded.tracks.first { $0.id == .computerKeyboard }
        check(after?.isListening, true, "loadScene restores isListening")
        check(after?.soundEnabled, true, "loadScene restores soundEnabled")
    } catch {
        failures += 1
        print("FAIL [scene save/load round trip]: threw \(error)")
    }
}

func testLoadSceneLeavesTracksNotMentionedUntouched() {
    do {
        let session = ImprovSession()
        try session.start()
        // An explicitly empty scene (built by hand, not via `saveScene` — which always
        // captures every local track, including as "not listening") must not touch
        // whatever's currently listening: only tracks it actually mentions are restored.
        let emptyScene = Scene(title: "Empty", roles: [])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(emptyScene).write(to: tempFile)

        try session.startTrack(.computerKeyboard)
        try session.loadScene(fromJSONFile: tempFile.path)
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "loading a scene that doesn't mention a track leaves it untouched")
    } catch {
        failures += 1
        print("FAIL [scene leaves unmentioned tracks untouched]: threw \(error)")
    }
}

// MARK: - Scene roles — mirrors Tests/AppCoreTests/ImprovSessionTests.swift's tests of the same name.

func testNewSceneCreatesEmptyActiveScene() {
    let session = ImprovSession()
    checkNil(session.currentScene, "fresh session has no active scene")
    session.newScene(title: "Repetition")
    check(session.currentScene?.title, "Repetition", "newScene sets title")
    check(session.currentScene?.roles.count, 0, "newScene starts with no roles")
}

func testAddSceneRoleAppendsAndRemoveSceneRoleRemoves() {
    do {
        let session = ImprovSession()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano 1")
        check(session.currentScene?.roles.count, 1, "addSceneRole appends a role")
        check(session.currentScene?.roles.first?.name, "Piano 1", "addSceneRole sets the role's name")

        try session.removeSceneRole(roleID)
        check(session.currentScene?.roles.count, 0, "removeSceneRole removes the role")
    } catch {
        failures += 1
        print("FAIL [scene role add/remove]: threw \(error)")
    }
}

func testAddSceneRoleWithoutActiveSceneThrows() {
    let session = ImprovSession()
    do {
        _ = try session.addSceneRole(name: "Piano 1")
        failures += 1; checks += 1
        print("FAIL [addSceneRole without active scene throws]: did not throw")
    } catch {
        checks += 1 // expected
    }
}

func testAttachInstrumentAppliesRoleConfigurationAndAutoDetachesFromPreviousRole() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let pianoID = try session.addSceneRole(name: "Piano")
        let bassID = try session.addSceneRole(name: "Basse")
        try session.setSceneRoleListening(pianoID, isListening: true)

        try session.attachInstrument(.computerKeyboard, toRole: pianoID)
        check(session.currentScene?.roles.first { $0.id == pianoID }?.attachedTrackID, .computerKeyboard, "attachInstrument sets attachedTrackID")
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "attachInstrument starts the track per the role's own isListening")

        // Moving the SAME instrument to a different role must auto-detach it from the first,
        // not throw/reject — the actual regression this choke point exists to prevent.
        try session.attachInstrument(.computerKeyboard, toRole: bassID)
        checkNil(session.currentScene?.roles.first { $0.id == pianoID }?.attachedTrackID, "attachInstrument auto-detaches from the previous role")
        check(session.currentScene?.roles.first { $0.id == bassID }?.attachedTrackID, .computerKeyboard, "attachInstrument attaches to the new role")
    } catch {
        failures += 1
        print("FAIL [attachInstrument auto-detach]: threw \(error)")
    }
}

func testDetachInstrumentClearsAttachmentWithoutStoppingTrack() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")
        try session.setSceneRoleListening(roleID, isListening: true)
        try session.attachInstrument(.computerKeyboard, toRole: roleID)
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "instrument listening after attach")

        try session.detachInstrument(fromRole: roleID)
        checkNil(session.currentScene?.roles.first { $0.id == roleID }?.attachedTrackID, "detachInstrument clears the attachment")
        // Detaching is bookkeeping only — the instrument itself keeps listening, mirroring
        // `stopTrack`'s own "state survives a stop" convention.
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "detachInstrument doesn't stop the track")
    } catch {
        failures += 1
        print("FAIL [detachInstrument bookkeeping-only]: threw \(error)")
    }
}

func testAttachInstrumentThrowsForUnknownRoleOrTrack() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")

        do {
            try session.attachInstrument(.computerKeyboard, toRole: UUID())
            failures += 1; checks += 1
            print("FAIL [attachInstrument unknown role throws]: did not throw")
        } catch {
            checks += 1 // expected
        }
        do {
            try session.attachInstrument(.midiSource(99), toRole: roleID)
            failures += 1; checks += 1
            print("FAIL [attachInstrument unknown track throws]: did not throw")
        } catch {
            checks += 1 // expected
        }
    } catch {
        failures += 1
        print("FAIL [attachInstrument error paths]: threw \(error)")
    }
}

func testFreeSceneRolesAndUnassignedInstruments() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let pianoID = try session.addSceneRole(name: "Piano")
        _ = try session.addSceneRole(name: "Basse")
        try session.attachInstrument(.computerKeyboard, toRole: pianoID)

        check(session.freeSceneRoles().map(\.name), ["Basse"], "freeSceneRoles lists only unattached roles")
        check(session.unassignedInstruments().contains { $0.id == .computerKeyboard }, false, "attached instrument is not unassigned")
        check(session.unassignedInstruments().contains { $0.id == .microphone }, true, "never-attached instrument is unassigned")
    } catch {
        failures += 1
        print("FAIL [freeSceneRoles/unassignedInstruments]: threw \(error)")
    }
}

func testSceneSaveLoadRoundTripReattachesComputerKeyboardAndReportsFreeRoles() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Repetition")
        let pianoID = try session.addSceneRole(name: "Piano")
        _ = try session.addSceneRole(name: "Basse")
        try session.setSceneRoleListening(pianoID, isListening: true)
        try session.attachInstrument(.computerKeyboard, toRole: pianoID)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveScene(title: "Repetition", toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.start()
        try reloaded.loadScene(fromJSONFile: tempFile.path)

        check(reloaded.currentScene?.roles.count, 2, "loadScene restores both roles")
        let reloadedPiano = reloaded.currentScene?.roles.first { $0.name == "Piano" }
        check(reloadedPiano?.attachedTrackID, .computerKeyboard, "loadScene reattaches the computer keyboard automatically")
        check(reloaded.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "loadScene applies the role's isListening")
        let reloadedBasse = reloaded.currentScene?.roles.first { $0.name == "Basse" }
        checkNil(reloadedBasse?.attachedTrackID, "an unattached role stays free after loadScene")
        // The direct fix for the reported bug: a role that couldn't reattach is reported, not
        // silently dropped.
        check(reloaded.log.contains { $0.contains("Basse") && $0.contains("libre") }, true, "loadScene logs which roles stayed free")
    } catch {
        failures += 1
        print("FAIL [scene save/load round trip with roles]: threw \(error)")
    }
}

func testLoadSceneMigratesLegacyFlatTrackFormat() {
    do {
        let legacyJSON = """
        {"title": "Ancienne Scene", "tracks": [
            {"trackID": "clavier", "isListening": true, "soundEnabled": true, "instrumentName": "mcb.sf2"}
        ]}
        """
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try legacyJSON.write(to: tempFile, atomically: true, encoding: .utf8)

        let session = ImprovSession()
        try session.start()
        try session.loadScene(fromJSONFile: tempFile.path)

        check(session.currentScene?.title, "Ancienne Scene", "legacy scene title migrates")
        check(session.currentScene?.roles.count, 1, "legacy scene produces one role per saved track")
        let role = session.currentScene?.roles.first
        check(role?.name, "Clavier ordinateur", "legacy track auto-named from its wire id")
        check(role?.attachedTrackID, .computerKeyboard, "legacy role reattaches to the computer keyboard")
        check(role?.lastAttachedInstrument, .computerKeyboard, "legacy role gets a computerKeyboard identity hint")
    } catch {
        failures += 1
        print("FAIL [loadScene migrates legacy format]: threw \(error)")
    }
}

func testLoadSceneDoesNotReattachMidiMergedHintInIndividualMode() {
    do {
        // `.midiMerged` has no CoreMIDI dependency (a singleton, unlike `.midiSource`), so this
        // is the one `matches(_:_:)` case fully testable without real hardware — see
        // `ImprovSession.matches(_:_:)`'s own doc comment for why `.midiPort` matching isn't
        // covered here (it needs a real or injectable CoreMIDI source list this test suite has
        // no way to control).
        let scene = Scene(title: "Old Setup", roles: [
            SceneRole(name: "Synth", lastAttachedInstrument: .midiMerged),
        ])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(scene).write(to: tempFile)

        let session = ImprovSession()
        try session.start()
        session.setMIDIFusionMode(.individual) // no MIDI hardware here, so this yields zero midi tracks
        try session.loadScene(fromJSONFile: tempFile.path)

        checkNil(session.currentScene?.roles.first?.attachedTrackID, "a .midiMerged hint doesn't reattach while in individual mode")
    } catch {
        failures += 1
        print("FAIL [loadScene midiMerged mode gate]: threw \(error)")
    }
}

testNewSceneCreatesEmptyActiveScene()
testAddSceneRoleAppendsAndRemoveSceneRoleRemoves()
testAddSceneRoleWithoutActiveSceneThrows()
testAttachInstrumentAppliesRoleConfigurationAndAutoDetachesFromPreviousRole()
testDetachInstrumentClearsAttachmentWithoutStoppingTrack()
testAttachInstrumentThrowsForUnknownRoleOrTrack()
testFreeSceneRolesAndUnassignedInstruments()
testSceneSaveLoadRoundTripReattachesComputerKeyboardAndReportsFreeRoles()
testLoadSceneMigratesLegacyFlatTrackFormat()
testLoadSceneDoesNotReattachMidiMergedHintInIndividualMode()

func testColorPaletteFileRoundTrips() {
    let file = ColorPaletteFile(palettes: ColorPalette.builtInDefaults)
    do {
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ColorPaletteFile.self, from: data)
        check(decoded.palettes, ColorPalette.builtInDefaults, "ColorPaletteFile round-trips through JSON unchanged")
    } catch {
        failures += 1
        print("FAIL [ColorPaletteFile round trip]: threw \(error)")
    }
}
testColorPaletteFileRoundTrips()

func testBuiltInDefaultPalettesAreThreeDistinctFullPalettes() {
    check(ColorPalette.builtInDefaults.count, 3, "builtInDefaults has 3 palettes")
    check(Set(ColorPalette.builtInDefaults.map(\.name)).count, 3, "builtInDefaults palette names are distinct")
    for palette in ColorPalette.builtInDefaults {
        check(palette.colors.count, 12, "\(palette.name) has 12 colors")
        check(Set(palette.colors).count, 12, "\(palette.name)'s 12 colors are distinct")
        check(palette.textColors.count, 12, "\(palette.name) has 12 text colors")
        for textColor in palette.textColors {
            check(textColor == "#ffffff" || textColor == "#111111", true, "\(palette.name)'s text colors are all either white or black")
        }
    }
}
testBuiltInDefaultPalettesAreThreeDistinctFullPalettes()

// The user hand-specified this exact pattern (white for every note except A/E/B, which get
// black) — not something `legibleTextColors(for:)` is expected to reproduce on its own, so
// this is pinned literally rather than re-derived from `PitchClassPalette.hex`.
func testDefaultPaletteTextColorsMatchHandSpecifiedPattern() {
    let palette = ColorPalette.builtInDefaults[0]
    check(palette.name, "Default", "builtInDefaults[0] is Default")
    // index: 0=C 1=Db 2=D 3=Eb 4=E 5=F 6=F# 7=G 8=Ab 9=A 10=Bb 11=B
    let expected = [
        "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff",
        "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff", "#111111",
    ]
    check(palette.textColors, expected, "Default's text colors are white except A(9)/E(4)/B(11), which are black")
}
testDefaultPaletteTextColorsMatchHandSpecifiedPattern()

func testLegibleTextColorsUsesYIQBrightnessThreshold() {
    let textColors = ColorPalette.legibleTextColors(for: ["#ffffff", "#000000", "#ffe119"])
    check(textColors, ["#111111", "#ffffff", "#111111"], "legibleTextColors picks black for bright colors, white for dark ones")
}
testLegibleTextColorsUsesYIQBrightnessThreshold()

func testSessionStartsWithDefaultPaletteMatchingPitchClassPalette() {
    let session = ImprovSession()
    check(session.colorPalettes.count, 1, "a fresh session starts with exactly one (fallback) palette")
    check(session.activeColorPalette.name, "Default", "the fallback palette is named Default")
    check(session.activeColorPalette.colors, PitchClassPalette.hex, "the fallback palette's colors mirror PitchClassPalette.hex")
}
testSessionStartsWithDefaultPaletteMatchingPitchClassPalette()

func testLoadOrCreateColorPalettesWritesBuiltInDefaultsOnFirstRunThenLoadsThem() {
    do {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        check(FileManager.default.fileExists(atPath: tempFile.path), false, "the file doesn't exist yet")

        let session = ImprovSession()
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)
        check(FileManager.default.fileExists(atPath: tempFile.path), true, "loadOrCreateColorPalettes creates the file")
        check(session.colorPalettes, ColorPalette.builtInDefaults, "loadOrCreateColorPalettes loads the freshly-written built-in defaults")
        check(session.activeColorPalette.name, "Default", "the first palette in the file is active after loading")

        // A second session pointed at the SAME (now-existing) file must not overwrite it —
        // only ever create it once.
        try session.selectColorPalette(named: "Pastel")
        let reloaded = ImprovSession()
        try reloaded.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)
        check(reloaded.colorPalettes, ColorPalette.builtInDefaults, "loadOrCreateColorPalettes doesn't overwrite an existing file")
    } catch {
        failures += 1
        print("FAIL [loadOrCreateColorPalettes]: threw \(error)")
    }
}
testLoadOrCreateColorPalettesWritesBuiltInDefaultsOnFirstRunThenLoadsThem()

func testSelectColorPaletteByNameAndIndexAndRejectsInvalid() {
    do {
        let session = ImprovSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)

        try session.selectColorPalette(named: "Contraste")
        check(session.activeColorPalette.name, "Contraste", "selectColorPalette(named:) switches the active palette")

        try session.selectColorPalette(atIndex: 2)
        check(session.activeColorPalette.name, "Pastel", "selectColorPalette(atIndex:) switches the active palette (0-based)")

        do {
            try session.selectColorPalette(named: "Not A Real Palette")
            failures += 1
            print("FAIL [selectColorPalette invalid name]: did not throw")
        } catch ImprovSession.SessionError.invalidColorPaletteIndex {
            // expected
        } catch {
            failures += 1
            print("FAIL [selectColorPalette invalid name]: wrong error \(error)")
        }

        do {
            try session.selectColorPalette(atIndex: 99)
            failures += 1
            print("FAIL [selectColorPalette invalid index]: did not throw")
        } catch ImprovSession.SessionError.invalidColorPaletteIndex {
            // expected
        } catch {
            failures += 1
            print("FAIL [selectColorPalette invalid index]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [selectColorPalette]: setup threw \(error)")
    }
}
testSelectColorPaletteByNameAndIndexAndRejectsInvalid()

func testLoadColorPalettesThrowsOnEmptyPalettesFile() {
    do {
        let session = ImprovSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(ColorPaletteFile(palettes: [])).write(to: tempFile)
        do {
            try session.loadColorPalettes(fromJSONFile: tempFile.path)
            failures += 1
            print("FAIL [loadColorPalettes empty file]: did not throw")
        } catch ImprovSession.SessionError.emptyColorPaletteFile {
            // expected
        } catch {
            failures += 1
            print("FAIL [loadColorPalettes empty file]: wrong error \(error)")
        }
        // And the previous (fallback) palette must still be there — a failed load shouldn't
        // have cleared anything.
        check(session.colorPalettes.count, 1, "a failed load leaves the existing palettes untouched")
    } catch {
        failures += 1
        print("FAIL [loadColorPalettes empty file]: setup threw \(error)")
    }
}
testLoadColorPalettesThrowsOnEmptyPalettesFile()

// Real HTTP round trip: the active palette's colors must appear in BOTH the web console's
// and the virtual keyboard's `/state`, and switching palettes must be reflected on the very
// next poll — no page reload, no server restart.
func testActiveColorPaletteIsReflectedInWebConsoleAndVirtualKeyboardState() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)

        try session.startWebConsole(port: 18400)
        try session.startVirtualKeyboard(port: 18401)
        Thread.sleep(forTimeInterval: 0.3)

        if let consoleState = syncGET("http://127.0.0.1:18400/state") {
            check(consoleState.body.contains("\"palette\":[\"#DB2A52\""), true, "web console /state reflects the Default palette's first color")
            check(consoleState.body.contains("\"paletteTextColors\":[\"#ffffff\""), true, "web console /state reflects the Default palette's first text color")
        } else {
            failures += 1
            print("FAIL [palette in web console state]: no response")
        }
        if let vkState = syncGET("http://127.0.0.1:18401/state?client=palette-test&name=Test") {
            check(vkState.body.contains("\"palette\":[\"#DB2A52\""), true, "virtual keyboard /state reflects the Default palette's first color")
            check(vkState.body.contains("\"paletteTextColors\":[\"#ffffff\""), true, "virtual keyboard /state reflects the Default palette's first text color")
        } else {
            failures += 1
            print("FAIL [palette in virtual keyboard state]: no response")
        }

        try session.selectColorPalette(named: "Pastel")
        Thread.sleep(forTimeInterval: 0.3)

        if let consoleState = syncGET("http://127.0.0.1:18400/state") {
            check(consoleState.body.contains("\"palette\":[\"#FFADAD\""), true, "web console /state reflects the switch to Pastel on the next poll")
            check(consoleState.body.contains("\"paletteTextColors\":[\"#111111\""), true, "web console /state reflects Pastel's all-black text colors on the next poll")
        } else {
            failures += 1
            print("FAIL [palette switch in web console state]: no response")
        }
        if let vkState = syncGET("http://127.0.0.1:18401/state?client=palette-test&name=Test") {
            check(vkState.body.contains("\"palette\":[\"#FFADAD\""), true, "virtual keyboard /state reflects the switch to Pastel on the next poll")
            check(vkState.body.contains("\"paletteTextColors\":[\"#111111\""), true, "virtual keyboard /state reflects Pastel's all-black text colors on the next poll")
        } else {
            failures += 1
            print("FAIL [palette switch in virtual keyboard state]: no response")
        }

        session.stopWebConsole()
        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [palette in HTTP state]: threw \(error)")
    }
}
testActiveColorPaletteIsReflectedInWebConsoleAndVirtualKeyboardState()

func testGuideSequenceSaveAndLoadRoundTrips() {
    do {
        let session = ImprovSession()
        session.newGuideSequence(title: "Round Trip")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveGuideSequence(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadGuideSequence(fromJSONFile: tempFile.path)
        check(reloaded.currentGuide, session.currentGuide, "guide sequence round-trips through JSON")
        checkNil(reloaded.currentGuideStepIndex, "loading a guide sequence resets the current step index")
    } catch {
        failures += 1
        print("FAIL [guide sequence save/load round trip]: threw \(error)")
    }
}

func testGuideStepWithChordProgressionRoundTripsThroughJSON() {
    do {
        let session = ImprovSession()
        session.newGuideSequence(title: "With Progression")
        let blues = ChordProgressionTemplate.builtInDefaults[0] // "Blues 12 mesures"
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: blues)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveGuideSequence(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadGuideSequence(fromJSONFile: tempFile.path)
        check(reloaded.currentGuide?.steps.first?.chordProgressionName, "Blues 12 mesures", "chord progression name round-trips")
        check(reloaded.currentGuide?.steps.first?.chordProgression?.count, 12, "chord progression round-trips with all 12 chords")
    } catch {
        failures += 1
        print("FAIL [guide step chord progression round trip]: threw \(error)")
    }
}

/// Every guide file saved before chord progressions existed stores each step as a bare
/// `ModeReference` (no "mode" key) — `GuideStep.init(from:)` must still load these.
func testGuideStepDecodesOldBareModeReferenceFormat() {
    let json = #"{"title":"Old Format","steps":[{"scaleID":"dorian","tonic":2}]}"#.data(using: .utf8)!
    do {
        let decoded = try JSONDecoder().decode(GuideSequence.self, from: json)
        check(decoded.steps.count, 1, "old-format guide file decodes its one step")
        check(decoded.steps.first?.mode, ModeReference(tonic: 2, scaleID: "dorian"), "old-format step's bare ModeReference becomes GuideStep.mode")
        checkNil(decoded.steps.first?.chordProgressionName, "old-format step has no chord progression name")
        checkNil(decoded.steps.first?.chordProgression, "old-format step has no chord progression")
    } catch {
        failures += 1
        print("FAIL [old-format guide step decode]: threw \(error)")
    }
}

func testRomanNumeralChordParseHandlesUpperLowerAndDiminished() {
    check(RomanNumeralChord.parse("I")?.quality, .major, "I is major")
    check(RomanNumeralChord.parse("I")?.degree, 1, "I is degree 1")
    check(RomanNumeralChord.parse("vi")?.quality, .minor, "vi is minor")
    check(RomanNumeralChord.parse("vi")?.degree, 6, "vi is degree 6")
    check(RomanNumeralChord.parse("vii°")?.quality, .diminished, "vii° is diminished")
    check(RomanNumeralChord.parse("vii°")?.degree, 7, "vii° is degree 7")
    checkNil(RomanNumeralChord.parse("VIII"), "VIII is not a valid roman numeral (out of range)")
    checkNil(RomanNumeralChord.parse("xyz"), "garbage text does not parse")
}

func testResolveChordProgressionAppliesLiteralCaseAsQualityInCIonian() {
    let session = ImprovSession()
    let mode = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("ionian")!)
    let blues = ChordProgressionTemplate.builtInDefaults[0] // I I I I IV IV I I V IV I I
    let resolved = session.resolveChordProgression(blues, in: mode)
    check(resolved.count, 12, "blues progression resolves to 12 chords")
    check(resolved.first?.root, 0, "first chord (I) is rooted on C")
    check(resolved.first?.chordTemplateID, "Ma", "I is taken literally as major")
    check(resolved[4].root, 5, "5th chord (IV) is rooted on F")
    check(resolved[8].root, 7, "9th chord (V) is rooted on G")
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

testCircleOfFifthsPhysicalOrderIsFixedAscendingFifthsFromC()
testCircleOfFifthsCTonicModeNamePositions()
testCircleOfFifthsMinorAndDiminishedRingsHaveTheirOwnSpelling()
testCircleOfFifthsCTonicDiatonicCellsMatchExpectedQualityAndDegree()
testCircleOfFifthsMinorAndDiminishedCellsAreOffsetFromTheirColumn()
testCircleOfFifthsActiveTonicPutsDegreeIOnTheModesOwnTonicNotTheParents()
testCircleOfFifthsShapeAlternatesByCellPitchClassParity()
testCircleOfFifthsDDorianParentTonicMatchesCIonian()
testCircleOfFifthsParentTonicNonFamily1ReturnsNil()
testPitchClassPaletteHas12DistinctEntries()

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
testMIDIRunningStatusNoteOnIsParsedWithoutARepeatedStatusByte()
testMIDIRunningStatusNoteOffIsParsedWithoutARepeatedStatusByte()
testMIDINonNoteStatusByteResetsRunningStatus()

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
testDefaultMIDIFusionModeIsIndividual()
testSetMIDIFusionModeSwitchesTrackList()
testMicrophoneTrackCannotHaveSound()
testSetMicrophoneRecognitionModeRejectsNonMicrophoneTrack()
testSetMicrophoneRecognitionModeRejectsInvalidWindowCount()
testSetMicrophoneRecognitionModeSurvivesTrackRestart()
testMicrophonePolyLatchedDoesNotConfirmAFlickeringNote()
testMicrophonePolySlidingConfirmsUnderMajorityDespiteOneDropout()
testMicrophoneMonophonicModeConfirmsImmediately()
testSaveThenLoadRoundTripsThePieceThroughJSON()
testLoadingAMissingFileThrows()
testListPieceFilesFindsJSONFilesAndIgnoresOthers()
testUsePieceByIndexAndNameLoadFromTheListedFolder()
testSaveWithoutEverLoadingOrSavingThrows()
testSaveAsThenBareSaveRoundTripToTheSameFile()
testSaveAsWithoutAPieceFolderListedThrowsForABareName()

testNewGuideSequenceThenAddStepsThenStartAndAdvance()
testAddGuideStepWithoutASequenceThrows()
testAddGuideStepWithUnknownScaleIDThrowsAndDoesNotAppendAStep()
testGuideSequenceSaveAndLoadRoundTrips()
testGuideStepWithChordProgressionRoundTripsThroughJSON()
testGuideStepDecodesOldBareModeReferenceFormat()
testRomanNumeralChordParseHandlesUpperLowerAndDiminished()
testResolveChordProgressionAppliesLiteralCaseAsQualityInCIonian()
testTrackIDWireIDTextRoundTrips()
testSceneSaveAndLoadRoundTripsTrackListeningAndSound()
testLoadSceneLeavesTracksNotMentionedUntouched()

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
        // Default fusion mode is now `.individual` (no `.midiMerged` track exists until
        // switched) — this test exercises `.midiMerged` specifically, not the default.
        session.setMIDIFusionMode(.merged)
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

func testTrackRecordsMostRecentMIDIChannel() {
    let session = ImprovSession()
    session.setMIDIFusionMode(.merged)
    do {
        try session.startTrack(.midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.lastChannel, nil, "lastChannel is nil before any note event")
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 3), track: .midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.lastChannel, 3, "lastChannel reflects the most recent note event's channel")
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 7), track: .midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.lastChannel, 7, "lastChannel updates on a later event with a different channel")
    } catch {
        failures += 1
        print("FAIL [track records most recent MIDI channel]: threw \(error)")
    }
}
testTrackRecordsMostRecentMIDIChannel()

// Deliberately single notes throughout (not a 3-note chord built one pitch at a time) to keep
// the expected event count unambiguous — playing a chord note by note legitimately produces
// one event per intermediate held-pitches snapshot (1 note, then 2, then 3), the whole point of
// this feature (nothing in between gets skipped), not something to work around here.
func testRecentChordEventsLogsChangesAndSkipsRestsOnFullRelease() {
    checks += 1
    do {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
        try session.startTrack(.midiMerged)
        func events() -> [WebConsoleChordEvent] {
            session.buildWebConsoleState().tracks.first { $0.id == "midi" }?.recentChordEvents ?? []
        }

        if events().count != 0 {
            failures += 1
            print("FAIL [recentChordEvents starts empty]: \(events().count)")
        }

        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0), track: .midiMerged)
        if events().count != 1 || events().last?.pitches != [60] {
            failures += 1
            print("FAIL [recentChordEvents records first note]: \(events())")
        }

        // A full release must NOT append a blank "rest" entry — the pitch-60 event stays last.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0), track: .midiMerged)
        if events().count != 1 {
            failures += 1
            print("FAIL [recentChordEvents skips a blank rest entry on full release]: \(events())")
        }

        // A different note is a genuinely new, distinct event.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 0), track: .midiMerged)
        if events().count != 2 || events().last?.pitches != [62] {
            failures += 1
            print("FAIL [recentChordEvents records a second distinct note]: \(events())")
        }

        // Repeated note-on for an already-held pitch (e.g. a hardware retrigger) is the exact
        // same snapshot again — must not append a duplicate.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 0), track: .midiMerged)
        if events().count != 2 {
            failures += 1
            print("FAIL [recentChordEvents skips a duplicate of the unchanged snapshot]: \(events())")
        }

        session.stopTrack(.midiMerged)
        if events().count != 0 {
            failures += 1
            print("FAIL [recentChordEvents clears on stopTrack]: \(events())")
        }
    } catch {
        failures += 1
        print("FAIL [recentChordEvents]: threw \(error)")
    }
}
testRecentChordEventsLogsChangesAndSkipsRestsOnFullRelease()

func testRecentChordEventsCapsAtTwentyEntries() {
    checks += 1
    do {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
        try session.startTrack(.midiMerged)
        func events() -> [WebConsoleChordEvent] {
            session.buildWebConsoleState().tracks.first { $0.id == "midi" }?.recentChordEvents ?? []
        }
        for pitch in 60..<85 {
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0), track: .midiMerged)
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: pitch, velocity: 0, channel: 0), track: .midiMerged)
        }
        if events().count != 20 || events().last?.pitches != [84] || events().first?.pitches != [65] {
            failures += 1
            print("FAIL [recentChordEvents caps at 20 entries]: count=\(events().count) first=\(String(describing: events().first?.pitches)) last=\(String(describing: events().last?.pitches))")
        }
    } catch {
        failures += 1
        print("FAIL [recentChordEvents caps at 20 entries]: threw \(error)")
    }
}
testRecentChordEventsCapsAtTwentyEntries()

// MARK: - Read-only structure detail (piece/composition/guide/soundtrack) — mirrors
// Tests/AppCoreTests/ImprovSessionTests.swift's tests of the same name.

func testBuildPieceDetailReflectsWholeStructureIncludingEmptyTracks() {
    do {
        let session = ImprovSession()
        check(session.buildPieceDetail().loaded, false, "buildPieceDetail reports not loaded with no piece")

        let trackWithNotes = Track(name: "lead", instrument: "mcb.sf2", melodyEvents: [
            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60),
        ])
        // The real regression this route fixes: `pieceDetailLines()` (the terminal's own
        // piece display) silently skips any track with zero `melodyEvents` — a fragment-only
        // track just vanishes. `buildPieceDetail()` must not repeat that mistake.
        let emptyTrack = Track(name: "fragment-only", instrument: "")
        let chord = ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))
        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [chord], tracks: [trackWithNotes, emptyTrack]
        )
        let piece = Piece(title: "Detail Test", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadPiece(fromJSONFile: tempFile.path)

        let detail = session.buildPieceDetail()
        check(detail.loaded, true, "buildPieceDetail reports loaded once a piece is loaded")
        check(detail.sections?.count, 1, "buildPieceDetail section count")
        check(detail.sections?[0].chordProgression.first?.chord.label, "CMa7", "buildPieceDetail resolves a chord label")
        check(detail.sections?[0].tracks.count, 2, "buildPieceDetail keeps every track, including empty ones")
        let hasEmptyTrack = detail.sections?[0].tracks.contains { $0.name == "fragment-only" && $0.melodyEvents.isEmpty } ?? false
        check(hasEmptyTrack, true, "buildPieceDetail includes a track with zero melody events")
    } catch {
        failures += 1
        print("FAIL [buildPieceDetail]: threw \(error)")
    }
}
testBuildPieceDetailReflectsWholeStructureIncludingEmptyTracks()

func testBuildCompositionDetailReflectsStagedTextAndResolvedPrompt() {
    let session = ImprovSession()
    let empty = session.buildCompositionDetail()
    checkNil(empty.sourceText, "buildCompositionDetail has no source text before anything is staged")
    checkNil(empty.resolvedPrompt, "buildCompositionDetail has no resolved prompt before anything is staged")

    session.setSourceText("a quiet lake at dusk")
    session.setCompositionTitle("Lake Piece")
    session.setAdditionalCompositionInstructions("impressionist, slow tempo")

    let detail = session.buildCompositionDetail()
    check(detail.title, "Lake Piece", "buildCompositionDetail title")
    check(detail.sourceText, "a quiet lake at dusk", "buildCompositionDetail source text")
    check(detail.additionalInstructions, "impressionist, slow tempo", "buildCompositionDetail instructions")
    check(detail.resolvedPrompt?.contains("a quiet lake at dusk") ?? false, true, "buildCompositionDetail resolved prompt contains the source text")
}
testBuildCompositionDetailReflectsStagedTextAndResolvedPrompt()

func testBuildGuideDetailReflectsAllStepsNotJustCurrent() {
    do {
        let session = ImprovSession()
        check(session.buildGuideDetail().loaded, false, "buildGuideDetail reports not loaded with no guide")

        session.newGuideSequence(title: "Explore")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.startGuide()

        let detail = session.buildGuideDetail()
        check(detail.loaded, true, "buildGuideDetail reports loaded once a guide is loaded")
        check(detail.title, "Explore", "buildGuideDetail title")
        check(detail.steps?.count, 2, "buildGuideDetail step count")
        check(detail.currentStepIndex, 0, "buildGuideDetail current step index")
        check(detail.steps?[0].isCurrent, true, "buildGuideDetail flags the current step")
        // The real regression this route fixes: `GET /state`'s own `guide` field only ever
        // exposes the CURRENT step's mode/chords — a non-current step's own detail must
        // still be reported here.
        check(detail.steps?[1].isCurrent, false, "buildGuideDetail correctly flags a non-current step")
        check(detail.steps?[1].mode.scaleID, "mixolydian", "buildGuideDetail reports a non-current step's own scale")
        check(detail.steps?[1].mode.tonicName, "G", "buildGuideDetail reports a non-current step's own tonic name")
    } catch {
        failures += 1
        print("FAIL [buildGuideDetail]: threw \(error)")
    }
}
testBuildGuideDetailReflectsAllStepsNotJustCurrent()

func testBuildSoundTrackDetailReflectsEventsAndTrackIDs() {
    do {
        let session = ImprovSession()
        check(session.buildSoundTrackDetail().loaded, false, "buildSoundTrackDetail reports not loaded with no soundtrack")

        try session.startRecording(title: "Detail Test")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        let detail = session.buildSoundTrackDetail()
        check(detail.loaded, true, "buildSoundTrackDetail reports loaded once a soundtrack is recorded")
        check(detail.title, "Detail Test", "buildSoundTrackDetail title")
        check(detail.events?.count, 2, "buildSoundTrackDetail event count")
        check(detail.trackIDs, ["clavier"], "buildSoundTrackDetail track ids")
    } catch {
        failures += 1
        print("FAIL [buildSoundTrackDetail]: threw \(error)")
    }
}
testBuildSoundTrackDetailReflectsEventsAndTrackIDs()

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
testFFTDominantFrequencyLocksOntoStrongSecondHarmonicWhenFundamentalIsWeak()
testMonophonicFundamentalHeuristicRecoversWeakFundamentalUnderStrongSecondHarmonic()
testMonophonicFundamentalHeuristicMatchesPlainPeakForAPureTone()
testMonophonicFundamentalHeuristicReturnsNilForSilence()
testMonophonicFundamentalHPSRecoversWeakFundamentalUnderStrongSecondHarmonic()
testMonophonicFundamentalHPSMatchesPlainPeakForAPureTone()
testMonophonicFundamentalHPSReturnsNilForSilence()
testPassthroughConfirmsEveryWindowImmediately()
testLatchedRejectsFlickerShorterThanN()
testLatchedConfirmsNoteOnAfterNConsecutiveWindows()
testLatchedConfirmsNoteOffOnlyAfterNConsecutiveAbsences()
testSlidingConfirmsByMajorityNotConsecutive()
testSlidingToleratesOneDroppedWindow()
testWindowsOfOneMatchesPassthroughForBothPolicies()
testMultiplePitchesTrackedIndependently()
testStabilizerResetClearsHistoryAndConfirmedPitches()

// MARK: - Localization (FR/EN/DE UI text) — mirrors Tests/AppCoreTests, no XCTest equivalent yet

func testEveryL10nKeyHasAllThreeLanguages() {
    for key in L10nKey.allCases {
        for language in AppLanguage.allCases {
            let value = L10n.string(key, language)
            checks += 1
            if value == key.rawValue {
                failures += 1
                print("FAIL [L10nKey completeness]: \(key.rawValue) has no \(language.rawValue) translation")
            }
        }
    }
}

func testLoadOrCreateLanguageSettingDefaultsToFrenchAndRoundTrips() {
    do {
        let session = ImprovSession()
        try session.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let path = folder.appendingPathComponent("language.json").path

        try session.loadOrCreateLanguageSetting(fromJSONFile: path)
        check(session.currentLanguage, .fr, "loadOrCreateLanguageSetting defaults to French on a fresh file")
        checks += 1
        if !FileManager.default.fileExists(atPath: path) {
            failures += 1
            print("FAIL [loadOrCreateLanguageSetting creates language.json]: file missing")
        }

        // `setLanguage` only rewrites language.json once `settingsFolder` is set (mirrors
        // `selectColorPalette`'s "in-memory only" default, but this one also persists on change).
        try session.setSettingsFolder(folder.path)
        try session.setLanguage(.de)
        let reloaded = ImprovSession()
        try reloaded.start()
        try reloaded.loadLanguageSetting(fromJSONFile: path)
        check(reloaded.currentLanguage, .de, "language.json round-trips the selected language across a fresh ImprovSession")
    } catch {
        failures += 1
        print("FAIL [loadOrCreateLanguageSetting default+roundtrip]: threw \(error)")
    }
}

func testSetLanguageUpdatesCurrentLanguageAndWebConsoleState() {
    do {
        let session = ImprovSession()
        try session.start()
        try session.setLanguage(.de)
        check(session.currentLanguage, .de, "setLanguage(.de) updates currentLanguage")
        check(session.buildWebConsoleState().language, "de", "buildWebConsoleState().language reflects the current language")
    } catch {
        failures += 1
        print("FAIL [setLanguage updates state]: threw \(error)")
    }
}

testEveryL10nKeyHasAllThreeLanguages()
testLoadOrCreateLanguageSettingDefaultsToFrenchAndRoundTrips()
testSetLanguageUpdatesCurrentLanguageAndWebConsoleState()

// MARK: - LumiSysexTests (mirrors Tests/MIDIEngineTests/LumiSysexTests.swift) — every
// expected byte array below was generated by running the actual reverse-engineered
// `lumi_sysex.js` (github.com/benob/LUMI-lights) under Node with `send_sysex` stubbed to
// capture its output, not hand-derived, and cross-checked against `SYSEX.txt`'s own
// captured-from-ROLI-Dashboard examples for the six named colors and the 0/25/50/75/100%
// brightness steps — this is a from-scratch Swift port, not a translation reviewed line by
// line, so byte-for-byte agreement with an independent JS run is the real assurance here.
// Device-id byte updated from that JS's `0x37` to `0x34` after capturing a real ROLI
// Dashboard session with MIDI Monitor against actual hardware — see LumiSysex.envelope's
// doc comment. The checksum bytes below were untouched by that fix (checksum only covers
// the 8-byte payload, not the device-id byte) and matched the live capture exactly.

func testLumiSetColorAllKeysRed() {
    check(LumiSysex.setColor(.allKeys, red: 255, green: 0, blue: 0),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x20, 0x04, 0x00, 0x00, 0x7F, 0x7F, 0x03, 0x1B, 0xF7],
          "lumi setColor(.allKeys, red) matches reference JS")
}

func testLumiSetColorAllKeysGreen() {
    check(LumiSysex.setColor(.allKeys, red: 0, green: 255, blue: 0),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x20, 0x04, 0x40, 0x7F, 0x00, 0x7E, 0x03, 0x46, 0xF7],
          "lumi setColor(.allKeys, green) matches reference JS")
}

func testLumiSetColorAllKeysBlue() {
    check(LumiSysex.setColor(.allKeys, red: 0, green: 0, blue: 255),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x20, 0x64, 0x3F, 0x00, 0x00, 0x7E, 0x03, 0x30, 0xF7],
          "lumi setColor(.allKeys, blue) matches reference JS")
}

func testLumiSetColorRootArbitraryRGB() {
    check(LumiSysex.setColor(.root, red: 128, green: 64, blue: 32),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x04, 0x08, 0x20, 0x00, 0x7F, 0x03, 0x1C, 0xF7],
          "lumi setColor(.root, ...) matches reference JS — also confirms .root really sends 0x30, not 0x20")
}

func testLumiSetColorAllKeysArbitraryRGB() {
    check(LumiSysex.setColor(.allKeys, red: 17, green: 200, blue: 99),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x20, 0x64, 0x18, 0x64, 0x11, 0x7E, 0x03, 0x7E, 0xF7],
          "lumi setColor non-saturated RGB matches reference JS (exercises the bit packer's carry-over path)")
}

func testLumiSetBrightnessZeroPercent() {
    check(LumiSysex.setBrightness(0),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x44, 0xF7],
          "lumi setBrightness(0) matches SYSEX.txt's 0% example")
}

func testLumiSetBrightnessFiftyPercent() {
    check(LumiSysex.setBrightness(50),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x44, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x50, 0xF7],
          "lumi setBrightness(50) matches SYSEX.txt's 50% example")
}

func testLumiSetBrightnessHundredPercent() {
    check(LumiSysex.setBrightness(100),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x04, 0x19, 0x00, 0x00, 0x00, 0x00, 0x2D, 0xF7],
          "lumi setBrightness(100) matches SYSEX.txt's 100% example")
}

func testLumiSetColorModeAllFiveVariants() {
    // Expected bytes are a live MIDI Monitor capture of ROLI Dashboard's own five mode
    // menu entries against the real hardware (2026-07-20) — see LumiSysex.ColorMode's
    // doc comment for why these replaced SYSEX.txt's four-mode table.
    check(LumiSysex.setColorMode(.user),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x3C, 0xF7],
          "lumi setColorMode(.user) matches live Dashboard capture")
    check(LumiSysex.setColorMode(.pro),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x5C, 0xF7],
          "lumi setColorMode(.pro) matches live Dashboard capture")
    check(LumiSysex.setColorMode(.stage),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x6C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7C, 0xF7],
          "lumi setColorMode(.stage) matches live Dashboard capture")
    check(LumiSysex.setColorMode(.piano),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x4C, 0x00, 0x00, 0x00, 0x00, 0x00, 0x1C, 0xF7],
          "lumi setColorMode(.piano) matches live Dashboard capture")
    check(LumiSysex.setColorMode(.rainbow),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x40, 0x0C, 0x01, 0x00, 0x00, 0x00, 0x00, 0x2D, 0xF7],
          "lumi setColorMode(.rainbow) matches live Dashboard capture")
}

func testLumiSetScaleSamples() {
    // `.blues` and `.lydian` are the two entries independently confirmed byte-for-byte via
    // live Dashboard capture (2026-07-20) — see LumiSysex.Scale's doc comment. The rest are
    // SYSEX.txt's own table, trusted on that table's strength (this checksum algorithm has
    // been right every other time it's been checked against real hardware).
    check(LumiSysex.setScale(.major),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x60, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x7E, 0xF7],
          "lumi setScale(.major)")
    check(LumiSysex.setScale(.dorian),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x60, 0x62, 0x01, 0x00, 0x00, 0x00, 0x00, 0x6F, 0xF7],
          "lumi setScale(.dorian)")
    check(LumiSysex.setScale(.blues),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x60, 0x42, 0x01, 0x00, 0x00, 0x00, 0x00, 0x0F, 0xF7],
          "lumi setScale(.blues) matches live Dashboard capture")
    check(LumiSysex.setScale(.lydian),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x60, 0x22, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xF7],
          "lumi setScale(.lydian) matches live Dashboard capture")
    check(LumiSysex.setScale(.chromatic),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x60, 0x42, 0x04, 0x00, 0x00, 0x00, 0x00, 0x02, 0xF7],
          "lumi setScale(.chromatic)")
}

// MARK: - LumiColorMapTests (mirrors Tests/AppCoreTests/LumiColorMapTests.swift)

func testLumiColorMapDirectlyMappedScales() {
    check(LumiColorMap.lumiScale(forScaleID: "ionian"), .major, "lumi color map ionian->major")
    check(LumiColorMap.lumiScale(forScaleID: "aeolian"), .minor, "lumi color map aeolian->minor")
    check(LumiColorMap.lumiScale(forScaleID: "harmonic_minor"), .harmonicMinor, "lumi color map harmonic_minor")
    check(LumiColorMap.lumiScale(forScaleID: "dorian"), .dorian, "lumi color map dorian")
    check(LumiColorMap.lumiScale(forScaleID: "phrygian"), .phrygian, "lumi color map phrygian")
    check(LumiColorMap.lumiScale(forScaleID: "lydian"), .lydian, "lumi color map lydian")
    check(LumiColorMap.lumiScale(forScaleID: "mixolydian"), .mixolydian, "lumi color map mixolydian")
    check(LumiColorMap.lumiScale(forScaleID: "locrian"), .locrian, "lumi color map locrian")
    check(LumiColorMap.lumiScale(forScaleID: "whole_tone"), .wholeTone, "lumi color map whole_tone")
}

func testLumiColorMapFallsBackToChromaticForUnmappedScales() {
    check(LumiColorMap.lumiScale(forScaleID: "melodic_minor"), nil, "lumi color map melodic_minor has no native equivalent")
    check(LumiColorMap.lumiScale(forScaleID: "altered"), nil, "lumi color map altered has no native equivalent")
    check(LumiColorMap.lumiScale(forScaleID: "diminished"), nil, "lumi color map diminished has no native equivalent")
    check(LumiColorMap.lumiScale(forScaleID: "augmented"), nil, "lumi color map augmented has no native equivalent")
    check(LumiColorMap.lumiScale(forScaleID: "not_a_real_scale_id"), nil, "lumi color map unknown id has no native equivalent")
}

func testLumiSetKeyAllTwelvePitchClasses() {
    // C, C#, D, D#, A, A#, B confirmed byte-for-byte via live Dashboard capture
    // (2026-07-20); E, F, F#, G, G# are derived from the same BitPacker fed the pattern
    // that fit all 7 confirmed notes — see LumiSysex.setKey's doc comment.
    check(LumiSysex.setKey(pitchClass: 0),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x03, 0x00, 0x00, 0x00, 0x00, 0x00, 0x41, 0xF7],
          "lumi setKey(C) matches live Dashboard capture")
    check(LumiSysex.setKey(pitchClass: 1),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x23, 0x00, 0x00, 0x00, 0x00, 0x00, 0x21, 0xF7],
          "lumi setKey(C#) matches live Dashboard capture")
    check(LumiSysex.setKey(pitchClass: 2),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x43, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0xF7],
          "lumi setKey(D) matches live Dashboard capture")
    check(LumiSysex.setKey(pitchClass: 3),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x63, 0x00, 0x00, 0x00, 0x00, 0x00, 0x61, 0xF7],
          "lumi setKey(D#) matches live Dashboard capture")
    check(LumiSysex.setKey(pitchClass: 4),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x03, 0x01, 0x00, 0x00, 0x00, 0x00, 0x12, 0xF7],
          "lumi setKey(E) — derived, not directly captured")
    check(LumiSysex.setKey(pitchClass: 5),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x23, 0x01, 0x00, 0x00, 0x00, 0x00, 0x72, 0xF7],
          "lumi setKey(F) — derived, not directly captured")
    check(LumiSysex.setKey(pitchClass: 6),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x43, 0x01, 0x00, 0x00, 0x00, 0x00, 0x52, 0xF7],
          "lumi setKey(F#) — derived, not directly captured")
    check(LumiSysex.setKey(pitchClass: 7),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x63, 0x01, 0x00, 0x00, 0x00, 0x00, 0x32, 0xF7],
          "lumi setKey(G) — derived, not directly captured")
    check(LumiSysex.setKey(pitchClass: 8),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x03, 0x02, 0x00, 0x00, 0x00, 0x00, 0x63, 0xF7],
          "lumi setKey(G#) — derived, not directly captured")
    check(LumiSysex.setKey(pitchClass: 9),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x23, 0x02, 0x00, 0x00, 0x00, 0x00, 0x43, 0xF7],
          "lumi setKey(A) matches live Dashboard capture")
    check(LumiSysex.setKey(pitchClass: 10),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x43, 0x02, 0x00, 0x00, 0x00, 0x00, 0x23, 0xF7],
          "lumi setKey(A#) matches live Dashboard capture")
    check(LumiSysex.setKey(pitchClass: 11),
          [0xF0, 0x00, 0x21, 0x10, 0x77, 0x34, 0x10, 0x30, 0x63, 0x02, 0x00, 0x00, 0x00, 0x00, 0x03, 0xF7],
          "lumi setKey(B) matches live Dashboard capture")
}

testLumiSetColorAllKeysRed()
testLumiSetColorAllKeysGreen()
testLumiSetColorAllKeysBlue()
testLumiSetColorRootArbitraryRGB()
testLumiSetColorAllKeysArbitraryRGB()
testLumiSetBrightnessZeroPercent()
testLumiSetBrightnessFiftyPercent()
testLumiSetBrightnessHundredPercent()
testLumiSetColorModeAllFiveVariants()
testLumiSetScaleSamples()
testLumiColorMapDirectlyMappedScales()
testLumiColorMapFallsBackToChromaticForUnmappedScales()
testLumiSetKeyAllTwelvePitchClasses()

// MARK: - LumiGuideMapTests (mirrors Tests/AppCoreTests/LumiGuideMapTests.swift)

func testLumiGuideMapMessagesOrderAndContentForADirectlyMappedScale() {
    let messages = LumiGuideMap.messages(
        mode: ModeReference(tonic: 0, scaleID: "ionian"),
        rootColor: (red: 255, green: 0, blue: 0),
        scaleColor: (red: 0, green: 0, blue: 255),
        brightnessPercentage: 75
    )
    check(messages.count, 6, "lumi guide map produces 6 ordered messages")
    check(messages[0], LumiSysex.setColorMode(.user), "lumi guide map message 0 is setColorMode(.user)")
    check(messages[1], LumiSysex.setKey(pitchClass: 0), "lumi guide map message 1 is setKey for the tonic")
    check(messages[2], LumiSysex.setScale(.major), "lumi guide map message 2 is setScale mapped from ionian")
    check(messages[3], LumiSysex.setColor(.root, red: 255, green: 0, blue: 0), "lumi guide map message 3 is the root color")
    check(messages[4], LumiSysex.setColor(.allKeys, red: 0, green: 0, blue: 255), "lumi guide map message 4 is the scale color")
    check(messages[5], LumiSysex.setBrightness(75), "lumi guide map message 5 is brightness")
}

func testLumiGuideMapFallsBackToChromaticForAnUnmappedScale() {
    let messages = LumiGuideMap.messages(
        mode: ModeReference(tonic: 4, scaleID: "melodic_minor"),
        rootColor: (red: 10, green: 20, blue: 30),
        scaleColor: (red: 40, green: 50, blue: 60)
    )
    check(messages[1], LumiSysex.setKey(pitchClass: 4), "lumi guide map normalizes tonic through PitchClass")
    check(messages[2], LumiSysex.setScale(.chromatic), "lumi guide map falls back to chromatic for melodic_minor")
}

testLumiGuideMapMessagesOrderAndContentForADirectlyMappedScale()
testLumiGuideMapFallsBackToChromaticForAnUnmappedScale()

// MARK: - LumiLiveModeLastState (mirrors Tests/AppCoreTests/LumiLiveModeTests.swift) — pure
// "which state should the LUMI show" decision logic, extracted from the liveInputQueue/
// CoreMIDI plumbing around it in ImprovSession.syncLumiLiveModeIfActive so it's testable
// without real hardware or live playing.

func testLumiLiveModeStateFallsBackToPianoWithNoTracks() {
    check(ImprovSession.LumiLiveModeLastState.current(for: []), .piano, "lumi live state: no tracks -> piano")
}

func testLumiLiveModeStateUsesTheMergedTrackWhenItIsListening() {
    let mode = RecognizedMode(tonic: PitchClass(0), scaleID: "ionian", confidence: 0.9)
    let tracks = [
        TrackInfo(id: .computerKeyboard, label: "t1", isListening: false, canHaveSound: true, recognizedModes: [mode]),
        TrackInfo(id: .midiMerged, label: "MIDI (fusionne)", isListening: true, canHaveSound: true, recognizedModes: [mode]),
    ]
    check(ImprovSession.LumiLiveModeLastState.current(for: tracks), .mode(mode), "lumi live state: merged track drives the display when listening")
}

func testLumiLiveModeStateFallsBackToPianoWhenListeningTrackHasNoRecognizedMode() {
    let tracks = [TrackInfo(id: .midiMerged, label: "MIDI (fusionne)", isListening: true, canHaveSound: true, recognizedModes: [])]
    check(ImprovSession.LumiLiveModeLastState.current(for: tracks), .piano, "lumi live state: listening track with no recognized mode -> piano")
}

// The bug this guards against: under MIDIFusionMode.individual, several MIDI devices can
// each have their own listening track (refreshTracks labels them "MIDI : <name>") — picking
// "the first listening track" would let an unrelated keyboard that happens to sort earlier
// drive the LUMI's own display. Only the track whose label names the LUMI should count.
func testLumiLiveModeStateIndividualModePicksTheLumiNamedTrack() {
    let otherKeyboardMode = RecognizedMode(tonic: PitchClass(2), scaleID: "dorian", confidence: 0.9)
    let lumiMode = RecognizedMode(tonic: PitchClass(0), scaleID: "ionian", confidence: 0.9)
    let tracks = [
        TrackInfo(id: .midiSource(0), label: "MIDI : Some Other Keyboard", isListening: true, canHaveSound: true, recognizedModes: [otherKeyboardMode]),
        TrackInfo(id: .midiSource(1), label: "MIDI : LUMI Keys BLOCK", isListening: true, canHaveSound: true, recognizedModes: [lumiMode]),
    ]
    check(ImprovSession.LumiLiveModeLastState.current(for: tracks), .mode(lumiMode), "lumi live state: LUMI-named track wins even when it doesn't sort first")
}

func testLumiLiveModeStateIndividualModeFallsBackToPianoWhenTheLumiTrackIsntListening() {
    let otherKeyboardMode = RecognizedMode(tonic: PitchClass(2), scaleID: "dorian", confidence: 0.9)
    let tracks = [
        TrackInfo(id: .midiSource(0), label: "MIDI : Some Other Keyboard", isListening: true, canHaveSound: true, recognizedModes: [otherKeyboardMode]),
        TrackInfo(id: .midiSource(1), label: "MIDI : LUMI Keys BLOCK", isListening: false, canHaveSound: true, recognizedModes: []),
    ]
    check(ImprovSession.LumiLiveModeLastState.current(for: tracks), .piano, "lumi live state: a non-listening LUMI track never falls back to another device's recognition")
}

testLumiLiveModeStateFallsBackToPianoWithNoTracks()
testLumiLiveModeStateUsesTheMergedTrackWhenItIsListening()
testLumiLiveModeStateFallsBackToPianoWhenListeningTrackHasNoRecognizedMode()
testLumiLiveModeStateIndividualModePicksTheLumiNamedTrack()
testLumiLiveModeStateIndividualModeFallsBackToPianoWhenTheLumiTrackIsntListening()

// MARK: - LumiGuideDisplayLastState (mirrors Tests/AppCoreTests/LumiLiveModeTests.swift)

func testLumiGuideDisplayStateFallsBackToPianoWhenNoStepReference() {
    check(ImprovSession.LumiGuideDisplayLastState.current(forStepMode: nil), .piano, "lumi guide display state: no step -> piano")
}

func testLumiGuideDisplayStateShowsGuideMapForAMappedScale() {
    let reference = ModeReference(tonic: 0, scaleID: "ionian")
    check(ImprovSession.LumiGuideDisplayLastState.current(forStepMode: reference), .guideMap(reference), "lumi guide display state: mapped scale -> guideMap")
}

func testLumiGuideDisplayStateFallsBackToPianoForAnUnmappedScale() {
    let reference = ModeReference(tonic: 0, scaleID: "melodic_minor")
    check(ImprovSession.LumiGuideDisplayLastState.current(forStepMode: reference), .piano, "lumi guide display state: unmapped scale -> piano")
}

testLumiGuideDisplayStateFallsBackToPianoWhenNoStepReference()
testLumiGuideDisplayStateShowsGuideMapForAMappedScale()
testLumiGuideDisplayStateFallsBackToPianoForAnUnmappedScale()

print("\(checks) checks, \(failures) failures")
if failures > 0 {
    exit(1)
}
