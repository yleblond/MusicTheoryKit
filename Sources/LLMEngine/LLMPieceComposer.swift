import Foundation
import MusicTheoryKit
import PieceModel
import SoundTrackModel

/// Parses a note name ("C", "F#", "Bb"...) into a pitch class 0...11. Returns nil for
/// anything that isn't a recognizable note letter A-G (optionally followed by a single
/// "#"/"s" for sharp or "b" for flat) — the LLM is asked for exactly this format, but its
/// output is never trusted outright.
public func parsePitchClass(_ name: String) -> Int? {
    let letters: [Character: Int] = ["C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11]
    var chars = Array(name.trimmingCharacters(in: .whitespaces))
    guard let first = chars.first, let base = letters[Character(first.uppercased())] else { return nil }
    chars.removeFirst()
    var value = base
    if let accidental = chars.first {
        if accidental == "#" || accidental == "s" || accidental == "S" { value += 1 }
        else if accidental == "b" || accidental == "B" { value -= 1 }
        else { return nil }
        chars.removeFirst()
    }
    guard chars.isEmpty else { return nil } // trailing garbage, e.g. "C##" or "Cbb"
    return ((value % 12) + 12) % 12
}

// MARK: - LLM-facing JSON schema (deliberately simpler than PieceModel's own Codable shape —
// note names instead of raw pitch classes, no ids, so it's natural for an LLM to produce).

struct LLMChordDTO: Decodable {
    var measure: Int
    var root: String
    var templateID: String
    var durationBeats: Double?
}

struct LLMMelodyNoteDTO: Decodable {
    var measure: Int
    var beat: Double
    var durationBeats: Double
    var pitch: Int
}

struct LLMSectionDTO: Decodable {
    var name: String
    var lengthInMeasures: Int
    var tonic: String
    var scaleID: String
    var chords: [LLMChordDTO]
    var melody: [LLMMelodyNoteDTO]?
}

struct LLMPieceDTO: Decodable {
    var title: String
    var tempoBPM: Double
    var tonic: String
    var scaleID: String
    var sections: [LLMSectionDTO]
}

public enum LLMPieceComposer {
    /// Builds the prompt sent to the LLM: the source text plus the exact JSON schema to
    /// answer with, restricted to the theory library's actual vocabulary (scale/chord IDs)
    /// so as much of the response as possible survives validation. `additionalInstructions`
    /// (e.g. "romantique, mode mineur" typed alongside a title/text in the "Nouveau morceau"
    /// wizard) is appended as a separate, clearly-labeled block after the text — free-form
    /// style guidance the LLM is asked to follow as long as it doesn't conflict with the
    /// schema above, not itself validated (there's nothing to validate — the actual output
    /// still goes through `parseAndValidate` regardless of whether guidance was given).
    public static func buildPrompt(sourceText: String, additionalInstructions: String? = nil) -> String {
        let scaleIDs = ScaleLibrary.all.map(\.id).joined(separator: ", ")
        let chordIDs = ChordVocabulary.seed.map(\.id).joined(separator: ", ")
        let instructionsBlock = additionalInstructions.map {
            "\n\nAdditional style guidance from the user (follow it as long as it doesn't conflict with the schema above):\n\($0)"
        } ?? ""
        return """
        You are a music composition assistant. Given the text below (e.g. a poem or lyrics), \
        propose a short musical piece whose mode and chord progression express its mood.

        Respond with ONLY a single JSON object — no markdown fences, no commentary — exactly \
        matching this schema:
        {
          "title": string,
          "tempoBPM": number,
          "tonic": string (a note name like "C", "F#", "Bb"),
          "scaleID": string (one of: \(scaleIDs)),
          "sections": [
            {
              "name": string,
              "lengthInMeasures": number,
              "tonic": string,
              "scaleID": string (one of: \(scaleIDs)),
              "chords": [ { "measure": number, "root": string, "templateID": string (one of: \(chordIDs)), "durationBeats": number } ],
              "melody": [ { "measure": number, "beat": number, "durationBeats": number, "pitch": number (MIDI note, 0-127) } ]
            }
          ]
        }
        "melody" is optional — omit it for a section with no separate melodic line.

        Text:
        \"\"\"
        \(sourceText)
        \"\"\"\(instructionsBlock)
        """
    }

    /// Builds the prompt for reconstructing a measure-based `Piece` from a purely temporal
    /// `SoundTrack` recording — same JSON schema and validation as `buildPrompt(sourceText:)`
    /// (see `parseAndValidate`, entirely unchanged and shared by both), just a different
    /// framing of the request: "infer a tempo/key/chords that explain this real performance"
    /// instead of "invent one to match this poem's mood." Note names use the same C4=MIDI 60
    /// convention as `ImprovCLI`'s own `noteNameWithOctave`.
    public static func buildPrompt(fromSoundTrack soundTrack: SoundTrack) -> String {
        let scaleIDs = ScaleLibrary.all.map(\.id).joined(separator: ", ")
        let chordIDs = ChordVocabulary.seed.map(\.id).joined(separator: ", ")
        let eventLines = soundTrack.events.map { event -> String in
            let pitchClass = ((event.pitch % 12) + 12) % 12
            let octave = event.pitch / 12 - 1
            let noteName = "\(PitchClass(pitchClass).name())\(octave)"
            let action = event.isNoteOn ? "ON" : "OFF"
            return "t=\(String(format: "%.2f", event.timeSeconds))s \(action) \(noteName) (piste: \(event.trackID))"
        }.joined(separator: "\n")

        return """
        You are a music transcription assistant. Below is a raw, real-time recording of \
        notes played on one or more input tracks — a list of note on/off events with exact \
        timestamps in seconds, not yet aligned to any tempo or measure grid.

        Infer a plausible tempo (BPM) and reconstruct this performance as a measure-based \
        piece: a key/mode, and a chord progression that reasonably explains the notes \
        actually played (group nearby simultaneous notes into chords where that makes \
        musical sense; align to a steady beat even if the original timing wasn't perfectly \
        steady).

        Respond with ONLY a single JSON object — no markdown fences, no commentary — exactly \
        matching this schema:
        {
          "title": string,
          "tempoBPM": number,
          "tonic": string (a note name like "C", "F#", "Bb"),
          "scaleID": string (one of: \(scaleIDs)),
          "sections": [
            {
              "name": string,
              "lengthInMeasures": number,
              "tonic": string,
              "scaleID": string (one of: \(scaleIDs)),
              "chords": [ { "measure": number, "root": string, "templateID": string (one of: \(chordIDs)), "durationBeats": number } ],
              "melody": [ { "measure": number, "beat": number, "durationBeats": number, "pitch": number (MIDI note, 0-127) } ]
            }
          ]
        }
        "melody" is optional — omit it for a section with no separate melodic line.

        Recording (\(String(format: "%.1f", soundTrack.durationSeconds))s total, \(soundTrack.events.count) events):
        \(eventLines)
        """
    }

    /// Strips a leading/trailing ``` fence if the model wrapped its JSON in one anyway.
    static func extractJSON(from text: String) -> String {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("```") else { return trimmed }
        if let firstNewline = trimmed.firstIndex(of: "\n") {
            trimmed = String(trimmed[trimmed.index(after: firstNewline)...])
        }
        if trimmed.hasSuffix("```") {
            trimmed = String(trimmed.dropLast(3))
        }
        return trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Parses the LLM's raw response text and validates every piece of it against the real
    /// theory library before building a `Piece` — an invalid scale/chord ID, or a section
    /// left with no valid chords, is dropped (with a warning) rather than silently trusted.
    /// Returns `(nil, warnings)` only if nothing usable survived at all.
    public static func parseAndValidate(responseText: String) -> (piece: Piece?, warnings: [String]) {
        let jsonText = extractJSON(from: responseText)
        guard let data = jsonText.data(using: .utf8) else {
            return (nil, ["response was not valid UTF-8"])
        }
        let dto: LLMPieceDTO
        do {
            dto = try JSONDecoder().decode(LLMPieceDTO.self, from: data)
        } catch {
            return (nil, ["could not parse the response as the expected JSON: \(error)"])
        }
        return compose(from: dto)
    }

    static func compose(from dto: LLMPieceDTO) -> (piece: Piece?, warnings: [String]) {
        var warnings: [String] = []

        guard let keyTonic = parsePitchClass(dto.tonic), ScaleLibrary.byID(dto.scaleID) != nil else {
            return (nil, ["invalid key: tonic=\(dto.tonic) scaleID=\(dto.scaleID)"])
        }

        var sections: [Section] = []
        for sectionDTO in dto.sections {
            guard let sectionTonic = parsePitchClass(sectionDTO.tonic), ScaleLibrary.byID(sectionDTO.scaleID) != nil else {
                warnings.append("dropped section '\(sectionDTO.name)': invalid mode tonic=\(sectionDTO.tonic) scaleID=\(sectionDTO.scaleID)")
                continue
            }

            var chordEvents: [ChordEvent] = []
            for chordDTO in sectionDTO.chords {
                guard let root = parsePitchClass(chordDTO.root), ChordVocabulary.byID(chordDTO.templateID) != nil else {
                    warnings.append("dropped chord \(chordDTO.root)\(chordDTO.templateID) in section '\(sectionDTO.name)': not in the vocabulary")
                    continue
                }
                chordEvents.append(ChordEvent(
                    measure: chordDTO.measure,
                    beat: 1,
                    durationBeats: chordDTO.durationBeats ?? 4,
                    chord: ChordReference(root: root, chordTemplateID: chordDTO.templateID)
                ))
            }
            guard !chordEvents.isEmpty else {
                warnings.append("dropped section '\(sectionDTO.name)': no valid chords survived validation")
                continue
            }

            var melodyEvents: [MelodyEvent] = []
            for noteDTO in sectionDTO.melody ?? [] {
                guard (0...127).contains(noteDTO.pitch) else {
                    warnings.append("dropped out-of-range melody note (pitch=\(noteDTO.pitch)) in section '\(sectionDTO.name)'")
                    continue
                }
                melodyEvents.append(MelodyEvent(measure: noteDTO.measure, beat: noteDTO.beat, durationBeats: noteDTO.durationBeats, pitch: noteDTO.pitch))
            }

            sections.append(Section(
                name: sectionDTO.name,
                lengthInMeasures: sectionDTO.lengthInMeasures,
                mode: ModeReference(tonic: sectionTonic, scaleID: sectionDTO.scaleID),
                chordProgression: chordEvents,
                // "" (not a placeholder like "piano") — an unset instrument means "use the
                // piece-playback default sound," see `Rendering.swift`; the LLM has no way
                // to know what sample files are actually available locally, so it never
                // gets to name one. Set a real instrument afterwards via
                // `setPieceTrackInstrument`/`set-track-instrument`.
                tracks: melodyEvents.isEmpty ? [] : [Track(name: "melody", instrument: "", melodyEvents: melodyEvents)]
            ))
        }

        guard !sections.isEmpty else {
            warnings.append("no valid sections survived validation")
            return (nil, warnings)
        }

        let piece = Piece(
            title: dto.title,
            tempoBPM: max(30, min(240, dto.tempoBPM)),
            key: ModeReference(tonic: keyTonic, scaleID: dto.scaleID),
            sections: sections
        )
        return (piece, warnings)
    }
}
