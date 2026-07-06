import XCTest
@testable import MusicTheoryKit

final class IIVIMajorChartTests: XCTestCase {

    func testFunctions() {
        let functions = Set(IIVIMajorChart.suggestions.map(\.function))
        XCTAssertEqual(functions, ["ii", "V", "I"])
    }

    func testIISuggestions() {
        let scales = IIVIMajorChart.scales(forFunction: "ii")
        XCTAssertEqual(scales.count, 5)
        XCTAssertEqual(scales.first?.id, "dorian")
    }

    func testVSuggestions() {
        let scales = IIVIMajorChart.scales(forFunction: "V")
        XCTAssertEqual(scales.first?.id, "mixolydian")
    }

    func testISuggestions() {
        let scales = IIVIMajorChart.scales(forFunction: "I")
        XCTAssertEqual(scales.first?.id, "ionian")
    }

    func testAllIDsResolve() {
        for suggestion in IIVIMajorChart.suggestions {
            for id in suggestion.suggestedScaleIDs {
                XCTAssertNotNil(ScaleLibrary.byID(id), "\(id) not found in ScaleLibrary")
            }
        }
    }
}
