import XCTest
@testable import Localization

final class L10nTests: XCTestCase {

    func testEveryL10nKeyHasAllThreeLanguages() {
        for key in L10nKey.allCases {
            for language in AppLanguage.allCases {
                let value = L10n.string(key, language)
                XCTAssertNotEqual(value, key.rawValue, "\(key.rawValue) has no \(language.rawValue) translation")
            }
        }
    }
}
