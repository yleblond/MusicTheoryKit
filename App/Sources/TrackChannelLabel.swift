import AppCore
import Localization

extension ImprovSession {
    /// `track.label` with its MIDI channel appended as a reminder when one is known and
    /// meaningful (see `displayedChannel(for:)`) — unchanged for a non-MIDI track or one
    /// whose channel hasn't been observed yet.
    func labelWithChannel(_ track: TrackInfo) -> String {
        guard let channel = displayedChannel(for: track) else { return track.label }
        return L10n.string(.appFormatCanalMidi, currentLanguage, track.label, channel + 1)
    }
}
