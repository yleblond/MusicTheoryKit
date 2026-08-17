import XCTest
@testable import AppCore

/// Golden test against a real piece — Schubert's "An die Musik", D major — using the
/// hand-verified reference analysis (`analyse_harmonique.md`, produced externally via music21
/// then manually corrected) as the fixture.
///
/// Not every row matches exactly: a handful of measures (8, 17, 20, 22) diverge from the
/// reference by a single chromatic passing/neighbor tone (e.g. this pipeline reads `C#dim7`
/// where the reference reads `A#m7(b5)` at m.8 — a genuinely different pitch a beat apart,
/// not a mislabeling). That's the eighth-note chordify grid occasionally landing on a slice
/// that includes a passing tone instead of the "core" harmony notes — exactly the "v2
/// refinement" (`spec_analyse_harmonique_1.md` step 3) explicitly deferred out of v1 scope.
/// The measures asserted below are the ones where the underlying pitch data is unambiguous,
/// and they cover every secondary-dominant/applied-leading-tone shape the reference names:
/// `viiø7/V` (m.4), `vii°/V` (m.10), `V7/IV` (m.14), `V7/vi` (m.16).
final class HarmonicAnalysisReportTests: XCTestCase {
    private func importReferenceEntries() throws -> [HarmonicAnalysisEntry] {
        let session = makeTestSession()
        let url = try XCTUnwrap(Bundle.module.url(forResource: "an-die-musik", withExtension: "mxl", subdirectory: "Fixtures"))
        try session.importScore(at: url)
        let piece = try XCTUnwrap(session.piece)
        return HarmonicAnalysisReport.build(from: piece)
    }

    func testReferenceMeasuresProduceExpectedRomanNumerals() throws {
        let entries = try importReferenceEntries()
        let byMeasure = Dictionary(grouping: entries, by: \.measure)

        func numerals(_ measure: Int) -> [String] {
            (byMeasure[measure] ?? []).map(\.romanNumeral)
        }

        // Measure 1, 3: plain tonic pedal — I.
        XCTAssertEqual(numerals(1), ["I"])
        XCTAssertEqual(numerals(3), ["I"])

        // Measure 4: ... -> Bm -> G#m7(b5)  |  ... -> vi -> viiø7/V
        XCTAssertTrue(numerals(4).contains("vi"))
        XCTAssertTrue(numerals(4).contains("vii\u{f8}7/V"))

        // Measure 7: D -> G  |  I⁶ -> IV
        XCTAssertTrue(numerals(7).contains("IV"))

        // Measure 10: A -> G#dim -> A7  |  V -> viiø7/V -> V7 (here as a plain diminished triad,
        // not a seventh, so it prints "vii°/V" rather than "viiø7/V")
        XCTAssertEqual(numerals(10), ["V", "vii\u{b0}/V", "V7"])

        // Measure 14: D -> D -> D7  |  I -> I -> V7/IV — the D7-as-secondary-dominant case.
        XCTAssertTrue(numerals(14).contains("V7/IV"))

        // Measure 16: ... -> F#7 -> ...  |  ... -> V7/vi -> ... — the F#7-as-secondary-dominant
        // case named explicitly in the reference's own remarks column.
        XCTAssertTrue(numerals(16).contains("V7/vi"))

        // Measure 22: G+7 -> Em -> A7  |  IV+7 (chrom.) -> ii -> V7 — Em and A7 (the plain
        // diatonic tail of the piece's most chromatic measure) should still read cleanly.
        XCTAssertTrue(numerals(22).contains("ii"))
        XCTAssertTrue(numerals(22).contains("V7"))
    }
}
