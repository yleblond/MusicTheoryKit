import SwiftUI
import AppCore
import MusicTheoryKit

/// A standard vertical guitar chord diagram (6 strings, 4 frets) rendered from
/// `GuitarChordShape.Diagram` (`Sources/AppCore/GuitarChordShapes.swift`) — that data is
/// already presentation-agnostic (no ASCII/HTML-specific concept anywhere in it), so this
/// view consumes it directly with no adaptation. Self-contained: unlike `PitchKeyboardView`,
/// it needs no live session state at all, just a root pitch class and a chord template ID.
public struct GuitarChordDiagramView: View {
    public let root: Int
    public let chordTemplateID: String

    public init(root: Int, chordTemplateID: String) {
        self.root = root
        self.chordTemplateID = chordTemplateID
    }

    private static let stringCount = 6
    private static let fretRowCount = 4

    public var body: some View {
        if let diagram = GuitarChordShape.diagram(forRoot: root, chordTemplateID: chordTemplateID) {
            VStack(spacing: 4) {
                Text(diagram.label).font(.headline)
                Canvas { context, size in
                    draw(diagram: diagram, in: context, size: size)
                }
                .frame(minWidth: 120, minHeight: 140)
            }
        } else {
            Text("\(PitchClass(root).name())\(chordTemplateID): pas de position standard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func draw(diagram: GuitarChordShape.Diagram, in context: GraphicsContext, size: CGSize) {
        let margin: CGFloat = 16
        let markerAreaHeight: CGFloat = 20 // room for the open/muted string markers above the nut
        let gridWidth = size.width - margin * 2
        let gridHeight = size.height - margin * 2 - markerAreaHeight
        let stringSpacing = gridWidth / CGFloat(Self.stringCount - 1)
        let fretSpacing = gridHeight / CGFloat(Self.fretRowCount)
        let gridTop = margin + markerAreaHeight
        let isOpenPosition = diagram.barreFret == 0

        // Strings (vertical lines), string 6 (low E) on the left, string 1 (high e) on the right.
        for stringIndex in 0..<Self.stringCount {
            let x = margin + CGFloat(stringIndex) * stringSpacing
            var path = Path()
            path.move(to: CGPoint(x: x, y: gridTop))
            path.addLine(to: CGPoint(x: x, y: gridTop + gridHeight))
            context.stroke(path, with: .color(.primary), lineWidth: 1)
        }

        // Frets (horizontal lines) — the nut (top line) is drawn thicker only when this
        // diagram is an open-position chord (barreFret == 0), matching standard notation.
        for fretIndex in 0...Self.fretRowCount {
            let y = gridTop + CGFloat(fretIndex) * fretSpacing
            var path = Path()
            path.move(to: CGPoint(x: margin, y: y))
            path.addLine(to: CGPoint(x: margin + gridWidth, y: y))
            let isNut = fretIndex == 0
            context.stroke(path, with: .color(.primary), lineWidth: (isNut && isOpenPosition) ? 4 : 1)
        }

        if !isOpenPosition {
            context.draw(Text("\(diagram.barreFret + 1)fr").font(.caption2), at: CGPoint(x: margin - 10, y: gridTop + fretSpacing / 2), anchor: .trailing)
        }

        // Barre: a rounded bar spanning every string sharing finger 1 at relativeFret 0.
        let barreStrings = diagram.positions.indices.filter { diagram.positions[$0].finger == 1 && diagram.positions[$0].relativeFret == 0 }
        if barreStrings.count > 1, let first = barreStrings.min(), let last = barreStrings.max() {
            let x1 = margin + CGFloat(first) * stringSpacing
            let x2 = margin + CGFloat(last) * stringSpacing
            let y = gridTop + fretSpacing / 2
            let barRect = CGRect(x: x1 - 6, y: y - 6, width: x2 - x1 + 12, height: 12)
            context.fill(Path(roundedRect: barRect, cornerRadius: 6), with: .color(.accentColor))
        }

        // Per-string markers: fretted dot, open circle, or muted "x" above the nut.
        for (stringIndex, position) in diagram.positions.enumerated() {
            let x = margin + CGFloat(stringIndex) * stringSpacing
            guard let relativeFret = position.relativeFret else {
                context.draw(Text("x").font(.caption.bold()), at: CGPoint(x: x, y: margin + markerAreaHeight / 2))
                continue
            }
            if relativeFret == 0 {
                if isOpenPosition {
                    let r: CGFloat = 5
                    context.stroke(Path(ellipseIn: CGRect(x: x - r, y: margin + markerAreaHeight / 2 - r, width: r * 2, height: r * 2)), with: .color(.primary), lineWidth: 1.5)
                }
                // Non-open barreFret==0-relative positions are covered by the barre bar above;
                // nothing extra to draw for a single (non-barre) string at the barre fret.
                continue
            }
            let dotY = gridTop + (CGFloat(relativeFret) - 0.5) * fretSpacing
            let r: CGFloat = 8
            context.fill(Path(ellipseIn: CGRect(x: x - r, y: dotY - r, width: r * 2, height: r * 2)), with: .color(.accentColor))
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        GuitarChordDiagramView(root: 0, chordTemplateID: "Ma") // open C... actually E-shape barre at fret matching C
        GuitarChordDiagramView(root: 5, chordTemplateID: "Ma") // F, fret 1 barre
        GuitarChordDiagramView(root: 0, chordTemplateID: "Ma7#5") // uncovered quality
    }
    .padding()
}
