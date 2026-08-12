import XCTest
@testable import MusicTheoryKit

final class TemperamentTests: XCTestCase {

    func testEqualTemperamentIsAllZero() {
        XCTAssertEqual(TemperamentLibrary.equal.centsFromEqualByDegree, Array(repeating: 0, count: 12))
    }

    func testTonicIsAlwaysZeroCentsInEveryTemperament() {
        for temperament in TemperamentLibrary.all {
            XCTAssertEqual(TemperamentLibrary.cents(for: PitchClass(0), in: temperament, tonic: PitchClass(0)), 0, "\(temperament.id) should leave its own tonic untouched")
        }
    }

    func testPythagoreanFifthIsSlightlySharp() {
        let cents = TemperamentLibrary.cents(for: PitchClass(7), in: TemperamentLibrary.pythagorean, tonic: PitchClass(0))
        XCTAssertEqual(cents, 1.955, accuracy: 0.001)
    }

    func testPythagoreanTableDerivationMatchesChainOfFifths() {
        // Recompute independently from the raw "k fifths from tonic" definition and compare —
        // guards against a copy/transcription error in the stored table.
        for k in -5...6 {
            let semitone = ((7 * k) % 12 + 12) % 12
            let rawCents = Double(k) * 701.955
            let equalCents = Double(semitone) * 100
            var deviation = rawCents - equalCents
            while deviation > 600 { deviation -= 1200 }
            while deviation < -600 { deviation += 1200 }
            let tableValue = TemperamentLibrary.cents(for: PitchClass(semitone), in: TemperamentLibrary.pythagorean, tonic: PitchClass(0))
            XCTAssertEqual(tableValue, deviation, accuracy: 0.01, "semitone \(semitone) (k=\(k))")
        }
    }

    func testJustIntonationMajorThirdIsNoticeablyFlat() {
        let cents = TemperamentLibrary.cents(for: PitchClass(4), in: TemperamentLibrary.justIntonation, tonic: PitchClass(0))
        XCTAssertEqual(cents, -13.69, accuracy: 0.01)
    }

    func testJustIntonationPerfectFifthIsSlightlySharp() {
        let cents = TemperamentLibrary.cents(for: PitchClass(7), in: TemperamentLibrary.justIntonation, tonic: PitchClass(0))
        XCTAssertEqual(cents, 1.96, accuracy: 0.01)
    }

    func testWerckmeisterIIIMatchesPublishedAbsoluteCentsMinusEqual() {
        let absoluteCentsFromC: [Double] = [0, 90.225, 192.18, 294.135, 390.225, 498.045, 588.27, 696.09, 792.18, 888.27, 996.09, 1092.18]
        for semitone in 0..<12 {
            let expected = absoluteCentsFromC[semitone] - Double(semitone) * 100
            let actual = TemperamentLibrary.cents(for: PitchClass(semitone), in: TemperamentLibrary.werckmeisterIII, tonic: PitchClass(0))
            XCTAssertEqual(actual, expected, accuracy: 0.01, "semitone \(semitone)")
        }
    }

    func testCentsAreAnchoredOnTonicNotAbsolutePitchClass() {
        // The same relative interval (a major third above the tonic) should give the same
        // deviation regardless of which pitch class the tonic actually is.
        let cCents = TemperamentLibrary.cents(for: PitchClass(4), in: TemperamentLibrary.justIntonation, tonic: PitchClass(0))
        let dCents = TemperamentLibrary.cents(for: PitchClass(6), in: TemperamentLibrary.justIntonation, tonic: PitchClass(2))
        XCTAssertEqual(cCents, dCents, accuracy: 0.0001)
    }

    func testByIDFindsEveryRegisteredTemperament() {
        for temperament in TemperamentLibrary.all {
            XCTAssertEqual(TemperamentLibrary.byID(temperament.id)?.id, temperament.id)
        }
        XCTAssertNil(TemperamentLibrary.byID("doesNotExist"))
    }
}
