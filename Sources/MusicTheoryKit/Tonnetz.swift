/// A node in the harmonic lattice — `q` counts perfect-fifth steps (+7 semitones each), `r`
/// counts major-third steps (+4 semitones each) from some tile's own origin. The minor-third
/// relation (the third side of every triangle, since 4+3=7) falls out for free from `q`/`r`
/// alone — no third axis is needed.
public struct TonnetzCoordinate: Hashable, Sendable {
    public let q: Int
    public let r: Int

    public init(q: Int, r: Int) {
        self.q = q
        self.r = r
    }
}

/// Which of the two triangles sharing a `TonnetzCoordinate` anchor a `TonnetzTriad` picks —
/// see `Tonnetz.nodes(ofQuality:anchoredAt:)`'s own doc comment for the exact node sets.
public enum TonnetzTriadQuality: String, Codable, Sendable {
    case major, minor
}

/// A major or minor triad, both by its musical identity (`root`/`quality`) and by where it
/// physically sits in the lattice (`coordinate`, its anchor node) — the anchor is needed
/// because the same `(root, quality)` pair can legitimately recur at multiple coordinates in an
/// unbounded lattice (see `Tonnetz.coordinate(forRoot:in:origin:)` for picking one to render).
public struct TonnetzTriad: Equatable, Sendable {
    public let coordinate: TonnetzCoordinate
    public let quality: TonnetzTriadQuality
    public let root: PitchClass

    public init(coordinate: TonnetzCoordinate, quality: TonnetzTriadQuality, root: PitchClass) {
        self.coordinate = coordinate
        self.quality = quality
        self.root = root
    }
}

/// The Tonnetz (harmonic lattice): triangular tiling where fifths run along one axis, major
/// thirds along another, and every triangle is a triad. Two callers read this same geometry two
/// ways — `pitchClass(at:origin:)` collapses it to the 12 pitch classes (mod 12, for the
/// harmonic/"Pitch Class Tonnetz" view), `midiPitch(at:origin:)` reads it as real, unbounded
/// pitches (for the performance/"Registered Tonnetz" view, windowed locally by its own caller).
public enum Tonnetz {
    /// The pitch class at `coordinate`, `origin` semitones/pitch-classes away from `(0,0)`
    /// (default: C). Collapses the lattice mod 12 — every pitch class recurs at infinitely many
    /// coordinates.
    public static func pitchClass(at coordinate: TonnetzCoordinate, origin: PitchClass = PitchClass(0)) -> PitchClass {
        origin + (7 * coordinate.q + 4 * coordinate.r)
    }

    /// The absolute MIDI pitch at `coordinate`, with `(0,0)` anchored at `origin` (default:
    /// middle C, 60) — the SAME `q`/`r` arithmetic as `pitchClass(at:origin:)`, just without the
    /// mod-12 collapse. Two distinct coordinates land on the same absolute pitch only 4 fifths +
    /// 7 major-thirds apart (`7*4 + 4*(-7) == 0`) — far outside any locally-rendered window, so
    /// callers never need to de-duplicate nodes in practice.
    public static func midiPitch(at coordinate: TonnetzCoordinate, origin: Int = 60) -> Int {
        origin + 7 * coordinate.q + 4 * coordinate.r
    }

    /// The 3 coordinates forming the `quality` triangle anchored at `coordinate` — every
    /// coordinate is simultaneously the root of a major triangle (toward `+q,+r`) and a minor
    /// triangle (toward `+q,-r`), so one anchor convention serves both qualities:
    /// - major: `{ anchor, anchor+(1,0) [+7 = fifth], anchor+(0,1) [+4 = major third] }`
    /// - minor: `{ anchor, anchor+(1,-1) [+3 = minor third], anchor+(1,0) [+7 = fifth] }`
    public static func nodes(ofQuality quality: TonnetzTriadQuality, anchoredAt coordinate: TonnetzCoordinate) -> [TonnetzCoordinate] {
        switch quality {
        case .major:
            return [coordinate, TonnetzCoordinate(q: coordinate.q + 1, r: coordinate.r), TonnetzCoordinate(q: coordinate.q, r: coordinate.r + 1)]
        case .minor:
            return [coordinate, TonnetzCoordinate(q: coordinate.q + 1, r: coordinate.r - 1), TonnetzCoordinate(q: coordinate.q + 1, r: coordinate.r)]
        }
    }

    /// The triad anchored at `coordinate` — convenience combining `nodes(ofQuality:anchoredAt:)`
    /// (for rendering) with the root pitch class (for musical identity/matching).
    public static func triad(quality: TonnetzTriadQuality, anchoredAt coordinate: TonnetzCoordinate, origin: PitchClass = PitchClass(0)) -> TonnetzTriad {
        TonnetzTriad(coordinate: coordinate, quality: quality, root: pitchClass(at: coordinate, origin: origin))
    }

