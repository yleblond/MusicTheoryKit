import Foundation

/// ANSI colors used on the keyboard: a held note explained by no chord at all (too few
/// notes, or nothing recognized), a held note that IS accompanied by a recognized chord
/// but isn't itself part of it, a recognized chord's root vs. its other tones, and the
/// mode-membership marker row.
enum KeyboardColor {
    static let reset = "\u{1B}[0m"
    static let heldNoChord = "\u{1B}[1;37m"      // bold white
    static let heldOutsideChord = "\u{1B}[1;32m" // bold green
    static let chordRoot = "\u{1B}[1;35m"        // bold magenta
    static let chordTone = "\u{1B}[1;33m"        // bold yellow
    static let modeMarker = "\u{1B}[1;36m"       // bold cyan
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
/// unhighlighted. `modeMarker` marks which pitch classes (0...11, repeating every octave)
/// belong to the current mode, using "▬" — a standalone rectangle glyph, not a box-drawing
/// character — so consecutive marked notes read as separate dashes, not one continuous
/// joined line. The marker row is always drawn (blank where nothing matches when the
/// default `{ _ in false }` is used, e.g. no mode detected yet) rather than being omitted —
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
    modeMarker: (Int) -> Bool = { _ in false },
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

            markerRow += modeMarker(semitone) ? "\(KeyboardColor.modeMarker)▬\(KeyboardColor.reset)" : " "

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
