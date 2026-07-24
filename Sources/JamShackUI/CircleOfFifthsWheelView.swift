import SwiftUI
import AppCore

/// A polar rendering of the circle-of-fifths wheel (`WebConsoleWheelState`, always present in
/// `SessionUIBridge.state` — never gated behind an active guide, same as the web console's own
/// `renderWheel`). 12 columns arranged around the circle in the fixed ascending-fifths order
/// the server already sends (`columns` never depends on `tonic`), each with 3 rings (major
/// outer, minor middle, diminished inner) — the diatonic 7 chords relative to the current
/// `tonic` are highlighted, matching the "grouping layer" the web console draws.
public struct CircleOfFifthsWheelView: View {
    public let wheel: WebConsoleWheelState

    public init(wheel: WebConsoleWheelState) {
        self.wheel = wheel
    }

    public var body: some View {
        VStack(spacing: 4) {
            Text(wheel.activeModeName).font(.headline)
            Canvas { context, size in
                draw(in: context, size: size)
            }
            .aspectRatio(1, contentMode: .fit)
        }
    }

    private func draw(in context: GraphicsContext, size: CGSize) {
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        let outerRadius = min(size.width, size.height) / 2 - 8
        // Major (index 0) outermost, diminished (index 2) innermost.
        let ringRadii = [outerRadius, outerRadius * 0.68, outerRadius * 0.38]
        let cellRadius: CGFloat = outerRadius * 0.16

        for (columnIndex, column) in wheel.columns.enumerated() {
            // Angle 0 (column 0, C) points straight up; columns proceed clockwise.
            let angle = (Double(columnIndex) / 12.0) * 2 * .pi - .pi / 2
            let isActiveColumn = columnIndex == wheel.activeColumnIndex

            for (ringIndex, cell) in column.cells.enumerated() {
                guard ringIndex < ringRadii.count else { continue }
                let radius = ringRadii[ringIndex]
                let point = CGPoint(x: center.x + CGFloat(cos(angle)) * radius, y: center.y + CGFloat(sin(angle)) * radius)
                let rect = CGRect(x: point.x - cellRadius, y: point.y - cellRadius, width: cellRadius * 2, height: cellRadius * 2)

                let isPlayed = !cell.trackLabels.isEmpty
                let fill: Color = isPlayed ? .accentColor : (cell.isDiatonic ? .accentColor.opacity(0.35) : .secondary.opacity(0.15))

                let path = cell.shape == "circle" ? Path(ellipseIn: rect) : Path(roundedRect: rect, cornerRadius: 4)
                context.fill(path, with: .color(fill))
                if isActiveColumn {
                    context.stroke(path, with: .color(.primary), lineWidth: 2)
                }
                context.draw(
                    Text(cell.relativeDegree).font(.caption2).foregroundStyle(isPlayed ? .white : .primary),
                    at: point
                )
            }
        }
    }
}

// No public initializer exists for WebConsoleWheelState/Column/Cell (deliberately — they're
// read-only outside AppCore, built only by ImprovSession.buildWebConsoleState()), so the
// preview goes through a real session rather than constructing fake wire data by hand.
#Preview {
    let session = ImprovSession()
    return CircleOfFifthsWheelView(wheel: session.buildWebConsoleState().wheel)
        .padding()
}