    /// Parallel (major⟷minor, same root) — pivots on the shared root-fifth edge, so only the
    /// third vertex changes (`anchor+(0,1)` for major becomes `anchor+(1,-1)` for minor, or vice
    /// versa — see `nodes(ofQuality:anchoredAt:)`); the anchor coordinate itself never moves.
    public static func parallel(of triad: TonnetzTriad) -> TonnetzTriad {
        TonnetzTriad(coordinate: triad.coordinate, quality: triad.quality == .major ? .minor : .major, root: triad.root)
    }

    /// Relative (major(R)⟷minor(R+9), i.e. minor(R)⟷major(R-9)=major(R+3)) — pivots on the
    /// shared root-third edge.
    public static func relative(of triad: TonnetzTriad) -> TonnetzTriad {
        switch triad.quality {
        case .major:
            return TonnetzTriad(coordinate: TonnetzCoordinate(q: triad.coordinate.q - 1, r: triad.coordinate.r + 1), quality: .minor, root: triad.root + 9)
        case .minor:
            return TonnetzTriad(coordinate: TonnetzCoordinate(q: triad.coordinate.q + 1, r: triad.coordinate.r - 1), quality: .major, root: triad.root + 3)
        }
    }

    /// Leittonwechsel/leading-tone exchange (major(R)⟷minor(R+4), minor(R)⟷major(R-4)) — pivots
    /// on the shared third-fifth edge.
    public static func leadingToneExchange(of triad: TonnetzTriad) -> TonnetzTriad {
        switch triad.quality {
        case .major:
            return TonnetzTriad(coordinate: TonnetzCoordinate(q: triad.coordinate.q, r: triad.coordinate.r + 1), quality: .minor, root: triad.root + 4)
        case .minor:
            return TonnetzTriad(coordinate: TonnetzCoordinate(q: triad.coordinate.q, r: triad.coordinate.r - 1), quality: .major, root: triad.root + (-4))
        }
    }

    /// The 12-cell fundamental domain (`q` in 0...3, `r` in 0...2 — one coordinate per pitch
    /// class, no repeats) plus a 1-cell padding halo, so every primary node's 6 triangle
    /// neighbors are also present in `primary + halo` for rendering. A halo coordinate always
    /// repeats some primary coordinate's own pitch class — never a distinct musical identity.
    public static func paddedTile(origin: PitchClass = PitchClass(0)) -> (primary: [TonnetzCoordinate], halo: [TonnetzCoordinate]) {
        let primary = (0..<4).flatMap { q in (0..<3).map { r in TonnetzCoordinate(q: q, r: r) } }
        let padded = (-1..<5).flatMap { q in (-1..<4).map { r in TonnetzCoordinate(q: q, r: r) } }
        let primarySet = Set(primary)
        let halo = padded.filter { !primarySet.contains($0) }
        return (primary, halo)
    }

    /// Every `(root, quality)` triad whose pitch-class set is a superset of
    /// `heldPitchClasses` — for exactly 2 held notes (e.g. a root+fifth dyad) this can
    /// legitimately return both the major and minor candidate sharing that dyad; for 3 held
    /// notes forming an exact triad, at most one match is possible (no two distinct
    /// `(root, quality)` pairs share a pitch-class set, and a superset of 3 notes by a 3-note
    /// set is necessarily that exact set). Empty for fewer than 2 or more than 3 held notes.
    public static func matchingTriads(forHeldPitchClasses heldPitchClasses: Set<PitchClass>) -> [(root: PitchClass, quality: TonnetzTriadQuality)] {
        guard heldPitchClasses.count >= 2, heldPitchClasses.count <= 3 else { return [] }
        var matches: [(root: PitchClass, quality: TonnetzTriadQuality)] = []
        for rootValue in 0..<12 {
            let root = PitchClass(rootValue)
            for (quality, templateID) in [(TonnetzTriadQuality.major, "Ma"), (.minor, "mi")] {
                guard let template = ChordVocabulary.byID(templateID) else { continue }
                let pitchClassSet = Chord(root: root, template: template).pitchClassSet
                if heldPitchClasses.isSubset(of: pitchClassSet) {
                    matches.append((root, quality))
                }
            }
        }
        return matches
    }

    /// A coordinate among `coordinates` whose pitch class equals `root` — `nil` if `root` isn't
    /// represented at all. Callers rendering a tile should pass primary coordinates before halo
    /// ones (e.g. `primary + halo`) so a primary node is preferred when both exist.
    public static func coordinate(forRoot root: PitchClass, in coordinates: [TonnetzCoordinate], origin: PitchClass = PitchClass(0)) -> TonnetzCoordinate? {
        coordinates.first { pitchClass(at: $0, origin: origin) == root }
    }
}
