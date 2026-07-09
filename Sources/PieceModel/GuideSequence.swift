import MusicTheoryKit

/// A user-authored ordered list of mode "steps" to navigate live (see
/// `ImprovSession.startGuide`/`advanceGuideStep`) — deliberately NOT a `Piece`: a guide step
/// is only "which mode are we in", with no tempo, tracks, timing, or chord progression.
public struct GuideSequence: Codable, Equatable, Sendable {
    public var title: String
    public var steps: [ModeReference]

    public init(title: String, steps: [ModeReference] = []) {
        self.title = title
        self.steps = steps
    }
}
