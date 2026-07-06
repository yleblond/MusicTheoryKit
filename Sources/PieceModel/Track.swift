import Foundation

/// One instrument's part within a `Section`. Harmony (mode, chord progression) is shared
/// at the section level; only the actual note content is per-track.
public struct Track: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var instrument: String   // free-form for now (e.g. General MIDI program name, later)
    public var melodyEvents: [MelodyEvent]
    public var fragmentPlacements: [FragmentPlacement]

    public init(
        id: String = UUID().uuidString,
        name: String,
        instrument: String,
        melodyEvents: [MelodyEvent] = [],
        fragmentPlacements: [FragmentPlacement] = []
    ) {
        self.id = id
        self.name = name
        self.instrument = instrument
        self.melodyEvents = melodyEvents
        self.fragmentPlacements = fragmentPlacements
    }
}
