@preconcurrency import AVFoundation

public enum MicrophonePitchError: Error, CustomStringConvertible {
    case permissionDenied
    case engineStartFailed(Error)

    public var description: String {
        switch self {
        case .permissionDenied:
            return "microphone access was denied — grant it in System Settings > Privacy & Security > Microphone "
                + "for this terminal app (Terminal/iTerm/etc. — the permission is tied to whatever process launched "
                + "this binary, not the binary itself), then try again"
        case .engineStartFailed(let error):
            return "could not start the microphone input engine: \(error)"
        }
    }
}

/// Pitch detection from the default audio input device, via `FFTPitchAnalyzer`. Delivers
/// `([DetectedPitch], level: Float)` to `handler` roughly every `analysisWindowSize` samples
/// of input (~93ms at a typical 44.1kHz input rate, for the default window size) — a plain
/// non-overlapping window: simpler than a sliding one, at the cost of a coarser update
/// rate. The array is empty for silence/no clear pitch, one element for a single note, and
/// more than one when several simultaneous pitches were found (see
/// `FFTPitchAnalyzer.dominantFrequencies`'s doc comment for how reliable that is — a
/// heuristic, not real chord transcription). `level` (see `FFTPitchAnalyzer.rms(of:)`) is
/// reported on *every* call, even when the array is empty — comparing it against
/// `FFTPitchAnalyzer.minimumRMSForDetection` is how a caller tells "nothing is reaching the
/// microphone at all" (permission problem, wrong input device, muted) apart from "audio is
/// arriving but isn't a clear pitch" (below the detection floor, or a noisy/percussive sound).
///
/// **macOS-only as written.** `AVAudioEngine.inputNode` exists on iOS too, but iOS
/// additionally requires configuring and activating an `AVAudioSession` (input category,
/// microphone permission) before an input tap delivers anything — that setup isn't
/// implemented here, since this app is CLI-only (macOS) for now; a SwiftUI/iOS front-end
/// would need to add it.
public final class MicrophonePitchListener {
    public typealias Handler = ([DetectedPitch], Float) -> Void

    private let engine = AVAudioEngine()
    private let analyzer: FFTPitchAnalyzer
    private let analysisWindowSize: Int
    private let maxSimultaneousPitches: Int
    private var accumulated: [Float] = []
    private let handler: Handler

    public init(analysisWindowSize: Int = 4096, maxSimultaneousPitches: Int = 6, handler: @escaping Handler) {
        self.analysisWindowSize = analysisWindowSize
        self.maxSimultaneousPitches = maxSimultaneousPitches
        self.analyzer = FFTPitchAnalyzer(size: analysisWindowSize)
        self.handler = handler
    }

    /// Checks/requests microphone permission (blocking until the user answers a first-time
    /// system prompt, if one is shown), then starts capturing. Throws `.permissionDenied`
    /// rather than silently starting an engine that will only ever deliver zeroed buffers —
    /// `AVAudioEngine.start()` itself does **not** fail just because microphone access was
    /// denied, so without this check the symptom would be a listener that "works" (no
    /// thrown error) but never detects anything, with no indication why.
    public func start() throws {
        try Self.ensureMicrophonePermission()

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(analysisWindowSize), format: format) { [weak self] buffer, _ in
            self?.process(buffer: buffer, sampleRate: format.sampleRate)
        }
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw MicrophonePitchError.engineStartFailed(error)
        }
    }

    public func stop() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        accumulated.removeAll()
    }

    private static func ensureMicrophonePermission() throws {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return
        case .notDetermined:
            let semaphore = DispatchSemaphore(value: 0)
            nonisolated(unsafe) var granted = false
            AVCaptureDevice.requestAccess(for: .audio) { result in
                granted = result
                semaphore.signal()
            }
            semaphore.wait()
            guard granted else { throw MicrophonePitchError.permissionDenied }
        case .denied, .restricted:
            throw MicrophonePitchError.permissionDenied
        @unknown default:
            throw MicrophonePitchError.permissionDenied
        }
    }

    /// Runs on whichever thread AVAudioEngine delivers input buffers on. Accumulates
    /// samples until there are enough for one FFT window, analyzes, and consumes exactly
    /// that many (there can be more than one window's worth ready if a callback delivered
    /// an unusually large buffer, hence the `while`, not `if`).
    private func process(buffer: AVAudioPCMBuffer, sampleRate: Double) {
        guard let channelData = buffer.floatChannelData else { return }
        let frameCount = Int(buffer.frameLength)
        accumulated.append(contentsOf: UnsafeBufferPointer(start: channelData[0], count: frameCount))

        while accumulated.count >= analysisWindowSize {
            let window = Array(accumulated.prefix(analysisWindowSize))
            accumulated.removeFirst(analysisWindowSize)
            let level = FFTPitchAnalyzer.rms(of: window)
            let frequencies = analyzer.dominantFrequencies(in: window, sampleRate: sampleRate, maxPeaks: maxSimultaneousPitches)
            let pitches = frequencies.map { DetectedPitch(frequencyHz: $0, midiPitch: DetectedPitch.midiPitch(forFrequencyHz: $0)) }
            handler(pitches, level)
        }
    }
}
