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

/// `(root, quality)` as a lookup key — used to test "is this rendered triangle one of the
/// current selection's P/L/R neighbors" without caring which specific lattice coordinate it
/// renders at (the same neighbor can legitimately appear at more than one coordinate in a
/// periodic tile).
private struct TonnetzKey: Hashable {
    let root: PitchClass
    let quality: TonnetzTriadQuality
}

private extension TonnetzTriad {
    var key: TonnetzKey { TonnetzKey(root: root, quality: quality) }

    /// The plain major/minor `Chord` this triad represents — `nil` only if `ChordVocabulary`
    /// somehow lost its built-in "Ma"/"mi" templates (never happens in practice).
    var chord: Chord? {
        ChordVocabulary.byID(quality == .major ? "Ma" : "mi").map { Chord(root: root, template: $0) }
    }
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

private func trianglePath(_ vertices: [CGPoint]) -> Path {
    var path = Path()
    guard vertices.count == 3 else { return path }
    path.move(to: vertices[0])
    path.addLine(to: vertices[1])
    path.addLine(to: vertices[2])
    path.closeSubpath()
    return path
}

/// Phase 1's simple voice-leading heuristic: a handful of candidate inversions/octaves for
/// `chord`, scored by total semitone movement from `previousPitches` (paired position-by-
/// position after sorting both), cheapest wins. Deliberately NOT the weighted-penalty optimizer
/// from the full Tonnetz spec (voice crossing / out-of-scale / register penalties) — that's
/// backlogged for Phase 2.
enum TonnetzVoicing {
    static func nearestVoicing(forChord chord: Chord, previousPitches: [Int]) -> [Int] {
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
}

/// The "Pitch Class Tonnetz" (mode Harmonique) — the 12-pitch-class lattice, chromatic and
/// register-independent. Tapping a node plays that pitch class (`onTapNote`); tapping a triangle
/// selects AND plays its triad (`onSelectTriad`, fused the same way every other Théorie screen's
/// tap-to-select already fuses selection with audition). The current selection's P/L/R neighbors
/// are outlined directly on the grid (dashed amber) rather than offered as separate buttons —
/// they're already visible, adjacent triangles.
public struct PitchClassTonnetzView: View {
    public let heldPitchClasses: Set<PitchClass>
    public let selectedTriad: TonnetzTriad?
    public let colorScheme: PitchKeyboardColorScheme
    public let notationStyle: any NotationStyle
    public let onTapNote: (PitchClass) -> Void
    public let onSelectTriad: (TonnetzTriad) -> Void

    public init(
        heldPitchClasses: Set<PitchClass>,
        selectedTriad: TonnetzTriad?,
        colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        notationStyle: any NotationStyle,
        onTapNote: @escaping (PitchClass) -> Void,
        onSelectTriad: @escaping (TonnetzTriad) -> Void
    ) {
        self.heldPitchClasses = heldPitchClasses
        self.selectedTriad = selectedTriad
        self.colorScheme = colorScheme
        self.notationStyle = notationStyle
        self.onTapNote = onTapNote
        self.onSelectTriad = onSelectTriad
    }

    private static let edgeLength: CGFloat = 60
    private static let nodeRadius: CGFloat = 22

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

    private struct LayoutTriangle {
        let anchor: TonnetzCoordinate
        let quality: TonnetzTriadQuality
        let root: PitchClass
        let vertices: [CGPoint]
    }

    private struct LayoutInfo {
        let nodes: [LayoutNode]
        let triangles: [LayoutTriangle]
    }

