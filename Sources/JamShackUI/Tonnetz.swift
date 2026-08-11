import SwiftUI
import AppCore
import MusicTheoryKit
import RecognitionEngine
import Localization

/// Pure screen-space geometry for the Tonnetz lattice — shared by `PitchClassTonnetzView` and
/// `RegisteredTonnetzView` so both draw the exact same triangular tiling shape, just fed
/// different `TonnetzCoordinate` lists (a fixed 12-cell tile vs. a locally-windowed range) and
/// different pitch resolvers (pitch class vs. absolute MIDI).
enum TonnetzGeometry {
    /// Equilateral-triangle position for `coordinate`: fifths run horizontal, major thirds along
    /// a 60° diagonal — matches every standard Tonnetz diagram.
    static func point(for coordinate: TonnetzCoordinate, edgeLength: CGFloat) -> CGPoint {
        let x = (CGFloat(coordinate.q) + CGFloat(coordinate.r) / 2) * edgeLength
        let y = -CGFloat(coordinate.r) * edgeLength * (CGFloat(3).squareRoot() / 2)
        return CGPoint(x: x, y: y)
    }

    /// The coordinate closest to `near` (in a small bounded neighborhood) whose
    /// `Tonnetz.midiPitch(at:)` is nearest `target` — the Registered Tonnetz's own "recenter"
    /// primitive. Brute-force, not a closed-form inverse: this view only ever needs a LOCAL
    /// window anchor, never a globally-canonical one (see `Tonnetz.midiPitch`'s own doc comment
    /// on why the map isn't invertible in general).
    static func nearestCoordinate(toMidiPitch target: Int, near: TonnetzCoordinate) -> TonnetzCoordinate {
        var best = near
        var bestDistance = abs(Tonnetz.midiPitch(at: near) - target)
        for dq in -6...6 {
            for dr in -6...6 {
                let candidate = TonnetzCoordinate(q: near.q + dq, r: near.r + dr)
                let distance = abs(Tonnetz.midiPitch(at: candidate) - target)
                if distance < bestDistance {
                    best = candidate
                    bestDistance = distance
                }
            }
        }
        return best
    }
}

extension Color {
    /// A lightened ("pastel") version of a `Color(hex:)`-style hex string, mixed toward white by
    /// `fraction` (0 = unchanged, 1 = white) — computed directly from the hex components (not by
    /// resolving a `Color` back to RGB, which needs an environment context), so it works
    /// anywhere `Color(hex:)` already does, including inside a `Canvas` draw closure.
    static func pastel(hex: String, fraction: Double = 0.55) -> Color {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return .white }
        let r = Double((value >> 16) & 0xFF) / 255
        let g = Double((value >> 8) & 0xFF) / 255
        let b = Double(value & 0xFF) / 255
        return Color(red: r + (1 - r) * fraction, green: g + (1 - g) * fraction, blue: b + (1 - b) * fraction)
    }
}

/// What's currently selected/played on either Tonnetz view — a single note, a lattice-adjacent
/// dyad (an edge), or a full triad. Unifies the 3 tappable primitives into one selection/audition
/// model so `TonnetzScreen` has a single `play(_:)` instead of 3 near-duplicate ones.
///
/// `.note`/`.edge` carry an OPTIONAL real absolute pitch alongside the abstract pitch-class
/// identity: `PitchClassTonnetzView` only ever knows a pitch class (register-independent by
/// design), so it leaves the real-pitch field `nil`; `RegisteredTonnetzView` always knows the
/// exact key that was tapped, so it fills it in — without this, a Performance-mode tap on, say,
/// G4 would collapse to the bare pitch class G and forget which octave was actually meant.
public enum TonnetzSelection: Equatable {
    case note(PitchClass, realPitch: Int?)
    case edge(TonnetzEdge, realPitches: [Int]?)
    case triad(TonnetzTriad)
}

public extension TonnetzSelection {
    var root: PitchClass {
        switch self {
        case .note(let pitchClass, _): return pitchClass
        case .edge(let edge, _): return edge.root
        case .triad(let triad): return triad.root
        }
    }

    /// The plain major/minor `Chord` this selection represents — only ever non-`nil` for
    /// `.triad` (a single note or a dyad isn't a chord in `ChordVocabulary`'s own sense).
    var chord: Chord? {
        guard case .triad(let triad) = self else { return nil }
        return ChordVocabulary.byID(triad.quality == .major ? "Ma" : "mi").map { Chord(root: triad.root, template: $0) }
    }
}

