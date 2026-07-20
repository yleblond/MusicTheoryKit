import XCTest
import MIDIEngine
import PieceModel
@testable import AppCore

final class LumiGuideMapTests: XCTestCase {
    func testMessagesOrderAndContentForADirectlyMappedScale() {
        let messages = LumiGuideMap.messages(
            mode: ModeReference(tonic: 0, scaleID: "ionian"),
            rootColor: (red: 255, green: 0, blue: 0),
            scaleColor: (red: 0, green: 0, blue: 255),
            brightnessPercentage: 75
        )
        XCTAssertEqual(messages.count, 6)
        XCTAssertEqual(messages[0], LumiSysex.setColorMode(.user))
        XCTAssertEqual(messages[1], LumiSysex.setKey(pitchClass: 0))
        XCTAssertEqual(messages[2], LumiSysex.setScale(.major))
        XCTAssertEqual(messages[3], LumiSysex.setColor(.root, red: 255, green: 0, blue: 0))
        XCTAssertEqual(messages[4], LumiSysex.setColor(.allKeys, red: 0, green: 0, blue: 255))
        XCTAssertEqual(messages[5], LumiSysex.setBrightness(75))
    }

    func testFallsBackToChromaticForAnUnmappedScale() {
        let messages = LumiGuideMap.messages(
            mode: ModeReference(tonic: 4, scaleID: "melodic_minor"),
            rootColor: (red: 10, green: 20, blue: 30),
            scaleColor: (red: 40, green: 50, blue: 60)
        )
        XCTAssertEqual(messages[1], LumiSysex.setKey(pitchClass: 4))
        XCTAssertEqual(messages[2], LumiSysex.setScale(.chromatic))
    }
}
