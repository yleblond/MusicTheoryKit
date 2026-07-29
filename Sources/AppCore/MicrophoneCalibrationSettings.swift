import AudioEngine
import SwiftData

/// Persisted two-point microphone level calibration: the raw RMS level (see
/// `FFTPitchAnalyzer.rms(of:)`) observed while playing a deliberately quiet note/sound and a
/// deliberately loud one, captured via `ImprovSession.beginMicrophoneCalibrationCapture`/
/// `endMicrophoneCalibrationCapture`. Used to rescale the "Niveau" meter shown while the
/// microphone track is listening (`MicrophoneControlsView`) into a range that's actually
/// meaningful for this microphone/room/instrument, instead of a fixed raw-RMS scale that reads
/// as barely-moving in a quiet room or pinned near the top in a loud one. Deliberately not
/// wired into the detection floor itself (`FFTPitchAnalyzer.minimumRMSForDetection` stays a
/// fixed global constant) — a first, simple pass, not a per-user detection retune.
///
/// Mirrors `LumiSettingsFile`'s "singleton value file" shape, persisted to
/// `microphone-calibration.json` in the settings folder the same way.
public struct MicrophoneCalibrationSettingsFile: Codable, Equatable {
    public var quietRMS: Float
    public var loudRMS: Float
    /// The peak FFT bin magnitude (see `FFTPitchAnalyzer.spectrumSnapshot`) actually observed
    /// during the quiet/loud capture, IF the spectroscope happened to be enabled at the time
    /// (`ImprovSession.storeMicrophoneSpectrum` opportunistically feeds this while a capture is
    /// in progress — no extra FFT cost, it's already computed whenever the spectroscope is on).
    /// `0` means "never captured with spectrum data" — use `estimatedQuietPeakMagnitude`/
    /// `estimatedLoudPeakMagnitude` below rather than these raw fields directly; they fall back
    /// to a real conversion, not an unstable live approximation, when this is 0.
    public var quietPeakMagnitude: Float
    public var loudPeakMagnitude: Float

    /// The value to actually use for the spectroscope's y-axis / threshold lines: the exact
    /// captured magnitude when available, otherwise a real conversion from the calibrated RMS
    /// via `FFTPitchAnalyzer.approximatePeakPowerPerSquaredRMS` — NOT the previous design's
    /// silent fallback to "just use whatever's loudest this frame," which is exactly the
    /// instability calibration exists to fix. Every calibration (even the untouched defaults)
    /// has a usable `quietRMS`/`loudRMS`, so these are always a real, non-zero number — the
    /// axis can be stable from the very first launch, before the user ever calibrates by hand.
    public var estimatedQuietPeakMagnitude: Float { quietPeakMagnitude > 0 ? quietPeakMagnitude : Self.estimatePeakMagnitude(fromRMS: quietRMS) }
    public var estimatedLoudPeakMagnitude: Float { loudPeakMagnitude > 0 ? loudPeakMagnitude : Self.estimatePeakMagnitude(fromRMS: loudRMS) }

    private static func estimatePeakMagnitude(fromRMS rms: Float) -> Float {
        Float(Double(rms) * Double(rms) * FFTPitchAnalyzer.approximatePeakPowerPerSquaredRMS)
    }

    /// Defaults (before the user ever calibrates) mirror the values this app already used
    /// un-calibrated: `FFTPitchAnalyzer.minimumRMSForDetection` for "quiet" and a plausible
    /// loud-signal RMS for "loud" — a reasonable starting range, not a real measurement. The
    /// peak-magnitude fields default to 0 ("unknown") since no spectrum has ever been captured.
    public init(
        quietRMS: Float = FFTPitchAnalyzer.minimumRMSForDetection, loudRMS: Float = 0.3,
        quietPeakMagnitude: Float = 0, loudPeakMagnitude: Float = 0
    ) {
        self.quietRMS = quietRMS
        self.loudRMS = loudRMS
        self.quietPeakMagnitude = quietPeakMagnitude
        self.loudPeakMagnitude = loudPeakMagnitude
    }

    /// Custom decoding so a `microphone-calibration.json` written before the peak-magnitude
    /// fields existed still loads — missing keys default to 0 ("unknown"), same convention
    /// `init(quietPeakMagnitude:loudPeakMagnitude:)` already uses.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        quietRMS = try container.decode(Float.self, forKey: .quietRMS)
        loudRMS = try container.decode(Float.self, forKey: .loudRMS)
        quietPeakMagnitude = try container.decodeIfPresent(Float.self, forKey: .quietPeakMagnitude) ?? 0
        loudPeakMagnitude = try container.decodeIfPresent(Float.self, forKey: .loudPeakMagnitude) ?? 0
    }

    /// Maps a raw RMS level onto 0...1 using this calibration's own quiet/loud range, clamped
    /// at both ends. `nil` for a degenerate range (`loudRMS <= quietRMS`, e.g. calibration was
    /// never run correctly) so the caller can fall back to an uncalibrated display instead of
    /// dividing by zero or showing an inverted meter.
    public func normalized(_ level: Float) -> Float? {
        guard loudRMS > quietRMS else { return nil }
        return min(1, max(0, (level - quietRMS) / (loudRMS - quietRMS)))
    }
}

/// The SwiftData-backed singleton counterpart of `MicrophoneCalibrationSettingsFile` — see
/// `ColorPaletteRecord`'s doc comment for the split rationale shared by every settings record
/// in this migration wave.
@Model
final class MicrophoneCalibrationSettingsRecord {
    var quietRMS: Float = FFTPitchAnalyzer.minimumRMSForDetection
    var loudRMS: Float = 0.3
    var quietPeakMagnitude: Float = 0
    var loudPeakMagnitude: Float = 0

    init(_ file: MicrophoneCalibrationSettingsFile) {
        quietRMS = file.quietRMS
        loudRMS = file.loudRMS
        quietPeakMagnitude = file.quietPeakMagnitude
        loudPeakMagnitude = file.loudPeakMagnitude
    }

    var asMicrophoneCalibrationSettingsFile: MicrophoneCalibrationSettingsFile {
        MicrophoneCalibrationSettingsFile(
            quietRMS: quietRMS, loudRMS: loudRMS, quietPeakMagnitude: quietPeakMagnitude, loudPeakMagnitude: loudPeakMagnitude
        )
    }
}
