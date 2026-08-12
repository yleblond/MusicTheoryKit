import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// A standard vertical guitar chord diagram (6 strings, 4 frets) rendered from
/// `GuitarChordShape.Diagram` (`Sources/AppCore/GuitarChordShapes.swift`) — that data is
/// already presentation-agnostic (no ASCII/HTML-specific concept anywhere in it), so this
/// view consumes it directly with no adaptation. A `Canvas` port of the web console's own
/// `guitarChordDiagramHTML` (`Sources/WebConsole/StaticAssets.swift`), same fixed 150x172
/// geometry and styling (fret-number label, finger numbers inside each dot, muted-string "x"
/// above the nut) — no "open position" special-casing (thicker nut / open-string ring) the
/// web version doesn't have either; a barre at fret 0 (an open-position chord) is drawn
/// exactly the same way as any other barre.
public struct GuitarChordDiagramView: View {
    public let diagram: GuitarChordShape.Diagram?
    /// Shown (with "pas de position standard") when `diagram` is `nil` — either an
    /// unrecognized chord/root, or a recognized one with no verified standard shape (see
    /// `GuitarChordShape`'s own doc comment for why some qualities are deliberately excluded).
    public let fallbackLabel: String
    public let colorScheme: PitchKeyboardColorScheme
    /// The chord's root pitch class, used to color each STRING by which note it sounds (root
    /// vs. any other chord tone, via `GuitarChordShape.Diagram.soundedPitchClass(atStringIndex:)`)
    /// — `nil` only for a caller that genuinely doesn't know it, in which case strings fall back
    /// to a plain neutral color instead of guessing.
    public let rootPitchClass: PitchClass?
    /// Color for the barre bar and finger-position dots — a fingering/position indicator,
    /// deliberately independent of `colorScheme.chordRoot`/`chordTone` (those are reserved for
    /// note identity on the strings themselves; the barre isn't always on the root string, see
    /// `soundedPitchClass(atStringIndex:)`'s own doc comment).
    public let positionColor: Color
    /// Which note-naming convention labels each string's own sounded note (see
    /// `stringNoteLabels`) — defaults to the only style shipped today, same fallback
    /// `NotationStyleRegistry.byID` itself uses for an unmigrated id.
    public let notationStyle: any NotationStyle
    /// Only used for the "position de base" fallback caption — defaults to French like every
    /// other JamShackUI component's default language.
    public let language: AppLanguage

    public init(
        root: Int, chordTemplateID: String, colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        positionColor: Color = .accentColor, notationStyle: any NotationStyle = AngloAmericanNotationStyle(), language: AppLanguage = .fr
    ) {
        self.diagram = GuitarChordShape.diagram(forRoot: root, chordTemplateID: chordTemplateID)
        self.fallbackLabel = "\(PitchClass(root).name())\(chordTemplateID)"
        self.colorScheme = colorScheme
        self.rootPitchClass = PitchClass(root)
        self.positionColor = positionColor
        self.notationStyle = notationStyle
        self.language = language
    }

    /// The Chord Library's own entry point: a specific inversion's diagram (0 = root position),
    /// via `GuitarChordShape.diagram(forRoot:chordTemplateID:inversion:)` — see that function's
    /// doc comment for when this falls back to the root-position shape (`diagram?.isBasePositionFallback`).
    public init(
        root: Int, chordTemplateID: String, inversion: Int, colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        positionColor: Color = .accentColor, notationStyle: any NotationStyle = AngloAmericanNotationStyle(), language: AppLanguage = .fr
    ) {
        self.diagram = GuitarChordShape.diagram(forRoot: root, chordTemplateID: chordTemplateID, inversion: inversion)
        self.fallbackLabel = "\(PitchClass(root).name())\(chordTemplateID)"
        self.colorScheme = colorScheme
        self.rootPitchClass = PitchClass(root)
        self.positionColor = positionColor
        self.notationStyle = notationStyle
        self.language = language
    }

