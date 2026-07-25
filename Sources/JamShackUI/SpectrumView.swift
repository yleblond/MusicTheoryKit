import SwiftUI

/// A microphone spectroscope: the live FFT magnitude spectrum as a filled area graph, with a
/// vertical marker at each currently-detected note's frequency — the visual counterpart to
/// `FFTPitchAnalyzer.spectrumSnapshot`/`ImprovSession.currentMicrophoneSpectrum()`. Pure
/// `Canvas`, no live session state of its own — the caller polls (typically a
/// `TimelineView`) and passes a fresh snapshot each tick.
public struct SpectrumView: View {
    public let magnitudes: [Float]
    public let binHz: Double
    /// MIDI pitches to mark with a vertical line (e.g. the microphone track's own
    /// `heldPitches`) — drawn regardless of `magnitudes` being empty/silent, so a note that
    /// was just detected still shows its marker on an otherwise-flat graph.
    public let markedPitches: [Int]
    public let minHz: Double
    public let maxHz: Double

    public init(magnitudes: [Float], binHz: Double, markedPitches: [Int] = [], minHz: Double = 60, maxHz: Double = 2000) {
        self.magnitudes = magnitudes
        self.binHz = binHz
        self.markedPitches = markedPitches
        self.minHz = minHz
        self.maxHz = maxHz
    }

    public var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .frame(minHeight: 120)
        .background(Color.black.opacity(0.05))
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        drawMarkers(in: context, size: size)
        guard binHz > 0, !magnitudes.isEmpty else { return }
        let minBin = max(0, Int(minHz / binHz))
        let maxBin = min(magnitudes.count - 1, Int(maxHz / binHz))
        guard minBin < maxBin else { return }
        let band = Array(magnitudes[minBin...maxBin])
        let peak = max(band.max() ?? 0, 1) // avoid divide-by-zero on pure silence

        // Log-scaled magnitude — a linear scale makes anything but the single loudest peak
        // invisible, since a real spectrum's energy spans several orders of magnitude.
        func normalizedHeight(_ magnitude: Float) -> CGFloat {
            CGFloat(log10(1 + Double(magnitude)) / log10(1 + Double(peak)))
        }

        var path = Path()
        path.move(to: CGPoint(x: 0, y: size.height))
        for (offset, magnitude) in band.enumerated() {
            let px = band.count > 1 ? CGFloat(offset) / CGFloat(band.count - 1) * size.width : 0
            let py = size.height - normalizedHeight(magnitude) * size.height
            path.addLine(to: CGPoint(x: px, y: py))
        }
        path.addLine(to: CGPoint(x: size.width, y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(.accentColor.opacity(0.35)))
        context.stroke(path, with: .color(.accentColor), lineWidth: 1)
    }

    private func drawMarkers(in context: GraphicsContext, size: CGSize) {
        guard binHz > 0 else { return }
        let minBin = Double(max(0, Int(minHz / binHz)))
        let maxBin = Double(min(max(magnitudes.count - 1, 1), Int(maxHz / binHz)))
        guard minBin < maxBin else { return }
        for pitch in markedPitches {
            let hz = 440.0 * pow(2.0, (Double(pitch) - 69.0) / 12.0)
            guard hz >= minHz, hz <= maxHz else { continue }
            let bin = hz / binHz
            let px = CGFloat((bin - minBin) / (maxBin - minBin)) * size.width
            var line = Path()
            line.move(to: CGPoint(x: px, y: 0))
            line.addLine(to: CGPoint(x: px, y: size.height))
            context.stroke(line, with: .color(.red), lineWidth: 1.5)
        }
    }
}

#Preview {
    SpectrumView(
        magnitudes: (0..<400).map { i in Float(max(0, sin(Double(i) / 6) * 40 + (i % 50 == 0 ? 200 : 0))) },
        binHz: 10,
        markedPitches: [60, 64, 67]
    )
    .padding()
}
