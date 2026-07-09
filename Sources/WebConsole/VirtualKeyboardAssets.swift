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
/// **JSON contract with `AppCore.ImprovSession`**: `GET /state?client=...` returns either
/// `null` (nothing has ever pressed a key for this `client` yet) or a single track object,
/// scoped to just this one client's own track, same shape as one entry of the web console's
/// `tracks` array (see `StaticAssets.swift`'s own contract comment):
/// ```json
/// {"id": "clavier-web:<uuid>", "label": "Alice", "owner": null,
///  "heldPitches": [60, 64, 67], "chordRoot": 0, "chordTones": [0, 4, 7],
///  "modeTones": [0, 2, 4, 5, 7, 9, 11], "chordLabel": "Cmaj", "modesLabel": "C ionian",
///  "microphoneLevel": null}
/// ```
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

function noteOn(pitch) {
  if (pressedLocally.has(pitch)) return; // already down — computer keydown auto-repeats
  pressedLocally.add(pitch);
  sendNoteEvent('/note-on?pitch=' + pitch);
  renderKeyboard();
}
function noteOff(pitch) {
  if (!pressedLocally.has(pitch)) return;
  pressedLocally.delete(pitch);
  sendNoteEvent('/note-off?pitch=' + pitch);
  renderKeyboard();
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
    const track = await response.json();
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
  } catch {
    infoLine = '<span class="empty">(connexion perdue — l\\'application est-elle toujours lancee ?)</span>';
  }
  renderKeyboard();
}

refresh();
setInterval(refresh, 200);
"""
