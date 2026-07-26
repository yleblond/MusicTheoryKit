import SwiftUI
import CoreGraphics

/// A scrolling waterfall spectrogram — time on the x-axis (a FIXED window of `totalColumns`
/// slots; real data fills in from the RIGHT as `history` grows, the left stays blank until
/// enough time has passed — not a stretch-to-fit of however much history happens to exist yet),
/// frequency on the y-axis (log-scaled in pitch, same convention as `SpectrumView`, so a held
/// note lines up with its own row), color-coded by intensity (see `SpectrogramColorScale`,
/// shared with `SpectrogramColorScaleView`'s legend so the two always agree on what a color
/// means). A vertical keyboard strip sits to the left, ROTATED from `SpectrumView`'s horizontal
/// one but sharing the exact same pitch-to-position math, so its keys land exactly on the
/// frequency rows they represent.
///
/// The caller owns the history buffer (this view holds no session state of its own, same
/// `SpectrumView` philosophy) — typically a capped array a periodic tick appends one fresh
/// `Column` to and trims from the front once past `totalColumns`.
public struct SpectrogramView: View {
    /// One FFT snapshot's worth of column data — `binHz` travels WITH each column (not shared
    /// once for the whole view) since nothing prevents the analyzer's sample rate/FFT size from
    /// changing between snapshots in principle, and the per-column cost of carrying it is
    /// negligible. `heldPitches` is that same tick's held notes, for the optional overlay.
    public struct Column {
        public let magnitudes: [Float]
        public let binHz: Double
        public let heldPitches: [Int]
        public init(magnitudes: [Float], binHz: Double, heldPitches: [Int] = []) {
            self.magnitudes = magnitudes
            self.binHz = binHz
            self.heldPitches = heldPitches
        }
    }

    /// Oldest first, newest last — index `count - 1` is always the rightmost (most recent)
    /// column.
    public let history: [Column]
    /// The FIXED number of column slots the x-axis represents — e.g. the caller's history
    /// buffer capacity. `history.count` can be less than this (still filling in) but never more.
    public let totalColumns: Int
    public let markedPitches: [Int]
    public let minHz: Double
    public let maxHz: Double
    public let calibrationQuietMagnitude: Float?
    public let calibrationLoudMagnitude: Float?
    /// Draws each history column's `heldPitches` as small marks at their own (time, frequency)
    /// position, layered on top of the color-coded magnitude image — off by default (it's a
    /// deliberate opt-in overlay, per explicit user request, not a permanent addition to the
    /// base graph).
    public let showNoteOverlay: Bool
    public let palette: SpectrogramPalette

