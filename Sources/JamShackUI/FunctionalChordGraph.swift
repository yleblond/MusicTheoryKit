import SwiftUI
import AppCore
import MusicTheoryKit
import Localization

/// Fixed fill colors per `ModalFunctionalRole` — same green/amber/orange-red/blue mapping in
/// both graphs and the legend, so a user can carry the association from one to the other.
public enum FunctionalRoleColors {
    public static func fill(for role: ModalFunctionalRole) -> Color {
        switch role {
        case .home: return Color(hex: "#2e7d32")
        case .away: return Color(hex: "#f9a825")
        case .tension: return Color(hex: "#e64a19")
        case .neutral: return Color(hex: "#1565c0")
        }
    }

    /// `.away`'s amber fill is the only one light enough to need dark text for contrast.
    public static func textColor(for role: ModalFunctionalRole) -> Color {
        role == .away ? .black : .white
    }

    /// Independent of role — see `ModalChordFunction.isModalCharacteristic`'s own doc comment
    /// for why this is never used as a fill color.
    public static let modalCharacteristicAccent = Color(hex: "#8e24aa")
}

/// The single source for a `ModalFunctionalRole`'s display name — used by the legend, the
/// selected-chord detail line, and each graph's own VoiceOver summary, so all three always agree.
public func functionalRoleLabel(_ role: ModalFunctionalRole, language: AppLanguage) -> String {
    switch role {
    case .home: return L10n.string(.appRoleHome, language)
    case .away: return L10n.string(.appRoleAway, language)
    case .tension: return L10n.string(.appRoleTension, language)
    case .neutral: return L10n.string(.appRoleNeutral, language)
    }
}

/// A plain-text stand-in for a `ModeFunctionalMap`, read by VoiceOver on each graph as a single
/// element (see `FunctionalOrbitGraphView`/`FunctionalAttractionGraphView`'s own
/// `.accessibilityLabel`) — `Canvas` exposes nothing to accessibility on its own, and giving each
/// node its own tappable accessibility element would need an invisible overlay of real views
/// matching the Canvas layout exactly; this is the pragmatic middle ground: everything the graph
/// shows visually is still available as text, just not navigable chord-by-chord yet.
public func functionalMapAccessibilitySummary(_ map: ModeFunctionalMap, notationStyle: any NotationStyle, language: AppLanguage) -> String {
    map.chords.map { chordFunction in
        let name = chordFunction.reference.resolve().map { notationStyle.displayName(for: $0) } ?? "?"
        let role = functionalRoleLabel(chordFunction.role, language: language)
        let modal = chordFunction.isModalCharacteristic ? ", \(L10n.string(.appLabelCaracteristiqueModale, language))" : ""
        return "\(name): \(role)\(modal)"
    }.joined(separator: "; ")
}

/// A `ChordNode`'s current display state — `hovered`/`dimmed` are macOS/visionOS-only in
/// practice (no hover on iOS), but the type stays platform-neutral.
public enum FunctionalNodeState: Equatable {
    case normal, hovered, selected, dimmed
}

/// Where each of a `ModeFunctionalMap`'s 7 chords sits, in a shared normalized coordinate space
/// (center = tonic, radius 0...1) — computed ONCE and handed to both graphs so their layouts
/// stay visually identical (per the original spec: "le layout des accords doit rester autant que
/// possible similaire entre les deux graphes afin que le cerveau conserve ses repères").
public struct FunctionalNodePosition: Identifiable {
    public let degree: Int
    public let position: CGPoint
    public var id: Int { degree }
}

public enum FunctionalGraphLayout {
    /// Degree 1 (the tonic) always sits dead center; every other chord's radius comes straight
    /// from its own `functionalIntensity` (see `ModalFunctionalMapBuilder`'s own doc comment for
    /// how that's computed) — angle is assigned evenly by degree order purely to keep nodes from
    /// overlapping, with no theoretical meaning of its own (explicitly allowed by the spec this
    /// was built from).
    public static func positions(for map: ModeFunctionalMap) -> [FunctionalNodePosition] {
        let minRadius: CGFloat = 0.22
        let maxRadius: CGFloat = 0.98
        let others = map.chords.filter { $0.degree != 1 }
        var result = [FunctionalNodePosition(degree: 1, position: .zero)]
        for (index, chord) in others.enumerated() {
            let radius = minRadius + CGFloat(chord.functionalIntensity) * (maxRadius - minRadius)
            let angle = (2 * .pi * Double(index)) / Double(max(others.count, 1)) - .pi / 2
            let point = CGPoint(x: radius * CGFloat(cos(angle)), y: radius * CGFloat(sin(angle)))
            result.append(FunctionalNodePosition(degree: chord.degree, position: point))
        }
        return result
    }
}

