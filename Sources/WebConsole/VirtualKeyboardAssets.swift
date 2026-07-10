/// The two static assets served by the virtual-keyboard HTTP server (`GET /` and `GET
/// /app.js`) — see `ImprovSession.startVirtualKeyboard`. Deliberately a separate page/module
/// concern from `StaticAssets.swift`'s read-only web console: this one is interactive (typed
/// keys, mouse clicks, touches all play notes — including clicking/tapping a circle-of-fifths
/// wheel cell, while a guide is active, to play that chord's triad), so keeping it in its own
/// file/route means the always-on console page never has to reason about input handling at
/// all — its own `renderWheel` has no click handling, deliberately.
///
/// **Computer keyboard**: two overlaid row-pairs (`KEY_MAP`) cover ~2.3 octaves at once
/// (bass: number row + `qwertyuiop`; treble, continuing right above it: `asdfgh` + the bottom
/// letter row), mapped by physical position (`KeyboardEvent.code`) rather than by character —
/// stays correct on a QWERTZ/AZERTY/etc. keyboard, not just the US layout the letters are
/// named after. `shiftOctave()` (the on-screen Octave -/+ buttons) slides this whole window
/// by a full octave at a time across `OCTAVE_STOPS` (C0..C6), rebuilding the on-screen piano
/// to match every time — see `ensureKeyboardBuilt`/`recomputeKeyRange`.
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
/// see `StaticAssets.swift`'s own contract comment), `guide`/`wheel` only while a guide is
/// actually running (see `ImprovSession.handleVirtualKeyboardRequest`'s doc comment) — the
/// role-line (degree badges) switches to the guide's own mode while active, but held/chord/
/// root coloring stays this client's own personal feedback either way:
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
/// `guide`/`wheel` (a `nil` `Optional` under Swift's synthesized `Encodable`) are OMITTED
/// from the JSON entirely while no guide is running, not present as an explicit `null` —
/// `app.js` only ever checks `state.guide && state.guide.isActive`, which is `undefined`-safe
/// either way. `palette`/`paletteTextColors` are always present, unlike those two — the 12 hex
/// colors (and matching legible text colors, see `ColorPalette.textColors`'s doc comment) of
/// whichever `ColorPalette` is currently active (`ImprovSession.activeColorPalette`), index 0
/// = C ... 11 = B, sent on every poll so switching palettes from the menu updates this page
/// within one refresh cycle — see `app.js`'s own `PITCH_CLASS_COLORS`/`PITCH_CLASS_TEXT_COLORS`.
///
/// `GET /note-on?pitch=<midi>&client=...&name=...` / `GET /note-off?pitch=<midi>&client=
/// ...&name=...` / `GET /release-all?client=...&name=...` are the only ways this page
/// *changes* anything — plain `GET`s with everything in the query string (not a POST body):
/// `WebConsole`'s hand-rolled HTTP server only ever parses a request line, never a body (see
/// `HTTPWireFormat`'s doc comment), and a one-off query string is simpler than teaching it to.
public let virtualKeyboardIndexHTML = """
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>JamShack — Clavier virtuel</title>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no">
<style>
  body { background: #111; color: #ddd; font-family: -apple-system, sans-serif; margin: 1.5rem; }
  h1 { font-size: 1.1rem; color: #888; font-weight: normal; }
  .field { color: #888; }
  .field b { color: #ddd; }
  .empty { color: #666; font-style: italic; }
  .hint { color: #666; font-size: 0.85rem; margin-top: 0.3rem; }
  .identity { color: #666; font-size: 0.85rem; }
  .identity a { color: #6cf; cursor: pointer; text-decoration: underline; }
  .octave-controls { color: #888; font-size: 0.85rem; margin: 0.4rem 0; }
  .octave-controls b { color: #ddd; }
  .octave-controls button {
    background: #333; color: #ddd; border: 1px solid #555; border-radius: 4px;
    width: 1.7rem; height: 1.7rem; font-size: 1rem; line-height: 1; cursor: pointer;
  }
  .octave-controls button:hover { background: #444; }
  .wheel { margin: 0.5rem 0 1rem; display: block; width: 100%; max-width: 520px; height: auto; }
  .wheel-disk { fill: #fff; }
  .wheel-grid-line { stroke: #000; stroke-width: 1; }
  .wheel-cell-shape { stroke: #333; stroke-width: 1; cursor: pointer; }
  .wheel-cell-shape.pressed { filter: brightness(0.7); }
  .wheel-diatonic-boundary { fill: none; stroke: #1a3a6b; stroke-width: 5; stroke-linejoin: round; }
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
  .pkey.root { background: #e91e63 !important; }
  .pkey.tone { background: #fdd835 !important; }
  .pkey.outside { background: #4caf50 !important; }
  .pkey.held { background: #bbb !important; }
  .pkey.pressed { filter: brightness(0.7); }
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
    font-size: 10px; color: #999; pointer-events: none;
  }
</style>
</head>
<body>
<h1>JamShack — Clavier virtuel (souris/tactile/clavier ordinateur)</h1>
<div id="app"></div>
<script src="/app.js"></script>
</body>
</html>
"""

