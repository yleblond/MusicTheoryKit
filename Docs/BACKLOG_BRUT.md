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

Les items 16/17 ont été implémentés et vérifiés le 2026-07-29 — mais avec une découverte
importante à la consolidation : les données des dossiers "Réglages"/"Composition IA" étaient déjà
sur CloudKit (SwiftData), ces dossiers ne servant plus qu'à une migration ponctuelle. Le vrai
travail effectué : suppression des 2 lignes de dossier devenues vestiges dans Réglages > Dossiers,
et ajout d'un nouvel onglet Réglages "Cadrages" (gestion des phrases de cadrage texte/soundtrack +
indications de style, avec suppression — capacité qui manquait même au CLI). Retirés d'ici.

Les items 19/20 ont été implémentés le 2026-07-29 : bug bloquant trouvé et corrigé au passage
(`ensureSceneReadyForLaunch()` ne se déclenchait jamais sur un tout premier lancement — corrigé
dans `ContentView.swift`), scène par défaut avec un rôle prêt à jouer (MIDI détecté préféré au
clavier virtuel), banc General MIDI système utilisé comme son par défaut sur macOS (iOS reste sur
le synthé sinus pour l'instant, cf. point 18) ; icônes suggérées par IA + choix manuel de secours
pour scènes/rôles/instruments favoris/claviers MIDI (nouveau composant `IconAssignmentButton`).
Vérifié en conditions réelles sur Simulateur iOS fraîchement installé (le point le plus à risque —
la scène/rôle par défaut) ; vérification complète des icônes limitée par l'écran verrouillé en
cours de session, à confirmer visuellement. Retirés d'ici.

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

18. **Gestion des soundfonts (dossier "Sons")** — une fois 16/17 traités, ce serait le dernier
    dossier fichier restant. Suggestions de design (index CloudKit + fichiers iCloud Drive/Application
    Support selon synchro, hash comme identité, gestion quota iCloud, imports multiples) rédigées
    dans `KnowledgeBase/SoundfontMgt/soundfontmgt.txt`. **Nécessite sa propre session de
    planification dédiée** (trop gros/structurant pour être traité à la volée) — pas d'exploration
    ni d'implémentation ici.

21. **Gestion de plusieurs microphones en entrée**, en plus du micro de base actuellement géré.

22. **Gestion de plusieurs sorties son** (casque, Bluetooth, etc.).

23. **Layout iPhone adapté** — l'app est aujourd'hui pensée/testée surtout pour macOS/iPad ; revoir
    la disposition pour un écran iPhone.
