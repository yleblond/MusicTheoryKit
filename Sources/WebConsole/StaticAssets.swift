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
/// degree number, not just "in the mode or not":
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
///   } | null
/// }
/// ```
/// `wheel` is always present (not gated behind an active guide) — see
/// `ImprovSession.wheelReferenceTonic()`/`buildWebConsoleWheelState()` for how its reference
/// key is chosen, and each cell's `trackLabels` for the multi-instrument "who's playing this
/// function right now" view. The palette (which chord is at which column/ring) never
/// changes; only `isDiatonic`/`modeName`/`relativeDegree` are relative to `tonic`.
public let webConsoleIndexHTML = """
<!doctype html>
<html lang="fr">
<head>
<meta charset="utf-8">
<title>JamShack — Console Web</title>
<style>
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
  .pkey.root { background: #e91e63 !important; }
  .pkey.tone { background: #fdd835 !important; }
  .pkey.outside { background: #4caf50 !important; }
  .pkey.held { background: #bbb !important; }
  .degree-badge {
    position: absolute; top: -18px; left: 50%; transform: translateX(-50%);
    width: 14px; height: 14px; border-radius: 50%;
    font-size: 9px; line-height: 14px; text-align: center; color: #111; font-weight: bold;
  }
  .empty { color: #666; font-style: italic; }
  .wheel { margin: 0.5rem 0 1rem; display: block; width: 100%; max-width: 820px; height: auto; }
  .wheel-disk { fill: #fff; }
  .wheel-grid-line { stroke: #000; stroke-width: 1; }
  .wheel-cell-shape { stroke: #333; stroke-width: 1; }
  .wheel-cell-outline { fill: none; stroke-width: 3; }
  .wheel-diatonic-boundary { fill: none; stroke: #1a3a6b; stroke-width: 5; stroke-linejoin: round; }
  .wheel-cell-symbol { font-size: 8px; font-weight: bold; text-anchor: middle; fill: #111; pointer-events: none; }
  .wheel-cell-degree { font-size: 6.5px; font-family: Georgia, 'Times New Roman', serif; text-anchor: middle; fill: #111; pointer-events: none; opacity: 0.75; }
  .wheel-mode-name { fill: #555; font-size: 11px; text-anchor: middle; dominant-baseline: middle; }
  .wheel-mode-name.active { fill: #b36b00; font-weight: bold; }
  .instrument-swatch { display: inline-block; width: 10px; height: 10px; border-radius: 50%; margin-right: 0.4em; }
  .layout-columns { display: flex; flex-wrap: wrap; gap: 2rem; align-items: flex-start; }
  .layout-col-left, .layout-col-right { flex: 1 1 380px; min-width: 0; }
</style>
</head>
<body>
<h1>JamShack — activite en direct (lecture seule, rafraichi toutes les ~250ms)</h1>
<div id="app"></div>
<script src="/app.js"></script>
</body>
</html>
"""

