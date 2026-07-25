import SwiftUI

/// A microphone spectroscope: the live FFT magnitude spectrum as a filled area graph, with a
/// vertical marker at each currently-detected note's frequency, plus a small chromatic keyboard
/// strip directly below sharing the exact same x-axis — the visual counterpart to
/// `FFTPitchAnalyzer.spectrumSnapshot`/`ImprovSession.currentMicrophoneSpectrum()`. Pure
/// `Canvas`, no live session state of its own — the caller polls (typically a
/// `TimelineView`) and passes a fresh snapshot each tick.
///
/// **The x-axis is linear in pitch (log-frequency), not linear in Hz.** Piano notes are evenly
/// spaced in log-frequency (each semitone = Hz x 2^(1/12)) — a linear-Hz axis would leave low
/// notes crammed on the left and high notes stretched across most of the width, and a keyboard
/// drawn below it could never line its keys up with the spectrum's own peaks. Mapping x by
/// pitch instead means the keyboard strip below can use plain equal-width keys (one per
/// semitone, not a realistic 7-white/5-black piano layout, whose keys are NOT equal width and
/// so couldn't stay aligned with a continuous frequency axis) and have every key land exactly
/// under its own frequency on the graph above.
///
/// **The y-axis is stable, not relative to whatever's loudest right now, and clamps at the
/// top.** `calibrationQuietMagnitude`/`calibrationLoudMagnitude` are RESOLVED values — the
/// caller (`MicrophoneCalibrationSettingsFile.estimatedQuietPeakMagnitude`/
/// `estimatedLoudPeakMagnitude`) always provides a real number, either the exact peak observed
/// during calibration or a proper RMS-to-magnitude conversion, never "whatever's loudest this
/// frame." The scale is fixed at 120% of the loud value; anything louder clips flat at the top
/// (losing the tip of an overloud peak is the deliberate trade-off of a stable axis).
public struct SpectrumView: View {
    public let magnitudes: [Float]
    public let binHz: Double
    /// MIDI pitches to mark/highlight — drawn as a vertical line on the spectrum and as a
    /// filled key on the keyboard strip below, regardless of `magnitudes` being empty/silent,
    /// so a note that was just detected still shows immediately.
    public let markedPitches: [Int]
    public let minHz: Double
    public let maxHz: Double
    /// Resolved calibration magnitudes to draw as horizontal dashed reference lines AND to
    /// anchor the y-axis scale (120% of `calibrationLoudMagnitude`) — see the type's own doc
    /// comment. `nil` omits a line entirely and, for the loud value specifically, falls back
    /// to the old (unstable) current-peak-relative scale — only relevant if a caller has no
    /// calibration data at all to offer, which shouldn't happen via `MicrophoneControlsView`.
    public let calibrationQuietMagnitude: Float?
    public let calibrationLoudMagnitude: Float?

    /// A0 (27.5 Hz, MIDI 21) through C8 (4186.01 Hz, MIDI 108) — the full 88-key piano range —
    /// is the default frequency window, not an arbitrary "audible range" band, so the keyboard
    /// strip below always shows a complete, real keyboard rather than an arbitrary slice of
    /// one. (Plain literals rather than `Self.hz(forPitch:)` here: a default argument
    /// expression must be at least as accessible as the callers that rely on it, and this
    /// `init` is called from outside this file/module.)
    public init(
        magnitudes: [Float], binHz: Double, markedPitches: [Int] = [],
        minHz: Double = 27.5, maxHz: Double = 4186.01,
        calibrationQuietMagnitude: Float? = nil, calibrationLoudMagnitude: Float? = nil
    ) {
        self.magnitudes = magnitudes
        self.binHz = binHz
        self.markedPitches = markedPitches
        self.minHz = minHz
        self.maxHz = maxHz
        self.calibrationQuietMagnitude = calibrationQuietMagnitude
        self.calibrationLoudMagnitude = calibrationLoudMagnitude
    }

