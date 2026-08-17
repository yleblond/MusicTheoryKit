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

function buildVoice(part, measure) {
    const vfNotes = measure.notes.map((n) => {
        const note = new VF.StaveNote({
            keys: n.isRest ? [restKeyForClef(part.clef)] : n.keys,
            duration: n.duration + (n.isRest ? "r" : ""),
            clef: part.clef || "treble",
        });
        if (!n.isRest) {
            n.keys.forEach((key, i) => {
                const code = accidentalCodeFromKey(key);
                if (code) note.addModifier(new VF.Accidental(code), i);
                const color = n.colors && n.colors[i];
                if (color) note.setKeyStyle(i, { fillStyle: color, strokeStyle: color });
            });
        }
        return note;
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

    // VexFlow's own `Formatter.preCalculateMinTotalWidth` is generous by design (default glyph/
    // modifier spacing, no compression) — a dense piano measure (an arpeggiated accompaniment,
    // 8-11 notes) can ask for 700-1100 logical px on its own. Without a zoom-out, that's wider
    // than most window widths, so NO two measures ever fit on the same system: every measure
    // ends up alone on its own line, forcing a horizontal scrollbar per line — a real bug, not
    // just a cosmetic "too big" complaint (found rendering the real *An die Musik* import: 43
    // measures, 43 one-measure systems). All layout math below stays in these same "logical"
    // units throughout (nothing here needs to change); only the very last step — sizing the
    // real `VF.Renderer` and scaling its context right before drawing — converts down to
    // physical pixels, so the whole score (glyphs, spacing, everything proportionally) ends up
    // visually smaller instead of just repositioned.
    const RENDER_SCALE = 0.72;

    const minMeasureWidth = 120;
    const notePadding = 40; // breathing room for the note area inside a measure
    const clefPadding = 30; // extra room for a clef repeated at the start of every system
    const timeSigPadding = 30; // extra room for the time signature, first measure of the piece only
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

    // In logical units — divide the physical container width by the scale so packing decisions
    // account for the fact that the final render will be smaller than these logical pixels.
    const availableWidth = Math.max(container.clientWidth / RENDER_SCALE - 2 * leftMargin, minMeasureWidth + clefPadding + timeSigPadding);
    const systems = []; // { start, end (exclusive) } measure-index ranges
    let systemStart = 0, systemWidth = 0;
    for (let m = 0; m < totalMeasures; m++) {
        const w = measureWidths[m] + (m === systemStart ? clefPadding + (m === 0 ? timeSigPadding : 0) : 0);
        if (systemWidth > 0 && systemWidth + w > availableWidth) {
            systems.push({ start: systemStart, end: m });
            systemStart = m;
            systemWidth = 0;
        }
        systemWidth += measureWidths[m] + (m === systemStart ? clefPadding + (m === 0 ? timeSigPadding : 0) : 0);
    }
    systems.push({ start: systemStart, end: totalMeasures });

    function renderedWidth(measureIndex, isFirstInSystem) {
        return measureWidths[measureIndex] + (isFirstInSystem ? clefPadding + (measureIndex === 0 ? timeSigPadding : 0) : 0);
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
            if (isFirstInSystem) stave.addClef(part.clef || "treble");
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
                    if (m === 0) stave.addTimeSignature(measure.beatsPerMeasure + "/" + measure.beatUnit);
                }
                return stave;
            });
            equalizeNoteStartX(staves); // must run AFTER every modifier (clef, time sig) is added — see its own doc comment
            if (voices.length) formatter.format(voices, width - notePadding);

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
                        if (bb) noteEntries.push({ pitches: meta.pitches, bbox: bb });
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
    window.highlightPitches(window.__lastHighlightedPitches || []);
};

// Called by the native side whenever the set of currently-sounding pitches changes during
// playback (see `ScoreEngravingCoordinator.highlight(_:in:)`) — deliberately NOT part of
// `renderScore`'s own layout passes: re-running the whole 3-pass render on every note
// onset/offset would be far too heavy for something that can fire many times a second.
window.highlightPitches = function (pitches) {
    window.__lastHighlightedPitches = pitches;
    const layer = window.__highlightLayer;
    if (!layer) return;
    while (layer.firstChild) layer.removeChild(layer.firstChild);
    const active = new Set(pitches);
    (window.__noteEntries || []).forEach((entry) => {
        if (!entry.pitches.some((p) => active.has(p))) return;
        const ellipse = document.createElementNS("http://www.w3.org/2000/svg", "ellipse");
        ellipse.setAttribute("cx", entry.bbox.x + entry.bbox.w / 2);
        ellipse.setAttribute("cy", entry.bbox.y + entry.bbox.h / 2);
        ellipse.setAttribute("rx", Math.max(entry.bbox.w / 2 + 5, 9));
        ellipse.setAttribute("ry", Math.max(entry.bbox.h / 2 + 5, 9));
        ellipse.setAttribute("fill", "#4caf50");
        ellipse.setAttribute("fill-opacity", "0.35");
        layer.appendChild(ellipse);
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
