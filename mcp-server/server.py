"""MCP server exposing JamShack's web-console "Commandes" actions as MCP tools.

This is a thin proxy, not a reimplementation: every tool here just turns an MCP tool call
into an HTTP `GET /menu-action?action=...&<params>` (or `GET /menu-lists`) request against an
already-running JamShack web console (`Sources/AppCore/ImprovSession.swift`'s
`performMenuAction`/`handleMenuListsRequest` — see `Docs/ARCHITECTURE.md`'s "Onglet 'Menu'"
section). No music-app logic lives here; JamShack itself stays the single source of truth.

`ACTIONS` below is a hand-ported copy of `MENU_ACTIONS` in
`Sources/WebConsole/StaticAssets.swift` — kept in sync by hand, same convention this whole
project already uses for its other hand-synced parallel definitions (e.g. `SanityChecks`
mirroring `Tests/*` by hand). If a menu action is added/changed/removed there, mirror the
change here too.

Experimental / v1: every action is exposed with no finer-grained permission model — the user
explicitly asked for "all of them for now, we'll add something finer later" (2026-07-12).
"""

import os
from typing import Any

import httpx
from mcp.server.fastmcp import FastMCP

# The web console must already be running (`web-console <port>` in the terminal, or the
# "Demarrer la console web..." menu item) — this server assumes it, exactly like a browser
# tab pointed at the same URL would.
BASE_URL = os.environ.get("JAMSHACK_BASE_URL", "http://localhost:8080")

mcp = FastMCP("jamshack")

# Same 12-name table as `NOTE_NAMES` in `Sources/WebConsole/StaticAssets.swift` (index = pitch
# class 0..11) — the web UI's tonic `<select>` sends the pitch-class INDEX as its value, but an
# LLM should get to say "D" rather than "2", so this server does that translation itself
# before forwarding to `/menu-action`.
NOTE_NAMES = ["C", "Db", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]


def _describe_field(field: dict) -> str:
    kind = field["kind"]
    label = field.get("label") or field.get("placeholder") or _exposed_name(field)
    if kind == "select-track":
        return f"{label} — a track id from get_menu_lists()['tracks'] (e.g. 'midi', 'clavier', 'micro')."
    if kind == "select" and field.get("list"):
        return f"{label} — one of the filenames/names from get_menu_lists()['{field['list']}']."
    if kind == "select" and field["name"] == "tonic":
        return f"{label} — a note name: one of {NOTE_NAMES}."
    if field.get("useIndex"):
        return f"{label} — the INDEX (0-based) of an item in get_menu_lists()['{field['list']}'], not its name."
    if kind == "textarea":
        return f"{label} (multi-line text)."
    return str(label)


def _exposed_name(field: dict) -> str:
    """The parameter name shown to the MCP caller — deliberately NOT always `field['name']`
    (the wire name `/menu-action` expects, e.g. `value`), which is the exact bug this function
    exists to fix: an earlier version exposed nearly every action's primary field as a bare
    `value`, with no hint of what it actually holds. An assistant using `composition_describe`
    then had no way to recognize its `value` parameter as "the composition's source text" —
    the same field the terminal's `paste-text` command sets (`ImprovSession.setSourceText`,
    confirmed by reading both call sites) — and reported being stuck with no tool for it, when
    the tool was there all along under an uninformative name. `field.get('expose_as')` lets a
    field pick its own clearer public name; falls back to `field['name']` when that's already
    clear enough on its own (title, instructions, tonic, scale, progression, host, port, ...)."""
    return field.get("expose_as", field["name"])


