import SwiftUI
import CoreGraphics

/// A scrolling waterfall spectrogram — time on the x-axis (oldest at the left, newest at the
/// right, one column per accumulated `Column`), frequency on the y-axis (log-scaled in pitch,
/// same convention as `SpectrumView`, so a held note lines up with its own row), color-coded by
/// intensity. A vertical keyboard strip sits to the left, ROTATED from `SpectrumView`'s
/// horizontal one but sharing the exact same pitch-to-position math, so its keys land exactly
/// on the frequency rows they represent — the visual counterpart to `SpectrumView` for "what
/// happened over the last N seconds" instead of "what's happening right now."
///
/// The caller owns the history buffer (this view holds no session state of its own, same
/// `SpectrumView` philosophy) — typically a capped array a `Timer`/similar periodic tick
/// appends one fresh `Column` to and trims from the front once past capacity.
public struct SpectrogramView: View {
    /// One FFT snapshot's worth of column data — `binHz` travels WITH each column (not shared
    /// once for the whole view) since nothing prevents the analyzer's sample rate/FFT size from
    /// changing between snapshots in principle, and the per-column cost of carrying it is
    /// negligible.
    public struct Column {
        public let magnitudes: [Float]
        public let binHz: Double
        public init(magnitudes: [Float], binHz: Double) {
            self.magnitudes = magnitudes
            self.binHz = binHz
        }
    }

    /// Oldest first, newest last — index `count - 1` is always the rightmost (most recent)
    /// column, matching how a live waterfall scrolls (new data enters at the right, ages
    /// leftward, same reading direction as this app's own RTL-agnostic timelines elsewhere).
    public let history: [Column]
    public let markedPitches: [Int]
    public let minHz: Double
    public let maxHz: Double
    public let calibrationQuietMagnitude: Float?
    public let calibrationLoudMagnitude: Float?

    public init(
        history: [Column], markedPitches: [Int] = [],
        minHz: Double = 27.5, maxHz: Double = 4186.01,
        calibrationQuietMagnitude: Float? = nil, calibrationLoudMagnitude: Float? = nil
    ) {
        self.history = history
        self.markedPitches = markedPitches
        self.minHz = minHz
        self.maxHz = maxHz
        self.calibrationQuietMagnitude = calibrationQuietMagnitude
        self.calibrationLoudMagnitude = calibrationLoudMagnitude
    }

    // MARK: - Shared pitch math (identical formulas to `SpectrumView`, kept independent rather
    // than factored out since these two views live at different call sites and this is the
    // only overlap — see `SpectrumView`'s own doc comment for why pitch, not raw Hz).
    private static func pitch(forHz hz: Double) -> Double { 69.0 + 12.0 * log2(hz / 440.0) }
    private static func hz(forPitch pitch: Double) -> Double { 440.0 * pow(2.0, (pitch - 69.0) / 12.0) }

    private var rawMinPitch: Double { Self.pitch(forHz: minHz) }
    private var rawMaxPitch: Double { Self.pitch(forHz: maxHz) }
    private var lowestKey: Int { Int(rawMinPitch.rounded(.down)) }
    private var highestKey: Int { Int(rawMaxPitch.rounded(.up)) }
    private var axisMinPitch: Double { Double(lowestKey) - 0.5 }
    private var axisMaxPitch: Double { Double(highestKey) + 0.5 }

    public var body: some View {
        HStack(spacing: 2) {
            Canvas { context, size in
                drawVerticalKeyboardStrip(in: context, size: size)
            }
            .frame(width: 56)
            Canvas { context, size in
                drawWaterfall(in: context, size: size)
            }
            .frame(minHeight: 160)
            .background(Color.black.opacity(0.05))
        }
    }

    // MARK: - Waterfall

