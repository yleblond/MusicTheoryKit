import SwiftUI
import AppCore

/// A polar rendering of the circle-of-fifths wheel (`WebConsoleWheelState`, always present in
/// `SessionUIBridge.state` — never gated behind an active guide), deliberately matching the
/// web console's own `renderWheel`/CSS (`Sources/WebConsole/StaticAssets.swift`) layout-for-
/// layout: same disk/grid/ring structure, same per-note palette colors (not a generic accent
/// color), same square/circle cell shapes, same chord-symbol + relative-degree text, same
/// per-instrument outline rings for occupied cells, same dark-blue diatonic-zone contour. Font
/// sizes are scaled up relative to the web's raw SVG values (which only read comfortably up
/// to the web page's own 820px max-width) since this view typically renders noticeably
/// smaller than that.
public struct CircleOfFifthsWheelView: View {
    public let wheel: WebConsoleWheelState
    public let palette: [String]
    public let paletteTextColors: [String]
    /// Same list `SessionUIBridge.state.tracks` sends — only used to assign each track a
    /// stable accent color by its position (`Self.instrumentColors`), mirroring
    /// `instrumentColor(index)`/`trackColorByLabel` in `StaticAssets.swift`.
    public let tracks: [WebConsoleTrackState]

    public init(wheel: WebConsoleWheelState, palette: [String], paletteTextColors: [String], tracks: [WebConsoleTrackState] = []) {
        self.wheel = wheel
        self.palette = palette
        self.paletteTextColors = paletteTextColors
        self.tracks = tracks
    }

    // MARK: - Layout constants (same 540x540/center-270 unit system the web SVG uses — see
    // `WHEEL_*` constants in `StaticAssets.swift` — scaled by `unit` at draw time).

    private static let viewBoxSize: CGFloat = 540
    private static let diskRadius: CGFloat = 262
    private static let hubRadius: CGFloat = 70
    private static let gridOuterRadius: CGFloat = 225
    private static let modeNameRadius: CGFloat = 248
    /// Major (outer), minor (middle), diminished (inner) — same order as `column.cells`.
    private static let ringRadii: [CGFloat] = [110, 160, 205]
    /// Only the minor/diminished and hub/major boundaries are ever drawn as grid circles
    /// (`renderWheel` only draws `[1]`/`[2]`) — `[0]` exists solely for the diatonic outline.
    private static let ringBoundaries: [CGFloat] = [90, 135, 182.5]
    private static let cellSize: CGFloat = 18

