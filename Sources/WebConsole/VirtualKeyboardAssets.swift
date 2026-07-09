/// The two static assets served by the virtual-keyboard HTTP server (`GET /` and `GET
/// /app.js`) — see `ImprovSession.startVirtualKeyboard`. Deliberately a separate page/module
/// concern from `StaticAssets.swift`'s read-only web console: this one is interactive (typed
/// keys, mouse clicks, touches all play notes), so keeping it in its own file/route means the
/// always-on console page never has to reason about input handling at all.
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
///  "wheel": { ...same shape as the web console's own "wheel" field... }}
/// ```
/// `guide`/`wheel` (a `nil` `Optional` under Swift's synthesized `Encodable`) are OMITTED
/// from the JSON entirely while no guide is running, not present as an explicit `null` —
/// `app.js` only ever checks `state.guide && state.guide.isActive`, which is `undefined`-safe
/// either way.
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
  .wheel { margin: 0.5rem 0 1rem; display: block; width: 100%; max-width: 520px; height: auto; }
  .wheel-disk { fill: #fff; }
  .wheel-grid-line { stroke: #000; stroke-width: 1; }
  .wheel-cell-shape { stroke: #333; stroke-width: 1; }
  .wheel-diatonic-boundary { fill: none; stroke: #1a3a6b; stroke-width: 5; stroke-linejoin: round; }
  .wheel-cell-symbol { font-size: 8px; font-weight: bold; text-anchor: middle; fill: #111; pointer-events: none; }
  .wheel-cell-degree { font-size: 6.5px; font-family: Georgia, 'Times New Roman', serif; text-anchor: middle; fill: #111; pointer-events: none; opacity: 0.75; }
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
    position: absolute; top: -32px; left: 50%; transform: translateX(-50%);
    width: 28px; height: 28px; border-radius: 50%;
    font-size: 15px; line-height: 28px; text-align: center; color: #111; font-weight: bold;
    pointer-events: none;
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
const MIN_MIDI = 48; // C3, same range as the terminal's/web console's own keyboards
const MAX_MIDI = 83; // B5

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
function degreeSVGMarkup(degree) {
  if (!degree.endsWith('°')) return degree;
  return `${degree.slice(0, -1)}<tspan baseline-shift="super" font-size="75%">°</tspan>`;
}
function polarPoint(cx, cy, r, index, count) {
  const angle = (2 * Math.PI * index) / count - Math.PI / 2;
  return { x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) };
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
      svg += `<text class="${cls}" x="${pos.x}" y="${pos.y}">${column.modeName}</text>`;
    }
    column.cells.forEach(cell => {
      const r = WHEEL_RING_RADIUS[cell.quality];
      const pos = polarPoint(cx, cy, r, index, count);
      const color = PITCH_CLASS_COLORS[cell.pitchClass];
      const size = 18;
      const rotateDeg = (360 * index) / count;
      if (cell.shape === 'square') {
        svg += `<g transform="rotate(${rotateDeg} ${pos.x} ${pos.y})"><rect class="wheel-cell-shape" x="${pos.x - size}" y="${pos.y - size}" width="${size * 2}" height="${size * 2}" fill="${color}" /></g>`;
      } else {
        svg += `<circle class="wheel-cell-shape" cx="${pos.x}" cy="${pos.y}" r="${size}" fill="${color}" />`;
      }
      const symbol = NOTE_NAMES[cell.pitchClass] + CHORD_SUFFIX[cell.quality];
      svg += `<text class="wheel-cell-symbol" x="${pos.x}" y="${pos.y + 1}">${symbol}</text>`;
      svg += `<text class="wheel-cell-degree" x="${pos.x}" y="${pos.y + 9}">${degreeSVGMarkup(cell.relativeDegree)}</text>`;
    });
  });
  svg += `<path class="wheel-diatonic-boundary" d="${diatonicBoundaryPath(wheel, cx, cy)}" />`;
  svg += '</svg>';
  return svg;
}

// Hand-mirrors `MusicTheoryKit.PitchClassPalette.hex` — see this module's JSON-contract
// comment above for the "no compiler-enforced contract, kept in sync by hand" convention.
const PITCH_CLASS_COLORS = [
  '#e6194B', '#f58231', '#ffe119', '#bfef45', '#3cb44b', '#42d4f4',
  '#4363d8', '#911eb4', '#f032e6', '#fabed4', '#469990', '#9A6324',
];

// Real-piano geometry, matching `StaticAssets.swift`'s own `keyboardHTML` (see there for the
// white/black-slot reasoning) — kept in sync by hand since the two pages are otherwise
// independent (this one is interactive, that one is read-only). Twice the read-only page's
// own key size: this one needs to be comfortably clickable/touchable, not just readable.
const WHITE_KEY_WIDTH = 44, WHITE_KEY_HEIGHT = 144, BLACK_KEY_WIDTH = 26, BLACK_KEY_HEIGHT = 92;
const WHITE_SLOT_BY_SEMITONE = { 0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6 };
const BLACK_AFTER_WHITE_SLOT = { 1: 0, 3: 1, 6: 3, 8: 4, 10: 5 };

// Same "Musical Typing"-style layout as the terminal's own computer-keyboard track (see
// `computerKeyboardNoteMap` in `JamShack/main.swift`) — kept in sync by hand, same convention
// as `PITCH_CLASS_COLORS` above. Unlike the terminal (which can't see key-*up*, so it fakes a
// 300ms pluck per keystroke), a real keyup event is available here — held keys genuinely
// sustain until released.
const COMPUTER_KEY_MAP = {
  a: 60, w: 61, s: 62, e: 63, d: 64, f: 65, t: 66, g: 67,
  y: 68, h: 69, u: 70, j: 71, k: 72, o: 73, l: 74, p: 75, ';': 76,
};

let roles = {};          // pitch class -> {degree, color}, from the last /state poll
let heldPitches = new Set();
let chordRoot = null;
let chordTones = new Set();
let infoLine = '<span class="empty">(aucune note)</span>';
let guideHTML = '';   // guide title/steps + wheel, only while a guide is active — see refresh()

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
// The panic button: asks the *session* to release whatever it thinks this track is holding,
// rather than replaying this client's own (possibly already-wrong) idea of what's down —
// clears local tracking too, so typed/touched keys don't look stuck after this even if the
// server had nothing left to release.
function releaseAll() {
  pressedLocally.clear();
  downKeys.clear();
  activeTouches.clear();
  mouseHeldPitch = null;
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

function keyboardHTML() {
  const octaveCount = Math.ceil((MAX_MIDI - MIN_MIDI + 1) / 12);
  const totalWidth = octaveCount * 7 * WHITE_KEY_WIDTH;
  let whiteHTML = '', blackHTML = '';
  for (let pitch = MIN_MIDI; pitch <= MAX_MIDI; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    const octave = Math.floor((pitch - MIN_MIDI) / 12);
    const role = roles[pc];
    const badge = role ? `<span class="degree-badge" style="background:${role.color}">${role.degree}</span>` : '';
    const cls = keyClasses(pitch, pc);
    if (WHITE_SLOT_BY_SEMITONE[pc] !== undefined) {
      const slot = octave * 7 + WHITE_SLOT_BY_SEMITONE[pc];
      const x = slot * WHITE_KEY_WIDTH;
      whiteHTML += `<div class="${cls}" data-pitch="${pitch}" style="left:${x}px; width:${WHITE_KEY_WIDTH}px; height:${WHITE_KEY_HEIGHT}px;">${badge}</div>`;
    } else {
      const slot = octave * 7 + BLACK_AFTER_WHITE_SLOT[pc] + 1;
      const x = slot * WHITE_KEY_WIDTH - BLACK_KEY_WIDTH / 2;
      blackHTML += `<div class="${cls}" data-pitch="${pitch}" style="left:${x}px; width:${BLACK_KEY_WIDTH}px; height:${BLACK_KEY_HEIGHT}px;">${badge}</div>`;
    }
  }
  return `<div class="keyboard" style="width:${totalWidth}px; height:${WHITE_KEY_HEIGHT}px;">${whiteHTML}${blackHTML}</div>`;
}

function renderKeyboard() {
  document.getElementById('app').innerHTML =
    `<div class="identity">Vous : <b>${alias}</b> — <a onclick="renameIdentity()">changer</a></div>` +
    guideHTML +
    `<div class="field">Accord: <b>${infoLine}</b></div>` +
    keyboardHTML() +
    '<div class="hint">Touches: A S D F G H J K L ; (blanches), W E T Y U O P (noires) — ou clique/touche directement les touches. Echap: relache tout.</div>';
}

// Pointer/pitch resolution is by DOM lookup (`data-pitch`), not by tracking coordinates —
// works identically for mouse and touch targets.
function pitchFromTarget(el) {
  const key = el && el.closest ? el.closest('.pkey') : null;
  return key ? parseInt(key.dataset.pitch, 10) : null;
}

// Mouse: only one pointer, so at most one note at a time — mouseup/mouseleave anywhere
// (not just on the key itself) releases it, so dragging off a held key while the button is
// still down doesn't leave a stuck note.
let mouseHeldPitch = null;
document.addEventListener('mousedown', e => {
  const pitch = pitchFromTarget(e.target);
  if (pitch === null) return;
  e.preventDefault();
  mouseHeldPitch = pitch;
  noteOn(pitch);
});
document.addEventListener('mouseup', () => {
  if (mouseHeldPitch !== null) { noteOff(mouseHeldPitch); mouseHeldPitch = null; }
});

// Touch: genuinely multi-touch — each `Touch` has a stable `identifier` across its own
// start/end, tracked independently so chords via several fingers (or several people on an
// iPad) work correctly.
const activeTouches = new Map(); // identifier -> pitch
document.addEventListener('touchstart', e => {
  e.preventDefault();
  for (const touch of e.changedTouches) {
    const pitch = pitchFromTarget(touch.target);
    if (pitch === null) continue;
    activeTouches.set(touch.identifier, pitch);
    noteOn(pitch);
  }
}, { passive: false });
function endTouch(e) {
  e.preventDefault();
  for (const touch of e.changedTouches) {
    const pitch = activeTouches.get(touch.identifier);
    if (pitch === undefined) continue;
    activeTouches.delete(touch.identifier);
    noteOff(pitch);
  }
}
document.addEventListener('touchend', endTouch, { passive: false });
document.addEventListener('touchcancel', endTouch, { passive: false });

// Computer keyboard: `downKeys` dedupes the browser's own auto-repeat (a held key fires
// `keydown` over and over) so a sustained key press doesn't hammer `/note-on` — the actual
// sustain is real here (unlike the terminal), since a browser genuinely reports `keyup`.
const downKeys = new Set();
document.addEventListener('keydown', e => {
  if (e.key === 'Escape') { releaseAll(); return; }
  const k = e.key.toLowerCase();
  if (downKeys.has(k)) return;
  const pitch = COMPUTER_KEY_MAP[k];
  if (pitch === undefined) return;
  downKeys.add(k);
  noteOn(pitch);
});
document.addEventListener('keyup', e => {
  const k = e.key.toLowerCase();
  downKeys.delete(k);
  const pitch = COMPUTER_KEY_MAP[k];
  if (pitch === undefined) return;
  noteOff(pitch);
});

async function refresh() {
  try {
    const response = await fetch('/state?' + identityQuery(), { cache: 'no-store' });
    const state = await response.json();
    const track = state.track;
    if (track) {
      heldPitches = new Set(track.heldPitches || []);
      chordRoot = track.chordRoot;
      chordTones = new Set(track.chordTones || []);
      roles = {};
      (track.modeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc] }; });
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
      (state.guide.currentModeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc] }; });
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
