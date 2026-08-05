import SwiftUI
import AppCore
import MusicTheoryKit

/// A single "column" of notes to draw on the grand staff — mirrors
/// `Sources/WebConsole/StaticAssets.swift`'s `renderStaffSVG` per-event shape
/// (`{pitches, chordRoot, chordTones}`).
public struct StaffEvent {
    public let pitches: [Int]
    public let chordRoot: Int?
    public let chordTones: [Int]

    public init(pitches: [Int], chordRoot: Int? = nil, chordTones: [Int] = []) {
        self.pitches = pitches
        self.chordRoot = chordRoot
        self.chordTones = chordTones
    }
}

/// A grand staff (treble + bass clef) drawing `events` left to right, one column per event —
/// a `Canvas` port of `Sources/WebConsole/StaticAssets.swift`'s `renderStaffSVG`/
/// `staffRowIndexForPitch`/`staffLedgerRows` (kept in sync by hand across the two
/// presentation layers, same convention this project already uses elsewhere for its JS/Swift/
/// Python surfaces — e.g. `mcp-server/server.py`'s own hand-ported `ACTIONS` table).
public struct ChordStaffView: View {
    public let events: [StaffEvent]
    public let colorScheme: PitchKeyboardColorScheme
    /// Scales every HEIGHT-affecting dimension (row spacing, margins, clef size) uniformly —
    /// e.g. the Guide screen's own notation is 0.9 (10% shorter than the shared default),
    /// per explicit user request. Width (`firstColX`/`colWidth`/`marginRight`) is deliberately
    /// untouched by this — only asked to change the height.
    public let heightScale: CGFloat

    public init(events: [StaffEvent], colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(), heightScale: CGFloat = 1) {
        self.events = events
        self.colorScheme = colorScheme
        self.heightScale = heightScale
    }

    // MARK: - Row geometry (mirrors STAFF_ROWS/STAFF_TREBLE_TOP/etc. in StaticAssets.swift)

    private struct StaffRow { let midi: Int; let isLine: Bool }

    private static let minMidi = 43 // G2
    private static let maxMidi = 84 // C6
    private static let naturalPitchClasses: Set<Int> = [0, 2, 4, 5, 7, 9, 11] // C D E F G A B

    /// One entry per natural note in `minMidi...maxMidi`, row 0 = highest pitch (descending),
    /// each carrying whether it's a staff LINE or a space — lines/spaces strictly alternate
    /// across the whole grand staff (ledger lines are just a continuation of the same
    /// pattern), so parity relative to one known line (E4, the treble clef's bottom line)
    /// determines every other row automatically.
    private static let rows: [StaffRow] = {
        let naturals = (minMidi...maxMidi).filter { naturalPitchClasses.contains((($0 % 12) + 12) % 12) }
        let reversed = Array(naturals.reversed())
        let anchorIndex = reversed.firstIndex(of: 64) ?? 0 // E4
        return reversed.enumerated().map { i, midi in
            StaffRow(midi: midi, isLine: (((reversed.count - 1 - i) - anchorIndex) % 2 + 2) % 2 == 0)
        }
    }()

    private static let trebleTop = rows.firstIndex { $0.midi == 77 }! // F5
    private static let trebleBottom = rows.firstIndex { $0.midi == 64 }! // E4
    private static let bassTop = rows.firstIndex { $0.midi == 57 }! // A3
    private static let bassBottom = rows.firstIndex { $0.midi == 43 }! // G2
    private static let g4Row = rows.firstIndex { $0.midi == 67 }! // G4 — treble clef curls around this line
    private static let f3Row = rows.firstIndex { $0.midi == 53 }! // F3 — bass clef's two dots straddle this line

    private static let noteNames = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    private static func rowIndex(forPitch pitch: Int) -> Int? {
        let pc = ((pitch % 12) + 12) % 12
        let name = noteNames[pc]
        let naturalMidi = pitch - (name.count > 1 ? (name.contains("#") ? 1 : -1) : 0)
        return rows.firstIndex { $0.midi == naturalMidi }
    }

    /// Ledger lines needed between the staff and a given row — walks outward from whichever
    /// staff edge the row is beyond (or, for a row between the two staves, from the treble's
    /// own bottom line), collecting every LINE-parity position along the way.
    private static func ledgerRows(for rowIndex: Int) -> [Int] {
        var ledger: [Int] = []
        if rowIndex < trebleTop {
            for i in stride(from: trebleTop - 1, through: rowIndex, by: -1) where rows[i].isLine { ledger.append(i) }
        } else if rowIndex > bassBottom {
            for i in stride(from: bassBottom + 1, through: rowIndex, by: 1) where rows[i].isLine { ledger.append(i) }
        } else if rowIndex > trebleBottom && rowIndex < bassTop {
            for i in stride(from: trebleBottom + 1, through: rowIndex, by: 1) where rows[i].isLine { ledger.append(i) }
        }
        return ledger
    }

