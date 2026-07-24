import XCTest
@testable import MusicTheoryKit

final class CircleOfFifthsTests: XCTestCase {

    private func cell(_ wheel: CircleOfFifthsWheel, _ root: Int, _ quality: ChordQuality) -> CircleOfFifthsCell {
        wheel.columns.flatMap(\.cells).first { $0.pitchClass.value == root && $0.quality == quality }!
    }

    private func column(_ wheel: CircleOfFifthsWheel, _ pitchClass: Int) -> CircleOfFifthsColumn {
        wheel.columns.first { $0.pitchClass.value == pitchClass }!
    }

    func testPhysicalOrderIsFixedAscendingFifthsFromC() {
        let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
        XCTAssertEqual(wheel.columns.map { $0.pitchClass.value }, [0, 7, 2, 9, 4, 11, 6, 1, 8, 3, 10, 5])
    }

    func testCTonicModeNamePositions() {
        let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
        let named = wheel.columns.filter { $0.modeName != nil }
        // NOT the 7 diatonic columns (see `CircleOfFifthsColumn.modeName`'s doc comment): each
        // mode name sits at "the interval up to its own parent" from the tonic, so only I/IV/V
        // (Ionian/Lydian/Mixolydian) coincide with a diatonic column here.
        XCTAssertEqual(named.map { $0.pitchClass.value }, [0, 7, 1, 8, 3, 10, 5])
        XCTAssertEqual(named.map(\.modeName), ["Ionian", "Lydian", "Locrian", "Phrygian", "Aeolian", "Dorian", "Mixolydian"])
        XCTAssertEqual(wheel.activeColumnIndex, 0)
    }

    func testCTonicDiatonicCellsMatchExpectedQualityAndDegree() {
        let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
        XCTAssertEqual(cell(wheel, 0, .major).relativeDegree, "I")
        XCTAssertTrue(cell(wheel, 0, .major).isDiatonic)
        XCTAssertEqual(cell(wheel, 5, .major).relativeDegree, "IV")
        XCTAssertEqual(cell(wheel, 7, .major).relativeDegree, "V")
        // D minor (ii of C) is the relative minor of F major — rooted at column F, not column D.
        XCTAssertEqual(cell(wheel, 2, .minor).relativeDegree, "ii")
        XCTAssertTrue(cell(wheel, 2, .minor).isDiatonic)
        XCTAssertFalse(cell(wheel, 2, .major).isDiatonic)
        // B diminished (vii° of C) is the leading-tone diminished of C major — rooted at column C.
        XCTAssertEqual(cell(wheel, 11, .diminished).relativeDegree, "vii\u{00B0}")
        XCTAssertTrue(cell(wheel, 11, .diminished).isDiatonic)
        XCTAssertEqual(cell(wheel, 10, .major).relativeDegree, "bVII")
        XCTAssertEqual(cell(wheel, 6, .major).relativeDegree, "bV")
    }

    func testMinorAndDiminishedRingsHaveTheirOwnSpelling() {
        // Each ring spells its accidental degrees independently — NOT `majorDegreeLabels`
        // lowercased. Same tritone (F#/Gb, column F#): "bV" on the major ring, "#iv" on the
        // minor ring, "#iv°" on the diminished ring — three different spellings.
        let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
        XCTAssertEqual(cell(wheel, 6, .minor).relativeDegree, "#iv")
        XCTAssertEqual(cell(wheel, 6, .diminished).relativeDegree, "#iv\u{00B0}")
        // The minor ring's two sharp-not-flat anomalies (offsets 1 and 8).
        XCTAssertEqual(cell(wheel, 1, .minor).relativeDegree, "#i")
        XCTAssertEqual(cell(wheel, 8, .minor).relativeDegree, "#v")
        // The diminished ring uses sharps for every accidental offset (never flats).
        XCTAssertEqual(cell(wheel, 1, .diminished).relativeDegree, "#i\u{00B0}")
        XCTAssertEqual(cell(wheel, 3, .diminished).relativeDegree, "#ii\u{00B0}")
        XCTAssertEqual(cell(wheel, 8, .diminished).relativeDegree, "#v\u{00B0}")
        XCTAssertEqual(cell(wheel, 10, .diminished).relativeDegree, "#vi\u{00B0}")
    }

