# Backlog

Idées et chantiers identifiés mais pas encore engagés. Chaque entrée garde le contexte
nécessaire pour être reprise sans redérivation ; à supprimer ou déplacer vers le README/
CHANGELOG une fois traitée.

## Stabilisation de l'environnement (2026-07-11)

1. **Remplacer les queues série manuelles de `ImprovSession` par un `actor`.** La concurrence
   repose aujourd'hui sur la discipline (queues dédiées + compteur `playbackGeneration` à
   vérifier à chaque nouvelle feature touchant l'état partagé), pas sur le compilateur. Trois
   crashs réels ont déjà eu lieu sur exactement ce pattern (voir l'historique de
   `ImprovSession.swift`). Passer l'état mutable en `actor` ferait respecter l'isolation par
   le type-system plutôt que par une règle à se rappeler. À faire une fois le point 2
   ci-dessous en place (filet de sécurité avant refactor).
2. **Ajouter des stress-tests automatisés dans `Tests/AppCoreTests`** pour les scénarios déjà
   connus fragiles (notes rapprochées au clavier ordinateur, `play()` appelé en
   chevauchement) — un seul run propre ne prouve rien pour ce genre de bug de concurrence
   intermittente. Une variante "répéter N fois" transformerait une vérification manuelle par
   session pty en filet permanent, exécuté à chaque `swift test`.
3. ~~Revérifier le binding réseau avant tout usage hors LAN de confiance.~~ **FAIT le
   2026-08-16** : les trois serveurs (`HTTPServer` pour console web/clavier virtuel,
   `NetworkServer` pour Jam Session) posent maintenant `NWParameters.prohibitedInterfaceTypes =
   [.cellular]`, ce qui exclut le routage par données mobiles (ex. partage de connexion) — jamais
   un appareil du même LAN. `GameCenterTransport` (un pair `GKMatch`, pas `NWListener`) n'est pas
   concerné, pas de port local à restreindre. **Limite explicitement assumée, pas corrigée ici** :
   ceci ne protège PAS contre un autre appareil sur le même Wi-Fi (même non fiable — café,
   conférence) — Network.framework n'a aucune notion de "Wi-Fi de confiance", l'absence
   d'authentification/chiffrement documentée dans le README reste entière. Web console et clavier
   virtuel gardent leur liaison LAN volontaire (`HTTPServer.start(port:host:)` avec `host: nil`) —
   seul le pont MCP (`host: "127.0.0.1"`) reste loopback-only, ce qui était déjà correct avant ce
   correctif.
4. ~~Synchroniser `colorPalettes`/`activeColorPaletteIndex` par une queue dédiée~~ **FAIT le
   2026-08-16** : `colorPaletteQueue` (même fichier, même discipline que `liveInputQueue`/
   `playbackStateQueue`) protège maintenant `refreshColorPalettes()`/
   `migrateColorPalettesFromJSONIfNeeded`/`selectColorPalette(atIndex:)` en écriture, et une
   nouvelle méthode `activeColorPaletteSnapshot()` (lecture synchronisée) remplace `activeColorPalette`
   aux deux sites background (`buildWebConsoleState()`, `handleVirtualKeyboardRequest`) qui
   causaient le crash TestFlight du 2026-08-01. Les lectures directes main-thread (SwiftUI, CLI)
   gardent `activeColorPalette` tel quel, sans changement de comportement. `swift test` (649/649)
   et `xcodebuild JamShackApp_macOS` verts.

## Fonctionnalités (2026-07-11)

1. **Meilleure détection micro pour le jeu au piano.** Le piano introduit trois sources de
   fausses notes que la détection FFT actuelle ne filtre pas :
   - harmoniques hautes réelles de la note jouée (sur un do : le do à l'octave, le sol qui
     suit, etc.),
   - résonances internes de l'instrument (sur un do : vibration sympathique d'un do deux
     octaves en dessous),
   - battements/pulsation dus au mode d'accord.

   Pistes à explorer :
   - moyenner les notes reconnues sur une fenêtre glissante plus large que la fenêtre
     d'échantillonnage/FFT, et éliminer les notes qui n'apparaissent que par intermittence ;
   - détecter le niveau moyen des pics spectraux pour établir un seuil de filtrage — les
     harmoniques/résonances sont typiquement plus faibles que la fondamentale réellement
     jouée.

