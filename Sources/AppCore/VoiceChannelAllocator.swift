/// Assigns each currently-held MIDI pitch on a track its own MIDI channel, so
/// `SamplerUnit.startNote(pitch:velocity:channel:cents:)` can bend each simultaneously-held note
/// independently — `AVAudioUnitSampler` only exposes a per-CHANNEL pitch bend, never a true
/// per-note one, so per-voice tuning requires one channel per voice.
///
/// Channels 1-15 are up for grabs (15 simultaneously-tuned voices per track); channel 0 is
/// reserved as the untuned default every other code path already uses. On overflow (a 16th note
/// while all 15 are taken), `channel(forPitch:)` returns `0` — that voice simply plays untuned
/// rather than stealing another voice's channel (per explicit product decision: in Music Lab's
/// single-instrument context, >15 simultaneously held notes is effectively never going to happen,
/// so a channel-stealing policy would add real complexity for a case that doesn't occur).
final class VoiceChannelAllocator {
    private var channelByPitch: [Int: Int] = [:]
    private var freeChannels: [Int] = Array((1...15).reversed())

    /// The channel to use for `pitch` — allocates a fresh one on first use, returns the same
    /// channel on repeat calls for a pitch that's still held (so `release(pitch:)` can find it
    /// again at note-off).
    func channel(forPitch pitch: Int) -> Int {
        if let existing = channelByPitch[pitch] { return existing }
        guard let channel = freeChannels.popLast() else { return 0 }
        channelByPitch[pitch] = channel
        return channel
    }

    /// Returns `pitch`'s channel to the pool and reports which channel that was — `nil` (and a
    /// no-op) if `pitch` was never allocated one (e.g. it played untuned on channel 0, or was
    /// already released). Callers use the returned channel to send the matching note-off on the
    /// exact channel the note-on used.
    @discardableResult
    func release(pitch: Int) -> Int? {
        guard let channel = channelByPitch.removeValue(forKey: pitch) else { return nil }
        freeChannels.append(channel)
        return channel
    }
}
