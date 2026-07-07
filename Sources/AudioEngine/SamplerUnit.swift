import AVFoundation

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

    /// Same three formats `PiecePlayer.loadSample` supports.
    public func loadSample(at url: URL, program: UInt8 = 0) throws {
        switch url.pathExtension.lowercased() {
        case "sf2", "dls":
            try sampler.loadSoundBankInstrument(
                at: url,
                program: program,
                bankMSB: UInt8(kAUSampler_DefaultMelodicBankMSB),
                bankLSB: UInt8(kAUSampler_DefaultBankLSB)
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
