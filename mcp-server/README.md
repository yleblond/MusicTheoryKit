# JamShack MCP server (experimental)

A small MCP server that exposes JamShack's web-console "Commandes" tab as MCP tools, so an
MCP-aware assistant (Claude Desktop, Claude Code, etc.) can drive the app directly from a
prompt — load/save pieces, start/stop tracks, run a guide, compose from a description, manage
a jam session, and so on.

This is a **thin proxy**, not a reimplementation: every tool call turns into an HTTP request
against JamShack's own web console (`GET /menu-action`, `GET /menu-lists`), the exact same
endpoints the "Commandes" tab in a browser uses. No app logic lives here.

**Experimental, v1**: every action is exposed with no finer-grained permission model yet — all
or nothing. A more selective mechanism (e.g. read-only vs. mutating, or a user-approved
allowlist) is a deliberate later step, not an oversight.

## Prerequisites

The JamShack web console must already be running before this server can do anything useful:

```
swift run JamShack
> web-console 8080
```

(or the "Demarrer la console web..." item in the terminal's own menu / the web console's
"Commandes" tab, if a console is already up on some other port).

## Setup

```
cd mcp-server
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

## Configuring in an MCP client

Point the client at `.venv/bin/python3 server.py`. For Claude Desktop/Claude Code's MCP config
(JSON), something like:

```json
{
  "mcpServers": {
    "jamshack": {
      "command": "/absolute/path/to/mcp-server/.venv/bin/python3",
      "args": ["/absolute/path/to/mcp-server/server.py"],
      "env": { "JAMSHACK_BASE_URL": "http://localhost:8080" }
    }
  }
}
```

`JAMSHACK_BASE_URL` defaults to `http://localhost:8080` (the web console's own default port)
if not set — only needed if you started `web-console` on a different port.

## What's exposed

- One tool per action in the terminal's own pull-down menu (mirrors `MENU_ACTIONS` in
  `Sources/WebConsole/StaticAssets.swift`, hand-ported into `ACTIONS` in `server.py` — keep
  the two in sync by hand if the menu ever changes), e.g. `piece_load`, `track_on`,
  `guide_add_mode`, `composition_describe`, `jam_start`, `scene_role_attach`. Pure read-only
  displays (status/run/scene-tree/show-*) are deliberately not included — same scope as the
  web console's own "Commandes" tab.
- `get_menu_lists` — fetches the current valid values for every dropdown-backed parameter
  (piece/sample/soundtrack/guide/scene/composition files, LLM connections, color palettes,
  chord progression templates, the 33 scales, currently-known tracks, MIDI fusion mode, and
  the last jam-session discovery scan). An assistant should call this before an action whose
  parameter comes from one of these lists, since they can change from outside this server too
  (the terminal, a browser tab, another jam-session participant).
- `get_piece_detail` / `get_composition_description` / `get_guide_sequence_detail` /
  `get_soundtrack_detail` — read-only content/structure, not just dropdown filenames or live
  playback state: full piece structure (sections, chords with resolved labels, every track's
  actual melody notes — including tracks with zero notes, unlike the terminal's own piece
  display), the composition currently staged for AI generation (title/source text/
  instructions/resolved prompt), the full guide sequence (every step's mode+chords, not just
  the current one), and the current soundtrack's events. Added after an assistant got stuck
  mid-composition unable to answer "how many sections does this piece have" — nothing in
  `get_menu_lists`/the app's live state exposed that at all.

`guide_add_mode`'s `tonic` parameter is the one place this server translates on your behalf:
it accepts a note name (`"C"`, `"D"`, `"F#"`, ...) and converts it to the pitch-class index the
HTTP endpoint actually expects — the web UI's own `<select>` does the same translation
client-side.

**`composition_describe`'s `source_text` parameter is the terminal's `paste-text`** — there is
no separate "paste text" tool. An assistant hit exactly this confusion once (the parameter used
to be exposed as a generic `value`, giving no hint that it was the composition's actual source
material) and reported being stuck with nothing to call — every action's primary parameter is
now given an explicit, descriptive name instead of a bare `value` (`track_id`, `piece_name`,
`folder_path`, `source_text`, ...) for exactly this reason.

**`composition_compose`/`soundtrack_compose` can legitimately take a while** (they call an
LLM) — JamShack itself has no timeout for this, so it always worked fine from the terminal;
this server used to apply a flat 10-second HTTP timeout to every action, which aborted these
two specifically before the model could respond. Fixed by giving just these two a much longer
timeout (`LONG_RUNNING_ACTIONS` in `server.py`) while keeping every other (fast, local)
action's timeout short.

**Scene roles** (`scene_new`, `scene_role_add`, `scene_role_sound`, `scene_role_listen`,
`scene_role_attach`, `scene_role_detach`) let an assistant declare named musical positions
("Piano 1", "Basse Guitare") and attach a live instrument to one — see `Docs/ARCHITECTURE.md`'s
"Rôles de scène" section for the full design. `scene_role_attach`'s `track_id` should come from
`get_menu_lists()['unassignedTracks']` (instruments not already attached to a role), not the
plain `tracks` list. A role attached to a remote/network participant's instrument is not yet
supported here — local/standalone only for now (a network-claiming phase is designed and
deliberately deferred, see `Docs/BACKLOG.md`).
