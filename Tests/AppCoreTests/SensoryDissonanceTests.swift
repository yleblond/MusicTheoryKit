import XCTest
@testable import AppCore

final class SensoryDissonanceTests: XCTestCase {
    func testPairwiseDissonanceIsZeroForIdenticalFrequencies() {
        XCTAssertEqual(SensoryDissonance.pairwiseDissonance(f1: 440, a1: 1, f2: 440, a2: 1), 0, accuracy: 1e-12)
        XCTAssertEqual(SensoryDissonance.pairwiseDissonance(f1: 220, a1: 0.7, f2: 220, a2: 0.3), 0, accuracy: 1e-12)
    }

    func testPairwiseDissonanceIsPositiveForANearbySeparation() {
        // A small separation (well inside a critical band at these frequencies) should read as
        // genuinely rough, not merely nonzero.
        XCTAssertGreaterThan(SensoryDissonance.pairwiseDissonance(f1: 440, a1: 1, f2: 460, a2: 1), 0)
    }

    func testPairwiseDissonanceDecaysTowardZeroForALargeSeparation() {
        let nearby = SensoryDissonance.pairwiseDissonance(f1: 440, a1: 1, f2: 460, a2: 1)
        let farApart = SensoryDissonance.pairwiseDissonance(f1: 440, a1: 1, f2: 4400, a2: 1)
        XCTAssertGreaterThan(nearby, farApart)
        XCTAssertLessThan(farApart, 0.01)
    }

    func testPairwiseDissonanceIsSymmetricInItsTwoPartials() {
        let a = SensoryDissonance.pairwiseDissonance(f1: 300, a1: 0.8, f2: 320, a2: 0.4)
        let b = SensoryDissonance.pairwiseDissonance(f1: 320, a1: 0.4, f2: 300, a2: 0.8)
        XCTAssertEqual(a, b, accuracy: 1e-12)
    }

    func testDissonanceBetweenTwoTonesSumsEveryCrossPartialPair() {
        let toneA = [SpectralPartial(frequencyHz: 200, amplitude: 1), SpectralPartial(frequencyHz: 400, amplitude: 0.5)]
        let toneB = [SpectralPartial(frequencyHz: 210, amplitude: 1), SpectralPartial(frequencyHz: 420, amplitude: 0.5)]
        let expected =
            SensoryDissonance.pairwiseDissonance(f1: 200, a1: 1, f2: 210, a2: 1)
            + SensoryDissonance.pairwiseDissonance(f1: 200, a1: 1, f2: 420, a2: 0.5)
            + SensoryDissonance.pairwiseDissonance(f1: 400, a1: 0.5, f2: 210, a2: 1)
            + SensoryDissonance.pairwiseDissonance(f1: 400, a1: 0.5, f2: 420, a2: 0.5)
        XCTAssertEqual(SensoryDissonance.dissonance(between: toneA, and: toneB), expected, accuracy: 1e-12)
    }

    func testTotalDissonanceOfATriadSumsAllThreePairsOfTonesOnly() {
        let root = [SpectralPartial(frequencyHz: 220, amplitude: 1)]
        let third = [SpectralPartial(frequencyHz: 277, amplitude: 1)]
        let fifth = [SpectralPartial(frequencyHz: 330, amplitude: 1)]
        let expected =
            SensoryDissonance.dissonance(between: root, and: third)
            + SensoryDissonance.dissonance(between: root, and: fifth)
            + SensoryDissonance.dissonance(between: third, and: fifth)
        XCTAssertEqual(SensoryDissonance.totalDissonance(ofTones: [root, third, fifth]), expected, accuracy: 1e-12)
    }

    func testTotalDissonanceOfASingleToneIsZero() {
        let root = [SpectralPartial(frequencyHz: 220, amplitude: 1), SpectralPartial(frequencyHz: 440, amplitude: 0.5)]
        XCTAssertEqual(SensoryDissonance.totalDissonance(ofTones: [root]), 0)
    }
}
