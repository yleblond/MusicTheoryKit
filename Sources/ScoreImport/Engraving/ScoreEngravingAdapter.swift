import Foundation
import MusicTheoryKit
import PieceModel
import RecognitionEngine

/// Converts a `RawScore` (tick-based, not-yet-notated) into a `NotatedScore` (measures of
/// discrete note durations + VexFlow key strings) for display. This is display quantization,
/// not the same as `BeatQuantizer`'s measure/beat grid for `Piece` — the two happen to share
/// the "round ticks to a standard value" idea but serve different consumers (a renderer here,
/// `MelodyEvent.measure/beat` there) and are free to diverge.
///
/// Known v1 limitations (acceptable for a "raw file" sanity-check view, not publication-quality
/// engraving — see the score-import plan's Option A/B discussion):
/// - Notes are clipped to fit within the measure they start in — no ties across a barline.
/// - Simultaneous notes are only grouped into a chord when they share the exact same start tick
///   AND duration; genuinely independent polyphonic voices of differing rhythm are not
///   separated into distinct notated voices, they render sequentially instead.
/// - One fixed clef (or a fixed treble/bass grand-staff split) per part, chosen once from its
///   overall pitch profile (see `staffPlan(forPitches:)`) — a part never switches clef mid-piece.
public enum ScoreEngravingAdapter {
    /// Renders an already-composed `Piece` (hand-authored, LLM-composed, or the result of
    /// `RawScoreComposer.compose`) the same way an imported file is rendered — rather than
    /// re-implementing measure-segmentation/rest-filling/duration-quantization a second time for
    /// `Piece`'s measure/beat shape, this converts each track's events into synthetic
    /// tick-based `RawNote`s (an arbitrary but internally-consistent 480 ticks/quarter) and
    /// reuses the same `buildMeasures` helper `build(from: RawScore)` is built on. `Piece`'s own
    /// "one time signature/tempo for the whole piece" shape means only one `RawTimeSignatureEvent`
    /// at tick 0 is ever needed here, unlike a real imported file's map.
    public static func build(from piece: Piece) -> NotatedScore {
        let ticksPerQuarter = 480
        let beatsPerMeasure = max(piece.timeSignature.beatsPerMeasure, 1)
        let beatUnit = max(piece.timeSignature.beatUnit, 1)
        let ticksPerBeatUnit = ticksPerQuarter * 4 / beatUnit
        let measureLengthTicks = beatsPerMeasure * ticksPerBeatUnit
        let totalMeasures = piece.sections.reduce(0) { $0 + $1.lengthInMeasures }
        let totalTicks = totalMeasures * measureLengthTicks
        let timeSignatures = [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: beatsPerMeasure, beatUnit: beatUnit)]

        let timeline = harmonicTimeline(from: piece, ticksPerBeatUnit: ticksPerBeatUnit, beatsPerMeasure: beatsPerMeasure)
        let colorLookup: (Int, Int) -> String? = { pitch, tick in color(forPitch: pitch, atTick: tick, in: timeline) }

        // Same formula `Piece.renderedNotes()` itself uses — lets `NotatedNote.startSeconds`
        // match real playback time exactly, so `bridge.js` can tell "the note sounding right
        // now" apart from another occurrence of the same pitch elsewhere in the piece.
        let secondsPerBeat = 60.0 / max(piece.tempoBPM, 1)
        let secondsForTick: (Int) -> Double = { tick in Double(tick) / Double(ticksPerBeatUnit) * secondsPerBeat }

        // One key signature for the whole score — same "one detected mode for the whole piece"
        // v1 simplification `RawScoreComposer` already documents; `nil` (no signature, today's
        // un-suppressed-accidentals behavior) for anything outside the 7 classic modes.
        let keyContext = keySignatureContext(for: piece)
        let chordAnnotations = chordAnnotationsByMeasure(
            from: timeline, measureLengthTicks: measureLengthTicks, ticksPerBeatUnit: ticksPerBeatUnit
        )