2. **Clavier virtuel : adapter la taille du piano à la largeur de la page (mode paysage).**
   Aujourd'hui le piano a une largeur fixe en pixels par touche (`WHITE_KEY_WIDTH`), calculée
   uniquement à partir du nombre de touches visibles — sur un écran large/en paysage (tablette,
   grand moniteur), il reste petit au lieu de profiter de l'espace disponible. Explicitement
   noté par l'utilisateur comme pouvant être fait séparément du reste. Pistes à explorer :
   recalculer `WHITE_KEY_WIDTH` (et donc `BLACK_KEY_WIDTH`, les décalages de touches noires,
   `MINI_WHITE_WIDTH`...) à partir de la largeur de `.layout-col-right` plutôt qu'une constante
   fixe, en gardant une taille minimale lisible sur mobile étroit ; recalculer sur
   `resize`/orientation change, pas seulement au chargement.

3. **Rôles de scène : revendication par un client réseau connecté.** Le round du 2026-07-12
   (`Docs/ARCHITECTURE.md`, section "Rôles de scène") a livré la partie locale/standalone
   (déclarer des rôles, attacher un instrument, réattache automatique au rechargement) ; la
   demande initiale incluait aussi qu'un instrument connecté via un client réseau puisse
   revendiquer un rôle libre sur une scène partagée. Conception complète déjà faite et
   documentée (autorité serveur, nouveaux cas `NetMessage` `.roleClaim`/`.roleRelease`/
   `.roleClaimRejected`/`.roleSync`, résolution des conflits gratuite via la queue série déjà
   partagée par toutes les connexions, pas de délai de grâce à la déconnexion) — voir
   `Docs/ARCHITECTURE.md` pour le détail, prête à implémenter sans reprendre ce qui précède
   (`InstrumentIdentityHint` n'a délibérément pas de cas `.remote` encore, c'est le point
   d'extension prévu).

## App SwiftUI (2026-07-25)

1. **Stockage des clefs API LLM dans le Trousseau (Keychain), pas en texte clair.** L'app
   SwiftUI (contrairement au CLI, qui lit une vraie variable d'environnement positionnée
   avant le lancement) n'a aucun moyen pratique de faire saisir une variable d'environnement
   par l'utilisateur — l'onglet JamShack > LLM permet donc de taper la clef directement, mais
   elle est aujourd'hui sauvegardée en JSON texte clair (`LLMAPIKeysFile`,
   `Sources/AppCore/LLMAPIKeysFile.swift`, fichier `llm-api-keys.json` dans le dossier
   Reglages) — accessible à quiconque a accès à ce dossier (par ex. tout appareil synchronisé
   sur le même compte iCloud Drive, si le dossier Reglages y est). Décision explicite de
   l'utilisateur : accepter ce compromis pour débloquer l'usage GUI maintenant, migrer plus
   tard vers le Trousseau (`Security.framework`/`Keychain Services`, ou
   `kSecClassGenericPassword`) sans changer la surface d'API (`ImprovSession.setLLMAPIKey`/
   `APIKeyStore.resolve` dans `Sources/LLMEngine/APIKeyStore.swift` resteraient les mêmes
   points d'entrée, seule l'implémentation de la persistance changerait).

## visionOS — fonctionnalités spatiales (2026-08-01)

Bloqué en attendant un Vision Pro physique : ni le hand-tracking ni un vrai flux passthrough
pour caler un overlay sur un clavier réel ne sont testables dans le simulateur visionOS — seule
la compilation/revue de code est vérifiable sans casque. Les deux points ci-dessous documentent
l'architecture déjà dégrossie et les briques réutilisables déjà identifiées dans le code, pour
être directement exploitables plus tard sans redérivation.

**Briques déjà réutilisables pour les deux fonctionnalités** (rien n'existe encore côté
ARKit/RealityKit/ImmersiveSpace dans ce repo — terrain vierge pour le rendu 3D, mais la logique/
données existent déjà) :
- Injection de note générique : `ImprovSession.pressKey(pitch:track:)`/`releaseKey(pitch:track:)`
  (`Sources/AppCore/ImprovSession.swift:3838`) — son propre commentaire anticipe déjà "a future
  on-screen/touch virtual keyboard".
