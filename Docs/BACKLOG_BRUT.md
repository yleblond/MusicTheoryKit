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

L'item 36 (freeze à la connexion d'un participant Jam Session distant) a été implémenté et
vérifié le 2026-08-14, dans la foulée de sa découverte : même correctif que celui du freeze
micro+clavier plus tôt cette session (`ImprovSession.mutateTrack`/`mutateTracks`, voir
[[feedback_improv_app_concurrency]]), appliqué cette fois à `addOrUpdateRemoteTrack`/
`removeRemoteTrack`/`removeAllRemoteTracks*`/`mergeRemoteSnapshot`. Deux pièges supplémentaires
rencontrés et corrigés en le faisant : (1) `handleServerMessage` (cas `.noteEvent`) vérifiait
l'existence d'une piste via `tracks.contains` — différer l'écriture réelle dans `tracks` rendait
ce test faux-négatif juste après une création ; corrigé par une nouvelle table à part,
synchrone et non-observée (`knownRemoteTrackIDs`), qui reflète l'état "réel" immédiatement même
pendant que l'écriture Observable est encore en attente ; (2) `updateRecognitionState` avait
elle-même un garde strict (`guard let index = tracks.firstIndex(...) else { return }`) qui
échouait encore pour la toute première note d'une piste distante fraîchement créée, même une
fois (1) corrigé — remplacé par un repli sur des valeurs par défaut raisonnables (label depuis
`wireIDText`, `soundEnabled` à `false`, `heldPitches` vide), sûr ici car rien en aval n'a
réellement besoin que la ligne existe déjà (`recognizers`/`samplers` sont indexés indépendamment
de `tracks`, et `samplers[track]` est toujours `nil` pour une piste `.remote`). Nouveau test de
régression `ImprovSessionNetworkTests.testConcurrentRemoteConnectionsAlongsideConnectedClientsPollingNeverHangs`
(connexions/annonces réseau concurrentes avec un polling de `connectedClients()`). `swift test`
(complet) et `xcodebuild JamShackApp_macOS` passent tous les deux. Retiré d'ici.

