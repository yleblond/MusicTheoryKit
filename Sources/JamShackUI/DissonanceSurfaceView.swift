import SwiftUI
import AppCore

/// The same sensory-dissonance landscape `DissonanceHeatmapView` draws as a flat 2D heatmap,
/// rendered instead as a rotatable 3D height-field surface (height = normalized roughness) —
/// per explicit request, an alternative "mode de dessin" to the 2D one, not a replacement.
/// Drag to orbit (horizontal drag = azimuth, vertical drag = elevation); tap a point on the
/// surface to report it back via `onTapRatios`, same contract as `DissonanceHeatmapView`.
///
/// This is a hand-rolled orthographic projection over `Canvas`, not `SceneKit`/`RealityKit` or
/// Swift Charts' `Chart3D` — the latter needs iOS/macOS 26, well past this app's 18.0/15.0
/// deployment target, and every other Théorie visualization (Tonnetz, circle of fifths, the 2D
/// heatmap itself) is already a plain `Canvas`, so this keeps the same rendering approach rather
/// than introducing a second, heavier 3D framework for one screen.
public struct DissonanceSurfaceView: View {
    public let grid: OctaveSpectrumGrid
    public let baseNoteLabel: String
    public let axisTicks: [(ratio: Double, label: String, isInScale: Bool)]
    public let markerRatios: (x: Double, y: Double)
    /// The X axis's own currently-played note (the middle tone) — ticked in green, matching
    /// `NoteSpectrumView`'s own per-tone color convention. `nil` draws no extra tick.
    public let playedXNote: (ratio: Double, label: String)?
    /// Same as `playedXNote`, for the Y axis's own currently-played note (the top tone) — ticked
    /// in blue.
    public let playedYNote: (ratio: Double, label: String)?
    /// Purely graphical Gaussian blur strength (0 = raw/disabled) — see `DissonanceLandscape`'s
    /// own doc comment.
    public let smoothingSigma: Double
    public let onTapRatios: (Double, Double) -> Void

    private struct RenderKey: Equatable {
        let gridKey: OctaveSpectrumGridKey
        let smoothingSigma: Double
    }

    /// Coarser than the 2D heatmap's own 64 — each sample here is a real mesh vertex redrawn on
    /// every rotation frame (unlike the 2D view's cells, which are simple flat fills), so keeping
    /// the face count in the low thousands matters for drag responsiveness.
    private static let resolution = 36
    private static let defaultAzimuth = 45.0 * .pi / 180
    private static let defaultElevation = 35.0 * .pi / 180
    private static let minElevation = 6.0 * .pi / 180
    private static let maxElevation = 85.0 * .pi / 180
    /// Visual exaggeration of the height axis relative to the [0,1] x/y footprint — the raw
    /// normalized dissonance already spans [0,1] itself, but a 1:1:1 box reads as flatter than
    /// the reference video's own tall, spiky peaks.
    private static let heightScale = 0.8

    public init(
        grid: OctaveSpectrumGrid, baseNoteLabel: String, axisTicks: [(ratio: Double, label: String, isInScale: Bool)],
        markerRatios: (x: Double, y: Double), playedXNote: (ratio: Double, label: String)? = nil,
        playedYNote: (ratio: Double, label: String)? = nil, smoothingSigma: Double = 0,
        onTapRatios: @escaping (Double, Double) -> Void
    ) {
        self.grid = grid
        self.baseNoteLabel = baseNoteLabel
        self.axisTicks = axisTicks
        self.markerRatios = markerRatios
        self.playedXNote = playedXNote
        self.playedYNote = playedYNote
        self.smoothingSigma = smoothingSigma
        self.onTapRatios = onTapRatios
    }

    @State private var values: [[Double]]?
    @State private var azimuth = DissonanceSurfaceView.defaultAzimuth
    @State private var elevation = DissonanceSurfaceView.defaultElevation
    @State private var dragStartAngles: (azimuth: Double, elevation: Double)?

