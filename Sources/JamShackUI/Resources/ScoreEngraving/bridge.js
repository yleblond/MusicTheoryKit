// Bridge between the native app and VexFlow (vendored as vexflow.js, loaded before this file —
// see score.html). Swift pushes a `NotatedScore`-shaped JSON object via
// `window.renderScore(score)` (called through WKWebView's `callAsyncJavaScript`); this file only
// draws it and forwards note taps back to Swift over `window.webkit.messageHandlers.noteAction`.
// Deliberately dumb: no musical logic here — quantization, spelling, and (later) role coloring
// all happen natively in Swift (see ScoreImport's ScoreEngravingAdapter), so this stays a pure
// renderer that could be swapped (e.g. for abcjs) without touching any Swift code.

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

window.renderScore = function (score) {
    const container = document.getElementById("score");
    container.innerHTML = "";
    if (!score || !score.parts || score.parts.length === 0) return;

    const VF = window.VexFlow;
    const measureWidth = 220;
    const staveHeight = 100;

    let totalMeasures = 0;
    score.parts.forEach((part) => (totalMeasures = Math.max(totalMeasures, part.measures.length)));

    const renderer = new VF.Renderer(container, VF.Renderer.Backends.SVG);
    renderer.resize(Math.max(600, totalMeasures * measureWidth + 40), score.parts.length * staveHeight + 40);
    const context = renderer.getContext();

    score.parts.forEach((part, partIndex) => {
        let x = 10;
        const y = 20 + partIndex * staveHeight;

        part.measures.forEach((measure, measureIndex) => {
            const stave = new VF.Stave(x, y, measureWidth);
            if (measureIndex === 0) {
                stave.addClef("treble");
                stave.addTimeSignature(measure.beatsPerMeasure + "/" + measure.beatUnit);
            }
            stave.setContext(context).draw();

            const vfNotes = measure.notes.map((n) => {
                const note = new VF.StaveNote({
                    keys: n.isRest ? ["b/4"] : n.keys,
                    duration: n.duration + (n.isRest ? "r" : ""),
                });
                if (!n.isRest) {
                    n.keys.forEach((key, i) => {
                        const code = accidentalCodeFromKey(key);
                        if (code) note.addModifier(new VF.Accidental(code), i);
                    });
                    if (n.color) note.setStyle({ fillStyle: n.color, strokeStyle: n.color });
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
            new VF.Formatter().joinVoices([voice]).format([voice], measureWidth - 40);
            voice.draw(context, stave);

            const beams = VF.Beam.generateBeams(vfNotes.filter((n) => !n.isRest));
            beams.forEach((b) => b.setContext(context).draw());

            vfNotes.forEach((note, i) => {
                const meta = measure.notes[i];
                const el = note.getSVGElement();
                if (el) {
                    el.style.cursor = "pointer";
                    el.addEventListener("click", () => postNoteAction(meta, "tap"));
                }
            });

            x += measureWidth;
        });
    });
};
