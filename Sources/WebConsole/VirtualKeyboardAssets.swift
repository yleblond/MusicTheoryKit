import Localization

/// The two static assets served by the virtual-keyboard HTTP server (`GET /` and `GET
/// /app.js`) — see `ImprovSession.startVirtualKeyboard`. Deliberately a separate page/module
/// concern from `StaticAssets.swift`'s read-only web console: this one is interactive (typed
/// keys, mouse clicks, touches all play notes — including clicking/tapping a circle-of-fifths
/// wheel cell, always shown now (not just while a guide is active), to play that chord's
/// triad), so keeping it in its own file/route means the always-on console page never has to
/// reason about input handling at all — its own `renderWheel` has no click handling,
/// deliberately.
///
/// **Layout**: two columns (`.layout-columns`, same responsive pattern as the console's own —
/// wraps to one column on a narrow screen) — left is identity/settings + the guide's own
/// info (title/steps, while active) + the wheel; right is the detected-chord line, the
/// octave overview + arrows, and the actual playable piano, so "what you're about to play"
/// and "what you're actually playing" read side by side.
///
/// **Computer keyboard**: two overlaid row-pairs (`KEY_MAP`) cover ~2.5 octaves at once
/// (bass: number row + `` ` `` + `qwertyuiop`; treble, continuing right above it: `S D G H J`
/// + the bottom letter row), mapped by physical position (`KeyboardEvent.code`) rather than by
/// character — stays correct on a QWERTZ/AZERTY/etc. keyboard, not just the US layout the
/// letters are named after. `shiftOctave()`/`applyOctaveIndex()` (the ◂/▸ arrows flanking the
/// mini-piano overview, `ArrowLeft`/`ArrowRight`, or `<`/`-` next to Shift on an ISO keyboard)
/// slide this whole window by a full octave at a time across `OCTAVE_STOPS` (C0..C6),
/// rebuilding the on-screen piano to match every time — see
/// `ensureKeyboardBuilt`/`recomputeKeyRange`. Clicking/tapping anywhere on the mini-piano
/// overview jumps straight to whichever octave stop's window best covers that spot
/// (`jumpOctaveFromMiniPianoClick`/`jumpToNearestOctaveFor`), still snapping to one of the
/// same fixed stops rather than an arbitrary pixel-perfect note.
///
/// **Guide navigation**: while a guide is running, `Tab`/`Shift+Tab` advance/go back one
/// step (`GET /guide-advance?delta=`) — a GLOBAL action (the same guide everyone sees, not
/// per-client), mirroring the terminal's own left/right arrows on its `.guide` screen.
///
/// **Multi-client**: every route below `/`/`/app.js` requires `?client=<uuid>` — a random id
/// this page generates once and keeps in `localStorage`, so the SAME browser/device keeps
/// driving the SAME `TrackID.webKeyboard(clientID:)` track across reloads, and several
/// browsers/tablets connected to the same server each get their own independent track (own
/// held notes, own chord recognition) rather than fighting over one shared track. `?name=
/// <alias>` (also sent on every request) is this connection's chosen display name — asked
/// once via `prompt()` on first load, also kept in `localStorage`; see
/// `ImprovSession.ensureWebKeyboardTrack`.
///
/// **JSON contract with `AppCore.ImprovSession`**: `GET /state?client=...` returns a
/// `VirtualKeyboardStateResponse` (`AppCore/WebConsoleState.swift`) — `track` scoped to just
/// this one client's own track (same shape as one entry of the web console's `tracks` array,
/// see `StaticAssets.swift`'s own contract comment), `guide` only while a guide is actually
/// running (see `ImprovSession.handleVirtualKeyboardRequest`'s doc comment) — the degree-line
/// (degree badges) switches to the guide's own mode while active, but held/chord/root coloring
/// stays this client's own personal feedback either way:
/// ```json
/// {"track": {"id": "clavier-web:<uuid>", "label": "Alice", "owner": null,
///            "heldPitches": [60, 64, 67], "chordRoot": 0, "chordTones": [0, 4, 7],
///            "modeTones": [0, 2, 4, 5, 7, 9, 11], "chordLabel": "Cmaj",
///            "modesLabel": "C ionian", "microphoneLevel": null} | null,
///  "guide": {"isActive": true, "steps": [{"label": "A Lydian", "isCurrent": true}],
///            "currentStepIndex": 0, "currentModeTones": [9, 11, 1, 3, 4, 6, 8],
///            "heldPitches": [...]},
///  "wheel": { ...same shape as the web console's own "wheel" field... },
///  "palette": ["#DB2A52", "#0AAD9A", ..., "#ABD144"],
///  "paletteTextColors": ["#ffffff", "#ffffff", ..., "#111111"]}
/// ```
/// `guide` (a `nil` `Optional` under Swift's synthesized `Encodable`) is OMITTED from the
/// JSON entirely while no guide is running, not present as an explicit `null` — `app.js`
/// only ever checks `state.guide && state.guide.isActive`, which is `undefined`-safe either
/// way. `wheel`/`palette`/`paletteTextColors` are always present, unlike `guide` — `wheel`'s
/// mode-relative parts (diatonic boundary, roman numerals, active mode name) are still only
/// MEANINGFUL while a guide is running, but that's a client-side rendering choice
/// (`renderWheel`'s `showModeContext` argument), not a server-side omission, since the wheel
/// itself (which chord sits where, its own color) stays clickable either way.
/// `palette`/`paletteTextColors` are the 12 hex colors (and matching legible text colors, see
/// `ColorPalette.textColors`'s doc comment) of whichever `ColorPalette` is currently active
/// (`ImprovSession.activeColorPalette`), index 0 = C ... 11 = B, sent on every poll so
/// switching palettes from the menu updates this page within one refresh cycle — see
/// `app.js`'s own `PITCH_CLASS_COLORS`/`PITCH_CLASS_TEXT_COLORS`.
///
/// `GET /note-on?pitch=<midi>&client=...&name=...` / `GET /note-off?pitch=<midi>&client=
/// ...&name=...` / `GET /release-all?client=...&name=...` / `GET /guide-advance?delta=
/// <±1>&client=...&name=...` are the only ways this page *changes* anything — plain `GET`s
/// with everything in the query string (not a POST body): `WebConsole`'s hand-rolled HTTP
/// server only ever parses a request line, never a body (see `HTTPWireFormat`'s doc comment),
/// and a one-off query string is simpler than teaching it to. `/guide-advance` ignores
/// `client`/`name` (still required, like every other route here) — it moves the session's one
/// shared guide, not anything scoped to this client's own track.
public let virtualKeyboardIndexHTML = """
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>JamShack — Clavier virtuel</title>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
  /* Defaults match NoteColorSettingsFile's own — overwritten from `state.noteColors` by
     `applyNoteColors()` every poll, same as `StaticAssets.swift`'s own copy of this block. */
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
  .field { color: #888; }
  .field b { color: #ddd; }
  .empty { color: #666; font-style: italic; }
  .hint { color: #666; font-size: 0.85rem; margin-top: 0.3rem; }
  .identity { color: #666; font-size: 0.85rem; }
  .identity a { color: #6cf; cursor: pointer; text-decoration: underline; }
  /* `display: inline-flex` (not `flex`) so `#layout-columns` shrink-wraps to the two columns'
     own natural content width — same "inline-flex vs flex" lesson as `.keyboard-align-wrapper`
     above, learned the SAME way (measured widths not matching visual expectations) — a plain
     `flex` row fills its parent's available width, and with both columns sharing
     `flex-grow: 1`, any leftover space between that available width and the columns' actual
     content got split 50/50 REGARDLESS of which column's content needed it — real bug caught
     this way (not by inspection) while building `applyResponsiveScale()` below: forcing
     `#layout-columns` to a specific pixel width to compute a transform scale from made this
     exact mismatch obvious (`getBoundingClientRect()` showed `#keyboard-align-wrapper` wider
     than its own parent `.layout-col-right`, silently overflowing it uncontained, instead of
     the piano fitting inside a correctly-sized column). `flex-wrap: nowrap` — no more
     CSS-driven wrapping to a single narrow column; `applyResponsiveScale()` is now the only
     responsive mechanism (a phone-sized single-column redesign is a separate, later pass, per
     the user's own scoping). */
  .layout-columns { display: inline-flex; flex-wrap: nowrap; gap: 2rem; align-items: flex-start; }
  .layout-col-left, .layout-col-right { flex: 0 0 auto; }
  /* `applyResponsiveScale()` sets `transform: scale(...)` on `#layout-columns` (now sized to
     its own natural content, see above) and an explicit `height` here to match — a transform
     doesn't affect normal layout flow on its own, so without this a shrunk layout would leave
     blank space below it (or a grown one would overflow into whatever follows). */
  #responsive-scale-clip { overflow: hidden; }
  .tab-bar { display: flex; gap: 1.2rem; border-bottom: 1px solid #333; margin-bottom: 1rem; }
  .tab { color: #888; cursor: pointer; padding: 0.3rem 0; user-select: none; }
  .tab.active { color: #fff; border-bottom: 2px solid #6cf; }
  /* `align-items: stretch` makes every direct child — octave overview, piano, staff,
     chord/mode panel — share the SAME width, but only once the container's OWN width is the
     widest child's width in the first place: a `display: flex` (block-level) container fills
     its PARENT's available width instead, which can be narrower than the piano — real bug
     caught this way, not by inspection: the piano visibly got clipped (the column was 660px,
     the piano itself 792px) once this was `flex`, because `align-items: stretch` shrank
     `#keyboard-container` down to that narrower 660px instead of matching the 792px piano.
     `inline-flex` shrink-wraps to content first (like `inline-block`), THEN `align-items:
     stretch` stretches every other child out to that content-driven width — restores the
     piano's own full width (it can still overflow onto a narrow viewport/scroll via
     `.keyboard-scroll`'s own `overflow-x: auto`, same as before this whole feature existed).
     `.octave-controls` gets its own `justify-content: flex-start` below so the whole row
     (labels + arrows + mini-piano) stays flush left, lined up with the piano/staff/panel below
     it, rather than centering — a target layout mockup made this explicit: every element
     shares the SAME left AND right edge. The row's own total width (labels + arrows + SVG) is
     what's matched to the piano's width (see `renderMiniPianoOverview`'s own comment on
     `octaveControlsOverheadWidth`), not the SVG alone — the mockup shows the mini-piano's own
     keys inset from both edges, with "F5 ◂"/"▸ B7" sitting flush at the shared edges instead. */
  .keyboard-align-wrapper { display: inline-flex; flex-direction: column; align-items: stretch; }
  .octave-controls {
    color: #888; font-size: 0.85rem; margin: 0.4rem 0; display: flex; align-items: center;
    justify-content: flex-start; gap: 0.5rem;
  }
  .octave-controls b { color: #ddd; }
  .octave-arrow {
    cursor: pointer; user-select: none; font-size: 1.3rem; line-height: 1; color: #ddd;
    padding: 0 0.2rem;
    /* `◂`/`▸`'s own ink sits noticeably above center within its glyph box (confirmed by
       rendering the character alone against a mid-height guide line) — `align-items: center`
       on `.octave-controls` correctly centers the BOX against the mini-piano next to it, but
       the visible triangle still reads as sitting too high. Nudged down to compensate. */
    position: relative; top: 0.12em;
  }
  .octave-arrow:hover { color: #fff; }
  .mini-piano { display: block; flex: 0 0 auto; cursor: pointer; }
  .mini-key-white { fill: #f5f5f5; stroke: #555; stroke-width: 0.5; }
  .mini-key-black { fill: #1a1a1a; }
  /* Outline only ("entourer"), no fill — sits on top of the mini keyboard's own keys to mark
     which slice of the full range [MIN_MIDI, MAX_MIDI] is currently played below. */
  .mini-piano-active { fill: none; stroke: #e91e63; stroke-width: 1.5; }
  /* Lets the real piano scroll horizontally within its own column instead of overflowing the
     whole page when it's wider than the column (common once the layout is 2 columns instead
     of the full page width) — same convention as the console's own `.keyboard-scroll`.
     `justify-content: flex-start` (not `center`) keeps the piano flush left, lined up with the
     mini-piano overview/staff/chord panel above and below it — a target layout mockup made
     this explicit, every element sharing one left edge rather than being centered relative to
     each other. */
  .keyboard-scroll { display: flex; justify-content: flex-start; overflow-x: auto; max-width: 100%; }
  .wheel { margin: 0.5rem 0 1rem; display: block; width: 100%; max-width: 624px; height: auto; } /* 520px + 20% */
  .wheel-disk { fill: #fff; }
  .wheel-grid-line { stroke: #000; stroke-width: 1; }
  .wheel-cell-shape { stroke: #333; stroke-width: 1; cursor: pointer; }
  .wheel-cell-shape.pressed { filter: brightness(0.7); }
  .wheel-diatonic-boundary { fill: none; stroke: #1a3a6b; stroke-width: 5; stroke-linejoin: round; }
  /* Ring around whichever cell matches this track's OWN currently-detected chord (see
     `detectedChordFrom`/`renderWheel`'s `detectedChord` argument) — same magenta as `.pkey.root`
     elsewhere in the app, for "this is the fundamental/the chord you're playing" consistency. */
  .wheel-cell-detected { fill: none; stroke: #e91e63; stroke-width: 3; pointer-events: none; }
  /* Bold outline around every cell whose (root, quality) appears in the active guide step's
     attached chord progression (see `WebConsoleGuideState.currentChordProgression`) — a
     distinct color from `.wheel-cell-detected` (this track's own live chord) so both can be
     visible on the same cell at once without being confused for one another. */
  .wheel-cell-progression { fill: none; stroke: #ffb300; stroke-width: 3; pointer-events: none; }
  /* No `fill` here (unlike most rules) — the palette's per-note text color is set inline,
     since it varies by pitch class (`PITCH_CLASS_TEXT_COLORS[cell.pitchClass]`), not fixed. */
  .wheel-cell-symbol { font-size: 8px; font-weight: bold; text-anchor: middle; pointer-events: none; }
  .wheel-cell-degree { font-size: 6.5px; font-family: Georgia, 'Times New Roman', serif; text-anchor: middle; pointer-events: none; opacity: 0.75; }
  .wheel-mode-name { fill: #555; font-size: 11px; text-anchor: middle; dominant-baseline: middle; }
  .wheel-mode-name.active { fill: #b36b00; font-weight: bold; }
  .keyboard { position: relative; margin: 2.5rem 0 0.8rem; user-select: none; -webkit-user-select: none; touch-action: none; }
  .pkey { position: absolute; top: 0; box-sizing: border-box; border: 1px solid #333; border-radius: 0 0 4px 4px; cursor: pointer; }
  .pkey.white { background: #f5f5f5; z-index: 1; }
  .pkey.black { background: #1a1a1a; z-index: 2; box-shadow: 0 2px 3px rgba(0,0,0,0.5); }
  .pkey.root { background: var(--chord-root-color) !important; }
  .pkey.tone { background: var(--chord-tone-color) !important; }
  .pkey.outside { background: var(--held-outside-color) !important; }
  .pkey.held { background: var(--held-no-chord-color) !important; }
  .pkey.pressed { filter: brightness(0.7); }
  /* Guide panel's own static mode/chord reference keyboards only (see
     `guideReferenceKeyboardHTML`) — same meaning/colors as `StaticAssets.swift`'s. */
  .pkey.mode-root { background: var(--mode-root-color) !important; }
  .pkey.mode-tone { background: var(--mode-tone-color) !important; }
  .guide-keyboard-small .pkey { cursor: default; }
  /* Guide panel's guitar-tab diagram — same rules/colors as StaticAssets.swift's own copy. */
  .guitar-diagram { display: block; margin: 0.3rem 0 0.6rem; }
  .guitar-diagram-label { font-size: 1.5rem; font-weight: bold; color: #ddd; margin: 0 0 -8px; line-height: 1.1; text-align: center; }
  .guitar-string { stroke: #666; stroke-width: 1.5; }
  .guitar-fret { stroke: #666; stroke-width: 1.5; }
  .guitar-fret-label { font-size: 11px; fill: #888; }
  .guitar-barre { stroke: var(--chord-root-color); stroke-width: 9; stroke-linecap: round; }
  .guitar-dot { fill: var(--chord-tone-color); }
  .guitar-finger { font-size: 10px; fill: #111; text-anchor: middle; }
  .guitar-muted { font-size: 13px; fill: #e57373; text-anchor: middle; }
  /* Guide panel's own inner layout — ported from `StaticAssets.swift`'s own copy (see there for
     the full reasoning): notation (left) — the two stacked keyboards (middle) — guitar tab
     (right), all 3 columns `flex: 0 0 auto` (natural content width, no grow) sharing one `gap`
     so both sides read as equal, and `align-items: stretch` so all 3 share the row's tallest
     height (the keyboards column). A dedicated `.guide-hint` (not the page's own `.hint`, whose
     look is already spoken for by `vkHint`) for the single consolidated arrow-key hint line. */
  .guide-hint { color: #666; font-style: italic; }
  .guide-layout { display: flex; flex-wrap: wrap; gap: 1rem; align-items: stretch; margin-top: 0.4rem; }
  .guide-col-notation, .guide-col-keyboards, .guide-col-tab { flex: 0 0 auto; display: flex; flex-direction: column; }
  .guide-col-keyboards { padding-bottom: 8px; }
  .guide-col-fill { flex: 1 1 auto; display: flex; flex-direction: column; }
  .guide-col-tab .guide-col-fill { justify-content: flex-end; }
  .guide-col-notation .guide-col-fill .staff-scroll { flex: 1 1 auto; display: flex; overflow: visible; }
  .guide-col-notation .guide-col-fill .staff-scroll svg.staff { flex: 1 1 auto; height: auto; width: auto; }
  .staff-scroll { overflow-x: auto; max-width: 100%; }
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
    position: absolute; top: -24px; left: 50%; transform: translateX(-50%);
    width: 20px; height: 20px; border-radius: 50%;
    font-size: 11px; line-height: 20px; text-align: center; font-weight: bold;
    pointer-events: none;
  }
  /* Same `top` on every key regardless of white/black (both start at the key's own top edge)
     — that's what makes these line up into one straight horizontal row across the whole
     keyboard instead of following each key's own height. */
  .key-letter {
    position: absolute; top: 6px; left: 50%; transform: translateX(-50%);
    font-size: 11px; font-weight: bold; pointer-events: none; z-index: 3;
  }
  .pkey.white .key-letter { color: #111; }
  .pkey.black .key-letter { color: #fff; }
  .octave-label {
    position: absolute; bottom: 6px; left: 50%; transform: translateX(-50%);
    font-size: 10px; color: #0097e6; font-weight: bold; pointer-events: none;
  }
</style>
</head>
<body>
<div id="app"></div>
<script src="/app.js"></script>
</body>
</html>
"""

