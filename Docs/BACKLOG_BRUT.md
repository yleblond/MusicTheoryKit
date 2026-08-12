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

24. **Représentation visuelle du rôle des accords dans un mode** (tension, résolution, etc.) —
    trouver un moyen visuel (couleur ?) de représenter le rôle fonctionnel de chaque accord
    (tonique/sus-tonique/médiante/sous-dominante/dominante/sus-dominante/sensible, voir
    `FunctionalHarmonyTable`), pas juste son nom. Chercher dans les dictionnaires musicaux la
    signification de chaque rôle (tension/résolution/couleur modale, etc.) et voir si une
    convention de couleurs par rôle existe déjà quelque part (théorie académique, logiciels de
    composition) avant d'en inventer une.

25. **Réglages > couleurs des écrans Théorie** — `TheorieSettingsView` (Settings > "Music Lab") a
    été supprimé (2026-08-09) une fois son seul contenu (le son d'écoute) devenu redondant avec le
    picker déjà présent sur la barre clavier principal en mode Théorie. Si la personnalisation de
    couleurs ci-dessous est reprise, il lui faudra un nouvel emplacement — le tab Settings
    "Couleurs" existant (`SettingsTab.couleurs`) est le candidat naturel. Idée d'origine, toujours
    valable : personnaliser les 4 rôles harmoniques (accords — `FunctionalRoleColors`), les 5 rôles
    mélodiques (notes — `MelodicRoleColors`), et l'accent "caractéristique modale" (violet, partagé
    par les deux). Probablement un SwiftData singleton du même genre que `NoteColorSettingsFile`,
    avec des valeurs par défaut = les couleurs actuelles codées en dur.

26. **Accordage/tempérament — mode A2 (intonation adaptative théorique)** — une fois l'onglet
    Music Lab "Intonations" (A1, théorique + fixe) livré, ajouter le mode dynamique : recalcule la
    correction de chaque voix en fonction de l'accord détecté en direct (`RecognizedChord`), via
    les rapports harmoniques théoriques (juste intonation ciblée sur l'accord courant, pas juste la
    tonique). Nécessite : une fonction de coût (dissonance + pénalité d'éloignement + pénalité de
    mouvement pour les notes déjà tenues), un mapping note tenue → rôle dans l'accord (tierce/
    quinte/etc. — n'existe pas encore, voir `PitchDisplayState`), et un lissage/glide pour les notes
    tenues lors d'un changement d'accord (`TuningTransition` dans la spec d'origine).

27. **Accordage/tempérament — mode B1 (spectre SF2 réel + fixe)** — analyser le spectre réel des
    samples d'un SoundFont (FFT sur les données PCM réelles, pas seulement les métadonnées lues par
    `SoundFontPresetReader` aujourd'hui — lire `sdta`/`shdr`/`ibag`/`igen` est un travail neuf,
    seule la marche RIFF bas niveau est réutilisable) pour proposer une disposition fixe des 12
    notes optimisée pour les résonances réelles de cet instrument précis (pas un tempérament
    historique). Presque gratuit une fois le mode B2 construit (réutilise son moteur spectral).

28. **Accordage/tempérament — mode B2 (spectre SF2 réel + adaptatif)** — le mode le plus avancé de
    la spec d'origine : optimisation en temps réel de chaque accord détecté à partir des partiels
    réellement mesurés dans les samples actifs (pas des partiels harmoniques idéaux). Inclut le
    graphe de dissonance 2D (surface/carte de contours pour un accord à 3 notes, axes = offset en
    cents des 2 notes non-fondamentales) — techniquement, réutiliser la technique de rendu bitmap/
    `CGImage` de `SpectrogramView.makeWaterfallImage` plutôt que des remplissages `Canvas` par
    cellule (bien trop lent pour une grille 2D, cf. commentaire de ce fichier).

29. **Accordage/tempérament — optimisation de trajectoire sur une progression (Guide)** — une fois
    A2/B2 en place, le Guide musical connaît potentiellement l'accord suivant d'une progression ;
    il pourrait optimiser non seulement l'accord courant mais la meilleure trajectoire d'accordage
    sur toute la progression (minimiser les sauts de hauteur des notes communes entre accords
    successifs).

30. **Accordage/tempérament — Studio** — envisageable uniquement pour le sous-ensemble purement
    théorique fixe (A1), jamais le mode spectral (B1/B2) : en Studio plusieurs instruments jouent en
    parallèle, et l'analyse spectrale est intrinsèquement par-instrument (l'appliquer à plusieurs
    instruments simultanés ferait exploser la complexité). Même en A1, vérifier la pression sur les
    16 canaux MIDI disponibles par piste avant d'activer (un accord de 7e + une mélodie sur un seul
    instrument utilise déjà ~5-6 canaux ; avec 2-3 instruments actifs en Studio, la marge devient
    vite serrée).
