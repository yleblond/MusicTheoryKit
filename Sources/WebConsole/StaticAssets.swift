import Localization

/// The two static assets served by the web console (`GET /` and `GET /app.js`). Embedded as
/// Swift string constants rather than read from disk at runtime — avoids wiring up
/// `Bundle.module`/SwiftPM resources for two short files, and keeps them reviewable/editable
/// like any other source file.
///
/// **JSON contract with `AppCore.WebConsoleState`** (`Sources/AppCore/WebConsoleState.swift`):
/// this module has no dependency on `AppCore` (kept as dumb as `NetEngine` about the app it
/// serves), so the shape `app.js` expects from `GET /state` is a contract enforced only by
/// convention, not the compiler — keep both in sync by hand. `modeTones` (everywhere it
/// appears below) is degree-ordered, not an arbitrary set order: index 0 is scale degree 1,
/// index 1 is degree 2, etc. — `app.js`'s `keyboardHTML` relies on this to show each note's
/// degree number, not just "in the mode or not". `recentChordEvents` is a per-track rolling
/// log appended server-side (`ImprovSession.recordChordEventIfChanged`) the instant the
/// held-pitches/chord actually changes — `app.js`'s `renderStaffSVG` just draws this array
/// directly, no client-side history-building/deduping (an earlier version did that by diffing
/// successive polls, which could silently miss a chord played and released faster than the
/// poll interval):
/// ```json
/// {
///   "lastEvent": "on pitch=60 vel=100" | null,
///   "tracks": [{
///     "id": "clavier", "label": "Piste clavier", "owner": "Bob" | null,
///     "heldPitches": [60, 64, 67],
///     "chordRoot": 0 | null, "chordTones": [0, 4, 7], "modeTones": [0, 2, 4, 5, 7, 9, 11],
///     "chordLabel": "Cmaj" | null, "modesLabel": "C ionian" | null,
///     "microphoneLevel": 0.0123 | null,
///     "recentChordEvents": [{"pitches": [60], "chordRoot": null, "chordTones": []}, ...]
///   }],
///   "playback": { "timeline": [{"label": "Dm7", "isCurrent": true}], "heldPitches": [...],
///                 "chordRoot": 2 | null, "chordTones": [...], "modeTones": [...] } | null,
///   "soundTrackPlayback": { "heldPitches": [...] } | null,
///   "wheel": { "tonic": 0, "activeModeName": "Dorian", "activeColumnIndex": 0, "columns": [
///     {"pitchClass": 0, "modeName": "Ionian", "cells": [
///       {"pitchClass": 0, "shape": "square", "quality": "major", "relativeDegree": "I", "isDiatonic": true, "trackLabels": ["Piste clavier"]},
///       {"pitchClass": 9, "shape": "circle", "quality": "minor", "relativeDegree": "vi", "isDiatonic": true, "trackLabels": []},
///       {"pitchClass": 11, "shape": "circle", "quality": "diminished", "relativeDegree": "vii°", "isDiatonic": true, "trackLabels": []}
///     ]},
///     ...12 total, fixed ascending-fifths order starting at C (C,G,D,A,E,B,F#,Db,Ab,Eb,Bb,F),
///     "modeName" non-null on 7 of the 12 — NOT the same 7 as the diatonic ones; each mode
///     name is glued at a fixed offset from the active tonic equal to the interval up to its
///     own parent, so "app.js" marks whichever column's "modeName" equals "activeModeName" as
///     active, which always lands on the *parent*'s column (see
///     `MusicTheoryKit.CircleOfFifthsColumn.modeName`'s doc comment). Each cell's own
///     "pitchClass"/"shape" can differ from its column's: only the major cell is rooted on the
///     column itself; minor is the column's relative minor (+9 semitones), diminished is its
///     leading-tone diminished (+11 semitones) — see `MusicTheoryKit.CircleOfFifthsCell`...
///   ] },
///   "guide": {
///     "isActive": true, "steps": [{"label": "D Dorian", "isCurrent": true}],
///     "currentStepIndex": 0 | null, "currentModeTones": [2, 4, 5, 7, 9, 11, 0],
///     "heldPitches": [...]
///   } | null,
///   "palette": ["#DB2A52", "#0AAD9A", ..., "#ABD144"],
///   "paletteTextColors": ["#ffffff", "#ffffff", ..., "#111111"],
///   "scene": {
///     "networkRoleText": "solo" | "serveur sur le port 5050" | "connecte a host:port",
///     "webConsolePort": 8080 | null, "virtualKeyboardPort": 8081 | null,
///     "localInstruments": [{"id": "midi", "label": "...", "isListening": true, ...}],
///     "clients": [{"clientID": "ab12", "name": "Bob", "instruments": [...]}]
///   }
/// }
/// ```
/// `wheel` is always present (not gated behind an active guide) — see
/// `ImprovSession.wheelReferenceTonic()`/`buildWebConsoleWheelState()` for how its reference
/// key is chosen, and each cell's `trackLabels` for the multi-instrument "who's playing this
/// function right now" view. The chord grid (which chord is at which column/ring) never
/// changes; only `isDiatonic`/`modeName`/`relativeDegree` are relative to `tonic`.
///
/// `palette` (not to be confused with the wheel's own fixed chord grid above — an unrelated,
/// pre-existing use of the word) is the 12 hex colors of whichever `ColorPalette` is currently
/// active (`ImprovSession.activeColorPalette`, `AppCore/ColorPalette.swift`), index 0 = C ...
/// 11 = B — sent on every poll, not just once, so switching palettes from the menu updates
/// any already-open browser tab within one refresh cycle. `app.js` overwrites its own
/// `PITCH_CLASS_COLORS` from this on every `refresh()` — see there.
///
/// `paletteTextColors` is the same active `ColorPalette`'s `textColors` — the legible text
/// color to paint OVER each note's own background color (`ColorPalette.textColors`'s doc
/// comment explains why this is a hand-picked/computed field of its own, not derived from
/// `palette` client-side). `app.js` mirrors it into `PITCH_CLASS_TEXT_COLORS` the same way.
public let webConsoleIndexHTML = """
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>JamShack — Console Web</title>
<style>
  /* Defaults match NoteColorSettingsFile's own — overwritten from `state.noteColors` by
     `applyNoteColors()` on first load and every poll after, so a `note-colors.json` change
     shows up here within one refresh cycle without needing this stylesheet regenerated. */
  :root {
    --mode-root-color: #ff9800;
    --mode-tone-color: #00bcd4;
    --chord-root-color: #e91e63;
    --chord-tone-color: #fdd835;
    --held-outside-color: #4caf50;
    --held-no-chord-color: #ffffff;
  }
  body { background: #111; color: #ddd; font-family: -apple-system, sans-serif; box-sizing: border-box; margin: 1.5rem auto; max-width: 1600px; padding: 0 1.5rem; }
  h1 { font-size: 1.1rem; color: #888; font-weight: normal; }
  h2 { font-size: 1rem; margin: 1.5rem 0 0.4rem; }
  .field { color: #888; }
  .field b { color: #ddd; }
  .keyboard-scroll { overflow-x: auto; max-width: 100%; }
  .keyboard { position: relative; margin: 1rem 0 0.8rem; }
  .pkey { position: absolute; top: 0; box-sizing: border-box; border: 1px solid #333; border-radius: 0 0 4px 4px; }
  .pkey.white { background: #f5f5f5; z-index: 1; }
  .pkey.black { background: #1a1a1a; z-index: 2; box-shadow: 0 2px 3px rgba(0,0,0,0.5); }
  .pkey.root { background: var(--chord-root-color) !important; }
  .pkey.tone { background: var(--chord-tone-color) !important; }
  .pkey.outside { background: var(--held-outside-color) !important; }
  .pkey.held { background: var(--held-no-chord-color) !important; }
  /* Guide panel's mode keyboard only (see keyboardHTML's `showModeColoring`) — root vs.
     rest of the mode, deliberately distinct from chord root/tone above so the two concepts
     are never visually confused when both keyboards are on screen together. Mirrors the
     terminal's KeyboardColor.modeRoot/modeOther. */
  .pkey.mode-root { background: var(--mode-root-color) !important; }
  .pkey.mode-tone { background: var(--mode-tone-color) !important; }
  /* Guide panel's guitar-tab diagram (see guitarChordDiagramHTML) — root color for the
     barre/dots, deliberately reusing --chord-root-color/--chord-tone-color so a fingered
     note's color is consistent with the chord keyboard right above it. */
  .guitar-diagram { display: block; margin: 0.3rem 0 0.6rem; }
  .guitar-diagram-label { font-size: 1.5rem; font-weight: bold; color: #ddd; margin: 0 0 -8px; line-height: 1.1; text-align: center; }
  .guitar-string { stroke: #666; stroke-width: 1.5; }
  .guitar-fret { stroke: #666; stroke-width: 1.5; }
  .guitar-fret-label { font-size: 11px; fill: #888; }
  .guitar-barre { stroke: var(--chord-root-color); stroke-width: 9; stroke-linecap: round; }
  .guitar-dot { fill: var(--chord-tone-color); }
  .guitar-finger { font-size: 10px; fill: #111; text-anchor: middle; }
  .guitar-muted { font-size: 13px; fill: #e57373; text-anchor: middle; }
  .staff-scroll { overflow-x: auto; max-width: 100%; }
  /* width: auto (not a fixed px) — the SVG's viewBox now grows with history length, so its
     natural aspect ratio (preserved by leaving width unset) is what should scale, not a fixed
     box that would squash a wide multi-event staff down to a narrow one. */
  .staff { display: block; margin: 0.4rem 0 0.8rem; width: auto; height: 130px; }
  .staff-paper { fill: #fff; }
  .staff-line, .staff-ledger { stroke: #333; stroke-width: 1; }
  .staff-clef { fill: #333; }
  .staff-note { stroke-width: 1; }
  .staff-note-root { fill: #e91e63; stroke: #e91e63; }
  .staff-note-tone { fill: #fdd835; stroke: #fdd835; }
  .staff-note-outside { fill: #4caf50; stroke: #4caf50; }
  .staff-note-held { fill: #bbb; stroke: #bbb; }
  .staff-accidental { font-size: 13px; text-anchor: middle; }
  .degree-badge {
    position: absolute; top: -18px; left: 50%; transform: translateX(-50%);
    width: 14px; height: 14px; border-radius: 50%;
    font-size: 9px; line-height: 14px; text-align: center; font-weight: bold;
  }
  .empty { color: #666; font-style: italic; }
  /* Same look as `.empty` (grey, italic) but semantically distinct: a permanent navigation
     hint, not a "nothing here yet" placeholder — e.g. the Guide panel's consolidated
     arrow-key hint below its mode+chord detail text. */
  .hint { color: #666; font-style: italic; }
  .wheel { margin: 0.5rem 0 1rem; display: block; width: 100%; max-width: 820px; height: auto; }
  .wheel-disk { fill: #fff; }
  .wheel-grid-line { stroke: #000; stroke-width: 1; }
  .wheel-cell-shape { stroke: #333; stroke-width: 1; }
  .wheel-cell-outline { fill: none; stroke-width: 3; }
  .wheel-diatonic-boundary { fill: none; stroke: #1a3a6b; stroke-width: 5; stroke-linejoin: round; }
  /* No `fill` here (unlike most rules) — the palette's per-note text color is set inline,
     since it varies by pitch class (`PITCH_CLASS_TEXT_COLORS[cell.pitchClass]`), not fixed. */
  .wheel-cell-symbol { font-size: 8px; font-weight: bold; text-anchor: middle; pointer-events: none; }
  .wheel-cell-degree { font-size: 6.5px; font-family: Georgia, 'Times New Roman', serif; text-anchor: middle; pointer-events: none; opacity: 0.75; }
  .wheel-mode-name { fill: #555; font-size: 11px; text-anchor: middle; dominant-baseline: middle; }
  .wheel-mode-name.active { fill: #b36b00; font-weight: bold; }
  .instrument-swatch { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 0.4em; }
  .layout-columns { display: flex; flex-wrap: wrap; gap: 2rem; align-items: flex-start; }
  .layout-col-left, .layout-col-right { flex: 1 1 380px; min-width: 0; }
  /* Observer tab's own octave-shift row — same look as `VirtualKeyboardAssets.swift`'s copy
     (no mini-piano overview here, per feedback: nothing else in this read-only tab is
     clickable either, so a clickable jump-to-octave shortcut isn't worth porting). */
  .observer-track-select { background: #1a1a1a; color: #ddd; border: 1px solid #444; border-radius: 3px; padding: 0.3rem 0.5rem; margin-bottom: 0.6rem; }
  .octave-controls { color: #888; font-size: 0.85rem; margin: 0.4rem 0; display: flex; align-items: center; gap: 0.5rem; }
  .octave-controls b { color: #ddd; }
  .octave-arrow { cursor: pointer; user-select: none; font-size: 1.3rem; line-height: 1; color: #ddd; padding: 0 0.2rem; position: relative; top: 0.12em; }
  .octave-arrow:hover { color: #fff; }
  /* Guide panel's own inner layout: notation (left) — the two stacked keyboards (middle) —
     guitar tab (right). A distinct set of classes from `.layout-columns` above (that one is
     the whole-page wheel/mode split) since this nests one level deeper and has 3 columns, not 2. */
  /* `align-items: stretch` so all 3 columns share the row's tallest height (the keyboards
     column, which always has 2 stacked keyboards whenever notation/tab exist at all — see
     `renderGuide`'s `hasChord` gate). Each column is its own flex-column with the `<h3>`
     heading as a plain first child (so all 3 headings sit flush at the same top row — see the
     `.guide-col-fill` comment below for why the graphic underneath needs a second wrapper).
     Every column is `flex: 0 0 auto` (natural content width, no grow) — `guide-col-keyboards`
     used to be `flex: 1 1 260px`, which grew to soak up the row's leftover width (the page's
     wide max-width vs. a ~310px 2-octave keyboard), pushing the tab column far to the right of
     the actual keyboard graphic despite sitting right next to the column's own edge. With none
     of the 3 columns growing, one single shared `gap` puts equal space on both sides, and the
     whole row now hugs the left like everything else on the page instead of stretching wide. */
  .guide-layout { display: flex; flex-wrap: wrap; gap: 1rem; align-items: stretch; margin-top: 0.4rem; }
  .guide-col-notation, .guide-col-keyboards, .guide-col-tab { flex: 0 0 auto; display: flex; flex-direction: column; }
  /* A little extra room below the 2nd keyboard, per feedback — purely cosmetic breathing room,
     not needed for the bottom-alignment mechanism itself (that's `.guide-col-fill` below). */
  .guide-col-keyboards { padding-bottom: 8px; }
  /* Wraps everything under a column's own heading (the staff/tab graphic). */
  .guide-col-fill { flex: 1 1 auto; display: flex; flex-direction: column; }
  /* Notation and tab both bottom-align their own (fixed-size — see `renderStaffSVG`'s
     `displayHeightPx` and `guitarChordDiagramHTML`'s own dimensions) graphic — so a shorter
     box's bottom edge lines up with the keyboards column's own bottom (its second keyboard)
     instead of floating wherever its own natural height happens to end. */
  .guide-col-tab .guide-col-fill, .guide-col-notation .guide-col-fill { justify-content: flex-end; }
  .tab-bar { display: flex; gap: 1.2rem; border-bottom: 1px solid #333; margin-bottom: 1rem; }
  .tab { color: #888; cursor: pointer; padding: 0.3rem 0; user-select: none; }
  .tab.active { color: #fff; border-bottom: 2px solid #6cf; }
  .scene-tree, .scene-tree ul { list-style: none; margin: 0; padding-left: 1.3rem; }
  .scene-tree { padding-left: 0; }
  .scene-tree li { margin: 0.15rem 0; }
  /* "Menu" tab — a remote-control mirror of the terminal's own pull-down menu (see
     `renderMenuTab`'s own doc comment). Built once per visit to the tab and never
     wholesale-replaced afterward, unlike every other tab, so in-progress typing/dropdown
     choices survive the page's own ~250ms `/state` poll — see `refresh()`. */
  .menu-category-panel { margin-bottom: 1rem; }
  /* Slightly smaller/dimmer than the page's main Run/Scene/Commandes/Infos bar, so the two
     nesting levels stay visually distinct rather than reading as one flat row of tabs. */
  .menu-subtab-bar { margin: 0 0 1rem; border-bottom-color: #292929; }
  .menu-subtab-bar .tab { font-size: 0.9rem; padding: 0.2rem 0; }
  .menu-row { display: flex; align-items: center; gap: 0.5rem; margin: 0.4rem 0; flex-wrap: wrap; }
  .menu-row label { color: #aaa; min-width: 220px; }
  .menu-row input[type="text"], .menu-row select { background: #1a1a1a; color: #ddd; border: 1px solid #444; border-radius: 3px; padding: 0.3rem 0.4rem; }
  .menu-row textarea { background: #1a1a1a; color: #ddd; border: 1px solid #444; border-radius: 3px; padding: 0.3rem 0.4rem; width: 100%; max-width: 480px; }
  .menu-row button { background: #234; color: #cde; border: 1px solid #456; border-radius: 3px; padding: 0.3rem 0.7rem; cursor: pointer; }
  .menu-row button:hover { background: #345; }
  #menu-result { position: sticky; top: 0; background: #111; padding: 0.5rem 0; margin-bottom: 0.5rem; z-index: 1; min-height: 1.2em; }
  #menu-result.ok { color: #7fd88f; }
  #menu-result.error { color: #ff6b6b; }
</style>
</head>
<body>
<div id="app"></div>
<script src="/app.js"></script>
</body>
</html>
"""

