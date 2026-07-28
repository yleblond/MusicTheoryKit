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

    public func startNote(pitch: Int, velocity: Int, channel: Int = 0) {
        sampler.startNote(Self.clampedByte(pitch), withVelocity: Self.clampedByte(velocity), onChannel: Self.clampedByte(channel))
    }

    public func stopNote(pitch: Int, channel: Int = 0) {
        sampler.stopNote(Self.clampedByte(pitch), onChannel: Self.clampedByte(channel))
    }

    /// Linear 0...1, applied to this instance's own dedicated `mainMixerNode` — safe to change
    /// without affecting any other track, since each `SamplerUnit` owns its own `AVAudioEngine`.
    public func setVolume(_ volume: Float) {
        engine.mainMixerNode.outputVolume = max(0, min(1, volume))
    }

    /// Mirrors `setVolume(_:)` — lets a caller verify a freshly created/reused instance
    /// actually carries the volume it's supposed to, rather than silently sitting at
    /// whatever `AVAudioEngine` itself defaults a new `mainMixerNode` to.
    public var volume: Float { engine.mainMixerNode.outputVolume }

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