/// `(root, quality)` as a lookup key — used to test "is this rendered triangle the current
/// selection, or one of its P/L/R neighbors" without caring which specific lattice coordinate it
/// renders at (the same neighbor can legitimately appear at more than one coordinate in a
/// periodic tile).
private struct TonnetzTriadKey: Hashable {
    let root: PitchClass
    let quality: TonnetzTriadQuality
}

private extension TonnetzTriad {
    var key: TonnetzTriadKey { TonnetzTriadKey(root: root, quality: quality) }
}

private func pointInTriangle(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint, _ c: CGPoint) -> Bool {
    func sign(_ p1: CGPoint, _ p2: CGPoint, _ p3: CGPoint) -> CGFloat {
        (p1.x - p3.x) * (p2.y - p3.y) - (p2.x - p3.x) * (p1.y - p3.y)
    }
    let d1 = sign(point, a, b), d2 = sign(point, b, c), d3 = sign(point, c, a)
    let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
    let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)
    return !(hasNeg && hasPos)
}

private func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat {
    hypot(a.x - b.x, a.y - b.y)
}

private func distanceToSegment(_ point: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let abx = b.x - a.x, aby = b.y - a.y
    let apx = point.x - a.x, apy = point.y - a.y
    let lengthSquared = abx * abx + aby * aby
    guard lengthSquared > 0 else { return distance(point, a) }
    let t = max(0, min(1, (apx * abx + apy * aby) / lengthSquared))
    let projection = CGPoint(x: a.x + t * abx, y: a.y + t * aby)
    return distance(point, projection)
}

private func trianglePath(_ vertices: [CGPoint]) -> Path {
    var path = Path()
    guard vertices.count == 3 else { return path }
    path.move(to: vertices[0])
    path.addLine(to: vertices[1])
    path.addLine(to: vertices[2])
    path.closeSubpath()
    return path
}

/// Fill/stroke for one rendered triangle, shared by both views. `colorByIdentity` (per explicit
/// request) aligns a triad's fill with the SAME per-pitch-class palette the circle-of-fifths
/// wheel already uses (a pastel tint of the root's own color) instead of a generic
/// selection-only accent; the non-identity mode keeps the original generic scheme as a fallback.
/// Diminished/augmented triads never reach this function in Phase 1 — the Tonnetz has no
/// triangle for them at all (no perfect fifth to anchor one), so the question of how to color
/// them doesn't arise yet (see the plan's Phase 2 backlog).
@MainActor
private func triangleAppearance(root: PitchClass, isSelected: Bool, isNeighbor: Bool, colorByIdentity: Bool, palette: [String]) -> (fill: Color, stroke: Color, lineWidth: CGFloat, dash: [CGFloat]) {
    let hex = palette.indices.contains(root.value) ? palette[root.value] : PitchKeyboardView.defaultPalette[root.value]
    if colorByIdentity {
        let base = Color.pastel(hex: hex, fraction: 0.55)
        if isSelected { return (base, .accentColor, 3, []) }
        if isNeighbor { return (base.opacity(0.85), .orange, 2, [4, 3]) }
        return (base.opacity(0.4), Color.secondary.opacity(0.3), 1, [])
    }
    if isSelected { return (Color.accentColor.opacity(0.4), .accentColor, 3, []) }
    if isNeighbor { return (Color.orange.opacity(0.2), .orange, 2, [4, 3]) }
    return (Color.secondary.opacity(0.05), Color.secondary.opacity(0.35), 1, [])
}