    // MARK: - Drawing constants (mirrors StaticAssets.swift's own STAFF_* constants)

    private static let baseRowHeight: CGFloat = 9
    private static let baseMarginTop: CGFloat = 46
    private static let baseMarginBottom: CGFloat = 32
    private static let baseClefFontSizeG: CGFloat = 84
    private static let baseClefFontSizeF: CGFloat = 58
    // How far below their own reference row the clef glyphs' baseline sits — proportionally
    // larger for the bass clef, since feedback confirmed it needed a much bigger correction
    // than the treble clef despite both starting from the same (too-small) offset.
    private static let baseClefGDy: CGFloat = 22
    private static let baseClefFDy: CGFloat = 34
    private static let baseNoteRX: CGFloat = 9
    private static let baseNoteRY: CGFloat = 7.5

    private var rowHeight: CGFloat { Self.baseRowHeight * heightScale }
    private var marginTop: CGFloat { Self.baseMarginTop * heightScale }
    private var marginBottom: CGFloat { Self.baseMarginBottom * heightScale }
    private var clefFontSizeG: CGFloat { Self.baseClefFontSizeG * heightScale }
    private var clefFontSizeF: CGFloat { Self.baseClefFontSizeF * heightScale }
    private var clefGDy: CGFloat { Self.baseClefGDy * heightScale }
    private var clefFDy: CGFloat { Self.baseClefFDy * heightScale }
    private var noteRX: CGFloat { Self.baseNoteRX * heightScale }
    private var noteRY: CGFloat { Self.baseNoteRY * heightScale }

    private static let linesLeftX: CGFloat = 4
    // Reduced from the original 78/104 (stavesX/firstColX) — per feedback that the notation
    // was too wide, with the single proposed-chord note column sitting far closer to the
    // right edge than to the clef. `marginRight` was bumped up to compensate so the note
    // column now sits roughly equidistant between the clef's own right edge and the staff's
    // right edge, instead of hugging one side. Width is deliberately NOT scaled by
    // `heightScale` — only asked to change the height.
    private static let stavesX: CGFloat = 48
    private static let colWidth: CGFloat = 44
    private static let firstColX: CGFloat = stavesX + 20
    private static let marginRight: CGFloat = 28

    private func y(_ row: Int) -> CGFloat { marginTop + CGFloat(row) * rowHeight }

    public var body: some View {
        let filteredEvents = events.filter { !$0.pitches.isEmpty }
        let height = marginTop + marginBottom + CGFloat(Self.rows.count - 1) * rowHeight
        let width = Self.firstColX + CGFloat(max(filteredEvents.count - 1, 0)) * Self.colWidth + Self.marginRight
        Canvas { context, size in
            draw(events: filteredEvents, in: context, size: size)
        }
        .frame(width: width, height: height)
    }