    private func layoutInfo(for size: CGSize) -> LayoutInfo {
        let tile = Tonnetz.paddedTile()
        let entries: [(TonnetzCoordinate, Bool)] = tile.primary.map { ($0, true) } + tile.halo.map { ($0, false) }
        let rawPoints = entries.map { TonnetzGeometry.point(for: $0.0, edgeLength: Self.edgeLength) }
        guard let minX = rawPoints.map(\.x).min(), let maxX = rawPoints.map(\.x).max(),
              let minY = rawPoints.map(\.y).min(), let maxY = rawPoints.map(\.y).max() else {
            return LayoutInfo(nodes: [], triangles: [])
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
        return LayoutInfo(nodes: nodes, triangles: triangles)
    }

    private func plrNeighborKeys() -> Set<TonnetzKey> {
        guard let selectedTriad else { return [] }
        let neighbors = [Tonnetz.parallel(of: selectedTriad), Tonnetz.relative(of: selectedTriad), Tonnetz.leadingToneExchange(of: selectedTriad)]
        return Set(neighbors.map(\.key))
    }

    private func handleTap(at location: CGPoint, layout: LayoutInfo) {
        if let nearestNode = layout.nodes.min(by: { distance($0.point, location) < distance($1.point, location) }),
           distance(nearestNode.point, location) <= Self.nodeRadius {
            onTapNote(nearestNode.pitchClass)
            return
        }
        if let triangle = layout.triangles.first(where: { pointInTriangle(location, $0.vertices[0], $0.vertices[1], $0.vertices[2]) }) {
            onSelectTriad(TonnetzTriad(coordinate: triangle.anchor, quality: triangle.quality, root: triangle.root))
        }
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, layout: LayoutInfo) {
        let neighborKeys = plrNeighborKeys()
        for triangle in layout.triangles {
            let key = TonnetzKey(root: triangle.root, quality: triangle.quality)
            let isSelected = selectedTriad?.key == key
            let isNeighbor = !isSelected && neighborKeys.contains(key)
            let path = trianglePath(triangle.vertices)
            let fill: Color = isSelected ? Color.accentColor.opacity(0.4) : (isNeighbor ? Color.orange.opacity(0.2) : Color.secondary.opacity(0.05))
            context.fill(path, with: .color(fill))
            if isNeighbor {
                context.stroke(path, with: .color(.orange), style: StrokeStyle(lineWidth: 2, dash: [4, 3]))
            } else {
                context.stroke(path, with: .color(isSelected ? Color.accentColor : Color.secondary.opacity(0.35)), lineWidth: isSelected ? 3 : 1)
            }
        }

        let chordTones = selectedTriad?.chord?.pitchClasses.map(\.value) ?? []
        let heldAtSyntheticOctave = Set(heldPitchClasses.map { 60 + $0.value })
        for node in layout.nodes {
            let state = pitchDisplayState(
                pitch: 60 + node.pitchClass.value,
                heldPitches: heldAtSyntheticOctave,
                chordRoot: selectedTriad?.root.value,
                chordTones: chordTones,
                modeTones: [],
                alwaysShowChord: true
            )
            context.drawLayer { layer in
                layer.opacity = node.isPrimary ? 1 : 0.55
                let fill = colorScheme.fillColor(for: state.role, isWhiteKey: true)
                let rect = CGRect(x: node.point.x - Self.nodeRadius, y: node.point.y - Self.nodeRadius, width: Self.nodeRadius * 2, height: Self.nodeRadius * 2)
                let circle = Path(ellipseIn: rect)
                layer.fill(circle, with: .color(fill))
                layer.stroke(circle, with: .color(.black.opacity(0.35)), lineWidth: 1)
                let isLightFill = fill == colorScheme.whiteKey || state.role == .chordTone || state.role == .modeTone
                layer.draw(
                    Text(notationStyle.rootName(node.pitchClass, preferFlats: false)).font(.system(size: 13, weight: .semibold)).foregroundStyle(isLightFill ? Color.black : Color.white),
                    at: node.point
                )
            }
        }
    }
}

/// The "Registered Tonnetz" (mode Performance) — real, absolute-MIDI notes, windowed locally
/// around whatever's currently held (see `TonnetzGeometry.nearestCoordinate`), never the full
/// 88-key lattice at once. Same tap-a-node/tap-a-triangle interaction as
/// `PitchClassTonnetzView`, just over real pitches instead of pitch classes.
public struct RegisteredTonnetzView: View {
    public let heldPitches: Set<Int>
    public let selectedTriad: TonnetzTriad?
    public let colorScheme: PitchKeyboardColorScheme
    public let notationStyle: any NotationStyle
    public let onTapNote: (Int) -> Void
    public let onSelectTriad: (TonnetzTriad) -> Void

