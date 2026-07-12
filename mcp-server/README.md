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
  `guide_add_mode`, `composition_describe`, `jam_start`. Pure read-only displays
  (status/run/scene-tree/show-*) are deliberately not included — same scope as the web
  console's own "Commandes" tab.
- `get_menu_lists` — fetches the current valid values for every dropdown-backed parameter
  (piece/sample/soundtrack/guide/scene/composition files, LLM connections, color palettes,
  chord progression templates, the 33 scales, currently-known tracks, MIDI fusion mode, and
  the last jam-session discovery scan). An assistant should call this before an action whose
  parameter comes from one of these lists, since they can change from outside this server too
  (the terminal, a browser tab, another jam-session participant).

`guide_add_mode`'s `tonic` parameter is the one place this server translates on your behalf:
it accepts a note name (`"C"`, `"D"`, `"F#"`, ...) and converts it to the pitch-class index the
HTTP endpoint actually expects — the web UI's own `<select>` does the same translation
client-side.
