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

L'item 18 (gestion des soundfonts) a été implémenté et fermé le 2026-07-30 : index CloudKit par
hash de contenu (fini le path-based fragile), stockage hybride iCloud Drive/local avec politique
adaptative par profil d'appareil (Économe/Standard/Généreux), imports multiples (fileImporter,
drag & drop, "Ouvrir dans…"), catalogue de banques offertes embarqué dans l'app (pas de serveur —
choix explicite de l'utilisateur), téléchargement direct depuis la source avec progression réelle
et bouton d'abandon, vérification d'intégrité (sha256) avec repli propre, écran Crédits pour les
licences l'exigeant, et un onglet "Stockage" dédié (profil, seuils par pas de 500 Mo, nettoyage
complet). Dette connue et assumée, pas un oubli : le catalogue ne compte qu'une seule entrée
vérifiée (MuseScore General) — FluidR3 GM était injoignable à la curation, et tout le fonds
FreePats n'est distribué qu'en archives `.7z`/`.tar.xz` qu'aucune API Apple ne sait décompresser
(nécessiterait un extracteur dédié, hors périmètre). Étoffer le catalogue au fil du temps (curation
manuelle par entrée) reste ouvert, mais n'est plus un blocage structurant. Retiré d'ici.

L'item 5 (serveur MCP embarqué) a été implémenté et vérifié le 2026-07-30 : `MCPServer.swift`
embarque un vrai serveur MCP (SDK `modelcontextprotocol/swift-sdk`) macOS uniquement, en
réutilisant le transport HTTP fait main de `WebConsole` (`HTTPConnection` a appris à lire un
corps de requête `Content-Length` pour l'occasion) plutôt que de réinventer un transport. Comme
Claude Desktop n'accepte qu'une entrée `"command"` (jamais une simple URL) dans sa
configuration, une seconde cible exécutable dédiée (`JamShackMCPBridge`) traduit le framing
stdio newline-delimited de Claude Desktop vers des requêtes HTTP contre ce serveur — toute la
logique reste dans le process de l'app, le pont est délibérément bête. Bascule dans le panneau
"I.A." (`JamShackAIView`, pas `JamShackLLMView` comme envisagé initialement — placée avec les
autres réglages IA plutôt qu'avec la connexion LLM). 84 actions de menu portées à la main
(`MCPToolDefinitions.swift`, portage de `MENU_ACTIONS`) plus les 4 tools de lecture déjà
existants côté ancien serveur Python. Vérifié : `swift test` (488/488) et `xcodebuild` du
scheme `JamShackApp_macOS` passent tous les deux, tests dédiés `MCPServerTests`/
`MCPBridgeTests`/`HTTPWireFormatTests` (nouveaux cas). **Pas encore vérifié** : connexion
bout-en-bout avec une vraie installation de Claude Desktop. Le dossier `mcp-server/` (Python,
superseded) reste sur disque pour l'instant — son retrait est une décision distincte, pas
encore prise. Retiré d'ici.

## Entrées

21. **Gestion de plusieurs microphones en entrée**, en plus du micro de base actuellement géré.

22. **Gestion de plusieurs sorties son** (casque, Bluetooth, etc.).

23. **Layout iPhone adapté** — l'app est aujourd'hui pensée/testée surtout pour macOS/iPad ; revoir
    la disposition pour un écran iPhone.
