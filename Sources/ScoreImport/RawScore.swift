import Foundation

/// Which parser produced a `RawScore` — kept alongside the data itself so a raw-file viewer
/// and any format-specific quirks (e.g. `explicitChords` only ever coming from MusicXML/MuseScore)
/// can be handled without re-inspecting the original file's extension.
public enum SourceFormat: String, Codable, Sendable {
    case midi
    case musicXML
    case museScore
}

/// The format-agnostic intermediate every importer (MIDI, MusicXML, MuseScore) normalizes into,
/// *before* quantization/analysis turns it into a `Piece`. Deliberately mirrors the source
/// format's own timing (ticks/divisions, not measures/beats) and notation (explicit chord
/// symbols when the source gives them) so a "show the raw file" view never loses precision the
/// source actually had, and so quantization can be re-run later (with a different grid, or an
/// improved chord/key detector) without re-parsing the original file.
public struct RawScore: Codable, Equatable, Sendable {
    public var sourceFormat: SourceFormat
    public var title: String?
    public var composer: String?
    /// Ticks per quarter note, common across every `RawPart` — MIDI's own PPQ, or MusicXML's
    /// per-part `<divisions>` rescaled at parse time to one shared value so cross-part timing
    /// lines up.
    public var divisionsPerQuarterNote: Int
    public var tempoMap: [RawTempoEvent]
    public var timeSignatureMap: [RawTimeSignatureEvent]
    public var keySignatureMap: [RawKeySignatureEvent]
    public var parts: [RawPart]
    /// Only ever populated by sources that carry their own chord symbols (MusicXML `<harmony>`,
    /// MuseScore `<Harmony>`) — empty for MIDI, which has no such notion.
    public var explicitChords: [RawChordSymbol]

    public init(
        sourceFormat: SourceFormat,
        title: String? = nil,
        composer: String? = nil,
        divisionsPerQuarterNote: Int,
        tempoMap: [RawTempoEvent] = [],
        timeSignatureMap: [RawTimeSignatureEvent] = [],
        keySignatureMap: [RawKeySignatureEvent] = [],
        parts: [RawPart] = [],
        explicitChords: [RawChordSymbol] = []
    ) {
        self.sourceFormat = sourceFormat
        self.title = title
        self.composer = composer
        self.divisionsPerQuarterNote = divisionsPerQuarterNote
        self.tempoMap = tempoMap
        self.timeSignatureMap = timeSignatureMap
        self.keySignatureMap = keySignatureMap
        self.parts = parts
        self.explicitChords = explicitChords
    }
}

/// One instrument's/staff's worth of notes — MIDI: one track (format 1) or one channel's slice
/// (format 0); MusicXML/MuseScore: one `<part>`/`<Staff>`.
public struct RawPart: Codable, Equatable, Sendable {
    public var id: String
    public var name: String?
    /// MIDI program-change name, or MusicXML/MuseScore's own declared instrument name — a hint
    /// only, never authoritative (the user assigns a real instrument/preset after import, same
    /// convention `RawScoreComposer` follows for `Track.instrument`).
    public var instrumentHint: String?
    public var notes: [RawNote]

    public init(id: String, name: String? = nil, instrumentHint: String? = nil, notes: [RawNote] = []) {
        self.id = id
        self.name = name
        self.instrumentHint = instrumentHint
        self.notes = notes
    }
}

