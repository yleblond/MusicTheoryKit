import SwiftUI
import AppCore

/// A continuous 2D sensory-dissonance landscape for a triad above a fixed root — x = the middle
/// note's frequency ratio to the root, y = the top note's, both in `[1, 2]` (one octave); color
/// = total roughness (`SensoryDissonance.totalDissonance`) of the real 3-tone spectrum at that
/// point (`OctaveSpectrumGrid.partials(atFrequencyHz:)`). The current scale's own notes are
/// ticked along both axes (they share the same `[1, 2]` ratio range), the root itself is labeled
/// at the origin corner, one larger marker shows whichever triad `DissonancesLibraryView`
/// currently has selected/playing, and tapping anywhere in the plot reports that point back via
/// `onTapRatios` so the caller can play it.
public struct DissonanceHeatmapView: View {
    public let grid: OctaveSpectrumGrid
    public let resolution: Int
    public let baseNoteLabel: String
    public let axisTicks: [(ratio: Double, label: String, isInScale: Bool)]
    public let markerRatios: (x: Double, y: Double)
    /// Purely graphical Gaussian blur strength (0 = raw/disabled) — see `DissonanceLandscape`'s
    /// own doc comment.
    public let smoothingSigma: Double
    public let onTapRatios: (Double, Double) -> Void

    private struct RenderKey: Equatable {
        let gridKey: OctaveSpectrumGridKey
        let smoothingSigma: Double
    }

    /// Reserved around the plot (see `plotRect`) — the white "paper" background still fills the
    /// FULL view, only the heatmap cells/marker/base-note label are confined to the shrunk plot
    /// rect. Left/bottom carry the axis-tick labels; top/right are plain breathing room, per
    /// explicit request.
    private static let leftMargin: CGFloat = 34
    private static let bottomMargin: CGFloat = 20
    private static let topMargin: CGFloat = 16
    private static let rightMargin: CGFloat = 16

    public init(
        grid: OctaveSpectrumGrid, resolution: Int, baseNoteLabel: String,
        axisTicks: [(ratio: Double, label: String, isInScale: Bool)], markerRatios: (x: Double, y: Double),
        smoothingSigma: Double = 0, onTapRatios: @escaping (Double, Double) -> Void
    ) {
        self.grid = grid
        self.resolution = resolution
        self.baseNoteLabel = baseNoteLabel
        self.axisTicks = axisTicks
        self.markerRatios = markerRatios
        self.smoothingSigma = smoothingSigma
        self.onTapRatios = onTapRatios
    }