/// Fill/text/stroke for one rendered node. `colorByIdentity` colors a note by its OWN
/// pitch-class identity (full saturation — the same 12-color palette the triangles use pastel
/// tints of), reserving the stroke ring for "is this actually held" instead of changing the fill
/// hue; the non-identity mode keeps the original role-based `PitchDisplayState` coloring
/// (root/tone/held/mode, via `colorScheme`).
@MainActor
private func nodeAppearance(paletteIndex: Int, role: PitchDisplayRole, colorByIdentity: Bool, palette: [String], paletteTextColors: [String], colorScheme: PitchKeyboardColorScheme) -> (fill: Color, textColor: Color, strokeColor: Color, strokeWidth: CGFloat) {
    let isHeld: Bool
    switch role {
    case .chordRoot, .chordTone, .heldOutsideChord, .held: isHeld = true
    default: isHeld = false
    }
    if colorByIdentity {
        let hex = palette.indices.contains(paletteIndex) ? palette[paletteIndex] : PitchKeyboardView.defaultPalette[paletteIndex]
        let textHex = paletteTextColors.indices.contains(paletteIndex) ? paletteTextColors[paletteIndex] : PitchKeyboardView.defaultPaletteTextColors[paletteIndex]
        return (Color(hex: hex), Color(hex: textHex), isHeld ? .white : .black.opacity(0.35), isHeld ? 3 : 1)
    }
    let fill = colorScheme.fillColor(for: role, isWhiteKey: true)
    let isLight = fill == colorScheme.whiteKey || role == .chordTone || role == .modeTone
    return (fill, isLight ? .black : .white, .black.opacity(0.35), 1)
}

/// Phase 1's simple voice-leading heuristic: a handful of candidate inversions/octaves for
/// `chord`, scored by total semitone movement from `previousPitches` (paired position-by-
/// position after sorting both), cheapest wins. Deliberately NOT the weighted-penalty optimizer
/// from the full Tonnetz spec (voice crossing / out-of-scale / register penalties) — that's
/// backlogged for Phase 2.
public enum TonnetzVoicing {
    public static func nearestVoicing(forChord chord: Chord, previousPitches: [Int]) -> [Int] {
        let anchor = previousPitches.isEmpty ? 60 : previousPitches.reduce(0, +) / previousPitches.count
        let toneCount = max(chord.pitchClasses.count, 1)
        var best: (pitches: [Int], cost: Int)?
        for inversion in 0..<toneCount {
            let voicing = chord.voicing(inversion: inversion)
            for floor in (anchor - 24)...(anchor + 12) {
                let candidate = PitchSequencing.ascendingPitches(forPitchClasses: voicing.orderedPitchClasses.map(\.value), startingAbove: floor)
                guard candidate.allSatisfy({ (21...108).contains($0) }) else { continue }
                let cost: Int
                if previousPitches.count == candidate.count, !previousPitches.isEmpty {
                    let sortedPrevious = previousPitches.sorted()
                    let sortedCandidate = candidate.sorted()
                    cost = zip(sortedPrevious, sortedCandidate).reduce(0) { $0 + abs($1.0 - $1.1) }
                } else {
                    cost = candidate.reduce(0) { $0 + abs($1 - anchor) }
                }
                if best == nil || cost < best!.cost { best = (candidate, cost) }
            }
        }
        return best?.pitches ?? PitchSequencing.ascendingPitches(forPitchClasses: chord.pitchClasses.map(\.value), startingAbove: 47)
    }

    /// Where to place a 2nd note a fixed interval away from `anchor`, taking whichever direction
    /// (up or down) is the shorter interval — the dyad counterpart to `nearestVoicing`, used when
    /// an edge is played without a concrete registered position of its own (a Harmonic-mode tap).
    public static func nearestOtherPitch(anchor: Int, otherPitchClass: PitchClass) -> Int {
        let anchorPitchClass = ((anchor % 12) + 12) % 12
        let forward = ((otherPitchClass.value - anchorPitchClass) % 12 + 12) % 12
        let delta = forward <= 6 ? forward : forward - 12
        return anchor + delta
    }
}

/// The "Pitch Class Tonnetz" (mode Harmonique) — the 12-pitch-class lattice, chromatic and
/// register-independent. Tapping a node/edge/triangle selects AND plays a note/dyad/triad (fused
/// the same way every other Théorie screen's tap-to-select already fuses selection with
/// audition). The current selection's P/L/R neighbors (triads only) are outlined directly on the
/// grid (dashed amber) rather than offered as separate buttons — they're already visible,
/// adjacent triangles.
public struct PitchClassTonnetzView: View {
    public let heldPitchClasses: Set<PitchClass>
    public let selection: TonnetzSelection?
    public let colorByIdentity: Bool
    public let palette: [String]
    public let paletteTextColors: [String]
    public let colorScheme: PitchKeyboardColorScheme
    public let notationStyle: any NotationStyle
    public let onSelect: (TonnetzSelection) -> Void

