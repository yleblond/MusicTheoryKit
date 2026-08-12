import AVFoundation
import SoundFontModel

/// One `AVAudioUnitSampler` on its own dedicated `AVAudioEngine` — instrument loading plus
/// realtime note on/off, with no notion of a pre-authored score (see `PiecePlayer` for
/// that). Each live-input track that wants sound gets its own instance, so several tracks
/// can sound with genuinely different timbres at the same time — each engine opens its own
/// independent connection to the default output device.
///
/// `@unchecked Sendable`: `startNote`/`stopNote` are called from several independent
/// `DispatchQueue.global().asyncAfter` callbacks (per-note playback scheduling in
/// `PiecePlayer`/`ImprovSession`), same as `AVAudioUnitSampler`'s own note on/off calls are
/// already relied on to be safe from any thread — this type adds no additional mutable
/// state of its own beyond what `AVAudioUnitSampler`/`AVAudioEngine` already guarantee.
public final class SamplerUnit: @unchecked Sendable {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()

    public init() {
        engine.attach(sampler)
        engine.connect(sampler, to: engine.mainMixerNode, format: nil)
    }

    public func start() throws {
        PlaybackAudioSession.activateIfNeeded()
        try engine.start()
    }

    public func stop() {
        engine.stop()
    }

    /// Whether this unit's own `AVAudioEngine` is actually running — `startNote`/`stopNote`
    /// are a silent no-op (no error, no sound) on a stopped engine, so callers that reuse an
    /// existing `SamplerUnit` need this to tell "silently dead" apart from "working".
    public var isRunning: Bool { engine.isRunning }

    public func startNote(pitch: Int, velocity: Int, channel: Int = 0) {
        sampler.startNote(Self.clampedByte(pitch), withVelocity: Self.clampedByte(velocity), onChannel: Self.clampedByte(channel))
    }

    /// Same as `startNote(pitch:velocity:channel:)`, plus a small pitch correction (a fraction of
    /// a semitone) sent as a MIDI pitch bend on `channel` right before the note-on — the closest
    /// thing to "per-voice fine tuning" `AVAudioUnitSampler` allows, since its pitch bend is
    /// per-CHANNEL, never per-note (see `VoiceChannelAllocator`, which is what makes giving each
    /// simultaneously-held note its own channel here actually work for a whole chord at once).
    /// Distinct name/signature from the 3-argument overload above rather than a default
    /// parameter, so every existing call site is untouched — this is purely additive.
    public func startNote(pitch: Int, velocity: Int, channel: Int, cents: Double) {
        sampler.sendPitchBend(Self.pitchBendValue(forCents: cents), onChannel: Self.clampedByte(channel))
        sampler.startNote(Self.clampedByte(pitch), withVelocity: Self.clampedByte(velocity), onChannel: Self.clampedByte(channel))
    }

    /// Converts a cents offset into a 14-bit MIDI pitch bend value (0...16383, 8192 = center/no
    /// bend), assuming `AVAudioUnitSampler`'s default pitch-bend sensitivity of ±2 semitones (the
    /// General MIDI default — this wrapper never sends an RPN 0/0 message to change it, so the
    /// default is what's actually in effect). Clamped to ±200 cents (1 semitone) well inside that
    /// ±2-semitone range, more than enough for any historical temperament's largest deviation.
    static func pitchBendValue(forCents cents: Double) -> UInt16 {
        let clampedCents = max(-200, min(200, cents))
        let bendRangeSemitones = 2.0
        let fraction = (clampedCents / 100) / bendRangeSemitones
        let value = 8192 + Int((fraction * 8191).rounded())
        return UInt16(max(0, min(16383, value)))
    }

    public func stopNote(pitch: Int, channel: Int = 0) {
        sampler.stopNote(Self.clampedByte(pitch), onChannel: Self.clampedByte(channel))
    }

    /// Linear 0...1, applied to this instance's own dedicated `mainMixerNode` — safe to change
    /// without affecting any other track, since each `SamplerUnit` owns its own `AVAudioEngine`.
    public func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, volume))
    }

    /// Same three formats `PiecePlayer.loadSample` supports. `preset` selects which instrument
    /// inside a multi-preset `.sf2` to load (see `SoundFontPresetReader`) — `nil` keeps the
    /// previous behavior of always loading program 0 in the default GM melodic bank (still the
    /// only sound in a single-preset `.sf2`/`.dls`).
    public func loadSample(at url: URL, preset: SoundFontPresetIdentity? = nil) throws {
        switch url.pathExtension.lowercased() {
        case "sf2", "dls":
            try sampler.loadSoundBankInstrument(
                at: url,
                program: preset?.samplerProgram ?? 0,
                bankMSB: preset?.bankMSB ?? UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: preset?.bankLSB ?? UInt8(kAUSampler_DefaultBankLSB)
            )
        case "aupreset":
            try sampler.loadInstrument(at: url)
        default:
            throw SampleLoadError.unsupportedExtension(url.pathExtension)
        }
    }

    private static func clampedByte(_ value: Int) -> UInt8 {
        UInt8(clamping: max(0, min(127, value)))
    }
}
