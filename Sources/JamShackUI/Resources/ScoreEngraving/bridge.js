// Bridge between the native app and VexFlow (vendored as vexflow.js, loaded before this file —
// see score.html). Swift pushes a `NotatedScore`-shaped JSON object via
// `window.renderScore(score)` (called through WKWebView's `callAsyncJavaScript`); this file only
// draws it and forwards note taps back to Swift over `window.webkit.messageHandlers.noteAction`.
// Deliberately dumb: no musical logic here — quantization, spelling, clef choice, and role
// coloring all happen natively in Swift (see ScoreImport's ScoreEngravingAdapter), so this stays
// a pure renderer that could be swapped (e.g. for abcjs) without touching any Swift code.

function accidentalCodeFromKey(key) {
    const match = key.match(/^[a-g]([#b]*)\//i);
    return match && match[1] ? match[1] : null;
}

function postNoteAction(meta, action) {
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.noteAction) {
        window.webkit.messageHandlers.noteAction.postMessage({
            noteID: meta.id,
            action: action,
            pitches: meta.pitches,
        });
    }
}

// VexFlow's default rest key ("b/4") is the treble-clef middle line; a bass-clef stave's middle
// line is "d/3" — using the treble one on a bass stave would draw the rest floating off-center.
function restKeyForClef(clef) {
    return clef === "bass" ? "d/3" : "b/4";
}

// Same (quarters, code) table `ScoreEngravingAdapter.standardDurations` (Swift) uses — needed
// here to find which note a `NotatedMeasure.chordAnnotations` entry's `beat` lands closest to
// (VexFlow has no "beat position of tickable N" query before formatting has actually run).
const DURATION_BEATS = { w: 4, hd: 3, h: 2, qd: 1.5, q: 1, "8d": 0.75, "8": 0.5, "16d": 0.375, "16": 0.25, "32": 0.125 };

function buildVoice(part, measure) {
    let cumulativeBeat = 1; // 1-based, matches `ChordAnnotationEntry.beat`'s own convention
    const noteStartBeats = measure.notes.map((n) => {
        const startBeat = cumulativeBeat;
        cumulativeBeat += DURATION_BEATS[n.duration] || 1;
        return startBeat;
    });

    const vfNotes = measure.notes.map((n) => {
        const note = new VF.StaveNote({
            keys: n.isRest ? [restKeyForClef(part.clef)] : n.keys,
            duration: n.duration + (n.isRest ? "r" : ""),
            clef: part.clef || "treble",
            autoStem: true, // conventional up-for-low/down-for-high stem direction, not a fixed one
        });
        if (!n.isRest) {
            n.keys.forEach((key, i) => {
                // `n.accidentals[i]` (Swift-computed, key-signature-aware) takes priority when
                // present; falls back to deriving one from the key string itself (every non-
                // natural letter gets its own accidental, today's raw-file-preview behavior) only
                // when Swift did no such analysis at all (`n.accidentals` absent, not just this
                // entry `null` — a `null` entry there is a real, deliberate "nothing to draw").
                const code = n.accidentals ? n.accidentals[i] : accidentalCodeFromKey(key);
                if (code) note.addModifier(new VF.Accidental(code), i);
                const color = n.colors && n.colors[i];
                if (color) note.setKeyStyle(i, { fillStyle: color, strokeStyle: color });
            });
        }
        return note;
    });

    // Chord/Roman-numeral annotations (only ever present on the top staff's own measures — see
    // `ScoreEngravingAdapter`) — attached to whichever note starts closest to the entry's own
    // beat, as two stacked `VF.Annotation` modifiers (VexFlow spaces them vertically on its own).
    (measure.chordAnnotations || []).forEach((annotation) => {
        let bestIndex = 0, bestDiff = Infinity;
        noteStartBeats.forEach((beat, i) => {
            const diff = Math.abs(beat - annotation.beat);
            if (diff < bestDiff) { bestDiff = diff; bestIndex = i; }
        });
        const note = vfNotes[bestIndex];
        const weight = annotation.isLowConfidence ? "italic" : "";
        const color = annotation.isLowConfidence ? "#b0672a" : "#333333"; // muted/amber = needs review, matching the Analyse tab's own marker
        [annotation.chordSymbol, annotation.romanNumeral].forEach((text) => {
            const label = new VF.Annotation(text)
                .setFont("Arial", 10, weight)
                .setVerticalJustification(VF.Annotation.VerticalJustify.BOTTOM);
            label.setStyle({ fillStyle: color, strokeStyle: color });
            note.addModifier(label, 0);
        });
    });

    const voice = new VF.Voice({
        num_beats: measure.beatsPerMeasure,
        beat_value: measure.beatUnit,
        numBeats: measure.beatsPerMeasure,
        beatValue: measure.beatUnit,
    });
    voice.setStrict(false); // our own quantization/clipping won't always sum exactly to a full measure
    voice.addTickables(vfNotes);
    return { measure, vfNotes, voice };
}

// One measure COLUMN across every part that has a measure at that index, joined into ONE shared
// Formatter — built fresh each call (see the 3-pass structure in `renderScore` below) since
// rebuilding rather than reusing the same VexFlow objects across draws avoids any doubt about
// whether formatting/drawing twice is safe.
//
// Joining every simultaneous voice into one Formatter (rather than formatting each part's voice
// on its own, which is what this used to do) is what keeps notes on the same beat aligned
// vertically across staves: VexFlow's formatter spaces notes accounting for glyph width, not
// just tick position, so two voices formatted independently can drift apart the moment their
// note shapes differ (an accidental, a chord stack, a different rhythm) even at the same tick —
// only a shared formatter guarantees the same tick lands at the same x on every staff.
function buildMeasureColumn(parts, measureIndex) {
    const entries = [];
    parts.forEach((part, partIndex) => {
        const measure = part.measures[measureIndex];
        if (measure) entries.push({ partIndex, ...buildVoice(part, measure) });
    });
    const voices = entries.map((e) => e.voice);
    const formatter = new VF.Formatter().joinVoices(voices);
    const minWidth = voices.length ? formatter.preCalculateMinTotalWidth(voices) : 0;
    return { entries, formatter, minWidth };
}

// Different clefs draw different-width header glyphs (a bass clef isn't the same width as a
// treble one) — given the SAME total stave width, `Stave.getNoteStartX()` (where the note area
// begins, right after the header) then differs between them, shifting every note in that voice
// by a constant amount relative to a sibling stave with a different clef. `Stave.setNoteStartX`
// is VexFlow's own answer to this (used for any multi-stave system, not just ours): force every
// stave in a measure column to share the widest `getNoteStartX()` among them BEFORE formatting,
// so a beat lines up at the same x on every staff regardless of that staff's own clef glyph
// width.
function equalizeNoteStartX(staves) {
    if (staves.length < 2) return;
    const maxNoteStartX = Math.max(...staves.map((s) => s.getNoteStartX()));
    staves.forEach((s) => s.setNoteStartX(maxNoteStartX));
}

let VF; // set on first renderScore() call

window.renderScore = function (score) {
    const container = document.getElementById("score");
    container.innerHTML = "";
    if (!score || !score.parts || score.parts.length === 0) return;

    VF = window.VexFlow;
    window.__lastRenderedScore = score; // re-drawn on resize, see the listener at the bottom

    // Overall zoom-out, applied by scaling the final render context (see the real `VF.Renderer`
    // setup below) rather than touching any layout constant — every measurement everywhere else
    // in this function stays in the same "logical" units it always has.
    //
    // Note: this does NOT fix the deeper reason a dense piano measure (an arpeggiated
    // accompaniment, 8-11 notes) can need 700-1100 logical px on its own via VexFlow's
    // `Formatter.preCalculateMinTotalWidth` — confirmed against the real *An die Musik* import,
    // whose 43 measures each land in their own single-measure system regardless of a reasonable
    // scale, since even two of the piece's SMALLEST measures combined already exceed a typical
    // window's available width. A meaningful chunk of that per-measure width used to be
    // redundant accidentals (every single F#/C# occurrence, even ones the key signature already
    // implies) — `ScoreEngravingAdapter` now draws a real key signature and suppresses those, but
    // that alone doesn't fully close the gap for this piece's own dense arpeggios.
    const RENDER_SCALE = 0.82;

    const minMeasureWidth = 120;
    const notePadding = 40; // breathing room for the note area inside a measure
    const clefPadding = 30; // extra room for a clef repeated at the start of every system
    const timeSigPadding = 30; // extra room for the time signature, first measure of the piece only
    // ~1 accidental's worth of extra room per system start, when a key signature is drawn there —
    // an approximation (VexFlow's own `getNoteStartX()` is the real source of truth, consulted via
    // `equalizeNoteStartX` at actual draw time either way), just enough that the packing pass
    // above doesn't systematically under-budget a keyed system's first measure.
    function keySigPadding(part) {
        return part.keySignature ? 30 : 0;
    }
    const defaultStaveSpan = 40; // a standard 5-line stave, top line to bottom line
    const staveMargin = 20; // minimum breathing room above/below a stave before the next one
    const interSystemGap = 30;
    const leftMargin = 24; // room for a StaveConnector's brace/line glyph, drawn left of the staves' own x
    const topMargin = 20;

    // Contiguous runs of parts sharing a non-null `staffGroupID` — sibling grand-staff staves of
    // one logical track (see `NotatedPart.staffGroupID`'s own doc comment), guaranteed adjacent
    // in `score.parts` by construction in `ScoreEngravingAdapter`. Get a connecting brace; every
    // system also gets one thin line spanning ALL its staves regardless of grouping (see the
    // connector-drawing code at the end of the final render pass below).
    const staffGroups = [];
    score.parts.forEach((part, partIndex) => {
        const id = part.staffGroupID;
        if (!id) return;
        const last = staffGroups[staffGroups.length - 1];
        if (last && last.id === id && last.end === partIndex - 1) {
            last.end = partIndex;
        } else {
            staffGroups.push({ id, start: partIndex, end: partIndex });
        }
    });

    let totalMeasures = 0;
    score.parts.forEach((part) => (totalMeasures = Math.max(totalMeasures, part.measures.length)));

    // Pass 0: one shared-Formatter measure column per index, purely to read each column's own
    // minimum content width and pack measures into systems that fit the real available width,
    // without ever truncating a measure.
    const measureWidths = [];
    for (let m = 0; m < totalMeasures; m++) {
        const { minWidth } = buildMeasureColumn(score.parts, m);
        measureWidths.push(Math.max(minMeasureWidth, minWidth + notePadding));
    }

    // All parts share the same key signature (one per whole score, see `ScoreEngravingAdapter`),
    // so a single shared padding value is enough for the width/packing estimate below.
    const sharedKeySigPadding = score.parts.length ? keySigPadding(score.parts[0]) : 0;
    function firstInSystemPadding(measureIndex) {
        return clefPadding + sharedKeySigPadding + (measureIndex === 0 ? timeSigPadding : 0);
    }

    // In logical units — divide the physical container width by the scale so packing decisions
    // account for the fact that the final render will be smaller than these logical pixels.
    const availableWidth = Math.max(container.clientWidth / RENDER_SCALE - 2 * leftMargin, minMeasureWidth + clefPadding + sharedKeySigPadding + timeSigPadding);
    const systems = []; // { start, end (exclusive) } measure-index ranges
    let systemStart = 0, systemWidth = 0;
    for (let m = 0; m < totalMeasures; m++) {
        const w = measureWidths[m] + (m === systemStart ? firstInSystemPadding(m) : 0);
        if (systemWidth > 0 && systemWidth + w > availableWidth) {
            systems.push({ start: systemStart, end: m });
            systemStart = m;
            systemWidth = 0;
        }
        systemWidth += measureWidths[m] + (m === systemStart ? firstInSystemPadding(m) : 0);
    }
    systems.push({ start: systemStart, end: totalMeasures });

    function renderedWidth(measureIndex, isFirstInSystem) {
        return measureWidths[measureIndex] + (isFirstInSystem ? firstInSystemPadding(measureIndex) : 0);
    }

    // Pass 1: draw once into a detached (never-appended) SVG at the default row spacing, purely
    // to read each note's real pixel bounding box back — the same "measure, then use the real
    // number" idea as the width pass above, applied to height, since a fixed row height caused
    // notes far below/above the stave to clip into the neighboring part.
    const probeRenderer = new VF.Renderer(document.createElement("div"), VF.Renderer.Backends.SVG);
    probeRenderer.resize(Math.max(600, measureWidths.reduce((sum, w) => sum + w, 0) + 100), score.parts.length * (defaultStaveSpan + 2 * staveMargin) + 40);
    const probeContext = probeRenderer.getContext();

    const probeY = score.parts.map((_, i) => topMargin + i * (defaultStaveSpan + 2 * staveMargin));
    const probeX = score.parts.map(() => leftMargin);
    const probeBounds = score.parts.map((_, i) => ({ minY: probeY[i], maxY: probeY[i] + defaultStaveSpan }));

    for (let m = 0; m < totalMeasures; m++) {
        const { entries, formatter } = buildMeasureColumn(score.parts, m);
        const voices = entries.map((e) => e.voice);
        const isFirstInSystem = systems.some((s) => s.start === m);
        const width = renderedWidth(m, isFirstInSystem);

        const staves = entries.map(({ partIndex }) => {
            const part = score.parts[partIndex];
            const stave = new VF.Stave(probeX[partIndex], probeY[partIndex], width);
            if (isFirstInSystem) {
                stave.addClef(part.clef || "treble");
                if (part.keySignature) stave.addKeySignature(part.keySignature);
            }
            return stave;
        });
        equalizeNoteStartX(staves);
        if (voices.length) formatter.format(voices, width - notePadding);

        entries.forEach(({ partIndex, vfNotes, voice }, i) => {
            const stave = staves[i];
            stave.setContext(probeContext).draw();
            voice.draw(probeContext, stave);
            const beams = VF.Beam.generateBeams(vfNotes.filter((n) => !n.isRest));
            beams.forEach((b) => b.setContext(probeContext).draw());
            vfNotes.forEach((note) => {
                const bb = note.getBoundingBox();
                if (bb) {
                    probeBounds[partIndex].minY = Math.min(probeBounds[partIndex].minY, bb.y);
                    probeBounds[partIndex].maxY = Math.max(probeBounds[partIndex].maxY, bb.y + bb.h);
                }
            });
            probeX[partIndex] += width;
        });
    }

    const rowHeights = score.parts.map((_, i) => {
        const overflowAbove = Math.max(0, probeY[i] - probeBounds[i].minY);
        const overflowBelow = Math.max(0, probeBounds[i].maxY - (probeY[i] + defaultStaveSpan));
        return defaultStaveSpan + overflowAbove + overflowBelow + 2 * staveMargin;
    });

    // Pass 2: the real render — systems stacked top to bottom, each holding every part's stave
    // for that system's measure range at the row heights computed above (uniform across the
    // whole piece, not recomputed per system, so stave spacing stays consistent throughout).
    const systemHeight = rowHeights.reduce((sum, h) => sum + h, 0);
    const totalHeight = systems.length * systemHeight + (systems.length - 1) * interSystemGap + topMargin;
    // Still logical units, same reasoning as `availableWidth` above.
    const totalWidth = Math.max(
        (container.clientWidth || 0) / RENDER_SCALE,
        ...systems.map((s) => {
            let w = leftMargin;
            for (let m = s.start; m < s.end; m++) w += renderedWidth(m, m === s.start);
            return w + leftMargin;
        })
    );

    const renderer = new VF.Renderer(container, VF.Renderer.Backends.SVG);
    // Physical pixels: the logical width/height computed above, shrunk by RENDER_SCALE.
    renderer.resize(Math.max(600, totalWidth) * RENDER_SCALE, Math.max(300, totalHeight) * RENDER_SCALE);
    const context = renderer.getContext();
    // Sets the SVG's viewBox back to the logical (un-shrunk) coordinate space — everything
    // drawn below (staves, notes, AND the highlight layer appended later, since viewBox governs
    // the whole <svg>, not just VexFlow's own drawn elements) keeps using the same logical
    // coordinates as the layout math above, but renders visually smaller.
    context.scale(RENDER_SCALE, RENDER_SCALE);

    // Collected below (one entry per rendered note, rests excluded) for `window.highlightPitches`.
    const noteEntries = [];

    systems.forEach((system, systemIndex) => {
        const systemY = topMargin + systemIndex * (systemHeight + interSystemGap);
        const partX = score.parts.map(() => leftMargin);
        const firstStaves = []; // this system's first-measure Stave per part, for the connectors below

        for (let m = system.start; m < system.end; m++) {
            const { entries, formatter } = buildMeasureColumn(score.parts, m);
            const voices = entries.map((e) => e.voice);
            const isFirstInSystem = m === system.start;
            const width = renderedWidth(m, isFirstInSystem);

            const staves = entries.map(({ partIndex, measure }) => {
                const part = score.parts[partIndex];
                const y = systemY + rowHeights.slice(0, partIndex).reduce((sum, h) => sum + h, 0);
                const stave = new VF.Stave(partX[partIndex], y, width);
                if (isFirstInSystem) {
                    stave.addClef(part.clef || "treble");
                    if (part.keySignature) stave.addKeySignature(part.keySignature);
                    if (m === 0) stave.addTimeSignature(measure.beatsPerMeasure + "/" + measure.beatUnit);
                }
                return stave;
            });
            equalizeNoteStartX(staves); // must run AFTER every modifier (clef, key/time sig) is added — see its own doc comment
            if (voices.length) formatter.format(voices, width - notePadding);

            // Measure number, above the top staff's own stave — no VexFlow API for this (grepped
            // vexflow.js: `Note.setMeasure` is an unrelated plain data field, no glyph), so drawn
            // with the same raw context text primitive the rest of this function already relies
            // on for non-note-modifier drawing. Every measure, not just each system's first — most
            // systems here hold only 1-2 measures (see `RENDER_SCALE`'s own doc comment), so
            // numbering only the first would leave most measures unlabeled.
            if (staves.length) {
                context.save();
                context.setFont("10px Arial");
                context.fillText(String(m + 1), staves[0].getX() + 2, staves[0].getYForLine(0) - 6);
                context.restore();
            }

            entries.forEach(({ partIndex, measure, vfNotes, voice }, entryIndex) => {
                const stave = staves[entryIndex];
                if (isFirstInSystem) firstStaves[partIndex] = stave;
                stave.setContext(context).draw();
                voice.draw(context, stave);

                const beams = VF.Beam.generateBeams(vfNotes.filter((n) => !n.isRest));
                beams.forEach((b) => b.setContext(context).draw());

                vfNotes.forEach((note, noteIndex) => {
                    const meta = measure.notes[noteIndex];
                    const el = note.getSVGElement();
                    if (el) {
                        el.style.cursor = "pointer";
                        el.addEventListener("click", () => postNoteAction(meta, "tap"));
                    }
                    if (!meta.isRest && meta.pitches && meta.pitches.length) {
                        const bb = note.getBoundingBox();
                        // `systemY`/`systemHeight` (this system's own top y and total height) let
                        // `window.highlightPitches` draw a playhead band spanning the WHOLE
                        // system, not just this one note's own bounding box.
                        if (bb) {
                            noteEntries.push({
                                pitches: meta.pitches, bbox: bb, systemTop: systemY, systemHeight: systemHeight,
                                startSeconds: meta.startSeconds, durationSeconds: meta.durationSeconds,
                            });
                        }
                    }
                });

                partX[partIndex] += width;
            });
        }

        // One thin line spans every staff in the system regardless of grouping; a brace
        // additionally groups each grand staff's own sibling pair — never the whole system,
        // and never two genuinely different tracks (e.g. Soprano/Baritone) that just happen to
        // sit next to each other. Filtered for `Boolean` since a part missing a measure at this
        // exact system's start (only possible for `build(from: RawScore)`'s uneven-length parts)
        // would otherwise leave a hole in `firstStaves`.
        const validFirstStaves = firstStaves.filter(Boolean);
        if (validFirstStaves.length > 1) {
            new VF.StaveConnector(validFirstStaves[0], validFirstStaves[validFirstStaves.length - 1])
                .setType("singleLeft").setContext(context).draw();
        }
        staffGroups.forEach((group) => {
            if (firstStaves[group.start] && firstStaves[group.end]) {
                new VF.StaveConnector(firstStaves[group.start], firstStaves[group.end])
                    .setType("brace").setContext(context).draw();
            }
        });
    });

    // A separate SVG layer drawn BEHIND every note (inserted as the first child) rather than
    // recoloring note glyphs directly: role-coloring already sets an INLINE `fill`/`stroke` on
    // individual noteheads (`setKeyStyle`), which would always outrank a CSS class toggle — a
    // halo behind the note works regardless of whatever color that note already has.
    const svgElement = container.querySelector("svg");
    let highlightLayer = null;
    if (svgElement) {
        highlightLayer = document.createElementNS("http://www.w3.org/2000/svg", "g");
        svgElement.insertBefore(highlightLayer, svgElement.firstChild);
    }
    window.__noteEntries = noteEntries;
    window.__highlightLayer = highlightLayer;
    window.highlightPitches(window.__lastHighlightedPitches || [], window.__lastElapsedSeconds || 0);
};

// Called by the native side whenever the set of currently-sounding pitches (or the elapsed
// playback position) changes (see `ScoreEngravingCoordinator.highlight(_:elapsedSeconds:in:)`) —
// deliberately NOT part of `renderScore`'s own layout passes: re-running the whole 3-pass render
// on every note onset/offset would be far too heavy for something that can fire many times a
// second.
//
// Draws one greyed vertical band per matching note — a narrow cursor at that note's own x,
// spanning its system's FULL height (not just the note's own bounding box). A note matches only
// when BOTH its pitch is in `pitches` AND `elapsedSeconds` falls within its own
// `[startSeconds, startSeconds + durationSeconds)` window (a small epsilon tolerance for
// scheduling/floating-point slop) — pitch alone isn't enough: the same pitch commonly recurs many
// times within one measure in exactly the arpeggiated-accompaniment texture this app's own real
// test file uses, so an earlier version (pitch-only matching) lit up every occurrence of a
// repeating pitch instead of just the one actually sounding. `startSeconds`/`durationSeconds` are
// `undefined` for a score with no tempo context (the raw-file preview, `build(from: RawScore)`) —
// falls back to pitch-only matching there, same as before this fix (that path currently has no
// playback highlight at all, but degrades safely if it ever does).
window.highlightPitches = function (pitches, elapsedSeconds) {
    window.__lastHighlightedPitches = pitches;
    window.__lastElapsedSeconds = elapsedSeconds;
    const layer = window.__highlightLayer;
    if (!layer) return;
    while (layer.firstChild) layer.removeChild(layer.firstChild);
    const active = new Set(pitches);
    const padding = 4;
    // Tolerance on the LOWER bound only (tiny float-precision slop) — `playbackElapsedSeconds`
    // is always set to a note's own exact intended `startSeconds` in the same closure that
    // triggers this push, so there's no real scheduling slop to accommodate on the upper bound.
    // Adding tolerance there too would make two back-to-back notes (no gap, common in this app's
    // own real test file) both match at their shared boundary instant — an exclusive upper bound
    // resolves that ambiguity in favor of the note that's just starting.
    const epsilon = 0.001;
    (window.__noteEntries || []).forEach((entry) => {
        if (!entry.pitches.some((p) => active.has(p))) return;
        if (entry.startSeconds !== undefined && entry.durationSeconds !== undefined) {
            const withinWindow = elapsedSeconds >= entry.startSeconds - epsilon
                && elapsedSeconds < entry.startSeconds + entry.durationSeconds;
            if (!withinWindow) return;
        }
        const rect = document.createElementNS("http://www.w3.org/2000/svg", "rect");
        rect.setAttribute("x", entry.bbox.x - padding);
        rect.setAttribute("y", entry.systemTop);
        rect.setAttribute("width", entry.bbox.w + 2 * padding);
        rect.setAttribute("height", entry.systemHeight);
        rect.setAttribute("fill", "#888888");
        rect.setAttribute("fill-opacity", "0.25");
        layer.appendChild(rect);
    });
};

// A real, non-modal screen can resize (window resize on macOS, rotation on iOS/iPadOS) — the
// small fixed-size sheet this view used to live in never needed this. Debounced since resize
// fires continuously while dragging.
let resizeTimer = null;
window.addEventListener("resize", () => {
    if (!window.__lastRenderedScore) return;
    clearTimeout(resizeTimer);
    resizeTimer = setTimeout(() => window.renderScore(window.__lastRenderedScore), 150);
});