        // `minimumTicks: totalTicks` below is what makes a track absent from a LATER section
        // still get that section's worth of silent measures, rather than the part simply
        // ending early and every other part's measures no longer lining up with it.
        let parts = rawParts(from: piece, ticksPerQuarter: ticksPerQuarter, ticksPerBeatUnit: ticksPerBeatUnit, beatsPerMeasure: beatsPerMeasure)
            .enumerated().flatMap { index, rawPart in
                notatedParts(
                    for: rawPart, timeSignatures: timeSignatures, ticksPerQuarter: ticksPerQuarter, minimumTicks: totalTicks,
                    colorLookup: colorLookup, keySignature: keyContext?.signature, keySignatureName: keyContext?.keyName,
                    diatonicSpelling: keyContext?.diatonicSpellingByPitchClass,
                    chordAnnotationsByMeasure: index == 0 ? chordAnnotations : nil, secondsForTick: secondsForTick
                )
            }
        return NotatedScore(parts: parts)
    }

    private struct KeySignatureContext {
        let keyName: String
        let signature: MajorKeySignature
        /// The mode's own 7 diatonic degrees, correctly spelled per the key signature (e.g. C#,
        /// not the context-free canonical table's "Db") — keyed by pitch class. Only the 7
        /// diatonic degrees are covered; a genuinely chromatic note still falls back to
        /// `DiatonicSpelling.canonicalSpelling(forPitchClass:)` (see `spelledPitch`).
        let diatonicSpellingByPitchClass: [Int: SpelledPitch]
    }

    /// The VexFlow key-name spec (e.g. `"D"`, `"F#"`, `"Bb"`) plus the underlying
    /// `MajorKeySignature` (which letters it affects, needed for per-note accidental
    /// suppression) for the whole score — derived from the first section whose mode resolves to
    /// one of the 7 classic modes (`CircleOfFifths.parentTonic(for:)`, `familyID == 1`); `nil`
    /// for anything else (non-family-1 modes have no conventional key signature).
    private static func keySignatureContext(for piece: Piece) -> KeySignatureContext? {
        for section in piece.sections {
            guard let mode = section.mode.resolve(), let parentTonic = CircleOfFifths.parentTonic(for: mode) else { continue }
            let signature = MajorKeySignature.forMajorTonic(parentTonic.value)
            let spelled = DiatonicSpelling.canonicalSpelling(forPitchClass: parentTonic)
            let accidentalSuffix = spelled.accidental == .sharp ? "#" : (spelled.accidental == .flat ? "b" : "")
            var byPitchClass: [Int: SpelledPitch] = [:]
            for degree in DiatonicSpelling.spelledDegrees(for: mode) ?? [] {
                byPitchClass[degree.pitchClass.value] = degree
            }
            return KeySignatureContext(keyName: "\(spelled.letter)\(accidentalSuffix)", signature: signature, diatonicSpellingByPitchClass: byPitchClass)
        }
        return nil
    }

    // MARK: - Clef / staff layout

    /// Builds the 1 (standalone) or 2 (grand staff, sharing `staffGroupID: rawPart.id`, treble
    /// first then bass) `NotatedPart`s for one raw part — see `staffPlan(forPitches:)`. A grand
    /// staff's two subsets are produced by filtering the part's own notes by pitch BEFORE calling
    /// `buildMeasures` (once per subset), so measure-segmentation/rest-filling/chord-grouping is
    /// reused unchanged: wherever one staff has no notes at a given moment because they're all on
    /// the other staff, `buildMeasures` naturally fills that gap with a rest, exactly as it
    /// already does for a genuinely silent stretch.
    private static func notatedParts(
        for rawPart: RawPart, timeSignatures: [RawTimeSignatureEvent], ticksPerQuarter: Int, minimumTicks: Int = 0,
        colorLookup: ((Int, Int) -> String?)? = nil, keySignature: MajorKeySignature? = nil, keySignatureName: String? = nil,
        diatonicSpelling: [Int: SpelledPitch]? = nil, chordAnnotationsByMeasure: [Int: [ChordAnnotationEntry]]? = nil,
        secondsForTick: ((Int) -> Double)? = nil
    ) -> [NotatedPart] {
        let realNotes = rawPart.notes.filter { !$0.isRest }
        let plan = staffPlan(forPitches: realNotes.map(\.pitch))
        guard plan.count > 1 else {
            return [NotatedPart(
                id: rawPart.id, name: rawPart.name, clef: plan.first ?? .treble, keySignature: keySignatureName,
                measures: buildMeasures(
                    notes: rawPart.notes, timeSignatures: timeSignatures, ticksPerQuarter: ticksPerQuarter, minimumTicks: minimumTicks,
                    colorLookup: colorLookup, keySignature: keySignature, diatonicSpelling: diatonicSpelling,
                    chordAnnotationsByMeasure: chordAnnotationsByMeasure, secondsForTick: secondsForTick
                )
            )]
        }
        return [
            NotatedPart(
                id: "\(rawPart.id)-treble", name: rawPart.name, clef: .treble, staffGroupID: rawPart.id, keySignature: keySignatureName,
                measures: buildMeasures(
                    notes: realNotes.filter { $0.pitch >= 60 }, timeSignatures: timeSignatures, ticksPerQuarter: ticksPerQuarter, minimumTicks: minimumTicks,
                    colorLookup: colorLookup, keySignature: keySignature, diatonicSpelling: diatonicSpelling,
                    chordAnnotationsByMeasure: chordAnnotationsByMeasure, secondsForTick: secondsForTick
                )
            ),
            NotatedPart(
                id: "\(rawPart.id)-bass", name: rawPart.name, clef: .bass, staffGroupID: rawPart.id, keySignature: keySignatureName,
                measures: buildMeasures(
                    notes: realNotes.filter { $0.pitch < 60 }, timeSignatures: timeSignatures, ticksPerQuarter: ticksPerQuarter, minimumTicks: minimumTicks,
                    colorLookup: colorLookup, keySignature: keySignature, diatonicSpelling: diatonicSpelling,
                    chordAnnotationsByMeasure: nil, secondsForTick: secondsForTick // top staff (treble half) only for annotations
                )
            ),
        ]
    }

    /// A single clef (majority register: `.bass` only on a strict majority below middle C/60,
    /// else `.treble`) unless the MINORITY register accounts for more than ~20% of the part's
    /// notes, in which case `[.treble, .bass]` — a real grand-staff split, not just occasional
    /// ledger lines. The 20% threshold is tuned against a real duet file investigated this
    /// session: a Baritone track at 89%/11% below/above C4 reads fine as a single bass staff
    /// with occasional high ledger lines, but a piano part at 75%/25% was illegible as a single
    /// treble staff — enough real low content to need its own staff, not just excursions. MIDI
    /// carries no clef/staff assignment of its own (unlike time/key signature, real meta events);
    /// MusicXML/MuseScore (not yet imported) would carry an exact `<staff>` per note instead of
    /// this heuristic.
    private static func staffPlan(forPitches pitches: [Int]) -> [Clef] {
        guard !pitches.isEmpty else { return [.treble] }
        let belowMiddleC = pitches.filter { $0 < 60 }.count
        let minorityFraction = Double(min(belowMiddleC, pitches.count - belowMiddleC)) / Double(pitches.count)
        if minorityFraction > 0.2 { return [.treble, .bass] }
        return [belowMiddleC * 2 > pitches.count ? .bass : .treble]
    }

    // MARK: - Role-coloring analysis

    /// One harmonic/melodic context spanning `[startTick, endTick)`, derived from a `Section`'s
    /// detected `mode` (shared across the whole section) and its `chordProgression` (one window
    /// per detected chord, or a single chordless window covering the section if none were
    /// detected). Reuses `pitchDisplayState` (`RecognitionEngine`) — the same root/tone
    /// classification the keyboard and `ChordStaffView` already color by — rather than
    /// reinventing it a third time.
    private struct HarmonicWindow {
        let startTick: Int
        let endTick: Int
        let modeTones: [Int]
        /// Kept alongside `modeTones` (rather than re-resolving `Section.mode` later) for the
        /// functional-role coloring's own `familyID`/`scale.degree` lookup (see
        /// `functionalRoleColor(forChordRoot:modeTones:mode:)`) — `nil` exactly when
        /// `section.mode.resolve()` itself failed.
        let mode: Mode?
        let chordRoot: Int?
        let chordTones: [Int]
        /// `ChordVocabulary` id, e.g. `"Ma7"` — `nil` exactly when `chordRoot` is, kept alongside
        /// it (rather than re-resolving `chordRoot`'s `ChordReference` later) for
        /// `RomanNumeralAnalyzer.label`'s per-measure annotations (see
        /// `chordAnnotationsByMeasure(from:measureLengthTicks:ticksPerBeatUnit:)`).
        let chordTemplateID: String?
    }

    /// Mirrors `rawParts(from:)`'s own `sectionStartBeat` accumulation so a chord event's
    /// absolute tick lands on the exact same timeline as the synthetic notes built there.
    private static func harmonicTimeline(from piece: Piece, ticksPerBeatUnit: Int, beatsPerMeasure: Int) -> [HarmonicWindow] {
        var windows: [HarmonicWindow] = []
        var sectionStartBeat = 0.0
        for section in piece.sections {
            let mode = section.mode.resolve()
            let modeTones = mode?.pitchClasses.map(\.value) ?? []
            let sectionLengthBeats = Double(section.lengthInMeasures * beatsPerMeasure)
            let sectionStartTick = Int((sectionStartBeat * Double(ticksPerBeatUnit)).rounded())
            let sectionEndTick = Int(((sectionStartBeat + sectionLengthBeats) * Double(ticksPerBeatUnit)).rounded())

            let sortedChords = section.chordProgression
                .map { event in (event: event, localBeat: section.absoluteBeat(measure: event.measure, beat: event.beat, beatsPerMeasure: beatsPerMeasure)) }
                .sorted { $0.localBeat < $1.localBeat }

            if sortedChords.isEmpty {
                windows.append(HarmonicWindow(startTick: sectionStartTick, endTick: sectionEndTick, modeTones: modeTones, mode: mode, chordRoot: nil, chordTones: [], chordTemplateID: nil))
            } else {
                for (index, entry) in sortedChords.enumerated() {
                    let startTick = Int(((sectionStartBeat + entry.localBeat) * Double(ticksPerBeatUnit)).rounded())
                    let endTick = index + 1 < sortedChords.count
                        ? Int(((sectionStartBeat + sortedChords[index + 1].localBeat) * Double(ticksPerBeatUnit)).rounded())
                        : sectionEndTick
                    let chordTones = entry.event.chord.resolve()?.pitchClasses.map(\.value) ?? []
                    windows.append(HarmonicWindow(
                        startTick: startTick, endTick: endTick, modeTones: modeTones, mode: mode,
                        chordRoot: entry.event.chord.root, chordTones: chordTones, chordTemplateID: entry.event.chord.chordTemplateID
                    ))
                }
            }
            sectionStartBeat += sectionLengthBeats
        }
        return windows
    }

    /// Roman-numeral + chord-symbol annotations, keyed by 0-based GLOBAL measure index (matches
    /// the running counter `buildMeasures` increments once per measure, consistent across every
    /// part's own call since `build(from: Piece)` uses one fixed time signature throughout — see
    /// that function's own `minimumTicks` comment). Reuses the exact `RomanNumeralAnalyzer.label`
    /// lookahead-window shape already validated by the Analyse tab's own golden test
    /// (`HarmonicAnalysisReportTests`) — a second, independent call site over the same pure
    /// function, not a duplicated algorithm (see this feature's own plan for why `AppCore`'s
    /// `HarmonicAnalysisReport`, which walks measure/beat for that tab, isn't reused directly:
    /// `ScoreImport` can't reach `AppCore`).
    private static func chordAnnotationsByMeasure(
        from timeline: [HarmonicWindow], measureLengthTicks: Int, ticksPerBeatUnit: Int
    ) -> [Int: [ChordAnnotationEntry]] {
        guard measureLengthTicks > 0, ticksPerBeatUnit > 0 else { return [:] }
        let chordWindows = timeline.filter { $0.chordRoot != nil && $0.chordTemplateID != nil }
        var result: [Int: [ChordAnnotationEntry]] = [:]
        for (position, window) in chordWindows.enumerated() {
            guard let chordRoot = window.chordRoot, let chordTemplateID = window.chordTemplateID else { continue }
            let lookaheadCount = min(3, chordWindows.count - position - 1)
            let lookahead = (0..<lookaheadCount).compactMap { chordWindows[position + 1 + $0].chordRoot }
            let label = RomanNumeralAnalyzer.label(
                chordRoot: chordRoot, chordTemplateID: chordTemplateID,
                keyTonic: window.modeTones.first ?? 0, modeTones: window.modeTones, lookahead: lookahead
            )
            let measureIndex = window.startTick / measureLengthTicks
            let beat = Double(window.startTick % measureLengthTicks) / Double(ticksPerBeatUnit) + 1.0
            let entry = ChordAnnotationEntry(
                beat: beat, chordSymbol: chordSymbol(forRoot: chordRoot, chordTemplateID: chordTemplateID),
                romanNumeral: label.numeral, isLowConfidence: label.confidence == .low
            )
            result[measureIndex, default: []].append(entry)
        }
        return result
    }

    private static let pitchNamesForChordSymbol = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]

    /// A short letter-name chord symbol (e.g. "G#m7b5") — mirrors `AppCore`'s
    /// `HarmonicAnalysisReport.chordSymbol(for:)` formatting verbatim (that function itself isn't
    /// reachable from here — see `chordAnnotationsByMeasure`'s own doc comment); keep both in
    /// sync if the format ever changes.
    private static func chordSymbol(forRoot root: Int, chordTemplateID: String) -> String {
        let rootName = pitchNamesForChordSymbol[((root % 12) + 12) % 12]
        let suffix: String
        switch chordTemplateID {
        case "Ma": suffix = ""
        case "mi": suffix = "m"
        case "dim": suffix = "dim"
        case "aug": suffix = "+"
        case "7": suffix = "7"
        case "Ma7": suffix = "Ma7"
        case "mi7": suffix = "m7"
        case "mi7b5": suffix = "m7b5"
        case "dim7": suffix = "dim7"
        case "7#5": suffix = "+7"
        case "Ma7#5": suffix = "+Ma7"
        case "miMa7": suffix = "mMa7"
        default: suffix = chordTemplateID
        }
        return rootName + suffix
    }

    /// Colors by the CURRENT CHORD's functional role in its mode (home/away/tension/neutral —
    /// same 4-color classification "Exploration fonctionnelle" already uses, see
    /// `ModalFunctionalRoleTable`), not a fixed 4-hue table per structural role like before: the
    /// note-role *classification* itself (`pitchDisplayState`, `RecognitionEngine`) is unchanged,
    /// only which color each role maps to.
    private static func color(forPitch pitch: Int, atTick tick: Int, in timeline: [HarmonicWindow]) -> String? {
        guard let window = timeline.first(where: { tick >= $0.startTick && tick < $0.endTick }) ?? timeline.last else { return nil }
        let state = pitchDisplayState(
            pitch: pitch, heldPitches: [], chordRoot: window.chordRoot, chordTones: window.chordTones,
            modeTones: window.modeTones, alwaysShowChord: true, showModeColoring: true
        )
        switch state.role {
        case .chordRoot:
            return mixHex(functionalRoleColor(forChordRoot: window.chordRoot, modeTones: window.modeTones, mode: window.mode), towardBlack: 0.3)
        case .chordTone:
            return mixHex(functionalRoleColor(forChordRoot: window.chordRoot, modeTones: window.modeTones, mode: window.mode), towardWhite: 0.45)
        case .modeRoot:
            // The piece's own tonic, held but not currently part of the chord — "the tonic is
            // always the ultimate home," reusing the home hue rather than inventing a new one.
            return mixHex(functionalRoleHex(for: .home), towardWhite: 0.45)
        case .modeTone:
            // Any other scale degree, held but not in the current chord — not creating or
            // resolving tension right now, "neutral" fits.
            return mixHex(functionalRoleHex(for: .neutral), towardWhite: 0.45)
        default:
            return nil
        }
    }

    /// The chord currently sounding's `ModalFunctionalRole` color (green/amber/orange-red/blue,
    /// matching `FunctionalRoleColors.fill(for:)` in `Sources/JamShackUI/FunctionalChordGraph.swift`
    /// exactly — duplicated as plain hex here since this pure-Swift/JS module has no SwiftUI
    /// `Color` of its own). Defaults to `.tension`'s color for anything without a plain diatonic
    /// role: a chromatic/secondary-dominant root (not one of the mode's own 7 pitch classes), a
    /// mode outside the 7 classic modes (`familyID != 1`, no defined role table at all), or no
    /// chord sounding yet — all of these ARE (or read visually like) harmonic tension/deviation,
    /// so defaulting there is musically apt rather than an arbitrary catch-all.
    private static func functionalRoleColor(forChordRoot chordRoot: Int?, modeTones: [Int], mode: Mode?) -> String {
        guard let chordRoot, let mode, mode.scale.familyID == 1,
              let degreeIndex = modeTones.firstIndex(of: chordRoot) else {
            return functionalRoleHex(for: .tension)
        }
        let (role, _) = ModalFunctionalRoleTable.standardRole(forScaleDegree: mode.scale.degree, chordDegree: degreeIndex + 1)
        return functionalRoleHex(for: role)
    }

    private static func functionalRoleHex(for role: ModalFunctionalRole) -> String {
        switch role {
        case .home: return "#2e7d32"
        case .away: return "#f9a825"
        case .tension: return "#e64a19"
        case .neutral: return "#1565c0"
        }
    }

    /// Plain hex-string RGB blending (no SwiftUI `Color` in this module) — same "toward white"
    /// formula `Color.pastel(hex:fraction:)` (`Sources/JamShackUI/Tonnetz.swift`) already uses;
    /// `towardBlack` is the same idea run the other direction, for the chord root's darker tone.
    private static func mixHex(_ hex: String, towardWhite fraction: Double) -> String {
        guard let (r, g, b) = rgbComponents(hex) else { return hex }
        return hexString(r: r + (255 - r) * fraction, g: g + (255 - g) * fraction, b: b + (255 - b) * fraction)
    }

    private static func mixHex(_ hex: String, towardBlack fraction: Double) -> String {
        guard let (r, g, b) = rgbComponents(hex) else { return hex }
        return hexString(r: r * (1 - fraction), g: g * (1 - fraction), b: b * (1 - fraction))
    }

    private static func rgbComponents(_ hex: String) -> (r: Double, g: Double, b: Double)? {
        var text = hex
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        return (Double((value >> 16) & 0xFF), Double((value >> 8) & 0xFF), Double(value & 0xFF))
    }

    private static func hexString(r: Double, g: Double, b: Double) -> String {
        func clamp(_ v: Double) -> Int { max(0, min(255, Int(v.rounded()))) }
        return String(format: "#%02x%02x%02x", clamp(r), clamp(g), clamp(b))
    }

    /// Tracks are matched across sections by name (first-seen order) so a multi-section piece's
    /// timeline stays aligned; a section missing a given name contributes no notes of its own
    /// here — the silence for its span comes from `build(from: Piece)`'s `minimumTicks`, passed
    /// to `buildMeasures` so that section's measures still get generated (as rests) for every
    /// part, not just the ones with real notes in it.
    private static func rawParts(from piece: Piece, ticksPerQuarter: Int, ticksPerBeatUnit: Int, beatsPerMeasure: Int) -> [RawPart] {
        var order: [String] = []
        for section in piece.sections {
            for track in section.tracks where !order.contains(track.name) { order.append(track.name) }
        }

        var notesByName: [String: [RawNote]] = Dictionary(uniqueKeysWithValues: order.map { ($0, []) })
        var sectionStartBeat = 0.0
        for section in piece.sections {
            for track in section.tracks {
                let notes = track.melodyEvents.map { event -> RawNote in
                    let localBeat = section.absoluteBeat(measure: event.measure, beat: event.beat, beatsPerMeasure: beatsPerMeasure)
                    let startTick = Int(((sectionStartBeat + localBeat) * Double(ticksPerBeatUnit)).rounded())
                    let durationTicks = max(Int((event.durationBeats * Double(ticksPerBeatUnit)).rounded()), 1)
                    return RawNote(startTick: startTick, durationTicks: durationTicks, pitch: event.pitch, velocity: event.velocity)
                }
                notesByName[track.name, default: []].append(contentsOf: notes)
            }
            sectionStartBeat += Double(section.lengthInMeasures * beatsPerMeasure)
        }

        return order.map { name in
            RawPart(id: name, name: name, notes: (notesByName[name] ?? []).sorted { $0.startTick < $1.startTick })
        }
    }

    public static func build(from rawScore: RawScore) -> NotatedScore {
        let ticksPerQuarter = max(rawScore.divisionsPerQuarterNote, 1)
        let timeSignatures = rawScore.timeSignatureMap.isEmpty
            ? [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)]
            : rawScore.timeSignatureMap.sorted { $0.tick < $1.tick }

        let parts = rawScore.parts.flatMap { rawPart in
            notatedParts(for: rawPart, timeSignatures: timeSignatures, ticksPerQuarter: ticksPerQuarter)
        }
        return NotatedScore(parts: parts)
    }

    // MARK: - Measure segmentation

    /// `minimumTicks` (default 0, i.e. no effect on the real-import path in `build(from:
    /// RawScore)`) forces at least that many ticks' worth of measures to be generated even past
    /// this part's own last note — used only by `build(from: Piece)`, so a track absent from a
    /// later section still gets that section's silent measures instead of ending early and
    /// throwing every other part's measure alignment off.
    private static func buildMeasures(
        notes: [RawNote], timeSignatures: [RawTimeSignatureEvent], ticksPerQuarter: Int, minimumTicks: Int = 0,
        colorLookup: ((Int, Int) -> String?)? = nil, keySignature: MajorKeySignature? = nil,
        diatonicSpelling: [Int: SpelledPitch]? = nil, chordAnnotationsByMeasure: [Int: [ChordAnnotationEntry]]? = nil,
        secondsForTick: ((Int) -> Double)? = nil
    ) -> [NotatedMeasure] {
        let sortedNotes = notes.filter { !$0.isRest }.sorted { $0.startTick < $1.startTick }
        guard !sortedNotes.isEmpty || minimumTicks > 0 else { return [] }

        var measures: [NotatedMeasure] = []
        var measureStart = 0
        var noteIndex = 0
        var timeSignatureIndex = 0
        var measureIndex = 0

        // Driven by how many *notes* remain (or `minimumTicks`, for a Piece part with no notes
        // at all in one or more sections), not by notes' (possibly long, since-clipped) raw end
        // ticks — a note that would have spanned past a measure gets clipped to fit (see the
        // type's doc comment on ties), so its discarded tail must NOT spawn extra trailing
        // rest-only measures. Each iteration is guaranteed to make progress: either it consumes
        // the next unconsumed note once `measureEnd` grows past its start tick, or `measureEnd`
        // itself keeps growing toward `minimumTicks`, so this always terminates.
        while noteIndex < sortedNotes.count || measureStart < minimumTicks {
            while timeSignatureIndex + 1 < timeSignatures.count, timeSignatures[timeSignatureIndex + 1].tick <= measureStart {
                timeSignatureIndex += 1
            }
            let timeSignature = timeSignatures[timeSignatureIndex]
            let ticksPerBeatUnit = ticksPerQuarter * 4 / max(timeSignature.beatUnit, 1)
            let measureLength = max(timeSignature.beatsPerMeasure, 1) * ticksPerBeatUnit
            let measureEnd = measureStart + measureLength

            var positions: [(startTick: Int, durationTicks: Int, notes: [(pitch: Int, spelling: RawSpelling?)])] = []
            while noteIndex < sortedNotes.count, sortedNotes[noteIndex].startTick < measureEnd {
                let note = sortedNotes[noteIndex]
                if !positions.isEmpty, positions[positions.count - 1].startTick == note.startTick,
                   positions[positions.count - 1].durationTicks == note.durationTicks {
                    positions[positions.count - 1].notes.append((note.pitch, note.spelling))
                } else {
                    positions.append((note.startTick, note.durationTicks, [(note.pitch, note.spelling)]))
                }
                noteIndex += 1
            }

            var measureNotes: [NotatedNote] = []
            var cursor = measureStart
            // Reset every measure — an accidental (or the key signature's own implied
            // alteration) only holds for the rest of the SAME measure, standard engraving rule.
            var accidentalTracker: [String: Int] = [:]
            for position in positions {
                if position.startTick > cursor {
                    measureNotes.append(contentsOf: rests(from: cursor, to: position.startTick, ticksPerQuarter: ticksPerQuarter))
                }
                let clippedDuration = min(position.durationTicks, measureEnd - position.startTick)
                measureNotes.append(NotatedNote(
                    id: UUID().uuidString, isRest: false,
                    keys: position.notes.map { vexFlowKey(forPitch: $0.pitch, spelling: $0.spelling, diatonicSpelling: diatonicSpelling) },
                    duration: quantizedDuration(ticks: clippedDuration, ticksPerQuarter: ticksPerQuarter),
                    pitches: position.notes.map(\.pitch),
                    colors: colorLookup.map { lookup in position.notes.map { lookup($0.pitch, position.startTick) } },
                    accidentals: keySignature.map { signature in
                        position.notes.map {
                            accidentalGlyph(forPitch: $0.pitch, spelling: $0.spelling, diatonicSpelling: diatonicSpelling, keySignature: signature, tracker: &accidentalTracker)
                        }
                    },
                    startSeconds: secondsForTick?(position.startTick),
                    durationSeconds: secondsForTick.map { toSeconds in toSeconds(position.startTick + clippedDuration) - toSeconds(position.startTick) }
                ))
                cursor = position.startTick + clippedDuration
            }
            if cursor < measureEnd {
                measureNotes.append(contentsOf: rests(from: cursor, to: measureEnd, ticksPerQuarter: ticksPerQuarter))
            }

            measures.append(NotatedMeasure(
                beatsPerMeasure: timeSignature.beatsPerMeasure, beatUnit: timeSignature.beatUnit, notes: measureNotes,
                chordAnnotations: chordAnnotationsByMeasure?[measureIndex] ?? []
            ))
            measureStart = measureEnd
            measureIndex += 1
        }
        return measures
    }

    // MARK: - Duration quantization

    /// (duration in quarter notes, VexFlow code), descending — used both to find the nearest
    /// standard value for an actual note and to greedily fill rest gaps largest-first.
    private static let standardDurations: [(quarters: Double, code: String)] = [
        (4.0, "w"), (3.0, "hd"), (2.0, "h"), (1.5, "qd"), (1.0, "q"),
        (0.75, "8d"), (0.5, "8"), (0.375, "16d"), (0.25, "16"), (0.125, "32"),
    ]

    private static func quantizedDuration(ticks: Int, ticksPerQuarter: Int) -> String {
        guard ticks > 0 else { return "32" }
        let quarters = Double(ticks) / Double(ticksPerQuarter)
        let best = standardDurations.min { abs($0.quarters - quarters) < abs($1.quarters - quarters) }
        return best?.code ?? "q"
    }

    private static func ticks(forQuarters quarters: Double, ticksPerQuarter: Int) -> Int {
        Int((quarters * Double(ticksPerQuarter)).rounded())
    }

    /// Fills a gap with rests, picking the largest standard duration that fits at each step
    /// (never overshooting past `to`) — a `safetyLimit` bounds the loop defensively, since a
    /// pathological tick value should degrade to "one oddly-sized rest" rather than hang.
    private static func rests(from start: Int, to end: Int, ticksPerQuarter: Int) -> [NotatedNote] {
        var result: [NotatedNote] = []
        var cursor = start
        var safetyLimit = 64
        while cursor < end, safetyLimit > 0 {
            safetyLimit -= 1
            let remaining = end - cursor
            let chosen = standardDurations.first { ticks(forQuarters: $0.quarters, ticksPerQuarter: ticksPerQuarter) <= remaining }
            let code = chosen?.code ?? "32"
            let consumed = max(chosen.map { ticks(forQuarters: $0.quarters, ticksPerQuarter: ticksPerQuarter) } ?? remaining, 1)
            result.append(NotatedNote(id: UUID().uuidString, isRest: true, duration: code))
            cursor += consumed
        }
        return result
    }

    // MARK: - Pitch spelling

    private static func vexFlowAccidentalCode(fromAlter alter: Int) -> String {
        switch alter {
        case -2: return "bb"
        case -1: return "b"
        case 1: return "#"
        case 2: return "##"
        default: return ""
        }
    }

    private static let noteLetterByStep: [String: NoteLetter] = ["C": .C, "D": .D, "E": .E, "F": .F, "G": .G, "A": .A, "B": .B]

    /// The source's own spelling when available (MusicXML/MuseScore); otherwise `diatonicSpelling`
    /// (the mode's own 7 degrees correctly spelled against the key signature, e.g. C# rather than
    /// the context-free canonical table's "Db") for a diatonic pitch class, falling back to
    /// `DiatonicSpelling.canonicalSpelling` only for a genuinely chromatic one — shared by
    /// `vexFlowKey` (the "keys" string) and `accidentalGlyph` (the key-signature-aware accidental
    /// decision), so both always agree on what a note IS.
    private static func spelledPitch(forPitch pitch: Int, spelling: RawSpelling?, diatonicSpelling: [Int: SpelledPitch]?) -> (letter: NoteLetter, alter: Int, octave: Int) {
        if let spelling, let letter = noteLetterByStep[spelling.step.uppercased()] {
            return (letter, spelling.alter, spelling.octave)
        }
        let pitchClassValue = ((pitch % 12) + 12) % 12
        let octave = pitch / 12 - 1
        if let diatonic = diatonicSpelling?[pitchClassValue] {
            return (diatonic.letter, diatonic.accidental.rawValue, octave)
        }
        let spelled = DiatonicSpelling.canonicalSpelling(forPitchClass: PitchClass(pitchClassValue))
        return (spelled.letter, spelled.accidental.rawValue, octave)
    }

    private static func vexFlowKey(forPitch pitch: Int, spelling: RawSpelling?, diatonicSpelling: [Int: SpelledPitch]? = nil) -> String {
        let spelled = spelledPitch(forPitch: pitch, spelling: spelling, diatonicSpelling: diatonicSpelling)
        let letter = String(describing: spelled.letter).lowercased()
        return "\(letter)\(vexFlowAccidentalCode(fromAlter: spelled.alter))/\(spelled.octave)"
    }

    private static func accidentalSymbol(forAlter alter: Int) -> String {
        switch alter {
        case -2: return "bb"
        case -1: return "b"
        case 1: return "#"
        case 2: return "##"
        default: return "n"
        }
    }

    /// Whether (and what) accidental glyph a specific stacked pitch should show, given the
    /// score's key signature and whatever's already been shown for that exact (letter, octave)
    /// earlier in the SAME measure (`tracker`, reset once per measure by the caller) — standard
    /// engraving rule: an accidental (or the key signature's own implied alteration) holds until
    /// the next barline. Returns `nil` when nothing needs drawing (the note already matches
    /// what's currently in effect for its letter+octave).
    private static func accidentalGlyph(
        forPitch pitch: Int, spelling: RawSpelling?, diatonicSpelling: [Int: SpelledPitch]?, keySignature: MajorKeySignature, tracker: inout [String: Int]
    ) -> String? {
        let spelled = spelledPitch(forPitch: pitch, spelling: spelling, diatonicSpelling: diatonicSpelling)
        let impliedAlter = keySignature.affectedLetters.contains(spelled.letter)
            ? (keySignature.accidentalDirection == .sharp ? 1 : -1)
            : 0
        let trackerKey = "\(spelled.letter.rawValue)\(spelled.octave)"
        let currentlyInEffect = tracker[trackerKey] ?? impliedAlter
        guard spelled.alter != currentlyInEffect else { return nil }
        tracker[trackerKey] = spelled.alter
        return accidentalSymbol(forAlter: spelled.alter)
    }
}
