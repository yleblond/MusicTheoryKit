import XCTest
@testable import AppCore
@testable import MusicTheoryKit

final class ModalFunctionalMapTests: XCTestCase {
    private let family1Degrees = 1...7

    func testBothSourcesProduceSevenChordsWithDegreeOneAsHomeForEveryClassicMode() {
        for scaleDegree in family1Degrees {
            let scale = ScaleLibrary.scales(inFamily: 1).first { $0.degree == scaleDegree }!
            let mode = Mode(tonic: PitchClass(0), scale: scale)
            for source in FunctionalRoleSource.allCases {
                let map = ModalFunctionalMapBuilder.build(for: mode, source: source)
                XCTAssertEqual(map.chords.count, 7, "\(scale.systematicName) / \(source)")
                XCTAssertEqual(map.chords[0].role, .home, "\(scale.systematicName) / \(source)")
                for chord in map.chords {
                    XCTAssertGreaterThanOrEqual(chord.functionalIntensity, 0)
                    XCTAssertLessThanOrEqual(chord.functionalIntensity, 1)
                }
            }
        }
    }

    func testNonFamilyOneModeProducesEmptyMap() {
        let harmonicMinor = ScaleLibrary.scales(inFamily: 2).first!
        let mode = Mode(tonic: PitchClass(0), scale: harmonicMinor)
        for source in FunctionalRoleSource.allCases {
            let map = ModalFunctionalMapBuilder.build(for: mode, source: source)
            XCTAssertTrue(map.chords.isEmpty)
            XCTAssertTrue(map.attractions.isEmpty)
        }
    }

    func testIonianHasNoCharacteristicNotesButEveryOtherClassicModeHasAtLeastOne() {
        for scaleDegree in family1Degrees {
            let scale = ScaleLibrary.scales(inFamily: 1).first { $0.degree == scaleDegree }!
            let mode = Mode(tonic: PitchClass(0), scale: scale)
            let notes = ModalFunctionalMapBuilder.characteristicNotes(for: mode)
            if scaleDegree == 1 {
                XCTAssertTrue(notes.isEmpty, "Ionian should have no characteristic note")
            } else {
                XCTAssertFalse(notes.isEmpty, "\(scale.systematicName) should have a characteristic note")
            }
        }
    }

    func testLocrianTonicTriadIsFlaggedAsLessThanFullyStable() {
        let locrian = ScaleLibrary.scales(inFamily: 1).first { $0.degree == 7 }!
        let mode = Mode(tonic: PitchClass(0), scale: locrian)
        for source in FunctionalRoleSource.allCases {
            let map = ModalFunctionalMapBuilder.build(for: mode, source: source)
            XCTAssertEqual(map.chords[0].role, .home)
            XCTAssertGreaterThan(map.chords[0].functionalIntensity, 0, "Locrian's own tonic triad is diminished — \(source)")
        }
    }

    func testAttractionsOnlyReferenceValidDegreesAndMeetTheDisplayThreshold() {
        let dorian = ScaleLibrary.scales(inFamily: 1).first { $0.degree == 2 }!
        let mode = Mode(tonic: PitchClass(0), scale: dorian)
        for source in FunctionalRoleSource.allCases {
            let map = ModalFunctionalMapBuilder.build(for: mode, source: source)
            for attraction in map.attractions {
                XCTAssertTrue(family1Degrees.contains(attraction.fromDegree))
                XCTAssertEqual(attraction.toDegree, 1)
                XCTAssertGreaterThanOrEqual(attraction.strength, ModalFunctionalMapBuilder.minimumDisplayedStrength)
            }
        }
    }
}