    public init(
        heldPitches: Set<Int>,
        selectedTriad: TonnetzTriad?,
        colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        notationStyle: any NotationStyle,
        onTapNote: @escaping (Int) -> Void,
        onSelectTriad: @escaping (TonnetzTriad) -> Void
    ) {
        self.heldPitches = heldPitches
        self.selectedTriad = selectedTriad
        self.colorScheme = colorScheme
        self.notationStyle = notationStyle
        self.onTapNote = onTapNote
        self.onSelectTriad = onSelectTriad
    }

    @State private var windowCenter = TonnetzCoordinate(q: 0, r: 0)

    private static let edgeLength: CGFloat = 56
    private static let nodeRadius: CGFloat = 20
    private static let qSpan = 3
    private static let rSpan = 2
    private static let midiRange = 21...108

    public var body: some View {
        GeometryReader { proxy in
            let layout = layoutInfo(for: proxy.size)
            Canvas { context, _ in draw(in: context, layout: layout) }
                .contentShape(Rectangle())
                .onTapGesture { location in handleTap(at: location, layout: layout) }
        }
        .aspectRatio(1.3, contentMode: .fit)
        // Recenters only when something is actually held — never snaps away during silence,
        // same "don't move the view out from under a still moment" convention
        // `AutoCenteredKeyboardView` already follows for its own window.
        .task(id: heldPitches) {
            guard !heldPitches.isEmpty else { return }
            let target = heldPitches.reduce(0, +) / heldPitches.count
            windowCenter = TonnetzGeometry.nearestCoordinate(toMidiPitch: target, near: windowCenter)
        }
    }

    // MARK: - Layout

    private struct LayoutNode {
        let midiPitch: Int
        let point: CGPoint
    }

    private struct LayoutTriangle {
        let anchor: TonnetzCoordinate
        let quality: TonnetzTriadQuality
        let root: PitchClass
        let pitches: [Int]
        let vertices: [CGPoint]
    }

    private struct LayoutInfo {
        let nodes: [LayoutNode]
        let triangles: [LayoutTriangle]
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
            return LayoutInfo(nodes: [], triangles: [])
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
        var triangles: [LayoutTriangle] = []
        for coordinate in validCoordinates {
            for quality in [TonnetzTriadQuality.major, .minor] {
                let vertexCoordinates = Tonnetz.nodes(ofQuality: quality, anchoredAt: coordinate)
                guard vertexCoordinates.allSatisfy({ validSet.contains($0) }) else { continue }
                let vertices = vertexCoordinates.compactMap { pointsByCoordinate[$0] }
                let pitches = vertexCoordinates.compactMap { coordinate in pointsByCoordinate[coordinate] != nil ? Tonnetz.midiPitch(at: coordinate) : nil }
                guard vertices.count == 3, pitches.count == 3 else { continue }
                triangles.append(LayoutTriangle(anchor: coordinate, quality: quality, root: Tonnetz.pitchClass(at: coordinate), pitches: pitches, vertices: vertices))
            }
        }
        return LayoutInfo(nodes: nodes, triangles: triangles)
    }

    private func handleTap(at location: CGPoint, layout: LayoutInfo) {
        if let nearestNode = layout.nodes.min(by: { distance($0.point, location) < distance($1.point, location) }),
           distance(nearestNode.point, location) <= Self.nodeRadius {
            onTapNote(nearestNode.midiPitch)
            return
        }
        if let triangle = layout.triangles.first(where: { pointInTriangle(location, $0.vertices[0], $0.vertices[1], $0.vertices[2]) }) {
            onSelectTriad(TonnetzTriad(coordinate: triangle.anchor, quality: triangle.quality, root: triangle.root))
        }
    }

