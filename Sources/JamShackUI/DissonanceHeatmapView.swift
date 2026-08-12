import SwiftUI
import AppCore

/// A continuous 2D sensory-dissonance landscape for a triad above a fixed root — x = the middle
/// note's frequency ratio to the root, y = the top note's, both in `[1, 2]` (one octave); color
/// = total roughness (`SensoryDissonance.totalDissonance`) of the real 3-tone spectrum at that
/// point (`OctaveSpectrumGrid.partials(atFrequencyHz:)`). Small ticks mark where the classic
/// triads (major/minor/diminished/augmented) land under the active temperament; one larger
/// marker shows whichever triad `DissonancesLibraryView` currently has selected/playing.
public struct DissonanceHeatmapView: View {
    public let grid: OctaveSpectrumGrid
    public let resolution: Int
    public let referenceTicks: [(label: String, ratios: (x: Double, y: Double))]
    public let markerRatios: (x: Double, y: Double)

    /// Validated sequential ramp (single hue, light→dark — see the `dataviz` skill's own
    /// `references/palette.md`), lightest step nearest zero/consonant, darkest nearest the
    /// loudest roughness peak. Fixed white "paper" background (same convention
    /// `ChordStaffView`/`GuitarChordDiagramView` already use for notation surfaces, independent
    /// of the app's own light/dark theme) — a magnitude-encoding heatmap needs its own anchored
    /// surface, not a theme-following one.
    private static let sequentialRamp: [(step: Double, hex: String)] = [
        (100, "#cde2fb"), (150, "#b7d3f6"), (200, "#9ec5f4"), (250, "#86b6ef"),
        (300, "#6da7ec"), (350, "#5598e7"), (400, "#3987e5"), (450, "#2a78d6"),
        (500, "#256abf"), (550, "#1c5cab"), (600, "#184f95"), (650, "#104281"), (700, "#0d366b"),
    ]

    public init(grid: OctaveSpectrumGrid, resolution: Int, referenceTicks: [(label: String, ratios: (x: Double, y: Double))], markerRatios: (x: Double, y: Double)) {
        self.grid = grid
        self.resolution = resolution
        self.referenceTicks = referenceTicks
        self.markerRatios = markerRatios
    }

    @State private var cellColors: [[Color]]?

    public var body: some View {
        Canvas { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
            if let cellColors {
                drawCells(cellColors, in: context, size: size)
            }
            for tick in referenceTicks {
                drawTick(label: tick.label, ratios: tick.ratios, in: context, size: size, color: .black.opacity(0.6), radius: 3)
            }
            drawTick(label: nil, ratios: markerRatios, in: context, size: size, color: .red, radius: 6)
        }
        .task(id: grid.key) {
            cellColors = Self.computeCellColors(grid: grid, resolution: resolution)
        }
    }

    /// One dissonance evaluation per cell (root vs. the cell's own two swept ratios) — computed
    /// once per grid, not per redraw (a `Canvas` draw closure runs on every frame/resize, and
    /// `SensoryDissonance.totalDissonance` is too expensive to repeat that often at a useful
    /// `resolution`).
    private static func computeCellColors(grid: OctaveSpectrumGrid, resolution: Int) -> [[Color]] {
        guard let rootHz = grid.points.first?.frequencyHz else { return [] }
        let rootPartials = grid.partials(atFrequencyHz: rootHz)
        var raw = [[Double]](repeating: [Double](repeating: 0, count: resolution), count: resolution)
        var minValue = Double.greatestFiniteMagnitude
        var maxValue = 0.0
        for row in 0..<resolution {
            let yRatio = 1.0 + Double(row) / Double(resolution - 1)
            let tone3 = grid.partials(atFrequencyHz: rootHz * yRatio)
            for col in 0..<resolution {
                let xRatio = 1.0 + Double(col) / Double(resolution - 1)
                let tone2 = grid.partials(atFrequencyHz: rootHz * xRatio)
                let value = SensoryDissonance.totalDissonance(ofTones: [rootPartials, tone2, tone3])
                raw[row][col] = value
                minValue = min(minValue, value)
                maxValue = max(maxValue, value)
            }
        }
        let range = max(maxValue - minValue, 1e-12)
        return raw.map { rowValues in rowValues.map { color(forNormalized: ($0 - minValue) / range) } }
    }

    private static func color(forNormalized t: Double) -> Color {
        let clamped = max(0, min(1, t))
        let steps = sequentialRamp.map(\.step)
        let target = steps.first! + clamped * (steps.last! - steps.first!)
        guard let upperIndex = steps.firstIndex(where: { $0 >= target }), upperIndex > 0 else {
            return Color(hex: sequentialRamp[clamped < 0.5 ? 0 : sequentialRamp.count - 1].hex)
        }
        let lower = sequentialRamp[upperIndex - 1]
        let upper = sequentialRamp[upperIndex]
        let localT = (target - lower.step) / (upper.step - lower.step)
        return blendedHex(lower.hex, upper.hex, fraction: localT)
    }

    /// Direct hex→hex linear RGB blend (0 = `hexA`, 1 = `hexB`) — computed straight from the hex
    /// components (like `Color.pastel`/`Tonnetz.pastel`), not by resolving either `Color` back to
    /// RGB (unsafe inside a `Canvas` draw closure, no live environment there).
    private static func blendedHex(_ hexA: String, _ hexB: String, fraction: Double) -> Color {
        guard let a = rgbComponents(fromHex: hexA), let b = rgbComponents(fromHex: hexB) else { return Color(hex: hexB) }
        let t = max(0, min(1, fraction))
        return Color(red: a.r + (b.r - a.r) * t, green: a.g + (b.g - a.g) * t, blue: a.b + (b.b - a.b) * t)
    }

    private static func rgbComponents(fromHex hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255)
    }

    private func drawCells(_ cellColors: [[Color]], in context: GraphicsContext, size: CGSize) {
        let cellWidth = size.width / CGFloat(resolution)
        let cellHeight = size.height / CGFloat(resolution)
        for row in 0..<cellColors.count {
            for col in 0..<cellColors[row].count {
                // Row 0 is ratio 1 (bottom of the [1,2] range) — flip vertically so it draws at
                // the BOTTOM of the canvas, y increasing upward like the ratio itself.
                let rect = CGRect(x: CGFloat(col) * cellWidth, y: size.height - CGFloat(row + 1) * cellHeight, width: cellWidth, height: cellHeight)
                context.fill(Path(rect), with: .color(cellColors[row][col]))
            }
        }
    }

    private func drawTick(label: String?, ratios: (x: Double, y: Double), in context: GraphicsContext, size: CGSize, color: Color, radius: CGFloat) {
        let x = CGFloat((ratios.x - 1.0)) * size.width
        let y = size.height - CGFloat((ratios.y - 1.0)) * size.height
        context.fill(Path(ellipseIn: CGRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        if let label {
            context.draw(Text(label).font(.system(size: 9)).foregroundStyle(.black), at: CGPoint(x: x, y: y - radius - 6), anchor: .bottom)
        }
    }
}