    @State private var cellColors: [[Color]]?

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let rect = plotRect(in: size)
                // Fixed white "paper" background, independent of the app's own light/dark theme
                // (same convention `ChordStaffView`/`GuitarChordDiagramView` use for notation
                // surfaces) — a magnitude-encoding heatmap needs its own anchored surface.
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                if let cellColors {
                    drawCells(cellColors, in: context, rect: rect)
                }
                drawAxisTicks(in: context, rect: rect)
                drawBaseNoteLabel(in: context, rect: rect)
                drawTick(label: nil, ratios: markerRatios, in: context, rect: rect, color: .red, radius: 6)
            }
            // `cellColors` starts nil and its own background `.task` below can take a visible
            // moment at a high `resolution`/dense grid — without this, the plot reads as simply
            // BLANK (the white background plus axis ticks look like "nothing happened yet") until
            // it finishes, which can easily be mistaken for needing some other action (e.g.
            // picking a triad) to "unblock" it.
            .overlay { if cellColors == nil { ProgressView() } }
            .contentShape(Rectangle())
            .onTapGesture { location in
                guard let tapped = ratios(forPoint: location, in: plotRect(in: proxy.size)) else { return }
                onTapRatios(tapped.x, tapped.y)
            }
        }
        .task(id: RenderKey(gridKey: grid.key, smoothingSigma: smoothingSigma)) {
            cellColors = Self.computeCellColors(grid: grid, resolution: resolution, smoothingSigma: smoothingSigma)
        }
    }

    /// The heatmap/marker/base-note-label area — the full view size minus the margins reserved
    /// for axis-tick labels (see `leftMargin`/`bottomMargin`). All ratio↔point conversions below
    /// go through this rect, never the raw view `size`, so the plotted `[1, 2]` range always
    /// lands inside it.
    private func plotRect(in size: CGSize) -> CGRect {
        CGRect(
            x: Self.leftMargin, y: Self.topMargin,
            width: max(0, size.width - Self.leftMargin - Self.rightMargin),
            height: max(0, size.height - Self.topMargin - Self.bottomMargin)
        )
    }

    private func point(forRatios ratios: (x: Double, y: Double), in rect: CGRect) -> CGPoint {
        CGPoint(x: rect.minX + CGFloat(ratios.x - 1.0) * rect.width, y: rect.maxY - CGFloat(ratios.y - 1.0) * rect.height)
    }

    /// The inverse of `point(forRatios:in:)` — clamped to `[1, 2]` on both axes, since a tap can
    /// land fractionally outside the plot rect (rounding at its very edges).
    private func ratios(forPoint point: CGPoint, in rect: CGRect) -> (x: Double, y: Double)? {
        guard rect.width > 0, rect.height > 0 else { return nil }
        let x = 1.0 + Double((point.x - rect.minX) / rect.width)
        let y = 1.0 + Double((rect.maxY - point.y) / rect.height)
        return (max(1, min(2, x)), max(1, min(2, y)))
    }

    /// One dissonance evaluation per cell (root vs. the cell's own two swept ratios) — computed
    /// once per grid, not per redraw (a `Canvas` draw closure runs on every frame/resize, and
    /// `SensoryDissonance.totalDissonance`, via `DissonanceLandscape`, is too expensive to repeat
    /// that often at a useful `resolution`).
    private static func computeCellColors(grid: OctaveSpectrumGrid, resolution: Int, smoothingSigma: Double) -> [[Color]] {
        DissonanceLandscape.normalizedValues(grid: grid, resolution: resolution, smoothingSigma: smoothingSigma)
            .map { rowValues in rowValues.map { DissonanceColorRamp.color(forNormalized: $0) } }
    }

    private func drawCells(_ cellColors: [[Color]], in context: GraphicsContext, rect: CGRect) {
        let cellWidth = rect.width / CGFloat(resolution)
        let cellHeight = rect.height / CGFloat(resolution)
        for row in 0..<cellColors.count {
            for col in 0..<cellColors[row].count {
                // Row 0 is ratio 1 (bottom of the [1,2] range) — flip vertically so it draws at
                // the BOTTOM of the plot rect, y increasing upward like the ratio itself.
                let cellRect = CGRect(x: rect.minX + CGFloat(col) * cellWidth, y: rect.maxY - CGFloat(row + 1) * cellHeight, width: cellWidth, height: cellHeight)
                context.fill(Path(cellRect), with: .color(cellColors[row][col]))
            }
        }
    }

    private func drawTick(label: String?, ratios: (x: Double, y: Double), in context: GraphicsContext, rect: CGRect, color: Color, radius: CGFloat) {
        let p = point(forRatios: ratios, in: rect)
        context.fill(Path(ellipseIn: CGRect(x: p.x - radius, y: p.y - radius, width: radius * 2, height: radius * 2)), with: .color(color))
        if let label {
            context.draw(Text(label).font(.system(size: 9)).foregroundStyle(.black), at: CGPoint(x: p.x, y: p.y - radius - 6), anchor: .bottom)
        }
    }

    /// Small tick marks + note names along both axes — every chromatic semitone, not just the
    /// current scale's own notes (they share the same `[1, 2]` ratio range, so one `axisTicks`
    /// list ticks both). Scale notes draw bold/dark; the other, "altered" notes outside the
    /// scale draw as shorter, lighter secondary ticks — still locatable, but visually secondary —
    /// per explicit request. Drawn in the margins `plotRect` carves out, outside the cells.
    private func drawAxisTicks(in context: GraphicsContext, rect: CGRect) {
        for tick in axisTicks {
            let tickLength: CGFloat = tick.isInScale ? 4 : 2
            let opacity: Double = tick.isInScale ? 0.7 : 0.35
            let fontSize: CGFloat = tick.isInScale ? 8 : 7

            let x = point(forRatios: (tick.ratio, 1.0), in: rect).x
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: x, y: rect.maxY))
                    path.addLine(to: CGPoint(x: x, y: rect.maxY + tickLength))
                }, with: .color(.black.opacity(opacity * 0.7))
            )
            context.draw(Text(tick.label).font(.system(size: fontSize)).foregroundStyle(.black.opacity(opacity)), at: CGPoint(x: x, y: rect.maxY + tickLength + 2), anchor: .top)

            let y = point(forRatios: (1.0, tick.ratio), in: rect).y
            context.stroke(
                Path { path in
                    path.move(to: CGPoint(x: rect.minX - tickLength, y: y))
                    path.addLine(to: CGPoint(x: rect.minX, y: y))
                }, with: .color(.black.opacity(opacity * 0.7))
            )
            context.draw(Text(tick.label).font(.system(size: fontSize)).foregroundStyle(.black.opacity(opacity)), at: CGPoint(x: rect.minX - tickLength - 2, y: y), anchor: .trailing)
        }
    }

    /// The root/base note's own name, right at the (1, 1) origin corner both axes start from —
    /// bolder than the plain scale-degree ticks since it's the point everything else is measured
    /// relative to, not just another scale tone.
    private func drawBaseNoteLabel(in context: GraphicsContext, rect: CGRect) {
        let corner = point(forRatios: (1.0, 1.0), in: rect)
        context.draw(
            Text(baseNoteLabel).font(.system(size: 10, weight: .semibold)).foregroundStyle(.black),
            at: CGPoint(x: corner.x + 4, y: corner.y - 4), anchor: .bottomLeading
        )
    }
}
