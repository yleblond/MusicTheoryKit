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
    /// per explicit user request.
    public let heightScale: CGFloat
    /// Scales every WIDTH-affecting dimension (column spacing, margins, ledger-line/accidental
    /// offsets) uniformly, independent of `heightScale` — e.g. a narrower sidebar column asked
    /// for 0.7 to fit tighter next to a keyboard. Glyph/font sizes (clef, accidentals, note
    /// heads) are NOT scaled by this — only the spacing between them — so symbols stay
    /// legible/undistorted, just packed closer together.
    public let widthScale: CGFloat
    /// Draws a translucent accent-colored band behind this column (index into `events` as
    /// passed to `init` — every event this view is actually used with has a non-empty
    /// `pitches`, so this lines up with the post-filter column the event ends up drawn in;
    /// see `body`'s own `filteredEvents`) — the Progression Library's "which chord is
    /// currently playing" indicator, kept in sync with playback by the caller.
    public let highlightedIndex: Int?
    /// When set, sharps/flats are drawn once at the clef (standard engraving) instead of next
    /// to every affected note — any note whose pitch class isn't covered by the signature still
    /// gets its own inline accidental, same as before. `nil` (the default) keeps the original
    /// per-note-accidental behavior, unchanged for every existing call site.
    public let keySignature: MajorKeySignature?
    /// Forces the drawn width to fit at least this many columns, even if `events` (after the
    /// empty-`pitches` filter) has fewer — lets two staffs with different event counts (e.g. the
    /// Mode Library's own scale staff vs. its diatonic-chords staff) render at the same total
    /// length by each passing the other's count. 0 (the default) never widens anything, so every
    /// existing call site is unaffected.
    public let minimumColumnCount: Int
    /// Fires with the tapped column's index into the filtered `events` (same indexing
    /// `highlightedIndex` uses) — x-position only, any y within the view counts, since columns
    /// are already visually separated. `nil` (the default) attaches no gesture at all.
    public let onColumnTap: ((Int) -> Void)?

    public init(
        events: [StaffEvent], colorScheme: PitchKeyboardColorScheme = PitchKeyboardColorScheme(),
        heightScale: CGFloat = 1, widthScale: CGFloat = 1, highlightedIndex: Int? = nil, keySignature: MajorKeySignature? = nil,
        minimumColumnCount: Int = 0, onColumnTap: ((Int) -> Void)? = nil
    ) {
        self.events = events
        self.colorScheme = colorScheme
        self.heightScale = heightScale
        self.widthScale = widthScale
        self.highlightedIndex = highlightedIndex
        self.keySignature = keySignature
        self.minimumColumnCount = minimumColumnCount
        self.onColumnTap = onColumnTap
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

    /// The exact height a `ChordStaffView` renders at for a given `heightScale` — lets a
    /// sibling view (e.g. a keyboard placed next to it) match it exactly instead of guessing a
    /// fixed constant that could drift out of sync with this view's own geometry.
    public static func height(heightScale: CGFloat = 1) -> CGFloat {
        (baseMarginTop + baseMarginBottom) * heightScale + CGFloat(rows.count - 1) * baseRowHeight * heightScale
    }

    private var rowHeight: CGFloat { Self.baseRowHeight * heightScale }
    private var marginTop: CGFloat { Self.baseMarginTop * heightScale }
    private var marginBottom: CGFloat { Self.baseMarginBottom * heightScale }
    private var clefFontSizeG: CGFloat { Self.baseClefFontSizeG * heightScale }
    private var clefFontSizeF: CGFloat { Self.baseClefFontSizeF * heightScale }
    private var clefGDy: CGFloat { Self.baseClefGDy * heightScale }
    private var clefFDy: CGFloat { Self.baseClefFDy * heightScale }
    private var noteRX: CGFloat { Self.baseNoteRX * heightScale }
    private var noteRY: CGFloat { Self.baseNoteRY * heightScale }

    // Reduced from the original 78/104 (stavesX/firstColX) — per feedback that the notation
    // was too wide, with the single proposed-chord note column sitting far closer to the
    // right edge than to the clef. `marginRight` was bumped up to compensate so the note
    // column now sits roughly equidistant between the clef's own right edge and the staff's
    // right edge, instead of hugging one side.
    private static let baseLinesLeftX: CGFloat = 4
    private static let baseStavesX: CGFloat = 48
    private static let baseColWidth: CGFloat = 44
    /// The "+20" in the original fixed `firstColX = stavesX + 20` — kept as its own named
    /// constant now that `stavesX`/this offset both need to scale with `widthScale`.
    private static let baseFirstColXOffset: CGFloat = 20
    private static let baseMarginRight: CGFloat = 28
    private static let baseKeySignatureAccidentalWidth: CGFloat = 9
    private static let baseKeySignatureStartPadding: CGFloat = 6
    private static let baseLedgerHalfWidth: CGFloat = 12
    private static let baseZigzagShift: CGFloat = 20
    private static let baseAccidentalOffset: CGFloat = 13
    private static let baseLineRightMargin: CGFloat = 4

    private var linesLeftX: CGFloat { Self.baseLinesLeftX * widthScale }
    private var stavesX: CGFloat { Self.baseStavesX * widthScale }
    private var colWidth: CGFloat { Self.baseColWidth * widthScale }
    private var marginRight: CGFloat { Self.baseMarginRight * widthScale }
    private var keySignatureAccidentalWidth: CGFloat { Self.baseKeySignatureAccidentalWidth * widthScale }
    private var keySignatureStartPadding: CGFloat { Self.baseKeySignatureStartPadding * widthScale }
    private var ledgerHalfWidth: CGFloat { Self.baseLedgerHalfWidth * widthScale }
    private var zigzagShift: CGFloat { Self.baseZigzagShift * widthScale }
    private var accidentalOffset: CGFloat { Self.baseAccidentalOffset * widthScale }
    private var lineRightMargin: CGFloat { Self.baseLineRightMargin * widthScale }

    /// Standard engraving positions (MIDI pitch of the NATURAL note the glyph sits on — e.g.
    /// 77 = F5, the position an F# key-signature sharp is drawn at) for each clef, in the
    /// standard sharp order (F,C,G,D,A,E,B) / flat order (B,E,A,D,G,C,F) — universally-taught
    /// values, not derived from anything else in this file.
    private static let trebleKeySigSharpMidis = [77, 72, 79, 74, 69, 76, 71] // F5,C5,G5,D5,A4,E5,B4
    private static let trebleKeySigFlatMidis = [71, 76, 69, 74, 67, 72, 65]  // B4,E5,A4,D5,G4,C5,F4
    private static let bassKeySigSharpMidis = [53, 48, 55, 50, 45, 52, 47]   // F3,C3,G3,D3,A2,E3,B2
    private static let bassKeySigFlatMidis = [47, 52, 45, 50, 43, 48, 41]    // B2,E3,A2,D3,G2,C3,F2

    /// Extra room reserved right after the clef for the key-signature glyphs — 0 when
    /// `keySignature` is `nil`, so every existing call site's layout is unaffected.
    private var keySignatureWidth: CGFloat {
        guard let keySignature, keySignature.accidentalCount > 0 else { return 0 }
        return CGFloat(keySignature.accidentalCount) * keySignatureAccidentalWidth + keySignatureStartPadding
    }

    private var firstColX: CGFloat { stavesX + Self.baseFirstColXOffset * widthScale + keySignatureWidth }

    private func y(_ row: Int) -> CGFloat { marginTop + CGFloat(row) * rowHeight }

    public var body: some View {
        let filteredEvents = events.filter { !$0.pitches.isEmpty }
        let height = marginTop + marginBottom + CGFloat(Self.rows.count - 1) * rowHeight
        let columnCount = max(filteredEvents.count, minimumColumnCount)
        let width = firstColX + CGFloat(max(columnCount - 1, 0)) * colWidth + marginRight
        Canvas { context, size in
            if let highlightedIndex, filteredEvents.indices.contains(highlightedIndex) {
                let colX = firstColX + CGFloat(highlightedIndex) * colWidth
                let band = CGRect(x: colX - colWidth / 2, y: 0, width: colWidth, height: size.height)
                context.fill(Path(band), with: .color(Color.accentColor.opacity(0.18)))
            }
            draw(events: filteredEvents, in: context, size: size)
        }
        .frame(width: width, height: height)
        .contentShape(Rectangle())
        .onTapGesture { location in
            guard let onColumnTap else { return }
            let index = Int(((location.x - firstColX) / colWidth).rounded())
            guard filteredEvents.indices.contains(index) else { return }
            onColumnTap(index)
        }
    }

    private func draw(events: [StaffEvent], in context: GraphicsContext, size: CGSize) {
        for i in Self.trebleTop...Self.trebleBottom where Self.rows[i].isLine {
            drawLine(context: context, y: y(i), x1: linesLeftX, x2: size.width - lineRightMargin)
        }
        for i in Self.bassTop...Self.bassBottom where Self.rows[i].isLine {
            drawLine(context: context, y: y(i), x1: linesLeftX, x2: size.width - lineRightMargin)
        }
        context.draw(
            Text("\u{1D11E}").font(.system(size: clefFontSizeG)).foregroundStyle(.primary),
            at: CGPoint(x: linesLeftX, y: y(Self.g4Row) + clefGDy), anchor: .bottomLeading
        )
        context.draw(
            Text("\u{1D122}").font(.system(size: clefFontSizeF)).foregroundStyle(.primary),
            at: CGPoint(x: linesLeftX, y: y(Self.f3Row) + clefFDy), anchor: .bottomLeading
        )

        if let keySignature {
            drawKeySignature(keySignature, context: context)
        }

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
            let colX = firstColX + CGFloat(colIndex) * colWidth
            for n in held {
                let pc = ((n.pitch % 12) + 12) % 12
                let color: Color
                if let root = event.chordRoot, pc == root { color = colorScheme.chordRoot }
                else if tones.contains(pc) { color = colorScheme.chordTone }
                else if event.chordRoot != nil { color = colorScheme.heldOutsideChord }
                else { color = .primary }
                let cx = colX + (shiftByRow[n.row] == true ? zigzagShift : 0)
                for li in Self.ledgerRows(for: n.row) {
                    drawLine(context: context, y: y(li), x1: cx - ledgerHalfWidth, x2: cx + ledgerHalfWidth)
                }
                let name = Self.noteNames[pc]
                if name.count > 1 && !(keySignature?.affectedPitchClasses.contains(pc) ?? false) {
                    let glyph = name.contains("#") ? "\u{266F}" : "\u{266D}"
                    context.draw(
                        Text(glyph).font(.system(size: 19)).foregroundStyle(color),
                        at: CGPoint(x: cx - accidentalOffset, y: y(n.row)), anchor: .center
                    )
                }
                let noteRect = CGRect(x: cx - noteRX, y: y(n.row) - noteRY, width: noteRX * 2, height: noteRY * 2)
                context.fill(Path(ellipseIn: noteRect), with: .color(color))
            }
        }
    }

    /// Draws the sharp/flat glyphs once, right after the clefs, at their standard engraving
    /// positions in both staves — see `trebleKeySigSharpMidis`/etc.'s own doc comment.
    private func drawKeySignature(_ keySignature: MajorKeySignature, context: GraphicsContext) {
        let glyph: String
        let trebleMidis: [Int]
        let bassMidis: [Int]
        switch keySignature {
        case .sharps(let count):
            glyph = "\u{266F}"
            trebleMidis = Array(Self.trebleKeySigSharpMidis.prefix(count))
            bassMidis = Array(Self.bassKeySigSharpMidis.prefix(count))
        case .flats(let count):
            glyph = "\u{266D}"
            trebleMidis = Array(Self.trebleKeySigFlatMidis.prefix(count))
            bassMidis = Array(Self.bassKeySigFlatMidis.prefix(count))
        }
        for (clefMidis) in [trebleMidis, bassMidis] {
            for (index, midi) in clefMidis.enumerated() {
                guard let row = Self.rowIndex(forPitch: midi) else { continue }
                let x = stavesX + keySignatureStartPadding + CGFloat(index) * keySignatureAccidentalWidth
                context.draw(Text(glyph).font(.system(size: 14)).foregroundStyle(Color.primary), at: CGPoint(x: x, y: y(row)), anchor: .center)
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
    public static func chordEvent(root: Int, tones: [Int], octaveOffset: Int = 0) -> StaffEvent {
        let rootMidi = 60 + root + 12 * octaveOffset
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