    private static let instrumentColors: [Color] = [
        Color(hex: "#e91e63"), Color(hex: "#00c853"), Color(hex: "#ff6f00"), Color(hex: "#00b8d4"),
        Color(hex: "#aa00ff"), Color(hex: "#ffd600"), Color(hex: "#795548"),
    ]
    /// Mirrors the physical wheel's own mixed sharp/flat convention (`NOTE_NAMES` in
    /// `StaticAssets.swift`) — NOT `MusicTheoryKit.PitchClass.name(preferFlats:)`, which uses
    /// an all-sharps or all-flats table instead of this wheel-specific mix.
    private static let noteNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]
    private static let chordSuffix: [String: String] = ["major": "", "minor": "m", "diminished": "\u{B0}"]

    public var body: some View {
        Canvas { context, size in
            draw(in: context, size: size)
        }
        .aspectRatio(1, contentMode: .fit)
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let unit = min(size.width, size.height) / Self.viewBoxSize
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let count = wheel.columns.count
        guard count > 0 else { return }

        var trackColorByLabel: [String: Color] = [:]
        for (index, track) in tracks.enumerated() {
            trackColorByLabel[track.label] = Self.instrumentColors[index % Self.instrumentColors.count]
        }

        func point(radius: CGFloat, index: Int, count: Int, offset: Double = 0) -> CGPoint {
            let angle = (2 * .pi * (Double(index) + offset)) / Double(count) - .pi / 2
            return CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
        }

        // Disk (the physical wheel's card stock) + ring/radial grid lines — always plain
        // white/black regardless of light/dark mode, matching the web's fixed-appearance page.
        let diskRect = CGRect(
            x: center.x - Self.diskRadius * unit, y: center.y - Self.diskRadius * unit,
            width: Self.diskRadius * unit * 2, height: Self.diskRadius * unit * 2
        )
        context.fill(Path(ellipseIn: diskRect), with: .color(.white))
        for boundary in [Self.ringBoundaries[1], Self.ringBoundaries[2]] {
            let r = boundary * unit
            let rect = CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(.black), lineWidth: 1)
        }
        for index in 0..<count {
            let inner = point(radius: Self.hubRadius * unit, index: index, count: count, offset: 0.5)
            let outer = point(radius: Self.gridOuterRadius * unit, index: index, count: count, offset: 0.5)
            var line = Path()
            line.move(to: inner)
            line.addLine(to: outer)
            context.stroke(line, with: .color(.black), lineWidth: 1)
        }

        // Mode-name ring — tangent-rotated labels, the current mode's own name highlighted.
        let modeNameFontSize = max(9, unit * 22)
        for (index, column) in wheel.columns.enumerated() {
            guard let modeName = column.modeName else { continue }
            let pos = point(radius: Self.modeNameRadius * unit, index: index, count: count)
            let isActive = modeName == wheel.activeModeName
            let rotationDegrees = Self.circularLabelRotation(index: index, count: count)
            context.drawLayer { layer in
                layer.translateBy(x: pos.x, y: pos.y)
                layer.rotate(by: .degrees(rotationDegrees))
                let text = Text(modeName)
                    .font(.system(size: modeNameFontSize, weight: isActive ? .bold : .regular))
                    .foregroundStyle(isActive ? Color(hex: "#b36b00") : Color(hex: "#555555"))
                layer.draw(text, at: .zero, anchor: .center)
            }
        }

        // Cells: shape (square/circle) in the note's palette color, chord symbol + relative
        // degree in the palette's own legible text color, occupied-track outline rings.
        let symbolFontSize = max(8, unit * 18)
        let degreeFontSize = max(6, unit * 14)
        for (index, column) in wheel.columns.enumerated() {
            for (ringIndex, cell) in column.cells.enumerated() {
                guard ringIndex < Self.ringRadii.count else { continue }
                let pos = point(radius: Self.ringRadii[ringIndex] * unit, index: index, count: count)
                let color = Self.color(atIndex: cell.pitchClass, in: palette, fallback: .accentColor)
                let textColor = Self.color(atIndex: cell.pitchClass, in: paletteTextColors, fallback: .primary)
                let half = Self.cellSize * unit
                let rotationDegrees = Double(index) * 360.0 / Double(count)

                let shapePath: Path = cell.shape == "square"
                    ? Self.rotatedSquare(center: pos, half: half, degrees: rotationDegrees)
                    : Path(ellipseIn: CGRect(x: pos.x - half, y: pos.y - half, width: half * 2, height: half * 2))
                context.fill(shapePath, with: .color(color))
                context.stroke(shapePath, with: .color(Color(hex: "#333333")), lineWidth: 1)

                let symbol = Self.noteNames[cell.pitchClass] + (Self.chordSuffix[cell.quality] ?? "")
                context.draw(
                    Text(symbol).font(.system(size: symbolFontSize, weight: .bold)).foregroundStyle(textColor),
                    at: CGPoint(x: pos.x, y: pos.y - degreeFontSize * 0.55)
                )
                context.draw(
                    Text(cell.relativeDegree).font(.system(size: degreeFontSize, design: .serif)).foregroundStyle(textColor.opacity(0.75)),
                    at: CGPoint(x: pos.x, y: pos.y + symbolFontSize * 0.55)
                )

                // One extra unfilled outline per occupying track, nested outward in that
                // track's own accent color — which instrument(s) sound this exact chord.
                for (labelIndex, label) in cell.trackLabels.enumerated() {
                    let outlineHalf = half + (6 + CGFloat(labelIndex) * 6) * unit
                    let outlineColor = trackColorByLabel[label] ?? Color(hex: "#2979ff")
                    let outlinePath: Path = cell.shape == "square"
                        ? Self.rotatedSquare(center: pos, half: outlineHalf, degrees: rotationDegrees)
                        : Path(ellipseIn: CGRect(x: pos.x - outlineHalf, y: pos.y - outlineHalf, width: outlineHalf * 2, height: outlineHalf * 2))
                    context.stroke(outlinePath, with: .color(outlineColor), lineWidth: 3)
                }
            }
        }

        // The 7-chord diatonic zone's outer contour, drawn last so it reads clearly on top.
        let boundary = Self.diatonicBoundaryPath(wheel: wheel, center: center, unit: unit)
        context.stroke(boundary, with: .color(Color(hex: "#1a3a6b")), style: StrokeStyle(lineWidth: 5, lineJoin: .round))
    }

    /// Degrees to rotate a mode-name label around its own point so its baseline runs tangent
    /// to the wheel — mirrors `circularLabelRotation` in `StaticAssets.swift`.
    private static func circularLabelRotation(index: Int, count: Int) -> Double {
        let deg = (360.0 * Double(index)) / Double(count)
        return deg > 90 && deg < 270 ? deg + 180 : deg
    }

    private static func rotatedSquare(center: CGPoint, half: CGFloat, degrees: Double) -> Path {
        let radians = degrees * .pi / 180
        let cosA = CGFloat(cos(radians)), sinA = CGFloat(sin(radians))
        let corners: [CGPoint] = [(-1.0, -1.0), (1.0, -1.0), (1.0, 1.0), (-1.0, 1.0)].map { dx, dy in
            let x = CGFloat(dx) * half, y = CGFloat(dy) * half
            return CGPoint(x: center.x + x * cosA - y * sinA, y: center.y + x * sinA + y * cosA)
        }
        var path = Path()
        path.move(to: corners[0])
        for corner in corners.dropFirst() { path.addLine(to: corner) }
        path.closeSubpath()
        return path
    }

    /// Mirrors `diatonicBoundaryPath` in `StaticAssets.swift`: the 7 diatonic cells of
    /// `wheel.tonic` always occupy exactly 3 adjacent columns (the tonic column itself, all 3
    /// rings diatonic, plus its two fifths-neighbors, only major+minor diatonic) — a fixed
    /// "crown" shape traced as its outer contour only, each arc sampled as short line segments.
    private static func diatonicBoundaryPath(wheel: WebConsoleWheelState, center: CGPoint, unit: CGFloat) -> Path {
        let count = wheel.columns.count
        let tonicIndex = wheel.activeColumnIndex
        func boundaryAngle(_ index: Int) -> Double {
            (2 * .pi * (Double(index) + 0.5)) / Double(count) - .pi / 2
        }
        let angleLeft = boundaryAngle(tonicIndex - 2)
        let angleIV = boundaryAngle(tonicIndex - 1)
        let angleV = boundaryAngle(tonicIndex)
        let angleRight = boundaryAngle(tonicIndex + 1)
        let rInner = ringBoundaries[0] * unit
        let rMid = ringBoundaries[2] * unit
        let rOuter = gridOuterRadius * unit

        func at(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + radius * CGFloat(cos(angle)), y: center.y + radius * CGFloat(sin(angle)))
        }
        func arcPoints(radius: CGFloat, from: Double, to: Double) -> [CGPoint] {
            let span = to - from
            let steps = max(1, Int(ceil(abs(span) * 180 / .pi / 3))) // ~3deg/segment
            return (1...steps).map { step in
                at(radius, from + span * Double(step) / Double(steps))
            }
        }

        var points: [CGPoint] = [at(rInner, angleLeft), at(rMid, angleLeft)]
        points.append(contentsOf: arcPoints(radius: rMid, from: angleLeft, to: angleIV))
        points.append(at(rOuter, angleIV))
        points.append(contentsOf: arcPoints(radius: rOuter, from: angleIV, to: angleV))
        points.append(at(rMid, angleV))
        points.append(contentsOf: arcPoints(radius: rMid, from: angleV, to: angleRight))
        points.append(at(rInner, angleRight))
        points.append(contentsOf: arcPoints(radius: rInner, from: angleRight, to: angleLeft))

        var path = Path()
        path.move(to: points[0])
        for point in points.dropFirst() { path.addLine(to: point) }
        path.closeSubpath()
        return path
    }

    private static func color(atIndex index: Int, in hexes: [String], fallback: Color) -> Color {
        guard hexes.indices.contains(index) else { return fallback }
        return Color(hex: hexes[index])
    }
}

extension Color {
    /// Parses "#RRGGBB" (the only shape `ColorPalette`/`WebConsoleState.palette` ever produce)
    /// — falls back to opaque black for anything else rather than crashing on a malformed value.
    fileprivate init(hex: String) {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else {
            self = .black
            return
        }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        self = Color(red: r, green: g, blue: b)
    }
}

// No public initializer exists for WebConsoleWheelState/Column/Cell (deliberately — they're
// read-only outside AppCore, built only by ImprovSession.buildWebConsoleState()), so the
// preview goes through a real session rather than constructing fake wire data by hand.
#Preview {
    let session = ImprovSession()
    let state = session.buildWebConsoleState()
    return CircleOfFifthsWheelView(wheel: state.wheel, palette: state.palette, paletteTextColors: state.paletteTextColors, tracks: state.tracks)
        .padding()
}