Les onglets Théorie "Tonnetz", "Intonations" et "Dissonances" ont été livrés courant début/mi-août
2026 sans passer par ce fichier (découverts après coup via un balayage des dates de modification,
pas suivis en amont) : Tonnetz (exploration harmonique), Intonations (mode A1 — tempérament
théorique fixe, précondition des items 26/29/30/33 ci-dessous), Dissonances (modèle de rugosité
sensorielle de Sethares sur le spectre réel du SoundFont actif, voir item 27 ci-dessous pour le
détail de ce qui est couvert et ce qui ne l'est pas). Voir `Docs/ARCHITECTURE.md` pour le détail.
Les trois onglets ont depuis gagné le détachement en fenêtre propre (`openWindow`/`WindowGroup`,
vérifié dans le code au 2026-08-16).

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

26. **Accordage/tempérament — mode A2 (intonation adaptative théorique)** — l'onglet Théorie
    "Intonations" (A1, théorique + fixe) est livré depuis début août 2026 ; sa précondition est
    donc remplie, reste à ajouter le mode dynamique : recalcule la
    correction de chaque voix en fonction de l'accord détecté en direct (`RecognizedChord`), via
    les rapports harmoniques théoriques (juste intonation ciblée sur l'accord courant, pas juste la
    tonique). Nécessite : une fonction de coût (dissonance + pénalité d'éloignement + pénalité de
    mouvement pour les notes déjà tenues), un mapping note tenue → rôle dans l'accord (tierce/
    quinte/etc. — n'existe pas encore, voir `PitchDisplayState`), et un lissage/glide pour les notes
    tenues lors d'un changement d'accord (`TuningTransition` dans la spec d'origine).

27. **Accordage/tempérament — mode B1 (spectre SF2 réel + fixe)** — PARTIELLEMENT couvert par
    l'onglet Théorie "Dissonances" livré le 2026-08-12/13 (`App/Sources/DissonancesLibraryView.swift`,
    `Sources/AppCore/SensoryDissonance.swift`, `OctaveSpectrumGrid`/`OctaveSpectrumGridBuilder` via
    `FFTPitchAnalyzer`+`OfflineNoteRenderer`) : le moteur d'analyse spectrale réelle du SoundFont
    (FFT sur les données PCM réelles, plus seulement les métadonnées `SoundFontPresetReader`) existe
    et fonctionne, exposé comme heatmap 2D de dissonance pour un accord à 3 notes au-dessus d'une
    tonique choisie, avec bouton d'audition "Jouer tempéré". Ce qui MANQUE encore pour clore
    vraiment l'item : ce n'est qu'un outil d'exploration/visualisation, pas un mode de tempérament
    intégré et sélectionnable dans l'onglet "Intonations" au même titre que A1 — il ne produit pas
    de disposition fixe des 12 notes réellement appliquée au jeu/à la lecture. Reste à faire pour
    clore : exposer ce moteur comme un vrai mode B1 dans `TuningLibraryView`/
    `VoiceChannelAllocator`, au même niveau qu'A1.

28. **Accordage/tempérament — mode B2 (spectre SF2 réel + adaptatif)** — le mode le plus avancé de
    la spec d'origine : optimisation en temps réel de chaque accord détecté à partir des partiels
    réellement mesurés dans les samples actifs (pas des partiels harmoniques idéaux). Le moteur
    spectral (`SensoryDissonance.swift`/`OctaveSpectrumGrid`) et le rendu heatmap 2D existent déjà
    depuis l'onglet Dissonances (voir item 27) — la partie neuve restante est surtout le
    branchement temps réel sur l'accord détecté (`RecognizedChord`) et l'intégration comme mode de
    lecture dans Intonations, pas la construction du graphe de dissonance lui-même. Le graphe 2D
    existant réutilise déjà la technique de rendu bitmap/`CGImage` (comme
    `SpectrogramView.makeWaterfallImage`) plutôt que des remplissages `Canvas` par cellule.

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

31. **Affichage des noms de notes/accords toujours en dièses** — `NotationStyle.rootName`/
    `PitchClass.name(preferFlats:)` n'utilisent qu'un booléen global, jamais la tonalité réelle du
    mode affiché ; Accords/Modes/Progressions affichent donc parfois des noms plausibles mais faux
    dans le contexte (ex. "G#" au lieu de "Ab" en La bémol majeur). Au moins 4 tables dièse/bémol
    par classe de hauteur sont dupliquées indépendamment dans le code (`PitchClass.swift`,
    `ChordStaffView.swift`, `CircleOfFifthsWheelView.swift`, `GuideEditionView.swift`), aucune
    consciente de la tonalité. `ChordStaffView` "triche" même pour le placement sur la portée : son
    `keySignature` ne sert qu'à supprimer un dièse/bémol redondant déjà indiqué à la clé, jamais à
    changer l'orthographe ou la ligne/interligne. Découvert en construisant `DiatonicSpelling`
    (voir le module `SpelledPitch`/`Temperament` pour la résolution correcte, utilisée pour l'instant
    uniquement par le moteur d'accordage) — un chantier à part, plus large (touche des écrans déjà
    livrés et stables), pas traité avec l'accordage.

32. **Résolution enharmonique par accord détecté (Accords) et par Guide** — le moteur d'accordage
    ne résout l'orthographe G#/Ab que par le mode sélectionné (Modes/Progressions/Exploration/
    Intonations). L'écran Accords n'a pas de tonique de référence, donc pas de tempérament fixe
    pertinent — mais une fois le mode A2 (accordage dynamique par accord détecté) construit, la
    résolution par accord ("E-G#-B ⇒ Mi majeur ⇒ G#" vs "Ab-C-Eb ⇒ La bémol majeur ⇒ Ab") devient
    nécessaire. Idem pour le Guide, une fois qu'il connaît le contexte harmonique courant.

33. **Module SPM dédié `TheoryTuning`** — la spécification d'origine propose de regrouper
    `Temperament`/`VoiceChannelAllocator`/`TuningConfiguration`/`SpelledPitch`/`DiatonicSpelling`
    (et, plus tard, les modes A2/B1/B2 + le graphe de dissonance) dans un module SPM séparé plutôt
    que dispersés dans `MusicTheoryKit`/`AppCore`. Prématuré tant que seul A1 existe ; à reconsidérer
    une fois A2/B1/B2 construits et la surface du module vraiment plus large.

