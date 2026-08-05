import XCTest
@testable import MusicTheoryKit

final class FunctionalHarmonyTests: XCTestCase {
    func testFamilyOneDegreesMapToTheClassicFunctionalRoles() {
        let expected: [FunctionalHarmonyRole] = [
            .tonic, .supertonic, .mediant, .subdominant, .dominant, .submediant, .leadingTone,
        ]
        for (index, role) in expected.enumerated() {
            XCTAssertEqual(FunctionalHarmonyTable.role(forDegree: index + 1, familyID: 1), role)
        }
    }

    func testDegreeWrapsAcrossOctaves() {
        XCTAssertEqual(FunctionalHarmonyTable.role(forDegree: 8, familyID: 1), .tonic)
        XCTAssertEqual(FunctionalHarmonyTable.role(forDegree: 9, familyID: 1), .supertonic)
    }

    func testNonFamilyOneReturnsNil() {
        XCTAssertNil(FunctionalHarmonyTable.role(forDegree: 1, familyID: 2))
        XCTAssertNil(FunctionalHarmonyTable.role(forDegree: 1, familyID: 5))
    }
}
