# Backlog brut — période de tests intensifs (2026-07-26 →)

Notes prises au fil de l'eau pendant une session d'usage/tests, une entrée par idée/bug/
ajustement signalé, sans tri ni mise en forme — la consolidation (déduplication, contexte,
priorité) se fait après coup dans `Docs/BACKLOG.md`. Ne pas polir ici, juste capturer vite.

Les items 1-4 et 6-10 (première fournée) ont été implémentés le 2026-07-26 (voir
`Docs/ARCHITECTURE.md` §JamShackUI/App et les commits correspondants) et retirés d'ici.

Les items 11 (vérification persistance renommages — confirmé OK sans changement de code) et
12/13/14 (refonte liste → détail Composition/Morceaux/Enregistrements) ont été implémentés et
vérifiés le 2026-07-29 et retirés d'ici.

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

15. **GÉNÉRAL — gros chantier de navigation : supprimer le premier niveau de menu (les tabs
    actuels)**. L'appli serait directement en "mode studio", avec un toggle/bottom bar
    permettant de naviguer entre les fonctions actuelles du mode Studio (Scène, Guide, Live) ET
    les 3 autres tabs actuels (Morceaux, Enregistrements, Composition) — donc 6 items côte à
    côte, à plat, au même niveau. Plus un bloc en bas séparé avec :
    - un bouton "settings/studio" correspondant à l'actuel menu JamShack, qui bascule entre le
      mode réglages et le mode studio ;
    - un bouton pour afficher/activer/désactiver le clavier virtuel ordinateur directement
      depuis cet endroit.
