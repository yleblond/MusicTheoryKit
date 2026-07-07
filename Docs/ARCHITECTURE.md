# Documentation technique — Music Improv Assistant

Documentation du code généré dans ce package Swift. Reflète l'état du code à la fin de la
session du 2026-07-07. Pour l'historique détaillé des décisions/itérations, voir la mémoire
`project_improv_app_roadmap.md`.

## Vue d'ensemble

Une application Swift Package Manager, orchestrée aujourd'hui par un front-end en ligne de
commande (`ImprovCLI`), mais dont toute la logique métier vit dans une couche
présentation-agnostique (`AppCore`) pensée pour qu'une future interface SwiftUI puisse s'y
brancher sans rien réécrire.

**Contrainte d'environnement importante** : cette machine n'a que les Command Line Tools,
pas Xcode complet. `swift test` échoue donc (`XCTest` indisponible). Deux filets de sécurité
existent :
- Chaque fonctionnalité a un vrai fichier `XCTest` dans `Tests/` (prêt pour le jour où Xcode
  sera installé), **et**
- Un exécutable `SanityChecks` qui reproduit chaque cas de test à la main (`check`/`checkNil`)
  et s'exécute avec `swift run SanityChecks`. C'est le seul moyen de vérifier la logique dans
  cet environnement — toujours le maintenir à jour en même temps que les vrais tests.

Il n'y a pas de dépôt git sur ce projet.

## Carte des modules (targets SwiftPM)

```
MusicTheoryKit  (théorie musicale pure, aucune dépendance)
      ↑
PieceModel      (modèle de morceau, Codable)      RecognitionEngine  (reconnaissance)
      ↑                                                  ↑
AudioEngine     (lecture + micro/FFT)             MIDIEngine (CoreMIDI, sans dépendance)
      ↑                    ↑                             ↑
      └────────────────────┴──────────────┬──────────────┘
                                           │
                              LLMEngine (composition IA)
                                           │
                                       AppCore
                          (ImprovSession — logique applicative)
                                           │
                                      ImprovCLI
                           (REPL + écran "console" + menus DOS)
```

`SanityChecks` (exécutable séparé) dépend de tout, pour pouvoir exécuter tous les cas de
test manuellement.

---

## MusicTheoryKit — théorie musicale

Bibliothèque pure (aucune dépendance externe), source de vérité pour tout ce qui touche aux
gammes/accords.

