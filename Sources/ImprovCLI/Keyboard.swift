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
private let whiteLetters: [Int: String] = [0: "C", 2: "D", 4: "E", 5: "F", 7: "G", 9: "A", 11: "B"]
/// A lighter, dotted separator between E and F: the one white-key boundary with no black
/// key to visually break it up, unlike every other pair of adjacent white keys.
private let eToFSeparator = "\u{1B}[2m┊\u{1B}[0m"

/// Draws an ASCII piano spanning `octaveCount` octaves from `startMIDI` (should land on a
/// C), 2 characters per semitone so nothing needs per-key variable widths to stay aligned.
///
/// `blackZoneRows` is the upper band where both black and white keys are visible;
/// `whiteZoneRows` is the lower band where only white keys reach (black keys are shorter,
/// same as on a real keyboard) — white key cells are drawn through *every* row of both
/// bands so a highlighted white key reads as one solid column, not just a sliver at the
/// bottom. Use `blackZoneRows: 2, whiteZoneRows: 2` for a taller, more keyboard-like look.
///
/// `colorFor` maps an absolute MIDI pitch to an ANSI color prefix, or nil to leave it
/// unhighlighted. `modeMarker`, if given, adds one row above everything else marking which
/// pitch classes (0...11, repeating every octave) belong to the current mode.
///
/// Octave boundaries are marked with "|" and labelled "C<n>" so the octave zones stay easy
/// to spot at a glance.
func renderKeyboard(
    startMIDI: Int,
    octaveCount: Int,
    blackZoneRows: Int = 1,
    whiteZoneRows: Int = 1,
    modeMarker: ((Int) -> Bool)? = nil,
    colorFor: (Int) -> String?
) -> [String] {
    var rows = Array(repeating: "", count: blackZoneRows + whiteZoneRows)
    var markerRow = modeMarker != nil ? "" : nil
    var labelRow = ""

    for octave in 0..<octaveCount {
        let octaveBase = startMIDI + octave * 12
        for semitone in 0..<12 {
            let pitch = octaveBase + semitone
            let color = colorFor(pitch)
            let isBlack = blackSemitones.contains(semitone)
            let blackCell = color.map { "\($0)▓▓\(KeyboardColor.reset)" } ?? "▓▓"
            let whiteCell = color.map { "\($0)░░\(KeyboardColor.reset)" } ?? "░░"

            for r in 0..<blackZoneRows { rows[r] += isBlack ? blackCell : whiteCell }
            for r in 0..<whiteZoneRows { rows[blackZoneRows + r] += isBlack ? "  " : whiteCell }

            if let modeMarker {
                markerRow! += modeMarker(semitone) ? "\(KeyboardColor.modeMarker)▪▪\(KeyboardColor.reset)" : "  "
            }

            if isBlack {
                labelRow += "  "
            } else {
                let letter = semitone == 0 ? "C\(octaveBase / 12 - 1)" : (whiteLetters[semitone] ?? "")
                labelRow += letter.padding(toLength: 2, withPad: " ", startingAt: 0)
            }

            if semitone == 4 { // just finished E; about to start F
                for r in rows.indices { rows[r] += eToFSeparator }
                if modeMarker != nil { markerRow! += eToFSeparator }
                labelRow += eToFSeparator
            }
        }
        for r in rows.indices { rows[r] += "|" }
        if modeMarker != nil { markerRow! += "|" }
        labelRow += "|"
    }

    var result = rows
    if let markerRow { result.insert(markerRow, at: 0) }
    result.append(labelRow)
    return result
}
