import MIDIEngine
import MusicTheoryKit
import PieceModel

/// Builds the ordered SysEx message sequence for LUMI's "guide" display: a static color map
/// showing a chosen tonic/scale, independent of what's actually being played — as opposed to
/// a live note-reactive display (not yet built; that would forward Note On/Off to the LUMI's
/// destination instead of sending these SysEx messages).
///
/// Pure message-list-in/message-list-out, no CoreMIDI dependency (see `ImprovSession
/// .pushLumiGuideMap` for the transport half, which sends each message in order via
/// `MIDIOutputPort`). Order matters: `.user` `ColorMode` and the key/scale that determine
/// which physical keys count as "in scale" must already be set before `setColor` actually
/// has something meaningful to color (see `LumiSysex.Scale`'s doc comment) — brightness is
/// last only because it has no such ordering dependency, not because it must be.
public enum LumiGuideMap {
    public static func messages(
        mode: ModeReference,
        rootColor: (red: UInt8, green: UInt8, blue: UInt8),
        scaleColor: (red: UInt8, green: UInt8, blue: UInt8),
        brightnessPercentage: Int = 100
    ) -> [[UInt8]] {
        [
            LumiSysex.setColorMode(.user),
            LumiSysex.setKey(pitchClass: PitchClass(mode.tonic).value),
            LumiSysex.setScale(LumiColorMap.lumiScale(forScaleID: mode.scaleID) ?? .chromatic),
            LumiSysex.setColor(.root, red: rootColor.red, green: rootColor.green, blue: rootColor.blue),
            LumiSysex.setColor(.allKeys, red: scaleColor.red, green: scaleColor.green, blue: scaleColor.blue),
            LumiSysex.setBrightness(brightnessPercentage),
        ]
    }
}