| Type | Rôle |
|---|---|
| `PitchClass` | Note ramenée à sa classe chromatique (0=C … 11=B), indépendante de l'octave. |
| `ScaleFamily` / `ScaleFamilies` | 7 familles de « scales of harmonies » (Oliver Prehn) : un motif d'intervalles de base par famille, dont chaque rotation (degré) engendre une gamme. |
| `ScaleDefinition` | Une gamme nommée = famille + degré + métadonnées (nom populaire, nom systématique, symboles d'accords associés). Les intervalles sont **toujours dérivés** de la famille, jamais saisis à la main — impossible qu'ils dérivent de la source. |
| `ScaleLibrary` | Catalogue complet des 33 gammes, recherche par `id` (ex. `"dorian"`) ou par famille. |
| `Mode` | Une `ScaleDefinition` ancrée sur une tonique — l'objet réellement joué/détecté/suggéré. |
| `ChordTemplate` / `ChordVocabulary` | Qualité d'accord = ensemble d'intervalles depuis la fondamentale. Contient les accords de septième (issus de la colonne « Chords » de la bibliothèque de gammes) **plus** les 4 triades de base (Ma/mi/dim/aug) — ajoutées suite à un bug réel (un simple Do-Mi-Sol majeur était étiqueté « CMa7 » faute de triade correspondante). |
| `Chord` | Un `ChordTemplate` ancré sur une fondamentale. |
| `FunctionalScaleSuggestion` / `IIVIMajorChart` | Suggestions de gammes par fonction harmonique (ii/V/I), pour une future aide à l'improvisation. |

## PieceModel — modèle de morceau

Schéma `Codable` d'un morceau, indépendant de tout moteur audio.

- **`Piece`** : titre, compositeur, signature rythmique, tempo, tonalité, fragments
  mélodiques réutilisables, liste de `Section`.
- **`Section`** : bloc structurel (mode, transition de mode optionnelle, progression
  d'accords, une ou plusieurs `Track`).
- **`ChordEvent`** : un accord placé sur la grille (mesure/temps/durée), avec inversion,
  basse alternative (accord « slash »), et `PlayingStyle` (`simultaneous` / `arpeggioUp` /
  `arpeggioDown` / `strum`).
- **`Track`** : une partie d'instrument = `MelodyEvent`s directement écrits + `FragmentPlacement`s.
- **`MelodicFragment`** : motif réutilisable stocké en intervalles relatifs (pas en hauteurs
  absolues), transposable/rétrogradable/inversible/accélérable.
- **`Rendering.swift`** — le cœur du calcul de lecture :
  - `renderedNotes() -> [RenderedNote]` : aplatit tout le morceau (accords voisés + mélodies +
    fragments) en notes absolues, en secondes, prêtes pour un moteur audio.
  - `harmonicTimeline() -> [TimedChordEvent]` : la même mécanique, mais à la granularité
    « accord » (pas note par note) — sert à afficher « où en est-on » pendant la lecture.

## MIDIEngine — entrée MIDI

- `MIDINoteEvent` + `MIDIRawParser.parseNoteEvents(_:)` : décodage MIDI **pur**, sans
  dépendance à CoreMIDI — testable sans matériel.
- `MIDIInputListener` : enveloppe CoreMIDI réelle. `connectAllSources()` (comportement par
  défaut) ou `connectSource(atIndex:)` (une seule source choisie).

## AudioEngine — lecture audio et écoute

- **`PiecePlayer`** : lecture non temps-réel d'un `Piece` (`play(_:)`) via
  `AVAudioUnitSampler`, plus des entrées temps réel (`startNote`/`stopNote`) pour le MIDI
  vivant. Chargement d'instruments `.sf2`/`.dls`/`.aupreset`.
  - **Filet de sécurité anti-note-bloquée** : en fin de lecture, force l'extinction de
    chaque hauteur utilisée dans le morceau, au cas où un accord et une mélodie partageant
    la même hauteur se seraient marché dessus.
- **`FFTPitchAnalyzer`** : détection de hauteur(s) par FFT (Accelerate/vDSP) sur une fenêtre
  de taille fixe (puissance de 2, 4096 par défaut ≈ 93 ms à 44,1 kHz).
  - `dominantFrequency(...)` : la hauteur la plus forte (ou `nil`).
  - `dominantFrequencies(...)` : jusqu'à `maxPeaks` hauteurs simultanées — la brique qui
    permet de détecter un accord joué au micro. Repère les vrais maxima locaux du spectre,
    élimine les fuites de bord (une source forte juste hors plage), exige un contraste net
    par rapport à la moyenne de bande, et fusionne les pics trop proches (< un demi-ton) pour
    qu'un seul lobe spectral ne compte pas comme plusieurs notes.
  - `rms(of:)` / `minimumRMSForDetection` : niveau brut du signal, indépendant de toute
    détection de hauteur — sert de jauge de diagnostic.
  - **Limite assumée et documentée** : heuristique de pic, pas une vraie transcription
    polyphonique. Peut se verrouiller sur une harmonique plutôt que la fondamentale ; les
    harmoniques d'un accord réel peuvent créer de fausses notes ou, à l'inverse, coïncider
    avec une vraie note de l'accord. Testé et validé sur un accord réel (Do majeur) joué
    physiquement via les haut-parleurs et capté par le micro.
- **`MicrophonePitchListener`** : capture le micro par défaut (`AVAudioEngine.inputNode`),
  livre `([DetectedPitch], niveau)` toutes les ~93 ms. Vérifie/demande explicitement la
  permission microphone macOS (`AVCaptureDevice`) avant de démarrer — sans quoi
  `AVAudioEngine.start()` réussirait silencieusement en ne recevant jamais que du silence.
  **macOS uniquement** : iOS/iPadOS demanderait en plus une configuration `AVAudioSession`
  (catégorie, permission) non implémentée ici.
- **`SamplerUnit`** : la même paire `AVAudioEngine`/`AVAudioUnitSampler` que `PiecePlayer`
  (mêmes `startNote`/`stopNote`/`loadSample`), mais sans notion de morceau pré-composé —
  juste un instrument jouable en temps réel. `AppCore` en crée une instance par piste
  d'entrée dont le son est activé (voir plus bas), ce qui permet à plusieurs pistes de
  sonner en même temps avec des timbres réellement différents (chaque instance ouvre sa
  propre connexion à la sortie audio par défaut).

## RecognitionEngine — reconnaissance d'accords et de modes

Un seul type, `RecognitionEngine`, alimenté par des événements note on/off (peu importe
leur origine — MIDI réel, clavier ordinateur, ou micro, voir `AppCore`) :

- **Accords** : lues sur les notes **littéralement tenues** (simultanéité exacte). Chaque
  paire (fondamentale, `ChordTemplate`) est comparée aux notes tenues par un score de
  Jaccard (`|intersection| / |union|`) ; le meilleur score au-dessus du seuil est retenu.
- **Modes** : lues sur un historique des notes récemment jouées, avec une pondération à
  décroissance exponentielle (demi-vie configurable, 4 s par défaut) — une gamme se joue
  mélodiquement, pas en accord plaqué. Les modes candidats sont classés par couverture
  pondérée, puis par nombre de notes (le plus spécifique en tête en cas d'égalité).

## LLMEngine — composition assistée par un modèle de langage

- **`LLMConnection`** : descripteur `Codable` (`name`, `provider`, `baseURL`, `model`,
  `apiKeyEnvVar`). **Ne contient jamais de clé réelle** — seulement le nom d'une variable
  d'environnement à lire au moment de l'appel, donc le fichier lui-même reste sûr à garder
  (même sous contrôle de version).
- **`LLMProvider` / `LLMClient`** : trois fournisseurs implémentés —
  - `OllamaProvider` (`/api/generate`, sans clé, pour un serveur local),
  - `OpenAICompatibleProvider` (`/v1/chat/completions` — couvre OpenAI et de nombreux
    serveurs locaux compatibles : LM Studio, llama.cpp…),
  - `AnthropicProvider` (`/v1/messages`, en-têtes `x-api-key`/`anthropic-version`, forme de
    réponse différente).
  Tous synchrones via un `DispatchSemaphore` autour de `URLSession` (le CLI n'a pas de
  `main` asynchrone).
- **`LLMPieceComposer`** : construit le prompt (texte source + schéma JSON exact restreint
  au vocabulaire réel de `ScaleLibrary`/`ChordVocabulary`), puis **valide** intégralement la
  réponse avant de construire un `Piece` — un ID de gamme/accord invalide, une note MIDI hors
  plage, ou une section sans accord valide sont abandonnés (avec un avertissement) plutôt que
  injectés tels quels. C'est le principe « ne jamais faire confiance à une suggestion de LLM
  sans validation » appliqué concrètement.

## AppCore — `ImprovSession`, le cœur applicatif

Une seule classe, `@Observable`, `@unchecked Sendable`, qui détient tout l'état de
l'application et toute la logique — indépendante de toute présentation. Le CLI ne fait que
l'appeler et lire son état ; une future interface SwiftUI pourrait s'y brancher directement.

### Groupes de fonctionnalités

- **Morceau** : `piece`, chargement/sauvegarde (`loadPiece`, `savePiece`/`savePiece(as:)`),
  parcours de dossier (`listPieceFiles`), morceau de démonstration (`loadDemoPiece`).
- **Lecture** : `play()` — calcule `renderedNotes()`/`harmonicTimeline()`, lance la lecture
  audio, et programme la mise à jour de l'état de présentation (`playbackHeldPitches`,
  `playbackCurrentChordIndex`) séparément du son.
- **Pistes d'entrée (`tracks`)** : chaque source d'entrée active — MIDI fusionné
  (`.midiMerged`), un port MIDI précis (`.midiSource(index)`, en mode individuel), le
  clavier de l'ordinateur (`.computerKeyboard`) ou le microphone (`.microphone`) — est une
  `TrackInfo` indépendante dans `session.tracks: [TrackInfo]` (type défini dans
  `AppCore/Track.swift`), avec son propre `heldPitches`/`recognizedChord`/`recognizedModes`,
  son propre état de son (`soundEnabled`/`instrumentName`), et pour le micro son propre
  `lastDetectedPitches`/`microphoneInputLevel`. `midiFusionMode` (`.merged`/`.individual`)
  décide si le MIDI apparaît comme une seule piste ou une par port visible ;
  `setMIDIFusionMode`/`refreshTracks()` reconstruisent la liste en préservant l'état de
  chaque piste survivante par identité (`TrackID`).
  - `startTrack(_:)`/`stopTrack(_:)` : démarre/arrête l'écoute d'une piste — connecte un
    `MIDIInputListener` dédié pour une piste MIDI, démarre `MicrophonePitchListener` pour le
    micro, ou se contente de marquer la piste « en écoute » pour le clavier (`pressKey`/
    `releaseKey` pilotent déjà directement cette piste, sans étape de connexion matérielle).
  - `setSoundEnabled(_:for:)`/`setInstrument(named:for:)` : active/désactive le son d'une
    piste (jamais permis pour `.microphone`, voir §3 du guide utilisateur) et charge un
    instrument sur son propre `SamplerUnit` — chaque piste sonnante a la sienne, donc
    plusieurs pistes peuvent sonner en même temps avec des timbres différents.
  - `pressKey`/`releaseKey` : le point d'entrée partagé par les commandes `press`/`release`,
    la piste clavier du CLI, et (plus tard) un clavier tactile — paramètre `track:` par
    défaut à `.computerKeyboard`.
  - `handleIncomingMIDIEvent(_:track:)` : logique par événement MIDI (log, recognizer de la
    piste, son via son `SamplerUnit` si activé) — extraite pour être appelable directement
    depuis les tests sans CoreMIDI réel.
  - `handleDetectedPitches(_:level:track:)` : transforme un flux « ces hauteurs sonnent
    actuellement » (le micro) en transitions note-on/note-off discrètes (une extinction par
    hauteur disparue, un allumage par hauteur apparue) sur la piste microphone, exactement
    comme le ferait un vrai clavier MIDI à plusieurs notes — c'est ce qui permet à la
    reconnaissance d'accords déjà existante de fonctionner sans aucune modification pour le
    micro.
- **Instruments** : `listSampleFiles`/`loadSample`.
- **Composition IA** : `newPiece`, `setSourceText`, `listLLMConnections`/`useLLMConnection`,
  `composeFromText(generate:)` — le paramètre `generate` est injectable, ce qui permet de
  tester tout le pipeline (prompt → validation → assignation) sans réseau réel.

### Modèle de concurrence — la leçon la plus importante du projet

`ImprovSession` peut être appelée depuis plusieurs threads différents en même temps
(callback CoreMIDI, minuteries d'extinction du clavier ordinateur, callback du micro, boucle
`console`). Trois vrais bugs de concurrence (corruption mémoire, plantages) ont été trouvés et
corrigés au cours de cette session, toujours selon le même schéma :

> **Règle** : toute mutation d'état partagé programmée sur une queue *concurrente*
> (`DispatchQueue.global()`) doit en réalité s'exécuter sur une queue *série* dédiée.

Deux queues série existent à cet effet :
- `liveInputQueue` — sérialise `handleIncomingMIDIEvent`/`stopTrack`/`handleDetectedPitches`
  (tout ce qui touche l'état d'une piste : son `recognizer`, son `heldPitches`, etc.), quelle
  que soit la piste concernée — une seule queue partagée par toutes les pistes, pas une par
  piste, donc deux pistes qui reçoivent un événement au même instant restent sérialisées
  entre elles aussi.
- `playbackStateQueue` — sérialise les mises à jour d'état pendant `play()`
  (`playbackHeldPitches`/`playbackCurrentChordIndex`/`isPlaying`).

Toute nouvelle fonctionnalité qui programme un callback différé touchant l'état de la
session doit réutiliser l'une de ces deux queues, ou en créer une nouvelle — jamais muter
directement depuis `.global()`. Voir la mémoire `feedback-improv-app-concurrency` pour le
détail des trois incidents.

## ImprovCLI — l'interface en ligne de commande

- **`main.swift`** : boucle REPL classique + `executeCommand(_:_:)` (un unique
  aiguillage de commandes, partagé par le REPL et les menus de `console`) + l'écran `console`
  (tableau de bord figé, redessiné en place).
- **`Menu.swift`** : mode brut du terminal (`termios`), lecture de touche par touche,
  système de menus déroulants façon DOS (mnémoniques soulignés, navigation aux flèches,
  Échap pour ouvrir/fermer sans passer par une lettre).
- **`Keyboard.swift`** : rendu ASCII d'un clavier de piano (1 caractère/demi-ton, largeur
  volontairement étroite pour ne jamais approcher 80 colonnes — une largeur trop proche de
  la limite du terminal a été la cause réelle d'un bug de scintillement).
- **`TextStyle.swift`** : mise en forme ANSI cohérente (libellé en gras/couleur, valeur en
  clair) pour lire l'écran d'un coup d'œil.

### Points de conception notables

- **Largeur de terminal** : toute ligne potentiellement longue (le déroulé d'un morceau à
  beaucoup d'accords) est explicitement découpée à ~70 colonnes visibles plutôt que laissée
  au retour à la ligne automatique du terminal — cause racine du scintillement observé.
- **Ligne de marqueurs de mode toujours dessinée** (même vide) pour que la position du
  clavier ne bouge jamais selon qu'un mode est détecté ou non.
- **Piste clavier** : `track clavier on` tape les touches du clavier physique comme un
  piano virtuel (disposition identique à « Musical Typing » de GarageBand) — la variable
  `computerKeyboardSourceActive` du CLI est mise à jour en même temps que l'état d'écoute de
  cette piste par `executeCommand("track", ...)`, pas par une commande séparée. Limite
  assumée : un terminal ne reçoit jamais d'événement de relâchement de touche, donc chaque
  frappe déclenche une note « pincée » avec extinction automatique après 300 ms plutôt qu'un
  vrai maintien.
- **Boucle de repli anti-conflit** : quand la piste clavier écoute, les lettres ne
  déclenchent plus les raccourcis-menu (qui utilisent aussi des lettres) ; Échap redevient
  l'unique porte d'entrée vers le menu.
- **Un clavier par piste en écoute** : `renderConsoleFrame()` boucle sur `session.tracks`
  filtrées par `isListening` et dessine un bloc (nom, son/micro, accord, modes, clavier)
  par piste active, au lieu d'un unique clavier partagé — `renderTrackKeyboard(_:)` isole le
  rendu d'un clavier à partir de l'état d'une seule `TrackInfo`.

## SanityChecks — le filet de sécurité sans Xcode

Exécutable qui rejoue à la main chaque cas de test des vrais fichiers `XCTest`
(`check`/`checkNil`), pour compenser l'absence d'Xcode. **Toujours mettre à jour ce fichier
en même temps que tout nouveau test** — c'est le seul moyen de vérifier que le code
fonctionne dans cet environnement. Se lance avec `swift run SanityChecks` depuis
`MusicTheoryKit/`. Compteur de vérifications à la fin de cette session : **187 checks, 0 échec**,
stable sur plusieurs exécutions répétées.

## Vérification/tests

```sh
cd MusicTheoryKit
swift build                 # compile tout
swift run SanityChecks      # exécute tous les checks (seul moyen de "tester" ici)
swift run ImprovCLI         # lance l'application
```

## Limites connues

- **Détection polyphonique au micro** : heuristique de pics spectraux, pas une vraie
  transcription d'accords. Fonctionne bien sur un accord clair ; peut se tromper sur des
  textures denses ou des timbres riches en harmoniques.
- **Micro : macOS uniquement.** Portage iOS/iPadOS à faire (configuration `AVAudioSession`).
- **Piste clavier sans vrai maintien** : limite du terminal, pas du code.
- **Pas de dépôt git** sur ce projet à ce jour.
- **Aucune interface graphique** : tout passe par le CLI ; la couche `AppCore` est conçue
  pour qu'une interface SwiftUI puisse s'y brancher sans réécriture, mais cette étape n'a
  pas encore été commencée (bloquée par l'absence d'Xcode sur cette machine).

## Suite prévue (feuille de route)

D'après la mémoire du projet, les phases suivantes restent à faire : `KeyboardView`
vectoriel/tactile (SwiftUI, nécessite Xcode), affinage de la reconnaissance
(RecognitionEngine — déjà largement implémenté ce jour), un vrai module texte→progression
au-delà du premier jet LLM actuel, et une vue timeline/lead-sheet.
