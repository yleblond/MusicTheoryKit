import AppCore
import Foundation

/// ANSI colors used on the keyboard: a held note explained by no chord at all (too few
/// notes, or nothing recognized), a held note that IS accompanied by a recognized chord
/// but isn't itself part of it, a recognized chord's root vs. its other tones, and the
/// Guide screen's mode keyboard's root vs. every other in-mode note.
///
/// `heldNoChord`/`heldOutsideChord`/`chordRoot`/`chordTone`/`modeRoot`/`modeOther` read live
/// from `session.noteColorSettings` (`Sources/AppCore/NoteColorSettings.swift`) — see that
/// type's own doc comment for why they're 24-bit truecolor now instead of the fixed 16-color
/// codes these used to be hardcoded as, and why `degreeColors` below is deliberately NOT
/// included (a separate, more involved system, left for later).
enum KeyboardColor {
    static let reset = "\u{1B}[0m"
    static var heldNoChord: String { ansi(session.noteColorSettings.heldNoChordHex) }
    static var heldOutsideChord: String { ansi(session.noteColorSettings.heldOutsideChordHex) }
    static var chordRoot: String { ansi(session.noteColorSettings.chordRootHex) }
    static var chordTone: String { ansi(session.noteColorSettings.chordToneHex) }
    static var modeRoot: String { ansi(session.noteColorSettings.modeRootHex) }
    static var modeOther: String { ansi(session.noteColorSettings.modeOtherHex) }

    /// One color per scale degree (index 0 = degree 1 ... index 6 = degree 7) for the
    /// mode degree-line — 256-color ANSI, deliberately distinct from the basic-16-color
    /// root/tone/outside highlights above (which can appear on the same frame) so a
    /// degree-line color is never mistaken for a chord-highlight color. Not yet part of
    /// `NoteColorSettingsFile` — see this enum's own doc comment.
    static let degreeColors: [String] = [
        "\u{1B}[1;38;5;208m", // 1 tonic — orange
        "\u{1B}[1;38;5;39m",  // 2 — sky blue
        "\u{1B}[1;38;5;205m", // 3 — hot pink
        "\u{1B}[1;38;5;141m", // 4 — lavender
        "\u{1B}[1;38;5;202m", // 5 — red-orange
        "\u{1B}[1;38;5;75m",  // 6 — light blue
        "\u{1B}[1;38;5;245m", // 7 — grey (deliberately desaturated)
    ]

    /// `#RRGGBB` -> bold 24-bit-truecolor ANSI foreground — `reset` (i.e. no visible
    /// highlight) for anything that doesn't parse, rather than crashing on a hand-edited
    /// `note-colors.json` with a typo'd hex value.
    private static func ansi(_ hex: String) -> String {
        guard let (r, g, b) = LumiColorHex.rgb(hex) else { return reset }
        return "\u{1B}[1;38;2;\(r);\(g);\(b)m"
    }
}

private let blackSemitones: Set<Int> = [1, 3, 6, 8, 10]
private let whiteLetters: [Int: String] = [2: "D", 4: "E", 5: "F", 7: "G", 9: "A", 11: "B"]
/// A lighter, dotted separator between E and F: the one white-key boundary with no black
/// key to visually break it up, unlike every other pair of adjacent white keys.
private let eToFSeparator = "\u{1B}[2m┊\u{1B}[0m"

/// Draws an ASCII piano spanning `octaveCount` octaves from `startMIDI` (should land on a
/// C), 1 character per semitone — kept deliberately narrow (~14 columns/octave) so the
/// widest row in the whole `console` frame still comfortably fits an ordinary terminal
/// width without wrapping; a previous 2-characters-per-semitone version (~26/octave, ~78
/// total for 3 octaves) was wide enough to wrap in some terminals, which broke this
/// renderer's line-by-line cursor positioning and looked like flicker at the end of each row.
///
/// `blackZoneRows` is the upper band where both black and white keys are visible;
/// `whiteZoneRows` is the lower band where only white keys reach (black keys are shorter,
/// same as on a real keyboard) — white key cells are drawn through *every* row of both
/// bands so a highlighted white key reads as one solid column, not just a sliver at the
/// bottom. This app's own keyboards use `blackZoneRows: 2, whiteZoneRows: 1` — 3 rows total,
/// black keys spanning the top 2, white keys spanning all 3 (a real keyboard's proportions,
/// deliberately not a taller `2/2` — the extra white-only row it would add reads as wasted
/// height without making anything easier to see).
///
/// `colorFor` maps an absolute MIDI pitch to an ANSI color prefix, or nil to leave it
/// unhighlighted. `modeMarker` gives the scale-degree role (1-7) and color of each pitch
/// class (0...11, repeating every octave) that belongs to the current mode, or nil for a
/// pitch class outside it — the marker row shows that colored digit above the note instead
/// of a uniform mark, so the degree-line conveys *which* degree each note is, not just
/// membership. The marker row is always drawn (blank where nothing matches when the
/// default `{ _ in nil }` is used, e.g. no mode detected yet) rather than being omitted —
/// an omitted row used to shift the keyboard, and everything below it, up and down as mode
/// detection came and went, which read as another kind of flicker.
///
/// Octave boundaries are marked with "|"; the label row shows the white-key letters, with
/// the octave number (not the letter "C") at each C so the octave zones stay easy to spot.
func renderKeyboard(
    startMIDI: Int,
    octaveCount: Int,
    blackZoneRows: Int = 1,
    whiteZoneRows: Int = 1,
    modeMarker: (Int) -> (degree: Int, color: String)? = { _ in nil },
    colorFor: (Int) -> String?
) -> [String] {
    var rows = Array(repeating: "", count: blackZoneRows + whiteZoneRows)
    var markerRow = ""
    var labelRow = ""

    for octave in 0..<octaveCount {
        let octaveBase = startMIDI + octave * 12
        for semitone in 0..<12 {
            let pitch = octaveBase + semitone
            let color = colorFor(pitch)
            let isBlack = blackSemitones.contains(semitone)
            let blackCell = color.map { "\($0)▓\(KeyboardColor.reset)" } ?? "▓"
            let whiteCell = color.map { "\($0)░\(KeyboardColor.reset)" } ?? "░"

            for r in 0..<blackZoneRows { rows[r] += isBlack ? blackCell : whiteCell }
            for r in 0..<whiteZoneRows { rows[blackZoneRows + r] += isBlack ? " " : whiteCell }

            markerRow += modeMarker(semitone).map { "\($0.color)\($0.degree)\(KeyboardColor.reset)" } ?? " "

            if isBlack {
                labelRow += " "
            } else if semitone == 0 {
                labelRow += String(octaveBase / 12 - 1) // the octave number, in place of "C"
            } else {
                labelRow += whiteLetters[semitone] ?? " "
            }

            if semitone == 4 { // just finished E; about to start F
                for r in rows.indices { rows[r] += eToFSeparator }
                markerRow += eToFSeparator
                labelRow += eToFSeparator
            }
        }
        for r in rows.indices { rows[r] += "|" }
        markerRow += "|"
        labelRow += "|"
    }

    var result = [markerRow]
    result.append(contentsOf: rows)
    result.append(labelRow)
    return result
}