    /// Builds the whole time x frequency image as one `CGImage` and draws it in a single call —
    /// deliberately NOT one `context.fill` rect per (column, frequency-row) cell: at a couple
    /// hundred columns by a hundred-plus rows, that's tens of thousands of `Canvas` fill calls
    /// every redraw, which is the actual bottleneck (Core Graphics per-path overhead), not the
    /// pixel math itself. Writing straight into a pixel buffer and handing Core Graphics one
    /// image is the standard fix and keeps this view's frame cost flat regardless of history
    /// length or view size.
    private func drawWaterfall(in context: GraphicsContext, size: CGSize) {
        guard let cgImage = makeWaterfallImage(pixelWidth: max(1, Int(size.width)), pixelHeight: max(1, min(Int(size.height), 300))) else { return }
        context.draw(Image(decorative: cgImage, scale: 1), in: CGRect(origin: .zero, size: size))
    }

    private func makeWaterfallImage(pixelWidth: Int, pixelHeight: Int) -> CGImage? {
        guard !history.isEmpty, axisMaxPitch > axisMinPitch else { return nil }
        let peakForScale = max(calibrationLoudMagnitude.map { $0 * 1.2 } ?? (history.compactMap { $0.magnitudes.max() }.max() ?? 0), 1)

        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4)
        for px in 0..<pixelWidth {
            // Nearest-neighbor column lookup: `history.count` columns of real data mapped onto
            // `pixelWidth` output pixels — usually a near-1:1 mapping in practice (this view is
            // typically about as wide as the history buffer is long), so nearest-neighbor reads
            // exactly as sharp as the underlying data actually is, with no invented detail.
            let columnIndex = min(history.count - 1, (px * history.count) / pixelWidth)
            let column = history[columnIndex]
            guard column.binHz > 0, !column.magnitudes.isEmpty else { continue }
            for py in 0..<pixelHeight {
                let t = Double(py) / Double(pixelHeight) // 0 at the top
                let pitch = axisMaxPitch - t * (axisMaxPitch - axisMinPitch)
                let hz = Self.hz(forPitch: pitch)
                let bin = Int((hz / column.binHz).rounded())
                guard column.magnitudes.indices.contains(bin) else { continue }
                let magnitude = column.magnitudes[bin]
                let ratio = log10(1 + Double(magnitude)) / log10(1 + Double(peakForScale))
                let intensity = min(max(ratio, 0), 1)
                let color = Self.thermalColor(intensity)
                let idx = (py * pixelWidth + px) * 4
                pixels[idx] = color.0
                pixels[idx + 1] = color.1
                pixels[idx + 2] = color.2
                pixels[idx + 3] = 255
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData) else { return nil }
        return CGImage(
            width: pixelWidth, height: pixelHeight, bitsPerComponent: 8, bitsPerPixel: 32,
            bytesPerRow: pixelWidth * 4, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent
        )
    }

    /// A dark-to-bright thermal ramp (black -> purple -> red -> orange -> yellow -> pale) —
    /// reads clearly against this app's dark theme and keeps quiet regions genuinely dark
    /// instead of a mid-tone color, so loud transients still pop visually.
    private static func thermalColor(_ intensity: Double) -> (UInt8, UInt8, UInt8) {
        let stops: [(Double, (Double, Double, Double))] = [
            (0.0, (0, 0, 0)),
            (0.15, (24, 0, 42)),
            (0.35, (92, 0, 84)),
            (0.55, (182, 22, 42)),
            (0.75, (230, 102, 18)),
            (0.9, (250, 200, 60)),
            (1.0, (255, 250, 224)),
        ]
        var lower = stops[0], upper = stops[stops.count - 1]
        for i in 0..<(stops.count - 1) where intensity >= stops[i].0 && intensity <= stops[i + 1].0 {
            lower = stops[i]
            upper = stops[i + 1]
            break
        }
        let span = upper.0 - lower.0
        let t = span > 0 ? (intensity - lower.0) / span : 0
        func mix(_ a: Double, _ b: Double) -> UInt8 { UInt8(max(0, min(255, a + (b - a) * t))) }
        return (mix(lower.1.0, upper.1.0), mix(lower.1.1, upper.1.1), mix(lower.1.2, upper.1.2))
    }

    // MARK: - Vertical keyboard strip

