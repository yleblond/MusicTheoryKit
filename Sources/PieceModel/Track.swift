import Foundation
import SoundFontModel

/// One instrument's part within a `Section`. Harmony (mode, chord progression) is shared
/// at the section level; only the actual note content is per-track.
public struct Track: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var instrument: String   // free-form for now (e.g. General MIDI program name, later)
    /// Which preset within `instrument`, when it names a multi-preset `.sf2` (see
    /// `SoundFontPresetReader`) — `nil` means the file's own default sound, same as every
    /// track saved before multi-preset support existed.
    public var instrumentPreset: SoundFontPresetIdentity?
    public var melodyEvents: [MelodyEvent]
    public var fragmentPlacements: [FragmentPlacement]

    public init(
        id: String = UUID().uuidString,
        name: String,
        instrument: String,
        instrumentPreset: SoundFontPresetIdentity? = nil,
        melodyEvents: [MelodyEvent] = [],
        fragmentPlacements: [FragmentPlacement] = []
    ) {
        self.id = id
        self.name = name
        self.instrument = instrument
        self.instrumentPreset = instrumentPreset
        self.melodyEvents = melodyEvents
        self.fragmentPlacements = fragmentPlacements
    }
}
