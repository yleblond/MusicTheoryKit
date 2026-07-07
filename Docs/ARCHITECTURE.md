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
PieceModel      SoundTrackModel      RecognitionEngine  (reconnaissance)
(morceau,       (enregistrement            ↑
 mesures/       événementiel,
 Codable)        secondes, Codable)
      ↑                ↑                   ↑
      └────────────────┴──────────┬────────┘
                                  │
AudioEngine (lecture Piece + SoundTrack, micro/FFT)   MIDIEngine (CoreMIDI)   NetEngine (TCP)
                    ↑                                        ↑                    ↑
                    └────────────────────┴─────────────┬──────┘                    │
                                                         │                          │
                                            LLMEngine (composition IA,              │
                                             Piece <- texte OU SoundTrack)           │
                                                         │                          │
                                                         └──────────────┬───────────┘
                                                                        │
                                                                    AppCore
                                                   (ImprovSession — logique applicative)
                                                                        │
                                                                   ImprovCLI
                                            (REPL + écrans "run"/"config" + menus DOS)
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
- **`Track`** : une partie d'instrument = `MelodyEvent`s directement écrits + `FragmentPlacement`s,
  plus `instrument: String` — nom d'un fichier échantillon (ex. `"mcb.sf2"`) dans le dossier
  `samples` courant ; `""` (le défaut, y compris pour tout fichier de morceau antérieur à cette
  fonctionnalité) veut dire « son par défaut de la lecture ».
- **`Section.chordInstrument: String?`** : même idée que `Track.instrument`, mais pour la
  progression d'accords de la section — les accords n'ont pas de piste à eux, donc ce champ vit
  directement sur `Section`. `nil` (le défaut) = son par défaut, comme pour une piste sans
  instrument propre.
- **`MelodicFragment`** : motif réutilisable stocké en intervalles relatifs (pas en hauteurs
  absolues), transposable/rétrogradable/inversible/accélérable.
- **`Rendering.swift`** — le cœur du calcul de lecture :
  - `renderedNotes() -> [RenderedNote]` : aplatit tout le morceau (accords voisés + mélodies +
    fragments) en notes absolues, en secondes, prêtes pour un moteur audio. Chaque
    `RenderedNote` porte aussi `instrumentName: String?`, propagé depuis `Track.instrument`
    (mélodie/fragments) ou `Section.chordInstrument` (accords) — une chaîne vide est
    normalisée en `nil` (`normalizedInstrumentName`), donc un fichier de morceau écrit avant
    cette fonctionnalité rend exactement le même son qu'avant (tout `nil`).
  - `harmonicTimeline() -> [TimedChordEvent]` : la même mécanique, mais à la granularité
    « accord » (pas note par note) — sert à afficher « où en est-on » pendant la lecture.

## SoundTrackModel — enregistrement événementiel (secondes)

Schéma `Codable` d'un enregistrement, **délibérément incompatible** avec `PieceModel` — pas
une variante, une autre forme : ici pas de tempo, pas de mesure, juste « cette hauteur est
passée on/off à tel instant réel ». Ajouté pour le mode Soundtrack (voir §AppCore) : capturer
une performance telle qu'elle a vraiment été jouée, sans la faire passer par une grille
musicale qu'elle ne respecte peut-être pas.

- **`RecordedNoteEvent`** : `timeSeconds` (temps écoulé depuis le début de l'enregistrement,
  pas une position mesure/temps), `trackID` (l'id *wire* de la piste source — `"clavier"`,
  `"midi:1"`... — voir `AppCore.TrackID.wireIDText` ; une chaîne simple plutôt qu'un vrai
  `TrackID` pour que ce module n'ait pas à dépendre d'`AppCore`), `isNoteOn`, `pitch`, `velocity`.
- **`SoundTrack`** : titre, durée totale, liste de `RecordedNoteEvent`. `trackIDs` (calculé) :
  l'ensemble des pistes distinctes ayant contribué au moins un événement.

## MIDIEngine — entrée MIDI

- `MIDINoteEvent` + `MIDIRawParser.parseNoteEvents(_:)` : décodage MIDI **pur**, sans
  dépendance à CoreMIDI — testable sans matériel.
- `MIDIInputListener` : enveloppe CoreMIDI réelle. `connectAllSources()` (comportement par
  défaut) ou `connectSource(atIndex:)` (une seule source choisie).

## AudioEngine — lecture audio et écoute