    /// Continuous MIDI pitch number for a frequency in Hz (A4 = 440Hz = 69) — the inverse of
    /// `DetectedPitch.midiPitch(forFrequencyHz:)`'s rounding, kept fractional since this is used
    /// for continuous x-axis positioning, not note identification.
    private static func pitch(forHz hz: Double) -> Double {
        69.0 + 12.0 * log2(hz / 440.0)
    }

    private var rawMinPitch: Double { Self.pitch(forHz: minHz) }
    private var rawMaxPitch: Double { Self.pitch(forHz: maxHz) }
    private var lowestKey: Int { Int(rawMinPitch.rounded(.down)) }
    private var highestKey: Int { Int(rawMaxPitch.rounded(.up)) }
    /// The domain actually used for EVERY x-axis computation below (curve, markers, keyboard
    /// strip) — `[minHz, maxHz]`'s pitch range widened just enough to land on whole-key
    /// boundaries at both ends. Without this, the lowest/highest visible key would be a
    /// partial sliver (cut off mid-key by the view's own edge) instead of a full key — reported
    /// as "missing the last octave and the first notes" since a half-drawn key at the edge
    /// reads as absent, not partial. Using ONE shared domain everywhere (rather than the exact
    /// `[minHz,maxHz]` for the curve and a separately-widened one for the keyboard) is what
    /// keeps the two canvases pixel-aligned — the alignment is the whole point of this view.
    private var axisMinPitch: Double { Double(lowestKey) - 0.5 }
    private var axisMaxPitch: Double { Double(highestKey) + 0.5 }