    public var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(.white))
                if let values {
                    draw(values: values, in: context, size: size)
                }
            }
            // See `DissonanceHeatmapView`'s identical overlay — `values` starts nil and its own
            // background `.task` below can take a visible moment, so this avoids a plain blank
            // canvas reading as "nothing happened."
            .overlay { if values == nil { ProgressView() } }
            .contentShape(Rectangle())
            .gesture(rotationDrag)
            .onTapGesture { location in
                guard let values, let hit = hitTestRatios(at: location, values: values, size: proxy.size) else { return }
                onTapRatios(hit.x, hit.y)
            }
        }
        .task(id: RenderKey(gridKey: grid.key, smoothingSigma: smoothingSigma)) {
            values = DissonanceLandscape.normalizedValues(grid: grid, resolution: Self.resolution, smoothingSigma: smoothingSigma)
        }
    }

    private var rotationDrag: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let start = dragStartAngles ?? (azimuth, elevation)
                if dragStartAngles == nil { dragStartAngles = start }
                azimuth = start.azimuth + Double(value.translation.width) * 0.01
                elevation = max(Self.minElevation, min(Self.maxElevation, start.elevation - Double(value.translation.height) * 0.01))
            }
            .onEnded { _ in dragStartAngles = nil }
    }

    private func projector(size: CGSize) -> Projector {
        Projector(
            azimuth: azimuth, elevation: elevation,
            scale: min(size.width, size.height) * 0.62,
            center: CGPoint(x: size.width / 2, y: size.height / 2 + 10),
            heightScale: Self.heightScale
        )
    }

    // MARK: - Scene assembly (surface faces + marker pin), depth-sorted together

    private enum SceneObject {
        case face(path: Path, color: Color)
        case line(path: Path, color: Color, lineWidth: CGFloat)
        case text(text: Text, at: CGPoint, anchor: UnitPoint)
    }

    private func draw(values: [[Double]], in context: GraphicsContext, size: CGSize) {
        let projector = projector(size: size)
        var objects: [(depth: Double, object: SceneObject)] = []
        objects.append(contentsOf: surfaceFaces(values: values, projector: projector))
        objects.append(contentsOf: axisObjects(projector: projector))
        objects.append(contentsOf: playedNoteObjects(projector: projector))
        objects.append(contentsOf: markerObjects(values: values, projector: projector))
        for entry in objects.sorted(by: { $0.depth < $1.depth }) {
            switch entry.object {
            case .face(let path, let color): context.fill(path, with: .color(color))
            case .line(let path, let color, let lineWidth): context.stroke(path, with: .color(color), lineWidth: lineWidth)
            case .text(let text, let at, let anchor): context.draw(text, at: at, anchor: anchor)
            }
        }
    }

    private func surfaceFaces(values: [[Double]], projector: Projector) -> [(depth: Double, object: SceneObject)] {
        let n = values.count
        guard n > 1 else { return [] }
        var faces: [(depth: Double, object: SceneObject)] = []
        faces.reserveCapacity((n - 1) * (n - 1))
        for row in 0..<(n - 1) {
            for col in 0..<(n - 1) {
                let corners = quadCorners(row: row, col: col, values: values)
                let projected = corners.map { projector.project(x: $0.x, y: $0.y, z: $0.z) }
                var path = Path()
                path.move(to: projected[0].point)
                for p in projected.dropFirst() { path.addLine(to: p.point) }
                path.closeSubpath()
                let avgZ = corners.map(\.z).reduce(0, +) / 4
                let avgDepth = projected.map(\.depth).reduce(0, +) / 4
                faces.append((avgDepth, .face(path: path, color: DissonanceColorRamp.color(forNormalized: avgZ))))
            }
        }
        return faces
    }

    private func quadCorners(row: Int, col: Int, values: [[Double]]) -> [(x: Double, y: Double, z: Double)] {
        let n = values.count
        let x0 = Double(col) / Double(n - 1), x1 = Double(col + 1) / Double(n - 1)
        let y0 = Double(row) / Double(n - 1), y1 = Double(row + 1) / Double(n - 1)
        return [
            (x0, y0, values[row][col]), (x1, y0, values[row][col + 1]),
            (x1, y1, values[row + 1][col + 1]), (x0, y1, values[row + 1][col]),
        ]
    }

    /// Tick marks + the base-note label, projected onto the base plane (`z = 0`) rather than
    /// drawn in flat screen space — so they rotate WITH the surface instead of floating over it.
    private func axisObjects(projector: Projector) -> [(depth: Double, object: SceneObject)] {
        var objects: [(depth: Double, object: SceneObject)] = []
        for tick in axisTicks {
            // Scale notes get a full grid line across the base plane, like the reference video's
            // own floor grid; the other, "altered" notes outside the scale get just a short tick
            // near the near edge — a full line per chromatic note would clutter the base plane.
            let fontSize: CGFloat = tick.isInScale ? 8 : 7
            let opacity: Double = tick.isInScale ? 0.7 : 0.4
            let farY: Double = tick.isInScale ? 1 : 0.08

            let x = tick.ratio - 1.0
            let (nearPoint, nearDepth) = projector.project(x: x, y: 0, z: 0)
            let (farPoint, _) = projector.project(x: x, y: farY, z: 0)
            objects.append((nearDepth, .line(path: linePath(from: nearPoint, to: farPoint), color: .black.opacity(tick.isInScale ? 0.15 : 0.3), lineWidth: 1)))
            objects.append((nearDepth, .text(text: Text(tick.label).font(.system(size: fontSize)).foregroundStyle(.black.opacity(opacity)), at: nearPoint, anchor: .top)))

            let y = tick.ratio - 1.0
            let (nearPoint2, nearDepth2) = projector.project(x: 0, y: y, z: 0)
            let (farPoint2, _) = projector.project(x: farY, y: y, z: 0)
            objects.append((nearDepth2, .line(path: linePath(from: nearPoint2, to: farPoint2), color: .black.opacity(tick.isInScale ? 0.15 : 0.3), lineWidth: 1)))
            objects.append((nearDepth2, .text(text: Text(tick.label).font(.system(size: fontSize)).foregroundStyle(.black.opacity(opacity)), at: nearPoint2, anchor: .trailing)))
        }
        let (origin, originDepth) = projector.project(x: 0, y: 0, z: 0)
        objects.append((originDepth + 0.001, .text(
            text: Text(baseNoteLabel).font(.system(size: 10, weight: .semibold)).foregroundStyle(.black),
            at: origin, anchor: .topTrailing
        )))
        return objects
    }

    /// Full-length, bolder colored grid lines for the currently PLAYED note on each axis — the 3D
    /// analog of `DissonanceHeatmapView.drawPlayedNoteTicks`, same green/blue convention matching
    /// `NoteSpectrumView`'s own tone colors.
    private func playedNoteObjects(projector: Projector) -> [(depth: Double, object: SceneObject)] {
        var objects: [(depth: Double, object: SceneObject)] = []
        if let playedXNote {
            let x = playedXNote.ratio - 1.0
            let (nearPoint, nearDepth) = projector.project(x: x, y: 0, z: 0)
            let (farPoint, _) = projector.project(x: x, y: 1, z: 0)
            objects.append((nearDepth + 0.001, .line(path: linePath(from: nearPoint, to: farPoint), color: .green, lineWidth: 1.5)))
            objects.append((nearDepth + 0.001, .text(text: Text(playedXNote.label).font(.system(size: 8, weight: .bold)).foregroundStyle(.green), at: nearPoint, anchor: .top)))
        }
        if let playedYNote {
            let y = playedYNote.ratio - 1.0
            let (nearPoint, nearDepth) = projector.project(x: 0, y: y, z: 0)
            let (farPoint, _) = projector.project(x: 1, y: y, z: 0)
            objects.append((nearDepth + 0.001, .line(path: linePath(from: nearPoint, to: farPoint), color: .blue, lineWidth: 1.5)))
            objects.append((nearDepth + 0.001, .text(text: Text(playedYNote.label).font(.system(size: 8, weight: .bold)).foregroundStyle(.blue), at: nearPoint, anchor: .trailing)))
        }
        return objects
    }

    /// The currently selected/playing triad as a vertical pin from the base plane up to its own
    /// height on the surface — the 3D analog of the 2D view's flat red dot marker.
    private func markerObjects(values: [[Double]], projector: Projector) -> [(depth: Double, object: SceneObject)] {
        let x = markerRatios.x - 1.0, y = markerRatios.y - 1.0
        let z = height(atX: x, y: y, values: values)
        let (base, baseDepth) = projector.project(x: x, y: y, z: 0)
        let (top, topDepth) = projector.project(x: x, y: y, z: z)
        let pin: SceneObject = .line(path: linePath(from: base, to: top), color: .red, lineWidth: 2)
        let dot = Path(ellipseIn: CGRect(x: top.x - 4, y: top.y - 4, width: 8, height: 8))
        return [(baseDepth, pin), (topDepth + 0.001, .face(path: dot, color: .red))]
    }

    /// Bilinear height lookup at an arbitrary (x, y) in `[0, 1]` — used only to place the marker
    /// pin's own top at the surface's actual sampled height, not to re-derive the surface itself.
    private func height(atX x: Double, y: Double, values: [[Double]]) -> Double {
        let n = values.count
        guard n > 1 else { return 0 }
        let fx = max(0, min(Double(n - 1), x * Double(n - 1)))
        let fy = max(0, min(Double(n - 1), y * Double(n - 1)))
        let col0 = Int(fx), row0 = Int(fy)
        let col1 = min(col0 + 1, n - 1), row1 = min(row0 + 1, n - 1)
        let tx = fx - Double(col0), ty = fy - Double(row0)
        let top = values[row0][col0] * (1 - tx) + values[row0][col1] * tx
        let bottom = values[row1][col0] * (1 - tx) + values[row1][col1] * tx
        return top * (1 - ty) + bottom * ty
    }

    private func linePath(from: CGPoint, to: CGPoint) -> Path {
        var path = Path()
        path.move(to: from)
        path.addLine(to: to)
        return path
    }

    /// Which mesh quad (if any) a tap lands inside, projected the same way the surface itself
    /// was drawn — the frontmost (largest-depth) match wins, since faces are otherwise ambiguous
    /// once rotated (a screen point can fall inside more than one quad's projected outline).
    private func hitTestRatios(at location: CGPoint, values: [[Double]], size: CGSize) -> (x: Double, y: Double)? {
        let projector = projector(size: size)
        let n = values.count
        guard n > 1 else { return nil }
        var best: (depth: Double, x: Double, y: Double)?
        for row in 0..<(n - 1) {
            for col in 0..<(n - 1) {
                let corners = quadCorners(row: row, col: col, values: values)
                let projected = corners.map { projector.project(x: $0.x, y: $0.y, z: $0.z) }
                guard pointInPolygon(location, polygon: projected.map(\.point)) else { continue }
                let avgDepth = projected.map(\.depth).reduce(0, +) / 4
                if best == nil || avgDepth > best!.depth {
                    let centerX = corners.map(\.x).reduce(0, +) / 4
                    let centerY = corners.map(\.y).reduce(0, +) / 4
                    best = (avgDepth, 1.0 + centerX, 1.0 + centerY)
                }
            }
        }
        return best.map { (x: $0.x, y: $0.y) }
    }

    private func pointInPolygon(_ point: CGPoint, polygon: [CGPoint]) -> Bool {
        guard polygon.count > 2 else { return false }
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if (pi.y > point.y) != (pj.y > point.y) {
                let slope = (point.y - pi.y) / (pj.y - pi.y)
                let xCross = pi.x + slope * (pj.x - pi.x)
                if point.x < xCross { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// Orbit-camera orthographic projection: rotate the data (centered on its own footprint) by
    /// `azimuth` around the vertical (height/Z) axis, then combine the tilted horizontal-depth
    /// axis with height (Z) via `elevation` to get both the on-screen vertical position and the
    /// painter's-algorithm `depth` — checked against the two edge cases that catch a mixed-up
    /// axis fastest: at `elevation = 90°` (straight overhead) the screen position must depend
    /// only on (x, y), never z (a top-down view is exactly the 2D heatmap, height invisible),
    /// while `depth` there must depend only on z (a taller peak is genuinely closer to a camera
    /// looking straight down, so it must sort to the front); at `elevation = 0°` (side-on) it's
    /// the other way around — screen position depends only on z, `depth` only on the horizontal
    /// axis. An earlier version of this had the two roles swapped (a taller peak ended up
    /// pushed AWAY from the screen instead of toward it — the "z axis inverted" symptom).
    private struct Projector {
        let azimuth: Double
        let elevation: Double
        let scale: CGFloat
        let center: CGPoint
        let heightScale: Double

        func project(x: Double, y: Double, z: Double) -> (point: CGPoint, depth: Double) {
            let X = x - 0.5, Y = y - 0.5, Z = z * heightScale
            let cosA = cos(azimuth), sinA = sin(azimuth)
            let screenX = X * cosA - Y * sinA
            let horizontalDepth = X * sinA + Y * cosA
            let cosE = cos(elevation), sinE = sin(elevation)
            let screenUp = horizontalDepth * sinE + Z * cosE
            let depth = Z * sinE - horizontalDepth * cosE
            let point = CGPoint(x: center.x + CGFloat(screenX) * scale, y: center.y - CGFloat(screenUp) * scale)
            return (point, depth)
        }
    }
}
