/// The two static assets served by the web console (`GET /` and `GET /app.js`). Embedded as
/// Swift string constants rather than read from disk at runtime — avoids wiring up
/// `Bundle.module`/SwiftPM resources for two short files, and keeps them reviewable/editable
/// like any other source file.
///
/// **JSON contract with `AppCore.WebConsoleState`** (`Sources/AppCore/WebConsoleState.swift`):
/// this module has no dependency on `AppCore` (kept as dumb as `NetEngine` about the app it
/// serves), so the shape `app.js` expects from `GET /state` is a contract enforced only by
/// convention, not the compiler — keep both in sync by hand:
/// ```json
/// {
///   "lastEvent": "on pitch=60 vel=100" | null,
///   "tracks": [{
///     "id": "clavier", "label": "Piste clavier", "owner": "Bob" | null,
///     "heldPitches": [60, 64, 67],
///     "chordRoot": 0 | null, "chordTones": [0, 4, 7], "modeTones": [0, 2, 4, 5, 7, 9, 11],
///     "chordLabel": "Cmaj" | null, "modesLabel": "C ionian" | null,
///     "microphoneLevel": 0.0123 | null
///   }],
///   "playback": { "timeline": [{"label": "Dm7", "isCurrent": true}], "heldPitches": [...],
///                 "chordRoot": 2 | null, "chordTones": [...], "modeTones": [...] } | null,
///   "soundTrackPlayback": { "heldPitches": [...] } | null
/// }
/// ```
public let webConsoleIndexHTML = """
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>Music Improv Assistant — Console Web</title>
<style>
  body { background: #111; color: #ddd; font-family: -apple-system, sans-serif; margin: 1.5rem; }
  h1 { font-size: 1.1rem; color: #888; font-weight: normal; }
  h2 { font-size: 1rem; margin: 1.5rem 0 0.4rem; }
  .field { color: #888; }
  .field b { color: #ddd; }
  .keyboard { display: flex; margin: 0.3rem 0 0.8rem; }
  .key { width: 16px; height: 60px; border: 1px solid #444; box-sizing: border-box; position: relative; }
  .key.black { background: #222; }
  .key.white { background: #eee; }
  .key.mode::after { content: ""; position: absolute; top: -6px; left: 2px; right: 2px; height: 3px; background: #00bcd4; }
  .key.root { background: #e91e63 !important; }
  .key.tone { background: #fdd835 !important; }
  .key.outside { background: #4caf50 !important; }
  .key.held { background: #bbb !important; }
  .empty { color: #666; font-style: italic; }
</style>
</head>
<body>
<h1>Music Improv Assistant — activite en direct (lecture seule, rafraichi toutes les ~250ms)</h1>
<div id="app"></div>
<script src="/app.js"></script>
</body>
</html>
"""

public let webConsoleAppJS = """
const MIN_MIDI = 48; // C3, same range as the terminal's per-track keyboard
const MAX_MIDI = 83; // B5

function keyboardHTML(heldPitches, chordRoot, chordTones, modeTones) {
  const held = new Set(heldPitches || []);
  const tones = new Set(chordTones || []);
  const modes = new Set(modeTones || []);
  const blackPitchClasses = new Set([1, 3, 6, 8, 10]);
  let html = '<div class="keyboard">';
  for (let pitch = MIN_MIDI; pitch <= MAX_MIDI; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    const classes = [blackPitchClasses.has(pc) ? 'black' : 'white'];
    if (modes.has(pc)) classes.push('mode');
    if (held.has(pitch)) {
      if (chordRoot !== null && chordRoot !== undefined && pc === chordRoot) classes.push('root');
      else if (tones.has(pc)) classes.push('tone');
      else if (chordRoot !== null && chordRoot !== undefined) classes.push('outside');
      else classes.push('held');
    }
    html += `<div class="key ${classes.join(' ')}"></div>`;
  }
  return html + '</div>';
}

function renderTrack(track) {
  const owner = track.owner ? ` — ${track.owner}` : '';
  let html = `<h2>[${track.id}] ${track.label}${owner}</h2>`;
  if (track.microphoneLevel !== null && track.microphoneLevel !== undefined) {
    html += `<div class="field">Micro: <b>${track.microphoneLevel.toFixed(4)}</b></div>`;
  }
  html += `<div class="field">Accord: <b>${track.chordLabel || '-'}</b></div>`;
  html += `<div class="field">Modes: <b>${track.modesLabel || '-'}</b></div>`;
  html += keyboardHTML(track.heldPitches, track.chordRoot, track.chordTones, track.modeTones);
  return html;
}

function renderPlayback(playback) {
  if (!playback) return '';
  let html = '<h2>Morceau en cours de lecture</h2>';
  html += '<div class="field">' + (playback.timeline || []).map(
    seg => seg.isCurrent ? `<b>[${seg.label}]</b>` : seg.label
  ).join(' ') + '</div>';
  html += keyboardHTML(playback.heldPitches, playback.chordRoot, playback.chordTones, playback.modeTones);
  return html;
}

function renderSoundTrackPlayback(playback) {
  if (!playback) return '';
  return '<h2>Enregistrement en cours de lecture</h2>' + keyboardHTML(playback.heldPitches, null, [], []);
}

async function refresh() {
  let state;
  try {
    const response = await fetch('/state', { cache: 'no-store' });
    state = await response.json();
  } catch (error) {
    document.getElementById('app').innerHTML = '<p class="empty">(connexion perdue — l\\'application est-elle toujours lancee ?)</p>';
    return;
  }
  const tracks = state.tracks || [];
  let html = `<div class="field">Dernier evt: <b>${state.lastEvent || '-'}</b></div>`;
  html += tracks.length
    ? tracks.map(renderTrack).join('')
    : '<p class="empty">(aucune piste en ecoute)</p>';
  html += renderPlayback(state.playback);
  html += renderSoundTrackPlayback(state.soundTrackPlayback);
  document.getElementById('app').innerHTML = html;
}

refresh();
setInterval(refresh, 250);
"""