    /// `SpectrumView.drawKeyboardStrip`, rotated: pitch now maps to Y (high pitch at the top,
    /// matching the waterfall's own frequency axis) instead of X, and the keyboard's "front"
    /// (where black keys sit, shorter than white keys) faces the waterfall — the strip's RIGHT
    /// edge, since that's the edge adjacent to the frequencies it's labeling. White keys span
    /// the full strip width (touching the waterfall); black keys are inset from the LEFT (the
    /// strip's outer edge) and don't reach all the way across, the rotated equivalent of
    /// `SpectrumView`'s black keys being shorter and "attached at the top."
    private func drawVerticalKeyboardStrip(in context: GraphicsContext, size: CGSize) {
        guard axisMaxPitch > axisMinPitch else { return }
        let held = Set(markedPitches)
        let lowestKey = self.lowestKey
        let highestKey = self.highestKey
        guard lowestKey <= highestKey else { return }

        func y(forPitch pitch: Double) -> CGFloat {
            size.height - CGFloat((pitch - axisMinPitch) / (axisMaxPitch - axisMinPitch)) * size.height
        }
        func isSharp(_ pitch: Int) -> Bool {
            [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12)
        }

        let blackKeyWidth = size.width * 0.62

        // 1) Continuous white background — no per-key gaps.
        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)), with: .color(.white.opacity(0.92)))

        // 2) Held WHITE key highlights.
        for pitch in lowestKey...highestKey where !isSharp(pitch) && held.contains(pitch) {
            let top = y(forPitch: Double(pitch) + 0.5)
            let bottom = y(forPitch: Double(pitch) - 0.5)
            context.fill(Path(CGRect(x: 0, y: top, width: size.width, height: bottom - top)), with: .color(.accentColor))
        }

        // 3) Separator lines per pair of consecutive natural notes — full width at E-F/B-C
        // (no black key between), otherwise centered on the black key's row and only across
        // the portion nearer the waterfall (beyond `blackKeyWidth`), mirroring `SpectrumView`.
        let naturalPitches = (lowestKey...highestKey).filter { !isSharp($0) }
        for (a, b) in zip(naturalPitches, naturalPitches.dropFirst()) {
            let gap = b - a
            let boundaryPitch: Double
            let fullWidth: Bool
            switch gap {
            case 1: boundaryPitch = Double(a) + 0.5; fullWidth = true
            case 2: boundaryPitch = Double(a) + 1.0; fullWidth = false
            default: continue
            }
            let boundaryY = y(forPitch: boundaryPitch)
            var line = Path()
            line.move(to: CGPoint(x: fullWidth ? 0 : blackKeyWidth, y: boundaryY))
            line.addLine(to: CGPoint(x: size.width, y: boundaryY))
            context.stroke(line, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        }

        // 4) C landmarks.
        for pitch in lowestKey...highestKey where ((pitch % 12) + 12) % 12 == 0 {
            let top = y(forPitch: Double(pitch) + 0.5)
            let bottom = y(forPitch: Double(pitch) - 0.5)
            let label = Text("C\(pitch / 12 - 1)").font(.system(size: 7)).foregroundStyle(.black.opacity(0.7))
            context.draw(context.resolve(label), at: CGPoint(x: 14, y: (top + bottom) / 2))
        }

        // 5) Black keys last, on top, inset from the left (outer) edge, not reaching the
        // waterfall edge.
        for pitch in lowestKey...highestKey where isSharp(pitch) {
            let slotTop = y(forPitch: Double(pitch) + 0.5)
            let slotBottom = y(forPitch: Double(pitch) - 0.5)
            let slotHeight = slotBottom - slotTop
            let inset = slotHeight * 0.16
            let rect = CGRect(x: 0, y: slotTop + inset, width: blackKeyWidth, height: slotHeight - inset * 2)
            let fillColor = held.contains(pitch) ? Color.accentColor : Color.black.opacity(0.88)
            context.fill(Path(rect), with: .color(fillColor))
        }
    }
}

#Preview {
    let history: [SpectrogramView.Column] = (0..<120).map { i in
        let mags = (0..<400).map { bin -> Float in
            let base = sin(Double(i) / 15) * 30 + 60
            return Float(max(0, base - abs(Double(bin) - 80) * 0.6 + (bin % 40 == 0 ? 150 : 0)))
        }
        return .init(magnitudes: mags, binHz: 10)
    }
    return SpectrogramView(history: history, markedPitches: [60, 64, 67])
        .padding()
}