    public init(
        heldPitchClasses: Set<PitchClass>,
        selection: TonnetzSelection?,
        colorByIdentity: Bool,
        palette: [String] = PitchKeyboardView.defaultPalette,
        paletteTextColors: [String] = PitchKeyboardView.defaultPaletteTextColors,
        colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        notationStyle: any NotationStyle,
        onSelect: @escaping (TonnetzSelection) -> Void
    ) {
        self.heldPitchClasses = heldPitchClasses
        self.selection = selection
        self.colorByIdentity = colorByIdentity
        self.palette = palette
        self.paletteTextColors = paletteTextColors
        self.colorScheme = colorScheme
        self.notationStyle = notationStyle
        self.onSelect = onSelect
    }

    private static let edgeLength: CGFloat = 60
    private static let nodeRadius: CGFloat = 22
    private static let edgeHitDistance: CGFloat = 12

    public var body: some View {
        GeometryReader { proxy in
            let layout = layoutInfo(for: proxy.size)
            Canvas { context, _ in draw(in: context, layout: layout) }
                .contentShape(Rectangle())
                .onTapGesture { location in handleTap(at: location, layout: layout) }
        }
        .aspectRatio(1.3, contentMode: .fit)
    }

    // MARK: - Layout

    private struct LayoutNode {
        let pitchClass: PitchClass
        let point: CGPoint
        let isPrimary: Bool
    }

    private struct LayoutEdge {
        let kind: TonnetzEdgeKind
        let root: PitchClass
        let other: PitchClass
        let a: CGPoint
        let b: CGPoint
    }

    private struct LayoutTriangle {
        let anchor: TonnetzCoordinate
        let quality: TonnetzTriadQuality
        let root: PitchClass
        let vertices: [CGPoint]
    }

    private struct LayoutInfo {
        let nodes: [LayoutNode]
        let edges: [LayoutEdge]
        let triangles: [LayoutTriangle]
    }

    private func layoutInfo(for size: CGSize) -> LayoutInfo {
        let tile = Tonnetz.paddedTile()
        let entries: [(TonnetzCoordinate, Bool)] = tile.primary.map { ($0, true) } + tile.halo.map { ($0, false) }
        let rawPoints = entries.map { TonnetzGeometry.point(for: $0.0, edgeLength: Self.edgeLength) }
        guard let minX = rawPoints.map(\.x).min(), let maxX = rawPoints.map(\.x).max(),
              let minY = rawPoints.map(\.y).min(), let maxY = rawPoints.map(\.y).max() else {
            return LayoutInfo(nodes: [], edges: [], triangles: [])
        }
        let offset = CGPoint(x: size.width / 2 - (minX + maxX) / 2, y: size.height / 2 - (minY + maxY) / 2)

        var pointsByCoordinate: [TonnetzCoordinate: CGPoint] = [:]
        var nodes: [LayoutNode] = []
        for (index, entry) in entries.enumerated() {
            let point = CGPoint(x: rawPoints[index].x + offset.x, y: rawPoints[index].y + offset.y)
            pointsByCoordinate[entry.0] = point
            nodes.append(LayoutNode(pitchClass: Tonnetz.pitchClass(at: entry.0), point: point, isPrimary: entry.1))
        }

        let allCoordinates = Set(entries.map(\.0))
        var edges: [LayoutEdge] = []
        for coordinate in allCoordinates {
            for kind in [TonnetzEdgeKind.fifth, .majorThird, .minorThird] {
                let otherCoordinate = Self.otherCoordinate(from: coordinate, kind: kind)
                guard allCoordinates.contains(otherCoordinate), let a = pointsByCoordinate[coordinate], let b = pointsByCoordinate[otherCoordinate] else { continue }
                let edge = Tonnetz.edge(kind: kind, anchoredAt: coordinate)
                edges.append(LayoutEdge(kind: kind, root: edge.root, other: edge.other, a: a, b: b))
            }
        }

        var triangles: [LayoutTriangle] = []
        for coordinate in allCoordinates {
            for quality in [TonnetzTriadQuality.major, .minor] {
                let vertexCoordinates = Tonnetz.nodes(ofQuality: quality, anchoredAt: coordinate)
                guard vertexCoordinates.allSatisfy({ allCoordinates.contains($0) }) else { continue }
                let vertices = vertexCoordinates.compactMap { pointsByCoordinate[$0] }
                guard vertices.count == 3 else { continue }
                triangles.append(LayoutTriangle(anchor: coordinate, quality: quality, root: Tonnetz.pitchClass(at: coordinate), vertices: vertices))
            }
        }
        return LayoutInfo(nodes: nodes, edges: edges, triangles: triangles)
    }

