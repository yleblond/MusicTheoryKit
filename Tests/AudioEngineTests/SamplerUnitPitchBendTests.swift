import XCTest
@testable import AudioEngine

final class SamplerUnitPitchBendTests: XCTestCase {

    func testZeroCentsIsExactCenter() {
        XCTAssertEqual(SamplerUnit.pitchBendValue(forCents: 0), 8192)
    }

    func testPositiveCentsBendsUpwardFromCenter() {
        XCTAssertGreaterThan(SamplerUnit.pitchBendValue(forCents: 50), 8192)
    }

    func testNegativeCentsBendsDownwardFromCenter() {
        XCTAssertLessThan(SamplerUnit.pitchBendValue(forCents: -50), 8192)
    }

    func testOneSemitoneUpIsHalfOfTheDefaultTwoSemitoneRange() {
        // ±2 semitones maps to the full 0...16383 range, so +100 cents (1 semitone) should land
        // roughly halfway between center and the top.
        let value = SamplerUnit.pitchBendValue(forCents: 100)
        XCTAssertEqual(Int(value), 8192 + 8191 / 2, accuracy: 1)
    }

    func testValuesAreSymmetricAroundCenter() {
        let up = Int(SamplerUnit.pitchBendValue(forCents: 30))
        let down = Int(SamplerUnit.pitchBendValue(forCents: -30))
        XCTAssertEqual(up - 8192, 8192 - down, accuracy: 1)
    }

    func testExtremeCentsClampToTheSameValueAsThePlusOrMinusTwoHundredCentsBoundary() {
        XCTAssertEqual(SamplerUnit.pitchBendValue(forCents: 10_000), SamplerUnit.pitchBendValue(forCents: 200))
        XCTAssertEqual(SamplerUnit.pitchBendValue(forCents: -10_000), SamplerUnit.pitchBendValue(forCents: -200))
    }

    func testValueStaysWithinTheValidFourteenBitMIDIRange() {
        for cents in stride(from: -300.0, through: 300.0, by: 25.0) {
            let value = SamplerUnit.pitchBendValue(forCents: cents)
            XCTAssertTrue((0...16383).contains(Int(value)))
        }
    }
}
