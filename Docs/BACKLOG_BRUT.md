# Backlog brut — période de tests intensifs (2026-07-26 →)

Notes prises au fil de l'eau pendant une session d'usage/tests, une entrée par idée/bug/
ajustement signalé, sans tri ni mise en forme — la consolidation (déduplication, contexte,
priorité) se fait après coup dans `Docs/BACKLOG.md`. Ne pas polir ici, juste capturer vite.

Les items 1-4 et 6-10 (première fournée) ont été implémentés le 2026-07-26 (voir
`Docs/ARCHITECTURE.md` §JamShackUI/App et les commits correspondants) et retirés d'ici.

## Entrées

5. **Incorporer le serveur MCP (actuellement `mcp-server/`, Python externe) directement dans
   l'app Swift**, plutôt que de le garder comme process Python séparé à lancer/configurer à la
   main. Ajouter son démarrage dans le même sous-onglet que "Connexion LLM"
   (`JamShackLLMView`) — ce sous-onglet contiendrait alors deux sections : Connexion LLM et
   Serveur MCP. Point à éclaircir à la consolidation : le serveur MCP actuel est un simple
   proxy HTTP vers les routes `/menu-action`/`/menu-lists` déjà exposées par `WebConsole` (voir
   `mcp-server/README.md`) — un portage Swift devra définir son propre transport MCP (stdio
   pour un client comme Claude Desktop, ou HTTP+SSE), pas juste réutiliser tel quel le protocole
   HTTP existant. **Sorti explicitement d'un premier plan d'implémentation (2026-07-26)** — trop
   gros pour être bundlé avec le reste, mérite sa propre exploration dédiée.
