import Foundation

public enum PlayingStyle: String, Codable, Sendable {
    case simultaneous
    case arpeggioUp
    case arpeggioDown
    case strum
}

/// A chord instance placed on the timeline, independent of any melodic content.
public struct ChordEvent: Codable, Identifiable, Equatable, Sendable {
    public var id: String
    public var measure: Int          // 1-based
    public var beat: Double          // 1-based position within the measure
    public var durationBeats: Double
    public var chord: ChordReference
    public var inversion: Int        // 0 = root position, 1 = first inversion...
    public var bassOverride: Int?    // explicit bass pitch class, for slash chords
    public var playingStyle: PlayingStyle

    public init(
        id: String = UUID().uuidString,
        measure: Int,
        beat: Double,
        durationBeats: Double,
        chord: ChordReference,
        inversion: Int = 0,
        bassOverride: Int? = nil,
        playingStyle: PlayingStyle = .simultaneous
    ) {
        self.id = id
        self.measure = measure
        self.beat = beat
        self.durationBeats = durationBeats
        self.chord = chord
        self.inversion = inversion
        self.bassOverride = bassOverride
        self.playingStyle = playingStyle
    }
}
