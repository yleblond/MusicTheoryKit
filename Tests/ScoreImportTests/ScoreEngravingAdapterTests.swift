import XCTest
@testable import ScoreImport

final class ScoreEngravingAdapterTests: XCTestCase {
    private let ticksPerQuarter = 480

    func testSingleQuarterNoteInOneMeasure() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [RawNote(startTick: 0, durationTicks: 480, pitch: 60)])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)

        XCTAssertEqual(notated.parts.count, 1)
        let measures = notated.parts[0].measures
        XCTAssertEqual(measures.count, 1)
        XCTAssertEqual(measures[0].beatsPerMeasure, 4)
        // A single quarter note followed by rests filling the remaining 3 beats.
        XCTAssertEqual(measures[0].notes.first?.duration, "q")
        XCTAssertEqual(measures[0].notes.first?.keys, ["c/4"])
        XCTAssertFalse(measures[0].notes.first?.isRest ?? true)
        XCTAssertTrue(measures[0].notes.dropFirst().allSatisfy(\.isRest))
        // Raw-file preview has no harmonic/mode context yet (no `Piece`, no analysis) — role
        // coloring only applies via `build(from: Piece)`.
        XCTAssertNil(measures[0].notes.first?.colors)
        // Same for playback-time positions — no `Piece`/tempo context to resolve real seconds from.
        XCTAssertNil(measures[0].notes.first?.startSeconds)
        XCTAssertNil(measures[0].notes.first?.durationSeconds)
        XCTAssertEqual(notated.parts[0].clef, .treble)
    }

    // MARK: - Clef / staff layout

    private func part(id: String, pitches: [Int]) -> RawPart {
        RawPart(id: id, notes: pitches.enumerated().map { index, pitch in
            RawNote(startTick: index * ticksPerQuarter, durationTicks: ticksPerQuarter, pitch: pitch)
        })
    }

    /// Reproduces the (rounded) pitch-profile ratios of a real duet file
    /// (`an-die-musik-sb-duet.mid`, investigated live this session): a part's clef is decided
    /// once from ALL its notes, not re-evaluated per measure. Soprano/Baritone/Piano-lower each
    /// stay comfortably on one side of the 20%-minority grand-staff threshold (0%, 11%, 0%) and
    /// get a single clef; Piano-upper's real 75%/25% split is tested separately below since it
    /// crosses that threshold into a grand staff instead.
    func testClefIsChosenByMajorityPitchAcrossTheWholePart() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [
                part(id: "soprano", pitches: [72, 74, 78]), // entirely above C4
                part(id: "baritone", pitches: [49, 50, 50, 50, 50, 50, 50, 50, 62]), // 89%/11%, below C4
                part(id: "pianoLower", pitches: [43, 48, 50]), // entirely below C4
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let clefByID = Dictionary(uniqueKeysWithValues: notated.parts.map { ($0.id, $0.clef) })

        XCTAssertEqual(clefByID["soprano"], .treble)
        XCTAssertEqual(clefByID["baritone"], .bass)
        XCTAssertEqual(clefByID["pianoLower"], .bass)
        XCTAssertEqual(notated.parts.count, 3, "none of these need a grand staff")
        XCTAssertTrue(notated.parts.allSatisfy { $0.staffGroupID == nil })
    }

    /// A note-for-note 50/50 split is itself well past the 20%-minority grand-staff threshold
    /// (see `testMixedRegisterPartBecomesAGrandStaff`), so an actual single-clef tie can't occur
    /// in practice — this instead guards `belowMiddleC * 2 > pitches.count`'s own `>` (not `>=`)
    /// directly: a part one note short of a below-C4 majority still resolves to `.treble`.
    func testClefTieFavorsTreble() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: (0..<9).map { index in
                RawNote(startTick: index * ticksPerQuarter, durationTicks: ticksPerQuarter, pitch: index == 0 ? 55 : 64) // 1 below / 8 above C4
            })]
        )
        XCTAssertEqual(ScoreEngravingAdapter.build(from: score).parts[0].clef, .treble)
    }

    func testMixedRegisterPartBecomesAGrandStaff() {
        // Piano-upper's real ratio: 75% at/above C4, 25% below — illegible as a single treble
        // staff per direct user feedback, so it splits into a treble+bass pair sharing one
        // `staffGroupID` instead.
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [part(id: "pianoUpper", pitches: [64, 67, 71, 55])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        XCTAssertEqual(notated.parts.count, 2)

        let treble = notated.parts[0]
        let bass = notated.parts[1]
        XCTAssertEqual(treble.clef, .treble)
        XCTAssertEqual(bass.clef, .bass)
        XCTAssertEqual(treble.staffGroupID, "pianoUpper")
        XCTAssertEqual(bass.staffGroupID, "pianoUpper")

        let trebleNotes = treble.measures.flatMap(\.notes).filter { !$0.isRest }
        let bassNotes = bass.measures.flatMap(\.notes).filter { !$0.isRest }
        XCTAssertEqual(trebleNotes.flatMap(\.pitches), [64, 67, 71])
        XCTAssertEqual(bassNotes.flatMap(\.pitches), [55])
    }

    func testGapBecomesRests() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 0, durationTicks: 480, pitch: 60),
                // gap of one beat (960...1440), then a note at beat 3
                RawNote(startTick: 1440, durationTicks: 480, pitch: 62),
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let notes = notated.parts[0].measures[0].notes
        XCTAssertEqual(notes.map(\.isRest), [false, true, false])
    }

    func testSimultaneousNotesGroupIntoChord() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 0, durationTicks: 480, pitch: 60),
                RawNote(startTick: 0, durationTicks: 480, pitch: 64),
                RawNote(startTick: 0, durationTicks: 480, pitch: 67),
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let firstNote = notated.parts[0].measures[0].notes[0]
        XCTAssertEqual(firstNote.pitches.sorted(), [60, 64, 67])
        XCTAssertEqual(firstNote.keys.count, 3)
    }

    func testNoteClippedAtMeasureBoundaryNotTied() {
        // A whole-note-length note starting one beat before the end of a 4/4 measure would
        // naturally spill into the next measure; v1 clips it instead of tying across the bar.
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 1440, durationTicks: 1920, pitch: 60), // starts at beat 4, would run 4 beats long
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let measures = notated.parts[0].measures
        XCTAssertEqual(measures.count, 1) // clipped, no second measure spawned for the overflow
        let note = measures[0].notes.last { !$0.isRest }
        XCTAssertEqual(note?.duration, "q") // clipped down to the 1 remaining beat
    }

    func testExplicitSpellingIsPreservedVerbatim() {
        let score = RawScore(
            sourceFormat: .musicXML,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [
                RawNote(
                    startTick: 0, durationTicks: 480, pitch: 64,
                    spelling: RawSpelling(step: "F", alter: -1, octave: 4) // Fb, not E
                ),
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        XCTAssertEqual(notated.parts[0].measures[0].notes.first?.keys, ["fb/4"])
    }

    func testMissingSpellingFallsBackToCanonicalSpelling() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
            parts: [RawPart(id: "0", notes: [RawNote(startTick: 0, durationTicks: 480, pitch: 61)])] // C#4/Db4
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        // DiatonicSpelling's canonical table picks Db over C# — see DiatonicSpelling.swift.
        XCTAssertEqual(notated.parts[0].measures[0].notes.first?.keys, ["db/4"])
    }

    func testMultipleMeasuresFromTimeSignatureChange() {
        let score = RawScore(
            sourceFormat: .midi,
            divisionsPerQuarterNote: ticksPerQuarter,
            timeSignatureMap: [
                RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4),
                RawTimeSignatureEvent(tick: 1920, beatsPerMeasure: 3, beatUnit: 4), // after 1 measure of 4/4
            ],
            parts: [RawPart(id: "0", notes: [
                RawNote(startTick: 0, durationTicks: 480, pitch: 60),
                RawNote(startTick: 1920, durationTicks: 480, pitch: 62), // first note of the 3/4 measure
            ])]
        )

        let notated = ScoreEngravingAdapter.build(from: score)
        let measures = notated.parts[0].measures
        XCTAssertEqual(measures.count, 2)
        XCTAssertEqual(measures[0].beatsPerMeasure, 4)
        XCTAssertEqual(measures[1].beatsPerMeasure, 3)
    }

    func testEmptyPartProducesNoMeasures() {
        let score = RawScore(sourceFormat: .midi, divisionsPerQuarterNote: ticksPerQuarter, parts: [RawPart(id: "0", notes: [])])
        let notated = ScoreEngravingAdapter.build(from: score)
        XCTAssertTrue(notated.parts[0].measures.isEmpty)
    }
}
