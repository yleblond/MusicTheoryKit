import XCTest
@testable import JamShackUI

/// Guards against the resource-path mismatch this actually hit once during development:
/// SwiftPM's `.copy("Resources/ScoreEngraving")` drops the `Resources/` prefix in the built
/// bundle (the folder lands at `ScoreEngraving/...`, not `Resources/ScoreEngraving/...`), which
/// `Bundle.module.url(forResource:withExtension:subdirectory:)` fails silently on — no crash,
/// just a blank WKWebView at runtime. A unit test catches that where a manual app run might not.
final class ScoreEngravingResourcesTests: XCTestCase {
    func testVendoredAssetsResolveInBundle() {
        XCTAssertNotNil(Bundle.module.url(forResource: "score", withExtension: "html", subdirectory: "ScoreEngraving"))
        XCTAssertNotNil(Bundle.module.url(forResource: "vexflow", withExtension: "js", subdirectory: "ScoreEngraving"))
        XCTAssertNotNil(Bundle.module.url(forResource: "bridge", withExtension: "js", subdirectory: "ScoreEngraving"))
    }

    func testScoreHTMLReferencesBothScripts() throws {
        let url = try XCTUnwrap(Bundle.module.url(forResource: "score", withExtension: "html", subdirectory: "ScoreEngraving"))
        let html = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(html.contains("vexflow.js"))
        XCTAssertTrue(html.contains("bridge.js"))
    }
}
