import SwiftUI
import AppCore

/// Equivalent of the console's/CLI's "Run" view: every currently-listening track, each showing
/// its held notes on a `PitchKeyboardView` plus its recognized chord/mode labels — driven live
/// by a `SessionUIBridge`. The first screen that proves the full chain end to end (bridge
/// polling -> per-track adapter -> `PitchKeyboardView`).
public struct RunScreen: View {
    public let bridge: SessionUIBridge

    public init(bridge: SessionUIBridge) {
        self.bridge = bridge
    }

    public var body: some View {
        List(bridge.state.tracks, id: \.id) { track in
            TrackRunRow(track: track)
        }
        #if os(macOS)
        .listStyle(.inset)
        #endif
    }
}

private struct TrackRunRow: View {
    let track: WebConsoleTrackState

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(track.label).font(.headline)
                if let owner = track.owner {
                    Text("(\(owner))").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let chordLabel = track.chordLabel {
                    Text(chordLabel).font(.headline).foregroundStyle(Color.accentColor)
                }
            }
            if let modesLabel = track.modesLabel {
                Text(modesLabel).font(.caption).foregroundStyle(.secondary)
            }
            if let recognitionMode = track.recognitionMode {
                Text(recognitionMode).font(.caption2).foregroundStyle(.secondary)
            }
            PitchKeyboardView(
                minMidi: 48,
                maxMidi: 72,
                heldPitches: Set(track.heldPitches),
                chordRoot: track.chordRoot,
                chordTones: track.chordTones,
                modeTones: track.modeTones
            )
        }
        .padding(.vertical, 6)
    }
}