public let virtualKeyboardAppJS = """
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
const BASS_WHITE_CODES = ['KeyQ', 'KeyW', 'KeyE', 'KeyR', 'KeyT', 'KeyY', 'KeyU', 'KeyI', 'KeyO', 'KeyP'];
// G A B C D E F G A B, relative to the octave anchor (`root`, below) — ends on a B so the
// treble register can start clean on the very next natural note, a C (see TREBLE_WHITE_OFFSETS).
const BASS_WHITE_OFFSETS = [-5, -3, -1, 0, 2, 4, 5, 7, 9, 11];
const BASS_BLACK_CODES = ['Digit2', 'Digit3', 'Digit5', 'Digit6', 'Digit8', 'Digit9', 'Digit0'];
// Digit1/4/7 are skipped (no key maps to them) — Digit1 sits above the Q-side edge, Digit4/7
// sit above the two "natural" gaps (B-C, E-F) that have no black key at all.
const BASS_BLACK_OFFSETS = [-4, -2, 1, 3, 6, 8, 10];
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
// ~2.3-octave window the two row-pairs above cover can slide across a real 88-key piano's
// full range instead of being stuck wherever it started. `root` is the reference C landmark
// (`KeyR`, the bass register's 4th white key) — NOT the window's own lowest note, which sits
// 5 semitones below it (see `BASS_WHITE_OFFSETS`).
const OCTAVE_STOPS = [12, 24, 36, 48, 60, 72, 84];
let octaveIndex = 3; // C3 — close to the old fixed layout's own MIN_MIDI, kept as the default
let MIN_MIDI, MAX_MIDI, KEY_MAP, pitchToCode;
function recomputeKeyRange() {
  const root = OCTAVE_STOPS[octaveIndex];
  MIN_MIDI = root - 5; // the bass register's own lowest note (a G)
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

// Slides the whole bass+treble window up/down by one of the `OCTAVE_STOPS`, then rebuilds the
// on-screen piano to match — "ajuster la zone affichee en fonction de la zone jouable au
// clavier". Releases everything first: the visible range is about to change entirely, so
// whatever was held may not even have an on-screen key left afterward.
function shiftOctave(delta) {
  const nextIndex = octaveIndex + delta;
  if (nextIndex < 0 || nextIndex >= OCTAVE_STOPS.length) return;
  clearAllLocalPressState();
  sendNoteEvent('/release-all');
  octaveIndex = nextIndex;
  recomputeKeyRange();
  keyboardBuilt = false;
  renderKeyboard();
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
  alias = (prompt('Quel nom afficher sur ce clavier virtuel ?', '') || '').trim() || 'Invite';
  localStorage.setItem('vkAlias', alias);
}
function renameIdentity() {
  const next = (prompt('Nouveau nom :', alias) || '').trim();
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

function renderWheel(wheel) {
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
    if (column.modeName) {
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
      const symbol = NOTE_NAMES[cell.pitchClass] + CHORD_SUFFIX[cell.quality];
      svg += `<text class="wheel-cell-symbol" x="${pos.x}" y="${pos.y + 1}" fill="${textColor}">${symbol}</text>`;
      svg += `<text class="wheel-cell-degree" x="${pos.x}" y="${pos.y + 9}" fill="${textColor}">${degreeSVGMarkup(cell.relativeDegree)}</text>`;
    });
  });
  svg += `<path class="wheel-diatonic-boundary" d="${diatonicBoundaryPath(wheel, cx, cy)}" />`;
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
let infoLine = '<span class="empty">(aucune note)</span>';
let guideHTML = '';   // guide title/steps + wheel, only while a guide is active — see refresh()

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
function ensureKeyboardBuilt() {
  if (keyboardBuilt) return;
  // Only reached right after `shiftOctave()` sets `keyboardBuilt = false` (a deliberate,
  // one-off user action, never something a periodic `refresh()` tick triggers on its own —
  // see `wheelChordActiveCount`'s doc comment for why that distinction matters) — safe to
  // drop whatever the previous range's keyboard div was.
  document.getElementById('keyboard-container').innerHTML = '';
  const octaveCount = Math.ceil((MAX_MIDI - MIN_MIDI + 1) / 12);
  const totalWidth = octaveCount * 7 * WHITE_KEY_WIDTH;
  const keyboardEl = document.createElement('div');
  keyboardEl.className = 'keyboard';
  keyboardEl.style.width = totalWidth + 'px';
  keyboardEl.style.height = WHITE_KEY_HEIGHT + 'px';
  // Octave number relative to a fixed reference (pitch 0), not to `MIN_MIDI` itself — `MIN_MIDI`
  // is no longer always a C (the bass register now starts on a G, see `BASS_WHITE_OFFSETS`),
  // and computing `octave` from `pitch - MIN_MIDI` silently assumed it was: G2 would land in
  // "octave 0" while the very next C landed in "octave 1", pushing it 7 white-key slots to the
  // RIGHT of where it belongs and scrambling the whole keyboard's left-to-right order.
  const octaveBase = Math.floor(MIN_MIDI / 12);
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
      const slot = octave * 7 + WHITE_SLOT_BY_SEMITONE[pc];
      el.className = 'pkey white';
      el.style.left = (slot * WHITE_KEY_WIDTH) + 'px';
      el.style.width = WHITE_KEY_WIDTH + 'px';
      el.style.height = WHITE_KEY_HEIGHT + 'px';
    } else {
      const slot = octave * 7 + BLACK_AFTER_WHITE_SLOT[pc] + 1;
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
  document.getElementById('keyboard-container').appendChild(keyboardEl);
  keyboardBuilt = true;
  refreshKeyLetterLabels();
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

function renderKeyboard() {
  if (!document.getElementById('keyboard-container')) {
    document.getElementById('app').innerHTML =
      '<div id="identity-container"></div>' +
      '<div id="guide-container"></div>' +
      '<div id="info-container"></div>' +
      '<div id="octave-container" class="octave-controls">Octave : ' +
      '<button onclick="shiftOctave(-1)">-</button> <b id="octave-range-label"></b> ' +
      '<button onclick="shiftOctave(1)">+</button></div>' +
      '<div id="keyboard-container"></div>' +
      '<div class="hint">Lettres affichees sur les touches (positionnelles — fonctionne quel que soit ton agencement clavier). Octave -/+ : glisse la zone jouable. Echap : relache tout.</div>';
  }
  ensureKeyboardBuilt();
  const layoutLabel = keyboardLayout === 'qwertz' ? 'QWERTZ' : 'QWERTY';
  document.getElementById('identity-container').innerHTML =
    `<div class="identity">Vous : <b>${alias}</b> — <a onclick="renameIdentity()">changer</a>` +
    ` · Disposition clavier : <b>${layoutLabel}</b> — <a onclick="toggleKeyboardLayout()">changer</a></div>`;
  document.getElementById('octave-range-label').textContent = noteLabel(MIN_MIDI) + ' – ' + noteLabel(MAX_MIDI);
  // Skipped entirely (not just "kept identical") while a wheel-cell press is in flight — see
  // `wheelChordActiveCount`'s doc comment.
  if (wheelChordActiveCount === 0) {
    document.getElementById('guide-container').innerHTML = guideHTML;
  }
  document.getElementById('info-container').innerHTML = `<div class="field">Accord: <b>${infoLine}</b></div>`;
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
  if (cell === null) return;
  e.preventDefault();
  mouseHeldWheelPitches = cell.pitches;
  mouseHeldWheelEl = cell.el;
  wheelChordActiveCount++;
  cell.el.classList.add('pressed');
  cell.pitches.forEach(noteOn);
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
    if (cell === null) continue;
    activeWheelTouches.set(touch.identifier, cell);
    wheelChordActiveCount++;
    cell.el.classList.add('pressed');
    cell.pitches.forEach(noteOn);
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
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') { releaseAll(); return; }
  const pitch = KEY_MAP[e.code];
  if (pitch === undefined) return;
  if (downCodes.has(e.code)) return;
  downCodes.add(e.code);
  noteOn(pitch);
});
document.addEventListener('keyup', e => {
  downCodes.delete(e.code);
  const pitch = KEY_MAP[e.code];
  if (pitch === undefined) return;
  noteOff(pitch);
});

async function refresh() {
  try {
    const response = await fetch('/state?' + identityQuery(), { cache: 'no-store' });
    const state = await response.json();
    if (state.palette && state.palette.length === 12) PITCH_CLASS_COLORS = state.palette;
    if (state.paletteTextColors && state.paletteTextColors.length === 12) PITCH_CLASS_TEXT_COLORS = state.paletteTextColors;
    const track = state.track;
    if (track) {
      heldPitches = new Set(track.heldPitches || []);
      chordRoot = track.chordRoot;
      chordTones = new Set(track.chordTones || []);
      roles = {};
      (track.modeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc], textColor: PITCH_CLASS_TEXT_COLORS[pc] }; });
      infoLine = track.chordLabel
        ? `${track.chordLabel}${track.modesLabel ? ' — ' + track.modesLabel : ''}`
        : (track.modesLabel || '<span class="empty">(aucune note)</span>');
    } else {
      heldPitches = new Set(); chordRoot = null; chordTones = new Set(); roles = {};
      infoLine = '<span class="empty">(piste non initialisee)</span>';
    }
    // While a guide is running, the role-line (degree badges) switches to ITS mode's notes
    // instead of this track's own recognized mode — "présente le clavier avec les notes du
    // mode [du guide]" — but held/chord/root coloring above stays this track's own, personal
    // feedback either way. `state.guide`/`state.wheel` are only present at all while a guide
    // is active (see `ImprovSession.handleVirtualKeyboardRequest`'s doc comment).
    if (state.guide && state.guide.isActive) {
      roles = {};
      (state.guide.currentModeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc], textColor: PITCH_CLASS_TEXT_COLORS[pc] }; });
      const steps = (state.guide.steps || []).map(step => step.isCurrent ? `<b>[${step.label}]</b>` : step.label).join(' ');
      guideHTML = '<h2>Guide</h2>' + `<div class="field">${steps}</div>` + renderWheel(state.wheel);
    } else {
      guideHTML = '';
    }
  } catch {
    infoLine = '<span class="empty">(connexion perdue — l\\'application est-elle toujours lancee ?)</span>';
  }
  renderKeyboard();
}

refresh();
setInterval(refresh, 200);
"""
