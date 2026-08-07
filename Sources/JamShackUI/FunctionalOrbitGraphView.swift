import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// Graph 1 of the "Exploration fonctionnelle" panel — the tonic at the center, every other
/// diatonic chord placed at a radius driven by its own `functionalIntensity` (farther = more
/// tense/unstable). Tapping a chord selects it (bubbles up via `onSelect`, shared with
/// `FunctionalAttractionGraphView` so both graphs' selection stay in sync) and plays it (via
/// `onPlay`) — the same "see it AND hear it" convention every other Théorie screen already uses.
public struct FunctionalOrbitGraphView: View {
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
    /// Matches `FunctionalGraphLayout.positions`' own min/max radius — drawn faintly as a guide
    /// for "how far from home is far", per the original spec's "orbites implicites" guidance
    /// (kept deliberately understated: dotted, low-opacity, no labels of their own).
    private static let guideRadii: [CGFloat] = [0.22, 0.6, 0.98]

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

    // MARK: - Layout

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

    private func draw(in context: GraphicsContext, size: CGSize, layout: LayoutInfo) {
        for radiusFraction in Self.guideRadii {
            let r = radiusFraction * layout.scale
            let rect = CGRect(x: layout.center.x - r, y: layout.center.y - r, width: r * 2, height: r * 2)
            context.stroke(Path(ellipseIn: rect), with: .color(.secondary.opacity(0.25)), style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
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
}