    /// Consumes an already-resolved diagram straight from `ImprovSession`'s live state (e.g.
    /// `WebConsoleGuideState.currentChordGuitarDiagram`, the same wire-shaped value the web
    /// console's own `renderGuide` uses) — this app's `SessionUIBridge` already exposes that
    /// exact struct, so there's no need to also carry a `chordTemplateID` through just to
    /// re-derive the same diagram a second time via `GuitarChordShape.diagram(forRoot:
    /// chordTemplateID:)`.
    public init(
        webDiagram: WebConsoleGuitarChordDiagram?, fallbackLabel: String, root: Int? = nil, colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        positionColor: Color = .accentColor, notationStyle: any NotationStyle = AngloAmericanNotationStyle(), language: AppLanguage = .fr
    ) {
        self.diagram = webDiagram.map { web in
            GuitarChordShape.Diagram(
                label: web.label,
                barreFret: web.barreFret,
                positions: zip(web.frets, web.fingers).map { GuitarChordShape.StringPosition(relativeFret: $0, finger: $1) }
            )
        }
        self.fallbackLabel = fallbackLabel
        self.colorScheme = colorScheme
        self.rootPitchClass = root.map(PitchClass.init)
        self.positionColor = positionColor
        self.notationStyle = notationStyle
        self.language = language
    }

    // MARK: - Geometry (mirrors guitarChordDiagramHTML's own width/height/margin/shownFrets)

    private static let stringCount = 6
    private static let shownFrets = 4 // barre fret + 3 more — every covered shape's highest offset is +3
    private static let width: CGFloat = 150
    // +12 off the original 172/16 (height/marginBottom, same delta on both so `fretSpacing`
    // below is unaffected) — just enough extra room for each string's own note-name label
    // below the grid, per explicit request.
    private static let height: CGFloat = 184
    private static let marginLeft: CGFloat = 24
    private static let marginTop: CGFloat = 22
    private static let marginBottom: CGFloat = 28
    private static let stringSpacing = (width - marginLeft * 2) / CGFloat(stringCount - 1)
    private static let fretSpacing = (height - marginTop - marginBottom) / CGFloat(shownFrets)
    private static let dotRadius: CGFloat = 8

