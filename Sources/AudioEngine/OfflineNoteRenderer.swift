import AVFoundation
import SoundFontModel

public enum OfflineNoteRenderError: Error {
    case unsupportedExtension(String)
    case renderingFailed
}

/// Renders a single SF2/DLS/aupreset note through `AVAudioUnitSampler` in OFFLINE (non-realtime)
/// mode and returns the captured mono PCM samples — the missing piece that makes it possible to
/// analyze an instrument's own REAL spectrum (via `FFTPitchAnalyzer.dominantPartials`) instead of
/// an idealized harmonic approximation. Every other SF2 playback path in this app
/// (`SamplerUnit`/`PiecePlayer`) is realtime-only, connected straight to the hardware output —
/// nothing captures a PCM buffer today, hence this dedicated, offscreen renderer. Not
/// `Sendable`/thread-shared by design: a fresh instance per analysis, unlike `SamplerUnit` which
/// is deliberately long-lived and shared across concurrent callbacks.
public final class OfflineNoteRenderer {
    private let engine = AVAudioEngine()
    private let sampler = AVAudioUnitSampler()
    public let sampleRate: Double

    /// No `PlaybackAudioSession.activateIfNeeded()` here (unlike `SamplerUnit`/`PiecePlayer`) —
    /// manual rendering mode never touches the hardware output or the shared `AVAudioSession`,
    /// so there's nothing to activate.
    public init(sampleRate: Double = 44100) throws {
        self.sampleRate = sampleRate
        engine.attach(sampler)
        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2) else {
            throw OfflineNoteRenderError.renderingFailed
        }
        engine.connect(sampler, to: engine.mainMixerNode, format: format)
        try engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 4096)
        try engine.start()
    }

    /// Same three formats `SamplerUnit.loadSample(at:preset:)` supports, same API — duplicated
    /// rather than shared since that method operates on `SamplerUnit`'s own private `sampler`,
    /// not this type's.
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
            throw OfflineNoteRenderError.unsupportedExtension(url.pathExtension)
        }
    }

    /// Renders `pitch` (+ a fine `cents` offset, same pitch-bend mechanism
    /// `SamplerUnit.startNote(pitch:velocity:channel:cents:)` uses) for `durationSeconds`, and
    /// returns the captured mono samples (channel 0 only — an instrument voice through
    /// `AVAudioUnitSampler` is already dual-mono/centered, so the second channel carries no
    /// extra information for spectral analysis). Skips no samples itself — callers doing FFT
    /// analysis should discard the attack transient (the first ~150-200ms) themselves and
    /// analyze a steady-state window, same as `FFTPitchAnalyzer` expects for a clean read.
    public func renderNote(pitch: Int, velocity: Int = 100, cents: Double = 0, durationSeconds: Double = 1.0) throws -> [Float] {
        let totalFrames = AVAudioFrameCount((durationSeconds * sampleRate).rounded(.up))
        var samples = [Float]()
        samples.reserveCapacity(Int(totalFrames))

        if cents != 0 {
            sampler.sendPitchBend(SamplerUnit.pitchBendValue(forCents: cents), onChannel: 0)
        }
        sampler.startNote(Self.clampedByte(pitch), withVelocity: Self.clampedByte(velocity), onChannel: 0)

        let renderBuffer = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: engine.manualRenderingMaximumFrameCount)!
        var renderedFrames: AVAudioFrameCount = 0
        while renderedFrames < totalFrames {
            let framesToRender = min(engine.manualRenderingMaximumFrameCount, totalFrames - renderedFrames)
            let status = try engine.renderOffline(framesToRender, to: renderBuffer)
            switch status {
            case .success:
                guard let channelData = renderBuffer.floatChannelData else { throw OfflineNoteRenderError.renderingFailed }
                samples.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: Int(renderBuffer.frameLength)))
                renderedFrames += renderBuffer.frameLength
            case .insufficientDataFromInputNode:
                // No input node feeds this engine (sampler-only graph) — shouldn't occur, but
                // treat as "nothing more to render" rather than spinning forever.
                renderedFrames = totalFrames
            case .cannotDoInCurrentContext:
                continue // transient — retry the same chunk
            case .error:
                throw OfflineNoteRenderError.renderingFailed
            @unknown default:
                throw OfflineNoteRenderError.renderingFailed
            }
        }
        sampler.stopNote(Self.clampedByte(pitch), onChannel: 0)
        return samples
    }

    private static func clampedByte(_ value: Int) -> UInt8 {
        UInt8(clamping: max(0, min(127, value)))
    }
}
