import XCTest
@testable import AudioEngine
import SoundFontModel

final class SoundFontPresetIdentitySamplerTests: XCTestCase {
    func testMelodicBankMapsToDefaultMelodicMSBWithBankAsLSB() {
        let identity = SoundFontPresetIdentity(program: 0, bank: 0)
        XCTAssertEqual(identity.bankMSB, 121)
        XCTAssertEqual(identity.bankLSB, 0)
    }

    func testNonZeroMelodicBankKeepsItsValueAsLSB() {
        let identity = SoundFontPresetIdentity(program: 40, bank: 5)
        XCTAssertEqual(identity.bankMSB, 121)
        XCTAssertEqual(identity.bankLSB, 5)
    }

    /// Verified against real files — both `FluidR3_GM2-2.SF2` and `GeneralUser GS v1.471.sf2`
    /// register their percussion kits under `wBank == 120`, not 128.
    func testPercussionBank120MapsToPercussionMSBWithZeroLSB() {
        let identity = SoundFontPresetIdentity(program: 0, bank: 120)
        XCTAssertEqual(identity.bankMSB, 120)
        XCTAssertEqual(identity.bankLSB, 0)
    }

    func testBank128IsTreatedAsAnOrdinaryMelodicBankNotPercussion() {
        let identity = SoundFontPresetIdentity(program: 0, bank: 128)
        XCTAssertEqual(identity.bankMSB, 121)
        XCTAssertEqual(identity.bankLSB, 128)
    }

    func testSamplerProgramClampsToAByte() {
        XCTAssertEqual(SoundFontPresetIdentity(program: 19, bank: 0).samplerProgram, 19)
        XCTAssertEqual(SoundFontPresetIdentity(program: 999, bank: 0).samplerProgram, 255)
    }
}
