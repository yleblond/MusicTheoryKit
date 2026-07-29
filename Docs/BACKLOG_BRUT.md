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

11. **Vérifier que les renommages (scène/guide) sont bien persistés**, pas juste visibles dans
    l'UI le temps de la session — confirmer que `renameCurrentScene`/`renameScene(atIndex:)` et
    leurs équivalents guide sauvent réellement en base (relancer l'app et vérifier que le nouveau
    nom tient).

12. **COMPOSITION : remplacer la logique de sous-onglets par le même schéma liste → écran de
    détail** déjà utilisé pour Scene/Guide (voir `SceneManagementView`) : afficher la liste des
    compositions, puis aller vers la composition sélectionnée. Si la liste est vide, montrer
    directement l'écran de création.

13. **MORCEAUX : même chose que Composition** — enlever la logique de sous-onglets, afficher la
    liste puis passer au morceau sélectionné. Différence explicite avec Composition : PAS de
    logique d'écran de création automatique si la liste est vide (Morceaux n'a pas cette notion).

14. **ENREGISTREMENTS : même schéma liste → détail** — afficher la liste des enregistrements,
    aller vers l'enregistrement sélectionné (avec l'option d'écoute), et y déplacer le bloc
    "composer à partir de cet enregistrement" (composition IA) directement dans cet écran plutôt
    que dans un sous-onglet séparé.

15. **GÉNÉRAL — gros chantier de navigation : supprimer le premier niveau de menu (les tabs
    actuels)**. L'appli serait directement en "mode studio", avec un toggle/bottom bar
    permettant de naviguer entre les fonctions actuelles du mode Studio (Scène, Guide, Live) ET
    les 3 autres tabs actuels (Morceaux, Enregistrements, Composition) — donc 6 items côte à
    côte, à plat, au même niveau. Plus un bloc en bas séparé avec :
    - un bouton "settings/studio" correspondant à l'actuel menu JamShack, qui bascule entre le
      mode réglages et le mode studio ;
    - un bouton pour afficher/activer/désactiver le clavier virtuel ordinateur directement
      depuis cet endroit.
