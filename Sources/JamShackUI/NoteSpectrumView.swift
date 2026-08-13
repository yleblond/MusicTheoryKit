import SwiftUI
import AppCore

/// A few tones' own REAL, FULL FFT magnitude spectra (frequency on x, magnitude on y) as
/// connected LINES — one color per tone, no filled area beneath (unlike `SpectrumView`'s single
/// live magnitude curve, there's no meaningful "silence baseline" to shade in when comparing
/// several tones at once) — plus a keyboard strip below sharing the exact same pitch-linear
/// x-axis, marking each tone's own pitch in its own color. Same visual family as `SpectrumView`
/// (the microphone spectroscope) — see `PitchAxisKeyboardStrip`'s own doc comment for the shared
/// keyboard-strip rendering — but without `SpectrumView`'s calibration threshold lines, which
/// don't apply to a handful of known, just-rendered notes.
///
/// Deliberately shows the FULL spectrum (`RawNoteSpectrum`, hundreds of FFT bins), not
/// `SensoryDissonance`'s reduced `dominantPartials` list — didactic intent: this is meant to show
/// what a tone's timbre actually looks like, not just the few peaks the roughness model reduces
/// it to. Ephemeral by design (see `RawSpectrumRenderer`'s own doc comment) — the caller re-renders
/// fresh for whichever chord is currently selected and discards the previous one, rather than
/// keeping a spectrum around per note ever explored.
public struct NoteSpectrumView: View {
    public struct Tone {
        public let label: String
        public let pitch: Int
        public let color: Color
        public let spectrum: RawNoteSpectrum
        /// The base/root note draws filled (a clear visual anchor — "this is the note everything
        /// else is measured against"); every other tone draws as a plain line only, per explicit
        /// request.
        public let isBase: Bool
        public init(label: String, pitch: Int, color: Color, spectrum: RawNoteSpectrum, isBase: Bool = false) {
            self.label = label
            self.pitch = pitch
            self.color = color
            self.spectrum = spectrum
            self.isBase = isBase
        }
    }

    public let tones: [Tone]
    public let minHz: Double
    public let maxHz: Double

    /// A0 through C8 (the full 88-key piano range), matching `SpectrumView`'s own default —
    /// keeps the two spectrum-family views visually consistent.
    public init(tones: [Tone], minHz: Double = 27.5, maxHz: Double = 4186.01) {
        self.tones = tones
        self.minHz = minHz
        self.maxHz = maxHz
    }

    private static func pitch(forHz hz: Double) -> Double {
        69.0 + 12.0 * log2(hz / 440.0)
    }

    private var rawMinPitch: Double { Self.pitch(forHz: minHz) }
    private var rawMaxPitch: Double { Self.pitch(forHz: maxHz) }
    private var lowestKey: Int { Int(rawMinPitch.rounded(.down)) }
    private var highestKey: Int { Int(rawMaxPitch.rounded(.up)) }
    private var axisMinPitch: Double { Double(lowestKey) - 0.5 }
    private var axisMaxPitch: Double { Double(highestKey) + 0.5 }

    public var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                draw(in: context, size: size)
            }
            .frame(minHeight: 160)
            .background(Color.black.opacity(0.05))
            Canvas { context, size in
                let marked = Dictionary(tones.map { ($0.pitch, $0.color) }, uniquingKeysWith: { first, _ in first })
                PitchAxisKeyboardStrip(axisMinPitch: axisMinPitch, axisMaxPitch: axisMaxPitch, lowestKey: lowestKey, highestKey: highestKey, markedPitches: marked)
                    .draw(in: context, size: size)
            }
            .frame(height: 56)
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        drawLegend(in: context, size: size)
        guard axisMaxPitch > axisMinPitch else { return }
        // One SHARED scale across every tone (not each tone's own loudest bin) so the 3 curves
        // stay directly comparable in relative loudness, same reasoning `SpectrumView` documents
        // for its own stable, non-per-frame-rescaling y-axis.
        let maxMagnitude = tones.map { $0.spectrum.magnitudes.max() ?? 0 }.max() ?? 0
        guard maxMagnitude > 0 else { return }

        func normalizedHeight(_ magnitude: Float) -> CGFloat {
            let ratio = log10(1 + Double(magnitude)) / log10(1 + Double(maxMagnitude))
            return CGFloat(min(max(ratio, 0), 1))
        }

        let baseline = size.height - 2
        let top: CGFloat = 16 // leaves room for the legend drawn at the top

        for tone in tones {
            let binHz = tone.spectrum.binHz
            guard binHz > 0 else { continue }
            let minBin = max(1, Int(minHz / binHz))
            let maxBin = min(tone.spectrum.magnitudes.count - 1, Int(maxHz / binHz))
            guard minBin < maxBin else { continue }

            func x(forBin bin: Int) -> CGFloat {
                let hz = Double(bin) * binHz
                let p = Self.pitch(forHz: hz)
                return CGFloat((p - axisMinPitch) / (axisMaxPitch - axisMinPitch)) * size.width
            }

            var linePath = Path()
            for bin in minBin...maxBin {
                let py = baseline - normalizedHeight(tone.spectrum.magnitudes[bin]) * (baseline - top)
                let point = CGPoint(x: x(forBin: bin), y: py)
                if bin == minBin { linePath.move(to: point) } else { linePath.addLine(to: point) }
            }
            if tone.isBase {
                var fillPath = linePath
                fillPath.addLine(to: CGPoint(x: x(forBin: maxBin), y: baseline))
                fillPath.addLine(to: CGPoint(x: x(forBin: minBin), y: baseline))
                fillPath.closeSubpath()
                context.fill(fillPath, with: .color(tone.color.opacity(0.35)))
            }
            context.stroke(linePath, with: .color(tone.color), lineWidth: 1.2)
        }
    }

    private func drawLegend(in context: GraphicsContext, size: CGSize) {
        var x: CGFloat = 4
        for tone in tones {
            context.fill(Path(CGRect(x: x, y: 2, width: 8, height: 8)), with: .color(tone.color))
            context.draw(Text(tone.label).font(.system(size: 8)).foregroundStyle(.black), at: CGPoint(x: x + 10, y: 6), anchor: .leading)
            x += 56
        }
    }
}