    private static func otherCoordinate(from coordinate: TonnetzCoordinate, kind: TonnetzEdgeKind) -> TonnetzCoordinate {
        switch kind {
        case .fifth: return TonnetzCoordinate(q: coordinate.q + 1, r: coordinate.r)
        case .majorThird: return TonnetzCoordinate(q: coordinate.q, r: coordinate.r + 1)
        case .minorThird: return TonnetzCoordinate(q: coordinate.q + 1, r: coordinate.r - 1)
        }
    }

    private func plrNeighborKeys() -> Set<TonnetzTriadKey> {
        guard case .triad(let triad) = selection else { return [] }
        let neighbors = [Tonnetz.parallel(of: triad), Tonnetz.relative(of: triad), Tonnetz.leadingToneExchange(of: triad)]
        return Set(neighbors.map(\.key))
    }

    private func handleTap(at location: CGPoint, layout: LayoutInfo) {
        if let nearestNode = layout.nodes.min(by: { distance($0.point, location) < distance($1.point, location) }),
           distance(nearestNode.point, location) <= Self.nodeRadius {
            onSelect(.note(nearestNode.pitchClass, realPitch: nil))
            return
        }
        if let nearestEdge = layout.edges.min(by: { distanceToSegment(location, $0.a, $0.b) < distanceToSegment(location, $1.a, $1.b) }),
           distanceToSegment(location, nearestEdge.a, nearestEdge.b) <= Self.edgeHitDistance {
            onSelect(.edge(TonnetzEdge(coordinate: TonnetzCoordinate(q: 0, r: 0), kind: nearestEdge.kind, root: nearestEdge.root, other: nearestEdge.other), realPitches: nil))
            return
        }
        if let triangle = layout.triangles.first(where: { pointInTriangle(location, $0.vertices[0], $0.vertices[1], $0.vertices[2]) }) {
            onSelect(.triad(TonnetzTriad(coordinate: triangle.anchor, quality: triangle.quality, root: triangle.root)))
        }
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, layout: LayoutInfo) {
        let neighborKeys = plrNeighborKeys()
        let selectedEdgePitchClasses: Set<PitchClass>? = {
            guard case .edge(let edge, _) = selection else { return nil }
            return [edge.root, edge.other]
        }()

        for edge in layout.edges {
            let isSelected = selectedEdgePitchClasses == Set([edge.root, edge.other])
            var path = Path()
            path.move(to: edge.a)
            path.addLine(to: edge.b)
            context.stroke(path, with: .color(isSelected ? .accentColor : Color.secondary.opacity(0.25)), lineWidth: isSelected ? 4 : 1)
        }

        for triangle in layout.triangles {
            let key = TonnetzTriadKey(root: triangle.root, quality: triangle.quality)
            let isSelected: Bool = {
                if case .triad(let triad) = selection { return triad.key == key }
                return false
            }()
            let isNeighbor = !isSelected && neighborKeys.contains(key)
            let appearance = triangleAppearance(root: triangle.root, isSelected: isSelected, isNeighbor: isNeighbor, colorByIdentity: colorByIdentity, palette: palette)
            let path = trianglePath(triangle.vertices)
            context.fill(path, with: .color(appearance.fill))
            if appearance.dash.isEmpty {
                context.stroke(path, with: .color(appearance.stroke), lineWidth: appearance.lineWidth)
            } else {
                context.stroke(path, with: .color(appearance.stroke), style: StrokeStyle(lineWidth: appearance.lineWidth, dash: appearance.dash))
            }
        }

        let chordTones = selection?.chord?.pitchClasses.map(\.value) ?? []
        let chordRoot = selection?.chord != nil ? selection?.root.value : nil
        let heldAtSyntheticOctave = Set(heldPitchClasses.map { 60 + $0.value })
        for node in layout.nodes {
            let state = pitchDisplayState(
                pitch: 60 + node.pitchClass.value,
                heldPitches: heldAtSyntheticOctave,
                chordRoot: chordRoot,
                chordTones: chordTones,
                modeTones: [],
                alwaysShowChord: true
            )
            let appearance = nodeAppearance(paletteIndex: node.pitchClass.value, role: state.role, colorByIdentity: colorByIdentity, palette: palette, paletteTextColors: paletteTextColors, colorScheme: colorScheme)
            context.drawLayer { layer in
                layer.opacity = node.isPrimary ? 1 : 0.55
                let rect = CGRect(x: node.point.x - Self.nodeRadius, y: node.point.y - Self.nodeRadius, width: Self.nodeRadius * 2, height: Self.nodeRadius * 2)
                let circle = Path(ellipseIn: rect)
                layer.fill(circle, with: .color(appearance.fill))
                layer.stroke(circle, with: .color(appearance.strokeColor), lineWidth: appearance.strokeWidth)
                layer.draw(
                    Text(notationStyle.rootName(node.pitchClass, preferFlats: false)).font(.system(size: 13, weight: .semibold)).foregroundStyle(appearance.textColor),
                    at: node.point
                )
            }
        }
    }
}