public let virtualKeyboardAppJS = """
\(L10n.jsTableLiteral)
// See `StaticAssets.swift`'s own identical `currentLanguage`/`t()` pair for the full reasoning
// — mutable, overwritten every `refresh()` tick from `state.language`.
let currentLanguage = 'fr';
function t(key, ...args) {
  const entry = L10N[key];
  let template = (entry && entry[currentLanguage]) || (entry && entry.fr) || key;
  args.forEach(arg => { template = template.replace('%d', arg).replace('%@', arg); });
  return template;
}

// Two overlaid row-pairs — the number row + top letter row form one "black keys above,
// white keys below" register for the low notes (bass), the home row + bottom letter row
// form the next one up (treble), continuing right where the bass register's last white key
// left off. Same shape as the classic computer-keyboard-as-piano layout many trackers/DAWs
// use, just spelled out explicitly here. Keyed by `KeyboardEvent.code` (physical key
// position), never by character/`.key` — `.code` names a key by where it SITS on a
// reference US/ANSI layout regardless of what the visitor's OS keyboard layout actually
// produces there, so this mapping stays positionally correct on a QWERTZ keyboard (which
// swaps the Y/Z labels but not their physical slots), AZERTY, etc. — only the on-screen
// LABEL (`codeLabels` below) needs to know what the visitor's layout actually prints.
// `Backquote` (the `` ` ``/`~` key, top-left corner) extends the white row one note further
// left than `KeyQ` alone would reach — starting the bass register on a G read as ambiguous at
// a glance ("on peut penser que ca commence sur un Do"), so it now starts two semitones lower,
// on F, matching a real piano's own F-to-B landmark rather than an arbitrary cutoff.
// `Backquote` exists on every keyboard (ANSI and ISO alike), unlike `IntlBackslash` (used
// for the octave-shift shortcut elsewhere) — a safe choice for a mapping that needs to work
// everywhere.
const BASS_WHITE_CODES = ['Backquote', 'KeyQ', 'KeyW', 'KeyE', 'KeyR', 'KeyT', 'KeyY', 'KeyU', 'KeyI', 'KeyO', 'KeyP'];
// F G A B C D E F G A B, relative to the octave anchor (`root`, below) — ends on a B so the
// treble register can start clean on the very next natural note, a C (see TREBLE_WHITE_OFFSETS).
const BASS_WHITE_OFFSETS = [-7, -5, -3, -1, 0, 2, 4, 5, 7, 9, 11];
// `Digit1` now sits exactly above the new Backquote-Q gap (F-G) — the same physical-row-offset
// convention already used for every other digit here, so Digit2..Digit0's own offsets below
// are completely unchanged from before this key was added.
const BASS_BLACK_CODES = ['Digit1', 'Digit2', 'Digit3', 'Digit5', 'Digit6', 'Digit8', 'Digit9', 'Digit0'];
// Digit4/7 are skipped (no key maps to them) — they sit above the two "natural" gaps (B-C,
// E-F) that have no black key at all.
const BASS_BLACK_OFFSETS = [-6, -4, -2, 1, 3, 6, 8, 10];
const TREBLE_WHITE_CODES = ['KeyZ', 'KeyX', 'KeyC', 'KeyV', 'KeyB', 'KeyN', 'KeyM'];
const TREBLE_WHITE_OFFSETS = [12, 14, 16, 17, 19, 21, 23]; // C D E F G A B, straight after the bass register's last B
// Shifted one key right of the naive "same shape as the bass row" alignment (KeyA/KeyD would
// otherwise be the first two) — matches how these two rows actually sit on a real keyboard.
// KeyF is skipped — it sits above the E-F gap, which (like B-C above) has no black key; KeyA
// isn't used at all here (it's one column left of where this row's black keys start).
const TREBLE_BLACK_CODES = ['KeyS', 'KeyD', 'KeyG', 'KeyH', 'KeyJ'];
const TREBLE_BLACK_OFFSETS = [13, 15, 18, 20, 22];

// C0..C6 (MIDI 12..84, scientific pitch notation — same convention as the old fixed
// `MIN_MIDI`/`MAX_MIDI` this replaces) — anchor points `shiftOctave()` steps through, so the
// ~2.5-octave window the two row-pairs above cover can slide across a real 88-key piano's
// full range instead of being stuck wherever it started. `root` is the reference C landmark
// (`KeyR`, the bass register's 5th white key) — NOT the window's own lowest note, which sits
// 7 semitones below it (see `BASS_WHITE_OFFSETS`).
const OCTAVE_STOPS = [12, 24, 36, 48, 60, 72, 84];
let octaveIndex = 3; // C3 — close to the old fixed layout's own MIN_MIDI, kept as the default
let MIN_MIDI, MAX_MIDI, KEY_MAP, pitchToCode;
function recomputeKeyRange() {
  const root = OCTAVE_STOPS[octaveIndex];
  MIN_MIDI = root - 7; // the bass register's own lowest note (an F)
  MAX_MIDI = root + 23; // the treble register's last white key (KeyM, a B)
  KEY_MAP = {};
  BASS_WHITE_CODES.forEach((code, i) => { KEY_MAP[code] = root + BASS_WHITE_OFFSETS[i]; });
  BASS_BLACK_CODES.forEach((code, i) => { KEY_MAP[code] = root + BASS_BLACK_OFFSETS[i]; });
  TREBLE_WHITE_CODES.forEach((code, i) => { KEY_MAP[code] = root + TREBLE_WHITE_OFFSETS[i]; });
  TREBLE_BLACK_CODES.forEach((code, i) => { KEY_MAP[code] = root + TREBLE_BLACK_OFFSETS[i]; });
  // One entry per pitch, not per code — every pitch in [MIN_MIDI, MAX_MIDI] has exactly one
  // mapped code by construction above, which is what lets `ensureKeyboardBuilt()` show a
  // letter on every single key it draws.
  pitchToCode = {};
  Object.entries(KEY_MAP).forEach(([code, pitch]) => { pitchToCode[pitch] = code; });
}
recomputeKeyRange();

// Canonical QWERTY reference letters for each code above — the labels shown by default, and
// always for every code except KeyY/KeyZ (see `applyKeyboardLayout` below). Uppercase
// already, per "en majuscule".
const CODE_QWERTY_LABEL = {
  Backquote: '`',
  KeyQ: 'Q', KeyW: 'W', KeyE: 'E', KeyR: 'R', KeyT: 'T', KeyY: 'Y', KeyU: 'U', KeyI: 'I', KeyO: 'O', KeyP: 'P',
  KeyA: 'A', KeyS: 'S', KeyD: 'D', KeyF: 'F', KeyG: 'G', KeyH: 'H', KeyJ: 'J',
  KeyZ: 'Z', KeyX: 'X', KeyC: 'C', KeyV: 'V', KeyB: 'B', KeyN: 'N', KeyM: 'M',
  Digit1: '1', Digit2: '2', Digit3: '3', Digit4: '4', Digit5: '5',
  Digit6: '6', Digit7: '7', Digit8: '8', Digit9: '9', Digit0: '0',
};
// QWERTY vs. QWERTZ differ, for every code this page actually maps, in exactly one place: the
// Y/Z swap — so a manual, persistent, two-way toggle (`toggleKeyboardLayout`, wired to a link
// near the identity line) covers it completely, rather than `navigator.keyboard.getLayoutMap()`
// alone: that API needs a SECURE CONTEXT (https, or http://localhost specifically) and isn't
// implemented at all in Safari/Firefox, so it silently never corrects anything the moment this
// page is reached over plain http:// from another device's LAN address — the normal way to
// reach it from a second browser/tablet, and exactly the situation that kept showing the
// un-swapped labels even after the underlying `.code`-based `KEY_MAP` was already correct.
let keyboardLayout = localStorage.getItem('vkKeyboardLayout') || 'qwerty';
let codeLabels = {};
function applyKeyboardLayout() {
  codeLabels = Object.assign({}, CODE_QWERTY_LABEL);
  if (keyboardLayout === 'qwertz') {
    codeLabels.KeyY = 'Z';
    codeLabels.KeyZ = 'Y';
  }
}
applyKeyboardLayout();
function toggleKeyboardLayout() {
  keyboardLayout = keyboardLayout === 'qwertz' ? 'qwerty' : 'qwertz';
  localStorage.setItem('vkKeyboardLayout', keyboardLayout);
  applyKeyboardLayout();
  refreshKeyLetterLabels();
  renderKeyboard();
}
// Best-effort pre-fill for the FIRST visit only (never overrides an explicit manual choice
// above) — if the API happens to be available (secure context, Chrome/Edge) and agrees this
// is a QWERTZ-style layout, start the toggle there instead of always defaulting to QWERTY.
if (!localStorage.getItem('vkKeyboardLayout') && navigator.keyboard && navigator.keyboard.getLayoutMap) {
  navigator.keyboard.getLayoutMap().then(layoutMap => {
    if (layoutMap.get('KeyY') === 'z' && keyboardLayout === 'qwerty') {
      keyboardLayout = 'qwertz';
      applyKeyboardLayout();
      refreshKeyLetterLabels(); // may resolve after the first paint — patch labels in place
    }
  }).catch(() => {}); // unsupported or permission denied — keep the QWERTY default
}

// Jumps straight to `newIndex` (any of `OCTAVE_STOPS`), then rebuilds the on-screen piano to
// match — "ajuster la zone affichee en fonction de la zone jouable au clavier". Releases
// everything first: the visible range is about to change entirely, so whatever was held may
// not even have an on-screen key left afterward. Shared by `shiftOctave()` (±1 step, from the
// ◂/▸ arrows or a keyboard shortcut) and `jumpToNearestOctaveFor()` (a direct jump, from
// clicking/tapping the mini-piano overview) — same effect, different way of picking the target.
function applyOctaveIndex(newIndex) {
  if (newIndex < 0 || newIndex >= OCTAVE_STOPS.length || newIndex === octaveIndex) return;
  clearAllLocalPressState();
  sendNoteEvent('/release-all');
  octaveIndex = newIndex;
  recomputeKeyRange();
  keyboardBuilt = false;
  renderKeyboard();
}
function shiftOctave(delta) {
  applyOctaveIndex(octaveIndex + delta);
}
// Picks whichever `OCTAVE_STOPS` window's own center ends up closest to `pitch` — "toujours en
// respectant la logique de positionnement correcte des touches": always one of the same fixed
// stops, never an arbitrary pixel-perfect note, so the result is exactly the same window
// `shiftOctave()` could have landed on by stepping.
function jumpToNearestOctaveFor(pitch) {
  let best = 0, bestDistance = Infinity;
  OCTAVE_STOPS.forEach((root, i) => {
    const distance = Math.abs(pitch - (root + 9)); // root+9 = this stop's own window center
    if (distance < bestDistance) { bestDistance = distance; best = i; }
  });
  applyOctaveIndex(best);
}

// This browser's persistent identity — generated once, kept in `localStorage` so reloading
// the page (or closing/reopening the tab) keeps driving the SAME track rather than starting
// a fresh one every time. `clientID` is opaque and never shown; `alias` is the display name,
// asked for once via `prompt()` and reusable/renamable afterward (see `renderIdentityLine`).
function loadOrCreateClientID() {
  let id = localStorage.getItem('vkClientID');
  if (!id) {
    id = (crypto.randomUUID ? crypto.randomUUID() : String(Date.now()) + '-' + Math.random().toString(16).slice(2));
    localStorage.setItem('vkClientID', id);
  }
  return id;
}
const clientID = loadOrCreateClientID();
let alias = localStorage.getItem('vkAlias');
if (!alias) {
  alias = (prompt(t('vkPromptDisplayName'), '') || '').trim() || t('vkDefaultAlias');
  localStorage.setItem('vkAlias', alias);
}
function renameIdentity() {
  const next = (prompt(t('vkPromptNewName'), alias) || '').trim();
  if (!next) return;
  alias = next;
  localStorage.setItem('vkAlias', alias);
  renderKeyboard();
}
// Every request needs both — appended by `sendNoteEvent`/`refresh`, never built ad hoc at
// each call site, so a change here (e.g. renaming) takes effect on the very next request.
function identityQuery() {
  return 'client=' + encodeURIComponent(clientID) + '&name=' + encodeURIComponent(alias);
}

// --- Circle-of-fifths wheel — shown only while a guide is active (see `refresh()`) ---
// Ported from `StaticAssets.swift`'s own `renderWheel`/`diatonicBoundaryPath`/`polarPoint`
// (see there for the reasoning behind each constant/shape) but trimmed down: no per-track
// outline rings or legend, since this page has no `tracks` list to color-code against — just
// the plain wheel itself, per "juste le cercle des quintes."
const NOTE_NAMES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
const CHORD_SUFFIX = { major: '', minor: 'm', diminished: '°' };

// --- Grand staff (treble + bass) — ported verbatim from `StaticAssets.swift`'s own
// `renderStaffSVG` (see there for the full reasoning behind the row/ledger-line math, the
// alternating-seconds offset, and the clef font-size/offset tuning). The history it draws
// (`track.recentChordEvents`) comes straight from the server now, not built/deduped
// client-side — see that field's own doc comment in `WebConsoleState.swift` for why: a
// client-side version built by diffing successive `GET /state` polls could silently miss any
// chord played and released faster than the poll interval, a real reported bug.
const STAFF_MIN_MIDI = 43; // G2
const STAFF_MAX_MIDI = 84; // C6
const STAFF_LETTER_PC = { C: 0, D: 2, E: 4, F: 5, G: 7, A: 9, B: 11 };
const STAFF_LETTERS = ['C', 'D', 'E', 'F', 'G', 'A', 'B'];

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
// See `StaticAssets.swift`'s own copy of these constants for how they were derived (measured
// glyph-ink-extent ratios against the text baseline, at a large font-size in a headless-Chrome
// screenshot) — kept identical here since both pages render the exact same clef glyphs.
const STAFF_MARGIN_TOP = 46, STAFF_MARGIN_BOTTOM = 32;
const STAFF_CLEF_FONT_SIZE_G = 130, STAFF_CLEF_FONT_SIZE_F = 83; // F clef reduced ~30% per feedback
const STAFF_CLEF_G_DY = 0.22 * STAFF_CLEF_FONT_SIZE_G, STAFF_CLEF_F_DY = 0.45 * STAFF_CLEF_FONT_SIZE_F; // 0.25 sat a hair too low
const STAFF_CLEF_X = 4;
const STAFF_LINES_LEFT_X = 4; // lines run the FULL width, under both clefs, like real notation
const STAFF_STAVES_X = 78; // past both clefs' own widest extent — first NOTE column starts here, not the lines themselves
const STAFF_COL_WIDTH = 44, STAFF_FIRST_COL_X = STAFF_STAVES_X + 26;
const STAFF_NOTE_RX = 9, STAFF_NOTE_RY = 7.5;

// Must match `.staff`'s own CSS `height` — how a viewBox width converts to an on-screen pixel
// width, since `.staff` is `width: auto; height: 130px` (aspect-ratio-preserving).
const STAFF_DISPLAY_HEIGHT_PX = 130;

// `minWidthPx`: the staff's on-screen width is never narrower than this (extra blank paper to
// the right of the last event) — used to match the piano's own current width (see
// `keyboardPixelWidth`) so the two don't visually mismatch just because there isn't enough
// history yet to need that much room on its own. Omit/0 to size purely from content, as the
// read-only console's own per-track staff still does (it has no single "the keyboard" to
// match widths against).
// `firstColOffset`: shifts every note column left/right from `STAFF_FIRST_COL_X` — only the
// Guide panel's own single-chord notation passes a (negative) value here, per feedback that its
// notes sat too far from the clef once that staff got rendered much larger than the shared
// default; every other caller omits it (0), keeping their own note placement unchanged.
function renderStaffSVG(history, minWidthPx, firstColOffset) {
  const events = (history || []).filter(e => e.pitches && e.pitches.length);
  const colOffset = firstColOffset || 0;
  const height = STAFF_MARGIN_TOP + STAFF_MARGIN_BOTTOM + (STAFF_ROWS.length - 1) * STAFF_ROW_HEIGHT;
  const contentWidth = STAFF_FIRST_COL_X + colOffset + Math.max(events.length - 1, 0) * STAFF_COL_WIDTH + STAFF_MARGIN_RIGHT;
  const minViewBoxWidth = minWidthPx ? minWidthPx * (height / STAFF_DISPLAY_HEIGHT_PX) : 0;
  const width = Math.max(contentWidth, minViewBoxWidth);
  const y = i => STAFF_MARGIN_TOP + i * STAFF_ROW_HEIGHT;

  let svg = `<svg class="staff" viewBox="0 0 ${width} ${height}">`;
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
        // once the guide's own single-chord staff got rendered much larger than the shared
        // default — visually cramped/overlapping per feedback.
        svg += `<text class="staff-accidental staff-note-${cls}" x="${cx - 18}" y="${y(n.row) + 4}">${glyph}</text>`;
      }
      svg += `<ellipse class="staff-note staff-note-${cls}" cx="${cx}" cy="${y(n.row)}" rx="${STAFF_NOTE_RX}" ry="${STAFF_NOTE_RY}" />`;
    });
  });

  svg += '</svg>';
  return `<div class="staff-scroll">${svg}</div>`;
}

// Builds a single `renderStaffSVG` event for the guide's proposed chord (root + tones), for the
// Guide panel's "partition" column — a static snapshot, not a live-performance event. Ported
// verbatim from `StaticAssets.swift`'s own copy — see there for the full reasoning (`tones`
// already includes the root itself as its first entry, and every chord template's intervals are
// guaranteed < 12, so `(pc - root + 12) % 12` recovers each tone's exact semitone offset from
// the root with no ambiguity).
function chordStaffEvent(root, tones) {
  const rootMidi = 60 + root;
  const pitches = (tones || []).map(pc => rootMidi + (((pc - root) % 12) + 12) % 12);
  return { pitches, chordRoot: root, chordTones: tones || [] };
}

// Plain triads (root/third/fifth), rooted at a fixed C4-based octave regardless of
// `shiftOctave()` — lights up real on-screen keys as long as the current octave window
// happens to overlap C4..G5, same as before this page could slide its own visible range;
// outside that window the notes still play (the session gets the note-on/off either way),
// they just won't have a highlighted key to show for it until you shift back.
const WHEEL_CHORD_INTERVALS = { major: [0, 4, 7], minor: [0, 3, 7], diminished: [0, 3, 6] };
function chordPitchesForCell(pitchClass, quality) {
  const root = 60 + pitchClass;
  return WHEEL_CHORD_INTERVALS[quality].map(interval => root + interval);
}
function wheelCellFromTarget(el) {
  const cell = el && el.closest ? el.closest('.wheel-cell-shape') : null;
  if (!cell) return null;
  return { pitches: chordPitchesForCell(parseInt(cell.dataset.pitchClass, 10), cell.dataset.quality), el: cell };
}
function degreeSVGMarkup(degree) {
  if (!degree.endsWith('°')) return degree;
  return `${degree.slice(0, -1)}<tspan baseline-shift="super" font-size="75%">°</tspan>`;
}
function polarPoint(cx, cy, r, index, count) {
  const angle = (2 * Math.PI * index) / count - Math.PI / 2;
  return { x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) };
}

// Degrees to rotate a label around its own `polarPoint` so its baseline runs tangent to the
// wheel (perpendicular to the radius) instead of staying horizontal — mirrors
// `StaticAssets.swift`'s own `circularLabelRotation` (see there for the reasoning behind the
// 180° flip on the lower half of the circle).
function circularLabelRotation(index, count) {
  const deg = (360 * index) / count;
  return deg > 90 && deg < 270 ? deg + 180 : deg;
}
const WHEEL_RING_RADIUS = { major: 110, minor: 160, diminished: 205 };
const WHEEL_MODE_NAME_RADIUS = 248;
const WHEEL_DISK_RADIUS = 262;
const WHEEL_HUB_RADIUS = 70;
const WHEEL_GRID_OUTER_RADIUS = 225;
const WHEEL_RING_BOUNDARIES = [
  (WHEEL_HUB_RADIUS + WHEEL_RING_RADIUS.major) / 2,
  (WHEEL_RING_RADIUS.major + WHEEL_RING_RADIUS.minor) / 2,
  (WHEEL_RING_RADIUS.minor + WHEEL_RING_RADIUS.diminished) / 2,
];

function diatonicBoundaryPath(wheel, cx, cy) {
  const count = wheel.columns.length;
  const tonicIndex = wheel.activeColumnIndex;
  const boundaryAngle = index => (2 * Math.PI * (index + 0.5)) / count - Math.PI / 2;
  const angleLeft = boundaryAngle(tonicIndex - 2);
  const angleIV = boundaryAngle(tonicIndex - 1);
  const angleV = boundaryAngle(tonicIndex);
  const angleRight = boundaryAngle(tonicIndex + 1);
  const rInner = WHEEL_RING_BOUNDARIES[0];
  const rMid = WHEEL_RING_BOUNDARIES[2];
  const rOuter = WHEEL_GRID_OUTER_RADIUS;
  function arcTo(points, radius, fromAngle, toAngle) {
    const span = toAngle - fromAngle;
    const steps = Math.max(1, Math.ceil((Math.abs(span) * 180) / Math.PI / 3));
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
  arcTo(points, rInner, angleRight, angleLeft);
  return 'M' + points.map(p => `${p.x.toFixed(1)},${p.y.toFixed(1)}`).join(' L') + ' Z';
}

// `showModeContext` gates everything that's only MEANINGFUL relative to an active guide's
// tonic/mode (mode-name labels, roman-numeral degrees, the diatonic-boundary outline) — the
// wheel is now always shown (guide or not), but without a guide there's no reference tonic to
// hang those on; showing them anyway (derived from whatever arbitrary fallback tonic the
// server picks — see `ImprovSession.wheelReferenceMode`'s doc comment) would just be
// misleading. The chord grid itself (shape/color/name, and clicking it) stays fully usable
// either way — only these mode-relative extras disappear.
// This client's own currently-detected chord, if any — `{pitchClass, quality}` matching a
// wheel cell's own shape, or `null`. Not gated by `showModeContext`: which chord you're
// personally playing right now isn't relative to any reference tonic, unlike the mode-name/
// roman-numeral/diatonic-boundary parts, so it stays shown whether or not a guide is running.
function detectedChordFrom(track) {
  if (!track || track.chordRoot === null || track.chordRoot === undefined) return null;
  const intervals = new Set((track.chordTones || []).map(t => ((t - track.chordRoot) % 12 + 12) % 12));
  let quality = null;
  if (intervals.has(4) && intervals.has(7)) quality = 'major';
  else if (intervals.has(3) && intervals.has(7)) quality = 'minor';
  else if (intervals.has(3) && intervals.has(6)) quality = 'diminished';
  return quality ? { pitchClass: track.chordRoot, quality } : null;
}

function renderWheel(wheel, showModeContext, detectedChord, progressionChords) {
  if (!wheel) return '';
  const cx = 270, cy = 270;
  const count = wheel.columns.length;
  let svg = `<svg class="wheel" viewBox="0 0 540 540">`;
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
    if (showModeContext && column.modeName) {
      const pos = polarPoint(cx, cy, WHEEL_MODE_NAME_RADIUS, index, count);
      const cls = column.modeName === wheel.activeModeName ? 'wheel-mode-name active' : 'wheel-mode-name';
      const rotate = circularLabelRotation(index, count);
      svg += `<text class="${cls}" x="${pos.x}" y="${pos.y}" transform="rotate(${rotate} ${pos.x} ${pos.y})">${column.modeName}</text>`;
    }
    column.cells.forEach(cell => {
      const r = WHEEL_RING_RADIUS[cell.quality];
      const pos = polarPoint(cx, cy, r, index, count);
      const color = PITCH_CLASS_COLORS[cell.pitchClass];
      const textColor = PITCH_CLASS_TEXT_COLORS[cell.pitchClass];
      const size = 18;
      const rotateDeg = (360 * index) / count;
      // `data-pitch-class`/`data-quality` — read back by `wheelCellFromTarget()` to figure out
      // which chord to play when this shape is clicked/tapped (see there); the read-only web
      // console's own `renderWheel` deliberately has no equivalent, since only this
      // interactive page plays notes.
      const cellAttrs = `class="wheel-cell-shape" data-pitch-class="${cell.pitchClass}" data-quality="${cell.quality}"`;
      if (cell.shape === 'square') {
        svg += `<g transform="rotate(${rotateDeg} ${pos.x} ${pos.y})"><rect ${cellAttrs} x="${pos.x - size}" y="${pos.y - size}" width="${size * 2}" height="${size * 2}" fill="${color}" /></g>`;
      } else {
        svg += `<circle ${cellAttrs} cx="${pos.x}" cy="${pos.y}" r="${size}" fill="${color}" />`;
      }
      if (detectedChord && cell.pitchClass === detectedChord.pitchClass && cell.quality === detectedChord.quality) {
        const ringSize = size + 4;
        if (cell.shape === 'square') {
          svg += `<g transform="rotate(${rotateDeg} ${pos.x} ${pos.y})"><rect class="wheel-cell-detected" x="${pos.x - ringSize}" y="${pos.y - ringSize}" width="${ringSize * 2}" height="${ringSize * 2}" /></g>`;
        } else {
          svg += `<circle class="wheel-cell-detected" cx="${pos.x}" cy="${pos.y}" r="${ringSize}" />`;
        }
      }
      if ((progressionChords || []).some(c => c.root === cell.pitchClass && c.quality === cell.quality)) {
        const ringSize = size + 8;
        if (cell.shape === 'square') {
          svg += `<g transform="rotate(${rotateDeg} ${pos.x} ${pos.y})"><rect class="wheel-cell-progression" x="${pos.x - ringSize}" y="${pos.y - ringSize}" width="${ringSize * 2}" height="${ringSize * 2}" /></g>`;
        } else {
          svg += `<circle class="wheel-cell-progression" cx="${pos.x}" cy="${pos.y}" r="${ringSize}" />`;
        }
      }
      // The chord's own name (e.g. "Cm") — always shown, unlike the roman numeral below: it's
      // a property of the chord itself, not of any reference tonic.
      const symbol = NOTE_NAMES[cell.pitchClass] + CHORD_SUFFIX[cell.quality];
      svg += `<text class="wheel-cell-symbol" x="${pos.x}" y="${pos.y + 1}" fill="${textColor}">${symbol}</text>`;
      if (showModeContext) {
        svg += `<text class="wheel-cell-degree" x="${pos.x}" y="${pos.y + 9}" fill="${textColor}">${degreeSVGMarkup(cell.relativeDegree)}</text>`;
      }
    });
  });
  if (showModeContext) {
    svg += `<path class="wheel-diatonic-boundary" d="${diatonicBoundaryPath(wheel, cx, cy)}" />`;
  }
  svg += '</svg>';
  return svg;
}

// `let`, not `const` — this starting array (hand-mirroring `MusicTheoryKit.PitchClassPalette.hex`)
// is only the fallback shown before the first `GET /state` response arrives; `refresh()`
// below overwrites it with `state.palette` every poll, so switching the active palette (menu
// JamShack > Choisir palette de couleur) updates this page within one refresh cycle.
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

// Real-piano geometry, matching `StaticAssets.swift`'s own `keyboardHTML` (see there for the
// white/black-slot reasoning) — kept in sync by hand since the two pages are otherwise
// independent (this one is interactive, that one is read-only). Twice the read-only page's
// own key size: this one needs to be comfortably clickable/touchable, not just readable.
const WHITE_KEY_WIDTH = 44, WHITE_KEY_HEIGHT = 144, BLACK_KEY_WIDTH = 26, BLACK_KEY_HEIGHT = 92;
const WHITE_SLOT_BY_SEMITONE = { 0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6 };
const BLACK_AFTER_WHITE_SLOT = { 1: 0, 3: 1, 6: 3, 8: 4, 10: 5 };

// Small, non-interactive 2-octave reference diagram for the Guide panel's own mode/chord
// keyboards (see `guideInfoHTML`'s assembly) — deliberately its own fixed range, independent
// of `MIN_MIDI`/`MAX_MIDI` (which move with `shiftOctave`/the interactive keyboard below):
// the guide's reference diagrams shouldn't scroll away just because the player moved their
// own playing range. `rootPC`/`tonesPCs` are pitch classes (0-11), not absolute pitches —
// `rootClass`/`toneClass` pick which CSS classes color them (`.mode-root`/`.mode-tone` for
// the mode keyboard, `.root`/`.tone` for the chord keyboard — same meaning as everywhere
// else `.pkey` is used, just applied unconditionally here since there's no "held" state).
function guideReferenceKeyboardHTML(minMidi, maxMidi, rootPC, tonesPCs, rootClass, toneClass) {
  const tones = new Set(tonesPCs || []);
  const octaveCount = Math.ceil((maxMidi - minMidi + 1) / 12);
  const totalWidth = octaveCount * 7 * WHITE_KEY_WIDTH;
  let whiteHTML = '', blackHTML = '';
  for (let pitch = minMidi; pitch <= maxMidi; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    const octave = Math.floor((pitch - minMidi) / 12);
    let cls = '';
    if (rootPC !== null && rootPC !== undefined && pc === rootPC) cls = rootClass;
    else if (tones.has(pc)) cls = toneClass;
    if (WHITE_SLOT_BY_SEMITONE[pc] !== undefined) {
      const slot = octave * 7 + WHITE_SLOT_BY_SEMITONE[pc];
      const x = slot * WHITE_KEY_WIDTH;
      whiteHTML += `<div class="pkey white ${cls}" style="left:${x}px; width:${WHITE_KEY_WIDTH}px; height:${WHITE_KEY_HEIGHT}px;"></div>`;
    } else {
      const slot = octave * 7 + BLACK_AFTER_WHITE_SLOT[pc] + 1;
      const x = slot * WHITE_KEY_WIDTH - BLACK_KEY_WIDTH / 2;
      blackHTML += `<div class="pkey black ${cls}" style="left:${x}px; width:${BLACK_KEY_WIDTH}px; height:${BLACK_KEY_HEIGHT}px;"></div>`;
    }
  }
  return `<div class="keyboard-scroll guide-keyboard-small"><div class="keyboard" style="width:${totalWidth}px; height:${WHITE_KEY_HEIGHT}px;">${whiteHTML}${blackHTML}</div></div>`;
}

// Same rendering as `StaticAssets.swift`'s own `guitarChordDiagramHTML` — see that copy's
// doc comment for the data shape/orientation. Kept as a duplicate rather than shared: these
// two pages are otherwise independent JS bundles (see this file's own header comment).
function guitarChordDiagramHTML(diagram) {
  if (!diagram) return `<div class="field empty">${t('placeholderPasDePositionGuitareStandard')}</div>`;
  const frets = diagram.frets || [];
  const fingers = diagram.fingers || [];
  const stringCount = 6;
  const shownFrets = 4;
  // Dimensions/margins match `StaticAssets.swift`'s own copy (enlarged a bit, and marginTop
  // tightened, per feedback there — see that copy's own comments for the exact reasoning).
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
    if (relativeFret === 0) return;
    const y = marginTop + (relativeFret + 0.5) * fretSpacing;
    svg += `<circle cx="${x}" cy="${y}" r="8" class="guitar-dot" />`;
    if (fingers[i] !== null && fingers[i] !== undefined) {
      svg += `<text x="${x}" y="${y + 4}" class="guitar-finger">${fingers[i]}</text>`;
    }
  });
  if (barredIndices.length === 1) {
    const x = marginLeft + barredIndices[0] * stringSpacing;
    const y = marginTop + fretSpacing / 2;
    svg += `<circle cx="${x}" cy="${y}" r="8" class="guitar-dot" />`;
  }
  svg += '</svg>';
  return `<div class="guitar-diagram-label">${diagram.label}</div>${svg}`;
}

// --- Mini full-piano overview, above the real keyboard — a tiny "you are here" strip
// spanning C-1..C8 (comfortably past every extreme `OCTAVE_STOPS`/`BASS_WHITE_OFFSETS` can
// reach), with an outline marking exactly which slice ([MIN_MIDI, MAX_MIDI]) is played below.
const MINI_PIANO_MIN = 0, MINI_PIANO_MAX = 108;
const MINI_WHITE_WIDTH = 5, MINI_WHITE_HEIGHT = 22, MINI_BLACK_WIDTH = 3, MINI_BLACK_HEIGHT = 14;
// Same "absolute octave, not relative to some arbitrary start pitch" fix as
// `ensureKeyboardBuilt()`'s own `octaveBase` — `MINI_PIANO_MIN` is 0 (a C) here, so this is
// actually a no-op today, but computing it the same way keeps both pieces of code obviously
// consistent rather than relying on that coincidence.
const MINI_OCTAVE_BASE = Math.floor(MINI_PIANO_MIN / 12);
function miniWhiteSlot(pitch) {
  const pc = ((pitch % 12) + 12) % 12;
  const octave = Math.floor(pitch / 12) - MINI_OCTAVE_BASE;
  return octave * 7 + WHITE_SLOT_BY_SEMITONE[pc];
}
// `svgTargetWidth`: the SVG's OWN displayed width — NOT the same as the piano's width. Per a
// target layout mockup, the whole `.octave-controls` ROW (min-label + ◂ + this SVG + ▸ +
// max-label) is what should match the piano's width, with "F5 ◂"/"▸ B7" flush at the shared
// left/right edges and the mini-piano's own keys inset from both — so the caller
// (`ensureKeyboardBuilt`) passes `keyboardPixelWidth` minus the labels/arrows' own measured
// width, not `keyboardPixelWidth` directly (an earlier pass did that, and separately had
// mis-read "make the overview bigger" as "30% wider than the piano" — the actual ask was
// always for the whole row to match the piano's width end to end). A pure display-size scale
// via the SVG's own `width`/`height` attributes, distinct from its `viewBox`: every rect below
// is still positioned in NATURAL (unscaled) coordinates, so this scale factor never has to
// leak into any of the click-to-pitch math (`jumpOctaveFromMiniPianoClick` already converts
// through `getBoundingClientRect()`, i.e. the actual on-screen size, so it's automatically
// correct at any scale).
function renderMiniPianoOverview(svgTargetWidth) {
  // NOT `Math.ceil((MAX-MIN+1)/12) * 7 * MINI_WHITE_WIDTH` (a round number of octaves) — real
  // bug found by measuring rendered element boxes, not by inspection: `MINI_PIANO_MIN`..
  // `MINI_PIANO_MAX` spans C-1..C8, i.e. 9 full octaves plus one extra white key (the final C),
  // not a round 10 octaves — rounding UP to 10 left a trailing ~59px strip of transparent SVG
  // background past the last drawn key, which is exactly the flush-right edge this SVG is
  // measured/sized against (`ensureKeyboardBuilt()`), so the piano keys visibly stopped short of
  // the `▸` arrow while the (invisible) SVG box itself sat correctly flush against it — read as
  // "the keyboard drawing isn't centered between the arrows". Deriving `naturalWidth` from the
  // actual rightmost drawn white key instead makes the SVG's own coordinate space match its
  // content exactly, with no dead space possible on either edge.
  const naturalWidth = (miniWhiteSlot(MINI_PIANO_MAX) + 1) * MINI_WHITE_WIDTH;
  const displayWidth = svgTargetWidth || naturalWidth;
  const displayHeight = MINI_WHITE_HEIGHT * (displayWidth / naturalWidth);
  const width = naturalWidth;
  let svg = `<svg class="mini-piano" width="${displayWidth}" height="${displayHeight}" viewBox="0 0 ${width} ${MINI_WHITE_HEIGHT}">`;
  for (let pitch = MINI_PIANO_MIN; pitch <= MINI_PIANO_MAX; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    if (WHITE_SLOT_BY_SEMITONE[pc] === undefined) continue;
    const x = miniWhiteSlot(pitch) * MINI_WHITE_WIDTH;
    svg += `<rect class="mini-key-white" x="${x}" y="0" width="${MINI_WHITE_WIDTH}" height="${MINI_WHITE_HEIGHT}" />`;
  }
  for (let pitch = MINI_PIANO_MIN; pitch <= MINI_PIANO_MAX; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    if (WHITE_SLOT_BY_SEMITONE[pc] !== undefined) continue;
    const octave = Math.floor(pitch / 12) - MINI_OCTAVE_BASE;
    const slot = octave * 7 + BLACK_AFTER_WHITE_SLOT[pc] + 1;
    const x = slot * MINI_WHITE_WIDTH - MINI_BLACK_WIDTH / 2;
    svg += `<rect class="mini-key-black" x="${x}" y="0" width="${MINI_BLACK_WIDTH}" height="${MINI_BLACK_HEIGHT}" />`;
  }
  // Both always land on a white key (F and B respectively — see `BASS_WHITE_OFFSETS`/
  // `TREBLE_WHITE_OFFSETS`), so a plain white-key-slot lookup is enough for both edges.
  const highlightX1 = miniWhiteSlot(MIN_MIDI) * MINI_WHITE_WIDTH;
  const highlightX2 = (miniWhiteSlot(MAX_MIDI) + 1) * MINI_WHITE_WIDTH;
  svg += `<rect class="mini-piano-active" x="${highlightX1}" y="0" width="${highlightX2 - highlightX1}" height="${MINI_WHITE_HEIGHT}" />`;
  svg += '</svg>';
  return svg;
}

// Inverse of `WHITE_SLOT_BY_SEMITONE` (slot 0..6 within an octave -> pitch class) — needed to
// go from "which white-key slot did the click land in" back to an actual pitch, for
// `jumpOctaveFromMiniPianoClick()` below.
const SEMITONE_BY_WHITE_SLOT = [0, 2, 4, 5, 7, 9, 11];
// Touch/click anywhere on the mini overview jumps the playable window straight there — "si on
// touche dans le plan de clavier, on decale la zone active sur cela". Only ever needs an
// APPROXIMATE pitch (`jumpToNearestOctaveFor` immediately snaps it to the nearest real stop
// anyway), so this doesn't bother distinguishing white/black — closest white slot is enough.
function jumpOctaveFromMiniPianoClick(svg, clientX) {
  const rect = svg.getBoundingClientRect();
  if (rect.width === 0) return;
  const xInSvg = ((clientX - rect.left) / rect.width) * svg.viewBox.baseVal.width;
  const slot = Math.max(0, Math.floor(xInSvg / MINI_WHITE_WIDTH));
  const octaveRel = Math.floor(slot / 7);
  const pc = SEMITONE_BY_WHITE_SLOT[Math.min(slot - octaveRel * 7, 6)];
  jumpToNearestOctaveFor((octaveRel + MINI_OCTAVE_BASE) * 12 + pc);
}

// C/F have a black key ONLY on their right (nothing between B-C or E-F), E/B have one ONLY
// on their left — so the visually "exposed" top portion of those 4 white keys (the part not
// covered by an adjacent black key) isn't centered on the key's own full width like it is for
// D/G/A (flanked on both sides). `key-letter`'s default `left: 50%` only suits D/G/A and the
// black keys themselves; `ensureKeyboardBuilt()` overrides it with one of these two for C/F/
// E/B, so their letters actually sit in the middle of the visible white area, not the middle
// of the whole key.
const KEY_LETTER_LEFT_SHIFTED_TOWARD_LEFT = (WHITE_KEY_WIDTH - BLACK_KEY_WIDTH / 2) / 2; // C, F
const KEY_LETTER_LEFT_SHIFTED_TOWARD_RIGHT = WHITE_KEY_WIDTH - KEY_LETTER_LEFT_SHIFTED_TOWARD_LEFT; // E, B

let roles = {};          // pitch class -> {degree, color, textColor}, from the last /state poll
let heldPitches = new Set();
let chordRoot = null;
let chordTones = new Set();
// Two separate lines (chord, then mode candidates below it if any), neither labeled — chord
// and mode are two independent pieces of information, not one combined sentence.
let chordLine = '<span class="empty">(aucune note)</span>';
let modeLine = '';
let guideIsActive = false;
let guideInfoHTML = '';  // guide title + steps, only while a guide is active — see refresh()
let wheelHTML = '';      // always rendered, mode-relative parts gated by `guideIsActive`
let staffHTML = '';      // this client's own track, rebuilt every poll — see refresh()
// Global, not scoped to this client's own track — see `ImprovSession.handleVirtualKeyboardRequest`'s
// doc comment on `/guide-advance`.
function sendGuideAdvance(delta) {
  fetch('/guide-advance?delta=' + delta + '&' + identityQuery()).catch(() => {});
}

// How many wheel-cell presses (mouse + every active touch) are currently in flight — while
// this is > 0, `renderKeyboard()` skips rebuilding `#guide-container` (see there): the wheel
// SVG is thrown away and rebuilt from scratch on every poll, and a touch that's still down
// when that happens has its element detached mid-gesture — the exact "release only registers
// on a second tap" failure mode `ensureKeyboardBuilt()`'s own comment describes, just for the
// wheel instead of the piano. Freezing the wheel's DOM for the (usually sub-second) duration
// of a press sidesteps it without needing the piano's full "build once, mutate" treatment.
let wheelChordActiveCount = 0;

// This client's OWN currently-pressed pitches — shown immediately (`.pressed`) without
// waiting for the next /state poll, which only carries the *server's* confirmed view (used
// for the root/tone/outside chord-relative coloring instead).
const pressedLocally = new Set();

// `GET /note-on`/`GET /note-off` are each their own independent TCP connection (no
// keep-alive — see `HTTPWireFormat`'s doc comment), so nothing guarantees a fast tap's "on"
// reaches the server before its "off": two unrelated connections racing to be accepted can
// arrive in either order, occasionally leaving a note stuck held with no release to follow.
// Chaining every request through one promise queue makes THIS client's own requests strictly
// sequential (each one's connection only opens once the previous finished) — the actual fix,
// not just a cosmetic one; Escape (below) is the recovery for anything that still slips
// through (a genuinely dropped/failed request, not just misordering).
let requestQueue = Promise.resolve();
function sendNoteEvent(path) {
  const separator = path.includes('?') ? '&' : '?';
  requestQueue = requestQueue.then(() => fetch(path + separator + identityQuery()).catch(() => {}));
}

// Toggles the `.pressed` class directly on the existing DOM node — NOT via `renderKeyboard()`
// (a full innerHTML rebuild): replacing a key's element while a touch that started on it is
// still active is what caused the reported "release only registers on a second tap" bug —
// WebKit (and others) can silently stop delivering touchend/touchmove for a touch whose
// original target got detached from the document mid-gesture, permanently orphaning it.
// Mutating the existing node in place never detaches it, so the touch's own touchend always
// still finds it.
function setPressedVisual(pitch, isPressed) {
  const el = document.querySelector('.pkey[data-pitch="' + pitch + '"]');
  if (el) el.classList.toggle('pressed', isPressed);
}

function noteOn(pitch) {
  if (pressedLocally.has(pitch)) return; // already down — computer keydown auto-repeats
  pressedLocally.add(pitch);
  setPressedVisual(pitch, true);
  sendNoteEvent('/note-on?pitch=' + pitch);
}
function noteOff(pitch) {
  if (!pressedLocally.has(pitch)) return;
  pressedLocally.delete(pitch);
  setPressedVisual(pitch, false);
  sendNoteEvent('/note-off?pitch=' + pitch);
}
// Shared by the panic button (below) and `shiftOctave()` — both need to drop every local
// "what's currently down" record without individually replaying note-offs (the session is
// asked to release everything itself, via one `/release-all`, right after).
function clearAllLocalPressState() {
  pressedLocally.clear();
  downCodes.clear();
  activeTouches.clear();
  mouseHeldPitch = null;
  if (mouseHeldWheelEl) { mouseHeldWheelEl.classList.remove('pressed'); mouseHeldWheelEl = null; }
  mouseHeldWheelPitches = [];
  activeWheelTouches.forEach(t => t.el.classList.remove('pressed'));
  activeWheelTouches.clear();
  wheelChordActiveCount = 0;
}
// The panic button: asks the *session* to release whatever it thinks this track is holding,
// rather than replaying this client's own (possibly already-wrong) idea of what's down —
// clears local tracking too, so typed/touched keys don't look stuck after this even if the
// server had nothing left to release.
function releaseAll() {
  clearAllLocalPressState();
  sendNoteEvent('/release-all');
  renderKeyboard();
}

function keyClasses(pitch, pc) {
  const classes = ['pkey', WHITE_SLOT_BY_SEMITONE[pc] !== undefined ? 'white' : 'black'];
  if (pressedLocally.has(pitch)) classes.push('pressed');
  if (heldPitches.has(pitch)) {
    if (chordRoot !== null && pc === chordRoot) classes.push('root');
    else if (chordTones.has(pc)) classes.push('tone');
    else if (chordRoot !== null) classes.push('outside');
    else classes.push('held');
  }
  return classes.join(' ');
}

// Built exactly ONCE (`ensureKeyboardBuilt`), then only ever mutated in place
// (`updateKeyVisuals`) — NOT rebuilt via `innerHTML` on every poll. A touch that starts on a
// `.pkey` element and is still down when the periodic `refresh()` tick lands (any hold longer
// than the ~200ms poll interval — i.e. any deliberately sustained note, not just a fast tap)
// used to have its element destroyed and recreated mid-gesture: WebKit (and others) then
// silently stop delivering that touch's `touchend`, permanently orphaning it — this is what
// was still reproducing the "release only registers on a second tap" bug even after `noteOn`/
// `noteOff` stopped rebuilding the DOM themselves (a fast tap could dodge a 200ms tick; a held
// note could not). Never destroying the element at all removes the failure mode entirely,
// regardless of hold duration or poll timing.
let keyboardBuilt = false;
// The real piano's current on-screen pixel width — recomputed only when the keyboard itself
// is rebuilt (an octave shift), not every poll. `renderStaffSVG` reads this so the staff's
// white "paper" background is never narrower than the piano above it, even when there isn't
// enough history yet to need that much width on its own — see `renderStaffSVG`'s own comment.
let keyboardPixelWidth = 0;

// Fits the whole two-column layout (wheel + keyboard/staff/etc.) into whatever viewport width
// is actually available, then grows it proportionally on a bigger screen instead of a fixed
// pixel design that just needs horizontal scrolling on a 13" MacBook/11" iPad and stays small
// on a large monitor — "usable on a 13"/11" screen, and grows on anything bigger" was the
// explicit ask (a phone-sized redesign is a separate, later pass).
//
// The wheel's own rendered width can't be measured directly and trusted as "natural": `.wheel`
// is `width: 100%; max-width: 624px`, and that 100% resolves against whatever space the
// CURRENT viewport happens to leave `.layout-col-left` — a real trap found via measurement,
// not by inspection: resetting `#layout-columns`' transform to `none` and reading
// `getBoundingClientRect().width` back kept coming back suspiciously close to the CURRENT
// viewport's own available width at every window size tried, instead of one fixed
// viewport-independent number — because the wheel's 100% had already shrunk/grown to fit
// whatever the page's actual current width was, so "resetting the transform" never actually
// removed the viewport's influence on the measurement. `#keyboard-align-wrapper`'s own width
// has no such trap (its children are all fixed-pixel or content-driven, no `%`-of-viewport
// sizing anywhere in that subtree), so it's measured directly; the wheel's contribution uses
// its own `WHEEL_MAX_WIDTH_PX` constant instead — the size it would actually render at once
// this whole block is scaled to fit (the transform applies uniformly to the whole subtree, so
// the wheel ends up the right proportional size regardless of what its `100%` resolved to at
// measurement time).
const WHEEL_MAX_WIDTH_PX = 624; // matches `.wheel`'s own CSS max-width
const LAYOUT_GAP_PX = 32; // matches `.layout-columns`' `gap: 2rem` (1rem = 16px default)
const BODY_MAX_WIDTH_PX = 1600, BODY_HORIZONTAL_PADDING_PX = 48; // matches `body`'s own CSS
const RESPONSIVE_MIN_SCALE = 0.5, RESPONSIVE_MAX_SCALE = 1.6;
function applyResponsiveScale() {
  const columns = document.getElementById('layout-columns');
  const clip = document.getElementById('responsive-scale-clip');
  const wrapper = document.getElementById('keyboard-align-wrapper');
  if (!columns || !clip || !wrapper) return;
  columns.style.transform = 'none';
  const wrapperWidth = wrapper.getBoundingClientRect().width;
  const naturalHeight = columns.getBoundingClientRect().height;
  if (!wrapperWidth) return;
  const naturalWidth = WHEEL_MAX_WIDTH_PX + LAYOUT_GAP_PX + wrapperWidth;
  const available = Math.max(1, Math.min(window.innerWidth, BODY_MAX_WIDTH_PX) - BODY_HORIZONTAL_PADDING_PX);
  const scale = Math.max(RESPONSIVE_MIN_SCALE, Math.min(RESPONSIVE_MAX_SCALE, available / naturalWidth));
  columns.style.transformOrigin = 'top left';
  columns.style.transform = `scale(${scale})`;
  // `transform` doesn't affect normal layout flow — without this, a shrunk layout would leave
  // its own UNSCALED height's worth of blank space below it (or a grown one would overflow
  // into whatever follows), since the surrounding page still sees the pre-transform box size.
  // Uses `naturalHeight` (measured above, before re-applying the transform) rather than
  // re-measuring now — `getBoundingClientRect()` after the transform already reflects the
  // SCALED size, and multiplying that by `scale` again would double-apply it.
  clip.style.height = (naturalHeight * scale) + 'px';
}
window.addEventListener('resize', applyResponsiveScale);
function ensureKeyboardBuilt() {
  if (keyboardBuilt) return;
  // Only reached right after `shiftOctave()` sets `keyboardBuilt = false` (a deliberate,
  // one-off user action, never something a periodic `refresh()` tick triggers on its own —
  // see `wheelChordActiveCount`'s doc comment for why that distinction matters) — safe to
  // drop whatever the previous range's keyboard div was.
  document.getElementById('keyboard-container').innerHTML = '';
  // Octave number relative to a fixed reference (pitch 0), not to `MIN_MIDI` itself — `MIN_MIDI`
  // is no longer always a C (the bass register now starts on an F, see `BASS_WHITE_OFFSETS`),
  // and computing `octave` from `pitch - MIN_MIDI` silently assumed it was: F2 would land in
  // "octave 0" while the very next C landed in "octave 1", pushing it 7 white-key slots to the
  // RIGHT of where it belongs and scrambling the whole keyboard's left-to-right order.
  const octaveBase = Math.floor(MIN_MIDI / 12);
  function whiteSlotFor(pitch) {
    const pc = ((pitch % 12) + 12) % 12;
    return (Math.floor(pitch / 12) - octaveBase) * 7 + WHITE_SLOT_BY_SEMITONE[pc];
  }
  // MIN_MIDI/MAX_MIDI are always white (F and B respectively — see `BASS_WHITE_OFFSETS`/
  // `TREBLE_WHITE_OFFSETS`), so both ends have a well-defined white-key slot. Subtracting
  // `leftWhiteSlotOffset` from every position below (instead of just starting the slot count
  // at whatever `octaveBase*7` happens to land on) is what makes MIN_MIDI's own key start
  // exactly at `left: 0` — without it, the `.keyboard` div's box was wider than its own visible
  // keys (extra blank space on one side, however much `MIN_MIDI` sits into its own octave),
  // which threw off `.keyboard-align-wrapper`'s centering: it centers each row on its
  // rendered BOX width, not on where the visible keys happen to sit inside that box.
  const leftWhiteSlotOffset = whiteSlotFor(MIN_MIDI);
  const totalWidth = (whiteSlotFor(MAX_MIDI) - leftWhiteSlotOffset + 1) * WHITE_KEY_WIDTH;
  keyboardPixelWidth = totalWidth;
  const keyboardEl = document.createElement('div');
  keyboardEl.className = 'keyboard';
  keyboardEl.style.width = totalWidth + 'px';
  keyboardEl.style.height = WHITE_KEY_HEIGHT + 'px';
  for (let pitch = MIN_MIDI; pitch <= MAX_MIDI; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    const octave = Math.floor(pitch / 12) - octaveBase;
    const el = document.createElement('div');
    el.dataset.pitch = String(pitch);
    // A base class up front (`updateKeyVisuals` only ever selects elements that already
    // have it) — without this, the very first `.pkey` query after building would match
    // nothing and every key would silently stay unstyled until some later, unrelated DOM
    // change happened to touch it.
    if (WHITE_SLOT_BY_SEMITONE[pc] !== undefined) {
      const slot = octave * 7 + WHITE_SLOT_BY_SEMITONE[pc] - leftWhiteSlotOffset;
      el.className = 'pkey white';
      el.style.left = (slot * WHITE_KEY_WIDTH) + 'px';
      el.style.width = WHITE_KEY_WIDTH + 'px';
      el.style.height = WHITE_KEY_HEIGHT + 'px';
    } else {
      const slot = octave * 7 + BLACK_AFTER_WHITE_SLOT[pc] + 1 - leftWhiteSlotOffset;
      el.className = 'pkey black';
      el.style.left = (slot * WHITE_KEY_WIDTH - BLACK_KEY_WIDTH / 2) + 'px';
      el.style.width = BLACK_KEY_WIDTH + 'px';
      el.style.height = BLACK_KEY_HEIGHT + 'px';
    }
    const badge = document.createElement('span');
    badge.className = 'degree-badge';
    badge.style.display = 'none';
    el.appendChild(badge);
    // The letter/digit that plays this exact pitch (see `KEY_MAP`/`pitchToCode`) — every
    // pitch in [MIN_MIDI, MAX_MIDI] has exactly one, by construction, so this is never absent
    // within the range this loop draws. Text filled in by `refreshKeyLetterLabels()`, not
    // here — it needs to re-run standalone once the real keyboard layout resolves (see
    // `codeLabels` above), without rebuilding the whole keyboard again.
    const code = pitchToCode[pitch];
    if (code) {
      el.dataset.keyCode = code;
      const letter = document.createElement('span');
      letter.className = 'key-letter';
      // Re-centers on C/F/E/B's own visible white area — see `KEY_LETTER_LEFT_SHIFTED_...`'s
      // doc comment. Left as the CSS default (`left: 50%`) for D/G/A and every black key.
      if (pc === 0 || pc === 5) { letter.style.left = KEY_LETTER_LEFT_SHIFTED_TOWARD_LEFT + 'px'; }
      else if (pc === 4 || pc === 11) { letter.style.left = KEY_LETTER_LEFT_SHIFTED_TOWARD_RIGHT + 'px'; }
      el.appendChild(letter);
    }
    // Only the C of each octave gets a landmark label — not every white key.
    if (pc === 0) {
      const octaveLabel = document.createElement('span');
      octaveLabel.className = 'octave-label';
      octaveLabel.textContent = noteLabel(pitch);
      el.appendChild(octaveLabel);
    }
    keyboardEl.appendChild(el);
  }
  // Scrollable wrapper — once the page is 2 columns instead of the full page width (see
  // `.layout-columns`), the piano is commonly wider than its own column; this lets it scroll
  // horizontally within that column instead of overflowing the whole layout.
  const scrollWrap = document.createElement('div');
  scrollWrap.className = 'keyboard-scroll';
  scrollWrap.appendChild(keyboardEl);
  document.getElementById('keyboard-container').appendChild(scrollWrap);
  keyboardBuilt = true;
  refreshKeyLetterLabels();
  // The mini overview + its flanking range labels only ever change alongside the real piano
  // (both driven by MIN_MIDI/MAX_MIDI) — refreshed here, not in `renderKeyboard()`'s own
  // per-poll body, for the exact same reason this whole function only runs on a deliberate
  // octave change rather than every ~200ms tick: a click/tap on the mini-piano's own SVG must
  // survive until its (synchronous, same-tick) handling finishes, same principle as the piano
  // keys above even though this SVG doesn't track a held gesture across ticks like they do.
  // Labels set FIRST, then their own individual widths summed (NOT `#octave-container`'s own
  // `getBoundingClientRect()` — that measures the row's OUTER box, already stretched to match
  // `keyboardPixelWidth` by `#keyboard-align-wrapper`'s `align-items: stretch`, which made a
  // first version of this measure ~792px of "overhead" out of a 792px-wide piano regardless of
  // how short the labels actually were, collapsing the mini-piano to its `20`-minimum clamp —
  // caught by comparing the rendered screenshot against the target mockup, not by inspection.
  // Individual flex-item children size to their OWN content along the row's main axis
  // regardless of the row's own stretched total width, so summing just the label/arrow
  // elements (skipping the empty `#mini-piano-container` span) plus the gaps between all of
  // them gives the real overhead. See `renderMiniPianoOverview`'s own comment for why the SVG's
  // target width is the piano's width MINUS this overhead, not the piano's width directly.
  document.getElementById('octave-min-label').textContent = noteLabel(MIN_MIDI);
  document.getElementById('octave-max-label').textContent = noteLabel(MAX_MIDI);
  const octaveContainerEl = document.getElementById('octave-container');
  const octaveGapPx = parseFloat(getComputedStyle(octaveContainerEl).columnGap) || 0;
  let octaveOverheadWidth = octaveGapPx * (octaveContainerEl.children.length - 1);
  Array.from(octaveContainerEl.children).forEach(child => {
    if (child.id !== 'mini-piano-container') octaveOverheadWidth += child.getBoundingClientRect().width;
  });
  const miniPianoTargetWidth = keyboardPixelWidth ? Math.max(20, keyboardPixelWidth - octaveOverheadWidth) : 0;
  document.getElementById('mini-piano-container').innerHTML = renderMiniPianoOverview(miniPianoTargetWidth);
}

function refreshKeyLetterLabels() {
  document.querySelectorAll('#keyboard-container .pkey').forEach(el => {
    const letter = el.querySelector('.key-letter');
    if (!letter) return;
    letter.textContent = codeLabels[el.dataset.keyCode] || '';
  });
}

// "C4", "F#3", etc. — reuses the wheel's own `NOTE_NAMES` rather than a second note-name
// table, for the octave landmark labels and the octave-controls range readout.
function noteLabel(pitch) {
  const pc = ((pitch % 12) + 12) % 12;
  const octave = Math.floor(pitch / 12) - 1;
  return NOTE_NAMES[pc] + octave;
}

function updateKeyVisuals() {
  document.querySelectorAll('#keyboard-container .pkey').forEach(el => {
    const pitch = parseInt(el.dataset.pitch, 10);
    const pc = ((pitch % 12) + 12) % 12;
    el.className = keyClasses(pitch, pc);
    const badge = el.querySelector('.degree-badge');
    const role = roles[pc];
    if (role) {
      badge.style.display = '';
      badge.style.background = role.color;
      badge.style.color = role.textColor;
      badge.textContent = role.degree;
    } else {
      badge.style.display = 'none';
    }
  });
}

let activeVKTab = 'clavier'; // 'clavier' | 'infos'
function setVKTab(tab) {
  activeVKTab = tab;
  document.getElementById('clavier-tab').style.display = tab === 'clavier' ? '' : 'none';
  document.getElementById('infos-tab').style.display = tab === 'infos' ? '' : 'none';
  document.querySelectorAll('#vk-tab-bar .tab').forEach(el => el.classList.toggle('active', el.dataset.tab === tab));
}

function renderKeyboard() {
  if (!document.getElementById('keyboard-container')) {
    // Two tabs: "Clavier" keeps every bit of graphical/interactive content (guide, wheel,
    // octave overview + piano + staff + chord/mode panel); "Infos" holds the identity/settings
    // line and the instructional hint text — moved out of the way so "Clavier" has more room,
    // per the user's own ask. Both tabs' DOM is built once and always kept up to date every
    // poll below (same as everything else on this page) — only `display` toggles with the
    // active tab, not a from-scratch re-render, since this page already updates sub-containers
    // in place rather than rebuilding one big HTML string per poll (unlike the read-only
    // console, see `StaticAssets.swift`).
    document.getElementById('app').innerHTML =
      '<div id="vk-tab-bar" class="tab-bar">' +
      `<a class="tab active" data-tab="clavier" onclick="setVKTab('clavier')">${t('tabClavier')}</a>` +
      `<a class="tab" data-tab="infos" onclick="setVKTab('infos')">${t('tabInfos')}</a>` +
      '</div>' +
      '<div id="clavier-tab">' +
      '<div id="responsive-scale-clip">' +
      '<div id="layout-columns" class="layout-columns">' +
      '<div class="layout-col-left">' +
      '<div id="guide-container"></div>' +
      '<div id="wheel-container"></div>' +
      '</div>' +
      '<div class="layout-col-right">' +
      '<div id="keyboard-align-wrapper" class="keyboard-align-wrapper">' +
      '<div id="octave-container" class="octave-controls">' +
      '<b id="octave-min-label"></b>' +
      '<a class="octave-arrow" onclick="shiftOctave(-1)">◂</a>' +
      '<span id="mini-piano-container"></span>' +
      '<a class="octave-arrow" onclick="shiftOctave(1)">▸</a>' +
      '<b id="octave-max-label"></b>' +
      '</div>' +
      '<div id="keyboard-container"></div>' +
      '<div id="staff-container"></div>' +
      '<div id="info-container"></div>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '</div>' +
      '<div id="infos-tab" style="display:none">' +
      `<h1>${t('vkHeading')}</h1>` +
      '<div id="identity-container"></div>' +
      `<div class="hint">${t('vkHint')}</div>` +
      '</div>';
  }
  ensureKeyboardBuilt();
  applyResponsiveScale();
  const layoutLabel = keyboardLayout === 'qwertz' ? 'QWERTZ' : 'QWERTY';
  document.getElementById('identity-container').innerHTML =
    `<div class="identity">${t('vkVousPrefix')}<b>${alias}</b> — <a onclick="renameIdentity()">${t('vkChanger')}</a>` +
    `${t('vkDispositionClavierPrefix')}<b>${layoutLabel}</b> — <a onclick="toggleKeyboardLayout()">${t('vkChanger')}</a></div>`;
  // Skipped entirely (not just "kept identical") while a wheel-cell press is in flight — see
  // `wheelChordActiveCount`'s doc comment. `guide-container` has no such touch/click state of
  // its own (just text), so it's always safe to update every poll.
  if (wheelChordActiveCount === 0) {
    document.getElementById('wheel-container').innerHTML = wheelHTML;
  }
  document.getElementById('guide-container').innerHTML = guideInfoHTML;
  document.getElementById('staff-container').innerHTML = staffHTML;
  document.getElementById('info-container').innerHTML =
    `<div class="field">${chordLine}</div>` + (modeLine ? `<div class="field">${modeLine}</div>` : '');
  updateKeyVisuals();
}

// Pointer/pitch resolution is by DOM lookup (`data-pitch`), not by tracking coordinates —
// works identically for mouse and touch targets.
function pitchFromTarget(el) {
  const key = el && el.closest ? el.closest('.pkey') : null;
  return key ? parseInt(key.dataset.pitch, 10) : null;
}

// Mouse: only one pointer, so at most one note (or one wheel chord) at a time — mouseup
// anywhere (not just on the key/cell itself) releases it, so dragging off while the button
// is still down doesn't leave a stuck note.
let mouseHeldPitch = null;
let mouseHeldWheelPitches = [];
let mouseHeldWheelEl = null;
document.addEventListener('mousedown', e => {
  const pitch = pitchFromTarget(e.target);
  if (pitch !== null) {
    e.preventDefault();
    mouseHeldPitch = pitch;
    noteOn(pitch);
    return;
  }
  const cell = wheelCellFromTarget(e.target);
  if (cell !== null) {
    e.preventDefault();
    mouseHeldWheelPitches = cell.pitches;
    mouseHeldWheelEl = cell.el;
    wheelChordActiveCount++;
    cell.el.classList.add('pressed');
    cell.pitches.forEach(noteOn);
    return;
  }
  // A single fire-and-forget jump, not a held gesture — no mouseup counterpart needed, unlike
  // the two cases above.
  const miniSvg = e.target.closest ? e.target.closest('svg.mini-piano') : null;
  if (miniSvg) jumpOctaveFromMiniPianoClick(miniSvg, e.clientX);
});
document.addEventListener('mouseup', () => {
  if (mouseHeldPitch !== null) { noteOff(mouseHeldPitch); mouseHeldPitch = null; }
  if (mouseHeldWheelPitches.length) {
    mouseHeldWheelPitches.forEach(noteOff);
    mouseHeldWheelPitches = [];
    mouseHeldWheelEl.classList.remove('pressed');
    mouseHeldWheelEl = null;
    wheelChordActiveCount--;
  }
});

// Touch: genuinely multi-touch — each `Touch` has a stable `identifier` across its own
// start/end, tracked independently so chords via several fingers (or several people on an
// iPad) work correctly. Kept as two separate maps (piano pitch vs. wheel chord) rather than
// one, since a wheel touch needs to remember its own element too (to un-highlight it) and a
// piano touch doesn't.
const activeTouches = new Map(); // identifier -> pitch
const activeWheelTouches = new Map(); // identifier -> {pitches, el}
document.addEventListener('touchstart', e => {
  e.preventDefault();
  for (const touch of e.changedTouches) {
    const pitch = pitchFromTarget(touch.target);
    if (pitch !== null) {
      activeTouches.set(touch.identifier, pitch);
      noteOn(pitch);
      continue;
    }
    const cell = wheelCellFromTarget(touch.target);
    if (cell !== null) {
      activeWheelTouches.set(touch.identifier, cell);
      wheelChordActiveCount++;
      cell.el.classList.add('pressed');
      cell.pitches.forEach(noteOn);
      continue;
    }
    const miniSvg = touch.target.closest ? touch.target.closest('svg.mini-piano') : null;
    if (miniSvg) jumpOctaveFromMiniPianoClick(miniSvg, touch.clientX);
  }
}, { passive: false });
function endTouch(e) {
  e.preventDefault();
  for (const touch of e.changedTouches) {
    const pitch = activeTouches.get(touch.identifier);
    if (pitch !== undefined) {
      activeTouches.delete(touch.identifier);
      noteOff(pitch);
    }
    const cell = activeWheelTouches.get(touch.identifier);
    if (cell === undefined) continue;
    activeWheelTouches.delete(touch.identifier);
    cell.el.classList.remove('pressed');
    cell.pitches.forEach(noteOff);
    wheelChordActiveCount--;
  }
}
document.addEventListener('touchend', endTouch, { passive: false });
document.addEventListener('touchcancel', endTouch, { passive: false });

// Computer keyboard: `downCodes` dedupes the browser's own auto-repeat (a held key fires
// `keydown` over and over) so a sustained key press doesn't hammer `/note-on` — the actual
// sustain is real here (unlike the terminal), since a browser genuinely reports `keyup`.
// Keyed by `e.code` (physical position), not `e.key` (produced character) — see `KEY_MAP`'s
// own doc comment for why.
const downCodes = new Set();
// `<`/`-`/`ArrowLeft`/`ArrowRight` shortcuts for `shiftOctave()`, mirroring the ◂/▸ arrows —
// `IntlBackslash` is the ISO "102nd key" immediately left of the bottom-row's first letter
// (Z, printed "Y" on a QWERTZ keycap — this is genuinely absent on US ANSI keyboards, which
// have no key there at all, so this particular shortcut just won't fire on one; the ◂ arrow
// and `ArrowLeft` always still work). `Slash` is the key right before the right Shift,
// present on every layout (produces "/" on QWERTY, "-" on QWERTZ) — both are fixed PHYSICAL
// positions, independent of the `keyboardLayout` Y/Z toggle above, so no branching needed here.
const OCTAVE_SHORTCUT_DELTA = { IntlBackslash: -1, Slash: 1, ArrowLeft: -1, ArrowRight: 1 };
// Deliberately a SEPARATE set from `downCodes`, not a shared one: `shiftOctave()` calls
// `clearAllLocalPressState()`, which clears `downCodes` (correctly — the whole visible range
// is about to change, so any note key logically "un-presses"). If this guard shared that same
// set, `shiftOctave()` would wipe out its own just-added entry on every call, and a held
// shortcut key would auto-repeat through every octave stop (or guide step) in one fast burst
// instead of moving one step per physical keydown. Also guards `Tab`/`Shift+Tab` below, for
// the same reason (advancing the guide, like `shiftOctave()`, is a one-per-keydown action).
const downActionCodes = new Set();
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') { releaseAll(); return; }
  if (OCTAVE_SHORTCUT_DELTA[e.code] !== undefined) {
    if (downActionCodes.has(e.code)) return;
    downActionCodes.add(e.code);
    e.preventDefault();
    shiftOctave(OCTAVE_SHORTCUT_DELTA[e.code]);
    return;
  }
  // Guide navigation — only while a guide is actually running (see `refresh()`'s own
  // `guideIsActive`); otherwise `Tab` keeps its normal browser behavior (cycling focus).
  // Global, like `shiftOctave()` isn't: this moves the ONE shared guide every client sees,
  // mirroring the terminal's own left/right arrows on its `.guide` screen.
  if (e.code === 'Tab' && guideIsActive) {
    if (downActionCodes.has(e.code)) return;
    downActionCodes.add(e.code);
    e.preventDefault();
    sendGuideAdvance(e.shiftKey ? -1 : 1);
    return;
  }
  const pitch = KEY_MAP[e.code];
  if (pitch === undefined) return;
  if (downCodes.has(e.code)) return;
  downCodes.add(e.code);
  noteOn(pitch);
});
document.addEventListener('keyup', e => {
  downCodes.delete(e.code);
  downActionCodes.delete(e.code);
  const pitch = KEY_MAP[e.code];
  if (pitch === undefined) return;
  noteOff(pitch);
});

// Mirrors `state.noteColors` onto the CSS custom properties `.pkey.*` rules above read from
// — same as `StaticAssets.swift`'s own copy of this function.
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
  try {
    const response = await fetch('/state?' + identityQuery(), { cache: 'no-store' });
    const state = await response.json();
    if (state.palette && state.palette.length === 12) PITCH_CLASS_COLORS = state.palette;
    if (state.paletteTextColors && state.paletteTextColors.length === 12) PITCH_CLASS_TEXT_COLORS = state.paletteTextColors;
    applyNoteColors(state.noteColors);
    // Unlike `StaticAssets.swift` (which only ever rebuilds its Menu tab from a `menuBuilt`
    // flag), THIS page's whole tab bar/hint/heading skeleton is built once and never revisited
    // (see `renderKeyboard()`'s own `!document.getElementById('keyboard-container')` guard) — so
    // a language change has to clear it out entirely to force that one-time skeleton (and the
    // piano itself, via `keyboardBuilt`) to rebuild in the new language on the very next
    // `renderKeyboard()` call below.
    if (state.language && state.language !== currentLanguage) {
      currentLanguage = state.language;
      document.documentElement.lang = currentLanguage;
      document.title = t('titleClavierVirtuel');
      document.getElementById('app').innerHTML = '';
      keyboardBuilt = false;
    }
    const track = state.track;
    if (track) {
      heldPitches = new Set(track.heldPitches || []);
      chordRoot = track.chordRoot;
      chordTones = new Set(track.chordTones || []);
      roles = {};
      (track.modeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc], textColor: PITCH_CLASS_TEXT_COLORS[pc] }; });
      chordLine = track.chordLabel || `<span class="empty">${t('placeholderAucunAccordVK')}</span>`;
      modeLine = track.modesLabel || '';
      staffHTML = renderStaffSVG(track.recentChordEvents || [], keyboardPixelWidth);
    } else {
      heldPitches = new Set(); chordRoot = null; chordTones = new Set(); roles = {};
      chordLine = `<span class="empty">${t('placeholderPisteNonInitialisee')}</span>`;
      modeLine = '';
      staffHTML = renderStaffSVG([], keyboardPixelWidth);
    }
    // While a guide is running, the degree-line (degree badges) switches to ITS mode's notes
    // instead of this track's own recognized mode — "présente le clavier avec les notes du
    // mode [du guide]" — but held/chord/root coloring above stays this track's own, personal
    // feedback either way. `state.guide` is only present at all while a guide is active (see
    // `ImprovSession.handleVirtualKeyboardRequest`'s doc comment); `state.wheel` is always
    // present now, but its mode-relative parts only render while `guideIsActive`.
    guideIsActive = !!(state.guide && state.guide.isActive);
    if (guideIsActive) {
      roles = {};
      (state.guide.currentModeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc], textColor: PITCH_CLASS_TEXT_COLORS[pc] }; });
      const steps = (state.guide.steps || []).map(step => step.isCurrent ? `<b>[${step.label}]</b>` : step.label).join(' ');
      const progression = state.guide.currentChordProgression || [];
      const progressionPrefix = state.guide.currentChordProgressionName
        ? t('formatSuiteAccordsNamed', state.guide.currentChordProgressionName)
        : t('fieldSuiteAccords');
      const progressionHTML = progression.length
        ? `<div class="field">${progressionPrefix}: ${progression.map(
            (c, i) => i === state.guide.currentChordIndex ? `<b>[${c.label}]</b>` : c.label
          ).join(' - ')}</div>`
        : '';
      // Layout ported from `StaticAssets.swift`'s own `renderGuide` (see there for the full
      // reasoning): one heading for both keyboards (not one per keyboard), both arrow hints
      // consolidated into a single italic line, and a 3-column row — notation (left) — the two
      // stacked keyboards (middle) — guitar tab (right) — instead of everything stacked
      // top-to-bottom.
      const modeTones = state.guide.currentModeTones || [];
      const modeRootPC = modeTones.length ? modeTones[0] : null;
      const hasChord = state.guide.currentChordIndex !== null && state.guide.currentChordIndex !== undefined;

      let keyboardsHTML = `<h3>${t('headingModeEtAccordGuideWeb')}</h3>`
        + guideReferenceKeyboardHTML(60, 83, modeRootPC, modeTones, 'mode-root', 'mode-tone');
      if (hasChord) {
        keyboardsHTML += guideReferenceKeyboardHTML(60, 83, state.guide.currentChordRoot ?? null, state.guide.currentChordTones || [], 'root', 'tone');
      }

      const notationHTML = hasChord
        ? `<h3>${t('headingPartitionGuideWeb')}</h3><div class="guide-col-fill">`
          + renderStaffSVG([chordStaffEvent(state.guide.currentChordRoot, state.guide.currentChordTones)], 84, -10) + `</div>`
        : '';
      const tabHTML = hasChord
        ? `<h3>${t('headingTablatureGuideWeb')}</h3><div class="guide-col-fill">${guitarChordDiagramHTML(state.guide.currentChordGuitarDiagram)}</div>`
        : '';
      const guideLayoutHTML = `<div class="guide-layout">`
        + `<div class="guide-col-notation">${notationHTML}</div>`
        + `<div class="guide-col-keyboards">${keyboardsHTML}</div>`
        + `<div class="guide-col-tab">${tabHTML}</div>`
        + `</div>`;

      guideInfoHTML = `<h2>${t('vkHeadingGuide')}</h2><br>` + `<div class="field">${steps}</div>` + progressionHTML
        + `<div class="field guide-hint">${t('hintNavigationGuideWeb')}</div>` + guideLayoutHTML;
    } else {
      guideInfoHTML = '';
    }
    const progressionChords = guideIsActive ? (state.guide.currentChordProgression || []).filter(c => c.quality) : [];
    wheelHTML = renderWheel(state.wheel, guideIsActive, detectedChordFrom(track), progressionChords);
  } catch {
    chordLine = `<span class="empty">${t('fallbackConnexionPerdueDetail')}</span>`;
    modeLine = '';
  }
  renderKeyboard();
}

refresh();
setInterval(refresh, 200);
"""
