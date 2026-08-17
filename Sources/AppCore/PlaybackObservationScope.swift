/// Which of a piece's tracks Music Lab (Théorie) should observe while it's playing —
/// `ImprovSession.piecePlaybackObservationScope`'s own value type. Deliberately NOT a `TrackID`
/// case: `TrackID` is the identity for a real input/output track with a sampler, network
/// identity, and scene-role persistence, none of which apply to "which of a Piece's tracks to
/// read notes from during playback" — see `ImprovSession.theoryDisplayState`'s own doc comment
/// for the fuller reasoning.
public enum PlaybackObservationScope: Equatable, Sendable {
    /// Every track combined — `ImprovSession.playbackHeldPitches`, the union across the whole piece.
    case wholePiece
    /// Only these track names (matching `Track.name`, `RenderedNote.trackName`) — the union of
    /// `ImprovSession.playbackHeldPitchesByTrack` for just the ones in this set.
    case tracks(Set<String>)
}