    // MARK: - Drawing

    private func draw(in context: GraphicsContext, layout: LayoutInfo) {
        for triangle in layout.triangles {
            let isSelected = selectedTriad?.key == TonnetzKey(root: triangle.root, quality: triangle.quality)
            let path = trianglePath(triangle.vertices)
            context.fill(path, with: .color(isSelected ? Color.accentColor.opacity(0.4) : Color.secondary.opacity(0.05)))
            context.stroke(path, with: .color(isSelected ? Color.accentColor : Color.secondary.opacity(0.35)), lineWidth: isSelected ? 3 : 1)
        }

        let chordTones = selectedTriad?.chord?.pitchClasses.map(\.value) ?? []
        for node in layout.nodes {
            let state = pitchDisplayState(
                pitch: node.midiPitch,
                heldPitches: heldPitches,
                chordRoot: selectedTriad?.root.value,
                chordTones: chordTones,
                modeTones: [],
                alwaysShowChord: true
            )
            context.drawLayer { layer in
                let fill = colorScheme.fillColor(for: state.role, isWhiteKey: true)
                let rect = CGRect(x: node.point.x - Self.nodeRadius, y: node.point.y - Self.nodeRadius, width: Self.nodeRadius * 2, height: Self.nodeRadius * 2)
                let circle = Path(ellipseIn: rect)
                layer.fill(circle, with: .color(fill))
                layer.stroke(circle, with: .color(.black.opacity(0.35)), lineWidth: 1)
                let isLightFill = fill == colorScheme.whiteKey || state.role == .chordTone || state.role == .modeTone
                let octave = node.midiPitch / 12 - 1
                let label = "\(notationStyle.rootName(PitchClass(node.midiPitch), preferFlats: false))\(octave)"
                layer.draw(
                    Text(label).font(.system(size: 11, weight: .semibold)).foregroundStyle(isLightFill ? Color.black : Color.white),
                    at: node.point
                )
            }
        }
    }
}

/// Studio's Tonnetz screen — the mode toggle (Harmonique/Performance) plus whichever grid is
/// active, both coupled to the app's single "clavier principal" (`session.theoryLiveInputSourceID`)
/// and the Studio scene's own assigned sound (mirrors `ContentView.studioSourceHasAssignedSound`'s
/// gate — a note only actually sounds when the live source is wired to a scene role with a sound).
/// Tapping a node or triangle here always plays through that same live track (`pressKey`/
/// `releaseKey`), so a tap-triggered chord becomes real, recognized `heldPitches` exactly like any
/// other played chord — closing the harmonic/performance loop the same way a real instrument would.
public struct TonnetzScreen: View {
    public let session: ImprovSession

    public init(session: ImprovSession) {
        self.session = session
    }

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case harmonic, performance
        var id: Self { self }
        func label(_ language: AppLanguage) -> String {
            switch self {
            case .harmonic: return L10n.string(.appModeTonnetzHarmonique, language)
            case .performance: return L10n.string(.appModeTonnetzPerformance, language)
            }
        }
    }

    @State private var displayMode: DisplayMode = .harmonic
    @State private var selectedTriad: TonnetzTriad? = Tonnetz.triad(quality: .major, anchoredAt: TonnetzCoordinate(q: 0, r: 0))
    @State private var auditionGeneration = 0

    private var sourceID: TrackID? { session.theoryLiveInputSourceID }

    private var heldPitches: Set<Int> {
        guard let sourceID else { return [] }
        return session.tracks.first { $0.id == sourceID }?.heldPitches ?? []
    }

    private var heldPitchClasses: Set<PitchClass> { Set(heldPitches.map { PitchClass($0) }) }

    /// Mirrors `ContentView.studioSourceHasAssignedSound` — a tap here should never fire notes
    /// into a track with no instrument to sound them.
    private var canPlay: Bool {
        guard let sourceID else { return false }
        return session.currentScene?.roles.contains { $0.attachedTrackID == sourceID && $0.soundName != nil } ?? false
    }

