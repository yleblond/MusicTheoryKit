import XCTest
import MusicTheoryKit
@testable import AppCore

final class FixedTemperamentCentsTests: XCTestCase {

    func testEqualTemperamentIsAlwaysZeroRegardlessOfTonic() {
        let configuration = TuningConfiguration(temperamentID: "equal", referenceA4: 440)
        for pitchClass in 0...11 {
            let cents = fixedTemperamentCents(forPitchClass: PitchClass(pitchClass), tonic: PitchClass(3), configuration: configuration)
            XCTAssertEqual(cents, 0)
        }
    }

    func testJustIntonationMajorThirdAboveTonicIsFlat() {
        let configuration = TuningConfiguration(temperamentID: "justIntonation", referenceA4: 440)
        // Tonic D (2), major third above is F# (6).
        let cents = fixedTemperamentCents(forPitchClass: PitchClass(6), tonic: PitchClass(2), configuration: configuration)
        XCTAssertEqual(cents, -13.69, accuracy: 0.01)
    }

    func testUnknownTemperamentIDDefaultsToNoCorrection() {
        let configuration = TuningConfiguration(temperamentID: "doesNotExist", referenceA4: 440)
        XCTAssertEqual(fixedTemperamentCents(forPitchClass: PitchClass(4), tonic: PitchClass(0), configuration: configuration), 0)
    }

    func testReferenceA4OffsetIsAdditiveOnTopOfTheTemperament() {
        // A4 = 441 Hz is 1200*log2(441/440) ≈ 3.93 cents sharp of standard.
        let configuration = TuningConfiguration(temperamentID: "equal", referenceA4: 441)
        let cents = fixedTemperamentCents(forPitchClass: PitchClass(0), tonic: PitchClass(0), configuration: configuration)
        XCTAssertEqual(cents, 1200 * log2(441.0 / 440.0), accuracy: 0.0001)
    }
}