    public var body: some View {
        if let diagram {
            VStack(spacing: 4) {
                Text(diagram.label).font(.title2).bold()
                Canvas { context, size in
                    draw(diagram: diagram, in: context, size: size)
                }
                .frame(width: Self.width, height: Self.height)
                if diagram.isBasePositionFallback {
                    Text(L10n.string(.appLabelPositionDeBase, language))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        } else {
            Text("\(fallbackLabel): pas de position standard")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func draw(diagram: GuitarChordShape.Diagram, in context: GraphicsContext, size: CGSize) {
        let gridBottom = Self.marginTop + CGFloat(Self.shownFrets) * Self.fretSpacing
        let gridRight = Self.marginLeft + CGFloat(Self.stringCount - 1) * Self.stringSpacing

        // Strings (vertical lines), string 6 (low E) on the left, string 1 (high e) on the
        // right — colored by the note each one actually sounds (root vs. any other chord tone),
        // not by its position in the shape; a muted string, or one with no known chord root,
        // stays neutral.
        for stringIndex in 0..<Self.stringCount {
            let x = Self.marginLeft + CGFloat(stringIndex) * Self.stringSpacing
            var path = Path()
            path.move(to: CGPoint(x: x, y: Self.marginTop))
            path.addLine(to: CGPoint(x: x, y: gridBottom))
            let stringColor: Color
            if let rootPitchClass, let sounded = diagram.soundedPitchClass(atStringIndex: stringIndex) {
                stringColor = sounded == rootPitchClass ? colorScheme.chordRoot : colorScheme.chordTone
            } else {
                stringColor = .secondary
            }
            context.stroke(path, with: .color(stringColor), lineWidth: 1.5)
        }

        // Which note each string actually sounds, labeled right below the grid — a muted
        // string gets no label (nothing to name), per explicit request.
        for stringIndex in 0..<Self.stringCount {
            guard let sounded = diagram.soundedPitchClass(atStringIndex: stringIndex) else { continue }
            let x = Self.marginLeft + CGFloat(stringIndex) * Self.stringSpacing
            context.draw(
                Text(notationStyle.rootName(sounded, preferFlats: false)).font(.system(size: 10)).foregroundStyle(.secondary),
                at: CGPoint(x: x, y: gridBottom + 10), anchor: .center
            )
        }

        // Frets (horizontal lines), all the same weight — no nut/open-position distinction.
        for fretIndex in 0...Self.shownFrets {
            let y = Self.marginTop + CGFloat(fretIndex) * Self.fretSpacing
            var path = Path()
            path.move(to: CGPoint(x: Self.marginLeft, y: y))
            path.addLine(to: CGPoint(x: gridRight, y: y))
            context.stroke(path, with: .color(.secondary), lineWidth: 1.5)
        }

        // Which fret the whole diagram is transposed to — always shown, even "0" for an
        // open-position chord (matches guitarChordDiagramHTML's own unconditional label).
        context.draw(
            Text("\(diagram.barreFret)").font(.system(size: 11)).foregroundStyle(.secondary),
            at: CGPoint(x: Self.marginLeft - 14, y: Self.marginTop + Self.fretSpacing / 2 + 4), anchor: .trailing
        )

        // Barre: a rounded bar spanning every string sharing relativeFret 0 — a single dot if
        // only one string does (a lone barred string still needs its own marker).
        let barredIndices = diagram.positions.indices.filter { diagram.positions[$0].relativeFret == 0 }
        let barreY = Self.marginTop + Self.fretSpacing / 2
        if barredIndices.count > 1, let first = barredIndices.min(), let last = barredIndices.max() {
            let x1 = Self.marginLeft + CGFloat(first) * Self.stringSpacing
            let x2 = Self.marginLeft + CGFloat(last) * Self.stringSpacing
            var path = Path()
            path.move(to: CGPoint(x: x1, y: barreY))
            path.addLine(to: CGPoint(x: x2, y: barreY))
            context.stroke(path, with: .color(positionColor), style: StrokeStyle(lineWidth: 9, lineCap: .round))
        } else if barredIndices.count == 1 {
            let x = Self.marginLeft + CGFloat(barredIndices[0]) * Self.stringSpacing
            context.fill(Path(ellipseIn: CGRect(x: x - Self.dotRadius, y: barreY - Self.dotRadius, width: Self.dotRadius * 2, height: Self.dotRadius * 2)), with: .color(positionColor))
        }

        // Per-string markers: a muted "x" above the nut, or a fretted dot with its finger
        // number inside — a string at relativeFret 0 is already covered by the barre above.
        for (stringIndex, position) in diagram.positions.enumerated() {
            let x = Self.marginLeft + CGFloat(stringIndex) * Self.stringSpacing
            guard let relativeFret = position.relativeFret else {
                context.draw(Text("\u{00D7}").font(.system(size: 13)).foregroundStyle(Color(hex: "#e57373")), at: CGPoint(x: x, y: Self.marginTop - 10))
                continue
            }
            guard relativeFret != 0 else { continue }
            let dotY = Self.marginTop + (CGFloat(relativeFret) + 0.5) * Self.fretSpacing
            context.fill(Path(ellipseIn: CGRect(x: x - Self.dotRadius, y: dotY - Self.dotRadius, width: Self.dotRadius * 2, height: Self.dotRadius * 2)), with: .color(positionColor))
            if let finger = position.finger {
                context.draw(Text("\(finger)").font(.system(size: 10)).foregroundStyle(.black), at: CGPoint(x: x, y: dotY))
            }
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
