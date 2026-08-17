import XCTest
import MusicTheoryKit
import PieceModel
@testable import ScoreImport

final class ScoreEngravingAdapterPieceTests: XCTestCase {
    func testRendersASingleSectionPieceWithOneTrack() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100),
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 62, velocity: 100),
                        ]),
                    ]
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)

        XCTAssertEqual(notated.parts.count, 1)
        XCTAssertEqual(notated.parts[0].name, "Melody")
        XCTAssertEqual(notated.parts[0].measures.count, 1)
        let notes = notated.parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.map(\.pitches), [[60], [62]])
        XCTAssertEqual(notated.parts[0].clef, .treble)
    }

    func testBassRegisterTrackGetsBassClef() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Bass", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 2, pitch: 40, velocity: 100),
                            MelodyEvent(measure: 1, beat: 3, durationBeats: 2, pitch: 43, velocity: 100),
                        ]),
                    ]
                ),
            ]
        )

        XCTAssertEqual(ScoreEngravingAdapter.build(from: piece).parts[0].clef, .bass)
    }

    func testMultipleSectionsConcatenateInOrder() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [
                        MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 60, velocity: 100),
                    ])]
                ),
                Section(
                    name: "B", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [
                        MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 67, velocity: 100),
                    ])]
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)

        XCTAssertEqual(notated.parts.count, 1)
        XCTAssertEqual(notated.parts[0].measures.count, 2)
        XCTAssertEqual(notated.parts[0].measures[0].notes.first { !$0.isRest }?.pitches, [60])
        XCTAssertEqual(notated.parts[0].measures[1].notes.first { !$0.isRest }?.pitches, [67])
    }

    func testTrackMissingFromASectionBecomesSilenceNotAMisalignment() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 60, velocity: 100)]),
                        Track(name: "Bass", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 36, velocity: 100)]),
                    ]
                ),
                Section(
                    name: "B", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 67, velocity: 100)])]
                    // "Bass" absent here on purpose.
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)
        let bass = notated.parts.first { $0.name == "Bass" }
        XCTAssertEqual(bass?.measures.count, 2) // still gets a 2nd, silent measure, not truncated
        XCTAssertTrue(bass?.measures[1].notes.allSatisfy(\.isRest) ?? false)

        let melody = notated.parts.first { $0.name == "Melody" }
        // Melody's 2nd-section note must still land in ITS 2nd measure, not shifted by Bass's absence.
        XCTAssertEqual(melody?.measures[1].notes.first { !$0.isRest }?.pitches, [67])
    }

    func testEmptyPieceProducesNoParts() {
        let piece = Piece(title: "Empty", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"))
        XCTAssertTrue(ScoreEngravingAdapter.build(from: piece).parts.isEmpty)
    }

    // MARK: - Role-coloring analysis
    //
    // Colors below match Part G's functional-role redesign: a chord's degree in its mode picks a
    // `ModalFunctionalRoleTable.standardRole` color (green `.home`/amber `.away`/red `.tension`/
    // blue `.neutral`), darkened for the chord root, lightened for other chord tones; a held
    // mode-root/mode-tone (no chord sounding) reuses the `.home`/`.neutral` hues respectively.
    // Degree 1 (I) in Ionian is always `.home` (`#2e7d32`) — darkened 30% -> `#205823`, lightened
    // 45% -> `#8cb88e`. `.neutral` (`#1565c0`) lightened 45% -> `#7eaadc`.

    func testChordRootToneAndOutOfContextNotesGetDistinctColors() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma"))],
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100), // C: chord root
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 64, velocity: 100), // E: chord tone
                            MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 61, velocity: 100), // C#: outside both the C-major chord and the C-ionian mode
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.map(\.colors), [["#205823"], ["#8cb88e"], [nil]])
    }

    func testChordStackNotesEachGetTheirOwnColor() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma"))],
                    tracks: [
                        Track(name: "Chord", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 60, velocity: 100), // root
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 64, velocity: 100), // tone
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 61, velocity: 100), // outside both
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.count, 1, "three simultaneous same-duration notes group into one chord stack")
        XCTAssertEqual(notes[0].pitches, [60, 64, 61])
        XCTAssertEqual(notes[0].colors, ["#205823", "#8cb88e", nil], "each stacked pitch is colored by its own role, not the stack as a whole")
    }

    func testModeToneWithoutAChordStillGetsColored() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    // No chordProgression at all — only the section's mode should drive coloring.
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100), // C: mode root
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 62, velocity: 100), // D: mode tone
                            MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 61, velocity: 100), // C#: outside the mode
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.map(\.colors), [["#8cb88e"], ["#7eaadc"], [nil]])
    }

    /// A chromatic/secondary-dominant chord root (not one of the mode's own 7 diatonic pitch
    /// classes) has no defined functional role — defaults to `.tension`'s color, which is
    /// musically apt (these chords ARE tension/deviation) rather than an arbitrary catch-all.
    func testChromaticChordRootDefaultsToTensionColor() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    // F#7 (root 6, not in C ionian's own 7 pitch classes) — a secondary dominant.
                    chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 6, chordTemplateID: "7"))],
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 66, velocity: 100)])]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        // `.tension` (`#e64a19`) darkened 30% (the note is the chord's own root).
        XCTAssertEqual(notes.map(\.colors), [["#a13412"]])
    }

    // MARK: - Key signature / accidental suppression

    func testKeySignatureIsComputedFromModeAndAppliedToEveryPart() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 2, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 2, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 62, velocity: 100)]),
                        Track(name: "Bass", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 38, velocity: 100)]),
                    ]
                ),
            ]
        )

        let parts = ScoreEngravingAdapter.build(from: piece).parts
        XCTAssertEqual(parts.count, 2)
        XCTAssertTrue(parts.allSatisfy { $0.keySignature == "D" })
    }

    func testNonFamilyOneModeHasNoKeySignatureOrAccidentalSuppression() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "harmonic_minor"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "harmonic_minor"),
                    tracks: [Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 61, velocity: 100)])]
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)
        XCTAssertNil(notated.parts[0].keySignature)
        XCTAssertNil(notated.parts[0].measures[0].notes.first { !$0.isRest }?.accidentals)
    }

    /// D major (2 sharps: F#, C#) — an F# note shouldn't repeat the sharp the key signature
    /// already implies; a same-measure F-natural must show an explicit natural sign; the F#
    /// returning later in the SAME measure must show its sharp again (the natural cancellation
    /// only holds until the next accidental on that same letter+octave, standard engraving rule).
    func testAccidentalsAreSuppressedWhenTheyMatchTheKeySignatureAndNaturalsShownWhenDeviating() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 2, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 2, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 66, velocity: 100), // F#4 — matches the key signature
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 65, velocity: 100), // F-natural4 — deviates, needs a natural sign
                            MelodyEvent(measure: 1, beat: 3, durationBeats: 1, pitch: 66, velocity: 100), // F#4 again — deviates from the just-shown natural
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        XCTAssertEqual(notes.map(\.keys), [["f#/4"], ["f/4"], ["f#/4"]])
        XCTAssertEqual(notes.map(\.accidentals), [[nil], ["n"], ["#"]])
    }

    func testAccidentalTrackerResetsAtEveryMeasure() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 2, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 2, mode: ModeReference(tonic: 2, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 65, velocity: 100), // F-natural4 in measure 1 — shows "n"
                            MelodyEvent(measure: 2, beat: 1, durationBeats: 4, pitch: 66, velocity: 100), // F#4 in measure 2 — fresh measure, matches key sig, no accidental
                        ]),
                    ]
                ),
            ]
        )

        let notated = ScoreEngravingAdapter.build(from: piece)
        XCTAssertEqual(notated.parts[0].measures[0].notes.first { !$0.isRest }?.accidentals, ["n"])
        XCTAssertEqual(notated.parts[0].measures[1].notes.first { !$0.isRest }?.accidentals, [nil])
    }

    // MARK: - Chord/Roman-numeral annotations

    func testChordAnnotationsAttachOnlyToTheTopStaff() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 2, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 2, scaleID: "ionian"),
                    chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 2, chordTemplateID: "Ma"))],
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 62, velocity: 100)]),
                        Track(name: "Bass", instrument: "", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 4, pitch: 38, velocity: 100)]),
                    ]
                ),
            ]
        )

        let parts = ScoreEngravingAdapter.build(from: piece).parts
        let melody = parts.first { $0.name == "Melody" }
        let bass = parts.first { $0.name == "Bass" }
        XCTAssertEqual(melody?.measures[0].chordAnnotations.map(\.romanNumeral), ["I"])
        XCTAssertEqual(melody?.measures[0].chordAnnotations.first?.chordSymbol, "D")
        XCTAssertEqual(melody?.measures[0].chordAnnotations.first?.isLowConfidence, false)
        XCTAssertEqual(bass?.measures[0].chordAnnotations, [], "chord symbols are a harmonic event, not repeated on every staff")
    }

    // MARK: - Playback-time note positions

    /// `NotatedNote.startSeconds`/`durationSeconds` must match real playback time exactly (same
    /// formula `Piece.renderedNotes()` itself uses) — this is what lets the score highlight tell
    /// "the note sounding right now" apart from another occurrence of the same pitch elsewhere.
    func testNoteStartAndDurationSecondsMatchTempo() {
        let piece = Piece(
            title: "Test", timeSignature: TimeSignature(beatsPerMeasure: 4, beatUnit: 4),
            tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"),
            sections: [
                Section(
                    name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
                    tracks: [
                        Track(name: "Melody", instrument: "", melodyEvents: [
                            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60, velocity: 100),
                            MelodyEvent(measure: 1, beat: 2, durationBeats: 1, pitch: 62, velocity: 100),
                        ]),
                    ]
                ),
            ]
        )

        let notes = ScoreEngravingAdapter.build(from: piece).parts[0].measures[0].notes.filter { !$0.isRest }
        // 120 BPM -> 0.5s per beat: beat 1 starts at 0s, beat 2 at 0.5s, each a 1-beat (0.5s) note.
        XCTAssertEqual(notes[0].startSeconds ?? -1, 0, accuracy: 0.001)
        XCTAssertEqual(notes[0].durationSeconds ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(notes[1].startSeconds ?? -1, 0.5, accuracy: 0.001)
        XCTAssertEqual(notes[1].durationSeconds ?? -1, 0.5, accuracy: 0.001)
    }
}