34. **Extensions d'accords (7e, 9e...) en cliquant sur le Tonnetz via un modificateur clavier** —
    idée soulevée en construisant le mode optionnel/mise en valeur diatonique du Tonnetz : jouer
    une extension (7e, 9e...) d'un triangle tapé en maintenant une touche modificatrice. Nécessite
    d'établir une convention de touches (une touche par extension ? un seul modificateur qui fait
    défiler ?) et de clarifier l'interaction avec le mode clavier ordinateur déjà présent dans
    l'app (`ComputerKeyboardInputBar`/`MainKeyboardMode` — les touches physiques jouent déjà des
    notes, un conflit de modificateur est possible). Sujet à part, pas traité avec le reste du
    Tonnetz cette session.

35. ~~Bouton "Théorie" (légende en pop-up) — rétrofit sur les autres écrans Théorie~~ **FAIT et
    ÉLARGI le 2026-08-16** : la demande initiale (4 écrans Théorie) a été étendue par l'utilisateur
    à **tous les écrans de l'application** (24 écrans de haut niveau), avec une refonte du format de
    rédaction. Livré :
    - `HelpTopicID` (`App/Sources/HelpTopicID.swift`, `String, CaseIterable`, 24 cas) + `HelpContentView`
      (`Sources/JamShackUI/HelpContentView.swift`) remplacent le pattern "une struct par écran" —
      un titre + un corps markdown par écran (`AttributedString(markdown:)` natif, aucune dépendance
      tierce ; mode `.inlineOnlyPreservingWhitespace` choisi après vérification empirique : préserve
      les sauts de ligne littéralement, gras/italique/liens fonctionnent, mais PAS les titres/listes
      markdown — convention de rédaction : texte plat, "•" littéraux, ligne vide = nouveau
      paragraphe).
    - Hypertexte entre écrans liés : liens `[texte](jamshackhelp://<id>)` interceptés par
      `View.interceptHelpLinks` (posé indépendamment sur `ContextualHelpWindow` ET la feuille iOS/
      iPadOS de `ContentView` — deux hiérarchies SwiftUI séparées) → `AppModel.pinnedHelpTopic`,
      avec bouton "Retour". Utilisé par ex. Accords→Progressions/Tonnetz, Modes→Exploration,
      Intonations→Dissonances.
    - Les 24 écrans enregistrent leur aide (bottom-bar "?" partagé, qui marche déjà partout
      automatiquement) ; en plus, l'icône "book.closed" sur écran est posée aux 10 écrans qui ont
      déjà un coin "détacher" (Accueil, Studio Scène/Live/Guide, les 5 Théorie restants, Réglages >
      Microphone) — pas d'UI neuve inventée ailleurs. `RunScreen` (Studio > Live) reste sans icône
      dédiée : c'est une vue du package `JamShackUI`, qui ne peut pas référencer les types
      App-only (`HelpTopicID`/`TheoryHelpButton`) ; le "?" partagé y fonctionne normalement.
    - `TonnetzHelpContent`/`TheoryLegendContent`/`FunctionalMapHelpContent`/`MelodicMapHelpContent`
      retirés (16+5 anciennes clés L10n consolidées en 4 nouvelles : titre+corps pour Tonnetz et
      pour Exploration).
    - Contenu français rédigé comme premier jet pour les 22 écrans qui n'en avaient aucun — **pas
      encore traduit dans les 8 autres langues** (dupliqué tel quel dans `L10nTable.json` en
      attendant une vraie passe de traduction, même convention que le reste de l'app).
    - Vérifié : `swift build`/`swift test` (649/649) et `xcodebuild JamShackApp_macOS` verts.
      **Non vérifié visuellement** : capture d'écran impossible dans cet environnement (écran
      verrouillé ou permission manquante) — le rendu réel (espacement des paragraphes, liens
      cliquables, bascule "Retour") reste à confirmer par l'utilisateur à l'usage.
