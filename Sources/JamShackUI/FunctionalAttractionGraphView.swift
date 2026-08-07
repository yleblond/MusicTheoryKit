import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// Graph 2 of the "Exploration fonctionnelle" panel — same node positions as
/// `FunctionalOrbitGraphView` (built from the same `FunctionalGraphLayout.positions(for:)`, so
/// the two graphs read as the same "map" rather than two unrelated layouts), plus directional
/// arrows for `map.attractions`: thicker/more opaque = stronger pull toward home. Selecting a
/// chord (tap, synced with the orbit graph via `selectedDegree`/`onSelect`) dims every arrow
/// that doesn't touch it, per the original spec's "que fait cet accord dans ce mode ?" goal.
public struct FunctionalAttractionGraphView: View {
    public let map: ModeFunctionalMap
    public let notationStyle: any NotationStyle
    public let language: AppLanguage
    public let selectedDegree: Int?
    public let onSelect: (Int) -> Void

    @State private var hoveredDegree: Int?

    public init(map: ModeFunctionalMap, notationStyle: any NotationStyle, language: AppLanguage, selectedDegree: Int?, onSelect: @escaping (Int) -> Void) {
        self.map = map
        self.notationStyle = notationStyle
        self.language = language
        self.selectedDegree = selectedDegree
        self.onSelect = onSelect
    }

    private static let baseNodeRadius: CGFloat = 26

    public var body: some View {
        GeometryReader { proxy in
            let layout = layoutInfo(for: proxy.size)
            Canvas { context, size in
                draw(in: context, size: size, layout: layout)
            }
            .contentShape(Rectangle())
            .onTapGesture { location in
                if let degree = nodeDegree(at: location, layout: layout) { onSelect(degree) }
            }
            #if os(macOS) || os(visionOS)
            .onContinuousHover { phase in
                switch phase {
                case .active(let location): hoveredDegree = nodeDegree(at: location, layout: layout)
                case .ended: hoveredDegree = nil
                }
            }
            #endif
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(functionalMapAccessibilitySummary(map, notationStyle: notationStyle, language: language))
        }
        .aspectRatio(1, contentMode: .fit)
    }

    // MARK: - Layout (identical math to FunctionalOrbitGraphView, deliberately not shared via a
    // common base type — two ~10-line functions is cheaper to keep in sync by inspection than a
    // shared abstraction would be to design well for exactly two call sites).

    private struct LayoutInfo {
        let center: CGPoint
        let scale: CGFloat
        let nodes: [FunctionalNodePosition]
    }

    private func layoutInfo(for size: CGSize) -> LayoutInfo {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let scale = min(size.width, size.height) / 2 * 0.78
        return LayoutInfo(center: center, scale: scale, nodes: FunctionalGraphLayout.positions(for: map))
    }

    private func screenPosition(_ node: FunctionalNodePosition, layout: LayoutInfo) -> CGPoint {
        CGPoint(x: layout.center.x + node.position.x * layout.scale, y: layout.center.y + node.position.y * layout.scale)
    }

    private func nodeDegree(at location: CGPoint, layout: LayoutInfo) -> Int? {
        for node in layout.nodes {
            let center = screenPosition(node, layout: layout)
            let state = displayState(for: node.degree)
            let radius = FunctionalChordNodeDrawing.hitRadius(baseRadius: Self.baseNodeRadius, degree: node.degree, state: state)
            let dx = location.x - center.x, dy = location.y - center.y
            if dx * dx + dy * dy <= radius * radius { return node.degree }
        }
        return nil
    }

    private func displayState(for degree: Int) -> FunctionalNodeState {
        if degree == selectedDegree { return .selected }
        if degree == hoveredDegree { return .hovered }
        if selectedDegree != nil { return .dimmed }
        return .normal
    }

    private func chord(forDegree degree: Int) -> ModalChordFunction? {
        map.chords.first { $0.degree == degree }
    }

    /// Whether `attraction` touches the currently selected chord — used to dim every OTHER
    /// arrow once something is selected, per the spec's "isole les relations de cet accord".
    private func isRelevant(_ attraction: HarmonicAttraction) -> Bool {
        guard let selectedDegree else { return true }
        return attraction.fromDegree == selectedDegree || attraction.toDegree == selectedDegree
    }

    private func draw(in context: GraphicsContext, size: CGSize, layout: LayoutInfo) {
        let nodeByDegree = Dictionary(uniqueKeysWithValues: layout.nodes.map { ($0.degree, $0) })
        for attraction in map.attractions {
            guard let from = nodeByDegree[attraction.fromDegree], let to = nodeByDegree[attraction.toDegree] else { continue }
            drawArrow(
                in: context, from: screenPosition(from, layout: layout), to: screenPosition(to, layout: layout),
                strength: attraction.strength, dimmed: !isRelevant(attraction)
            )
        }
        for node in layout.nodes {
            guard let chordFunction = chord(forDegree: node.degree), let chord = chordFunction.reference.resolve() else { continue }
            let center = screenPosition(node, layout: layout)
            let name = notationStyle.displayName(for: chord)
            let numeral = romanNumeral(degree: node.degree, quality: triadQuality(of: chord))
            FunctionalChordNodeDrawing.draw(
                in: context, center: center, baseRadius: Self.baseNodeRadius,
                chord: chordFunction, name: name, romanNumeral: numeral, state: displayState(for: node.degree)
            )
        }
    }

    /// A line shortened at both ends by the target node's own radius (so the arrowhead touches
    /// the node's edge, not its center) plus a filled triangular head — thickness/opacity scale
    /// with `strength`, matching the "faible/moyen/fort" rendering the original spec described.
    private func drawArrow(in context: GraphicsContext, from: CGPoint, to: CGPoint, strength: Double, dimmed: Bool) {
        let dx = to.x - from.x, dy = to.y - from.y
        let length = max(sqrt(dx * dx + dy * dy), 1)
        let ux = dx / length, uy = dy / length
        let startInset = Self.baseNodeRadius * 1.1
        let endInset = Self.baseNodeRadius * 1.35
        let start = CGPoint(x: from.x + ux * startInset, y: from.y + uy * startInset)
        let end = CGPoint(x: to.x - ux * endInset, y: to.y - uy * endInset)

        let lineWidth = 1.5 + CGFloat(strength) * 3.5
        let baseOpacity = 0.35 + strength * 0.55

        context.drawLayer { layer in
            layer.opacity = dimmed ? baseOpacity * 0.25 : baseOpacity

            var line = Path()
            line.move(to: start)
            line.addLine(to: end)
            layer.stroke(line, with: .color(.primary), style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))

            let headLength: CGFloat = 8 + CGFloat(strength) * 4
            let headWidth: CGFloat = 6 + CGFloat(strength) * 3
            let backX = end.x - ux * headLength, backY = end.y - uy * headLength
            let perpX = -uy, perpY = ux
            var head = Path()
            head.move(to: end)
            head.addLine(to: CGPoint(x: backX + perpX * headWidth / 2, y: backY + perpY * headWidth / 2))
            head.addLine(to: CGPoint(x: backX - perpX * headWidth / 2, y: backY - perpY * headWidth / 2))
            head.closeSubpath()
            layer.fill(head, with: .color(.primary))
        }
    }
}