public let webConsoleAppJS = """
const MIN_MIDI = 48; // C3, same range as the terminal's per-track keyboard
const MAX_MIDI = 83; // B5

// Fixed color per chromatic pitch class (index 0 = C ... 11 = B), "mycolormusic"-style: a
// note keeps the same color no matter which mode/key it's functioning in. Hand-mirrors
// `MusicTheoryKit.PitchClassPalette.hex` — see this module's JSON-contract comment above for
// the "no compiler-enforced contract, kept in sync by hand" convention this follows.
const PITCH_CLASS_COLORS = [
  '#e6194B', '#f58231', '#ffe119', '#bfef45', '#3cb44b', '#42d4f4',
  '#4363d8', '#911eb4', '#f032e6', '#fabed4', '#469990', '#9A6324',
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

function keyboardHTML(heldPitches, chordRoot, chordTones, modeTones) {
  const held = new Set(heldPitches || []);
  const tones = new Set(chordTones || []);
  // pitch class -> {degree, color} — `modeTones` is degree-ordered (index 0 = degree 1).
  const roles = {};
  (modeTones || []).forEach((pc, index) => { roles[pc] = { degree: index + 1, color: PITCH_CLASS_COLORS[pc] }; });

  const octaveCount = Math.ceil((MAX_MIDI - MIN_MIDI + 1) / 12);
  const totalWidth = octaveCount * 7 * WHITE_KEY_WIDTH;
  let whiteHTML = '', blackHTML = '';

  for (let pitch = MIN_MIDI; pitch <= MAX_MIDI; pitch++) {
    const pc = ((pitch % 12) + 12) % 12;
    const octave = Math.floor((pitch - MIN_MIDI) / 12);
    const role = roles[pc];
    const badge = role ? `<span class="degree-badge" style="background:${role.color}">${role.degree}</span>` : '';
    let cls = '';
    if (held.has(pitch)) {
      if (chordRoot !== null && chordRoot !== undefined && pc === chordRoot) cls = 'root';
      else if (tones.has(pc)) cls = 'tone';
      else if (chordRoot !== null && chordRoot !== undefined) cls = 'outside';
      else cls = 'held';
    }
    if (WHITE_SLOT_BY_SEMITONE[pc] !== undefined) {
      const slot = octave * 7 + WHITE_SLOT_BY_SEMITONE[pc];
      const x = slot * WHITE_KEY_WIDTH;
      whiteHTML += `<div class="pkey white ${cls}" style="left:${x}px; width:${WHITE_KEY_WIDTH}px; height:${WHITE_KEY_HEIGHT}px;">${badge}</div>`;
    } else {
      const whiteSlotBefore = BLACK_AFTER_WHITE_SLOT[pc];
      const slot = octave * 7 + whiteSlotBefore + 1;
      const x = slot * WHITE_KEY_WIDTH - BLACK_KEY_WIDTH / 2;
      blackHTML += `<div class="pkey black ${cls}" style="left:${x}px; width:${BLACK_KEY_WIDTH}px; height:${BLACK_KEY_HEIGHT}px;">${badge}</div>`;
    }
  }
  // The keyboard itself is necessarily a fixed pixel width (`.pkey` children are absolutely
  // positioned, which a percentage-based layout can't drive) — wrapped in its own scrolling
  // container so a narrow browser window scrolls just this widget horizontally instead of
  // the whole page (see `.keyboard-scroll` in the CSS above).
  return `<div class="keyboard-scroll"><div class="keyboard" style="width:${totalWidth}px; height:${WHITE_KEY_HEIGHT}px;">${whiteHTML}${blackHTML}</div></div>`;
}

// Point at angle `2*PI*index/columnCount - PI/2` (column 0 at 12 o'clock, clockwise — matches
// the wheel's fixed ascending-fifths physical layout) on a circle of radius `r` centered at
// (cx, cy) — shared by every ring (chord cells and the mode-name ring), which all place their
// items at the same 12 angular positions (only the radius differs per ring).
function polarPoint(cx, cy, r, index, count) {
  const angle = (2 * Math.PI * index) / count - Math.PI / 2;
  return { x: cx + r * Math.cos(angle), y: cy + r * Math.sin(angle) };
}

// One note name per pitch class — mirrors the physical wheel's own mixed convention (sharp
// side C,G,D,A,E,B,F# stays sharp; the remaining 5 black keys are spelled flat: Db,Ab,Eb,
// Bb,F), not a single global sharps-only or flats-only table.
const NOTE_NAMES = ['C', 'Db', 'D', 'Eb', 'E', 'F', 'F#', 'G', 'Ab', 'A', 'Bb', 'B'];
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

function renderWheelSection(wheel, tracks) {
  if (!wheel) return '';
  return '<h2>Cercle des quintes</h2>' + renderWheel(wheel, tracks);
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

function renderWheel(wheel, tracks) {
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
      svg += `<text class="${cls}" x="${pos.x}" y="${pos.y}">${column.modeName}</text>`;
    }
    // Each cell has its OWN chord root (`cell.pitchClass`) — only the major ring is rooted
    // on the column itself; minor/diminished are the column's relative-minor/leading-tone-
    // diminished, so color/shape/note-name must come from the cell, not the column.
    column.cells.forEach(cell => {
      const r = WHEEL_RING_RADIUS[cell.quality];
      const pos = polarPoint(cx, cy, r, index, count);
      const color = PITCH_CLASS_COLORS[cell.pitchClass];
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
      svg += `<text class="wheel-cell-symbol" x="${pos.x}" y="${pos.y + 1}">${symbol}</text>`;
      svg += `<text class="wheel-cell-degree" x="${pos.x}" y="${pos.y + 9}">${degreeSVGMarkup(cell.relativeDegree)}</text>`;

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

function renderGuide(guide) {
  if (!guide || !guide.isActive) return '';
  let html = '<h2>Guide</h2>';
  html += '<div class="field">' + (guide.steps || []).map(
    step => step.isCurrent ? `<b>[${step.label}]</b>` : step.label
  ).join(' ') + '</div>';
  html += keyboardHTML(guide.heldPitches, null, [], guide.currentModeTones);
  return html;
}

function renderTrack(track, index) {
  const owner = track.owner ? ` — ${track.owner}` : '';
  const swatch = `<span class="instrument-swatch" style="background:${instrumentColor(index)}"></span>`;
  let html = `<h2>${swatch}[${track.id}] ${track.label}${owner}</h2>`;
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
  const tracksHTML = tracks.length
    ? tracks.map(renderTrack).join('')
    : '<p class="empty">(aucune piste en ecoute)</p>';
  let html = `<div class="field">Dernier evt: <b>${state.lastEvent || '-'}</b></div>`;

  // Always the same 2-column layout: left is just the wheel ("what mode/key are we in"),
  // right leads with whatever represents "the mode" right now — the guide's own keyboard if
  // one is running, the piece/soundtrack currently playing otherwise — then every individual
  // active instrument's own keyboard below that. Reading "the mode" and "who's playing what"
  // side by side is the point, whether or not a guide happens to be active.
  const modeHTML = renderGuide(state.guide) + renderPlayback(state.playback) + renderSoundTrackPlayback(state.soundTrackPlayback);
  const left = renderWheelSection(state.wheel, tracks);
  const right = modeHTML + tracksHTML;
  html += `<div class="layout-columns"><div class="layout-col-left">${left}</div><div class="layout-col-right">${right}</div></div>`;
  document.getElementById('app').innerHTML = html;
}

refresh();
setInterval(refresh, 250);
"""
