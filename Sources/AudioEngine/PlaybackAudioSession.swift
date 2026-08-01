@preconcurrency import AVFoundation

/// Puts the shared `AVAudioSession` into a state where `AVAudioEngine` output is actually
/// audible on iOS, before starting an engine used purely for playback (`SamplerUnit`,
/// `PiecePlayer`) — a macOS-only concern, so this is a no-op there (macOS has no
/// `AVAudioSession` concept; routing "just works," which is why these engines had no session
/// handling at all until now). Unlike the crash `MicrophonePitchListener` avoids by doing the
/// equivalent for its record-capable session (see its doc comment), skipping this for a
/// playback-only engine doesn't crash — it stays silent instead, since the session's default
/// `.soloAmbient` category is muted by the device's Silent switch, which is much easier to
/// miss while testing than a crash.
enum PlaybackAudioSession {
    static func activateIfNeeded() {
        #if os(iOS) || os(visionOS)
        let session = AVAudioSession.sharedInstance()
        guard session.category != .playAndRecord else { return }
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothHFP])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)
        #endif
    }
}