/// The "Registered Tonnetz" (mode Performance) — real, absolute-MIDI notes, windowed locally
/// around whatever's currently held. The window only re-anchors once the held notes get close to
/// its own edge (per explicit request — a small window that recenters on every note read as
/// constant, hard-to-follow jumping); it never snaps away during silence.
public struct RegisteredTonnetzView: View {
    public let heldPitches: Set<Int>
    public let selection: TonnetzSelection?
    public let colorByIdentity: Bool
    public let palette: [String]
    public let paletteTextColors: [String]
    public let colorScheme: PitchKeyboardColorScheme
    public let notationStyle: any NotationStyle
    public let onSelect: (TonnetzSelection) -> Void

    public init(
        heldPitches: Set<Int>,
        selection: TonnetzSelection?,
        colorByIdentity: Bool,
        palette: [String] = PitchKeyboardView.defaultPalette,
        paletteTextColors: [String] = PitchKeyboardView.defaultPaletteTextColors,
        colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        notationStyle: any NotationStyle,
        onSelect: @escaping (TonnetzSelection) -> Void
    ) {
        self.heldPitches = heldPitches
        self.selection = selection
        self.colorByIdentity = colorByIdentity
        self.palette = palette
        self.paletteTextColors = paletteTextColors
        self.colorScheme = colorScheme
        self.notationStyle = notationStyle
        self.onSelect = onSelect
    }

    @State private var windowCenter = TonnetzCoordinate(q: 0, r: 0)

    private static let edgeLength: CGFloat = 52
    private static let nodeRadius: CGFloat = 19
    private static let edgeHitDistance: CGFloat = 10
    /// Wider than the harmonic tile's own fixed 12-cell footprint — per explicit request, a
    /// bigger window so playing near the middle of the keyboard rarely nears its edge. Widened
    /// more along `q` (fifths, 7 semitones/step) than `r` (thirds, 3-4 semitones/step): covering
    /// the same real pitch range takes fewer fifth-steps than third-steps, so a wider `q` span
    /// buys more actual keyboard coverage per extra rendered column.
    private static let qSpan = 6
    private static let rSpan = 4
    /// Only recenter once the held notes' resolved coordinate is within this many steps of the
    /// window's own edge — the "don't jump on every note near the middle" ask.
    private static let recenterMargin = 1
    private static let midiRange = 21...108

    public var body: some View {
        GeometryReader { proxy in
            let layout = layoutInfo(for: proxy.size)
            Canvas { context, _ in draw(in: context, layout: layout) }
                .contentShape(Rectangle())
                .onTapGesture { location in handleTap(at: location, layout: layout) }
        }
        .aspectRatio(1.6, contentMode: .fit)
        .task(id: heldPitches) {
            guard !heldPitches.isEmpty else { return }
            let target = heldPitches.reduce(0, +) / heldPitches.count
            let candidate = TonnetzGeometry.nearestCoordinate(toMidiPitch: target, near: windowCenter)
            let dq = abs(candidate.q - windowCenter.q)
            let dr = abs(candidate.r - windowCenter.r)
            if dq >= Self.qSpan - Self.recenterMargin || dr >= Self.rSpan - Self.recenterMargin {
                windowCenter = candidate
            }
        }
    }

