import MIDIEngine
import MusicTheoryKit

/// Maps this app's own scale vocabulary (`MusicTheoryKit.ScaleLibrary`, 33 scales across 7
/// families) onto the LUMI Keys' much smaller, fixed built-in scale list
/// (`LumiSysex.Scale`) — see that type's own doc comment for why these aren't the same
/// vocabulary at all: only 9 of `ScaleLibrary`'s scales have a native LUMI equivalent.
///
/// Every other scale (the melodic-minor/harmonic-major/diminished/augmented families, and
/// jazz alterations like `altered`/`half_diminished`) has no native equivalent — `nil`.
/// Callers get to decide what that means for them: `LumiGuideMap.messages` degrades to
/// `.chromatic` (every key colored uniformly, root still correct, just no in/out-of-scale
/// distinction), while `ImprovSession`'s live "run"/"guide" LUMI displays instead fall back
/// to LUMI's own native `.piano` `ColorMode` entirely rather than show a possibly-misleading
/// chromatic map for a scale LUMI can't really represent.
public enum LumiColorMap {
    public static func lumiScale(forScaleID scaleID: String) -> LumiSysex.Scale? {
        switch scaleID {
        case "ionian": return .major
        case "aeolian": return .minor
        case "harmonic_minor": return .harmonicMinor
        case "dorian": return .dorian
        case "phrygian": return .phrygian
        case "lydian": return .lydian
        case "mixolydian": return .mixolydian
        case "locrian": return .locrian
        case "whole_tone": return .wholeTone
        default: return nil
        }
    }
}
