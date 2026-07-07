import MusicTheoryKit

/// A single playable note, fully resolved to an absolute time within its section —
/// the shape a non-realtime playback engine (or a piano-roll view) would consume.
public struct ScheduledNote: Equatable, Sendable {
    public var startBeat: Double   // absolute beat position within the section, 0-based
    public var durationBeats: Double
    public var pitch: Int
    public var velocity: Int
    /// Which sample-based instrument should sound this note (matched by name against a
    /// sample folder) — `nil` means "the piece-playback default sound," same as today.
    public var instrumentName: String?

    public init(startBeat: Double, durationBeats: Double, pitch: Int, velocity: Int, instrumentName: String? = nil) {
        self.startBeat = startBeat
        self.durationBeats = durationBeats
        self.pitch = pitch
        self.velocity = velocity
        self.instrumentName = instrumentName
    }
}

/// Normalizes a free-form instrument field to `nil` when unset, so an empty string and a
/// genuinely absent instrument both mean "use the default sound."
private func normalizedInstrumentName(_ raw: String?) -> String? {
    guard let raw, !raw.isEmpty else { return nil }
    return raw
}

public extension Section {
    /// Converts a 1-based (measure, beat) position into an absolute 0-based beat offset
    /// from the start of this section.
    func absoluteBeat(measure: Int, beat: Double, beatsPerMeasure: Int) -> Double {
        Double((measure - 1) * beatsPerMeasure) + (beat - 1)
    }
}

public extension Track {
    /// Flattens this track's directly-authored melody events and its fragment placements
    /// (with their transforms resolved) into one time-ordered list of scheduled notes.
    func scheduledNotes(in piece: Piece, section: Section) -> [ScheduledNote] {
        let beatsPerMeasure = piece.timeSignature.beatsPerMeasure
        let instrumentName = normalizedInstrumentName(instrument)

        let fromMelodyEvents = melodyEvents.map { event in
            ScheduledNote(
                startBeat: section.absoluteBeat(measure: event.measure, beat: event.beat, beatsPerMeasure: beatsPerMeasure),
                durationBeats: event.durationBeats,
                pitch: event.pitch,
                velocity: event.velocity,
                instrumentName: instrumentName
            )
        }

        let fromFragmentPlacements = fragmentPlacements.compactMap { placement -> [ScheduledNote]? in
            guard let fragment = piece.fragment(id: placement.fragmentID) else { return nil }
            let resolved = placement.resolvedFragment(from: fragment)
            let pitches = resolved.absolutePitches(basePitch: placement.basePitch)
            let placementStart = section.absoluteBeat(measure: placement.measure, beat: placement.beat, beatsPerMeasure: beatsPerMeasure)

            var notes: [ScheduledNote] = []
            var cursor = placementStart
            for (pitch, duration) in zip(pitches, resolved.noteDurations) {
                notes.append(ScheduledNote(startBeat: cursor, durationBeats: duration, pitch: pitch, velocity: placement.velocity, instrumentName: instrumentName))
                cursor += duration
            }
            return notes
        }.flatMap { $0 }

        return (fromMelodyEvents + fromFragmentPlacements).sorted { $0.startBeat < $1.startBeat }
    }
}

extension ChordEvent {
    /// Concrete MIDI pitches for this chord, stacked upward from `octaveBase`, after
    /// applying `inversion` (each inverted tone moved up an octave) and, if set,
    /// `bassOverride` as the lowest sounding pitch (for slash chords).
    fileprivate func voicedPitches(octaveBase: Int) -> [Int] {
        guard let resolved = chord.resolve() else { return [] }
        // Built from `intervalsFromRoot` directly (not `pitchClasses`, which wraps mod 12
        // and would lose the ascending order needed for the root to land as the bass).
        let rootPitch = octaveBase + resolved.root.value
        var pitches = resolved.template.intervalsFromRoot.map { rootPitch + $0 }

        let rotation = ((inversion % pitches.count) + pitches.count) % pitches.count
        if rotation > 0 {
            pitches = Array(pitches[rotation...]) + pitches[..<rotation].map { $0 + 12 }
        }

        if let bassOverride {
            let bassClass = PitchClass(bassOverride)
            if let index = pitches.firstIndex(where: { PitchClass($0).value == bassClass.value }) {
                let bassPitch = pitches.remove(at: index)
                pitches.insert(bassPitch - 12, at: 0)
            } else {
                pitches.insert(octaveBase - 12 + bassClass.value, at: 0)
            }
        }

        return pitches.sorted()
    }

    /// Flattens this chord event into individually-timed notes (beat offsets relative to
    /// the event's own start) according to `playingStyle`.
    fileprivate func voicedNotes(octaveBase: Int) -> [(offsetBeats: Double, durationBeats: Double, pitch: Int)] {
        let pitches = voicedPitches(octaveBase: octaveBase)
        guard !pitches.isEmpty else { return [] }

        switch playingStyle {
        case .simultaneous:
            return pitches.map { (0, durationBeats, $0) }
        case .arpeggioUp, .arpeggioDown, .strum:
            let ordered = playingStyle == .arpeggioDown ? Array(pitches.reversed()) : pitches
            let step = playingStyle == .strum
                ? min(0.05, durationBeats / Double(ordered.count))
                : durationBeats / Double(ordered.count)
            return ordered.enumerated().map { index, pitch in
                let offset = Double(index) * step
                let sustained = playingStyle == .strum
                return (offset, sustained ? durationBeats - offset : max(durationBeats - offset, step), pitch)
            }
        }
    }
}

