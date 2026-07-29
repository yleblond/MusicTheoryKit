/// The fixed set of SF Symbol names an icon can be assigned from — for scenes, roles, favorite
/// instruments, and MIDI keyboards (see `ImprovSession.suggestIcon(kind:name:)` and each object
/// kind's own `set...Icon` method). Constrained so an AI suggestion always lands on a real,
/// stylistically-consistent symbol rather than an arbitrary string — the exact same "inject the
/// real allowed vocabulary into the prompt, then validate the response against it" shape
/// `LLMPieceComposer` already uses for scale/chord names. A name here that turns out not to
/// exist on some OS version is a purely cosmetic gap (`Image(systemName:)` never crashes on an
/// unknown name), not a correctness concern.
public enum IconVocabulary {
    public static let allowedSymbolNames: [String] = [
        "theatermasks", "pianokeys", "guitars", "mic", "music.mic",
        "waveform", "music.note", "music.note.list", "music.quarternote.3",
        "speaker.wave.2.fill", "headphones", "radio.fill", "hifispeaker.fill",
        "sparkles", "flame.fill", "leaf.fill", "moon.stars.fill", "sun.max.fill",
        "bolt.fill", "heart.fill", "cloud.fill", "star.fill", "person.fill", "person.2.fill",
    ]
}