    public var body: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                draw(in: context, size: size)
            }
            .frame(minHeight: 120)
            .background(Color.black.opacity(0.05))
            Canvas { context, size in
                drawKeyboardStrip(in: context, size: size)
            }
            .frame(height: 56)
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        drawMarkers(in: context, size: size)
        guard binHz > 0, !magnitudes.isEmpty else { return }
        let axisMinPitch = self.axisMinPitch, axisMaxPitch = self.axisMaxPitch
        guard axisMaxPitch > axisMinPitch else { return }

        // Bin 0 is DC (0 Hz) — log2(0) is undefined, so it's always excluded; only bins whose
        // frequency falls in [minHz, maxHz] contribute to the visible curve.
        let minBin = max(1, Int(minHz / binHz))
        let maxBin = min(magnitudes.count - 1, Int(maxHz / binHz))
        guard minBin < maxBin else { return }
        let band = Array(magnitudes[minBin...maxBin])

        // Stable reference when calibrated (120% of the resolved loud magnitude — see the
        // type's own doc comment); otherwise the old current-peak-relative fallback, which is
        // always available but re-stretches to fill the height every frame.
        let peakForScale = max(calibrationLoudMagnitude.map { $0 * 1.2 } ?? (band.max() ?? 0), 1)

        // Log-scaled magnitude — a linear scale makes anything but the single loudest peak
        // invisible, since a real spectrum's energy spans several orders of magnitude.
        // Explicitly clamped to [0, 1]: once calibrated, `peakForScale` is a FIXED 120%-of-loud
        // ceiling, not necessarily this frame's own loudest bin, so a signal louder than that
        // ceiling must have its peak clipped flat at the top of the graph — losing the tip of
        // the peak is the deliberate trade-off of a stable axis, not a bug to smooth over.
        func normalizedHeight(_ magnitude: Float) -> CGFloat {
            let ratio = log10(1 + Double(magnitude)) / log10(1 + Double(peakForScale))
            return CGFloat(min(max(ratio, 0), 1))
        }
        func x(forBin bin: Int) -> CGFloat {
            let hz = Double(bin) * binHz
            let pitch = Self.pitch(forHz: hz)
            return CGFloat((pitch - axisMinPitch) / (axisMaxPitch - axisMinPitch)) * size.width
        }

        var path = Path()
        path.move(to: CGPoint(x: x(forBin: minBin), y: size.height))
        for (offset, magnitude) in band.enumerated() {
            let bin = minBin + offset
            let py = size.height - normalizedHeight(magnitude) * size.height
            path.addLine(to: CGPoint(x: x(forBin: bin), y: py))
        }
        path.addLine(to: CGPoint(x: x(forBin: maxBin), y: size.height))
        path.closeSubpath()
        context.fill(path, with: .color(.accentColor.opacity(0.35)))
        context.stroke(path, with: .color(.accentColor), lineWidth: 1)

        drawCalibrationThresholds(in: context, size: size, normalizedHeight: normalizedHeight)
    }

    /// Horizontal dashed reference lines at the resolved quiet/loud calibration magnitudes —
    /// "at what height would the curve reach if the signal were exactly at the calibrated
    /// quiet/loud level." Both are already-resolved magnitudes (see the type's own doc
    /// comment) — no unit conversion happens here anymore.
    private func drawCalibrationThresholds(in context: GraphicsContext, size: CGSize, normalizedHeight: (Float) -> CGFloat) {
        func line(magnitude: Float?, color: Color, label: String) {
            guard let magnitude, magnitude > 0 else { return }
            let y = size.height - normalizedHeight(magnitude) * size.height
            guard y >= 0, y <= size.height else { return }
            var path = Path()
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: size.width, y: y))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
            let text = Text(label).font(.system(size: 8)).foregroundStyle(color)
            // Clamp the LABEL (not the line itself) so it stays fully readable even when the
            // line sits right at the very top/bottom edge — e.g. a "loud" line drawn near the
            // top when the current peak approaches the calibrated loud reference.
            let labelY = min(max(y - 7, 7), size.height - 7)
            context.draw(context.resolve(text), at: CGPoint(x: 14, y: labelY))
        }
        line(magnitude: calibrationQuietMagnitude, color: .yellow, label: "faible")
        line(magnitude: calibrationLoudMagnitude, color: .orange, label: "forte")
    }

    private func drawMarkers(in context: GraphicsContext, size: CGSize) {
        let axisMinPitch = self.axisMinPitch, axisMaxPitch = self.axisMaxPitch
        guard axisMaxPitch > axisMinPitch else { return }
        for pitch in markedPitches {
            guard Double(pitch) >= axisMinPitch, Double(pitch) <= axisMaxPitch else { continue }
            let px = CGFloat((Double(pitch) - axisMinPitch) / (axisMaxPitch - axisMinPitch)) * size.width
            var line = Path()
            line.move(to: CGPoint(x: px, y: 0))
            line.addLine(to: CGPoint(x: px, y: size.height))
            context.stroke(line, with: .color(.red), lineWidth: 1.5)
        }
    }

    /// A small chromatic keyboard strip — one equal-width slot per semitone, so every key
    /// lines up exactly under its own frequency on the spectrum above (see the type's own doc
    /// comment for why this isn't a realistic piano layout) — but drawn with real piano-key
    /// SHAPE cues for a familiar visual read. Spans whatever `[minHz,maxHz]` covers — the full
    /// 88-key piano range by default (see `init`'s own doc comment).
    ///
    /// **White keys actually join beneath the black keys.** A continuous white background
    /// fills the whole strip first (so there's never a bare-background gap), and separator
    /// lines are positioned per NATURAL-NOTE PAIR, not per semitone: between two naturals with
    /// no black key between them (E-F, B-C) the separator sits at the natural boundary, full
    /// height. Between two naturals WITH a black key between them (e.g. C and D, via C#), the
    /// separator sits at the CENTER of that black key's own slot, not at either of its edges —
    /// exactly how a real piano's C and D keys are notched around C# and meet in the middle
    /// beneath it — and only in the bottom (front) portion, below the black key's own height,
    /// since the black key itself (drawn last, on top) already provides the visual break for
    /// the top portion.
    private func drawKeyboardStrip(in context: GraphicsContext, size: CGSize) {
        let axisMinPitch = self.axisMinPitch, axisMaxPitch = self.axisMaxPitch
        guard axisMaxPitch > axisMinPitch else { return }
        let held = Set(markedPitches)
        let lowestKey = self.lowestKey
        let highestKey = self.highestKey
        guard lowestKey <= highestKey else { return }

        func x(forPitch pitch: Double) -> CGFloat {
            CGFloat((pitch - axisMinPitch) / (axisMaxPitch - axisMinPitch)) * size.width
        }
        func isSharp(_ pitch: Int) -> Bool {
            [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12)
        }

        let blackKeyHeight = size.height * 0.62

        // 1) One continuous white background — no per-key gaps anywhere.
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)), with: .color(.white.opacity(0.92)))

        // 2) Held WHITE key highlights, each still its own one-semitone slot (a real piano's
        // physical white keys are wider than one semitone up front, but matching that exactly
        // isn't the point here — staying aligned with the correct pitch is).
        for pitch in lowestKey...highestKey where !isSharp(pitch) && held.contains(pitch) {
            let left = x(forPitch: Double(pitch) - 0.5)
            let right = x(forPitch: Double(pitch) + 0.5)
            context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(.accentColor))
        }

        // 3) Separator lines, one per pair of consecutive NATURAL notes (not per semitone) —
        // see this method's own doc comment for exactly where each one lands.
        let naturalPitches = (lowestKey...highestKey).filter { !isSharp($0) }
        for (a, b) in zip(naturalPitches, naturalPitches.dropFirst()) {
            let gap = b - a
            let boundaryPitch: Double
            let fullHeight: Bool
            switch gap {
            case 1: boundaryPitch = Double(a) + 0.5; fullHeight = true // E-F / B-C: no black key between
            case 2: boundaryPitch = Double(a) + 1.0; fullHeight = false // meet at the center of the black key between them
            default: continue // not reachable for consecutive naturals in a chromatic scale
            }
            let boundaryX = x(forPitch: boundaryPitch)
            var line = Path()
            line.move(to: CGPoint(x: boundaryX, y: fullHeight ? 0 : blackKeyHeight))
            line.addLine(to: CGPoint(x: boundaryX, y: size.height))
            context.stroke(line, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        }

        // 4) C landmarks — same octave-boundary convention the rest of this app's keyboard
        // renderers use (e.g. `StaticAssets.swift`'s `octave = pitch/12 - 1`) — without this, a
        // plain row of equal-width keys gives no way to tell which note is which at a glance.
        for pitch in lowestKey...highestKey where ((pitch % 12) + 12) % 12 == 0 {
            let left = x(forPitch: Double(pitch) - 0.5)
            let right = x(forPitch: Double(pitch) + 0.5)
            let label = Text("C\(pitch / 12 - 1)").font(.system(size: 8)).foregroundStyle(.black.opacity(0.7))
            context.draw(context.resolve(label), at: CGPoint(x: (left + right) / 2, y: size.height - 8))
        }

        // 5) Black keys last, on top, shorter (attached at the top, not reaching the bottom)
        // and inset narrower within their slot.
        for pitch in lowestKey...highestKey where isSharp(pitch) {
            let slotLeft = x(forPitch: Double(pitch) - 0.5)
            let slotRight = x(forPitch: Double(pitch) + 0.5)
            let slotWidth = slotRight - slotLeft
            let inset = slotWidth * 0.16
            let rect = CGRect(x: slotLeft + inset, y: 0, width: slotWidth - inset * 2, height: blackKeyHeight)
            let fillColor = held.contains(pitch) ? Color.accentColor : Color.black.opacity(0.88)
            context.fill(Path(rect), with: .color(fillColor))
        }
    }
}

#Preview {
    SpectrumView(
        magnitudes: (0..<400).map { i in Float(max(0, sin(Double(i) / 6) * 40 + (i % 50 == 0 ? 200 : 0))) },
        binHz: 10,
        markedPitches: [60, 64, 67],
        calibrationQuietMagnitude: 2000,
        calibrationLoudMagnitude: 60000
    )
    .padding()
}
