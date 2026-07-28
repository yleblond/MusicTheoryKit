import AVFoundation
import SoundFontModel

/// Bridges a raw `SoundFontPresetIdentity` (as read straight from a `.sf2`'s `phdr` records) to
/// the `program`/`bankMSB`/`bankLSB` triplet `AVAudioUnitSampler.loadSoundBankInstrument`
/// actually takes — kept out of `SoundFontPresetReader.swift` itself so that file stays free of
/// any dependency on the sampler API it's independent from.
extension SoundFontPresetIdentity {
    /// SoundFont2/General MIDI convention (verified against real files — `FluidR3_GM2-2.SF2`
    /// and `GeneralUser GS v1.471.sf2` both use this): percussion kits are registered under
    /// `wBank == 120` (matching `kAUSampler_DefaultPercussionBankMSB` directly), not 128 — a
    /// value used in an earlier draft of this mapping without checking a real file, which
    /// silently broke every percussion preset (wrong bankMSB/bankLSB → `AVAudioUnitSampler`
    /// finds no matching zone → no sound, no thrown error). Everything else maps to the
    /// ordinary melodic MSB.
    public var bankMSB: UInt8 {
        bank == 120 ? UInt8(kAUSampler_DefaultPercussionBankMSB) : UInt8(kAUSampler_DefaultMelodicBankMSB)
    }

    /// 0 for the percussion bank (there's only one); otherwise the raw `bank` value itself,
    /// clamped to a byte — lets a multi-bank `.sf2` (banks other than the plain melodic/
    /// percussion split, e.g. FluidR3's own alternate-instrument banks) still select among its
    /// own banks via the LSB.
    public var bankLSB: UInt8 {
        bank == 120 ? UInt8(kAUSampler_DefaultBankLSB) : UInt8(clamping: bank)
    }

    /// `program` is stored as the SoundFont2 spec's 16-bit `WORD`, but `AVAudioUnitSampler`
    /// takes a `UInt8` (MIDI program numbers only ever go up to 127 in practice).
    public var samplerProgram: UInt8 {
        UInt8(clamping: program)
    }
}
