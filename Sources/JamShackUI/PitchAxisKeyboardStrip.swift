import SwiftUI

/// Draws a small chromatic keyboard strip aligned to a PITCH-LINEAR x-axis spanning
/// `[axisMinPitch, axisMaxPitch]` — see `SpectrumView`'s own doc comment for why a spectrum's
/// x-axis (and this strip beneath it) must be linear in pitch (log-frequency), not Hz, to stay
/// aligned. Factored out of `SpectrumView` so `NoteSpectrumView` (the Dissonances screen's
/// per-tone partial spectra) can share the exact same keyboard-strip rendering rather than
/// re-deriving it, with one difference: `markedPitches` is a per-pitch COLOR map here (a mic
/// spectroscope marks every detected pitch the same accent color; a multi-tone display marks
/// each of its own tones in that tone's own distinct color instead).
struct PitchAxisKeyboardStrip {
    let axisMinPitch: Double
    let axisMaxPitch: Double
    let lowestKey: Int
    let highestKey: Int
    let markedPitches: [Int: Color]

    /// White keys actually join beneath the black keys — see the original `SpectrumView`
    /// implementation this was extracted from for the exact separator-placement reasoning
    /// (natural-note-pair boundaries, not per-semitone).
    func draw(in context: GraphicsContext, size: CGSize) {
        guard axisMaxPitch > axisMinPitch, lowestKey <= highestKey else { return }

        func x(forPitch pitch: Double) -> CGFloat {
            CGFloat((pitch - axisMinPitch) / (axisMaxPitch - axisMinPitch)) * size.width
        }
        func isSharp(_ pitch: Int) -> Bool {
            [1, 3, 6, 8, 10].contains(((pitch % 12) + 12) % 12)
        }

        let blackKeyHeight = size.height * 0.62

        context.fill(Path(CGRect(x: 0, y: 0, width: size.width, height: size.height)), with: .color(.white.opacity(0.92)))

        for pitch in lowestKey...highestKey where !isSharp(pitch) {
            guard let color = markedPitches[pitch] else { continue }
            let left = x(forPitch: Double(pitch) - 0.5)
            let right = x(forPitch: Double(pitch) + 0.5)
            context.fill(Path(CGRect(x: left, y: 0, width: right - left, height: size.height)), with: .color(color))
        }

        let naturalPitches = (lowestKey...highestKey).filter { !isSharp($0) }
        for (a, b) in zip(naturalPitches, naturalPitches.dropFirst()) {
            let gap = b - a
            let boundaryPitch: Double
            let fullHeight: Bool
            switch gap {
            case 1: boundaryPitch = Double(a) + 0.5; fullHeight = true // E-F / B-C: no black key between
            case 2: boundaryPitch = Double(a) + 1.0; fullHeight = false // meet at the center of the black key between them
            default: continue
            }
            let boundaryX = x(forPitch: boundaryPitch)
            var line = Path()
            line.move(to: CGPoint(x: boundaryX, y: fullHeight ? 0 : blackKeyHeight))
            line.addLine(to: CGPoint(x: boundaryX, y: size.height))
            context.stroke(line, with: .color(.black.opacity(0.25)), lineWidth: 0.5)
        }

        for pitch in lowestKey...highestKey where ((pitch % 12) + 12) % 12 == 0 {
            let left = x(forPitch: Double(pitch) - 0.5)
            let right = x(forPitch: Double(pitch) + 0.5)
            let label = Text("C\(pitch / 12 - 1)").font(.system(size: 8)).foregroundStyle(.black.opacity(0.7))
            context.draw(context.resolve(label), at: CGPoint(x: (left + right) / 2, y: size.height - 8))
        }

        for pitch in lowestKey...highestKey where isSharp(pitch) {
            let slotLeft = x(forPitch: Double(pitch) - 0.5)
            let slotRight = x(forPitch: Double(pitch) + 0.5)
            let slotWidth = slotRight - slotLeft
            let inset = slotWidth * 0.16
            let rect = CGRect(x: slotLeft + inset, y: 0, width: slotWidth - inset * 2, height: blackKeyHeight)
            let fillColor = markedPitches[pitch] ?? Color.black.opacity(0.88)
            context.fill(Path(rect), with: .color(fillColor))
        }
    }
}
