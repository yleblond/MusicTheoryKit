import XCTest
import MIDIEngine
@testable import AppCore

final class LumiColorMapTests: XCTestCase {
    func testDirectlyMappedScalesUseTheirLumiEquivalent() {
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "ionian"), .major)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "aeolian"), .minor)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "harmonic_minor"), .harmonicMinor)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "dorian"), .dorian)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "phrygian"), .phrygian)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "lydian"), .lydian)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "mixolydian"), .mixolydian)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "locrian"), .locrian)
        XCTAssertEqual(LumiColorMap.lumiScale(forScaleID: "whole_tone"), .wholeTone)
    }

    func testScalesWithNoLumiEquivalentReturnNil() {
        XCTAssertNil(LumiColorMap.lumiScale(forScaleID: "melodic_minor"))
        XCTAssertNil(LumiColorMap.lumiScale(forScaleID: "altered"))
        XCTAssertNil(LumiColorMap.lumiScale(forScaleID: "diminished"))
        XCTAssertNil(LumiColorMap.lumiScale(forScaleID: "augmented"))
        XCTAssertNil(LumiColorMap.lumiScale(forScaleID: "not_a_real_scale_id"))
    }
}