    public init(
        history: [Column], totalColumns: Int, markedPitches: [Int] = [],
        minHz: Double = 27.5, maxHz: Double = 4186.01,
        calibrationQuietMagnitude: Float? = nil, calibrationLoudMagnitude: Float? = nil,
        showNoteOverlay: Bool = false, palette: SpectrogramPalette = .thermal
    ) {
        self.history = history
        self.totalColumns = max(1, totalColumns)
        self.markedPitches = markedPitches
        self.minHz = minHz
        self.maxHz = maxHz
        self.calibrationQuietMagnitude = calibrationQuietMagnitude
        self.calibrationLoudMagnitude = calibrationLoudMagnitude
        self.showNoteOverlay = showNoteOverlay
        self.palette = palette
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
            // `.frame(maxWidth: .infinity)` here is load-bearing, not decorative: a `Canvas`
            // has no intrinsic content size, and without an explicit "expand" signal it can
            // end up sized to something far narrower than the space actually available inside
            // a `Form`/`Section` row on macOS — confirmed via a real screenshot showing a wide
            // dead gap between the keyboard strip and where the waterfall actually started
            // drawing.
            Canvas { context, size in
                drawWaterfall(in: context, size: size)
                if showNoteOverlay {
                    drawNoteOverlay(in: context, size: size)
                }
            }
            .frame(maxWidth: .infinity)
            .background(Color.black.opacity(0.05))
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Column layout (shared by the waterfall image and the note overlay, so the two
    // always agree on exactly where each history column sits horizontally)

    /// Fixed-width columns (`pixelWidth / totalColumns`) — NOT `pixelWidth / history.count`,
    /// which would stretch whatever little history exists yet to fill the whole width. Real
    /// data is right-aligned (newest at the right edge); anything left of `history.count`
    /// columns' worth of width is deliberately left blank, so the graph visibly fills in from
    /// the right as time passes instead of arriving pre-stretched.
    ///
    /// `columnWidth` is a `Double`, NOT rounded down to whole pixels: `pixelWidth / totalColumns`
    /// almost never divides evenly (e.g. a 700px-wide canvas over 240 columns is really 2.91px
    /// each), and truncating that to `2` before multiplying back by `history.count` at full
    /// capacity left a permanent ~200px dead gap at the left that never filled in no matter how
    /// long the capture ran — confirmed via a real screenshot showing the gap stuck at a fixed
    /// width instead of shrinking to zero. Keeping the fractional width and only rounding once,
    /// at the end, when computing `startX`, means a full buffer always reaches `startX == 0`.
    private func columnLayout(pixelWidth: Int) -> (columnWidth: Double, startX: Int) {
        let columnWidth = Double(pixelWidth) / Double(max(1, totalColumns))
        let startX = max(0, pixelWidth - Int((Double(history.count) * columnWidth).rounded()))
        return (columnWidth, startX)
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
        let peakForScale = SpectrogramColorScale.peakForScale(
            calibrationLoudMagnitude: calibrationLoudMagnitude,
            fallback: history.compactMap { $0.magnitudes.max() }.max() ?? 0
        )
        let (columnWidth, startX) = columnLayout(pixelWidth: pixelWidth)

        var pixels = [UInt8](repeating: 0, count: pixelWidth * pixelHeight * 4) // starts fully transparent
        for px in startX..<pixelWidth {
            let historyIndex = min(history.count - 1, Int(Double(px - startX) / columnWidth))
            let column = history[historyIndex]
            guard column.binHz > 0, !column.magnitudes.isEmpty else { continue }
            for py in 0..<pixelHeight {
                let t = Double(py) / Double(pixelHeight) // 0 at the top
                let pitch = axisMaxPitch - t * (axisMaxPitch - axisMinPitch)
                let hz = Self.hz(forPitch: pitch)
                let bin = Int((hz / column.binHz).rounded())
                guard column.magnitudes.indices.contains(bin) else { continue }
                let magnitude = column.magnitudes[bin]
                let intensity = SpectrogramColorScale.intensity(for: magnitude, peakForScale: peakForScale)
                let color = SpectrogramColorScale.color(intensity, palette: palette)
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

    // MARK: - Note overlay

    /// One semi-transparent rect per (history column, held pitch) pair, sized to exactly that
    /// column's on-screen width and that pitch's own row height (the SAME `columnLayout`/pitch
    /// math the waterfall image itself uses, so a mark always lands exactly on the real cell it
    /// represents) — many adjacent columns holding the same pitch naturally read as one
    /// continuous bar, which is exactly "this note was held over this time span."
    private func drawNoteOverlay(in context: GraphicsContext, size: CGSize) {
        guard axisMaxPitch > axisMinPitch, !history.isEmpty else { return }
        let pixelWidth = max(1, Int(size.width))
        let (columnWidth, startX) = columnLayout(pixelWidth: pixelWidth)
        func y(forPitch pitch: Double) -> CGFloat {
            size.height - CGFloat((pitch - axisMinPitch) / (axisMaxPitch - axisMinPitch)) * size.height
        }
        for (index, column) in history.enumerated() {
            guard !column.heldPitches.isEmpty else { continue }
            let left = CGFloat(startX) + CGFloat(index) * CGFloat(columnWidth)
            for pitch in column.heldPitches {
                guard Double(pitch) >= axisMinPitch, Double(pitch) <= axisMaxPitch else { continue }
                let top = y(forPitch: Double(pitch) + 0.5)
                let bottom = y(forPitch: Double(pitch) - 0.5)
                let rect = CGRect(x: left, y: top, width: CGFloat(columnWidth), height: bottom - top)
                context.fill(Path(rect), with: .color(.white.opacity(0.55)))
                context.stroke(Path(rect), with: .color(.white.opacity(0.85)), lineWidth: 0.5)
            }
        }
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
    let history: [SpectrogramView.Column] = (0..<80).map { i in
        let mags = (0..<400).map { bin -> Float in
            let base = sin(Double(i) / 15) * 30 + 60
            return Float(max(0, base - abs(Double(bin) - 80) * 0.6 + (bin % 40 == 0 ? 150 : 0)))
        }
        return .init(magnitudes: mags, binHz: 10, heldPitches: i > 40 ? [60, 64, 67] : [60])
    }
    return SpectrogramView(history: history, totalColumns: 120, markedPitches: [60, 64, 67], showNoteOverlay: true)
        .frame(height: 280)
        .padding()
}