    // MARK: - Layout

    private struct LayoutNode {
        let midiPitch: Int
        let point: CGPoint
    }

    private struct LayoutEdge {
        let kind: TonnetzEdgeKind
        let rootPitch: Int
        let otherPitch: Int
        let a: CGPoint
        let b: CGPoint
    }

    private struct LayoutTriangle {
        let anchor: TonnetzCoordinate
        let quality: TonnetzTriadQuality
        let root: PitchClass
        let vertices: [CGPoint]
    }

    private struct LayoutInfo {
        let nodes: [LayoutNode]
        let edges: [LayoutEdge]
        let triangles: [LayoutTriangle]
    }

    private static func otherCoordinate(from coordinate: TonnetzCoordinate, kind: TonnetzEdgeKind) -> TonnetzCoordinate {
        switch kind {
        case .fifth: return TonnetzCoordinate(q: coordinate.q + 1, r: coordinate.r)
        case .majorThird: return TonnetzCoordinate(q: coordinate.q, r: coordinate.r + 1)
        case .minorThird: return TonnetzCoordinate(q: coordinate.q + 1, r: coordinate.r - 1)
        }
    }

    private func layoutInfo(for size: CGSize) -> LayoutInfo {
        var coordinates: [TonnetzCoordinate] = []
        for dq in -Self.qSpan...Self.qSpan {
            for dr in -Self.rSpan...Self.rSpan {
                coordinates.append(TonnetzCoordinate(q: windowCenter.q + dq, r: windowCenter.r + dr))
            }
        }
        let validCoordinates = coordinates.filter { Self.midiRange.contains(Tonnetz.midiPitch(at: $0)) }
        let rawPoints = validCoordinates.map { TonnetzGeometry.point(for: $0, edgeLength: Self.edgeLength) }
        guard let minX = rawPoints.map(\.x).min(), let maxX = rawPoints.map(\.x).max(),
              let minY = rawPoints.map(\.y).min(), let maxY = rawPoints.map(\.y).max() else {
            return LayoutInfo(nodes: [], edges: [], triangles: [])
        }
        let offset = CGPoint(x: size.width / 2 - (minX + maxX) / 2, y: size.height / 2 - (minY + maxY) / 2)

        var pointsByCoordinate: [TonnetzCoordinate: CGPoint] = [:]
        var nodes: [LayoutNode] = []
        for (index, coordinate) in validCoordinates.enumerated() {
            let point = CGPoint(x: rawPoints[index].x + offset.x, y: rawPoints[index].y + offset.y)
            pointsByCoordinate[coordinate] = point
            nodes.append(LayoutNode(midiPitch: Tonnetz.midiPitch(at: coordinate), point: point))
        }

        let validSet = Set(validCoordinates)
        var edges: [LayoutEdge] = []
        for coordinate in validCoordinates {
            for kind in [TonnetzEdgeKind.fifth, .majorThird, .minorThird] {
                let otherCoordinate = Self.otherCoordinate(from: coordinate, kind: kind)
                guard validSet.contains(otherCoordinate), let a = pointsByCoordinate[coordinate], let b = pointsByCoordinate[otherCoordinate] else { continue }
                edges.append(LayoutEdge(kind: kind, rootPitch: Tonnetz.midiPitch(at: coordinate), otherPitch: Tonnetz.midiPitch(at: otherCoordinate), a: a, b: b))
            }
        }

        var triangles: [LayoutTriangle] = []
        for coordinate in validCoordinates {
            for quality in [TonnetzTriadQuality.major, .minor] {
                let vertexCoordinates = Tonnetz.nodes(ofQuality: quality, anchoredAt: coordinate)
                guard vertexCoordinates.allSatisfy({ validSet.contains($0) }) else { continue }
                let vertices = vertexCoordinates.compactMap { pointsByCoordinate[$0] }
                guard vertices.count == 3 else { continue }
                triangles.append(LayoutTriangle(anchor: coordinate, quality: quality, root: Tonnetz.pitchClass(at: coordinate), vertices: vertices))
            }
        }
        return LayoutInfo(nodes: nodes, edges: edges, triangles: triangles)
    }

