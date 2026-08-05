import Foundation

/// A chord quality as a pitch-class set relative to its root.
public struct ChordTemplate: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let intervalsFromRoot: [Int]

    public init(id: String, intervalsFromRoot: [Int]) {
        self.id = id
        self.intervalsFromRoot = intervalsFromRoot
    }
}

/// Starting vocabulary: the chord qualities named in the "Chords" column of the scale
/// library (all 7th chords, so every scale is tied to at least one recognizable chord),
/// plus the four basic triads. The triads matter for recognition: without them, a bare
/// major/minor/diminished/augmented triad has no exact match and gets force-fit into the
/// nearest 7th chord (e.g. a plain C-E-G reported as "CMa7"). "7alt" and "6#5" are
/// intentionally omitted from the 7th chords: their tensions vary and they are not a
/// single fixed pitch-class set.
///
/// Beyond this seed, the Chord Library feature lets a `chords.json` file (migrated once into
/// SwiftData by `AppCore`, see `ChordTemplateFile`) add further qualities at runtime via
/// `register(_:)` — `byID(_:)`/`allChords(forRoot:)` always see the merged catalog.
public enum ChordVocabulary {
    public static let seed: [ChordTemplate] = [
        ChordTemplate(id: "Ma", intervalsFromRoot: [0, 4, 7]),
        ChordTemplate(id: "mi", intervalsFromRoot: [0, 3, 7]),
        ChordTemplate(id: "dim", intervalsFromRoot: [0, 3, 6]),
        ChordTemplate(id: "aug", intervalsFromRoot: [0, 4, 8]),
        ChordTemplate(id: "Ma7", intervalsFromRoot: [0, 4, 7, 11]),
        ChordTemplate(id: "mi7", intervalsFromRoot: [0, 3, 7, 10]),
        ChordTemplate(id: "mi7b5", intervalsFromRoot: [0, 3, 6, 10]),
        ChordTemplate(id: "7", intervalsFromRoot: [0, 4, 7, 10]),
        ChordTemplate(id: "Ma7#5", intervalsFromRoot: [0, 4, 8, 11]),
        ChordTemplate(id: "miMa7", intervalsFromRoot: [0, 3, 7, 11]),
        ChordTemplate(id: "dim7", intervalsFromRoot: [0, 3, 6, 9]),
        ChordTemplate(id: "7#5", intervalsFromRoot: [0, 4, 8, 10]),
        ChordTemplate(id: "7b5", intervalsFromRoot: [0, 4, 6, 10]),
        // Added for the Chord Library (2026-08): sus/added-note/6th/9th qualities, plus the
        // power chord — common enough to belong in the core seed rather than left to
        // `chords.json` extension only.
        ChordTemplate(id: "5", intervalsFromRoot: [0, 7]),
        ChordTemplate(id: "sus2", intervalsFromRoot: [0, 2, 7]),
        ChordTemplate(id: "sus4", intervalsFromRoot: [0, 5, 7]),
        ChordTemplate(id: "6", intervalsFromRoot: [0, 4, 7, 9]),
        ChordTemplate(id: "mi6", intervalsFromRoot: [0, 3, 7, 9]),
        ChordTemplate(id: "add9", intervalsFromRoot: [0, 4, 7, 14]),
        ChordTemplate(id: "miAdd9", intervalsFromRoot: [0, 3, 7, 14]),
        ChordTemplate(id: "9", intervalsFromRoot: [0, 4, 7, 10, 14]),
        ChordTemplate(id: "Ma9", intervalsFromRoot: [0, 4, 7, 11, 14]),
        ChordTemplate(id: "mi9", intervalsFromRoot: [0, 3, 7, 10, 14]),
    ]

    private static let lock = NSLock()
    /// Populated once from `seed`, then merged with anything `register(_:)` adds — see this
    /// type's own doc comment. `nonisolated(unsafe)`: every access is gated by `lock`, same
    /// pattern `LLMEngine.APIKeyStore.overridesByEnvVar` already uses for its own shared
    /// mutable state.
    nonisolated(unsafe) private static var byIDLookup: [String: ChordTemplate] = Dictionary(
        uniqueKeysWithValues: seed.map { ($0.id, $0) }
    )

    /// All ids currently known, seed + registered, in the order first seen — lets a caller
    /// enumerate "every chord quality" (e.g. the Chord Library's quality list) without
    /// depending on `seed` alone once user-added qualities exist. Guarded by `lock`, same as
    /// `byIDLookup`.
    nonisolated(unsafe) private static var allIDsInOrder: [String] = seed.map(\.id)

    public static func byID(_ id: String) -> ChordTemplate? {
        lock.lock()
        defer { lock.unlock() }
        return byIDLookup[id]
    }

    /// Every id currently known, seed + registered, in the order first seen.
    public static func allIDs() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return allIDsInOrder
    }

    /// Merges `templates` into the catalog — a template whose `id` already exists (e.g. a
    /// `chords.json` entry re-declaring a seeded quality) overwrites the existing definition
    /// rather than being skipped, so a user can locally override a seeded interval set too.
    /// Called once by `AppCore` after its `chords.json`/SwiftData migration; safe to call
    /// again (e.g. in a test) since it's purely additive/overwriting, never destructive.
    public static func register(_ templates: [ChordTemplate]) {
        lock.lock()
        defer { lock.unlock() }
        for template in templates {
            if byIDLookup[template.id] == nil {
                allIDsInOrder.append(template.id)
            }
            byIDLookup[template.id] = template
        }
    }

    /// Restores the catalog to just `seed`, discarding anything `register(_:)` added — for test
    /// isolation only. `register(_:)` mutates genuinely global, process-wide state (by design,
    /// so a migrated `chords.json` quality is visible everywhere without threading a session
    /// through every call site), which means a test that calls it (directly, or indirectly via
    /// a JSON migration) MUST reset afterward or it silently leaks into unrelated tests sharing
    /// the same process — confirmed the hard way (a scale-migration test corrupting an
    /// unrelated `ScaleLibraryTests` family-size assertion) before this existed.
    static func resetForTesting() {
        lock.lock()
        defer { lock.unlock() }
        byIDLookup = Dictionary(uniqueKeysWithValues: seed.map { ($0.id, $0) })
        allIDsInOrder = seed.map(\.id)
    }

    /// Every chord quality currently known (seed + registered) anchored on the same root — the
    /// full set of "extensions" (7th, sus, etc.) reachable from one fundamental, for a UI that
    /// lets a chord's quality be changed without touching its root (see the Guide's
    /// chord-progression editor, and the Chord Library's quality picker).
    public static func allChords(forRoot root: PitchClass) -> [Chord] {
        allIDs().compactMap(byID).map { Chord(root: root, template: $0) }
    }
}

/// A chord template anchored to a root — the object actually played/detected/suggested.
public struct Chord: Equatable, Sendable {
    public let root: PitchClass
    public let template: ChordTemplate

    public init(root: PitchClass, template: ChordTemplate) {
        self.root = root
        self.template = template
    }

    public var pitchClasses: [PitchClass] {
        template.intervalsFromRoot.map { root + $0 }
    }

    public var pitchClassSet: Set<PitchClass> {
        Set(pitchClasses)
    }

    public var displayName: String {
        "\(root.name())\(template.id)"
    }
}