/// One note (or rest) at the source's own rhythmic precision — not yet quantized to a beat grid.
public struct RawNote: Codable, Equatable, Sendable {
    public var startTick: Int
    public var durationTicks: Int
    /// Absolute MIDI note number (0...127). Meaningless (0) when `isRest` is true.
    public var pitch: Int
    public var velocity: Int
    /// The source's own letter-name spelling (e.g. Fb, not E) — only ever populated by
    /// MusicXML/MuseScore, which spell pitches explicitly; nil for MIDI, which has no such
    /// notion. Kept so a raw-file view can render the source's exact enharmonic choice rather
    /// than a best-guess respelling.
    public var spelling: RawSpelling?
    public var isRest: Bool
    /// MusicXML/MuseScore `<voice>` — which notated voice within a staff this note belongs to;
    /// nil for MIDI, which has no such notion (a MIDI track is a single implicit voice).
    public var voice: Int?
    /// MusicXML/MuseScore `<staff>` — e.g. which staff of a piano grand staff; nil for MIDI.
    public var staff: Int?
    public var tieStart: Bool
    public var tieStop: Bool

    public init(
        startTick: Int,
        durationTicks: Int,
        pitch: Int,
        velocity: Int = 100,
        spelling: RawSpelling? = nil,
        isRest: Bool = false,
        voice: Int? = nil,
        staff: Int? = nil,
        tieStart: Bool = false,
        tieStop: Bool = false
    ) {
        self.startTick = startTick
        self.durationTicks = durationTicks
        self.pitch = pitch
        self.velocity = velocity
        self.spelling = spelling
        self.isRest = isRest
        self.voice = voice
        self.staff = staff
        self.tieStart = tieStart
        self.tieStop = tieStop
    }
}

/// A source's own explicit letter-name spelling of a pitch — distinct from `PitchClass`/
/// `DiatonicSpelling` in `MusicTheoryKit`, which *compute* a best-guess spelling; this one is
/// whatever the source file actually wrote, kept verbatim for raw-fidelity display.
public struct RawSpelling: Codable, Equatable, Sendable {
    /// "C" ... "B"
    public var step: String
    /// -2 (double flat) ... 2 (double sharp)
    public var alter: Int
    public var octave: Int

    public init(step: String, alter: Int, octave: Int) {
        self.step = step
        self.alter = alter
        self.octave = octave
    }
}

public struct RawTempoEvent: Codable, Equatable, Sendable {
    public var tick: Int
    public var microsecondsPerQuarter: Int

    public init(tick: Int, microsecondsPerQuarter: Int) {
        self.tick = tick
        self.microsecondsPerQuarter = microsecondsPerQuarter
    }

    public var beatsPerMinute: Double {
        60_000_000 / Double(microsecondsPerQuarter)
    }
}

public struct RawTimeSignatureEvent: Codable, Equatable, Sendable {
    public var tick: Int
    public var beatsPerMeasure: Int
    public var beatUnit: Int

    public init(tick: Int, beatsPerMeasure: Int, beatUnit: Int) {
        self.tick = tick
        self.beatsPerMeasure = beatsPerMeasure
        self.beatUnit = beatUnit
    }
}

public struct RawKeySignatureEvent: Codable, Equatable, Sendable {
    public var tick: Int
    /// Sharps (positive) or flats (negative) — MIDI and MusicXML/MuseScore both express key
    /// signatures this way.
    public var fifths: Int
    public var isMinor: Bool

    public init(tick: Int, fifths: Int, isMinor: Bool = false) {
        self.tick = tick
        self.fifths = fifths
        self.isMinor = isMinor
    }
}

/// An explicit chord symbol as given by the source (MusicXML `<harmony>`, MuseScore
/// `<Harmony>`) — kept in the source's own vocabulary (`kind` is MusicXML's own kind string,
/// or MuseScore's own chord-name text) rather than mapped to `ChordVocabulary` here, so a
/// future rename of our own chord IDs never requires re-parsing the source file; that mapping
/// happens downstream, in `ChordSliceDetector`.
public struct RawChordSymbol: Codable, Equatable, Sendable {
    public var tick: Int
    public var rootStep: String
    public var rootAlter: Int
    public var kind: String

    public init(tick: Int, rootStep: String, rootAlter: Int, kind: String) {
        self.tick = tick
        self.rootStep = rootStep
        self.rootAlter = rootAlter
        self.kind = kind
    }
}
