/// Serializes every offline note-rendering session (`OctaveSpectrumGridBuilder.buildOrLoad`,
/// `RawSpectrumRenderer.render`) through ONE AT A TIME, process-wide.
///
/// `OfflineNoteRenderer` is "not thread-shared BY DESIGN: a fresh instance per analysis" (see its
/// own doc comment) — but that only ever covered not sharing ONE instance across threads, never
/// two DIFFERENT instances (each with their own `AVAudioEngine`/`AVAudioUnitSampler` in offline
/// manual-rendering mode) being alive and rendering AT THE SAME TIME. That crashed inside
/// `AVAudioUnitSampler.loadSoundBankInstrument` once a second rendering pipeline existed that
/// could genuinely overlap with the first (an octave-grid rebuild racing a same-chord spectrum
/// render, or several rapid chord clicks each spawning their own render) — nothing serialized the
/// two before this existed. An `actor`'s own isolation is enough: every call queues on its single
/// executor, so at most one closure — and therefore at most one live `OfflineNoteRenderer` — ever
/// runs at once, regardless of how many callers ask concurrently.
public actor OfflineRenderQueue {
    public static let shared = OfflineRenderQueue()

    private init() {}

    public func run<T: Sendable>(_ work: @Sendable () throws -> T) async throws -> T {
        try work()
    }
}