- **`PiecePlayer`** : lecture non temps-réel d'un `Piece` (`play(_:instrumentURLs:)`) via un
  `AVAudioUnitSampler` par défaut, plus des entrées temps réel (`startNote`/`stopNote`) pour
  le MIDI vivant. Chargement d'instruments `.sf2`/`.dls`/`.aupreset`.
  - **Un `SamplerUnit` par instrument distinct utilisé dans le morceau** : toute
    `RenderedNote.instrumentName` non-`nil` rencontrée est routée vers son propre
    `SamplerUnit` (créé/réutilisé à la volée), chargé avec l'URL fournie dans
    `instrumentURLs[name]` — même mécanisme que les pistes d'entrée en direct (plusieurs
    `AVAudioEngine` indépendants sonnant en même temps), réutilisé ici pour qu'un morceau
    puisse faire sonner ses accords et chacune de ses pistes/lignes mélodiques avec des
    timbres réellement différents. Un nom réévalué à chaque `play()` (pas mis en cache pour
    toujours) : un instrument introuvable la première fois (dossier pas encore listé) a une
    vraie chance de se charger la fois suivante.
  - **Jamais d'échec silencieux ni d'exception qui interrompt la lecture** : un nom sans
    entrée dans `instrumentURLs`, ou un fichier qui échoue au chargement, retombe sur le son
    par défaut de son propre `SamplerUnit` et ajoute un message au tableau `[String]` que
    `play(_:instrumentURLs:)` retourne — `ImprovSession.play()` les relaie dans le journal
    (`"Instrument: ..."`), même convention « on jette ce qui est invalide, on prévient, on
    continue » que `LLMPieceComposer`.
  - **Filet de sécurité anti-note-bloquée** : en fin de lecture, force l'extinction de
    chaque hauteur utilisée dans le morceau — regroupée par instrument (chaque nom a son
    propre sampler), pas globalement — au cas où deux parties partageant la même hauteur se
    seraient marché dessus.
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
- **`SoundTrackPlayer`** : le pendant de `PiecePlayer` pour un `SoundTrack` (voir
  `SoundTrackModel`) — plus simple sur un point (`timeSeconds` est déjà un offset absolu,
  aucune conversion mesure/temps→secondes) et volontairement pas une variante sur un autre :
  il rejoue le flux brut d'événements on/off exactement comme enregistré (chevauchements
  compris), au lieu de reconstruire des paires note+durée à partir d'un modèle mesuré. Même
  filet de sécurité anti-note-bloquée que `PiecePlayer`, même raison (deux pistes enregistrées
  ensemble peuvent se marcher sur la même hauteur). Toutes les pistes de l'enregistrement
  sonnent à travers un seul `SamplerUnit` dans cette première version (pas de timbre par
  piste d'origine — voir `SoundTrack.trackIDs` si une version future veut les séparer).

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
  - **`buildPrompt(fromSoundTrack:)`** : deuxième point d'entrée, même schéma JSON et même
    `parseAndValidate` que `buildPrompt(sourceText:)` (entièrement partagé, aucune duplication
    de la validation) — reformule juste la demande : au lieu de « invente un morceau qui colle
    à l'ambiance de ce texte », c'est « déduis un tempo/tonalité/accords qui expliquent
    raisonnablement cette performance réelle », avec le flux d'événements
    (`t=0.45s ON C4 (piste: clavier)`...) inséré tel quel dans le prompt. Voir §AppCore pour
    qui appelle ça et ce qui se passe ensuite.

## NetEngine — transport réseau de la session collaborative

Aucune dépendance externe (ni HTTP, ni WebSocket, ni swift-nio) — juste `Network.framework`
(un framework système Apple, pas une lib à charger) plus un format de message maison, choisi
volontairement simple puisque les échanges eux-mêmes sont simples (notes, annonces de piste).

- **`NetMessage`** : une seule struct `Codable` à plat (pas une enum à cas associés — le
  JSON encode/decode maison reste trivial) avec un champ `kind` (`hello`/`helloAck`/
  `trackAnnounce`/`trackUnannounce`/`noteEvent`/`sync`) et tous les autres champs optionnels,
  seuls ceux pertinents pour ce `kind` étant renseignés. `RemoteTrackSnapshot` : l'état
  d'affichage complet d'une piste (écoute, son, hauteurs tenues, accord/mode déjà formatés en
  texte) tel que diffusé dans un message `sync`.
- **`FramedConnection`** : encapsule un `NWConnection`, sérialise chaque `NetMessage` en JSON
  précédé de 4 octets de longueur (big-endian) — pas de HTTP ni de handshake WebSocket,
  juste assez pour délimiter un message sans ambiguïté (contrairement à du JSON délimité par
  des retours à la ligne, dont le contenu pourrait en théorie contenir un vrai retour à la
  ligne). `onReady` ne se déclenche qu'une fois la connexion réellement `.ready` — envoyer
  avant risquerait que les octets soient silencieusement perdus pendant la poignée de main.
- **`NetworkServer`** : encapsule un `NWListener`, accepte n'importe quel client sans liste
  blanche (design volontairement permissif — « purement collaboratif, le serveur ne coupe
  personne »), une `FramedConnection` par connexion. `start(port:advertisedAs:)` : si un nom
  est fourni, assigne `listener.service = NWListener.Service(name:type:)` avant `start()` —
  le serveur devient alors détectable en Bonjour/mDNS sur ce même port explicite, sans passer
  par l'initialiseur `NWListener(service:using:)` qui choisirait lui-même un port aléatoire.
- **`NetworkClient`** : une seule connexion sortante, envoie une liste de messages une fois
  prête (`hello` puis une annonce par piste déjà en écoute, pour rejoindre une session déjà
  commencée sans avoir à tout re-activer). Deux façons de se connecter, unifiées en interne
  sur le même chemin : `connect(host:port:)` (adresse connue) ou `connect(to: NWEndpoint)`
  (un résultat de `ServiceBrowser`, dont l'hôte/port réels sont résolus par Network.framework
  lui-même — rien à valider côté appelant, contrairement à la variante host/port).
- **`ServiceBrowser`** : découverte réseau local via `NWBrowser` sur le type de service
  Bonjour `_musicimprov._tcp`. `discover(timeout:)` bloque l'appelant pendant une fenêtre de
  recherche fixe (pont synchrone au-dessus de l'API à callback de `NWBrowser`, même principe
  que `LLMProvider` pour `URLSession`) puis renvoie ce qui a été trouvé — vide n'est pas une
  erreur, juste « rien vu sur ce réseau pendant cette fenêtre ». Testé pour de vrai (pas
  seulement en théorie) : deux processus `ImprovCLI` séparés sur cette machine, l'un en
  `server`, l'autre tapant `discover`, se voient bien l'un l'autre — voir §AppCore.
- **`FramedConnection`/`NetworkServer`/`NetworkClient` sont `@unchecked Sendable`** : chaque
  propriété mutable n'est touchée que depuis la queue série dédiée à cette instance — même
  raisonnement que celui déjà appliqué à `ImprovSession` (voir plus bas).

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
- **Instruments (son par défaut de la lecture du morceau)** : `listSampleFiles`/`loadSample`.
- **Instruments par piste/accord d'un `Piece`** : `setPieceTrackInstrument(sectionIndex:trackIndex:instrumentName:)`
  et `setPieceChordInstrument(sectionIndex:instrumentName:)` modifient `piece` en mémoire
  (pas de persistance automatique — suivre d'un `savePiece()`/`savePiece(as:)`). `play()`
  résout chaque `RenderedNote.instrumentName` distinct via `resolvedInstrumentURLs(for:)`
  (même dossier `sampleFolder` que `use-sample` ; un nom sans fichier correspondant est
  simplement omis, laissant `PiecePlayer` retomber sur le son par défaut et prévenir).
- **Composition IA** : `newPiece`, `setSourceText`, `listLLMConnections`/`useLLMConnection`,
  `composeFromText(generate:)` — le paramètre `generate` est injectable, ce qui permet de
  tester tout le pipeline (prompt → validation → assignation) sans réseau réel.
  - **Prompts de composition — prévisualisables, sauvegardables, remplaçables** :
    `currentTextCompositionPrompt()`/`currentSoundTrackCompositionPrompt()` renvoient
    exactement le texte que `composeFromText()`/`composeSoundTrackToPieces()` enverraient
    *maintenant* — `activeTextCompositionPrompt`/`activeSoundTrackCompositionPrompt` (chargés
    via `useTextCompositionPrompt`/`useSoundTrackCompositionPrompt`) si un a été chargé,
    sinon reconstruit à la volée depuis `sourceText`/`currentSoundTrack` via
    `LLMPieceComposer.buildPrompt(...)`. `composeFromText`/`composeSoundTrackToPieces` ont
    été récrites pour passer par ces deux méthodes plutôt que d'appeler `buildPrompt`
    directement — un seul point de résolution, pas de double logique à garder synchronisée.
  - `setPromptsFolder(_:)` crée (si absents) et pointe deux sous-dossiers fixes,
    `Texte`/`Soundtrack`, sous une racine unique (auto-écoutée au démarrage comme
    `Pieces`/`SoundFonts`/`SoundTracks`, voir plus bas) — `save[Text|SoundTrack]CompositionPrompt(as:)`
    y écrit le prompt courant, `use[Text|SoundTrack]CompositionPrompt(named:/atIndex:)` le
    recharge comme override, `reset[Text|SoundTrack]CompositionPrompt()` l'efface (retour au
    comportement par défaut, reconstruit à chaque appel).
  - `composeSoundTrackToPieces` a gagné un paramètre `title: String?` — quand fourni,
    remplace le titre choisi par l'IA (et donc le nom du fichier sauvegardé) sur chaque
    candidat, seul le suffixe `-candidat-N` continuant à les distinguer entre eux.
- **Enregistrement (SoundTrack) — mode purement événementiel** : deuxième mode de lecture,
  volontairement incompatible avec le premier (mesures/accords) — voir `SoundTrackModel`.
  - `startRecording(title:tracks:)`/`stopRecording()` : `tracks` vide (le défaut) capture
    toutes les pistes actuellement en écoute ; en nommer capture seulement celles-là, même si
    d'autres écoutent en même temps. La capture d'un événement se fait dans
    `updateRecognitionState` (donc déjà à l'intérieur de `liveInputQueue.sync`) via
    `captureRecordingEventIfRecording` — silencieuse pour une piste `.remote` (son
    `wireIDText` est `nil` : l'enregistrement ne capture que les pistes *locales* de ce
    participant dans cette première version).
  - `playSoundTrack()` : le pendant de `play()` pour le mode temporel — même schéma de
    planification (`playbackStateQueue`, compteur de génération contre un appel périmé), juste
    `soundTrackHeldPitches`/`isPlayingSoundTrack` au lieu de `playbackHeldPitches`/`isPlaying`.
  - `listSoundTrackFiles`/`loadSoundTrack`/`saveSoundTrack(as:)` : miroirs exacts des méthodes
    équivalentes pour `Piece`.
  - **`composeSoundTrackToPieces(candidateCount:generate:)`** : la nouvelle fonction IA
    demandée — construit le prompt via `LLMPieceComposer.buildPrompt(fromSoundTrack:)`, réutilise
    intégralement `parseAndValidate` (même garantie « jamais de suggestion LLM non validée »
    que `composeFromText`), et écrit **chaque** candidat qui survit à la validation comme un
    nouveau fichier de morceau dans `pieceFolder` (via `writePieceToDisk`, qui encode un
    `Piece` arbitraire sans passer par `self.piece` — pour ne pas qu'un candidat écrase le
    précédent avant d'être sauvegardé). Le dernier candidat réussi devient `piece` (comme
    `composeFromText`) ; tous restent inspectables via `pieces`/`use-piece`.
- **Session collaborative (`server`/`client`)** : `TrackID.remote(clientID:trackID:)` est un
  cas de plus dans le même enum que `.midiMerged`/`.computerKeyboard`/etc. — la piste d'un
  autre participant se comporte, pour tout le reste du code (recognizer, sampler,
  `updateRecognitionState`), exactement comme n'importe quelle autre piste ; c'est ce qui a
  rendu l'ajout du réseau simple une fois le modèle de pistes déjà en place.
  - `startServer(port:)`/`stopServer()` : ouvre un `NetworkServer`, démarre un
    `DispatchSourceTimer` qui rediffuse (`broadcastSyncSoon()`) l'état complet des pistes
    toutes les 150ms et juste après chaque changement (piste qui rejoint/part) — le serveur
    est la seule machine à faire tourner un vrai `RecognitionEngine` pour les pistes
    distantes ; les clients ne re-dérivent jamais eux-mêmes une reconnaissance. Le serveur
    s'annonce systématiquement en Bonjour (`advertisedAs: localClientName`) — il n'y a pas
    de bascule séparée « annoncer ou non », l'écoute d'un client déjà au courant de
    l'adresse fonctionnant de toute façon même sans que quiconque ait cherché à découvrir.
  - `discoverServers(timeout:)` : recherche synchrone (voir `ServiceBrowser` plus haut) —
    renvoie une liste de `DiscoveredServer` (nom + `NWEndpoint` opaque) que le CLI numérote
    et propose au choix.
  - `connectToServer(host:port:)` (adresse connue) / `connectToServer(discovered:)` (résultat
    de `discoverServers()`) / `disconnectFromServer()` : les deux variantes de connexion
    partagent la même logique interne (`makeNetworkClient()`/`initialClientMessages()`) —
    `hello` + une `trackAnnounce` par piste déjà en écoute, pour rejoindre une session déjà
    commencée sans tout re-activer.
  - Aucune permission demandée : le rôle serveur accepte n'importe quel client
    (« purement collaboratif, le serveur ne coupe personne », décision explicite de
    l'utilisateur) — un point à revisiter si un usage moins bienveillant apparaît plus tard.
  - **Le son reste toujours une décision locale** : `canHaveSound`/`soundEnabled` sur une
    piste `.remote` fonctionnent exactement comme sur une piste locale (même `setSoundEnabled`
    /`setInstrument`, aucun cas spécial) — chaque participant choisit lui-même, indépendamment
    des autres, quelles pistes distantes il veut entendre, avec quel instrument.
  - **Piège de test réel trouvé en écrivant le test collaboratif** (voir plus bas) :
    `localClientID` a d'abord été persisté dans `~/.music-improv-client-id`, pensé pour
    survivre à un relance. Deux instances sur la même machine (même `$HOME`) — exactement le
    scénario « je teste serveur et client dans deux Terminaux sur mon propre Mac » — chargent
    alors le **même** identifiant, et un client filtre alors par erreur la propre piste du
    serveur en la prenant pour la sienne. Corrigé en générant un UUID aléatoire en mémoire à
    chaque lancement, sans persistance disque — un participant relancé redevient simplement
    « nouveau » dans cette première version, ce qui reste cohérent avec le point 5 de la
    demande initiale (distinguer les clients simultanés, pas forcément survivre à un relance).
  - **`TrackInfo.remoteChordDisplay`/`remoteModesDisplay`** : uniquement renseignés côté
    client par `mergeRemoteSnapshot`, jamais côté serveur (qui a toujours la vraie valeur
    structurée `recognizedChord`/`recognizedModes`) — reconstruire un `RecognizedChord` à
    partir d'une simple chaîne de caractères aurait été fragile et sans intérêt réel ; le
    serveur formate une fois (`Self.describe`), chaque client réaffiche tel quel. Le CLI
    (`chordDisplayText`/`modesDisplayText`) préfère toujours la valeur structurée quand elle
    existe, et ne retombe sur la chaîne affichée que si elle est absente.

### Modèle de concurrence — la leçon la plus importante du projet

`ImprovSession` peut être appelée depuis plusieurs threads différents en même temps
(callback CoreMIDI, minuteries d'extinction du clavier ordinateur, callback du micro, boucle
de redessin des écrans `run`/`config`). Trois vrais bugs de concurrence (corruption mémoire, plantages) ont été trouvés et
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

- **`main.swift`** : boucle REPL classique + `executeCommand(_:_:)` (un unique aiguillage de
  commandes, partagé par le REPL et les menus des écrans figés) + `renderConsoleFrame(mode:)`/
  `runConsoleScreen(mode:)` (`ConsoleScreenMode.run`/`.config` — un seul mécanisme de
  redessin-en-place partagé, deux contenus distincts, voir plus bas). `runConsoleScreen`
  garde `mode` comme `var` local (pas juste le paramètre reçu une fois) : la touche `Tab`
  (`Key.tab`, nouveau cas) bascule `.run`↔`.config` directement dans la boucle, sans jamais
  repasser par Command — interceptée avant tout le reste dans le `switch` sur la touche lue,
  sans toucher `openMenuIndex` (un menu ouvert reste ouvert pendant la bascule, puisque c'est
  le même système de menus dans les deux écrans). **`q`** (`case .char("q") where
  !computerKeyboardSourceActive`) quitte l'écran — met `consoleShouldStop = true`, exactement
  ce que fait déjà le gestionnaire SIGINT de Ctrl+C, donc le même chemin de sortie propre ;
  demandé comme alternative "moins violente" à Ctrl+C. Ctrl+C reste fonctionnel en secours
  (notamment le seul moyen de sortir pendant que "Source clavier" intercepte toutes les
  lettres pour jouer des notes — le `where !computerKeyboardSourceActive` sur le cas `q`
  s'efface alors, comme n'importe quelle autre lettre, vers la recherche de note juste après).
- **`Menu.swift`** : mode brut du terminal (`termios`), lecture de touche par touche,
  système de menus déroulants façon DOS (mnémoniques soulignés, navigation aux flèches,
  Échap pour ouvrir/fermer sans passer par une lettre). `Key.tab` (octet 9) ajouté à
  l'énumération — `handleMenuKey` l'ignore explicitement (`case .tab: break`) puisque le
  changement d'écran n'est pas une notion de menu, gérée un niveau plus haut dans `main.swift`.
- **`Keyboard.swift`** : rendu ASCII d'un clavier de piano (1 caractère/demi-ton, largeur
  volontairement étroite pour ne jamais approcher 80 colonnes — une largeur trop proche de
  la limite du terminal a été la cause réelle d'un bug de scintillement).
- **`TextStyle.swift`** : mise en forme ANSI cohérente (libellé en gras/couleur, valeur en
  clair) pour lire l'écran d'un coup d'œil.

Commandes réseau : `server [port]`/`stop-server` (héberge), `client [host] [port]`/`discover`/
`disconnect` (rejoint, par adresse connue ou par découverte Bonjour) — menu **Jam Session**
(mnémonique `J`, renommé depuis « Reseau »). Champ `Reseau` (celui de `status`/`config`/
`tracks` — un libellé d'état, distinct du nom du menu) inchangé.

**Menu principal `MusicLab`** (mnémonique `L` — pas la première lettre, pour ne pas entrer
en collision avec `Morceaux`, même astuce que `Composition`/`C` évite `Morceaux`/`M` et
`Jam Session`/`J` évite tout le reste — voir le commentaire de `renderMenuBar`) : premier de
`menuCategories`, donc celui qui s'ouvre par défaut aux flèches/Échap. Point d'entrée
**unique** de configuration : Infos (`status`), Aide (`help`), les cinq « Choisir dossier
de... » (morceaux/sons/soundtracks/connexions LLM/prompts), Choisir une connexion LLM,
Quitter — ces sept dernières actions n'existent **que** dans ce menu (retirées de
`Morceaux`/`Soundtrack`/`IA` à la demande de l'utilisateur, pour éviter la duplication d'un
même réglage dans plusieurs menus).
- **Le menu `Instrument` a été supprimé entièrement** : ses deux items (« Choisir dossier de
  sons... », qui a rejoint `MusicLab`, et « Choisir le son de lecture du morceau... », qui a
  rejoint `Morceaux`) l'auraient laissé vide, ce qui aurait fait planter la navigation
  (`selectedItemIndex % items.count` dans `handleMenuKey` divise par zéro sur un menu à 0
  item). Toute nouvelle catégorie doit donc garder au moins un item, ou être retirée
  entièrement comme ici.
- `Morceaux` a aussi gagné « Voir le morceau (structure et instruments)... » — le même
  `show-piece`/`printPieceDetail()` que l'item « Voir le morceau » qui existait dans `IA`
  (supprimé depuis de `Composition` car c'était un vrai doublon, pas juste un raccourci utile
  ailleurs).
- **`IA` renommé `Composition`** (mnémonique `C`, première lettre — plus de collision avec
  `Instrument` puisqu'il a disparu). Gagné : « Voir/Sauvegarder/Charger le prompt de
  composition... » et « Revenir au prompt par défaut » (texte), voir plus haut. `Soundtrack`
  a gagné les quatre mêmes items pour son propre prompt, et son item de composition renommé
  « Composer un morceau à partir de la soundtrack... » (d'abord « Composer à partir de la
  soundtrack... ») demande maintenant un nom de morceau avant le nombre de candidats (vide =
  laisser l'IA choisir, comme avant). Ses deux items « Sauvegarder »/« Sauvegarder sous... »
  sont devenus « Sauvegarder la soundtrack »/« Sauvegarder la soundtrack sous... » (le libellé
  court prêtait à confusion avec la sauvegarde d'un `Piece`, deux concepts différents dans ce
  même menu). « Se deconnecter » (Jam Session) est devenu « Se deconnecter du serveur », même
  raison.
- **Ordre de `menuCategories`** (choisi explicitement par l'utilisateur, pas alphabétique ni
  par ordre d'ajout) : `MusicLab, Instruments, Morceaux, Soundtracks, Composition, Jam
  Session` (`Instruments`/`Soundtracks` sont les noms actuels de ce qui s'appelait
  `Source`/`Soundtrack` — voir plus bas). `Morceaux` a perdu son item « Quitter » (déjà
  présent dans `MusicLab`, un vrai doublon puisque les deux menus sont maintenant adjacents
  dans la barre).

**Instrument par piste/accord depuis le menu `Morceaux`** : deux items ("Choisir le son d'une
piste...", "Choisir le son des accords d'une section..." — d'abord nommés "Instrument d'une
piste..."/"Instrument des accords d'une section...") qui affichent `show-piece`, demandent
un numéro de section (et de piste pour le premier), listent `session.sampleFiles`, puis
appellent `set-track-instrument`/`set-chord-instrument` — mêmes commandes que celles tapables
directement en mode Command. `resolvedSampleName(_:)` (nouvelle fonction partagée) accepte un
numéro (résolu contre `sampleFiles`, même convention que `use-sample`), un nom, ou une chaîne
vide (= son par défaut) pour ces deux commandes.

**Toilettage terminologique et séparateurs de menu** (une demande "pour la cohérence") :
- **`MenuItem.isSeparator`** (`Menu.swift`) : une ligne non sélectionnable dans un menu
  déroulant, via `MenuItem.separator` (label vide, `action` no-op). `handleMenuKey`'s
  up/down (`case .up`/`.down`) boucle jusqu'à retomber sur un item non-séparateur au lieu de
  s'arrêter au premier index venu — sans quoi les flèches pourraient s'arrêter sur une ligne
  vide, non actionnable via Entrée. `renderDropdown` dessine un séparateur comme
  `"├" + tirets + "┤"` plutôt qu'un label encadré. Utilisé dans `Instruments` (avant les deux
  items "son"), `Soundtracks` (avant "Charger un enregistrement...", et avant "Voir le
  prompt de composition..."), `Composition` (avant "Voir le prompt de composition...").
- **`Source` → `Instruments`** (mnémonique `I`, première lettre — libre depuis la suppression
  de l'ancien menu `Instrument`) : items reformulés en vocabulaire "instrument" plutôt que
  "piste" pour rester cohérent avec `Morceaux`, qui parle déjà de pistes différemment (une
  piste *du morceau*, pas une piste *d'entrée*) — "Lister les instruments", "Activer/Arreter
  un instrument...", "Activer/Desactiver le son d'un instrument...", "Choisir un son pour un
  instrument..." (d'abord "Choisir un instrument pour une piste..."). Aucune commande
  sous-jacente renommée (`tracks`, `track <id> ...`) — uniquement les libellés du menu.
- **`Soundtrack` → `Soundtracks`**, et tous ses items reformulés en "enregistrement" plutôt
  que "soundtrack" ("Jouer l'enregistrement", "Charger/Sauvegarder/Voir l'enregistrement",
  "Composer un morceau à partir de l'enregistrement...") — même raisonnement, aucune commande
  renommée (`play-soundtrack`, `use-soundtrack`, etc. inchangées).
- **`Morceaux`** : "Jouer" → "Ecouter le morceau" ; "Sauvegarder"/"Sauvegarder sous..." →
  "Sauvegarder le morceau"/"Sauvegarder le morceau sous..." (même raison que pour
  `Soundtracks` : lisible sans ambiguïté à côté d'autres "Sauvegarder" dans d'autres menus).
- **L'assistant "Nouveau morceau..." (menu `Composition`) fusionne l'ancien "Coller un
  texte..."** (retiré du menu, la commande `paste-text` reste utilisable seule) et gagne des
  **indications de style libres** (ex. "romantique, mode mineur") : demande titre → texte →
  indications → lance `compose <titre>` directement. `LLMPieceComposer.buildPrompt(sourceText:additionalInstructions:)`
  ajoute un bloc "Additional style guidance..." après le texte quand des indications sont
  données ; `ImprovSession.additionalCompositionInstructions`/`setAdditionalCompositionInstructions(_:)`
  les stocke (nil/chaîne vide = aucune), `currentTextCompositionPrompt()` les inclut (sauf
  override actif, exactement comme `sourceText` lui-même). `composeFromText(title:generate:)`
  gagne un paramètre `title` (même mécanique que `composeSoundTrackToPieces(title:...)`) :
  remplace le titre choisi par l'IA une fois la réponse validée, pas envoyé dans le prompt
  lui-même (cohérent avec le fait que le prompt sert à générer le *contenu*, pas le nom).
  Nouvelle commande CLI `indications [texte]` (vide = efface) pour du monde-Command sans
  passer par le menu.

**Suite du toilettage — "Voir l'enregistrement" replacé, composition-depuis-l'enregistrement
déplacée sous `Morceaux`, renommage `Jam Session`** :
- **`MenuItem.header(_ title:)`** (`Menu.swift`) : même comportement non sélectionnable que
  `.separator`, mais avec un titre affiché en estompé (`\u{1B}[2m`) au lieu d'un simple trait
  — une "sous-section nommée" à l'intérieur d'un seul menu déroulant plat, puisque ce système
  de menus n'a pas de vrais sous-menus imbriqués. Partage l'implémentation avec `.separator`
  (même init privé `isSeparator: Bool`, seul le `label` diffère) et donc la même protection
  anti-crash dans `handleMenuKey`.
- **`Soundtracks`** : "Voir l'enregistrement" déplacé avant "Jouer l'enregistrement" (juste
  après "Arreter l'enregistrement"), à la demande explicite de l'utilisateur — pas de raison
  fonctionnelle, un simple choix d'ordre.
- **`MenuItem.header("Assistant IA")` a d'abord été placé dans `Morceaux`, puis ramené dans
  `Soundtracks`** (voir la section suivante, datée, pour le détail du revirement) — sa
  position **actuelle** est en fin de `Soundtracks`, après son séparateur d'origine :
  contient "Composer un morceau à partir de l'enregistrement..." et ses quatre items de
  gestion du prompt de composition (`show-soundtrack-prompt` etc. — plus de suffixe
  "(enregistrement)", redevenu inutile une fois de retour dans `Soundtracks`, où "le prompt
  de composition" ne désigne déjà que celui-là).
- **`Jam Session`** : "Demarrer un serveur..." → "Demarrer une jam session...", "Arreter le
  serveur" → "Arreter la jam session", "Rejoindre un serveur (adresse connue)..." →
  "Rejoindre une jam session...", "Decouvrir des serveurs..." → "Trouver une jam session...",
  "Se deconnecter du serveur" → "Quitter la jam session". Toujours aucune commande renommée
  (`server`/`stop-server`/`client`/`discover`/`disconnect`).

**Revirement immédiat — `Assistant IA` ramené dans `Soundtracks`, `Morceaux` réorganisé en 4
groupes.** L'utilisateur est revenu sur le placement dans `Morceaux` dès le tour suivant :
"Composer un morceau à partir de l'enregistrement..." et ses 4 items de prompt sont en fait
spécifiques à l'enregistrement, donc **`Soundtracks`** en reste le bon endroit — en section
séparée (`MenuItem.header("Assistant IA")`) à la toute fin du menu, après son séparateur
d'origine. `Morceaux`, débarrassé de cette section, est réorganisé en 4 groupes séparés par
`MenuItem.separator` :
1. Ecouter le morceau / Voir le morceau (structure et instruments)
2. Choisir le son de lecture du morceau... / Choisir le son d'une piste... / Choisir le son
   des accords d'une section...
3. Charger demo / Charger morceau... / Sauvegarder le morceau / Sauvegarder le morceau sous...
4. `MenuItem.header("Assistant IA")` — **volontairement sans aucun item derrière** pour
   l'instant : un intitulé de sous-section réservé, en attendant une future fonctionnalité de
   modification par dialogue ("plus vite", "moins vite"...) qui s'appliquerait à *n'importe
   quel* morceau chargé (texte, soundtrack, ou chargé depuis un fichier) — contrairement à la
   composition-depuis-l'enregistrement, qui reste spécifique à une source et vit donc dans
   `Soundtracks`. Un header sans item à la fin d'une catégorie n'est pas un cas dangereux : la
   boucle de saut de `handleMenuKey` retombe simplement sur l'index 0 en bouclant — vérifié
   par pty (12 appuis flèche-bas de suite dans `Morceaux`, qui doit forcément croiser ce
   header au moins deux fois, sans plantage).

**Encore un tour de toilettage — MIDI déplacé vers `MusicLab`, `Morceaux`/`Soundtracks` réorganisés en groupes explicites, `Soundtracks`→`Enregistrement`, et la vraie nouveauté : titre/description/indications persistés et consultables.**
- **`Mode MIDI: fusionne`/`Mode MIDI: individuel` déplacés d'`Instruments` vers `MusicLab`**,
  qui gagne 4 groupes explicites séparés par `MenuItem.separator` : (1) Infos/Aide,
  (2) les cinq "Choisir dossier de..." + "Choisir une connexion LLM..." (le choix de
  connexion n'a pas de groupe dédié dans la demande, rattaché ici puisque c'est la suite
  naturelle du choix de son dossier), (3) les deux items MIDI, (4) Quitter. `Instruments`
  perd ces deux items — rien d'autre n'y change.
- **`Morceaux`** gagne un `MenuItem.separator` explicite juste avant
  `MenuItem.header("Assistant IA")` (qui n'en avait pas jusqu'ici — le header seul faisait
  office de séparation visuelle ; maintenant il y a les deux, à la demande explicite
  "isoler après un séparateur").
- **`Soundtracks` renommé `Enregistrement`** (mnémonique `T`→`E`, première lettre, libre).
  Aucune commande sous-jacente renommée.
- **`Composition`** : "Nouveau morceau..." → **"Decrire le morceau..."**, "Composer a partir
  du texte" → **"Composer a partir de la description"** — le contenu collé (`sourceText`) se
  pense maintenant comme une *description* du morceau à composer, pas nécessairement un
  poème. Nouvel item **"Voir la description"** → commande `show-description` →
  `printCompositionDescription()` (nouveau, `main.swift`) affiche titre/description/
  indications via `TextStyle.field`, même schéma que `printSoundTrackDetail`/`printPieceDetail`.
- **Le titre devient un vrai état persisté, pas seulement une variable locale du wizard** :
  `ImprovSession.compositionTitle: String?`/`setCompositionTitle(_:)` (nil/chaîne vide =
  aucun — même convention que `additionalCompositionInstructions`), pour que
  "Voir la description" ait quelque chose à montrer même après que le wizard a rendu la main.
  Le wizard "Decrire le morceau..." appelle `setCompositionTitle(title)` en plus de
  `setSourceText`/`setAdditionalCompositionInstructions`, puis `compose <title>` comme avant
  — `compositionTitle` n'est **pas** automatiquement mis à jour par `composeFromText(title:)`
  lui-même (les deux restent indépendants : `compose "Autre Titre"` tapé directement au clavier
  n'écrase pas ce que `show-description` affichait). Nouvelle commande CLI `title [texte]`
  (vide efface), symétrique de `indications [texte]`.
- Test coverage : `testSetCompositionTitleEmptyStringClearsIt` (`ImprovSessionTests.swift` +
  `SanityChecks`). 252 → **255 checks, 0 failures**.
- Vérifié via pty : les 6 menus diffés item-par-item contre la demande exacte ; `t`
  (mnémonique historique de `Soundtracks`) n'ouvre plus rien ; le wizard "Decrire le
  morceau..." exécuté de bout en bout (titre "Ma Ballade" → description → indications
  "romantique, mode mineur") échoue proprement à l'étape LLM (aucune connexion choisie dans
  ce test), puis `show-description` confirme les trois champs correctement affichés.

**`Enregistrement` : retrait du header "Assistant IA", deux séparateurs à sa place.**
L'utilisateur a préféré deux `MenuItem.separator` simples plutôt que le header nommé :
un avant "Composer un morceau à partir de l'enregistrement...", un second avant "Voir le
prompt de composition...". Note pour la prochaine fois qu'un header nommé est proposé pour
grouper des items dans ce menu : ce n'est pas la préférence par défaut de l'utilisateur — un
simple séparateur suffit si le regroupement est déjà clair par le contexte des libellés.

**Correctif de scintillement, round 1 (`renderConsoleFrame`) — un seul `print` par frame au
lieu d'un par ligne.** Signalé : "sautillement de l'écran quand le menu est déployé", d'autant
plus visible que les dropdowns se sont allongés au fil des demandes précédentes (15+ lignes
pour `Enregistrement`). Avant : chaque ligne de la frame (~26 avec un menu ouvert) déclenchait
son propre `print(...)`. Après : `renderConsoleFrame()` accumule toute la frame (curseur-home,
chaque ligne, `\x1B[J` final) dans une seule `String`, puis fait un seul `print` à la fin.
**La vérification pty initiale de ce round (comptage des lectures pty à 1024 octets = 1
occurrence de `ESC[H` par lecture) s'est révélée non concluante** : creusé plus tard (round 2
ci-dessous, avec un clavier affiché — une frame plus grosse) — le pty plafonne chaque `read()`
côté lecteur à 1024 octets *quel que soit* le nombre d'écritures côté application ; ça ne
prouve donc rien sur le nombre réel de `write()` — juste une coïncidence de taille pour la
frame plus courte testée alors. Leçon : le chunking observé côté lecteur pty n'est pas une
preuve fiable du nombre d'écritures côté écrivain ; ne pas réutiliser cette méthode.

**Correctif de scintillement, round 2 (abandonné) — `setvbuf` en cours de route, mauvaise
piste.** Tentative : rebufferiser stdout en entrant dans `console` (`setvbuf(stdout, nil,
_IOFBF, 1 << 16)`) + `fflush` explicite par frame + retour à `_IONBF` en sortie, en pariant
que "parfois le clavier ne se dessine pas complètement" venait du `_IONBF` global. **Ça a
rendu les choses nettement pires** ("j'ai l'impression que l'écran se redessine en permanence
... ralentit très fort") : `setvbuf` n'est bien défini par la norme C que s'il est appelé
*avant* toute E/S sur le flux — au moment où `console` démarre, stdout a déjà servi à tout
l'affichage du REPL, donc le rappeler en cours de route est un comportement non défini.
Abandonné entièrement, `stdout` reste `_IONBF` du début à la fin, une seule fois, au tout
début de `main.swift` — plus aucun autre appel à `setvbuf` nulle part dans le programme.

**Correctif de scintillement, round 3 — la vraie cause : `O_NONBLOCK` sur stdin partagé avec
stdout via le pty.** En cherchant à vérifier le round 2, remplacé temporairement le `print`
de `renderConsoleFrame` par une écriture bas niveau (`FileHandle.standardOutput.write`) pour
observer le comportement réel — et ça a **crashé de façon reproductible** :
`NSFileHandleOperationException: ... Resource temporarily unavailable` (EAGAIN sur l'écriture).
EAGAIN sur une écriture ne peut se produire que sur un descripteur **non bloquant** — or rien
dans ce fichier ne rend stdout non bloquant... sauf indirectement : `setStdinNonBlocking`
(`Menu.swift`, appelé à l'entrée/sortie de `console` et dans `runMenuAction`) met `O_NONBLOCK`
sur `STDIN_FILENO` pour que `readKey()` puisse lire sans bloquer. Sous la manière standard
dont un shell interactif s'attache à un terminal (`login_tty(3)` : le pty esclave est ouvert
**une seule fois** puis `dup2`-é sur les descripteurs 0, 1 et 2), les trois partagent la
**même** description de fichier ouvert sous-jacente — `O_NONBLOCK` est une propriété de cette
description partagée, pas du descripteur en tant que tel : rendre stdin non bloquant rendait
donc **stdout et stderr non bloquants aussi**, silencieusement. Une écriture qui tombait sur
un tampon pty momentanément plein renvoyait EAGAIN : `print`/stdio l'ignorait en silence (la
cause probable et réelle du "clavier parfois incomplet" dès l'origine, bien avant ce round de
correctifs), et `FileHandle.write` la transformait en exception fatale (la cause du crash/du
ralentissement sévère signalé). **Ni le nombre de `print` par frame (round 1) ni le mode de
bufferisation (round 2) n'étaient la vraie cause.**
- **Corrigé à la racine** : `setStdinNonBlocking` supprimé entièrement (fonction + ses 4 sites
  d'appel dans `Menu.swift`/`main.swift`). `readKey()` (`Menu.swift`) n'a plus besoin que
  `STDIN_FILENO` soit non bloquant : une fonction privée `stdinHasByteAvailable()` interroge
  `poll(2)` avec un délai nul avant chaque lecture (la première comme les deux lectures de
  continuation de la séquence d'échappement des flèches) — un moyen de "lire sans bloquer"
  qui n'a besoin de toucher aucun drapeau de descripteur, donc qui ne peut plus jamais
  déteindre sur stdout. `renderConsoleFrame()` est revenu à un simple `print` bufferisé
  (sûr maintenant que stdout ne peut plus être non bloquant).
- **Vérifié par la reproduction directe du crash, puis sa disparition** — pas seulement par
  relecture de code : capturé le crash exact ci-dessus via un lancement direct du binaire
  sous pty (contournant `swift run`, pour écarter tout bruit de recompilation), puis, après le
  correctif, 3 exécutions consécutives de 3 s chacune avec un clavier affiché : ~9,5 images/s
  stables (proche du taux de rafraîchissement visé de 10 Hz), 0 crash, réactivité immédiate
  (0 ms) après Échap — contre un crash systématique et reproductible avant.

**Astuce clavier de la barre de menu déplacée sur sa propre ligne, masquée quand un menu est
ouvert** (`renderConsoleFrame`) : `"(lettre: ouvre un menu, fleches, Entree, Echap...)"` était
concaténée à la fin de la ligne de `renderMenuBar` ; elle passe maintenant sur la ligne
suivante, et seulement quand `openMenuIndex == nil` — une fois un menu déroulé, cette ligne
est simplement omise (le contenu du dropdown prend sa place), plutôt que remplacée par une
ligne vide.

**Clavier ASCII : 3 lignes de touches, pas 4** (`Keyboard.swift`/`main.swift`). Les trois
appels à `renderKeyboard` (piste en écoute, lecture d'un `Piece`, lecture d'une soundtrack)
étaient passés à `blackZoneRows: 2, whiteZoneRows: 2` (4 lignes de touches : les blanches
occupent `blackZoneRows + whiteZoneRows` puisqu'elles sont aussi dessinées dans la zone
noire ; les noires occupent seulement `blackZoneRows`). Corrigés en `whiteZoneRows: 1` —
touches blanches sur 3 lignes au total, noires sur 2, comme demandé et comme sur un clavier
réel. Vérifié via pty : la ligne de touches "blanc seul" (`░ ░ ░┊░ ░ ░ ░|...`) apparaît
exactement une fois sous les deux lignes partagées noir+blanc, plus la ligne de marqueurs de
mode et la ligne d'étiquettes — 5 lignes au total pour le bloc clavier, comme attendu.

**`printHelp()` regroupée par catégorie** (Général / Morceaux / Pistes d'entrée / Instruments /
Soundtrack / IA / Session collaborative) plutôt qu'une seule liste plate — demande explicite
de l'utilisateur pour rester lisible à mesure que le nombre de commandes grossit.

Commandes Soundtrack : `record start [<id> ...]`/`record stop`, `play-soundtrack`,
`soundtracks <dossier>`/`use-soundtrack <n|nom>`, `save-soundtrack`/`save-soundtrack-as <nom>`,
`show-soundtrack`, `compose-piece-from-soundtrack [n]` — nouveau menu **Soundtrack** (mnémonique
`T`, la lettre choisie apparaît réellement dans le titre, même convention que `IA`→`A`). Champs
`Recording`/`Soundtrack`/`Playing (soundtrack)` ajoutés à `status`/`console`. Menu **Fichier**
renommé **Morceaux** (mnémonique `M`) et absorbe désormais "Jouer" ; le menu **Lecture**
(qui ne contenait que ça) a été supprimé.

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
`MusicTheoryKit/`. Compteur de vérifications à la fin de cette session : **211 checks, 0 échec**,
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
- **Session collaborative sans authentification ni chiffrement** : TCP en clair, tout client
  qui atteint le port est accepté (design délibéré pour cette première version — voir §AppCore).
  Ne pas exposer ce port au-delà d'un réseau de confiance (LAN/VPN).
- **`localClientID` ne survit pas à un relance** (UUID en mémoire, non persisté — voir §AppCore
  pour la vraie raison, un bug de collision trouvé en testant).
- **Découverte Bonjour dépendante du réseau local et de la permission macOS** :
  ne fonctionne que sur le même segment réseau (pas à travers un VPN ou un autre sous-réseau
  sans relais mDNS) ; macOS peut demander la permission « Réseau local » au premier essai
  (non observée en pty sur cette machine de dev, probablement déjà accordée au Terminal —
  à surveiller sur une machine fraîche/un vrai premier lancement).
- **Enregistrement Soundtrack : une seule piste locale à la fois, un seul timbre à la lecture** :
  ne capture jamais les pistes `.remote` (voir §AppCore) ; `SoundTrackPlayer` rejoue toutes les
  pistes enregistrées à travers un seul `SamplerUnit`, pas un timbre par piste d'origine.
- **Pas encore de "enregistrer une SoundTrack pendant qu'un Piece joue"** : demandé par
  l'utilisateur mais explicitement reporté ("Eventuellement, plus tard") — non implémenté.

## Suite prévue (feuille de route)

D'après la mémoire du projet, les phases suivantes restent à faire : `KeyboardView`
vectoriel/tactile (SwiftUI, nécessite Xcode), affinage de la reconnaissance
(RecognitionEngine — déjà largement implémenté ce jour), un vrai module texte→progression
au-delà du premier jet LLM actuel, et une vue timeline/lead-sheet.

Explicitement demandé par l'utilisateur pour **plus tard**, pas cette session : pouvoir
enregistrer une nouvelle SoundTrack pendant qu'un `Piece` est en train de jouer, et réfléchir
à comment l'intégrer dans le morceau une fois enregistrée.