public extension Section {
    /// Flattens this section's chord progression into scheduled notes (beat offsets
    /// relative to the section start), resolving each chord's inversion/bass/playing style.
    func chordScheduledNotes(beatsPerMeasure: Int, octaveBase: Int = 48, velocity: Int = 90) -> [ScheduledNote] {
        let instrumentName = normalizedInstrumentName(chordInstrument)
        return chordProgression.flatMap { event -> [ScheduledNote] in
            let eventStart = absoluteBeat(measure: event.measure, beat: event.beat, beatsPerMeasure: beatsPerMeasure)
            return event.voicedNotes(octaveBase: octaveBase).map { voiced in
                ScheduledNote(
                    startBeat: eventStart + voiced.offsetBeats,
                    durationBeats: voiced.durationBeats,
                    pitch: voiced.pitch,
                    velocity: velocity,
                    instrumentName: instrumentName
                )
            }
        }.sorted { $0.startBeat < $1.startBeat }
    }
}

/// A single playable note, fully resolved to an absolute time (in seconds) within the
/// whole piece — the shape a non-realtime audio engine consumes directly.
public struct RenderedNote: Equatable, Sendable {
    public var startSeconds: Double
    public var durationSeconds: Double
    public var pitch: Int
    public var velocity: Int
    /// Carried over from `ScheduledNote.instrumentName` — see there for what `nil` means.
    public var instrumentName: String?

    public init(startSeconds: Double, durationSeconds: Double, pitch: Int, velocity: Int, instrumentName: String? = nil) {
        self.startSeconds = startSeconds
        self.durationSeconds = durationSeconds
        self.pitch = pitch
        self.velocity = velocity
        self.instrumentName = instrumentName
    }
}

public extension Piece {
    /// Flattens every section's chord progression and tracks into one absolute-time
    /// timeline in seconds, using `tempoBPM` (beats per minute, where a "beat" is the
    /// same unit as `measure`/`beat` throughout this model).
    func renderedNotes() -> [RenderedNote] {
        let secondsPerBeat = 60.0 / tempoBPM
        let beatsPerMeasure = timeSignature.beatsPerMeasure

        var notes: [RenderedNote] = []
        var sectionStartBeat = 0.0
        for section in sections {
            var sectionNotes = section.chordScheduledNotes(beatsPerMeasure: beatsPerMeasure)
            for track in section.tracks {
                sectionNotes += track.scheduledNotes(in: self, section: section)
            }
            for note in sectionNotes {
                let absoluteBeat = sectionStartBeat + note.startBeat
                notes.append(RenderedNote(
                    startSeconds: absoluteBeat * secondsPerBeat,
                    durationSeconds: note.durationBeats * secondsPerBeat,
                    pitch: note.pitch,
                    velocity: note.velocity,
                    instrumentName: note.instrumentName
                ))
            }
            sectionStartBeat += Double(section.lengthInMeasures) * Double(beatsPerMeasure)
        }
        return notes.sorted { $0.startSeconds < $1.startSeconds }
    }
}

/// One chord event resolved to absolute seconds within the whole piece, carrying its
/// section's mode along with it — the granularity a "where are we right now" playback
/// display needs (which chord, which mode), as opposed to `renderedNotes()`, which explodes
/// everything down to individually-voiced notes and loses that structure.
public struct TimedChordEvent: Equatable, Sendable {
    public var startSeconds: Double
    public var endSeconds: Double
    public var chord: ChordReference
    public var mode: ModeReference
    public var sectionName: String
    public var measure: Int

    public init(startSeconds: Double, endSeconds: Double, chord: ChordReference, mode: ModeReference, sectionName: String, measure: Int) {
        self.startSeconds = startSeconds
        self.endSeconds = endSeconds
        self.chord = chord
        self.mode = mode
        self.sectionName = sectionName
        self.measure = measure
    }
}

public extension Piece {
    /// Flattens every section's chord progression (ignoring melody/fragments) into one
    /// absolute-time timeline in seconds — the chord-level granularity a playback-position
    /// display needs, using the same beat math as `renderedNotes()`.
    func harmonicTimeline() -> [TimedChordEvent] {
        let secondsPerBeat = 60.0 / tempoBPM
        let beatsPerMeasure = timeSignature.beatsPerMeasure

        var events: [TimedChordEvent] = []
        var sectionStartBeat = 0.0
        for section in sections {
            for chordEvent in section.chordProgression {
                let startBeat = sectionStartBeat + section.absoluteBeat(measure: chordEvent.measure, beat: chordEvent.beat, beatsPerMeasure: beatsPerMeasure)
                let endBeat = startBeat + chordEvent.durationBeats
                events.append(TimedChordEvent(
                    startSeconds: startBeat * secondsPerBeat,
                    endSeconds: endBeat * secondsPerBeat,
                    chord: chordEvent.chord,
                    mode: section.mode,
                    sectionName: section.name,
                    measure: chordEvent.measure
                ))
            }
            sectionStartBeat += Double(section.lengthInMeasures) * Double(beatsPerMeasure)
        }
        return events.sorted { $0.startSeconds < $1.startSeconds }
    }
}