# Hand-ported from `MENU_ACTIONS` in `Sources/WebConsole/StaticAssets.swift` — see this file's
# own module docstring for why this duplication is deliberate, not an oversight. Every field
# that the web UI names generically `value` (it can afford to, since a human sees the row's own
# label right next to the input) gets an explicit `expose_as` here instead — see
# `_exposed_name`'s doc comment for why that matters a lot more for an MCP tool's schema than
# it does for an HTML form.
ACTIONS: list[dict] = [
    {"category": "JamShack", "items": [
        {"action": "folder-pieces", "label": "Choisir dossier de morceaux", "fields": [{"name": "value", "expose_as": "folder_path", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-samples", "label": "Choisir dossier de sons", "fields": [{"name": "value", "expose_as": "folder_path", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-soundtracks", "label": "Choisir dossier de soundtracks", "fields": [{"name": "value", "expose_as": "folder_path", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-guides", "label": "Choisir dossier de guides musicaux", "fields": [{"name": "value", "expose_as": "folder_path", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-scenes", "label": "Choisir dossier de scenes", "fields": [{"name": "value", "expose_as": "folder_path", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-settings", "label": "Choisir dossier de reglages", "fields": [{"name": "value", "expose_as": "folder_path", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-prompts", "label": "Choisir dossier de composition IA", "fields": [{"name": "value", "expose_as": "folder_path", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "use-llm", "label": "Choisir une connexion LLM", "fields": [{"name": "value", "expose_as": "connection_name", "kind": "select", "list": "llmConnections"}]},
        {"action": "use-palette", "label": "Choisir palette de couleur", "fields": [{"name": "value", "expose_as": "palette_name", "kind": "select", "list": "colorPalettes"}]},
        {"action": "midi-mode-merged", "label": "Mode MIDI: fusionne", "fields": []},
        {"action": "midi-mode-individual", "label": "Mode MIDI: individuel", "fields": []},
        {"action": "web-console-start", "label": "Demarrer la console web", "fields": [{"name": "value", "expose_as": "port", "kind": "text", "placeholder": "port (8080)", "optional": True}]},
        {"action": "web-console-stop", "label": "Arreter la console web", "fields": []},
        {"action": "vk-start", "label": "Demarrer le clavier virtuel", "fields": [{"name": "value", "expose_as": "port", "kind": "text", "placeholder": "port (8081)", "optional": True}]},
        {"action": "vk-stop", "label": "Arreter le clavier virtuel", "fields": []},
    ]},
    {"category": "Scene", "items": [
        {"action": "track-on", "label": "Activer un instrument", "fields": [{"name": "value", "expose_as": "track_id", "kind": "select-track"}]},
        {"action": "track-off", "label": "Arreter un instrument", "fields": [{"name": "value", "expose_as": "track_id", "kind": "select-track"}]},
        {"action": "track-sound-on", "label": "Activer le son d'un instrument", "fields": [{"name": "value", "expose_as": "track_id", "kind": "select-track"}]},
        {"action": "track-sound-off", "label": "Desactiver le son d'un instrument", "fields": [{"name": "value", "expose_as": "track_id", "kind": "select-track"}]},
        {"action": "track-instrument", "label": "Choisir un son pour un instrument", "fields": [
            {"name": "track", "expose_as": "track_id", "kind": "select-track", "label": "Instrument"},
            {"name": "value", "expose_as": "sample_name", "kind": "select", "list": "sampleFiles", "label": "Son"},
        ]},
        {"action": "scene-save", "label": "Sauvegarder scene", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
        {"action": "scene-load", "label": "Charger scene", "fields": [{"name": "value", "expose_as": "scene_name", "kind": "select", "list": "sceneFiles"}]},
    ]},
    {"category": "Guide Musicaux", "items": [
        {"action": "guide-new", "label": "Nouveau guide musical", "fields": [{"name": "value", "expose_as": "title", "kind": "text", "placeholder": "titre"}]},
        {"action": "guide-add-mode", "label": "Ajouter un mode au guide", "fields": [
            {"name": "tonic", "kind": "select", "label": "Tonique"},
            {"name": "scale", "expose_as": "scale_id", "kind": "select", "list": "scales", "label": "Gamme (id, e.g. 'ionian', 'dorian')"},
            {"name": "progression", "expose_as": "chord_progression_name", "kind": "select", "list": "chordProgressionTemplates", "label": "Progression", "optional": True},
        ]},
        {"action": "guide-load", "label": "Charger un guide musical", "fields": [{"name": "value", "expose_as": "guide_name", "kind": "select", "list": "guideFiles"}]},
        {"action": "guide-save", "label": "Sauvegarder le guide musical", "fields": []},
        {"action": "guide-save-as", "label": "Sauvegarder le guide musical sous", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
        {"action": "guide-start", "label": "Demarrer le guide musical", "fields": []},
        {"action": "guide-stop", "label": "Arreter le guide musical", "fields": []},
    ]},
    {"category": "Enregistrement", "items": [
        {"action": "record-start", "label": "Demarrer un enregistrement", "fields": [{"name": "value", "expose_as": "track_ids", "kind": "text", "placeholder": "pistes separees par espace (vide = toutes)", "optional": True}]},
        {"action": "record-stop", "label": "Arreter l'enregistrement", "fields": []},
        {"action": "soundtrack-play", "label": "Jouer l'enregistrement", "fields": []},
        {"action": "soundtrack-load", "label": "Charger un enregistrement", "fields": [{"name": "value", "expose_as": "soundtrack_name", "kind": "select", "list": "soundTrackFiles"}]},
        {"action": "soundtrack-save", "label": "Sauvegarder l'enregistrement", "fields": []},
        {"action": "soundtrack-save-as", "label": "Sauvegarder l'enregistrement sous", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
        {"action": "soundtrack-compose", "label": "Composer un morceau a partir de l'enregistrement", "fields": [
            {"name": "value", "expose_as": "title", "kind": "text", "placeholder": "titre", "label": "Titre", "optional": True},
            {"name": "count", "kind": "text", "placeholder": "1", "label": "Nombre de candidats", "optional": True},
        ]},
        {"action": "soundtrack-framing-set", "label": "Modifier la phrase de cadrage", "fields": [{"name": "value", "expose_as": "framing_sentence", "kind": "textarea"}]},
        {"action": "soundtrack-framing-save", "label": "Sauvegarder la phrase de cadrage", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
        {"action": "soundtrack-framing-load", "label": "Charger une phrase de cadrage", "fields": [{"name": "value", "expose_as": "framing_name", "kind": "select", "list": "soundTrackFramingFiles"}]},
        {"action": "soundtrack-framing-reset", "label": "Revenir a la phrase de cadrage par defaut", "fields": []},
        {"action": "soundtrack-instructions-set", "label": "Modifier les indications de style", "fields": [{"name": "value", "expose_as": "instructions", "kind": "text", "placeholder": "indications", "optional": True}]},
        {"action": "soundtrack-instructions-save", "label": "Sauvegarder les indications de style", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
        {"action": "soundtrack-instructions-load", "label": "Charger des indications de style", "fields": [{"name": "value", "expose_as": "instructions_name", "kind": "select", "list": "soundTrackInstructionsFiles"}]},
        {"action": "soundtrack-instructions-reset", "label": "Revenir aux indications de style par defaut", "fields": []},
        {"action": "soundtrack-prompt-export", "label": "Exporter le prompt de composition", "fields": [{"name": "value", "expose_as": "export_name", "kind": "text", "placeholder": "nom"}]},
    ]},
    {"category": "Morceaux", "items": [
        {"action": "piece-play", "label": "Ecouter le morceau", "fields": []},
        {"action": "piece-sample", "label": "Choisir le son de lecture du morceau", "fields": [{"name": "value", "expose_as": "sample_name", "kind": "select", "list": "sampleFiles"}]},
        {"action": "piece-track-instrument", "label": "Choisir le son d'une piste", "fields": [
            {"name": "section", "expose_as": "section_number", "kind": "text", "placeholder": "section #", "label": "Section (1-based)"},
            {"name": "track", "expose_as": "track_number", "kind": "text", "placeholder": "piste #", "label": "Piste (1-based)"},
            {"name": "value", "expose_as": "sample_name", "kind": "select", "list": "sampleFiles", "label": "Son", "optional": True},
        ]},
        {"action": "piece-chord-instrument", "label": "Choisir le son des accords d'une section", "fields": [
            {"name": "section", "expose_as": "section_number", "kind": "text", "placeholder": "section #", "label": "Section (1-based)"},
            {"name": "value", "expose_as": "sample_name", "kind": "select", "list": "sampleFiles", "label": "Son", "optional": True},
        ]},
        {"action": "piece-load-demo", "label": "Charger demo", "fields": []},
        {"action": "piece-load", "label": "Charger morceau", "fields": [{"name": "value", "expose_as": "piece_name", "kind": "select", "list": "pieceFiles"}]},
        {"action": "piece-save", "label": "Sauvegarder le morceau", "fields": []},
        {"action": "piece-save-as", "label": "Sauvegarder le morceau sous", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
    ]},
    {"category": "Composition", "items": [
        {"action": "composition-describe", "label": "Decrire le morceau", "fields": [
            {"name": "title", "kind": "text", "placeholder": "titre", "label": "Titre", "optional": True},
            # THE field behind the bug reported 2026-07-12: exposed as a bare, generically-
            # labeled `value` ("Description"), an assistant using this tool had no way to
            # recognize it as "the composition's source text" — the exact same field the
            # terminal's `paste-text` command sets (`ImprovSession.setSourceText`, confirmed
            # by reading both call sites: `composition-describe`'s Swift case calls
            # `setSourceText(value)` directly) — and reported being stuck with no tool for
            # pasting source text, when this parameter WAS that tool all along. Renamed +
            # description now says so explicitly, by name, so a semantic search for
            # "texte source"/"paste-text" actually lands here.
            {"name": "value", "expose_as": "source_text", "kind": "textarea", "label": "Source text — the composition's full source material (poem, description, mood, theme...). This is exactly the same field the terminal's `paste-text` command / \"texte source\" sets — there is no separate action for it."},
            {"name": "instructions", "kind": "text", "placeholder": "indications", "label": "Indications", "optional": True},
        ]},
        {"action": "composition-compose", "label": "Composer a partir de la description", "fields": []},
        {"action": "composition-load", "label": "Charger une description", "fields": [{"name": "value", "expose_as": "description_name", "kind": "select", "list": "compositionFiles"}]},
        {"action": "composition-save-as", "label": "Sauvegarder la description sous", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
        {"action": "composition-save", "label": "Sauvegarder la description", "fields": []},
        {"action": "text-framing-set", "label": "Modifier la phrase de cadrage", "fields": [{"name": "value", "expose_as": "framing_sentence", "kind": "textarea"}]},
        {"action": "text-framing-save", "label": "Sauvegarder la phrase de cadrage", "fields": [{"name": "value", "expose_as": "name", "kind": "text", "placeholder": "nom"}]},
        {"action": "text-framing-load", "label": "Charger une phrase de cadrage", "fields": [{"name": "value", "expose_as": "framing_name", "kind": "select", "list": "textFramingFiles"}]},
        {"action": "text-framing-reset", "label": "Revenir a la phrase de cadrage par defaut", "fields": []},
        {"action": "text-prompt-export", "label": "Exporter le prompt de composition", "fields": [{"name": "value", "expose_as": "export_name", "kind": "text", "placeholder": "nom"}]},
    ]},
    {"category": "Jam Session", "items": [
        {"action": "jam-start", "label": "Demarrer une jam session", "fields": [
            {"name": "pseudo", "kind": "text", "placeholder": "pseudo", "label": "Pseudo", "optional": True},
            {"name": "value", "expose_as": "port", "kind": "text", "placeholder": "port (7777)", "label": "Port", "optional": True},
        ]},
        {"action": "jam-stop", "label": "Arreter la jam session", "fields": []},
        {"action": "jam-join", "label": "Rejoindre une jam session", "fields": [
            {"name": "pseudo", "kind": "text", "placeholder": "pseudo", "label": "Pseudo", "optional": True},
            {"name": "host", "kind": "text", "placeholder": "hote", "label": "Hote"},
            {"name": "port", "kind": "text", "placeholder": "port (7777)", "label": "Port", "optional": True},
        ]},
        {"action": "jam-discover", "label": "Rechercher des jam sessions", "fields": []},
        {"action": "jam-connect-discovered", "label": "Rejoindre une session trouvee", "fields": [{"name": "value", "expose_as": "discovered_index", "kind": "select", "list": "discoveredJamSessions", "useIndex": True}]},
        {"action": "jam-leave", "label": "Quitter la jam session", "fields": []},
    ]},
]


# `composition-compose`/`soundtrack-compose` are the only two actions that call an LLM
# (`ImprovSession.composeFromText`/`composeSoundTrackToPieces`) — JamShack itself has NO
# timeout for this (it just blocks synchronously on a `URLSession` call until the model
# responds, however long that takes), which is why it always worked fine from the terminal.
# A short client-side timeout here would abort a composition that's proceeding completely
# normally, just slowly — confirmed as the actual cause of a real "it times out via MCP but
# not the terminal" report (2026-07-12): the fixed 10s timeout below used to apply to every
# action uniformly, aborting the HTTP connection to JamShack long before generation finished.
# Every OTHER action is local file I/O / an in-memory state change and should never
# legitimately take more than a couple seconds — kept short so a genuinely hung connection
# still fails fast instead of hanging for 3 minutes.
LONG_RUNNING_ACTIONS = {"composition-compose", "soundtrack-compose"}
DEFAULT_ACTION_TIMEOUT = 10.0
LONG_RUNNING_ACTION_TIMEOUT = 180.0


def _call_menu_action(action: str, params: dict[str, Any]) -> dict:
    query = {"action": action}
    for key, value in params.items():
        if value is None:
            continue
        # `guide-add-mode`'s `tonic` is the one field this server translates before sending —
        # the web UI's own `<select>` sends a pitch-class index, so an LLM caller gets to say
        # a note name instead (see `_describe_field`/module docstring).
        if key == "tonic" and isinstance(value, str) and value in NOTE_NAMES:
            value = str(NOTE_NAMES.index(value))
        query[key] = str(value)
    timeout = LONG_RUNNING_ACTION_TIMEOUT if action in LONG_RUNNING_ACTIONS else DEFAULT_ACTION_TIMEOUT
    response = httpx.get(f"{BASE_URL}/menu-action", params=query, timeout=timeout)
    response.raise_for_status()
    return response.json()


def _make_tool_function(action: str, fields: list[dict]):
    """Builds a real Python function with one named parameter per field (defaulting to `None`
    when `optional`), so FastMCP's signature-based schema introspection produces a proper
    per-action input schema — a plain `**kwargs` function wouldn't give it enough to work
    with. See this module's own docstring for why the definitions are hand-ported data rather
    than something generated from the Swift/JS side directly.

    The exposed parameter NAME (`_exposed_name`) can differ from the wire field name
    `/menu-action` actually expects (`field['name']`, e.g. `value`) — the function body maps
    back to the wire name when building the query dict, so this is purely a caller-facing
    naming choice with no effect on what gets sent over HTTP."""
    # Required params must precede defaulted ones in a Python signature — `fields` is
    # authored in the order that reads best in the tool's own description, which doesn't
    # always already put optional fields last (e.g. `composition-describe`'s middle
    # `source_text` field is required while `title` before it is optional).
    ordered_fields = sorted(fields, key=lambda f: bool(f.get("optional")))
    param_defs = []
    for field in ordered_fields:
        default = " = None" if field.get("optional") else ""
        param_defs.append(f"{_exposed_name(field)}: str{default}")
    signature = ", ".join(param_defs)
    wire_to_local = [(f["name"], _exposed_name(f)) for f in fields]
    source = (
        f"def _tool({signature}):\n"
        f"    return _call_menu_action({action!r}, {{" +
        ", ".join(f"{wire!r}: {local}" for wire, local in wire_to_local) + "})\n"
    )
    namespace = {"_call_menu_action": _call_menu_action}
    exec(source, namespace)  # noqa: S102 — building a real function per data-driven action, not arbitrary input
    return namespace["_tool"]


for category in ACTIONS:
    for item in category["items"]:
        tool_name = item["action"].replace("-", "_")
        field_docs = "\n".join(f"- {_exposed_name(f)}: {_describe_field(f)}" for f in item["fields"])
        description = f"{item['label']} (JamShack — {category['category']})."
        if field_docs:
            description += "\n\nParameters:\n" + field_docs
        fn = _make_tool_function(item["action"], item["fields"])
        fn.__name__ = tool_name
        mcp.add_tool(fn, name=tool_name, description=description)


@mcp.tool()
def get_menu_lists() -> dict:
    """Fetches the current valid values for every dropdown-driven parameter used by the
    other tools here (piece/sample/soundtrack/guide/scene/composition files, framing/
    instructions files, LLM connections, color palettes, chord progression templates, all 33
    scales, currently-known local tracks, the current MIDI fusion mode, and the last jam-session
    discovery scan). Call this before an action whose parameter is drawn from one of these
    lists (e.g. `piece_load`'s `piece_name`, `track_on`'s `track_id`) to see what's actually
    available right now — these lists can change from outside this MCP server too (the
    terminal, a browser tab, another jam-session participant)."""
    response = httpx.get(f"{BASE_URL}/menu-lists", timeout=DEFAULT_ACTION_TIMEOUT)
    response.raise_for_status()
    return response.json()


@mcp.tool()
def get_piece_detail() -> dict:
    """Full structure of the currently loaded piece: title/composer/tempo/key, every
    section (mode, chord progression with beat-level timing/inversion/playing style and a
    resolved chord label like 'Dm7'), every track's actual melody events
    (measure/beat/duration/pitch/velocity, not just a count) and fragment placements —
    INCLUDING tracks with zero notes, unlike the terminal's own piece display, which silently
    omits those. Returns `{"loaded": false, ...}` if no piece is loaded. Call this to answer
    questions like "how many sections does this piece have", "what are the melodic lines",
    "what chords are in section 2" — none of that is visible in get_menu_lists() or any menu
    action's result."""
    response = httpx.get(f"{BASE_URL}/piece-detail", timeout=DEFAULT_ACTION_TIMEOUT)
    response.raise_for_status()
    return response.json()


@mcp.tool()
def get_composition_description() -> dict:
    """The composition currently staged for AI composition: title, source text (the same
    field `composition_describe`'s `source_text` sets — see that tool's own description),
    style instructions, and the exact resolved prompt that would be sent to an LLM right now
    if `composition_compose` were called. Call this to check what's already been
    described/staged BEFORE or DURING an AI composition, instead of guessing from the
    conversation history — `composition_describe` sets this but never reads it back on its
    own."""
    response = httpx.get(f"{BASE_URL}/composition-detail", timeout=DEFAULT_ACTION_TIMEOUT)
    response.raise_for_status()
    return response.json()


@mcp.tool()
def get_guide_sequence_detail() -> dict:
    """Full structure of the currently loaded guide sequence: every step's actual mode
    (tonic/scale, resolved names included) and chord progression — not just the step LABELS
    that a live-state view would show, and not just the CURRENT step's detail either. Returns
    `{"loaded": false, ...}` if no guide is loaded. Call this to answer "what modes/chords
    does this guide actually walk through", not just "which step is active right now"."""
    response = httpx.get(f"{BASE_URL}/guide-detail", timeout=DEFAULT_ACTION_TIMEOUT)
    response.raise_for_status()
    return response.json()


@mcp.tool()
def get_soundtrack_detail() -> dict:
    """The currently recorded/loaded soundtrack: title, file path, duration, which tracks
    contributed events, and every individual recorded note on/off event (time in seconds,
    track id, pitch, velocity) — not just an event count. Returns `{"loaded": false, ...}` if
    nothing is recorded/loaded."""
    response = httpx.get(f"{BASE_URL}/soundtrack-detail", timeout=DEFAULT_ACTION_TIMEOUT)
    response.raise_for_status()
    return response.json()


if __name__ == "__main__":
    mcp.run()
