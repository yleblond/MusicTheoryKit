import SwiftUI

/// A play/stop control with the icon above its French label — used by the Morceaux and
/// Enregistrement "Play" screens, per explicit user request ("icones play et stop ... avec
/// eventuellement le label en dessous"). One shared view so both screens' buttons stay
/// visually identical rather than two hand-tuned copies.
struct PlaybackControlButton: View {
    let isPlaying: Bool
    let onPlay: () -> Void
    let onStop: () -> Void

    var body: some View {
        Button(action: isPlaying ? onStop : onPlay) {
            VStack(spacing: 2) {
                Image(systemName: isPlaying ? "stop.fill" : "play.fill")
                    .font(.title2)
                Text(isPlaying ? "Arreter" : "Jouer")
                    .font(.caption)
            }
            .frame(minWidth: 60)
        }
        .buttonStyle(.bordered)
        .tint(isPlaying ? .red : .accentColor)
    }
}

#Preview {
    HStack(spacing: 16) {
        PlaybackControlButton(isPlaying: false, onPlay: {}, onStop: {})
        PlaybackControlButton(isPlaying: true, onPlay: {}, onStop: {})
    }
    .padding()
}