    func testMinorAndDiminishedCellsAreOffsetFromTheirColumn() {
        let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
        // Column C: major=C(I), minor=Am(vi, relative minor of C), diminished=B°(vii°, leading tone).
        XCTAssertEqual(column(wheel, 0).cells.first { $0.quality == .major }!.pitchClass, PitchClass(0))
        XCTAssertEqual(column(wheel, 0).cells.first { $0.quality == .minor }!.pitchClass, PitchClass(9))
        XCTAssertEqual(column(wheel, 0).cells.first { $0.quality == .diminished }!.pitchClass, PitchClass(11))
        // Column F: major=F(IV), minor=Dm(ii), diminished=E°.
        XCTAssertEqual(column(wheel, 5).cells.first { $0.quality == .minor }!.pitchClass, PitchClass(2))
        XCTAssertEqual(column(wheel, 5).cells.first { $0.quality == .diminished }!.pitchClass, PitchClass(4))
    }

    func testActiveTonicPutsDegreeIOnTheModesOwnTonicNotTheParents() {
        // "A Lydian": parent is E (Lydian is degree 4). Without `activeTonic`, "I" used to land
        // on E (the parent) — correct only for Ionian, off by one degree for Lydian/Mixolydian,
        // and completely wrong (opposite end of the label table) for Locrian.
        let aLydian = Mode(tonic: PitchClass(9), scale: ScaleLibrary.byID("lydian")!)
        let parentOfA = CircleOfFifths.parentTonic(for: aLydian)
        XCTAssertEqual(parentOfA, PitchClass(4))
        let lydianWheel = CircleOfFifths.wheel(tonic: parentOfA!, activeTonic: aLydian.tonic)
        let aMajorCell = lydianWheel.columns.flatMap(\.cells).first { $0.pitchClass == PitchClass(9) && $0.quality == .major }!
        XCTAssertEqual(aMajorCell.relativeDegree, "I")
        XCTAssertTrue(aMajorCell.isDiatonic)

        // "D Locrian": parent is Eb (Locrian is degree 7, farthest from its parent). D Locrian's
        // own tonic triad is diminished, so "I" belongs on D's *diminished* cell specifically.
        let dLocrian = Mode(tonic: PitchClass(2), scale: ScaleLibrary.byID("locrian")!)
        let parentOfD = CircleOfFifths.parentTonic(for: dLocrian)
        XCTAssertEqual(parentOfD, PitchClass(3))
        let locrianWheel = CircleOfFifths.wheel(tonic: parentOfD!, activeTonic: dLocrian.tonic)
        let dDiminishedCell = locrianWheel.columns.flatMap(\.cells).first { $0.pitchClass == PitchClass(2) && $0.quality == .diminished }!
        XCTAssertEqual(dDiminishedCell.relativeDegree, "i\u{00B0}")
        XCTAssertTrue(dDiminishedCell.isDiatonic)

        // Omitting `activeTonic` must keep behaving exactly as before (defaults to `tonic`).
        let unspecified = CircleOfFifths.wheel(tonic: PitchClass(0))
        let cMajorCell = unspecified.columns.flatMap(\.cells).first { $0.pitchClass == PitchClass(0) && $0.quality == .major }!
        XCTAssertEqual(cMajorCell.relativeDegree, "I")
    }

    func testShapeAlternatesByCellPitchClassParity() {
        let wheel = CircleOfFifths.wheel(tonic: PitchClass(0))
        for cell in wheel.columns.flatMap(\.cells) {
            let expected: ChordShape = cell.pitchClass.value % 2 == 0 ? .square : .circle
            XCTAssertEqual(cell.shape, expected, "parity for cell pitch class \(cell.pitchClass.value)")
        }
    }

    func testDDorianParentTonicMatchesCIonian() {
        let mode = Mode(tonic: PitchClass(2), scale: ScaleLibrary.byID("dorian")!)
        XCTAssertEqual(CircleOfFifths.parentTonic(for: mode), PitchClass(0))
    }

    func testParentTonicNonFamily1ReturnsNil() {
        let mode = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("altered")!)
        XCTAssertNil(CircleOfFifths.parentTonic(for: mode))
    }

    func testPitchClassPaletteHas12DistinctEntries() {
        XCTAssertEqual(PitchClassPalette.hex.count, 12)
        XCTAssertEqual(Set(PitchClassPalette.hex).count, 12)
    }
}