/// Major/minor/diminished/augmented, derived straight from a resolved chord's own triad
/// intervals (indices 1/2 of `ChordTemplate.intervalsFromRoot` — third/fifth — regardless of any
/// extension beyond that, e.g. a 7th) — self-contained rather than depending on any of the
/// several OTHER "quality" derivations already scattered through this app for their own narrower
/// purposes (none of which is public from here).
public enum TriadQuality { case major, minor, diminished, augmented }

public func triadQuality(of chord: Chord) -> TriadQuality {
    let intervals = chord.template.intervalsFromRoot
    guard intervals.count >= 3 else { return .major }
    let third = intervals[1], fifth = intervals[2]
    if third == 3 && fifth == 6 { return .diminished }
    if third == 4 && fifth == 8 { return .augmented }
    return third == 3 ? .minor : .major
}

private let romanNumeralBases = ["I", "II", "III", "IV", "V", "VI", "VII"]

/// "I"/"i"/"vii°" style roman-numeral label for a 1-based diatonic degree + quality — case marks
/// major vs. minor/diminished, "°" marks diminished specifically, same convention used throughout
/// this app's own chord-progression text (`RomanNumeralChord`).
public func romanNumeral(degree: Int, quality: TriadQuality) -> String {
    let wrapped = ((degree - 1) % 7 + 7) % 7
    let base = romanNumeralBases[wrapped]
    switch quality {
    case .major, .augmented: return base
    case .minor: return base.lowercased()
    case .diminished: return base.lowercased() + "\u{b0}"
    }
}

/// Draws one chord node into `context` — the shared visual vocabulary both
/// `FunctionalOrbitGraphView` and `FunctionalAttractionGraphView` use, so a node looks and
/// behaves identically in either graph (per this feature's own "keep the layout/vocabulary
/// consistent across both graphs" goal).
public enum FunctionalChordNodeDrawing {
    public static func draw(
        in context: GraphicsContext, center: CGPoint, baseRadius: CGFloat,
        chord: ModalChordFunction, name: String, romanNumeral: String, state: FunctionalNodeState
    ) {
        context.drawLayer { layer in
            layer.opacity = state == .dimmed ? 0.32 : 1.0
            let scale: CGFloat = chord.degree == 1 ? 1.35 : (state == .selected || state == .hovered ? 1.15 : 1.0)
            let radius = baseRadius * scale
            let rect = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
            let path = Path(ellipseIn: rect)
            layer.fill(path, with: .color(FunctionalRoleColors.fill(for: chord.role)))
            layer.stroke(path, with: .color(.black.opacity(0.35)), lineWidth: 1)
            if state == .selected {
                layer.stroke(path, with: .color(.white), lineWidth: 3)
            }
            if chord.isModalCharacteristic {
                let haloRect = rect.insetBy(dx: -4, dy: -4)
                layer.stroke(Path(ellipseIn: haloRect), with: .color(FunctionalRoleColors.modalCharacteristicAccent), lineWidth: 2.5)
                let badgeCenter = CGPoint(x: center.x + radius * 0.72, y: center.y - radius * 0.72)
                layer.fill(diamondPath(center: badgeCenter, half: 6), with: .color(FunctionalRoleColors.modalCharacteristicAccent))
                layer.stroke(diamondPath(center: badgeCenter, half: 6), with: .color(.white), lineWidth: 1)
            }
            let textColor = FunctionalRoleColors.textColor(for: chord.role)
            layer.draw(Text(name).font(.system(size: 13, weight: .bold)).foregroundStyle(textColor), at: CGPoint(x: center.x, y: center.y - 6))
            layer.draw(Text(romanNumeral).font(.system(size: 10, design: .serif)).foregroundStyle(textColor.opacity(0.85)), at: CGPoint(x: center.x, y: center.y + 8))
        }
    }

    /// The node's own footprint at `state`, for hit-testing — mirrors the scale factor `draw`
    /// itself applies, so a tap registers against exactly what's drawn.
    public static func hitRadius(baseRadius: CGFloat, degree: Int, state: FunctionalNodeState) -> CGFloat {
        baseRadius * (degree == 1 ? 1.35 : (state == .selected || state == .hovered ? 1.15 : 1.0))
    }

    private static func diamondPath(center: CGPoint, half: CGFloat) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: center.x, y: center.y - half))
        path.addLine(to: CGPoint(x: center.x + half, y: center.y))
        path.addLine(to: CGPoint(x: center.x, y: center.y + half))
        path.addLine(to: CGPoint(x: center.x - half, y: center.y))
        path.closeSubpath()
        return path
    }
}
