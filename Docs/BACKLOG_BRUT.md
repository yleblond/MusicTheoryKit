# Backlog brut — période de tests intensifs (2026-07-26 →)

Notes prises au fil de l'eau pendant une session d'usage/tests, une entrée par idée/bug/
ajustement signalé, sans tri ni mise en forme — la consolidation (déduplication, contexte,
priorité) se fait après coup dans `Docs/BACKLOG.md`. Ne pas polir ici, juste capturer vite.

Les items 1-4 et 6-10 (première fournée) ont été implémentés le 2026-07-26 (voir
`Docs/ARCHITECTURE.md` §JamShackUI/App et les commits correspondants) et retirés d'ici.

Les items 11 (vérification persistance renommages — confirmé OK sans changement de code),
12/13/14 (refonte liste → détail Composition/Morceaux/Enregistrements) et 15 (refonte navigation
globale — mode studio à plat + toggle Réglages) ont été implémentés et vérifiés le 2026-07-29 et
retirés d'ici.

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

16. **Le dossier "Réglages" (`JamShackFoldersView`, `session.settingsFolder`) devrait passer en
    CloudKit** plutôt que rester un dossier fichier à choisir manuellement — avec, si possible, un
    jeu de valeurs par défaut fourni à la première installation de l'app (pas d'écran "choisis un
    dossier" pour un nouvel utilisateur).

17. **Le dossier "Composition IA - Prompts" (`session.promptsFolder`) devrait aussi passer en
    CloudKit**, dans le même esprit que le point 16. Idée associée : un nouvel onglet dans
    Réglages permettant d'en créer/gérer plusieurs (différents cadrages de prompt), plutôt qu'un
    unique dossier.

18. **Gestion des soundfonts (dossier "Sons")** — une fois 16/17 traités, ce serait le dernier
    dossier fichier restant. Suggestions de design (index CloudKit + fichiers iCloud Drive/Application
    Support selon synchro, hash comme identité, gestion quota iCloud, imports multiples) rédigées
    dans `KnowledgeBase/SoundfontMgt/soundfontmgt.txt`. **Nécessite sa propre session de
    planification dédiée** (trop gros/structurant pour être traité à la volée) — pas d'exploration
    ni d'implémentation ici.
