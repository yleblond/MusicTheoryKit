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
    label = field.get("label") or field.get("placeholder") or field["name"]
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


# Hand-ported from `MENU_ACTIONS` in `Sources/WebConsole/StaticAssets.swift` — see this file's
# own module docstring for why this duplication is deliberate, not an oversight.
ACTIONS: list[dict] = [
    {"category": "JamShack", "items": [
        {"action": "folder-pieces", "label": "Choisir dossier de morceaux", "fields": [{"name": "value", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-samples", "label": "Choisir dossier de sons", "fields": [{"name": "value", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-soundtracks", "label": "Choisir dossier de soundtracks", "fields": [{"name": "value", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-guides", "label": "Choisir dossier de guides musicaux", "fields": [{"name": "value", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-scenes", "label": "Choisir dossier de scenes", "fields": [{"name": "value", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-settings", "label": "Choisir dossier de reglages", "fields": [{"name": "value", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "folder-prompts", "label": "Choisir dossier de composition IA", "fields": [{"name": "value", "kind": "text", "placeholder": "chemin du dossier"}]},
        {"action": "use-llm", "label": "Choisir une connexion LLM", "fields": [{"name": "value", "kind": "select", "list": "llmConnections"}]},
        {"action": "use-palette", "label": "Choisir palette de couleur", "fields": [{"name": "value", "kind": "select", "list": "colorPalettes"}]},
        {"action": "midi-mode-merged", "label": "Mode MIDI: fusionne", "fields": []},
        {"action": "midi-mode-individual", "label": "Mode MIDI: individuel", "fields": []},
        {"action": "web-console-start", "label": "Demarrer la console web", "fields": [{"name": "value", "kind": "text", "placeholder": "port (8080)", "optional": True}]},
        {"action": "web-console-stop", "label": "Arreter la console web", "fields": []},
        {"action": "vk-start", "label": "Demarrer le clavier virtuel", "fields": [{"name": "value", "kind": "text", "placeholder": "port (8081)", "optional": True}]},
        {"action": "vk-stop", "label": "Arreter le clavier virtuel", "fields": []},
    ]},
    {"category": "Scene", "items": [
        {"action": "track-on", "label": "Activer un instrument", "fields": [{"name": "value", "kind": "select-track"}]},
        {"action": "track-off", "label": "Arreter un instrument", "fields": [{"name": "value", "kind": "select-track"}]},
        {"action": "track-sound-on", "label": "Activer le son d'un instrument", "fields": [{"name": "value", "kind": "select-track"}]},
        {"action": "track-sound-off", "label": "Desactiver le son d'un instrument", "fields": [{"name": "value", "kind": "select-track"}]},
        {"action": "track-instrument", "label": "Choisir un son pour un instrument", "fields": [
            {"name": "track", "kind": "select-track", "label": "Instrument"},
            {"name": "value", "kind": "select", "list": "sampleFiles", "label": "Son"},
        ]},
        {"action": "scene-save", "label": "Sauvegarder scene", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
        {"action": "scene-load", "label": "Charger scene", "fields": [{"name": "value", "kind": "select", "list": "sceneFiles"}]},
    ]},
    {"category": "Guide Musicaux", "items": [
        {"action": "guide-new", "label": "Nouveau guide musical", "fields": [{"name": "value", "kind": "text", "placeholder": "titre"}]},
        {"action": "guide-add-mode", "label": "Ajouter un mode au guide", "fields": [
            {"name": "tonic", "kind": "select", "label": "Tonique"},
            {"name": "scale", "kind": "select", "list": "scales", "label": "Gamme (id, e.g. 'ionian', 'dorian')"},
            {"name": "progression", "kind": "select", "list": "chordProgressionTemplates", "label": "Progression", "optional": True},
        ]},
        {"action": "guide-load", "label": "Charger un guide musical", "fields": [{"name": "value", "kind": "select", "list": "guideFiles"}]},
        {"action": "guide-save", "label": "Sauvegarder le guide musical", "fields": []},
        {"action": "guide-save-as", "label": "Sauvegarder le guide musical sous", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
        {"action": "guide-start", "label": "Demarrer le guide musical", "fields": []},
        {"action": "guide-stop", "label": "Arreter le guide musical", "fields": []},
    ]},
    {"category": "Enregistrement", "items": [
        {"action": "record-start", "label": "Demarrer un enregistrement", "fields": [{"name": "value", "kind": "text", "placeholder": "pistes separees par espace (vide = toutes)", "optional": True}]},
        {"action": "record-stop", "label": "Arreter l'enregistrement", "fields": []},
        {"action": "soundtrack-play", "label": "Jouer l'enregistrement", "fields": []},
        {"action": "soundtrack-load", "label": "Charger un enregistrement", "fields": [{"name": "value", "kind": "select", "list": "soundTrackFiles"}]},
        {"action": "soundtrack-save", "label": "Sauvegarder l'enregistrement", "fields": []},
        {"action": "soundtrack-save-as", "label": "Sauvegarder l'enregistrement sous", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
        {"action": "soundtrack-compose", "label": "Composer un morceau a partir de l'enregistrement", "fields": [
            {"name": "value", "kind": "text", "placeholder": "titre", "label": "Titre", "optional": True},
            {"name": "count", "kind": "text", "placeholder": "1", "label": "Nombre de candidats", "optional": True},
        ]},
        {"action": "soundtrack-framing-set", "label": "Modifier la phrase de cadrage", "fields": [{"name": "value", "kind": "textarea"}]},
        {"action": "soundtrack-framing-save", "label": "Sauvegarder la phrase de cadrage", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
        {"action": "soundtrack-framing-load", "label": "Charger une phrase de cadrage", "fields": [{"name": "value", "kind": "select", "list": "soundTrackFramingFiles"}]},
        {"action": "soundtrack-framing-reset", "label": "Revenir a la phrase de cadrage par defaut", "fields": []},
        {"action": "soundtrack-instructions-set", "label": "Modifier les indications de style", "fields": [{"name": "value", "kind": "text", "placeholder": "indications", "optional": True}]},
        {"action": "soundtrack-instructions-save", "label": "Sauvegarder les indications de style", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
        {"action": "soundtrack-instructions-load", "label": "Charger des indications de style", "fields": [{"name": "value", "kind": "select", "list": "soundTrackInstructionsFiles"}]},
        {"action": "soundtrack-instructions-reset", "label": "Revenir aux indications de style par defaut", "fields": []},
        {"action": "soundtrack-prompt-export", "label": "Exporter le prompt de composition", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
    ]},
    {"category": "Morceaux", "items": [
        {"action": "piece-play", "label": "Ecouter le morceau", "fields": []},
        {"action": "piece-sample", "label": "Choisir le son de lecture du morceau", "fields": [{"name": "value", "kind": "select", "list": "sampleFiles"}]},
        {"action": "piece-track-instrument", "label": "Choisir le son d'une piste", "fields": [
            {"name": "section", "kind": "text", "placeholder": "section #", "label": "Section (1-based)"},
            {"name": "track", "kind": "text", "placeholder": "piste #", "label": "Piste (1-based)"},
            {"name": "value", "kind": "select", "list": "sampleFiles", "label": "Son", "optional": True},
        ]},
        {"action": "piece-chord-instrument", "label": "Choisir le son des accords d'une section", "fields": [
            {"name": "section", "kind": "text", "placeholder": "section #", "label": "Section (1-based)"},
            {"name": "value", "kind": "select", "list": "sampleFiles", "label": "Son", "optional": True},
        ]},
        {"action": "piece-load-demo", "label": "Charger demo", "fields": []},
        {"action": "piece-load", "label": "Charger morceau", "fields": [{"name": "value", "kind": "select", "list": "pieceFiles"}]},
        {"action": "piece-save", "label": "Sauvegarder le morceau", "fields": []},
        {"action": "piece-save-as", "label": "Sauvegarder le morceau sous", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
    ]},
    {"category": "Composition", "items": [
        {"action": "composition-describe", "label": "Decrire le morceau", "fields": [
            {"name": "title", "kind": "text", "placeholder": "titre", "label": "Titre", "optional": True},
            {"name": "value", "kind": "textarea", "label": "Description"},
            {"name": "instructions", "kind": "text", "placeholder": "indications", "label": "Indications", "optional": True},
        ]},
        {"action": "composition-compose", "label": "Composer a partir de la description", "fields": []},
        {"action": "composition-load", "label": "Charger une description", "fields": [{"name": "value", "kind": "select", "list": "compositionFiles"}]},
        {"action": "composition-save-as", "label": "Sauvegarder la description sous", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
        {"action": "composition-save", "label": "Sauvegarder la description", "fields": []},
        {"action": "text-framing-set", "label": "Modifier la phrase de cadrage", "fields": [{"name": "value", "kind": "textarea"}]},
        {"action": "text-framing-save", "label": "Sauvegarder la phrase de cadrage", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
        {"action": "text-framing-load", "label": "Charger une phrase de cadrage", "fields": [{"name": "value", "kind": "select", "list": "textFramingFiles"}]},
        {"action": "text-framing-reset", "label": "Revenir a la phrase de cadrage par defaut", "fields": []},
        {"action": "text-prompt-export", "label": "Exporter le prompt de composition", "fields": [{"name": "value", "kind": "text", "placeholder": "nom"}]},
    ]},
    {"category": "Jam Session", "items": [
        {"action": "jam-start", "label": "Demarrer une jam session", "fields": [
            {"name": "pseudo", "kind": "text", "placeholder": "pseudo", "label": "Pseudo", "optional": True},
            {"name": "value", "kind": "text", "placeholder": "port (7777)", "label": "Port", "optional": True},
        ]},
        {"action": "jam-stop", "label": "Arreter la jam session", "fields": []},
        {"action": "jam-join", "label": "Rejoindre une jam session", "fields": [
            {"name": "pseudo", "kind": "text", "placeholder": "pseudo", "label": "Pseudo", "optional": True},
            {"name": "host", "kind": "text", "placeholder": "hote", "label": "Hote"},
            {"name": "port", "kind": "text", "placeholder": "port (7777)", "label": "Port", "optional": True},
        ]},
        {"action": "jam-discover", "label": "Rechercher des jam sessions", "fields": []},
        {"action": "jam-connect-discovered", "label": "Rejoindre une session trouvee", "fields": [{"name": "value", "kind": "select", "list": "discoveredJamSessions", "useIndex": True}]},
        {"action": "jam-leave", "label": "Quitter la jam session", "fields": []},
    ]},
]


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
    response = httpx.get(f"{BASE_URL}/menu-action", params=query, timeout=10.0)
    response.raise_for_status()
    return response.json()


def _make_tool_function(action: str, fields: list[dict]):
    """Builds a real Python function with one named parameter per field (defaulting to `None`
    when `optional`), so FastMCP's signature-based schema introspection produces a proper
    per-action input schema — a plain `**kwargs` function wouldn't give it enough to work
    with. See this module's own docstring for why the definitions are hand-ported data rather
    than something generated from the Swift/JS side directly."""
    # Required params must precede defaulted ones in a Python signature — `fields` is
    # authored in the order that reads best in the tool's own description, which doesn't
    # always already put optional fields last (e.g. `composition-describe`'s middle
    # `value` field is required while `title` before it is optional).
    ordered_fields = sorted(fields, key=lambda f: bool(f.get("optional")))
    param_defs = []
    for field in ordered_fields:
        default = " = None" if field.get("optional") else ""
        param_defs.append(f"{field['name']}: str{default}")
    signature = ", ".join(param_defs)
    field_names = [f["name"] for f in fields]
    source = (
        f"def _tool({signature}):\n"
        f"    return _call_menu_action({action!r}, {{" + ", ".join(f"{n!r}: {n}" for n in field_names) + "})\n"
    )
    namespace = {"_call_menu_action": _call_menu_action}
    exec(source, namespace)  # noqa: S102 — building a real function per data-driven action, not arbitrary input
    return namespace["_tool"]


for category in ACTIONS:
    for item in category["items"]:
        tool_name = item["action"].replace("-", "_")
        field_docs = "\n".join(f"- {f['name']}: {_describe_field(f)}" for f in item["fields"])
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
    lists (e.g. `piece_load`'s `value`, `track_on`'s `value`) to see what's actually available
    right now — these lists can change from outside this MCP server too (the terminal, a
    browser tab, another jam-session participant)."""
    response = httpx.get(f"{BASE_URL}/menu-lists", timeout=10.0)
    response.raise_for_status()
    return response.json()


if __name__ == "__main__":
    mcp.run()