    public var body: some View {
        VStack(spacing: 12) {
            Picker("", selection: $displayMode) {
                ForEach(DisplayMode.allCases) { mode in
                    Text(mode.label(session.currentLanguage)).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 360)

            selectedChordSummary

            Group {
                switch displayMode {
                case .harmonic:
                    PitchClassTonnetzView(
                        heldPitchClasses: heldPitchClasses,
                        selectedTriad: selectedTriad,
                        notationStyle: session.notationStyle,
                        onTapNote: { pitchClass in
                            guard canPlay else { return }
                            playSingleNote(nearestRealPitch(forPitchClass: pitchClass))
                        },
                        onSelectTriad: { triad in
                            selectedTriad = triad
                            guard canPlay else { return }
                            playTriad(triad)
                        }
                    )
                case .performance:
                    RegisteredTonnetzView(
                        heldPitches: heldPitches,
                        selectedTriad: selectedTriad,
                        notationStyle: session.notationStyle,
                        onTapNote: { pitch in
                            guard canPlay else { return }
                            playSingleNote(pitch)
                        },
                        onSelectTriad: { triad in
                            selectedTriad = triad
                            guard canPlay else { return }
                            playTriad(triad)
                        }
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding()
        .onChange(of: session.theoryLiveInputRecognizedChord) { _, newChord in
            reactToLiveRecognition(newChord)
        }
    }

    @ViewBuilder
    private var selectedChordSummary: some View {
        if let chord = selectedTriad?.chord {
            Text(session.notationStyle.displayName(for: chord)).font(.title2).bold()
        }
    }

    /// Directly follows a recognized major/minor triad exactly as if it had been tapped — same
    /// "live overrides the browsed selection" convention every other Théorie screen's live-match
    /// reaction already follows. Recognized chords of any other quality (7ths, etc.) are ignored
    /// for now — Phase 1 only models plain triads on the lattice (see the plan's Phase 2 backlog).
    private func reactToLiveRecognition(_ chord: RecognizedChord?) {
        guard let chord, chord.chordTemplateID == "Ma" || chord.chordTemplateID == "mi" else { return }
        let quality: TonnetzTriadQuality = chord.chordTemplateID == "Ma" ? .major : .minor
        let tile = Tonnetz.paddedTile()
        guard let coordinate = Tonnetz.coordinate(forRoot: chord.root, in: tile.primary + tile.halo) else { return }
        selectedTriad = Tonnetz.triad(quality: quality, anchoredAt: coordinate)
    }

    private func nearestRealPitch(forPitchClass pitchClass: PitchClass) -> Int {
        let anchor = heldPitches.isEmpty ? 60 : heldPitches.reduce(0, +) / heldPitches.count
        let candidates = stride(from: pitchClass.value, through: 120, by: 12).map { $0 }
        let best = candidates.min(by: { abs($0 - anchor) < abs($1 - anchor) }) ?? (pitchClass.value + 60)
        return min(max(best, 21), 108)
    }

    private func playSingleNote(_ pitch: Int) {
        guard let sourceID else { return }
        session.pressKey(pitch: pitch, track: sourceID)
        auditionGeneration += 1
        let generation = auditionGeneration
        Task {
            try? await Task.sleep(nanoseconds: 700_000_000)
            if generation == auditionGeneration {
                session.releaseKey(pitch: pitch, track: sourceID)
            }
        }
    }

    private func playTriad(_ triad: TonnetzTriad) {
        guard let sourceID, let chord = triad.chord else { return }
        let targetPitches = TonnetzVoicing.nearestVoicing(forChord: chord, previousPitches: Array(heldPitches))
        session.releaseAllKeys(track: sourceID)
        for pitch in targetPitches { session.pressKey(pitch: pitch, track: sourceID) }
        auditionGeneration += 1
        let generation = auditionGeneration
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            if generation == auditionGeneration {
                session.releaseAllKeys(track: sourceID)
            }
        }
    }
}