    private func draw(events: [StaffEvent], in context: GraphicsContext, size: CGSize) {
        for i in Self.trebleTop...Self.trebleBottom where Self.rows[i].isLine {
            drawLine(context: context, y: y(i), x1: Self.linesLeftX, x2: size.width - 4)
        }
        for i in Self.bassTop...Self.bassBottom where Self.rows[i].isLine {
            drawLine(context: context, y: y(i), x1: Self.linesLeftX, x2: size.width - 4)
        }
        context.draw(
            Text("\u{1D11E}").font(.system(size: clefFontSizeG)).foregroundStyle(.primary),
            at: CGPoint(x: Self.linesLeftX, y: y(Self.g4Row) + clefGDy), anchor: .bottomLeading
        )
        context.draw(
            Text("\u{1D122}").font(.system(size: clefFontSizeF)).foregroundStyle(.primary),
            at: CGPoint(x: Self.linesLeftX, y: y(Self.f3Row) + clefFDy), anchor: .bottomLeading
        )

        for (colIndex, event) in events.enumerated() {
            let tones = Set(event.chordTones)
            let held = event.pitches.compactMap { pitch -> (pitch: Int, row: Int)? in
                guard let row = Self.rowIndex(forPitch: pitch) else { return nil }
                return (pitch, row)
            }
            // A run of several consecutive seconds needs a proper zigzag, not just "shift
            // every note that has one above it" — walking top-to-bottom and only shifting a
            // note when its immediate upstairs neighbor exists AND wasn't itself shifted
            // reproduces the standard alternating-seconds engraving.
            var shiftByRow: [Int: Bool] = [:]
            var previousRow: Int?
            var previousShifted = false
            for n in held.sorted(by: { $0.row < $1.row }) {
                let shift = previousRow != nil && n.row - previousRow! == 1 && !previousShifted
                shiftByRow[n.row] = shift
                previousRow = n.row
                previousShifted = shift
            }
            let colX = Self.firstColX + CGFloat(colIndex) * Self.colWidth
            for n in held {
                let pc = ((n.pitch % 12) + 12) % 12
                let color: Color
                if let root = event.chordRoot, pc == root { color = colorScheme.chordRoot }
                else if tones.contains(pc) { color = colorScheme.chordTone }
                else if event.chordRoot != nil { color = colorScheme.heldOutsideChord }
                else { color = .primary }
                let cx = colX + (shiftByRow[n.row] == true ? 20 : 0)
                for li in Self.ledgerRows(for: n.row) {
                    drawLine(context: context, y: y(li), x1: cx - 12, x2: cx + 12)
                }
                let name = Self.noteNames[pc]
                if name.count > 1 {
                    let glyph = name.contains("#") ? "\u{266F}" : "\u{266D}"
                    context.draw(
                        Text(glyph).font(.system(size: 14)).foregroundStyle(color),
                        at: CGPoint(x: cx - 18, y: y(n.row)), anchor: .center
                    )
                }
                let noteRect = CGRect(x: cx - noteRX, y: y(n.row) - noteRY, width: noteRX * 2, height: noteRY * 2)
                context.fill(Path(ellipseIn: noteRect), with: .color(color))
            }
        }
    }

    private func drawLine(context: GraphicsContext, y: CGFloat, x1: CGFloat, x2: CGFloat) {
        var path = Path()
        path.move(to: CGPoint(x: x1, y: y))
        path.addLine(to: CGPoint(x: x2, y: y))
        context.stroke(path, with: .color(.primary), lineWidth: 1)
    }

    /// Builds the Guide panel's own "proposed chord" snapshot: `tones` (pitch classes,
    /// already including the root as offset 0) stacked as a close-position voicing from
    /// middle C upward — mirrors `StaticAssets.swift`'s own `chordStaffEvent`. Every chord
    /// template's intervals are guaranteed < 12 (no chord spans more than an octave), so
    /// `(pc - root) % 12` recovers each tone's exact semitone offset from the root with no
    /// ambiguity, letting every tone be placed relative to one fixed anchor octave (60 =
    /// middle C) with no real per-note octave data needed.
    public static func chordEvent(root: Int, tones: [Int]) -> StaffEvent {
        let rootMidi = 60 + root
        let pitches = tones.map { pc in rootMidi + (((pc - root) % 12) + 12) % 12 }
        return StaffEvent(pitches: pitches, chordRoot: root, chordTones: tones)
    }

    /// One column per pitch class, each in the next octave above the previous (see
    /// `PitchSequencing.ascendingPitches`) — a sequence of individual notes (a scale run), as
    /// opposed to `chordEvent(root:tones:)`'s single stacked-chord column. Used by the Mode
    /// Library (the mode's own notes in degree order) and the Progression Library (a bass-line
    /// preview), each column highlighting `chordRoot`/`chordTones` the same way a chord's own
    /// root/tones do.
    public static func ascendingSequence(pitchClasses: [Int], chordRoot: Int?, chordTones: [Int], startingAbove floor: Int = 59) -> [StaffEvent] {
        PitchSequencing.ascendingPitches(forPitchClasses: pitchClasses, startingAbove: floor).map {
            StaffEvent(pitches: [$0], chordRoot: chordRoot, chordTones: chordTones)
        }
    }

    /// Same ascending placement as `ascendingSequence(pitchClasses:...)`, but keeps every pitch
    /// class in ONE column — the Chord Library's own inversion display (which tone sits lowest
    /// determines what the inversion actually sounds like, unlike `chordEvent`'s always-root
    /// position stacking).
    public static func ascendingVoicing(pitchClasses: [Int], chordRoot: Int?, chordTones: [Int], startingAbove floor: Int = 59) -> StaffEvent {
        StaffEvent(
            pitches: PitchSequencing.ascendingPitches(forPitchClasses: pitchClasses, startingAbove: floor),
            chordRoot: chordRoot, chordTones: chordTones
        )
    }
}

#Preview {
    ChordStaffView(events: [ChordStaffView.chordEvent(root: 0, tones: [0, 4, 7, 11])])
        .padding()
}
