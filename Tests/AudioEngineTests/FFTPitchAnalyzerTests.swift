import XCTest
@testable import AudioEngine

final class FFTPitchAnalyzerTests: XCTestCase {

    private func sineWave(frequencyHz: Double, sampleRate: Double, count: Int, amplitude: Float = 1.0) -> [Float] {
        (0..<count).map { i in
            amplitude * Float(sin(2.0 * Double.pi * frequencyHz * Double(i) / sampleRate))
        }
    }

    /// Sums several sine waves at equal amplitude into one signal — a synthetic stand-in
    /// for a chord (several simultaneous notes) without needing real audio input.
    private func mixedSineWaves(frequenciesHz: [Double], sampleRate: Double, count: Int, amplitude: Float = 1.0) -> [Float] {
        var mix = [Float](repeating: 0, count: count)
        for frequency in frequenciesHz {
            let wave = sineWave(frequencyHz: frequency, sampleRate: sampleRate, count: count, amplitude: amplitude)
            for i in 0..<count { mix[i] += wave[i] }
        }
        return mix
    }

    func testDetectsA440SineWave() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = sineWave(frequencyHz: 440, sampleRate: 44100, count: 4096)
        let detected = analyzer.dominantFrequency(in: samples, sampleRate: 44100)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 440, accuracy: 2.0)
    }

    func testDetectsMiddleCSineWave() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = sineWave(frequencyHz: 261.63, sampleRate: 44100, count: 4096)
        let detected = analyzer.dominantFrequency(in: samples, sampleRate: 44100)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 261.63, accuracy: 2.0)
    }

    func testReturnsNilForSilence() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = [Float](repeating: 0, count: 4096)
        XCTAssertNil(analyzer.dominantFrequency(in: samples, sampleRate: 44100))
    }

    func testReturnsNilForLowAmplitudeNoise() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        var generator = SystemRandomNumberGenerator()
        let samples = (0..<4096).map { _ in Float.random(in: -0.0001...0.0001, using: &generator) }
        XCTAssertNil(analyzer.dominantFrequency(in: samples, sampleRate: 44100))
    }

    func testReturnsNilWhenSampleCountDoesNotMatchSize() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        XCTAssertNil(analyzer.dominantFrequency(in: [Float](repeating: 0, count: 100), sampleRate: 44100))
    }

    func testRespectsMinAndMaxHzRange() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        // A strong 100Hz tone should not be reported if the caller only wants 200-2000Hz.
        let samples = sineWave(frequencyHz: 100, sampleRate: 44100, count: 4096)
        XCTAssertNil(analyzer.dominantFrequency(in: samples, sampleRate: 44100, minHz: 200, maxHz: 2000))
    }

    func testMidiPitchFromFrequencyMatchesKnownNotes() {
        XCTAssertEqual(DetectedPitch.midiPitch(forFrequencyHz: 440.0), 69)   // A4
        XCTAssertEqual(DetectedPitch.midiPitch(forFrequencyHz: 261.63), 60) // C4 (middle C)
        XCTAssertEqual(DetectedPitch.midiPitch(forFrequencyHz: 220.0), 57)  // A3
    }

    func testRMSOfSilenceIsZero() {
        XCTAssertEqual(FFTPitchAnalyzer.rms(of: [Float](repeating: 0, count: 4096)), 0)
    }

    func testRMSOfFullScaleSineIsAboutOneOverSqrtTwo() {
        let samples = sineWave(frequencyHz: 440, sampleRate: 44100, count: 4096)
        XCTAssertEqual(FFTPitchAnalyzer.rms(of: samples), Float(1.0 / 2.0.squareRoot()), accuracy: 0.01)
    }

    func testRMSScalesWithAmplitude() {
        // amplitude 0.001 sine -> rms ~= 0.001/sqrt(2) =~ 0.0007, comfortably below the
        // 0.003 detection floor (unlike e.g. amplitude 0.01, whose rms of ~0.007 clears it).
        let quiet = sineWave(frequencyHz: 440, sampleRate: 44100, count: 4096, amplitude: 0.001)
        XCTAssertLessThan(FFTPitchAnalyzer.rms(of: quiet), FFTPitchAnalyzer.minimumRMSForDetection)
    }

    // MARK: - dominantFrequencies (multi-peak / chord detection)

    func testDetectsAllThreeNotesOfACMajorTriad() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        // C4, E4, G4 — each at a fraction of full amplitude so the mix doesn't clip.
        let samples = mixedSineWaves(frequenciesHz: [261.63, 329.63, 392.00], sampleRate: 44100, count: 4096, amplitude: 0.3)
        let detected = analyzer.dominantFrequencies(in: samples, sampleRate: 44100)
        XCTAssertEqual(detected.count, 3)
        let sorted = detected.sorted()
        XCTAssertEqual(sorted[0], 261.63, accuracy: 3.0)
        XCTAssertEqual(sorted[1], 329.63, accuracy: 3.0)
        XCTAssertEqual(sorted[2], 392.00, accuracy: 3.0)
    }

    func testDominantFrequenciesReturnsEmptyForSilence() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        XCTAssertEqual(analyzer.dominantFrequencies(in: [Float](repeating: 0, count: 4096), sampleRate: 44100), [])
    }

    func testDominantFrequenciesRespectsMaxPeaks() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = mixedSineWaves(frequenciesHz: [261.63, 329.63, 392.00, 440.00], sampleRate: 44100, count: 4096, amplitude: 0.25)
        let detected = analyzer.dominantFrequencies(in: samples, sampleRate: 44100, maxPeaks: 2)
        XCTAssertEqual(detected.count, 2)
    }

    func testDominantFrequenciesMergesPeaksCloserThanMinSemitoneSeparation() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        // 440Hz and 445Hz are well under a semitone apart (a semitone above 440Hz is ~466Hz).
        let samples = mixedSineWaves(frequenciesHz: [440, 445], sampleRate: 44100, count: 4096, amplitude: 0.5)
        let detected = analyzer.dominantFrequencies(in: samples, sampleRate: 44100, minSemitoneSeparation: 1.0)
        XCTAssertEqual(detected.count, 1)
    }

    func testDominantFrequencyMatchesFirstOfDominantFrequencies() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = mixedSineWaves(frequenciesHz: [261.63, 392.00], sampleRate: 44100, count: 4096, amplitude: 0.4)
        let single = analyzer.dominantFrequency(in: samples, sampleRate: 44100)
        let multi = analyzer.dominantFrequencies(in: samples, sampleRate: 44100, maxPeaks: 1)
        XCTAssertEqual(single, multi.first)
    }

    // MARK: - monophonicFundamentalHeuristic / monophonicFundamentalHPS

    /// A fundamental plus its own harmonics at independently chosen amplitudes — a synthetic
    /// stand-in for a real instrument tone whose harmonic series isn't flat, unlike
    /// `mixedSineWaves`'s equal-amplitude chord stand-in. `harmonicAmplitudes[0]` is the
    /// fundamental's own amplitude, `[1]` the 2nd harmonic's, etc.
    private func harmonicRichWave(fundamentalHz: Double, harmonicAmplitudes: [Float], sampleRate: Double, count: Int) -> [Float] {
        var mix = [Float](repeating: 0, count: count)
        for (index, amplitude) in harmonicAmplitudes.enumerated() {
            let wave = sineWave(frequencyHz: fundamentalHz * Double(index + 1), sampleRate: sampleRate, count: count, amplitude: amplitude)
            for i in 0..<count { mix[i] += wave[i] }
        }
        return mix
    }

    /// Documents the known limitation `monophonicFundamentalHeuristic`/`monophonicFundamentalHPS`
    /// exist to fix: plain peak-picking locks onto the louder 2nd harmonic instead of the
    /// weaker true fundamental.
    func testDominantFrequencyLocksOntoStrongSecondHarmonicWhenFundamentalIsWeak() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = harmonicRichWave(fundamentalHz: 220, harmonicAmplitudes: [0.25, 0.5], sampleRate: 44100, count: 4096)
        let detected = analyzer.dominantFrequency(in: samples, sampleRate: 44100)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 440, accuracy: 3.0)
    }

    func testMonophonicFundamentalHeuristicRecoversWeakFundamentalUnderStrongSecondHarmonic() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = harmonicRichWave(fundamentalHz: 220, harmonicAmplitudes: [0.25, 0.5], sampleRate: 44100, count: 4096)
        let detected = analyzer.monophonicFundamentalHeuristic(in: samples, sampleRate: 44100)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 220, accuracy: 3.0)
    }

    func testMonophonicFundamentalHeuristicMatchesPlainPeakForAPureTone() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = sineWave(frequencyHz: 440, sampleRate: 44100, count: 4096)
        let detected = analyzer.monophonicFundamentalHeuristic(in: samples, sampleRate: 44100)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 440, accuracy: 2.0)
    }

    func testMonophonicFundamentalHeuristicReturnsNilForSilence() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        XCTAssertNil(analyzer.monophonicFundamentalHeuristic(in: [Float](repeating: 0, count: 4096), sampleRate: 44100))
    }

    func testMonophonicFundamentalHPSRecoversWeakFundamentalUnderStrongSecondHarmonic() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = harmonicRichWave(fundamentalHz: 220, harmonicAmplitudes: [0.25, 0.5], sampleRate: 44100, count: 4096)
        let detected = analyzer.monophonicFundamentalHPS(in: samples, sampleRate: 44100)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 220, accuracy: 3.0)
    }

    func testMonophonicFundamentalHPSMatchesPlainPeakForAPureTone() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        let samples = sineWave(frequencyHz: 440, sampleRate: 44100, count: 4096)
        let detected = analyzer.monophonicFundamentalHPS(in: samples, sampleRate: 44100)
        XCTAssertNotNil(detected)
        XCTAssertEqual(detected!, 440, accuracy: 2.0)
    }

    func testMonophonicFundamentalHPSReturnsNilForSilence() {
        let analyzer = FFTPitchAnalyzer(size: 4096)
        XCTAssertNil(analyzer.monophonicFundamentalHPS(in: [Float](repeating: 0, count: 4096), sampleRate: 44100))
    }
}