    private func handleTap(at location: CGPoint, layout: LayoutInfo) {
        if let nearestNode = layout.nodes.min(by: { distance($0.point, location) < distance($1.point, location) }),
           distance(nearestNode.point, location) <= Self.nodeRadius {
            onSelect(.note(PitchClass(nearestNode.midiPitch), realPitch: nearestNode.midiPitch))
            return
        }
        if let nearestEdge = layout.edges.min(by: { distanceToSegment(location, $0.a, $0.b) < distanceToSegment(location, $1.a, $1.b) }),
           distanceToSegment(location, nearestEdge.a, nearestEdge.b) <= Self.edgeHitDistance {
            let edge = TonnetzEdge(coordinate: TonnetzCoordinate(q: 0, r: 0), kind: nearestEdge.kind, root: PitchClass(nearestEdge.rootPitch), other: PitchClass(nearestEdge.otherPitch))
            onSelect(.edge(edge, realPitches: [nearestEdge.rootPitch, nearestEdge.otherPitch]))
            return
        }
        if let triangle = layout.triangles.first(where: { pointInTriangle(location, $0.vertices[0], $0.vertices[1], $0.vertices[2]) }) {
            onSelect(.triad(TonnetzTriad(coordinate: triangle.anchor, quality: triangle.quality, root: triangle.root)))
        }
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, layout: LayoutInfo) {
        let selectedRealPitches: Set<Int>? = {
            guard case .edge(_, let realPitches) = selection, let realPitches, realPitches.count == 2 else { return nil }
            return Set(realPitches)
        }()
        let selectedEdgePitchClasses: Set<PitchClass>? = {
            guard case .edge(let edge, let realPitches) = selection, realPitches == nil else { return nil }
            return [edge.root, edge.other]
        }()

        for edge in layout.edges {
            let isSelected: Bool
            if let selectedRealPitches {
                isSelected = selectedRealPitches == Set([edge.rootPitch, edge.otherPitch])
            } else if let selectedEdgePitchClasses {
                isSelected = selectedEdgePitchClasses == Set([PitchClass(edge.rootPitch), PitchClass(edge.otherPitch)])
            } else {
                isSelected = false
            }
            var path = Path()
            path.move(to: edge.a)
            path.addLine(to: edge.b)
            context.stroke(path, with: .color(isSelected ? .accentColor : Color.secondary.opacity(0.25)), lineWidth: isSelected ? 4 : 1)
        }

        for triangle in layout.triangles {
            let isSelected: Bool = {
                if case .triad(let triad) = selection { return triad.key == TonnetzTriadKey(root: triangle.root, quality: triangle.quality) }
                return false
            }()
            let appearance = triangleAppearance(root: triangle.root, isSelected: isSelected, isNeighbor: false, colorByIdentity: colorByIdentity, palette: palette)
            let path = trianglePath(triangle.vertices)
            context.fill(path, with: .color(appearance.fill))
            context.stroke(path, with: .color(appearance.stroke), lineWidth: appearance.lineWidth)
        }

        let chordTones = selection?.chord?.pitchClasses.map(\.value) ?? []
        let chordRoot = selection?.chord != nil ? selection?.root.value : nil
        for node in layout.nodes {
            let state = pitchDisplayState(
                pitch: node.midiPitch,
                heldPitches: heldPitches,
                chordRoot: chordRoot,
                chordTones: chordTones,
                modeTones: [],
                alwaysShowChord: true
            )
            let paletteIndex = ((node.midiPitch % 12) + 12) % 12
            let appearance = nodeAppearance(paletteIndex: paletteIndex, role: state.role, colorByIdentity: colorByIdentity, palette: palette, paletteTextColors: paletteTextColors, colorScheme: colorScheme)
            context.drawLayer { layer in
                let rect = CGRect(x: node.point.x - Self.nodeRadius, y: node.point.y - Self.nodeRadius, width: Self.nodeRadius * 2, height: Self.nodeRadius * 2)
                let circle = Path(ellipseIn: rect)
                layer.fill(circle, with: .color(appearance.fill))
                layer.stroke(circle, with: .color(appearance.strokeColor), lineWidth: appearance.strokeWidth)
                let octave = node.midiPitch / 12 - 1
                let label = "\(notationStyle.rootName(PitchClass(node.midiPitch), preferFlats: false))\(octave)"
                layer.draw(
                    Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(appearance.textColor),
                    at: node.point
                )
            }
        }
    }
}