public let webConsoleAppJS = """
\(L10n.jsTableLiteral)
// The active UI language — mutable (`let`, not `const`), overwritten every `refresh()`/
// `refreshMenuLists()` tick from `state.language`/`menuLists.language`, same "server-authoritative,
// re-applied every poll" convention already used by `PITCH_CLASS_COLORS` below. Defaults to 'fr'
// only until the first poll response lands.
let currentLanguage = 'fr';
function t(key, ...args) {
  const entry = L10N[key];
  let template = (entry && entry[currentLanguage]) || (entry && entry.fr) || key;
  args.forEach(arg => { template = template.replace('%d', arg).replace('%@', arg); });
  return template;
}

const MIN_MIDI = 48; // C3, same range as the terminal's per-track keyboard
const MAX_MIDI = 83; // B5

// One color per chromatic pitch class (index 0 = C ... 11 = B), "mycolormusic"-style: a note
// keeps the same color no matter which mode/key it's functioning in. `let`, not `const` —
// this starting array (hand-mirroring `MusicTheoryKit.PitchClassPalette.hex`) is only the
// fallback shown before the first `GET /state` response arrives; `refresh()` below overwrites
// it with `state.palette` every poll, so switching the active palette (menu JamShack >
// Choisir palette de couleur) updates any already-open tab within one refresh cycle.
let PITCH_CLASS_COLORS = [
  '#DB2A52', '#0AAD9A', '#F7872D', '#4169B7', '#F2DE18', '#AE2F93',
  '#44B853', '#F15830', '#249CD7', '#FEBC20', '#884A9C', '#ABD144',
];
// Same indexing as `PITCH_CLASS_COLORS`, same "fallback until the first /state, then
// overwritten every poll from `state.paletteTextColors`" convention — the legible text color
// to paint OVER each note's own background (degree badges, wheel cell symbols/degrees).
let PITCH_CLASS_TEXT_COLORS = [
  '#ffffff', '#ffffff', '#ffffff', '#ffffff', '#111111', '#ffffff',
  '#ffffff', '#ffffff', '#ffffff', '#111111', '#ffffff', '#111111',
];

// One accent color per track, assigned by its position in `state.tracks` (not by anything
// about the track itself, so it's stable across a session but says nothing musical) — lets
// a multi-instrument setup tell "who's playing this" apart at a glance, both next to each
// track's own heading and around whichever wheel cell(s) it's currently sounding.
const INSTRUMENT_COLORS = ['#e91e63', '#00c853', '#ff6f00', '#00b8d4', '#aa00ff', '#ffd600', '#795548'];
function instrumentColor(index) { return INSTRUMENT_COLORS[index % INSTRUMENT_COLORS.length]; }

// Real-piano geometry: white keys adjacent with no gaps, black keys shorter/narrower and
// straddling the boundary between the two white keys they sit above.
const WHITE_KEY_WIDTH = 22, WHITE_KEY_HEIGHT = 72, BLACK_KEY_WIDTH = 13, BLACK_KEY_HEIGHT = 46;
const WHITE_SLOT_BY_SEMITONE = { 0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6 };
const BLACK_AFTER_WHITE_SLOT = { 1: 0, 3: 1, 6: 3, 8: 4, 10: 5 };
// Same window for every track/guide/playback here (unlike the virtual keyboard, this page has
// no octave-shifting), so — unlike `keyboardPixelWidth` there — this is a plain constant, not
// something that needs recomputing per poll; passed into `renderStaffSVG` so a staff is never
// narrower than the keyboard drawn right above it (see `renderStaffSVG`'s own comment).
const KEYBOARD_TOTAL_WIDTH = Math.ceil((MAX_MIDI - MIN_MIDI + 1) / 12) * 7 * WHITE_KEY_WIDTH;
// Approximates the Guide panel's own 3-column row width (2-octave keyboard + guitar-tab svg +
// their gaps + a rough allowance for the notation column) — used only for the Guide panel's own
// "held pitches" staff below that row, so its right edge reaches roughly as far as the
// tablature's own right edge instead of stopping at the unrelated `KEYBOARD_TOTAL_WIDTH` (sized
// for the Run tab's much wider 3-octave keyboard). The notation column's actual on-screen width
// is flex-grow/aspect-ratio-derived from the row's rendered height, which isn't knowable from
// plain string-building JS — the `110` below is a best-effort estimate, not an exact figure.
const GUIDE_ROW_WIDTH_ESTIMATE = 110 + 16 + (2 * 7 * WHITE_KEY_WIDTH) + 16 + 150;

// `alwaysShowChord`: color chordRoot/chordTones even on keys that aren't currently held —
// used only by the Guide panel's chord keyboard, whose chord is a *proposed* one to play
// next, not something already sounding (every other caller shows chord coloring only on
// held pitches, matching "here's what's actually playing").
// `options.minMidi`/`options.maxMidi` override the default 3-octave `MIN_MIDI`/`MAX_MIDI`
// range — used by the Guide panel's own two 2-octave keyboards (mode, chord), which don't
// need or want the full range every other caller shows.
// `options.showModeColoring`: color the mode's root (`modeTones[0]` — degree-ordered, so
// index 0 is always the tonic) vs. its other notes, with dedicated `.mode-root`/`.mode-tone`
// classes distinct from chord root/tone — used only by the Guide panel's mode keyboard, so
// "this is the mode's tonic" is never visually confused with "this is the chord's root".
// `options.bigKeys`: use the same bigger key size as `VirtualKeyboardAssets.swift`'s real
// interactive piano (44/144/26/92) instead of this file's own small 22/72/13/46 — used only by
// the Observer tab's own keyboard (see `renderObserverTab`), which wants the same visual scale
// as the virtual keyboard page even though it isn't interactive itself. Every other caller
// omits it and keeps this file's own small size unchanged.
function keyboardHTML(heldPitches, chordRoot, chordTones, modeTones, alwaysShowChord, options) {
  options = options || {};
  const minMidi = options.minMidi !== undefined ? options.minMidi : MIN_MIDI;
  const maxMidi = options.maxMidi !== undefined ? options.maxMidi : MAX_MIDI;
  const showModeColoring = !!options.showModeColoring;
  const whiteW = options.bigKeys ? 44 : WHITE_KEY_WIDTH;
  const whiteH = options.bigKeys ? 144 : WHITE_KEY_HEIGHT;
  const blackW = options.bigKeys ? 26 : BLACK_KEY_WIDTH;
  const blackH = options.bigKeys ? 92 : BLACK_KEY_HEIGHT;
  const modeRootPC = (modeTones && modeTones.length) ? modeTones[0] : null;

  const held = new Set(heldPitches || []);
  const tones = new Set(chordTones || []);
  // pitch class -> {degree, color, textColor} — `modeTones` is degree-ordered (index 0 =
  // degree 1).
  const roles = {};
  (modeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc], textColor: PITCH_CLASS_TEXT_COLORS[pc] }; });

  const octaveCount = Math.ceil((maxMidi - minMidi + 1) / 12);
  const totalWidth = octaveCount * 7 * whiteW;
  let whiteHTML = '', blackHTML = '';

  for (let pitch = minMidi; pitch <= maxMidi; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    const octave = Math.floor((pitch - minMidi) / 12);
    const role = roles[pc];
    const badge = role ? `<span class="degree-badge" style="background:${role.color};color:${role.textColor}">${role.degree}</span>` : '';
    let cls = '';
    const isChordRoot = chordRoot !== null && chordRoot !== undefined && pc === chordRoot;
    if (held.has(pitch)) {
      if (isChordRoot) cls = 'root';
      else if (tones.has(pc)) cls = 'tone';
      else if (chordRoot !== null && chordRoot !== undefined) cls = 'outside';
      else cls = 'held';
    } else if (alwaysShowChord) {
      if (isChordRoot) cls = 'root';
      else if (tones.has(pc)) cls = 'tone';
    }
    if (!cls && showModeColoring) {
      if (pc === modeRootPC) cls = 'mode-root';
      else if (role) cls = 'mode-tone';
    }
    if (WHITE_SLOT_BY_SEMITONE[pc] !== undefined) {
      const slot = octave * 7 + WHITE_SLOT_BY_SEMITONE[pc];
      const x = slot * whiteW;
      whiteHTML += `<div class="pkey white ${cls}" style="left:${x}px; width:${whiteW}px; height:${whiteH}px;">${badge}</div>`;
    } else {
      const whiteSlotBefore = BLACK_AFTER_WHITE_SLOT[pc];
      const slot = octave * 7 + whiteSlotBefore + 1;
      const x = slot * whiteW - blackW / 2;
      blackHTML += `<div class="pkey black ${cls}" style="left:${x}px; width:${blackW}px; height:${blackH}px;">${badge}</div>`;
    }
  }
  // The keyboard itself is necessarily a fixed pixel width (`.pkey` children are absolutely
  // positioned, which a percentage-based layout can't drive) — wrapped in its own scrolling
  // container so a narrow browser window scrolls just this widget horizontally instead of
  // the whole page (see `.keyboard-scroll` in the CSS above).
  return `<div class="keyboard-scroll"><div class="keyboard" style="width:${totalWidth}px; height:${whiteH}px;">${whiteHTML}${blackHTML}</div></div>`;
}

// Grand staff (treble + bass), a fixed G2..C6 natural-row window (one natural step of margin
// beyond MIN_MIDI/MAX_MIDI on each side) — same root/tone/outside/held meaning and colors as
// `keyboardHTML`'s `.pkey.*` classes, just a different physical layout. Accidentals reuse the
// wheel's own fixed `NOTE_NAMES` table (see there for why: this project has no per-key/per-mode
// spelling logic anywhere, so a single site-wide convention is used rather than inventing a
// second one here).
//
// Shows a short *history* of recent chord/note events (left = oldest, right = most recent/
// still sounding), not just the current instant — deliberately without any real timing/
// duration for now (a future pass, possibly LLM-assisted, may retroprocess that): each column
// is one discrete "what was held" snapshot, not a duration-weighted note. Built server-side now
// (`track.recentChordEvents`, see that field's own doc comment in `WebConsoleState.swift`), not
// reconstructed here by diffing successive `GET /state` polls — a client-side version could
// silently miss any chord played and released faster than the poll interval, a real reported
// bug ("des notes/accords se perdent parfois").
const STAFF_MIN_MIDI = 43; // G2
const STAFF_MAX_MIDI = 84; // C6
const STAFF_LETTER_PC = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const STAFF_LETTERS = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

// One entry per natural note in [STAFF_MIN_MIDI, STAFF_MAX_MIDI], row 0 = highest pitch
// (descending), each carrying whether it's a staff LINE or a space. Lines/spaces strictly
// alternate across the whole grand staff — that's what makes ledger lines a continuation of
// the same pattern rather than a separate concept — so parity relative to one known line (E4,
// the treble clef's bottom line) determines every other row automatically, staff or ledger,
// with no separate per-position lookup table to keep in sync.
const STAFF_ROWS = (() => {
  const naturals = [];
  for (let m = STAFF_MIN_MIDI; m <= STAFF_MAX_MIDI; m++) {
    const pc = ((m % 12) + 12) % 12;
    const letter = STAFF_LETTERS.find(l => STAFF_LETTER_PC[l] === pc);
    if (letter) naturals.push({ midi: m, letter });
  }
  const anchorIndex = naturals.findIndex(n => n.midi === 64); // E4
  return naturals.reverse().map((n, i) => ({
    ...n,
    isLine: (((naturals.length - 1 - i) - anchorIndex) % 2 + 2) % 2 === 0,
  }));
})();
const STAFF_TREBLE_TOP = STAFF_ROWS.findIndex(r => r.midi === 77); // F5
const STAFF_TREBLE_BOTTOM = STAFF_ROWS.findIndex(r => r.midi === 64); // E4
const STAFF_BASS_TOP = STAFF_ROWS.findIndex(r => r.midi === 57); // A3
const STAFF_BASS_BOTTOM = STAFF_ROWS.findIndex(r => r.midi === 43); // G2
const STAFF_G4_ROW = STAFF_ROWS.findIndex(r => r.midi === 67); // G4 — treble clef curls around this line
const STAFF_F3_ROW = STAFF_ROWS.findIndex(r => r.midi === 53); // F3 — bass clef's two dots straddle this line

function staffRowIndexForPitch(pitch) {
  const pc = ((pitch % 12) + 12) % 12;
  const name = NOTE_NAMES[pc];
  const naturalMidi = pitch - (name.length > 1 ? (name[1] === '#' ? 1 : -1) : 0);
  return STAFF_ROWS.findIndex(r => r.midi === naturalMidi);
}

// Ledger lines needed between the staff and a given row — walks outward from whichever staff
// edge the row is beyond (or, for a row between the two staves, from the treble's own bottom
// line), collecting every LINE-parity position along the way. A plain continuation of the
// alternating pattern, so it generalizes to any row instead of special-casing "middle C".
function staffLedgerRows(rowIndex) {
  const ledger = [];
  if (rowIndex < STAFF_TREBLE_TOP) {
    for (let i = STAFF_TREBLE_TOP - 1; i >= rowIndex; i--) if (STAFF_ROWS[i].isLine) ledger.push(i);
  } else if (rowIndex > STAFF_BASS_BOTTOM) {
    for (let i = STAFF_BASS_BOTTOM + 1; i <= rowIndex; i++) if (STAFF_ROWS[i].isLine) ledger.push(i);
  } else if (rowIndex > STAFF_TREBLE_BOTTOM && rowIndex < STAFF_BASS_TOP) {
    for (let i = STAFF_TREBLE_BOTTOM + 1; i <= rowIndex; i++) if (STAFF_ROWS[i].isLine) ledger.push(i);
  }
  return ledger;
}

const STAFF_ROW_HEIGHT = 9, STAFF_MARGIN_RIGHT = 16;
// More top margin than bottom — measured empirically (see below), the treble clef's own
// glyph extends further above G4 than the bass clef's extends below F3, so the top needs more
// breathing room to avoid clipping; the bottom margin was also bumped up from an earlier,
// too-tight value that put the bottom bass line uncomfortably close to the paper's edge.
const STAFF_MARGIN_TOP = 46, STAFF_MARGIN_BOTTOM = 32;
// Font-size/offsets found by measuring THIS glyph's own ink extent (top/bottom of the drawn
// shape, and the "eye"/dot-midpoint position) relative to the text baseline, at a large
// font-size in a headless-Chrome screenshot with a measurement grid — a first pass anchored
// the "eye" on G4/F3 correctly but picked a font-size far too small (34) relative to the
// glyph's own proportions, so the clef never actually reached the staff's own top/bottom
// lines, let alone extended past them like real notation (the actual complaint). Measured
// ratios: treble eye sits 0.25em above baseline, glyph top 0.417em above eye, glyph bottom
// 0.293em below eye; bass F3-anchor (dot midpoint) sits 0.45em above baseline, glyph top
// 0.217em above that, glyph bottom 0.45em below it. Font-sizes below are picked from those
// ratios, then reduced (an initial larger pick made the two clefs visually collide — the gap
// between the two staves isn't big enough for both clefs at their "ideal" real-notation
// size) — a compromise between "clearly extends past the staff" and "doesn't overlap the
// other clef", re-verify with a fresh measurement if this glyph's rendering ever changes.
const STAFF_CLEF_FONT_SIZE_G = 130, STAFF_CLEF_FONT_SIZE_F = 83; // F clef reduced ~30% per feedback
const STAFF_CLEF_G_DY = 0.22 * STAFF_CLEF_FONT_SIZE_G, STAFF_CLEF_F_DY = 0.45 * STAFF_CLEF_FONT_SIZE_F; // 0.25 sat a hair too low
const STAFF_CLEF_X = 4;
const STAFF_LINES_LEFT_X = 4; // lines run the FULL width, under both clefs, like real notation
const STAFF_STAVES_X = 78; // past both clefs' own widest extent — first NOTE column starts here, not the lines themselves
const STAFF_COL_WIDTH = 44, STAFF_FIRST_COL_X = STAFF_STAVES_X + 26;
const STAFF_NOTE_RX = 9, STAFF_NOTE_RY = 7.5; // near-full interline height (interline = 2*ROW_HEIGHT = 18)

// Must match `.staff`'s own CSS `height` — how a viewBox width converts to an on-screen pixel
// width, since `.staff` is `width: auto; height: 130px` (aspect-ratio-preserving).
const STAFF_DISPLAY_HEIGHT_PX = 130;

// `history`: array of { pitches: number[], chordRoot: number|null, chordTones: number[] },
// oldest first, most recent (currently live) last — straight off the server now
// (`track.recentChordEvents`), no client-side building/deduping. Each column is drawn
// independently with its OWN root/tones, so e.g. a single held note with no chord (grey) sits
// right next to an earlier recognized chord's colored notes without either affecting the other.
// `minWidthPx`: the staff's on-screen width is never narrower than this — every call site here
// passes `KEYBOARD_TOTAL_WIDTH` so a track's staff always matches its own keyboard's width,
// even before there's enough history to need that much room on its own (same mechanism as the
// virtual keyboard's `keyboardPixelWidth`, just a constant here since this page has no
// per-track octave shifting).
// `firstColOffset`: shifts every note column left/right from `STAFF_FIRST_COL_X` — only the
// Guide panel's own single-chord notation passes a (negative) value here, per feedback that its
// notes sat too far from the clef once that staff got rendered much larger than the shared
// default; every other caller omits it (0), keeping their own note placement unchanged.
// `displayHeightPx`: overrides the shared `STAFF_DISPLAY_HEIGHT_PX` (130) for THIS call only,
// via an inline `style` (higher specificity than the `.staff` class's own `height: 130px`) —
// only the Guide panel's own notation column passes one (bigger, to look properly sized next
// to the keyboards/tab rather than a small fixed-130px box). Tried making it flex-grow to
// exactly match the keyboards column's own rendered height first — checked empirically with a
// real headless-Chromium instance (Playwright), not assumed — but `aspect-ratio` on a flex
// item inside a shrink-to-fit (`flex: 0 0 auto`) ancestor doesn't reliably derive its width from
// a flex-grown height in current Chromium; it fell back to unrelated default/fallback sizing
// instead. A fixed, generously-sized display height + bottom-alignment (see
// `.guide-col-notation .guide-col-fill`'s own comment) is less "perfect" (won't always reach
// the very top) but is actually reliable.
function renderStaffSVG(history, minWidthPx, firstColOffset, displayHeightPx) {
  const events = (history || []).filter(e => e.pitches && e.pitches.length);
  const colOffset = firstColOffset || 0;
  const height = STAFF_MARGIN_TOP + STAFF_MARGIN_BOTTOM + (STAFF_ROWS.length - 1) * STAFF_ROW_HEIGHT;
  const contentWidth = STAFF_FIRST_COL_X + colOffset + Math.max(events.length - 1, 0) * STAFF_COL_WIDTH + STAFF_MARGIN_RIGHT;
  const targetHeightPx = displayHeightPx || STAFF_DISPLAY_HEIGHT_PX;
  const minViewBoxWidth = minWidthPx ? minWidthPx * (height / targetHeightPx) : 0;
  const width = Math.max(contentWidth, minViewBoxWidth);
  const y = i => STAFF_MARGIN_TOP + i * STAFF_ROW_HEIGHT;

  const heightStyle = displayHeightPx ? ` style="height: ${displayHeightPx}px;"` : '';
  let svg = `<svg class="staff" viewBox="0 0 ${width} ${height}"${heightStyle}>`;
  svg += `<rect class="staff-paper" x="0" y="0" width="${width}" height="${height}" rx="4" />`;
  for (let i = STAFF_TREBLE_TOP; i <= STAFF_TREBLE_BOTTOM; i++) {
    if (STAFF_ROWS[i].isLine) svg += `<line class="staff-line" x1="${STAFF_LINES_LEFT_X}" y1="${y(i)}" x2="${width - 4}" y2="${y(i)}" />`;
  }
  for (let i = STAFF_BASS_TOP; i <= STAFF_BASS_BOTTOM; i++) {
    if (STAFF_ROWS[i].isLine) svg += `<line class="staff-line" x1="${STAFF_LINES_LEFT_X}" y1="${y(i)}" x2="${width - 4}" y2="${y(i)}" />`;
  }
  svg += `<text class="staff-clef" x="${STAFF_CLEF_X}" y="${y(STAFF_G4_ROW) + STAFF_CLEF_G_DY}" font-size="${STAFF_CLEF_FONT_SIZE_G}">\u{1D11E}</text>`;
  svg += `<text class="staff-clef" x="${STAFF_CLEF_X}" y="${y(STAFF_F3_ROW) + STAFF_CLEF_F_DY}" font-size="${STAFF_CLEF_FONT_SIZE_F}">\u{1D122}</text>`;

  events.forEach((ev, colIndex) => {
    const tones = new Set(ev.chordTones || []);
    const held = ev.pitches.map(pitch => ({ pitch, row: staffRowIndexForPitch(pitch) })).filter(n => n.row >= 0);
    // A run of several consecutive seconds (e.g. the mode's own scale held as a cluster) needs
    // a proper zigzag, not just "shift every note that has one above it" — that stateless rule
    // would shift every note but the topmost into the same column. Walking top-to-bottom and
    // only shifting a note when its immediate upstairs neighbor exists AND wasn't itself shifted
    // reproduces the standard alternating-seconds engraving instead.
    const shiftByRow = new Map();
    let previousRow = null, previousShifted = false;
    held.slice().sort((a, b) => a.row - b.row).forEach(n => {
      const shift = previousRow !== null && n.row - previousRow === 1 && !previousShifted;
      shiftByRow.set(n.row, shift);
      previousRow = n.row;
      previousShifted = shift;
    });
    const colX = STAFF_FIRST_COL_X + colOffset + colIndex * STAFF_COL_WIDTH;
    held.forEach(n => {
      const pc = ((n.pitch % 12) + 12) % 12;
      let cls = 'held';
      if (ev.chordRoot !== null && ev.chordRoot !== undefined && pc === ev.chordRoot) cls = 'root';
      else if (tones.has(pc)) cls = 'tone';
      else if (ev.chordRoot !== null && ev.chordRoot !== undefined) cls = 'outside';
      const cx = colX + (shiftByRow.get(n.row) ? 20 : 0);
      staffLedgerRows(n.row).forEach(li => {
        svg += `<line class="staff-ledger" x1="${cx - 12}" y1="${y(li)}" x2="${cx + 12}" y2="${y(li)}" />`;
      });
      const name = NOTE_NAMES[pc];
      if (name.length > 1) {
        const glyph = name[1] === '#' ? '♯' : '♭';
        // -18 (not -15) — with `.staff-accidental`'s `text-anchor: middle`, the glyph is
        // centered on this x, so -15 left almost no gap before the notehead's own left edge
        // (`cx - STAFF_NOTE_RX`) once the guide's own single-chord staff got rendered much
        // larger than the shared default — visually cramped/overlapping per feedback.
        svg += `<text class="staff-accidental staff-note-${cls}" x="${cx - 18}" y="${y(n.row) + 4}">${glyph}</text>`;
      }
      svg += `<ellipse class="staff-note staff-note-${cls}" cx="${cx}" cy="${y(n.row)}" rx="${STAFF_NOTE_RX}" ry="${STAFF_NOTE_RY}" />`;
    });
  });

  svg += '</svg>';
  return `<div class="staff-scroll">${svg}</div>`;
}

// Point at angle `2*PI*index/columnCount - PI/2` (column 0 at 12 o'clock, clockwise — matches
// the wheel's fixed ascending-fifths physical layout) on a circle of radius `r` centered at
// (cx, cy) — shared by every ring (chord cells and the mode-name ring), which all place their
// items at the same 12 angular positions (only the radius differs per ring).
function polarPoint(cx, cy, r, index, count) {
  const angle = (2 * Math.PI * index) / count - Math.PI / 2;
  return { x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) };
}

// Degrees to rotate a label around its own `polarPoint` so its baseline runs tangent to the
// wheel (perpendicular to the radius) instead of staying horizontal — same `360*index/count`
// angle already used to spin the square cells (see `renderWheel`), since a label rotated by
// that amount ends up aligned the same way. Flipped by 180° on the lower half of the circle
// (deg strictly between 90 and 270) so labels there still read left-to-right instead of
// upside-down — the tangent line is the same either way, only which end reads "first" flips.
function circularLabelRotation(index, count) {
  const deg = (360 * index) / count;
  return deg > 90 && deg < 270 ? deg + 180 : deg;
}

// One note name per pitch class — mirrors the physical wheel's own mixed convention (sharp
// side C,G,D,A,E,B,F# stays sharp; the remaining 5 black keys are spelled flat: Db,Ab,Eb,
// Bb,F), not a single global sharps-only or flats-only table.
const NOTE_NAMES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
// "C4", "F#3", etc. — the Observer tab's own octave-shift range readout (same as
// `VirtualKeyboardAssets.swift`'s copy).
function noteLabel(pitch) {
  const pc = ((pitch % 12) + 12) % 12;
  const octave = Math.floor(pitch / 12) - 1;
  return NOTE_NAMES[pc] + octave;
}
const CHORD_SUFFIX = { major: '', minor: 'm', diminished: '°' };
// Raises a trailing "°" (diminished-ring degree labels, e.g. "iv°") to a proper superscript —
// SVG text has no <sup>, so this splits it into its own smaller, baseline-shifted <tspan>.
function degreeSVGMarkup(degree) {
  if (!degree.endsWith('°')) return degree;
  return `${degree.slice(0, -1)}<tspan baseline-shift="super" font-size="75%">°</tspan>`;
}
// Same idea for the plain-HTML legend below the wheel, where a real <sup> is available.
function degreeHTMLMarkup(degree) {
  return degree.endsWith('°') ? `${degree.slice(0, -1)}<sup>°</sup>` : degree;
}
// Ring radius per quality, innermost to outermost — matches the physical wheel this is
// modeled on (major closest to center, then minor, then diminished). The hub (center) is
// deliberately large so the major ring — the tightest, being innermost — has as much arc
// length per sector as the others to draw its chord symbol without crowding.
const WHEEL_RING_RADIUS = { major: 110, minor: 160, diminished: 205 };
const WHEEL_MODE_NAME_RADIUS = 248;
const WHEEL_DISK_RADIUS = 262; // the big white disk everything is drawn on
const WHEEL_HUB_RADIUS = 70; // radial divider lines start here — an empty center hub
const WHEEL_GRID_OUTER_RADIUS = 225; // ...and stop here, just inside the mode-name ring
// Ring-boundary circles — midway between each pair of adjacent rings (and the hub/major
// boundary, used only by the diatonic-zone outline below, not drawn as a grid line itself).
const WHEEL_RING_BOUNDARIES = [
  (WHEEL_HUB_RADIUS + WHEEL_RING_RADIUS.major) / 2,
  (WHEEL_RING_RADIUS.major + WHEEL_RING_RADIUS.minor) / 2,
  (WHEEL_RING_RADIUS.minor + WHEEL_RING_RADIUS.diminished) / 2,
];

function renderWheelSection(wheel, tracks, guide) {
  if (!wheel) return '';
  const progressionChords = (guide && guide.isActive) ? (guide.currentChordProgression || []).filter(c => c.quality) : [];
  return `<h2>${t('headingCercleDesQuintes')}</h2>` + renderWheel(wheel, tracks, progressionChords);
}

// The 7 diatonic cells of `wheel.tonic` always occupy exactly 3 adjacent columns — the tonic
// column itself (all 3 rings diatonic: I, vi, vii°) and its two fifths-neighbors (only the
// major+minor rings diatonic: IV+ii on one side, V+iii on the other) — a fixed "crown" shape
// regardless of which tonic. Traces just its OUTER contour (not the internal boundaries
// between its own 7 cells, and not the empty center hub) as a closed SVG path, sampling each
// arc as short line segments to avoid large-arc-flag bookkeeping.
function diatonicBoundaryPath(wheel, cx, cy) {
  const count = wheel.columns.length;
  const tonicIndex = wheel.activeColumnIndex;
  const boundaryAngle = index => (2 * Math.PI * (index + 0.5)) / count - Math.PI / 2;
  const angleLeft = boundaryAngle(tonicIndex - 2);
  const angleIV = boundaryAngle(tonicIndex - 1);
  const angleV = boundaryAngle(tonicIndex);
  const angleRight = boundaryAngle(tonicIndex + 1);
  // Inner edge sits just inside the major ring (NOT the center hub) — the hub/major
  // boundary; mid edge is the minor/diminished boundary (the side columns' major+minor
  // cells are diatonic, their diminished cell isn't); outer edge is the tonic column's own
  // diminished cell's outer boundary.
  const rInner = WHEEL_RING_BOUNDARIES[0];
  const rMid = WHEEL_RING_BOUNDARIES[2];
  const rOuter = WHEEL_GRID_OUTER_RADIUS;

  function arcTo(points, radius, fromAngle, toAngle) {
    const span = toAngle - fromAngle;
    const steps = Math.max(1, Math.ceil((Math.abs(span) * 180) / Math.PI / 3)); // ~3deg/segment
    for (let s = 1; s <= steps; s++) {
      const a = fromAngle + (span * s) / steps;
      points.push({ x: cx + radius * Math.cos(a), y: cy + radius * Math.sin(a) });
    }
  }

  const points = [{ x: cx + rInner * Math.cos(angleLeft), y: cy + rInner * Math.sin(angleLeft) }];
  points.push({ x: cx + rMid * Math.cos(angleLeft), y: cy + rMid * Math.sin(angleLeft) });
  arcTo(points, rMid, angleLeft, angleIV);
  points.push({ x: cx + rOuter * Math.cos(angleIV), y: cy + rOuter * Math.sin(angleIV) });
  arcTo(points, rOuter, angleIV, angleV);
  points.push({ x: cx + rMid * Math.cos(angleV), y: cy + rMid * Math.sin(angleV) });
  arcTo(points, rMid, angleV, angleRight);
  points.push({ x: cx + rInner * Math.cos(angleRight), y: cy + rInner * Math.sin(angleRight) });
  // Close the shape the SHORT way (back to angleLeft, ~90 deg) — going the long way (+2*PI)
  // used to sweep the other 9 columns' worth of the circle at rInner, which reads as "this
  // outline encircles the center hub" even though rInner already sits just outside it.
  arcTo(points, rInner, angleRight, angleLeft);

  return 'M' + points.map(p => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' L') + ' Z';
}

function renderWheel(wheel, tracks, progressionChords) {
  if (!wheel) return '';
  const cx = 270, cy = 270;
  const count = wheel.columns.length;
  let svg = `<svg class="wheel" viewBox="0 0 540 540">`;
  const occupied = [];
  const trackColorByLabel = {};
  (tracks || []).forEach((t, i) => { trackColorByLabel[t.label] = instrumentColor(i); });

  // Big white disk (the physical wheel's card stock) + thin black grid lines marking the
  // zone boundaries — a ring boundary between major/minor and between minor/diminished (not
  // the hub/major one, which exists only to give the diatonic-zone outline an inner edge
  // below), and one radial divider per column pair.
  svg += `<circle class="wheel-disk" cx="${cx}" cy="${cy}" r="${WHEEL_DISK_RADIUS}" />`;
  [WHEEL_RING_BOUNDARIES[1], WHEEL_RING_BOUNDARIES[2]].forEach(r => {
    svg += `<circle class="wheel-grid-line" fill="none" cx="${cx}" cy="${cy}" r="${r}" />`;
  });
  for (let i = 0; i < count; i++) {
    const angle = (2 * Math.PI * (i + 0.5)) / count - Math.PI / 2;
    const x1 = cx + WHEEL_HUB_RADIUS * Math.cos(angle), y1 = cy + WHEEL_HUB_RADIUS * Math.sin(angle);
    const x2 = cx + WHEEL_GRID_OUTER_RADIUS * Math.cos(angle), y2 = cy + WHEEL_GRID_OUTER_RADIUS * Math.sin(angle);
    svg += `<line class="wheel-grid-line" x1="${x1}" y1="${y1}" x2="${x2}" y2="${y2}" />`;
  }

  wheel.columns.forEach((column, index) => {
    if (column.modeName) {
      const pos = polarPoint(cx, cy, WHEEL_MODE_NAME_RADIUS, index, count);
      // Match by NAME, not by pitch class: each mode name is glued at a fixed offset from the
      // active tonic equal to the interval up to its own parent, so the active mode's own name
      // always lands on the PARENT's column (the same column the diatonic boundary is centered
      // on) — comparing pitch classes would only ever match "Ionian" (whichever column IS the
      // active tonic never carries the active mode's own name unless it's Ionian).
      const cls = column.modeName === wheel.activeModeName ? 'wheel-mode-name active' : 'wheel-mode-name';
      const rotate = circularLabelRotation(index, count);
      svg += `<text class="${cls}" x="${pos.x}" y="${pos.y}" transform="rotate(${rotate} ${pos.x} ${pos.y})">${column.modeName}</text>`;
    }
    // Each cell has its OWN chord root (`cell.pitchClass`) — only the major ring is rooted
    // on the column itself; minor/diminished are the column's relative-minor/leading-tone-
    // diminished, so color/shape/note-name must come from the cell, not the column.
    column.cells.forEach(cell => {
      const r = WHEEL_RING_RADIUS[cell.quality];
      const pos = polarPoint(cx, cy, r, index, count);
      const color = PITCH_CLASS_COLORS[cell.pitchClass];
      const textColor = PITCH_CLASS_TEXT_COLORS[cell.pitchClass];
      const size = 18;
      const rotateDeg = (360 * index) / count;
      if (cell.shape === 'square') {
        // Rotated so the square's own axis points through the disk's center (purely
        // decorative — matches the physical wheel's alternating circle/square look without
        // every square sitting flat/axis-aligned with the page). Text stays outside this
        // rotated group so labels stay upright and readable.
        svg += `<g transform="rotate(${rotateDeg} ${pos.x} ${pos.y})"><rect class="wheel-cell-shape" x="${pos.x - size}" y="${pos.y - size}" width="${size * 2}" height="${size * 2}" fill="${color}" /></g>`;
      } else {
        svg += `<circle class="wheel-cell-shape" cx="${pos.x}" cy="${pos.y}" r="${size}" fill="${color}" />`;
      }
      const symbol = NOTE_NAMES[cell.pitchClass] + CHORD_SUFFIX[cell.quality];
      svg += `<text class="wheel-cell-symbol" x="${pos.x}" y="${pos.y + 1}" fill="${textColor}">${symbol}</text>`;
      svg += `<text class="wheel-cell-degree" x="${pos.x}" y="${pos.y + 9}" fill="${textColor}">${degreeSVGMarkup(cell.relativeDegree)}</text>`;

      // One extra unfilled outline per occupying track, nested outward in that track's own
      // accent color — distinguishes which instrument(s) are sounding this exact chord
      // instead of a single shared "occupied" indicator.
      if ((cell.trackLabels || []).length) {
        occupied.push(cell);
        cell.trackLabels.forEach((label, labelIndex) => {
          const outlineSize = size + 6 + labelIndex * 6;
          const outlineColor = trackColorByLabel[label] || '#2979ff';
          svg += cell.shape === 'square'
            ? `<g transform="rotate(${rotateDeg} ${pos.x} ${pos.y})"><rect class="wheel-cell-outline" x="${pos.x - outlineSize}" y="${pos.y - outlineSize}" width="${outlineSize * 2}" height="${outlineSize * 2}" stroke="${outlineColor}" /></g>`
            : `<circle class="wheel-cell-outline" cx="${pos.x}" cy="${pos.y}" r="${outlineSize}" stroke="${outlineColor}" />`;
        });
      }
      // Bold outline for every cell whose (root, quality) is part of the active guide step's
      // attached chord progression — a fixed color, unrelated to any track, stacked outward
      // past any track outlines above so both remain visible on the same cell.
      if ((progressionChords || []).some(c => c.root === cell.pitchClass && c.quality === cell.quality)) {
        const outlineSize = size + 6 + (cell.trackLabels || []).length * 6;
        svg += cell.shape === 'square'
          ? `<g transform="rotate(${rotateDeg} ${pos.x} ${pos.y})"><rect class="wheel-cell-outline" x="${pos.x - outlineSize}" y="${pos.y - outlineSize}" width="${outlineSize * 2}" height="${outlineSize * 2}" stroke="#ffb300" /></g>`
          : `<circle class="wheel-cell-outline" cx="${pos.x}" cy="${pos.y}" r="${outlineSize}" stroke="#ffb300" />`;
      }
    });
  });

  // The 7-chord diatonic zone's outer contour, dark blue — drawn last so it reads clearly on
  // top of the grid lines and cell edges, per the current tonic/mode's own selection.
  svg += `<path class="wheel-diatonic-boundary" d="${diatonicBoundaryPath(wheel, cx, cy)}" />`;

  svg += '</svg>';

  // Multi-instrument legend: which track(s) currently sound each occupied cell's chord,
  // each name colored to match its own outline ring above.
  if (occupied.length) {
    svg += '<div class="field">' + occupied.map(cell => {
      const symbol = NOTE_NAMES[cell.pitchClass] + CHORD_SUFFIX[cell.quality];
      const labels = cell.trackLabels.map(label => `<b style="color:${trackColorByLabel[label] || '#2979ff'}">${label}</b>`).join(', ');
      return `${symbol} (${degreeHTMLMarkup(cell.relativeDegree)}): ${labels}`;
    }).join(' &middot; ') + '</div>';
  }
  return svg;
}

// Renders the proposed chord's guitar-tab diagram (see `WebConsoleGuitarChordDiagram`) as a
// small SVG fretboard box — a "no standard position" message (see `GuitarChordShape`'s own
// doc comment for why not every chord quality is covered) if `diagram` is null despite a
// chord being selected (the caller only invokes this once a chord IS selected at all).
// String order left-to-right matches `diagram.frets`/`fingers`: index 0 = string 6 (low E)
// on the left, index 5 = string 1 (high e) on the right — the same orientation as looking at
// a right-handed guitar's fretboard face-on.
function guitarChordDiagramHTML(diagram) {
  if (!diagram) return `<div class="field empty">${t('placeholderPasDePositionGuitareStandard')}</div>`;
  const frets = diagram.frets || [];
  const fingers = diagram.fingers || [];
  const stringCount = 6;
  const shownFrets = 4; // barre fret + 3 more — enough for every covered shape's highest offset (+3)
  // marginTop reduced from its original 28 — just enough room left for the muted-string "×"
  // markers/fret-number label above the first fret line, per feedback that the gap between the
  // chord-name label above and the grid itself read as too tall.
  const width = 150, height = 172, marginLeft = 24, marginTop = 22, marginBottom = 16;
  const stringSpacing = (width - marginLeft * 2) / (stringCount - 1);
  const fretSpacing = (height - marginTop - marginBottom) / shownFrets;
  let svg = `<svg width="${width}" height="${height}" viewBox="0 0 ${width} ${height}" class="guitar-diagram">`;
  for (let s = 0; s < stringCount; s++) {
    const x = marginLeft + s * stringSpacing;
    svg += `<line x1="${x}" y1="${marginTop}" x2="${x}" y2="${marginTop + shownFrets * fretSpacing}" class="guitar-string" />`;
  }
  for (let f = 0; f <= shownFrets; f++) {
    const y = marginTop + f * fretSpacing;
    svg += `<line x1="${marginLeft}" y1="${y}" x2="${marginLeft + (stringCount - 1) * stringSpacing}" y2="${y}" class="guitar-fret" />`;
  }
  svg += `<text x="${marginLeft - 14}" y="${marginTop + fretSpacing / 2 + 4}" class="guitar-fret-label">${diagram.barreFret}</text>`;
  const barredIndices = frets.map((f, i) => f === 0 ? i : null).filter(i => i !== null);
  if (barredIndices.length > 1) {
    const x1 = marginLeft + Math.min(...barredIndices) * stringSpacing;
    const x2 = marginLeft + Math.max(...barredIndices) * stringSpacing;
    const y = marginTop + fretSpacing / 2;
    svg += `<line x1="${x1}" y1="${y}" x2="${x2}" y2="${y}" class="guitar-barre" />`;
  }
  frets.forEach((relativeFret, i) => {
    const x = marginLeft + i * stringSpacing;
    if (relativeFret === null || relativeFret === undefined) {
      svg += `<text x="${x}" y="${marginTop - 10}" class="guitar-muted">×</text>`;
      return;
    }
    if (relativeFret === 0) return; // already covered by the barre bar (or a lone barre dot below)
    const y = marginTop + (relativeFret + 0.5) * fretSpacing;
    svg += `<circle cx="${x}" cy="${y}" r="8" class="guitar-dot" />`;
    if (fingers[i] !== null && fingers[i] !== undefined) {
      svg += `<text x="${x}" y="${y + 4}" class="guitar-finger">${fingers[i]}</text>`;
    }
  });
  // A single barred string with no other string sharing the barre fret still needs its own dot.
  if (barredIndices.length === 1) {
    const x = marginLeft + barredIndices[0] * stringSpacing;
    const y = marginTop + fretSpacing / 2;
    svg += `<circle cx="${x}" cy="${y}" r="8" class="guitar-dot" />`;
  }
  svg += '</svg>';
  return `<div class="guitar-diagram-label">${diagram.label}</div>${svg}`;
}

// Builds a single `renderStaffSVG` event for the guide's proposed chord (root + tones), for the
// Guide panel's "partition" column — a static snapshot, not a live-performance event. `tones`
// already includes the root itself as its first entry (offset 0 — see
// `ImprovSession.pitchClassSets`'s `intervalsFromRoot` mapping) and every template's intervals
// are guaranteed < 12 (no chord spans more than an octave), so `(pc - root + 12) % 12` recovers
// each tone's exact original semitone offset from the root with no ambiguity, letting every
// tone be placed as a simple close-position voicing stacked up from one fixed anchor octave
// (`60` = middle C) rather than needing any real per-note octave data the server doesn't send.
function chordStaffEvent(root, tones) {
  const rootMidi = 60 + root;
  const pitches = (tones || []).map(pc => rootMidi + (((pc - root) % 12) + 12) % 12);
  return { pitches, chordRoot: root, chordTones: tones || [] };
}

function renderGuide(guide) {
  if (!guide || !guide.isActive) return '';
  let html = `<h2>${t('headingGuide')}</h2><br>`;
  html += '<div class="field">' + (guide.steps || []).map(
    step => step.isCurrent ? `<b>[${step.label}]</b>` : step.label
  ).join(' ') + '</div>';
  const progression = guide.currentChordProgression || [];
  if (progression.length) {
    const prefix = guide.currentChordProgressionName ? t('formatSuiteAccordsNamed', guide.currentChordProgressionName) : t('fieldSuiteAccords');
    const chordsHTML = progression.map(
      (c, i) => i === guide.currentChordIndex ? `<b>[${c.label}]</b>` : c.label
    ).join(' - ');
    html += `<div class="field">${prefix}: ${chordsHTML}</div>`;
  }
  // Both arrow hints consolidated into one italic line here, shown once — the plain headings
  // below no longer carry either hint inline the way the terminal's own
  // `headingClavierGuide`/`headingClavierAccordGuide` still do.
  html += `<div class="field hint">${t('hintNavigationGuideWeb')}</div>`;

  const hasChord = guide.currentChordIndex !== null && guide.currentChordIndex !== undefined;

  // One heading for both keyboards (not one per keyboard) — the mode keyboard shows root-vs-
  // rest of the mode (`.mode-root`/`.mode-tone`, not the chord's `.root`/`.tone`), the chord
  // keyboard shows root-vs-rest of the currently-proposed chord. Neither shows held pitches —
  // static reference diagrams for what's suggested, not live-performance feedback.
  const guideKeyboardRange = { minMidi: 60, maxMidi: 83 };
  let keyboardsHTML = `<h3>${t('headingModeEtAccordGuideWeb')}</h3>`;
  keyboardsHTML += keyboardHTML([], null, [], guide.currentModeTones, false, { ...guideKeyboardRange, showModeColoring: true });
  if (hasChord) {
    keyboardsHTML += keyboardHTML([], guide.currentChordRoot ?? null, guide.currentChordTones || [], [], true, guideKeyboardRange);
  }

  // Notation (left) and tab (right) both depend on a chord actually being selected — neither
  // has anything to show for a mode-only step (no progression, or nothing navigated to yet).
  // Each heading sits as a plain first child of its column (flush with the other two, all 3
  // starting the row at the same top line) with the actual graphic wrapped in `.guide-col-fill`
  // below it, bottom-aligned like the tab (see `.guide-col-tab .guide-col-fill`'s comment).
  // `minWidthPx: 84` sets how much wider than its bare minimum content width the viewBox is;
  // `-10` shifts the chord's own notes a bit closer to the clef; `380` is a fixed display
  // height, sized to look properly proportioned next to the keyboards/tab (see
  // `renderStaffSVG`'s `displayHeightPx` comment for why this isn't dynamically computed).
  const notationHTML = hasChord
    ? `<h3>${t('headingPartitionGuideWeb')}</h3><div class="guide-col-fill">`
      + renderStaffSVG([chordStaffEvent(guide.currentChordRoot, guide.currentChordTones)], 84, -10, 380) + `</div>`
    : '';
  const tabHTML = hasChord
    ? `<h3>${t('headingTablatureGuideWeb')}</h3><div class="guide-col-fill">${guitarChordDiagramHTML(guide.currentChordGuitarDiagram)}</div>`
    : '';

  html += `<div class="guide-layout">`
    + `<div class="guide-col-notation">${notationHTML}</div>`
    + `<div class="guide-col-keyboards">${keyboardsHTML}</div>`
    + `<div class="guide-col-tab">${tabHTML}</div>`
    + `</div>`;

  // The guide's own step is prescribed, not "recently played" — a single current snapshot,
  // not a rolling history like a live track's own staff below. `GUIDE_ROW_WIDTH_ESTIMATE` (not
  // `KEYBOARD_TOTAL_WIDTH`, sized for the Run tab's own wider 3-octave keyboard) so this staff's
  // right edge reaches roughly as far as the tablature's own right edge above it.
  html += renderStaffSVG([{ pitches: guide.heldPitches, chordRoot: null, chordTones: [] }], GUIDE_ROW_WIDTH_ESTIMATE);
  return html;
}

function renderTrack(track, index) {
  const owner = track.owner ? ` — ${track.owner}` : '';
  const swatch = `<span class="instrument-swatch" style="background:${instrumentColor(index)}"></span>`;
  // No `[track.id]` prefix here (used to leak a web-keyboard client's raw uuid, e.g.
  // "clavier-web:9F2A..." — see `sceneTrackLineHTML`'s own comment) — this is a read-only
  // viewer, not a place to type commands, so the label alone (already the display alias for a
  // web keyboard track) is all a viewer needs.
  let html = `<h2>${swatch}${track.label}${owner}</h2>`;
  if (track.microphoneLevel !== null && track.microphoneLevel !== undefined) {
    html += `<div class="field">${t('fieldMicro')}: <b>${track.microphoneLevel.toFixed(4)}</b></div>`;
    html += `<div class="field">${t('fieldModeReconnaissance')}: <b>${track.recognitionMode || t('fallbackTiret')}</b></div>`;
  }
  html += keyboardHTML(track.heldPitches, track.chordRoot, track.chordTones, track.modeTones);
  html += renderStaffSVG(track.recentChordEvents || [], KEYBOARD_TOTAL_WIDTH);
  html += `<div class="field">${t('fieldAccordWeb')}: <b>${track.chordLabel || t('fallbackTiret')}</b></div>`;
  html += `<div class="field">${t('fieldModes')}: <b>${track.modesLabel || t('fallbackTiret')}</b></div>`;
  return html;
}

// Observer tab's own persistent (across-poll) client state — the octave window and which
// track is selected. Unlike the Menu tab's own DOM-persistence dance (see `refreshMenuLists`'s
// own comment), a full per-poll HTML rebuild is safe here: neither of these two pieces of state
// is ever read back FROM the DOM, so rebuilding this tab from scratch every ~250ms (exactly
// like Run/Scene/Infos already do) never loses anything.
let observerMinMidi = MIN_MIDI, observerMaxMidi = MAX_MIDI;
let observerSelectedTrackID = null; // null = "not chosen yet" -> falls back to tracks[0]
function shiftObserverOctave(delta) {
  observerMinMidi += delta * 12;
  observerMaxMidi += delta * 12;
  refresh();
}

// Same rich layout as the virtual keyboard page (guide left, keyboard+wheel+staff right) but
// for spectating any OTHER already-connected instrument instead of playing one's own — a
// picklist over `state.tracks` (already fetched every poll here, no separate endpoint needed)
// picks which track's held notes/chord/mode drive the keyboard below it (bigger than this
// file's own default — see `keyboardHTML`'s `options.bigKeys`). Purely read-only: no click
// handlers anywhere in this function's own output, unlike the virtual keyboard page's piano.
function renderObserverTab(state) {
  const tracks = state.tracks || [];
  if (!tracks.length) {
    return `<p class="empty">${t('placeholderAucunePisteEnEcouteWeb')}</p>`;
  }
  // Falls back to the first track WITHOUT mutating `observerSelectedTrackID` itself — if the
  // previously-selected track just disconnected, the `<select>`'s own `selected` attribute
  // below reflects this fallback so the picklist always shows what's actually on screen,
  // without silently "forgetting" a still-valid choice for whenever that track reconnects.
  const selectedID = tracks.some(tr => tr.id === observerSelectedTrackID) ? observerSelectedTrackID : tracks[0].id;
  const track = tracks.find(tr => tr.id === selectedID);

  const pickerHTML = '<select class="observer-track-select" onchange="observerSelectedTrackID=this.value; refresh();">' +
    tracks.map(tr => `<option value="${tr.id}"${tr.id === selectedID ? ' selected' : ''}>${tr.label}${tr.owner ? ' — ' + tr.owner : ''}</option>`).join('') +
    '</select>';

  const octaveHTML = `<div class="octave-controls"><b>${noteLabel(observerMinMidi)}</b>` +
    `<a class="octave-arrow" onclick="shiftObserverOctave(-1)">◂</a>` +
    `<a class="octave-arrow" onclick="shiftObserverOctave(1)">▸</a>` +
    `<b>${noteLabel(observerMaxMidi)}</b></div>`;

  // Matches the big keyboard's own actual on-screen width (see `keyboardHTML`'s `bigKeys`
  // dimensions), not `KEYBOARD_TOTAL_WIDTH` (sized for this file's small default keys) — same
  // "staff never narrower than the keyboard above it" principle as every other caller here.
  const bigKeyboardWidth = Math.ceil((observerMaxMidi - observerMinMidi + 1) / 12) * 7 * 44;
  const keyboardOptions = { minMidi: observerMinMidi, maxMidi: observerMaxMidi, bigKeys: true };
  const rightHTML = pickerHTML + octaveHTML
    + keyboardHTML(track.heldPitches, track.chordRoot, track.chordTones, track.modeTones, false, keyboardOptions)
    + `<div class="field">${t('fieldAccordWeb')}: <b>${track.chordLabel || t('fallbackTiret')}</b></div>`
    + `<div class="field">${t('fieldModes')}: <b>${track.modesLabel || t('fallbackTiret')}</b></div>`
    + renderWheelSection(state.wheel, tracks, state.guide)
    + renderStaffSVG(track.recentChordEvents || [], bigKeyboardWidth);

  const leftHTML = renderGuide(state.guide);
  return `<div class="layout-columns"><div class="layout-col-left">${leftHTML}</div><div class="layout-col-right">${rightHTML}</div></div>`;
}

function renderPlayback(playback) {
  if (!playback) return '';
  let html = `<h2>${t('headingMorceauEnCoursDeLecture')}</h2>`;
  html += '<div class="field">' + (playback.timeline || []).map(
    seg => seg.isCurrent ? `<b>[${seg.label}]</b>` : seg.label
  ).join(' ') + '</div>';
  html += keyboardHTML(playback.heldPitches, playback.chordRoot, playback.chordTones, playback.modeTones);
  html += renderStaffSVG([{ pitches: playback.heldPitches, chordRoot: playback.chordRoot, chordTones: playback.chordTones }], KEYBOARD_TOTAL_WIDTH);
  return html;
}

function renderSoundTrackPlayback(playback) {
  if (!playback) return '';
  return `<h2>${t('headingEnregistrementEnCoursDeLecture')}</h2>`
    + keyboardHTML(playback.heldPitches, null, [], [])
    + renderStaffSVG([{ pitches: playback.heldPitches, chordRoot: null, chordTones: [] }], KEYBOARD_TOTAL_WIDTH);
}

function renderRunTab(state) {
  const tracks = state.tracks || [];
  // No client-side staff-history bookkeeping to prune anymore (see `renderStaffSVG`'s own
  // comment) — a track's `recentChordEvents` just comes and goes with the track itself, server-side.
  const tracksHTML = tracks.length
    ? tracks.map(renderTrack).join('')
    : `<p class="empty">${t('placeholderAucunePisteEnEcouteWeb')}</p>`;

  // Always the same 2-column layout: left is just the wheel ("what mode/key are we in"),
  // right leads with whatever represents "the mode" right now — the guide's own keyboard if
  // one is running, the piece/soundtrack currently playing otherwise — then every individual
  // active instrument's own keyboard below that. Reading "the mode" and "who's playing what"
  // side by side is the point, whether or not a guide happens to be active.
  const modeHTML = renderGuide(state.guide) + renderPlayback(state.playback) + renderSoundTrackPlayback(state.soundTrackPlayback);
  const left = renderWheelSection(state.wheel, tracks, state.guide);
  const right = modeHTML + tracksHTML;
  return `<div class="layout-columns"><div class="layout-col-left">${left}</div><div class="layout-col-right">${right}</div></div>`;
}

// Static, no live data — just the page's own description, moved here from a permanent page
// header so the Run/Scene tabs aren't cluttered with it on every visit.
function renderInfosTab() {
  return `<h1>${t('textInfosTab')}</h1>`;
}

// One line of the Scene tab's tree (see `renderSceneTree`) — mirrors the terminal's own
// `printSceneTree` line format minus the bracketed id (that id exists so the terminal user can
// type it into a command; there's nothing to type here, and for a web-keyboard track it'd leak
// that client's raw uuid, e.g. "clavier-web:9F2A...", for no benefit).
function sceneTrackLineHTML(track) {
  let line = track.label;
  if (track.owner) line += ` — ${track.owner}`;
  line += `${t('labelEcoutePrefix')}<b>${track.isListening ? t('labelOui') : t('labelNon')}</b>`;
  if (track.canHaveSound) {
    line += `${t('labelSonPrefix')}<b>${track.soundEnabled ? t('labelOui') : t('labelNon')}</b>`;
    if (track.instrumentName) line += ` (${track.instrumentName})`;
  }
  return line;
}

// The "plan de scene" tree — app + local instruments + web console/virtual keyboard status,
// and (server mode only) every connected jam-session participant with their own instruments
// nested underneath, exactly like the terminal's `scene-tree` command, but as a nested HTML
// list instead of ASCII box-drawing (more natural to read in a browser).
function renderSceneTree(scene) {
  if (!scene) return '';
  const isServer = scene.networkRoleText.indexOf('serveur') === 0;
  let html = `<div class="field">${t('labelMode')}<b>${scene.networkRoleText}</b></div>`;
  html += '<ul class="scene-tree">';

  // The scene/roles concept as its own clearly-labeled, always-present branch — shown even
  // with no active scene ("(aucune)") so the concept itself is always visible in the tree,
  // not just when it happens to be in use, and placed BEFORE "Instruments locaux" since a
  // scene/role is the declarative concept an instrument then gets attached to, not the other
  // way around. See `Sources/AppCore/Scene.swift`'s own doc comments for what a role is.
  const roles = scene.roles || [];
  html += `<li>${t('labelSceneTree')}` + (scene.sceneTitle ? `<b>${scene.sceneTitle}</b>` : `<span class="empty">${t('placeholderAucune')}</span>`);
  if (scene.sceneTitle) {
    html += roles.length
      ? '<ul>' + roles.map(role => {
          const soundText = role.soundName ? ` [${role.soundName}]` : '';
          const attachedText = role.attachedLabel ? `<b>${role.attachedLabel}</b>` : `<span class="empty">${t('placeholderLibre')}</span>`;
          return `<li>${role.name} — ${attachedText}${soundText}</li>`;
        }).join('') + '</ul>'
      : ` <span class="empty">${t('placeholderAucunRoleDeclare')}</span>`;
  }
  html += '</li>';

  const localInstruments = scene.localInstruments || [];
  html += `<li>${t('labelInstrumentsLocaux')}` + (
    localInstruments.length
      ? '<ul>' + localInstruments.map(track => `<li>${sceneTrackLineHTML(track)}</li>`).join('') + '</ul>'
      : ` <span class="empty">${t('placeholderAucun')}</span>`
  ) + '</li>';

  html += `<li>${t('labelConsoleWebPrefix')}<b>${scene.webConsolePort ? 'http://localhost:' + scene.webConsolePort : t('placeholderInactive')}</b></li>`;
  html += `<li>${t('labelClavierVirtuelPrefix')}<b>${scene.virtualKeyboardPort ? 'http://localhost:' + scene.virtualKeyboardPort : t('placeholderInactif')}</b></li>`;

  if (isServer) {
    const clients = scene.clients || [];
    html += `<li>${t('formatClientsConnectes', clients.length)}`;
    if (clients.length) {
      html += '<ul>' + clients.map(client => {
        const instruments = client.instruments || [];
        const inner = instruments.length
          ? '<ul>' + instruments.map(track => `<li>${sceneTrackLineHTML(track)}</li>`).join('') + '</ul>'
          : ` <span class="empty">${t('labelAucunInstrumentEncore')}</span>`;
        return `<li>${client.name}${inner}</li>`;
      }).join('') + '</ul>';
    } else {
      html += ` <span class="empty">${t('placeholderAucun')}</span>`;
    }
    html += '</li>';
  }

  html += '</ul>';
  return html;
}

// --- "Menu" tab — a remote-control mirror of the terminal's own pull-down menu ---
//
// `Sources/JamShack/main.swift`'s `menuCategories` (and the plain-text REPL) both funnel into
// one shared `executeCommand(_:_:)` switch, which calls `AppCore.ImprovSession`'s public
// methods directly — this tab is that same command surface reached over HTTP instead
// (`GET /menu-action?action=...&...params`, dispatched by `ImprovSession.performMenuAction`),
// NOT a second copy of the terminal's own menu-building code. Deliberately excludes every
// pure read-only display item (status/run/scene-tree/show-*) — those already exist elsewhere
// (Run/Scene/Infos tabs) — and decomposes the CLI menu's few multi-step "wizards" (e.g.
// "Nouveau guide musical..."'s repeating tonic/scale/progression loop) into their underlying
// atomic commands (`guide-new`, `guide-add-mode`), submitted independently instead of chained
// through prompts — a browser form naturally collects every field in one submission, so there
// is no need to reproduce the terminal's own step-by-step prompting here.
let menuBuilt = false;
let menuLists = null; // last `GET /menu-lists` response — see `refreshMenuLists`

const NOTE_NAME_TONIC_OPTIONS = NOTE_NAMES.map((name, pc) => ({ value: String(pc), labelKey: null, label: name }));

// `labelKey`/`fields[].labelKey`/`fields[].placeholderKey` are `L10nKey` id strings looked up
// live via `t(...)` at render time (see `menuItemRowHTML`/`menuFieldControlHTML`) — NOT
// pre-resolved strings — so a language change followed by a Menu-tab rebuild (`buildMenuTab()`,
// triggered by `refreshMenuLists()` noticing `menuLists.language` changed) actually picks up the
// new language, instead of forever showing whatever language happened to be active when this
// array literal was first evaluated. `category` stays each category's ORIGINAL French name and
// is never displayed directly anymore — it's now purely a stable identifier (matched against
// `activeMenuCategory`/`data-category`); `categoryLabelKey` is what's actually shown, via
// `renderMenuSubTabBar`. Every item label here that also exists in the terminal's own
// `buildMenuCategories` (`JamShack/main.swift`) reuses the exact same `L10nKey` — see
// `Localization.L10nKey`/`L10nTable` for the single shared FR/EN/DE source of truth.
const MENU_ACTIONS = [
  { category: 'JamShack', categoryLabelKey: 'catJamShack', items: [
    { action: 'folder-pieces', labelKey: 'menuChoisirDossierMorceaux', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderCheminDuDossier' }] },
    { action: 'folder-samples', labelKey: 'menuChoisirDossierSons', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderCheminDuDossier' }] },
    { action: 'folder-soundtracks', labelKey: 'menuChoisirDossierSoundtracks', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderCheminDuDossier' }] },
    { action: 'folder-guides', labelKey: 'menuChoisirDossierGuides', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderCheminDuDossier' }] },
    { action: 'folder-scenes', labelKey: 'menuChoisirDossierScenes', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderCheminDuDossier' }] },
    { action: 'folder-settings', labelKey: 'menuChoisirDossierReglages', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderCheminDuDossier' }] },
    { action: 'folder-prompts', labelKey: 'menuChoisirDossierCompositionIA', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderCheminDuDossier' }] },
    { action: 'use-llm', labelKey: 'menuChoisirConnexionLLM', fields: [{ name: 'value', kind: 'select', list: 'llmConnections' }] },
    { action: 'use-palette', labelKey: 'menuChoisirPalette', fields: [{ name: 'value', kind: 'select', list: 'colorPalettes' }] },
    { action: 'midi-mode-merged', labelKey: 'menuMidiModeFusionne', fields: [] },
    { action: 'midi-mode-individual', labelKey: 'menuMidiModeIndividuel', fields: [] },
    { action: 'refresh-midi', labelKey: 'menuRefreshMidi', fields: [] },
    { action: 'web-console-start', labelKey: 'menuDemarrerConsoleWeb', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderPort8080', optional: true }] },
    { action: 'web-console-stop', labelKey: 'menuArreterConsoleWeb', fields: [] },
    { action: 'vk-start', labelKey: 'menuDemarrerClavierVirtuel', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderPort8081', optional: true }] },
    { action: 'vk-stop', labelKey: 'menuArreterClavierVirtuel', fields: [] },
    { action: 'lumi-root-color', labelKey: 'menuLumiCouleurRacine', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderLumiCouleurHex' }] },
    { action: 'lumi-scale-color', labelKey: 'menuLumiCouleurGamme', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderLumiCouleurHex' }] },
    { action: 'lumi-brightness', labelKey: 'menuLumiLuminosite', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderLumiLuminosite' }] },
    { action: 'lumi-auto-run-on', labelKey: 'menuLumiAutoRunActiver', fields: [] },
    { action: 'lumi-auto-run-off', labelKey: 'menuLumiAutoRunDesactiver', fields: [] },
    { action: 'lumi-auto-guide-on', labelKey: 'menuLumiAutoGuideActiver', fields: [] },
    { action: 'lumi-auto-guide-off', labelKey: 'menuLumiAutoGuideDesactiver', fields: [] },
  ] },
  { category: 'Scene', categoryLabelKey: 'catScene', items: [
    { action: 'track-on', labelKey: 'menuActiverInstrument', fields: [{ name: 'value', kind: 'select-track' }] },
    { action: 'track-off', labelKey: 'menuArreterInstrument', fields: [{ name: 'value', kind: 'select-track' }] },
    { action: 'track-sound-on', labelKey: 'menuActiverSonInstrument', fields: [{ name: 'value', kind: 'select-track' }] },
    { action: 'track-sound-off', labelKey: 'menuDesactiverSonInstrument', fields: [{ name: 'value', kind: 'select-track' }] },
    { action: 'track-instrument', labelKey: 'menuChoisirSonPourInstrument', fields: [
        { name: 'track', kind: 'select-track', labelKey: 'fieldInstrument' },
        { name: 'value', kind: 'select', list: 'sampleFiles', labelKey: 'fieldSon' },
      ] },
    { action: 'track-recognition-mode', labelKey: 'menuChoisirModeReconnaissanceMicro', fields: [
        { name: 'track', kind: 'select-track', labelKey: 'fieldInstrument' },
        { name: 'value', kind: 'select', labelKey: 'fieldModeReconnaissance', options: [
            { value: 'mono-heuristique', labelKey: 'optionMonoHeuristique' },
            { value: 'mono-hps', labelKey: 'optionMonoHPS' },
            { value: 'poly-latched', labelKey: 'optionPolyLatched' },
            { value: 'poly-glissant', labelKey: 'optionPolySliding' },
          ] },
      ] },
    { action: 'scene-save', labelKey: 'menuSauvegarderScene', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'scene-load', labelKey: 'menuChargerScene', fields: [{ name: 'value', kind: 'select', list: 'sceneFiles' }] },
    { action: 'scene-new', labelKey: 'menuNouvelleScene', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderTitreCourt' }] },
    { action: 'scene-role-add', labelKey: 'menuAjouterRole', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'scene-role-sound', labelKey: 'menuChoisirSonDunRole', fields: [
        { name: 'role', kind: 'select', list: 'sceneRoles', labelKey: 'fieldRole' },
        { name: 'value', kind: 'select', list: 'sampleFiles', labelKey: 'fieldSon', optional: true },
      ] },
    { action: 'scene-role-listen', labelKey: 'menuEcouteDunRole', fields: [
        { name: 'role', kind: 'select', list: 'sceneRoles', labelKey: 'fieldRole' },
        { name: 'value', kind: 'select', labelKey: 'fieldEcoute', options: [{ value: 'on', labelKey: 'optionActiver' }, { value: 'off', labelKey: 'optionArreter' }] },
      ] },
    { action: 'scene-role-attach', labelKey: 'menuAttacherInstrumentARole', fields: [
        { name: 'role', kind: 'select', list: 'sceneRoles', labelKey: 'fieldRole' },
        { name: 'value', kind: 'select', list: 'unassignedTracks', labelKey: 'fieldInstrument' },
      ] },
    { action: 'scene-role-detach', labelKey: 'menuDetacherRole', fields: [{ name: 'value', kind: 'select', list: 'sceneRoles' }] },
  ] },
  { category: 'Guide Musicaux', categoryLabelKey: 'catGuideMusicaux', items: [
    { action: 'guide-new', labelKey: 'menuNouveauGuideMusical', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderTitreCourt' }] },
    { action: 'guide-add-mode', labelKey: 'menuAjouterModeAuGuideCourt', fields: [
        { name: 'tonic', kind: 'select', options: NOTE_NAME_TONIC_OPTIONS, labelKey: 'fieldTonique' },
        { name: 'scale', kind: 'select', list: 'scales', labelKey: 'fieldGamme' },
        { name: 'progression', kind: 'select', list: 'chordProgressionTemplates', labelKey: 'fieldProgression', optional: true },
      ] },
    { action: 'guide-load', labelKey: 'menuChargerGuideMusical', fields: [{ name: 'value', kind: 'select', list: 'guideFiles' }] },
    { action: 'guide-save', labelKey: 'menuSauvegarderGuideMusical', fields: [] },
    { action: 'guide-save-as', labelKey: 'menuSauvegarderGuideMusicalSous', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'guide-start', labelKey: 'menuDemarrerGuideMusical', fields: [] },
    { action: 'guide-stop', labelKey: 'menuArreterGuideMusical', fields: [] },
  ] },
  { category: 'Enregistrement', categoryLabelKey: 'catEnregistrement', items: [
    { action: 'record-start', labelKey: 'menuDemarrerEnregistrement', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderPistesSepareesParEspace', optional: true }] },
    { action: 'record-stop', labelKey: 'menuArreterEnregistrement', fields: [] },
    { action: 'soundtrack-play', labelKey: 'menuJouerEnregistrement', fields: [] },
    { action: 'soundtrack-load', labelKey: 'menuChargerEnregistrement', fields: [{ name: 'value', kind: 'select', list: 'soundTrackFiles' }] },
    { action: 'soundtrack-save', labelKey: 'menuSauvegarderEnregistrement', fields: [] },
    { action: 'soundtrack-save-as', labelKey: 'menuSauvegarderEnregistrementSous', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'soundtrack-compose', labelKey: 'menuComposerDepuisEnregistrement', fields: [
        { name: 'value', kind: 'text', placeholderKey: 'placeholderTitreCourt', labelKey: 'fieldTitre', optional: true },
        { name: 'count', kind: 'text', placeholderKey: 'placeholderUn', labelKey: 'fieldNombreCandidats', optional: true },
      ] },
    { action: 'soundtrack-framing-set', labelKey: 'menuModifierPhraseDeCadrage', fields: [{ name: 'value', kind: 'textarea' }] },
    { action: 'soundtrack-framing-save', labelKey: 'menuSauvegarderPhraseDeCadrage', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'soundtrack-framing-load', labelKey: 'menuChargerPhraseDeCadrage', fields: [{ name: 'value', kind: 'select', list: 'soundTrackFramingFiles' }] },
    { action: 'soundtrack-framing-reset', labelKey: 'menuRevenirPhraseDeCadrageParDefaut', fields: [] },
    { action: 'soundtrack-instructions-set', labelKey: 'menuModifierIndicationsStyle', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderIndicationsCourt', optional: true }] },
    { action: 'soundtrack-instructions-save', labelKey: 'menuSauvegarderIndicationsStyle', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'soundtrack-instructions-load', labelKey: 'menuChargerIndicationsStyle', fields: [{ name: 'value', kind: 'select', list: 'soundTrackInstructionsFiles' }] },
    { action: 'soundtrack-instructions-reset', labelKey: 'menuRevenirIndicationsStyleParDefaut', fields: [] },
    { action: 'soundtrack-prompt-export', labelKey: 'menuExporterPromptComposition', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
  ] },
  { category: 'Morceaux', categoryLabelKey: 'catMorceaux', items: [
    { action: 'piece-play', labelKey: 'menuEcouterMorceau', fields: [] },
    { action: 'piece-sample', labelKey: 'menuChoisirSonLectureMorceau', fields: [{ name: 'value', kind: 'select', list: 'sampleFiles' }] },
    { action: 'piece-track-instrument', labelKey: 'menuChoisirSonDunePiste', fields: [
        { name: 'section', kind: 'text', placeholderKey: 'placeholderSectionNum', labelKey: 'fieldSection' },
        { name: 'track', kind: 'text', placeholderKey: 'placeholderPisteNum', labelKey: 'fieldPiste' },
        { name: 'value', kind: 'select', list: 'sampleFiles', labelKey: 'fieldSon', optional: true },
      ] },
    { action: 'piece-chord-instrument', labelKey: 'menuChoisirSonAccordsSection', fields: [
        { name: 'section', kind: 'text', placeholderKey: 'placeholderSectionNum', labelKey: 'fieldSection' },
        { name: 'value', kind: 'select', list: 'sampleFiles', labelKey: 'fieldSon', optional: true },
      ] },
    { action: 'piece-load-demo', labelKey: 'menuChargerDemo', fields: [] },
    { action: 'piece-load', labelKey: 'menuChargerMorceau', fields: [{ name: 'value', kind: 'select', list: 'pieceFiles' }] },
    { action: 'piece-save', labelKey: 'menuSauvegarderMorceau', fields: [] },
    { action: 'piece-save-as', labelKey: 'menuSauvegarderMorceauSous', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
  ] },
  { category: 'Composition', categoryLabelKey: 'catComposition', items: [
    { action: 'composition-describe', labelKey: 'menuDecrireMorceau', fields: [
        { name: 'title', kind: 'text', placeholderKey: 'placeholderTitreCourt', labelKey: 'fieldTitre', optional: true },
        { name: 'value', kind: 'textarea', labelKey: 'fieldDescription' },
        { name: 'instructions', kind: 'text', placeholderKey: 'placeholderIndicationsCourt', labelKey: 'fieldIndications', optional: true },
      ] },
    { action: 'composition-compose', labelKey: 'menuComposerDepuisDescription', fields: [] },
    { action: 'composition-load', labelKey: 'menuChargerDescription', fields: [{ name: 'value', kind: 'select', list: 'compositionFiles' }] },
    { action: 'composition-save-as', labelKey: 'menuSauvegarderDescriptionSous', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'composition-save', labelKey: 'menuSauvegarderDescription', fields: [] },
    { action: 'text-framing-set', labelKey: 'menuModifierPhraseDeCadrage', fields: [{ name: 'value', kind: 'textarea' }] },
    { action: 'text-framing-save', labelKey: 'menuSauvegarderPhraseDeCadrage', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
    { action: 'text-framing-load', labelKey: 'menuChargerPhraseDeCadrage', fields: [{ name: 'value', kind: 'select', list: 'textFramingFiles' }] },
    { action: 'text-framing-reset', labelKey: 'menuRevenirPhraseDeCadrageParDefaut', fields: [] },
    { action: 'text-prompt-export', labelKey: 'menuExporterPromptComposition', fields: [{ name: 'value', kind: 'text', placeholderKey: 'placeholderNom' }] },
  ] },
  { category: 'Jam Session', categoryLabelKey: 'catJamSession', items: [
    { action: 'jam-start', labelKey: 'menuDemarrerJamSession', fields: [
        { name: 'pseudo', kind: 'text', placeholderKey: 'placeholderPseudoCourt', labelKey: 'fieldPseudo', optional: true },
        { name: 'value', kind: 'text', placeholderKey: 'placeholderPort7777', labelKey: 'fieldPort', optional: true },
      ] },
    { action: 'jam-stop', labelKey: 'menuArreterJamSession', fields: [] },
    { action: 'jam-join', labelKey: 'menuRejoindreJamSession', fields: [
        { name: 'pseudo', kind: 'text', placeholderKey: 'placeholderPseudoCourt', labelKey: 'fieldPseudo', optional: true },
        { name: 'host', kind: 'text', placeholderKey: 'placeholderHoteCourt', labelKey: 'fieldHote' },
        { name: 'port', kind: 'text', placeholderKey: 'placeholderPort7777', labelKey: 'fieldPort', optional: true },
      ] },
    { action: 'jam-discover', labelKey: 'menuRechercherJamSessions', fields: [] },
    { action: 'jam-connect-discovered', labelKey: 'menuRejoindreSessionTrouvee', fields: [{ name: 'value', kind: 'select', list: 'discoveredJamSessions', useIndex: true }] },
    { action: 'jam-leave', labelKey: 'menuQuitterJamSession', fields: [] },
  ] },
];

function escapeHTML(text) {
  return String(text).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

function menuFieldControlHTML(action, field) {
  const id = 'menu-' + action + '-' + field.name;
  if (field.kind === 'text') {
    return `<input type="text" id="${id}" placeholder="${escapeHTML(field.placeholderKey ? t(field.placeholderKey) : '')}">`;
  }
  if (field.kind === 'textarea') {
    return `<textarea id="${id}" rows="3"></textarea>`;
  }
  // 'select' (list-driven or fixed `options`) and 'select-track' (always list-driven, from
  // `menuLists.tracks`) — `data-list`/`data-use-index`/`data-optional` are read back by
  // `refreshMenuLists` so it can repaint just this element's `<option>`s in place without
  // disturbing any other field's in-progress input.
  const listName = field.kind === 'select-track' ? 'tracks' : (field.list || '');
  // `o.labelKey` for translatable fixed options (e.g. Activer/Arreter); plain `o.label` for
  // options whose text is itself musical/dynamic data, not UI copy (e.g. note names).
  const staticOptionsHTML = field.options ? field.options.map(o => `<option value="${escapeHTML(o.value)}">${escapeHTML(o.labelKey ? t(o.labelKey) : o.label)}</option>`).join('') : '';
  const placeholderOptionHTML = field.optional ? `<option value="">${escapeHTML(t('optionAucun'))}</option>` : '';
  return `<select id="${id}" data-list="${listName}" data-use-index="${field.useIndex ? '1' : ''}" data-optional="${field.optional ? '1' : ''}">` +
    placeholderOptionHTML + staticOptionsHTML + '</select>';
}

function menuItemRowHTML(item) {
  const fieldsHTML = item.fields.map(field => {
    const labelHTML = field.labelKey ? `<label for="menu-${item.action}-${field.name}">${escapeHTML(t(field.labelKey))}</label>` : '';
    return labelHTML + menuFieldControlHTML(item.action, field);
  }).join('');
  return `<div class="menu-row"><label>${escapeHTML(t(item.labelKey))}</label>${fieldsHTML}` +
    `<button onclick="submitMenuItem('${item.action}')">${escapeHTML(t('buttonOK'))}</button></div>`;
}

// Which category's panel is currently shown — a sub-tab bar under the main Run/Scene/
// Commandes/Infos one, one sub-tab per `MENU_ACTIONS` category. Every panel is built once
// (inside `buildMenuTab`, alongside everything else on this tab) and just hidden/shown via
// `display`, never removed from the DOM — so switching sub-tabs can't lose any in-progress
// input in a panel that's momentarily not visible, same principle as `menuBuilt` itself.
let activeMenuCategory = null;

function renderMenuSubTabBar() {
  return '<div class="tab-bar menu-subtab-bar">' + MENU_ACTIONS.map(category =>
    `<a class="tab${category.category === activeMenuCategory ? ' active' : ''}" onclick="setMenuCategory('${category.category}')">${escapeHTML(t(category.categoryLabelKey))}</a>`
  ).join('') + '</div>';
}

function setMenuCategory(category) {
  activeMenuCategory = category;
  // The sub-tab bar itself holds no user input (just links), so a full re-render of it alone
  // is safe — unlike the category panels below it, which are only ever shown/hidden.
  document.querySelector('#menu-container .menu-subtab-bar').outerHTML = renderMenuSubTabBar();
  document.querySelectorAll('#menu-container .menu-category-panel').forEach(panel => {
    panel.style.display = panel.dataset.category === activeMenuCategory ? '' : 'none';
  });
}

function buildMenuTab() {
  activeMenuCategory = MENU_ACTIONS[0].category;
  const panelsHTML = MENU_ACTIONS.map(category =>
    `<div class="menu-category-panel" data-category="${escapeHTML(category.category)}">` +
    category.items.map(menuItemRowHTML).join('') + '</div>'
  ).join('');
  document.getElementById('menu-container').innerHTML =
    '<div id="menu-result"></div>' + renderMenuSubTabBar() + panelsHTML;
  document.querySelectorAll('#menu-container .menu-category-panel').forEach(panel => {
    panel.style.display = panel.dataset.category === activeMenuCategory ? '' : 'none';
  });
  refreshMenuLists();
  startMenuListsPolling();
}

// The dropdown lists (pieces/samples/scenes/tracks/...) can change from something other than
// this tab's own actions — the terminal, another browser tab, another jam-session participant
// saving a scene, etc. — so a one-shot refresh right after this tab's own actions isn't
// enough. Polled independently from (and much slower than) the `/state` ~250ms tick used by
// every other tab, since `refreshMenuLists` only ever repaints `<select>` options in place
// (never touches text/textarea input, see its own doc comment) — safe to run in the
// background for as long as this tab stays open. Stopped when leaving the tab (`refresh()`'s
// non-menu branch) purely to avoid pointless polling while nobody's looking at it.
let menuListsPollTimer = null;
function startMenuListsPolling() {
  stopMenuListsPolling();
  menuListsPollTimer = setInterval(refreshMenuLists, 2000);
}
function stopMenuListsPolling() {
  if (menuListsPollTimer) { clearInterval(menuListsPollTimer); menuListsPollTimer = null; }
}

function menuItemByAction(action) {
  for (const category of MENU_ACTIONS) {
    const found = category.items.find(item => item.action === action);
    if (found) return found;
  }
  return null;
}

function submitMenuItem(action) {
  const item = menuItemByAction(action);
  if (!item) return;
  const params = {};
  for (const field of item.fields) {
    const el = document.getElementById('menu-' + action + '-' + field.name);
    if (!el) continue;
    if (!el.value && field.optional) continue;
    // `useIndex` fields (only `jam-connect-discovered` today, never `optional`, so
    // `selectedIndex` needs no placeholder-offset correction) send the option's position
    // rather than its label — `lastDiscoveredServers` has no other stable per-item key.
    params[field.name] = (field.kind === 'select' && el.dataset.useIndex === '1') ? String(el.selectedIndex) : el.value;
  }
  runMenuAction(action, params);
}

function runMenuAction(action, params) {
  const qs = Object.keys(params).map(key => encodeURIComponent(key) + '=' + encodeURIComponent(params[key])).join('&');
  fetch('/menu-action?action=' + encodeURIComponent(action) + (qs ? '&' + qs : ''), { cache: 'no-store' })
    .then(response => response.json())
    .then(showMenuResult)
    .catch(() => showMenuResult({ ok: false, message: t('fallbackConnexionPerdue') }))
    .then(refreshMenuLists);
}

function showMenuResult(result) {
  const el = document.getElementById('menu-result');
  if (!el) return;
  el.textContent = result.message + (result.items && result.items.length ? ' (' + result.items.join(', ') + ')' : '');
  el.className = result.ok ? 'ok' : 'error';
  return result;
}

// Repaints just the `<option>`s of every list-driven `<select>` currently on the page, keyed
// by its own `data-list` attribute — deliberately never touches text inputs/textareas, or any
// select's currently-typed... nothing to preserve there beyond the selection itself, which
// this restores by value (see `previousValue` below) whenever the freshly-listed options still
// contain it. Called after every action (a save/list-folder action can change what these lists
// contain) and once when the tab is first built.
async function refreshMenuLists() {
  try {
    const response = await fetch('/menu-lists', { cache: 'no-store' });
    menuLists = await response.json();
  } catch (error) { return; }
  // The Menu tab never touches `/state` (see `buildMenuTab`'s own doc comment) — `/menu-lists`
  // (polled every 2s regardless of which tab is showing, see `startMenuListsPolling`) is the
  // only channel it has to notice a language change made elsewhere. Mirrors `refresh()`'s own
  // `state.language` handling below.
  if (menuLists.language && menuLists.language !== currentLanguage) {
    currentLanguage = menuLists.language;
    document.documentElement.lang = currentLanguage;
    menuBuilt = false;
  }
  document.querySelectorAll('#menu-container select[data-list]').forEach(sel => {
    const listName = sel.dataset.list;
    if (!listName || !menuLists) return;
    const items = menuLists[listName] || [];
    const useIndex = sel.dataset.useIndex === '1';
    const previousValue = sel.value;
    const placeholderOptionHTML = sel.dataset.optional === '1' ? `<option value="">${escapeHTML(t('optionAucun'))}</option>` : '';
    const optionsHTML = items.map((item, index) => {
      let value, label;
      if (useIndex) { value = String(index); label = item; }
      else if (typeof item === 'string') { value = item; label = item; }
      else if (listName === 'tracks' || listName === 'unassignedTracks') { value = item.id; label = item.label; }
      else if (listName === 'sceneRoles') { value = item.id; label = item.name + (item.attachedLabel ? ` (${item.attachedLabel})` : ` (${t('optionLibre')})`); }
      else { value = item.id; label = item.name; } // scales: {id, name}
      return `<option value="${escapeHTML(value)}">${escapeHTML(label)}</option>`;
    }).join('');
    sel.innerHTML = placeholderOptionHTML + optionsHTML;
    if (Array.from(sel.options).some(o => o.value === previousValue)) sel.value = previousValue;
  });
}

let activeTab = 'run'; // 'run' | 'scene' | 'observer' | 'infos' | 'menu'
// Updated every poll in `refresh()` — read by the guide-navigation keydown handler below, so
// arrow keys only drive the guide while one is actually running (see that handler's own comment).
let guideIsActive = false;
function renderTabBar() {
  return '<div class="tab-bar">' +
    `<a class="tab${activeTab === 'run' ? ' active' : ''}" onclick="setTab('run')">Run</a>` +
    `<a class="tab${activeTab === 'scene' ? ' active' : ''}" onclick="setTab('scene')">${t('tabScene')}</a>` +
    `<a class="tab${activeTab === 'observer' ? ' active' : ''}" onclick="setTab('observer')">${t('tabObserver')}</a>` +
    `<a class="tab${activeTab === 'menu' ? ' active' : ''}" onclick="setTab('menu')">${t('tabCommandes')}</a>` +
    `<a class="tab${activeTab === 'infos' ? ' active' : ''}" onclick="setTab('infos')">${t('tabInfos')}</a>` +
    '</div>';
}
function setTab(tab) {
  // Re-clicking the tab that's already active must be a no-op — without this guard, clicking
  // "Commandes" while already on it would force `menuBuilt = false` below and rebuild the
  // whole tab from scratch on the next `refresh()`, wiping any in-progress input for no reason.
  if (tab === activeTab) return;
  if (activeTab === 'menu') stopMenuListsPolling(); // leaving the tab — no point polling unseen
  activeTab = tab;
  menuBuilt = false;
  refresh();
}

// Mirrors `state.noteColors` (see `WebConsoleState.noteColors`'s doc comment) onto the CSS
// custom properties `.pkey.*` rules above read from — cheap and idempotent to call every
// poll even when nothing changed, so no separate "did this change" tracking is needed.
function applyNoteColors(noteColors) {
  if (!noteColors) return;
  const style = document.documentElement.style;
  style.setProperty('--mode-root-color', noteColors.modeRootHex);
  style.setProperty('--mode-tone-color', noteColors.modeOtherHex);
  style.setProperty('--chord-root-color', noteColors.chordRootHex);
  style.setProperty('--chord-tone-color', noteColors.chordToneHex);
  style.setProperty('--held-outside-color', noteColors.heldOutsideChordHex);
  style.setProperty('--held-no-chord-color', noteColors.heldNoChordHex);
}

async function refresh() {
  // The "Menu" tab never touches `/state` at all (see `buildMenuTab`'s own doc comment) — its
  // DOM is built once per visit and then left alone so in-progress form input survives this
  // function's own ~250ms tick, unlike every other tab, which is fine being wholesale replaced
  // since none of them hold any live user input.
  if (activeTab === 'menu') {
    if (!menuBuilt) {
      document.getElementById('app').innerHTML = renderTabBar() + '<div id="menu-container"></div>';
      buildMenuTab();
      menuBuilt = true;
    }
    return;
  }
  let state;
  try {
    const response = await fetch('/state', { cache: 'no-store' });
    state = await response.json();
  } catch (error) {
    document.getElementById('app').innerHTML = `<p class="empty">${t('fallbackConnexionPerdueDetail')}</p>`;
    return;
  }
  if (state.palette && state.palette.length === 12) PITCH_CLASS_COLORS = state.palette;
  if (state.paletteTextColors && state.paletteTextColors.length === 12) PITCH_CLASS_TEXT_COLORS = state.paletteTextColors;
  applyNoteColors(state.noteColors);
  guideIsActive = !!(state.guide && state.guide.isActive);
  if (state.language && state.language !== currentLanguage) {
    currentLanguage = state.language;
    document.documentElement.lang = currentLanguage;
    document.title = t('titleConsoleWeb');
    menuBuilt = false; // forces the Menu tab to rebuild with the new language next time it's shown
  }
  const tabHTML = activeTab === 'run' ? renderRunTab(state)
    : activeTab === 'scene' ? renderSceneTree(state.scene)
    : activeTab === 'observer' ? renderObserverTab(state)
    : renderInfosTab();
  document.getElementById('app').innerHTML = renderTabBar() + tabHTML;
}

// Guide navigation from the keyboard — up/down move between modes (steps), left/right between
// chords within the current step's progression, mirroring the terminal's own arrow-key mapping
// on its `.guide` screen (and the virtual keyboard page's own `Tab`/`Shift+Tab` step navigation
// — see `VirtualKeyboardAssets.swift`'s own `sendGuideAdvance`). Global session state, not
// scoped to any one client: any browser tab's arrow keys move the SAME guide everyone sees.
// `/guide-advance-step`/`/guide-advance-chord` are this file's own new endpoints (the virtual
// keyboard page's existing `/guide-advance` only moves the step, and additionally requires a
// `?client=` identity query this page has no equivalent of).
function sendGuideAdvanceStep(delta) {
  fetch('/guide-advance-step?delta=' + delta).catch(() => {});
}
function sendGuideAdvanceChord(delta) {
  fetch('/guide-advance-chord?delta=' + delta).catch(() => {});
}
// Only while a guide is actually running (`guideIsActive`, refreshed every poll) AND the
// currently active tab actually shows the guide panel (Run/Observer — Scene/Commandes/Infos
// don't render it at all, so hijacking arrows there would be surprising); and never while focus
// is in a form control (the Observer tab's own track picklist, the Menu tab's text inputs), so
// typing/selecting there keeps working normally. `downActionCodes` debounces a held key's
// auto-repeat into a single action per physical press, same technique as the virtual keyboard
// page's own octave-shift/Tab handling.
const downActionCodes = new Set();
const GUIDE_STEP_DELTA = { ArrowUp: -1, ArrowDown: 1 };
const GUIDE_CHORD_DELTA = { ArrowLeft: -1, ArrowRight: 1 };
document.addEventListener('keydown', e => {
  if (!guideIsActive || (activeTab !== 'run' && activeTab !== 'observer')) return;
  const tag = document.activeElement ? document.activeElement.tagName : '';
  if (tag === 'INPUT' || tag === 'SELECT' || tag === 'TEXTAREA') return;
  if (downActionCodes.has(e.code)) return;
  if (GUIDE_STEP_DELTA[e.code] !== undefined) {
    downActionCodes.add(e.code);
    e.preventDefault();
    sendGuideAdvanceStep(GUIDE_STEP_DELTA[e.code]);
  } else if (GUIDE_CHORD_DELTA[e.code] !== undefined) {
    downActionCodes.add(e.code);
    e.preventDefault();
    sendGuideAdvanceChord(GUIDE_CHORD_DELTA[e.code]);
  }
});
document.addEventListener('keyup', e => { downActionCodes.delete(e.code); });

refresh();
setInterval(refresh, 250);
"""