- Pattern de piste dynamique à répliquer : `TrackID.webKeyboard(clientID:)`
  (`Sources/AppCore/Track.swift`) + `ensureWebKeyboardTrack`/`removeAllWebKeyboardTracks`
  (`ImprovSession.swift:5731`/`5746`) — un nouveau cas (ex. `.handTracking`) suivrait ce même
  patron (piste créée/détruite à la demande, ajoutée à la liste blanche "dynamique" de
  `refreshTracks()` vers la ligne 2931-2936).
- Calcul couleur par touche déjà centralisé : `pitchDisplayState(pitch:heldPitches:chordRoot:
  chordTones:modeTones:...)` (`Sources/AppCore/PitchDisplayState.swift`), alimenté par
  `ImprovSession.pitchClassSets(...)` (ligne 5902) à partir du `recognizedChord`/
  `recognizedModes` d'une piste en écoute ; rôle → couleur hex via `NoteColorSettingsFile`
  (`Sources/AppCore/NoteColorSettings.swift`). Le chemin LUMI (`LumiColorMap`/`LumiGuideMap`,
  SysEx) est une fausse piste ici — plus pauvre (2 couleurs, pas les 6 rôles) et pensé pour
  piloter du matériel, pas pour de l'affichage.
- Géométrie clavier : `PitchKeyboardView.layout(for:)` (`Sources/JamShackUI/PitchKeyboardView.swift:197`,
  actuellement `internal`) a déjà tout le calcul touche blanche/noire → position. À extraire
  dans un petit type `public` partagé (ex. `PianoKeyGeometry`) pour être appelable à la fois par
  la vue existante et par le nouveau code AR/hand-tracking, qui vivra dans le target App (module
  SPM différent de `JamShackUI`).
- Nouveau réglage requis : `NSHandsTrackingUsageDescription` dans `App/project.yml` (Info.plist
  partagé) — API standard visionOS 2, aucun entitlement entreprise nécessaire.

1. **Clavier virtuel jouable au hand-tracking** (mains en l'air, comme le clavier virtuel
   système pour le texte). Suggéré en premier : pose les fondations `ImmersiveSpace`/ARKit
   communes aux deux fonctionnalités. Architecture : nouvelle scène `ImmersiveSpace` (visionOS
   uniquement) dans `App/Sources/JamShackApp.swift`, style `.mixed` (passthrough conservé,
   pas de VR complète) ; `ARKitSession` + `HandTrackingProvider` (mise à jour 90Hz sur
   visionOS 2) ; clavier flottant en RealityKit positionné via `PianoKeyGeometry` ; détection
   doigt/touche par simple test de proximité (bounding volume) pour un premier prototype, pas
   de détection de vélocité/pression sophistiquée dans un premier temps ; appelle
   `pressKey(pitch:track: .handTracking)`/`releaseKey(...)` sur entrée/sortie de volume.

2. **Overlay AR qui colore les touches d'un clavier réel** selon le mode/accord reconnu en
   direct — même idée que l'intégration LUMI Keys existante, mais en réalité augmentée plutôt
   que sur du matériel. Réutilise la Phase 1 ci-dessus. Calibration **manuelle** (décision
   explicite de l'utilisateur, plutôt que `ObjectTrackingProvider`/reconnaissance d'objet
   pré-scanné) : l'utilisateur aligne par glisser/pincer un repère virtuel semi-transparent
   (même géométrie `PianoKeyGeometry`) sur son clavier réel, puis verrouille — ancré via
   `WorldTrackingProvider`/`WorldAnchor` pour rester en place spatialement. Fonctionne avec
   n'importe quel clavier, sans étape de scan préalable hors app (contrairement à
   `ObjectTrackingProvider`, qui ne suivrait que le clavier précis scanné via l'app Object
   Capture d'Apple). Par touche réelle dans la plage calibrée : `pitchDisplayState(...)` →
   couleur via `NoteColorSettingsFile` → quad RealityKit coloré positionné selon la
   calibration, rafraîchi au rythme de `bridge.state` (~30Hz déjà utilisé ailleurs, à limiter
   si coût de rendu trop élevé). Purement en lecture — aucun nouveau `pressKey`/`TrackID`
   nécessaire ici. Limite connue à noter pour un premier prototype : pas de persistance de la
   calibration entre lancements (à refaire à chaque session) — amélioration possible plus
   tard.
