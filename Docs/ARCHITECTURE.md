# Documentation technique — Music Improv Assistant

Documentation du code généré dans ce package Swift. Reflète l'état du code à la fin de la
session du 2026-07-10. Pour l'historique détaillé des décisions/itérations, voir la mémoire
`project_improv_app_roadmap.md` ; pour la définition des termes ambigus/récurrents
(« piste », « prompt de composition », les trois écrans...), voir `Docs/GLOSSAIRE.md`.

## Vue d'ensemble

Une application Swift Package Manager, orchestrée aujourd'hui par un front-end en ligne de
commande (`JamShack`), mais dont toute la logique métier vit dans une couche
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

Le projet est versionné avec git (dépôt dans `MusicTheoryKit/`, avec un remote `origin`).

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
AudioEngine (lecture Piece + SoundTrack, micro/FFT)   MIDIEngine (CoreMIDI)   NetEngine (TCP)   WebConsole (HTTP)
                    ↑                                        ↑                    ↑                  ↑
                    └────────────────────┴─────────────┬──────┴──────────────────────────────────────┘
                                                         │
                                            LLMEngine (composition IA,
                                             Piece <- texte OU SoundTrack)
                                                         │
                                                         ▼
                                                                    AppCore
                                                   (ImprovSession — logique applicative)
                                                                        │
                                                                   JamShack
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

**Vrai bug corrigé, pas juste une théorie : le running status MIDI n'était pas géré.**
Utilisateur signalant "des notes qui restent memorisées à tort" en jouant un vrai clavier MIDI.
`parseNoteEvents` exigeait un octet de statut (`& 0x80 != 0`) en tête de chaque message — or
beaucoup de matériel réel (surtout tout ce qui parle le vrai MIDI 5 broches plutôt que
l'USB-MIDI class-compliant) omet l'octet de statut répété pour des messages consécutifs sur le
même canal (le "running status" du standard MIDI) : juste les deux octets de données, en
comptant sur le dernier statut réel encore en vigueur. Avant la correction, ces deux octets
(tous deux `< 0x80`) étaient silencieusement sautés un par un — pour un **note-off** en
running status, ça voulait dire que la hauteur ne quittait jamais `heldPitches`, restant
bloquée "tenue" jusqu'à ce qu'un futur note-off sans lien (même hauteur, un octet de statut
réel cette fois) arrive par hasard, ou jamais. Corrigé en suivant un `runningStatus: UInt8?`
mutable pendant le parcours des octets — un octet de statut note-on/note-off réel le met à
jour, tout autre octet de statut réel le réinitialise à `nil` (un message d'un type différent
porte quasiment toujours son propre octet de statut explicite en pratique). Vérifié par 3
nouveaux tests dans `Tests/MIDIEngineTests/MIDIRawParserTests.swift` (+ miroir `SanityChecks`,
547 → 550 checks) couvrant explicitement le running-status note-on, le running-status note-off
(le cas du bug lui-même), et la remise à zéro par un octet de statut non-note. Root-cause
identifiée via un agent de recherche dédié plutôt que par supposition — classé le plus probable
des deux symptômes rapportés (l'autre, "une note jouée en affiche deux", reste possible en
mode MIDI individuel si le clavier physique expose plus d'une source CoreMIDI visible, mais
dépend du matériel de l'utilisateur et n'a pas été corrigé ici faute de pouvoir le reproduire).

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
    (`t=0.45s ON C4 (piste: clavier)`...) inséré tel quel dans le prompt, et le même paramètre
    `additionalInstructions:` que la variante texte (ajouté après coup — la soundtrack n'avait
    au départ aucune notion d'indications de style). Voir §AppCore pour qui appelle ça et ce
    qui se passe ensuite.
  - **Le prompt, dans les deux cas, a trois parties, toujours recomposées séparément — jamais
    chargé/remplacé comme un seul bloc** (voir le corps de
    `buildPrompt(sourceText:framingSentence:additionalInstructions:)`/
    `buildPrompt(fromSoundTrack:framingSentence:additionalInstructions:)` pour le texte exact) :
    1. **La phrase de cadrage** — `defaultTextFramingSentence`/`defaultSoundTrackFramingSentence`,
       deux constantes publiques nommées : *« You are a music composition assistant...
       propose a short musical piece whose mode and chord progression express its mood »*
       pour le texte, *« You are a music transcription assistant... Infer a plausible tempo
       (BPM) and reconstruct this performance as a measure-based piece »* pour la soundtrack.
       `buildPrompt` prend un paramètre `framingSentence:` (défaut = la constante
       correspondante) — c'est ce qui permet à `ImprovSession` de le remplacer sans toucher
       au reste du template (voir §AppCore).
    2. **Le schéma JSON cible — identique, textuellement partagé, dans les deux cas** :
       `title`, `tempoBPM`, `tonic`, `scaleID` (restreint à `ScaleLibrary.all.map(\.id)`),
       `sections[]` avec `chords[]` (`root`/`templateID`, restreint à
       `ChordVocabulary.seed.map(\.id)`) et `melody[]` optionnel — c'est ce bloc que
       `parseAndValidate` s'attend à pouvoir décoder et valider ; un ID hors de cette liste
       littéralement énumérée dans le prompt n'a de toute façon aucune chance de survivre à
       la validation. **Jamais exposé à un remplacement complet** (voir point suivant) —
       c'est précisément ce que ça protège.
    3. Les données + indications : le `sourceText` collé (entre `"""`), plus un bloc
       *« Additional style guidance... »* si des indications de style sont définies ; ou la
       liste brute des événements on/off horodatés (soundtrack) avec le même bloc de
       guidance si des indications soundtrack sont définies (§AppCore,
       `activeSoundTrackCompositionInstructions`).
  - **Le prompt complet n'est jamais rechargé/remplacé comme un tout** — seulement consulté
    (`show-text-prompt`/`show-soundtrack-prompt`) et **exporté** en lecture seule
    (`exportTextCompositionPrompt(as:)`/`exportSoundTrackCompositionPrompt(as:)`, §AppCore) ;
    éditer un fichier exporté n'a plus aucun effet sur la composition, précisément pour éviter
    le risque qu'un ancien mécanisme de rechargement du prompt entier posait — perdre le
    schéma (point 2) en éditant à la main. Pour personnaliser, deux leviers indépendants,
    chacun protégeant les autres parties :
    - **La phrase de cadrage** (point 1) — `ImprovSession.currentTextFramingSentence()`/
      `currentSoundTrackFramingSentence()` passent leur résultat au paramètre
      `framingSentence:` ; l'éditer ne peut jamais faire disparaître le schéma ni les données.
    - **Les indications de style** (point 3) — `additionalCompositionInstructions` (texte,
      déjà existant) et `activeSoundTrackCompositionInstructions` (soundtrack, nouveau — la
      soundtrack n'avait jusqu'ici aucun moyen d'en fournir).

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
  seulement en théorie) : deux processus `JamShack` séparés sur cette machine, l'un en
  `server`, l'autre tapant `discover`, se voient bien l'un l'autre — voir §AppCore.
- **`FramedConnection`/`NetworkServer`/`NetworkClient` sont `@unchecked Sendable`** : chaque
  propriété mutable n'est touchée que depuis la queue série dédiée à cette instance — même
  raisonnement que celui déjà appliqué à `ImprovSession` (voir plus bas).

## WebConsole — serveur HTTP fait main pour la console web

Un second transport réseau, indépendant de `NetEngine` : là où `NetEngine` fait du TCP+JSON
fait main pour la session collaborative, `WebConsole` fait du HTTP/1.1 fait main (toujours
`Network.framework`, toujours aucune dépendance tierce) pour servir une page/un script à un
navigateur — voir §AppCore pour qui le pilote et §JamShack pour la commande/le menu.
`WebConsole` ne connaît rien à `ImprovSession`/`AppCore` : il reçoit juste un closure
`onRequest` et ne sait rien de ce qu'il sert.

- **`HTTPServer`** : `start(port:)`/`stop()` sur un `NWListener`, un `HTTPConnection` par
  connexion acceptée.
- **`HTTPConnection`** : lit exactement une requête (GET uniquement, pas de corps, pas de
  keep-alive), appelle `onRequest`, écrit la réponse, ferme. Le parsing/formatage HTTP
  lui-même (ligne de requête, en-têtes de réponse) est extrait dans `HTTPWireFormat` — pur,
  sans `NWConnection`, donc testable sans socket réel (voir `Tests/WebConsoleTests/` et son
  miroir `SanityChecks`).
- **`HTTPRequest`/`HTTPResponse`** : structs triviales (méthode+chemin ; statut+type+corps).
- **`webConsoleIndexHTML`/`webConsoleAppJS`** (`StaticAssets.swift`) : les deux assets servis,
  embarqués comme constantes Swift plutôt que lus depuis le disque (pas de
  `Bundle.module`/ressources SwiftPM à gérer pour deux fichiers aussi courts). Le contrat JSON
  attendu par `app.js` en réponse à `GET /state` est documenté dans le commentaire de
  `webConsoleIndexHTML` — maintenu à la main en synchronisation avec `AppCore.WebConsoleState`
  (aucune vérification par le compilateur entre les deux, `WebConsole` n'important pas `AppCore`).
- **Mise en page responsive** : `body` a un `max-width` (1600px) centré (`margin: auto`) plutôt
  qu'une largeur fixe ou illimitée — profite de l'espace sur un grand écran sans s'étirer à
  l'infini. `.layout-columns` (flexbox, `flex-wrap: wrap`) passe automatiquement en une seule
  colonne sous une certaine largeur. Chaque clavier reste nécessairement de largeur fixe en
  pixels (les touches `.pkey` sont positionnées en absolu, incompatible avec un dimensionnement
  en pourcentage) — enveloppé dans son propre `.keyboard-scroll` (`overflow-x: auto`) pour que
  ce soit CE widget qui défile sur un écran étroit, pas la page entière.

**Piège réel trouvé pendant la vérification manuelle, pas en théorie** — deux bugs de durée de
vie distincts, tous deux liés à la même cause : un objet `Network.framework`
(`NWListener`/`NWConnection`) se maintient en vie **lui-même**, en interne, une fois démarré,
indépendamment de toute référence Swift qu'on garde dessus ; à l'inverse, laisser une closure
de callback ne capturer `self` que faiblement (`[weak self]`) peut faire disparaître **notre**
wrapper avant que ce callback n'ait eu la moindre chance de s'exécuter :
1. Chaque `HTTPConnection` était d'abord créée comme variable locale dans le closure
   `newConnectionHandler`, avec seulement des callbacks `[weak self]` — sans référence forte
   externe, elle disparaissait aussitôt le closure terminé, avant même de pouvoir lire la
   moindre requête. Symptôme observé : `curl`/`URLSession` se connectaient bien (poignée de
   main TCP réussie) mais n'obtenaient jamais de réponse (timeout, 0 octet reçu). Corrigé en
   donnant à `HTTPServer` un dictionnaire `activeConnections` qui retient chaque connexion
   jusqu'à son propre `onClose` — même principe que `NetworkServer.connections`.
2. `HTTPServer.stop()` faisait `queue.async { [weak self] in self?.listener?.cancel() ... }`,
   alors que l'appelant (`ImprovSession.stopWebConsole()`) fait `webConsoleServer?.stop();
   webConsoleServer = nil` juste après — la seule référence forte à `HTTPServer` disparaissait
   avant que le `cancel()` mis en file d'attente n'ait pu s'exécuter, donc `self` valait déjà
   `nil` une fois le closure exécuté : le `NWListener` sous-jacent, lui, restait actif
   indéfiniment (confirmé au `lsof` : le port restait en `LISTEN` bien après l'arrêt). Corrigé
   en capturant `self` **fortement** dans ce `queue.async` — intentionnel : ça garde
   l'instance en vie juste assez longtemps pour que son propre nettoyage s'exécute, avant de
   se libérer naturellement une fois terminé.
- Vérifié par la reproduction directe (requêtes HTTP réelles en boucle via un script, `lsof`
  pour confirmer qu'un port reste bien libéré après `stop`) plutôt que par relecture de code
  seule — même discipline que la leçon `feedback-debug-verify-dont-theorize` déjà retenue pour
  le bug de scintillement du terminal.

### Portée musicale (`renderStaffSVG`, dupliquée dans les deux assets)

Sous chaque clavier ASCII/HTML (console web et clavier virtuel), une portée à deux clés (sol
et fa) en SVG généré côté client. Le code JS est identique dans `StaticAssets.swift` et
`VirtualKeyboardAssets.swift` (copié tel quel, pas factorisé — les deux fichiers embarquent
chacun un script HTML autonome, aucun module JS partagé entre les deux pages) ; toute future
correction doit être répercutée dans les deux.

- **Fenêtre fixe Sol2-Do6** (`STAFF_MIN_MIDI`/`STAFF_MAX_MIDI`), un ton naturel de marge
  au-delà de `MIN_MIDI`/`MAX_MIDI` de chaque côté — même logique de fenêtre fixe (pas
  recentrée dynamiquement) que le clavier ASCII du terminal, pour la même raison : simplicité,
  pas de redimensionnement à gérer.
- **`STAFF_ROWS`** : une entrée par note naturelle de la fenêtre, avec une parité
  ligne/interligne calculée une seule fois par rapport à un point d'ancrage connu (Mi4, la
  ligne du bas de la clé de sol) — les lignes et interlignes alternent strictement sur toute la
  portée, y compris au-delà des deux clés, donc les lignes supplémentaires ne sont qu'une
  continuation du même motif plutôt qu'un cas particulier à part.
- **`staffLedgerRows(rowIndex)`** : parcourt depuis le bord de la portée le plus proche jusqu'à
  la note, en ne gardant que les positions de parité "ligne" — généralise à n'importe quelle
  note sans table de correspondance séparée à tenir à jour.
- **Clés positionnées sur G4/F3 ET à la bonne taille** — deux passes, pas une. La première
  passe (`STAFF_CLEF_G_DY`/`STAFF_CLEF_F_DY`) a centré la volute de la clé de sol sur Sol4 et
  les deux points de la clé de fa sur Fa3 mais avec une taille de police beaucoup trop petite
  (34) — trouvée en jugeant seulement l'alignement, pas la proportion. Résultat : la clé ne
  dépassait même pas les lignes de la portée, contrairement à une vraie clé de sol/fa qui
  déborde nettement au-dessus et en dessous — exactement la plainte de l'utilisateur ("ne
  respecte pas la taille standard"), qu'aucun réglage de position seule ne pouvait corriger.
  Deuxième passe : mesure de l'extension réelle de CE glyphe (haut/bas de l'encre dessinée, et
  position de son "œil"/du milieu des deux points) par rapport à la ligne de base du texte, à
  une grande taille de police, dans une capture Chrome headless avec grille de mesure — ratios
  trouvés : l'œil de la clé de sol est à 0.25em au-dessus de la ligne de base, le haut du
  glyphe à 0.417em au-dessus de l'œil, le bas à 0.293em en dessous ; l'ancrage Fa3 de la clé de
  fa (milieu des deux points) est à 0.45em au-dessus de la ligne de base, le haut du glyphe à
  0.217em au-dessus de cet ancrage, le bas à 0.45em en dessous. `STAFF_CLEF_FONT_SIZE_G = 130`/
  `STAFF_CLEF_FONT_SIZE_F = 118` choisies à partir de ces ratios puis réduites (un premier choix
  plus grand, dérivé des mêmes ratios pour atteindre l'extension "idéale" façon partition
  imprimée, faisait visuellement se chevaucher les deux clés — l'écart entre les deux portées
  n'est pas assez grand pour ça) — un compromis entre "dépasse clairement la portée" et "ne
  chevauche pas l'autre clé". `STAFF_MARGIN_TOP`/`STAFF_MARGIN_BOTTOM` (46/32, avant : 22/22
  symétrique) agrandis en conséquence — la clé de sol déborde plus au-dessus que la clé de fa
  en dessous, d'où des marges asymétriques ; `STAFF_STAVES_X` (78, avant 32) pour laisser la
  place à la clé de fa, plus large des deux à cause de ses deux points. À revérifier avec une
  nouvelle mesure si le rendu de ce glyphe change un jour (moteur de rendu, police système).
  **Troisième passe** (retour utilisateur après la deuxième) : `STAFF_CLEF_FONT_SIZE_F` réduite
  d'encore ~30% (118 → 83, `STAFF_CLEF_G_DY`/`STAFF_CLEF_F_DY` recalculées automatiquement —
  ce sont des formules dérivées du font-size, pas des constantes séparées à resynchroniser à la
  main) — la clé de fa restait trop massive à côté de la clé de sol une fois les deux
  effectivement visibles côte à côte. La clé de sol elle-même n'a pas été retouchée (seule la
  clé de fa a été signalée comme trop grosse).
  **Quatrième passe** : `STAFF_CLEF_G_DY` affiné de `0.25 * fontSize` à `0.22 * fontSize` — un
  léger excès faisait sembler la clé de sol "un tout petit peu trop basse" par rapport à la
  ligne Sol4. Vérifié en comparant plusieurs valeurs de ratio côte à côte contre une ligne de
  repère, comme pour les passes précédentes.
- **Lignes de portée prolongées sous les deux clés, comme en vraie notation** —
  `STAFF_LINES_LEFT_X` (nouvelle constante, proche du bord gauche du papier) sépare enfin "où
  les lignes commencent" de "où la première colonne de notes commence" (`STAFF_STAVES_X`,
  inchangée) : les deux étaient confondues avant ce correctif, laissant les lignes s'arrêter net
  à droite des clés au lieu de passer dessous. Les clés, dessinées APRÈS les lignes dans le
  SVG (donc peintes par-dessus), continuent de bien apparaître au premier plan.
- **Historique d'événements, pas un instantané** (`STAFF_HISTORY_LENGTH = 20`, initialement 12
  puis agrandi — "il y a assez de place") : `renderStaffSVG`
  prend un tableau d'événements `{ pitches, chordRoot, chordTones }` (un événement = une
  colonne, la plus ancienne à gauche) plutôt que les seules notes tenues à l'instant présent.
  Une note seule tenue sans accord reconnu est un événement à part entière (gris), au même
  titre qu'un accord. La largeur du SVG grandit avec le nombre de colonnes ; `.staff` passe
  donc de `width: <fixe>` à `width: auto` (hauteur fixe, ratio préservé) pour que
  l'élargissement du contenu élargisse vraiment l'affichage au lieu d'être écrasé dans une
  boîte de taille fixe.
  **Le tableau est désormais construit côté serveur, pas côté client** (`AppCore/ImprovSession.
  swift`, `recordChordEventIfChanged` + `recentChordEvents: [TrackID: [WebConsoleChordEvent]]`,
  servi via `WebConsoleTrackState.recentChordEvents` dans le JSON de `GET /state`). Avant ce
  correctif, l'historique était construit côté JS : chaque page maintenait son propre tableau
  roulant (`updateStaffHistory` côté console, indexé par id de piste ; `staffHistory` côté
  clavier virtuel) et lui poussait une colonne (`pushStaffEvent`) à chaque fois qu'elle recevait
  un nouvel état via son polling de `GET /state`. Ça créait un vrai trou : le polling a une
  période fixe, donc tout accord joué ET relâché plus vite que cette période n'était tout
  simplement jamais vu par le client — l'historique côté navigateur ne pouvait pousser que ce
  qu'il recevait, pas ce qui s'était réellement passé entre deux requêtes. C'est la cause du
  signalement utilisateur "des notes/accords se perdent parfois". Corrigé en déplaçant la
  construction de l'historique à l'endroit où l'état change réellement : `recordChordEventIfChanged`
  est appelée depuis `refreshRecognition` (donc dans le même chemin protégé par
  `liveInputQueue.sync` qui traite chaque événement MIDI), et n'ajoute une colonne que si
  l'instantané courant (pitches/chordRoot/chordTones) diffère du dernier événement enregistré
  ET qu'il y a au moins une note tenue — même règle qu'avant pour "pas de colonne silence sur
  un relâchement complet", mais appliquée à la source plutôt qu'à la réception. Les deux pages
  (`StaticAssets.swift`, `VirtualKeyboardAssets.swift`) se contentent maintenant de lire
  `track.recentChordEvents` tel quel et de le passer à `renderStaffSVG` — `pushStaffEvent`,
  `staffHistory`/`staffHistories` et la boucle de purge associée dans `renderRunTab()` ont été
  supprimés des deux fichiers. Couvert par
  `testRecentChordEventsLogsChangesAndSkipsRestsOnFullRelease` et
  `testRecentChordEventsCapsAtTwentyEntries` (`Tests/AppCoreTests/ImprovSessionTests.swift`,
  mirroré dans `SanityChecks`) — possible maintenant que la logique vit dans `AppCore` (Swift)
  plutôt que dans le JS embarqué, contrairement au reste de cette section sur la portée qui
  reste non testable par XCTest/`SanityChecks` (voir plus bas).
- **Décalage en zigzag pour les secondes tenues ensemble** (`shiftByRow`), par colonne : notes
  triées du grave à l'aigu, une note n'est décalée que si son voisin immédiatement au-dessus
  existe ET n'a pas lui-même déjà été décalé — reproduit le zigzag habituel de gravure plutôt
  qu'un décalage bête de "toute note qui a un voisin au-dessus".
- **Rondes de note agrandies** (`STAFF_NOTE_RX`/`STAFF_NOTE_RY`, ~près de la hauteur d'un
  interligne) et **contour de la même couleur que le remplissage** (`.staff-note-root`,
  `.staff-note-tone`, etc. — `stroke` = `fill`, plus de liseré gris uniforme `#333`) — mêmes
  couleurs que `.pkey.*`.
- **Altérations** : pas d'armure — chaque note altérée porte son propre dièse/bémol,
  puisqu'il n'existe nulle part ailleurs dans ce projet de logique d'orthographe par
  tonalité/mode ; le nom vient de la même table `NOTE_NAMES` (dièses uniquement) que le reste
  de la page.
- **Largeur minimale alignée sur le clavier, dans les deux pages** (`renderStaffSVG(history,
  minWidthPx)`) : le papier de la portée (fond blanc) n'est jamais plus étroit que le clavier
  affiché juste au-dessus, converti en unités de viewBox via le ratio hauteur-affichée/
  hauteur-viewBox (`STAFF_DISPLAY_HEIGHT_PX = 130`) — évite que la portée paraisse plus étroite
  que le clavier juste parce qu'il n'y a pas encore assez d'historique pour la remplir. Diffère
  entre les deux pages seulement dans la SOURCE de `minWidthPx` : `VirtualKeyboardAssets.swift`
  utilise `keyboardPixelWidth` (recalculé à chaque reconstruction du piano — changement
  d'octave — puisque la fenêtre `[MIN_MIDI, MAX_MIDI]` glisse mais garde toujours le même
  nombre de touches ; correction ajoutée après-coup, la console web n'en avait pas au départ) ;
  `StaticAssets.swift` utilise `KEYBOARD_TOTAL_WIDTH`, une simple constante (`Math.ceil((MAX_MIDI
  - MIN_MIDI + 1) / 12) * 7 * WHITE_KEY_WIDTH`, dérivée des mêmes `MIN_MIDI`/`MAX_MIDI`/
  `WHITE_KEY_WIDTH` que `keyboardHTML` elle-même) puisque cette page n'a pas de glissement
  d'octave — une seule fenêtre fixe pour toute piste/guide/lecture.
- **Vérifié** : la logique JS (lignes/interlignes, ledger, zigzag, coloration, historique) via
  un script Node.js autonome (pas de navigateur ni Xcode disponibles dans cet environnement —
  voir la limite déjà documentée ailleurs) ; le rendu réel (positionnement des clés, tailles,
  couleurs, alignement des largeurs, onglets) via des captures d'écran Chrome headless de la
  vraie page extraite du fichier Swift avec un `fetch`/`prompt` simulés (`prompt` bloque
  indéfiniment sous Chrome headless sans interface — piège réel rencontré en testant, pas
  une supposition : reproduit d'abord sur le code déjà commité, donc pas une régression
  introduite ici). Aucun test XCTest/`SanityChecks` ajouté : cette portée est un script JS
  embarqué dans une constante Swift, hors de portée du compilateur Swift comme de
  `SanityChecks` (même convention déjà établie pour `keyboardHTML`/`renderWheel`).

### Second serveur : le Clavier virtuel (`VirtualKeyboardAssets.swift`)

Une seconde instance d'`HTTPServer`, sur un port indépendant, pilotée par
`ImprovSession.startVirtualKeyboard(port:)`/`stopVirtualKeyboard()` — même classe `HTTPServer`
réutilisée telle quelle (elle ne connaît qu'un closure `onRequest`, aucune notion de "combien
d'instances"), juste un second `onRequest` différent
(`handleVirtualKeyboardRequest`) et ses propres assets (`virtualKeyboardIndexHTML`/
`virtualKeyboardAppJS`). Contrairement à la console web (strictement lecture seule),
`GET /note-on?pitch=<midi>`/`GET /note-off?pitch=<midi>` acceptent une entrée — en query
string plutôt qu'un corps de requête, `HTTPRequest`/`HTTPWireFormat` ne parsant toujours que
la ligne de requête (voir plus haut) ; `ImprovSession.splitQuery(_:)` découpe le `?...` à la
main, un besoin trop ponctuel pour justifier un vrai parseur de query string générique dans
`WebConsole`. Ces deux routes appellent `pressKey`/`releaseKey` sur
`TrackID.webKeyboard(clientID:)` — une piste dédiée (voir `Track.swift`), distincte de
`.computerKeyboard` : un vrai clavier MIDI, le "clavier" tapé dans le terminal, et un onglet
de navigateur peuvent ainsi tous écouter/sonner indépendamment sans se marcher dessus.

**Multi-clavier** : `clientID` (pas le nom affiché) identifie une connexion — chaque
navigateur génère et garde le sien en `localStorage`, envoyé sur chaque requête
(`?client=...&name=...`). Contrairement à `.computerKeyboard`/aux ports MIDI (fixes,
recréés à chaque `refreshTracks()`), ces pistes sont dynamiques : `ensureWebKeyboardTrack`
crée la piste au premier contact d'un `clientID` (et met juste à jour son `label` — l'alias —
ensuite), mirroir de `addOrUpdateRemoteTrack` pour les pistes `.remote` d'une jam session ;
`removeAllWebKeyboardTracks` les efface toutes quand le serveur s'arrête (mirroir de
`removeAllRemoteTracks`). `GET /state?client=...` ne renvoie donc que la piste de CE client —
pas un instantané partagé mis en cache comme la console web (`refreshWebConsoleStateSoon`),
puisque chaque client attend un état différent ; recalculer à la demande reste bon marché
(la reconnaissance elle-même tourne déjà en continu, cette route ne fait que la lire).

**Clavier de l'ordinateur, entièrement côté client** (`virtualKeyboardAppJS`, aucune donnée
serveur impliquée) : `KEY_MAP` (objet `code -> pitch`) est reconstruit par
`recomputeKeyRange()` à partir de deux paires de rangées superposées (`BASS_WHITE_CODES`/
`BASS_BLACK_CODES` pour le grave — chiffres + `qwertyuiop`, `G3` à `B4`... — et
`TREBLE_WHITE_CODES`/`TREBLE_BLACK_CODES` pour l'aigu qui suit — `S D G H J` + `zxcvbnm`,
continuant proprement sur un Do juste après le Si grave), ancrées sur `OCTAVE_STOPS` (C0..C6,
MIDI 12..84) via `octaveIndex`. Indexé par `KeyboardEvent.code` (position physique de la
touche), pas par `.key` (caractère produit) : `.code` nomme la touche d'après sa position sur
une disposition ANSI/US de référence, quelle que soit la disposition réellement configurée
côté OS — ce qui reste vrai sur QWERTZ (qui échange les étiquettes Y/Z, pas leurs
emplacements physiques), AZERTY, etc.

`codeLabels` (l'étiquette affichée sur chaque touche) reste séparé de `KEY_MAP` — seule la
LABEL a besoin de savoir quelle disposition le visiteur utilise réellement, jamais `KEY_MAP`
lui-même. QWERTY et QWERTZ ne diffèrent, pour les codes utilisés ici, que par un seul
échange (Y/Z) : `keyboardLayout` (`'qwerty'` | `'qwertz'`, persisté dans `localStorage`,
comme `alias`) pilote ce seul échange via `applyKeyboardLayout()`, basculé par
`toggleKeyboardLayout()` (lien "Disposition clavier ... — changer", à côté de l'alias) —
c'est la source de vérité, pas `navigator.keyboard.getLayoutMap()` : cette API a d'abord été
essayée seule, mais elle exige un **contexte sécurisé** (`https:`, ou `http://localhost`
précisément) et n'existe pas du tout sur Safari/Firefox — elle échoue donc silencieusement
dès que la page est ouverte en `http://<adresse-LAN>:port` depuis un second appareil, le cas
d'usage normal de cette page (voir "Multi-clavier" plus haut), laissant l'inversion Y/Z non
corrigée malgré un `KEY_MAP` déjà correct. Elle reste utilisée, mais seulement comme
pré-remplissage au tout premier chargement (si `localStorage` n'a encore aucune préférence
ET que l'API répond) — jamais pour écraser un choix déjà fait via le lien.

`applyOctaveIndex(newIndex)` change `octaveIndex`, relance `recomputeKeyRange()`, puis force
un rebuild complet du piano affiché (`keyboardBuilt = false` avant `renderKeyboard()`) — un
rebuild déclenché par une action utilisateur ponctuelle (flèches ◂/▸, `ArrowLeft`/`ArrowRight`,
`<`/`-` sur un clavier ISO, ou un clic/tap sur l'aperçu miniature — voir plus bas), jamais par
le sondage périodique (`refresh()`, ~200ms) — c'est cette distinction qui compte : un rebuild
déclenché par le sondage périodique pendant qu'un doigt est encore posé sur une touche est ce
qui a causé le bug de relâchement tactile décrit dans `ensureKeyboardBuilt`/
`wheelChordActiveCount` (`VirtualKeyboardAssets.swift`), pas le rebuild en lui-même.
`shiftOctave(delta)` (±1, depuis les flèches/raccourcis) et `jumpToNearestOctaveFor(pitch)`
(saut direct, depuis l'aperçu miniature — trouve le `OCTAVE_STOPS` dont le centre de fenêtre
est le plus proche) délèguent tous deux à `applyOctaveIndex`. `OCTAVE_SHORTCUT_DELTA` (objet
`code -> delta`, couvrant `IntlBackslash`/`Slash`/`ArrowLeft`/`ArrowRight`) et le raccourci
`Tab`/`Maj+Tab` du guide (voir plus bas) utilisent un `Set` de garde anti-répétition
**séparé** de `downCodes` (`downActionCodes`) — `downCodes` est vidé par
`clearAllLocalPressState()`, que `shiftOctave()`/`applyOctaveIndex()` appellent eux-mêmes à
chaque déclenchement ; le partager aurait fait perdre sa propre garde à chaque appel, laissant
une touche maintenue défiler plusieurs octaves (ou étapes de guide) d'un coup au lieu d'une
seule.

**Aperçu miniature** (`renderMiniPianoOverview()`) : un mini-piano complet Do-1..Do8
(`MINI_PIANO_MIN`/`MAX`), redessiné en SVG uniquement quand l'octave change (même déclencheur
que le piano réel, dans `ensureKeyboardBuilt()` — jamais à chaque sondage, pour la même raison
que ci-dessus), avec un rectangle (`.mini-piano-active`, contour seul, pas de remplissage)
entourant la tranche `[MIN_MIDI, MAX_MIDI]`, flanqué des étiquettes `octave-min-label`/
`octave-max-label` (la note la plus grave/aiguë jouable, une de chaque côté des flèches ◂/▸)
et centré dans sa colonne (`.octave-controls { justify-content: center }`) pour s'aligner
au-dessus du piano réel. `miniWhiteSlot()` réutilise le même correctif "octave absolue, pas
relative au début de la plage" que `ensureKeyboardBuilt()` (voir plus haut) mais n'en a en
pratique pas besoin aujourd'hui, `MINI_PIANO_MIN` étant déjà un Do. Cliquer/toucher l'aperçu
(`jumpOctaveFromMiniPianoClick`) convertit la position en pitch approximatif (`SEMITONE_BY_WHITE_SLOT`,
l'inverse de `WHITE_SLOT_BY_SEMITONE`) puis appelle `jumpToNearestOctaveFor` — un simple clic
fire-and-forget, pas un geste tenu, donc sans le même besoin de préserver l'identité du nœud
DOM entre deux sondages que les touches du piano ou de la roue.

**Mise en page à deux colonnes** (`.layout-columns`, même motif responsive que la console) :
colonne gauche = guide (si actif) + roue ; colonne droite, en vis-à-vis =
`#keyboard-align-wrapper` (aperçu/flèches d'octave, piano réel, portée, panneau accord/mode).
`ensureKeyboardBuilt()` calcule la largeur exacte du `.keyboard` à partir du slot de touche
blanche de `MIN_MIDI`/`MAX_MIDI` (`whiteSlotFor`, `leftWhiteSlotOffset`, décalant chaque touche
de `leftWhiteSlotOffset`) — la boîte du clavier correspond pile à ses propres touches visibles,
sans marge invisible d'un côté (l'ancienne approximation par nombre entier d'octaves en
laissait une dès que `MIN_MIDI` ne tombait pas sur un Do, ce qui est le cas courant — voir
`BASS_WHITE_OFFSETS`). Le piano réel reste enveloppé dans `.keyboard-scroll` (`overflow-x:
auto`) pour défiler dans sa colonne plutôt que déborder toute la page une fois celle-ci scindée
en deux.

**`#keyboard-align-wrapper` : `display: inline-flex` (pas `flex`), `align-items: stretch`** —
fait que l'aperçu d'octave, le piano, la portée et le panneau accord/mode partagent tous la
même largeur. `inline-flex` (pas juste `flex`) est le point qui compte : un conteneur flex
`display: flex` (bloc) remplit la largeur disponible de SON PARENT, qui peut être plus étroite
que le piano — **vrai bug trouvé ainsi, pas par relecture** : avec `flex` tout court, le piano
se retrouvait visuellement tronqué (dernières touches invisibles/coupées), parce que
`align-items: stretch` rétrécissait `#keyboard-container` à la largeur de la colonne (660px
dans un cas mesuré) au lieu de la largeur réelle du piano (792px) — confirmé en lisant
`getBoundingClientRect()` des deux dans une capture headless. `inline-flex` se comporte comme
`inline-block` : il se dimensionne d'abord sur son enfant le plus large, PUIS `align-items:
stretch` étire les autres sur cette même largeur — restaure la pleine largeur du piano (qui
peut toujours déborder sur un écran étroit/défiler via `.keyboard-scroll`, exactement comme
avant l'existence de cette fonctionnalité).

**Aperçu de clavier — alignement final, après plusieurs itérations guidées par une maquette
cible fournie par l'utilisateur** (`renderMiniPianoOverview()`) : une première version
l'affichait délibérément ~30% plus large que le piano (mauvaise lecture d'une demande
utilisateur — le "30% de plus" visait la taille de l'aperçu par rapport à SA PROPRE version
précédente, pas une différence voulue avec le piano). Une deuxième version a fait correspondre
la largeur du SVG lui-même à `keyboardPixelWidth`, avec tout centré (`justify-content: center`
sur `.octave-controls`/`.keyboard-scroll`). La maquette cible a montré autre chose : les
étiquettes min/max ("F5 ◂"/"▸ B7") doivent être **au ras des mêmes bords gauche/droite** que le
piano/la portée/le panneau texte — pas le SVG de l'aperçu tout seul, la RANGÉE ENTIÈRE
(étiquette + flèche + SVG + flèche + étiquette), avec les touches de l'aperçu lui-même en
retrait des deux bords (pas alignées sur les touches du piano). Implémentation finale :
- `.octave-controls`/`.keyboard-scroll` passés de `justify-content: center` à `flex-start` —
  tout au ras du même bord gauche, plus de centrage nulle part dans cette colonne.
- `renderMiniPianoOverview(svgTargetWidth)` prend désormais la largeur cible du SVG **lui-même**
  en paramètre (pas `keyboardPixelWidth` directement) — le viewBox reste à sa taille naturelle
  (calcul interne rects blancs/noirs/surbrillance inchangé), seuls les attributs `width`/
  `height` du `<svg>` changent (pur zoom d'affichage) ; `jumpOctaveFromMiniPianoClick` n'a
  besoin d'aucun changement, il convertit déjà via `getBoundingClientRect()` (taille RÉELLE),
  pas une supposition d'échelle 1:1.
- `ensureKeyboardBuilt()` calcule ce `svgTargetWidth` comme `keyboardPixelWidth` moins la
  largeur déjà prise par les étiquettes/flèches ("overhead"), pour que la RANGÉE TOTALE
  corresponde au piano, pas le SVG seul. **Piège réel trouvé en comparant le rendu à la
  maquette, pas par relecture** : une première mesure de cet "overhead" lisait
  `#octave-container.getBoundingClientRect().width` — mais cette boîte est déjà étirée à
  `keyboardPixelWidth` par le `align-items: stretch` du `#keyboard-align-wrapper` parent,
  donc ça mesurait ~792px de "overhead" sur un piano de 792px de large quel que soit le texte
  réel des étiquettes, écrasant l'aperçu à sa largeur plancher (`20`px, presque invisible dans
  la capture). Corrigé en sommant les largeurs INDIVIDUELLES des étiquettes/flèches (chaque
  enfant flex non-`mini-piano-container` se dimensionne sur son propre contenu le long de
  l'axe principal, indépendamment de la largeur étirée de la rangée qui les contient) plus les
  `gap` entre eux, mesurés avec `#mini-piano-container` encore vide (texte des étiquettes déjà
  posé, SVG pas encore inséré).

**Flèches `◂`/`▸` recentrées verticalement** (`.octave-arrow`) : `align-items: center` sur
`.octave-controls` centre correctement la BOÎTE de chaque flèche par rapport au SVG voisin
(confirmé par `getBoundingClientRect()` — même centre vertical à 0.01px près) — mais l'ENCRE
visible du glyphe `◂`/`▸` lui-même ne remplit pas symétriquement sa propre boîte de caractère
(vérifié en l'isolant seul contre une ligne de repère à mi-hauteur dans une capture headless) :
elle est décalée vers le haut, avec plus de vide en dessous qu'au-dessus — un décalage de police,
pas un bug de mise en page. D'où le signalement "pas bien centré" malgré un alignement CSS
techniquement correct. Corrigé par un simple `position: relative; top: 0.12em` sur `.octave-arrow`
pour compenser ce décalage propre au glyphe, retrouvé par la même méthode que les ajustements de
clé de portée (rendu du caractère seul contre une grille/ligne de repère, pas une supposition).

**Taille adaptative — tenir sur un MacBook 13"/iPad 11", grandir sur un plus grand écran**
(`applyResponsiveScale()`) : toute la mise en page à deux colonnes (`#layout-columns`) est mise
à l'échelle comme un seul bloc via un `transform: scale(...)` CSS calculé à partir de la largeur
de fenêtre réellement disponible, recalculé au chargement et sur `resize` — remplace l'ancien
repli `flex-wrap: wrap` (repasser en une colonne), explicitement écarté par l'utilisateur pour
cette passe ("on fera un design iPhone plus tard").
- **`.layout-columns` passe de `display: flex` à `inline-flex`, et `.layout-col-left`/
  `.layout-col-right` de `flex: 1 1 380px` à `flex: 0 0 auto`** — même leçon "inline-flex vs
  flex" que `#keyboard-align-wrapper` plus haut, retrouvée en construisant CETTE fonctionnalité :
  une première version forçait `#layout-columns` à une largeur totale ESTIMÉE (`WHEEL_MAX_WIDTH_PX
  + LAYOUT_GAP_PX + keyboardPixelWidth`) pour en déduire le facteur d'échelle — mais avec les
  deux colonnes en `flex-grow: 1`, forcer une largeur totale approximative faisait répartir tout
  écart 50/50 entre les deux colonnes SANS RAPPORT avec ce dont chacune avait réellement besoin,
  confirmé en lisant `getBoundingClientRect()` : `#keyboard-align-wrapper` se retrouvait plus
  large que sa propre colonne parente, débordant sans être contenu. Avec les deux colonnes
  fixées à leur taille de contenu (plus de "grandir"), plus rien à estimer par formule.
- **Largeur naturelle mesurée dans le DOM, pas calculée par formule** — mais pas en mesurant
  `#layout-columns` lui-même : `.wheel` est `width: 100%; max-width: 624px`, et ce `100%` se
  résout par rapport à l'espace que la fenêtre ACTUELLE laisse à `.layout-col-left` — un vrai
  piège trouvé en mesurant, pas en relisant le code : remettre le `transform` à `none` puis
  relire `getBoundingClientRect().width` donnait systématiquement un nombre suspicieusement
  proche de la largeur de fenêtre ACTUELLE à chaque taille essayée, au lieu d'un nombre fixe
  indépendant du viewport — parce que le `100%` de la roue s'était déjà adapté à la largeur de
  page du moment, donc "annuler le transform" n'annulait jamais vraiment l'influence du
  viewport sur la mesure. Solution : mesurer directement `#keyboard-align-wrapper` (aucun `%`
  dans tout ce sous-arbre, seulement du pixel fixe ou du contenu) et utiliser la constante
  `WHEEL_MAX_WIDTH_PX` (624, la taille que la roue prendra une fois ce bloc mis à l'échelle,
  puisque le transform s'applique uniformément à tout le sous-arbre) pour la contribution de la
  roue plutôt que de la mesurer.
- **`RESPONSIVE_MIN_SCALE`/`RESPONSIVE_MAX_SCALE`** (0.5/1.6) bornent le facteur, `BODY_MAX_WIDTH_PX`/
  `BODY_HORIZONTAL_PADDING_PX` (1600/48) reproduisent les contraintes déjà posées par le CSS de
  `body` pour calculer la largeur réellement disponible. `#responsive-scale-clip` (nouveau
  wrapper autour de `#layout-columns`, `overflow: hidden`) reçoit une `height` explicite
  (hauteur naturelle × échelle) — un `transform` ne modifie pas le flux de mise en page normal,
  donc sans ça un bloc rétréci laisserait un vide de sa hauteur non réduite en dessous (ou un
  bloc agrandi déborderait sur ce qui suit).
- **Vérifié** via des captures Chrome headless à plusieurs largeurs de fenêtre représentatives
  (MacBook 13" ≈1280px, iPad 11" paysage ≈1194px, un grand écran 1920px, et un iPad 11"
  portrait ≈834px comme cas dégradé non ciblé) avec un mock de roue réaliste (12 colonnes, pas
  juste `wheel: null`, pour éviter de sous-estimer la largeur naturelle) — piano et roue
  entièrement visibles sans défilement horizontal aux deux premières tailles, agrandissement
  visible au-delà, réduction sans casse (juste petit) au cas dégradé.

**Roue toujours affichée, avec ou sans guide** : `ImprovSession.handleVirtualKeyboardRequest`
calcule désormais `wheel` à chaque `/state` sans condition (avant : seulement si un guide
tournait) — `buildWebConsoleWheelState` a déjà son propre repli (guide, puis morceau en
lecture, puis piste en écoute, puis Do ionien) qui garantit toujours un résultat. Côté client,
`renderWheel(wheel, showModeContext, detectedChord)` — `showModeContext = guideIsActive` —
n'omet QUE les parties relatives à une tonalité de référence (noms de mode, chiffres romains,
contour diatonique) quand aucun guide ne tourne ; la grille d'accords elle-même (forme/
couleur/nom, et le clic pour jouer) reste toujours affichée et cliquable — décision prise avec
l'utilisateur : plutôt qu'un sélecteur local de tonique/mode (option écartée), la roue hors
guide reste volontairement "nue". `detectedChord` (indépendant de `showModeContext` — savoir
QUEL accord tu joues n'est relatif à aucune tonalité de référence) entoure d'un anneau
(`.wheel-cell-detected`, même magenta que `.pkey.root`) la case dont `pitchClass`/`quality`
correspondent au `chordRoot`/`chordTones` actuels de CETTE piste — `detectedChordFrom(track)`
déduit la qualité (majeur/mineur/diminué) des intervalles présents par rapport à la
fondamentale, entièrement côté client, sans nouveau champ serveur (le calcul équivalent existe
déjà côté serveur pour peupler `trackLabels`, mais celui-ci liste TOUTES les pistes en écoute
correspondantes, pas seulement la piste de ce client — pas ce qu'on veut ici).

**Navigation du guide** (`Tab`/`Maj+Tab`, uniquement si un guide tourne) : `sendGuideAdvance(delta)`
appelle `GET /guide-advance?delta=±1` — une nouvelle route dans
`ImprovSession.handleVirtualKeyboardRequest`, qui appelle directement `advanceGuideStep(by:)`
(la même méthode que les flèches gauche/droite de l'écran `.guide` du terminal). Action
**globale** (pas scopée à `track`/`clientID`, même si `?client=...` reste exigé par
convention comme sur chaque route) : n'importe quel client qui appuie sur Tab avance LE MÊME
guide pour tout le monde qui regarde.

### Palettes de couleur (`AppCore/ColorPalette.swift`)

`ColorPalette` (`name` + 12 couleurs hex `colors` + 12 couleurs de texte `textColors`, même
indexation, 0 = C ... 11 = B) et `ColorPaletteFile` (`{"palettes": [...]}`, la forme sur
disque de `palettes.json`) — un seul fichier listant plusieurs palettes, pas un fichier par
palette (à la différence de `Scene`/`GuideSequence`) : il n'y en a jamais qu'une poignée, et
en choisir une est un choix ponctuel, pas un document qu'on éditerait en continu depuis l'app.
`ColorPalette.builtInDefaults` (3 palettes : Default — couleurs échantillonnées à la main
depuis `Sources/Colors/Colors.PNG`, la roue physique photographiée, projet racine ; couleurs
de texte choisies à la main par l'utilisateur (blanc partout sauf La/Mi/Si, en noir) —
Contraste, Pastel, couleurs de texte calculées/choisies) est écrit dans `palettes.json` la
première fois qu'il n'existe pas encore (`ImprovSession.loadOrCreateColorPalettes`), puis
chargé normalement.

`textColors` existe pour la lisibilité : un fond clair a besoin d'un texte sombre et
inversement, et ce n'est délibérément **pas** une formule pure — `Default` a ses 3
exceptions (La/Mi/Si) choisies à l'œil par l'utilisateur, pas dérivées d'un calcul de
luminosité (voir le commentaire de `ColorPalette.textColors`). `textColors` est
`decodeIfPresent` dans `init(from:)` : une palette ajoutée à la main dans `palettes.json`
sans ce champ (ou un `palettes.json` antérieur à son introduction) retombe sur
`ColorPalette.legibleTextColors(for:)` — seuil de luminosité perçue (formule YIQ) — plutôt que
d'échouer au chargement.

`ImprovSession.activeColorPaletteIndex` est **volontairement jamais persisté** : seules les
palettes *disponibles* vivent dans `palettes.json`, pas celle *active* — chaque relance
repart sur la première du fichier. `activeColorPalette.colors`/`.textColors` sont envoyés
dans `WebConsoleState.palette`/`.paletteTextColors` et `VirtualKeyboardStateResponse.palette`/
`.paletteTextColors` à chaque `GET /state`, donc un changement de palette (`use-palette`/menu
JamShack) se répercute dans n'importe quel onglet déjà ouvert au prochain sondage (~150-250ms),
sans recharger la page — `app.js`/`vk.js` réaffectent leurs `PITCH_CLASS_COLORS`/
`PITCH_CLASS_TEXT_COLORS` (passés de `const` à `let` pour l'occasion) depuis `state.palette`/
`state.paletteTextColors` à chaque `refresh()`, au lieu de les garder figés au chargement.

Une seule classe, `@Observable`, `@unchecked Sendable`, qui détient tout l'état de
l'application et toute la logique — indépendante de toute présentation. Le CLI ne fait que
l'appeler et lire son état ; une future interface SwiftUI pourrait s'y brancher directement.

### Dossiers de travail : Settings / User / Library

Trois racines, à côté de `MusicTheoryKit/`, chacune couvrant un seul type de contenu :
`Settings/` (réglages **de l'installation**, pas d'une pièce donnée — `palettes.json`,
`chordprogressions.json`, `LLMConnections/`), `User/` (matière musicale de l'utilisateur —
`Pieces/`, `Scenes/`, `Sequences/` (guides), `SoundTracks/`, `Composition IA/`), `Library/`
(ressources réutilisables indépendantes de toute pièce — `SoundFonts/`).

`ImprovSession.setSettingsFolder(_:)` (mêmes gabarits que `setPromptsFolder` — un seul dossier
choisi, plusieurs sous-chemins fixes créés dessous si absents) est le seul point d'entrée pour
`Settings/` : elle charge `palettes.json` (`loadOrCreateColorPalettes`), `chordprogressions.json`
(`loadOrCreateChordProgressionTemplates`) et liste `LLMConnections/` (`listLLMConnections`) en
un seul appel — il n'existe plus de commande/menu pour rediriger `LLMConnections` seul. Les
dossiers de `User/`/`Library/` restent chacun redirectable indépendamment, exactement comme
avant (`listPieceFiles`, `listSampleFiles`, `listSoundTrackFiles`, `listGuideFiles`,
`listSceneFiles`, `setPromptsFolder`) — seule leur valeur par défaut au démarrage
(`Sources/JamShack/main.swift`) a changé de chemin.

### Progressions d'accords (`MusicTheoryKit/RomanNumeralChord.swift`, `AppCore/ChordProgressionTemplate.swift`)

`RomanNumeralChord.parse(_:)` (MusicTheoryKit, théorie pure, aucune dépendance à `PieceModel`)
transforme un token en chiffre romain ("I", "vi", "vii°") en `(degree: Int, quality:
ChordQuality)` — **la casse du texte EST la qualité, prise littéralement** (majuscule =
majeur, minuscule = mineur, "°" final = diminué), jamais dérivée de l'harmonie propre du mode
appliqué : "I-IV-V" désigne toujours trois triades majeures, quel que soit le mode/tonique sur
lequel on l'applique — comme dans un livre de blues/jazz. `RomanNumeralChord.rootAndQuality(for:in:)`
résout un token contre un `Mode` réel via `Mode.degree(_:)` (1-based, déjà existant).

`ChordProgressionTemplate` (AppCore, `name` + `degrees: [String]`) suit la même convention
« fichier plat, plusieurs templates, pas un fichier par template » que `ColorPalette` (pas
celle de `Scene`/`GuideSequence`) — `ChordProgressionTemplateFile` sur disque dans
`chordprogressions.json`, sous `Settings/`. `ChordProgressionTemplate.builtInDefaults` (blues
12 mesures, ii-V-I, pop I-V-vi-IV, cadence andalouse…) est écrit au premier lancement s'il
n'existe pas encore, comme `ColorPalette.builtInDefaults`. `ImprovSession.resolveChordProgression(_:in:)`
convertit chaque degré en `ChordReference` (root + `chordTemplateID` "Ma"/"mi"/"dim") — cette
conversion vit dans `AppCore`, pas `MusicTheoryKit`, puisque `ChordReference` appartient à
`PieceModel` : `MusicTheoryKit` reste sans dépendance montante.

`PieceModel.GuideStep` (remplace l'ancien `steps: [ModeReference]` de `GuideSequence` par
`steps: [GuideStep]`) associe un `mode: ModeReference` à une progression optionnelle
(`chordProgressionName: String?` + `chordProgression: [ChordReference]?`, déjà résolue au
moment de l'ajout, jamais recalculée au chargement — le nom du template reste pour affichage
même si la bibliothèque change ensuite). `GuideStep.init(from:)` accepte aussi l'ancien format
(l'objet JSON entier EST un `ModeReference` nu, sans clé `"mode"`) — même convention
`decodeIfPresent` + repli que `ColorPalette.textColors` — pour que tout guide sauvegardé avant
cette fonctionnalité continue de se charger. `ImprovSession.addGuideStep(_:chordProgression:)`
est le nouveau point d'entrée (l'ancien `addGuideStep(_:)` reste une façade qui l'appelle avec
`nil`).

### Plan de scène (arbre app/instruments/clients)

`ImprovSession.connectedClients()` expose `clientIDToClientName` (jusque-là privé) — chaque
participant connecté en mode serveur, même sans instrument encore annoncé (contrairement à un
simple filtrage de `tracks` sur `.remote`, qui ne montre que les participants ayant déjà
annoncé au moins une piste). Ce détour a révélé un bug latent dans `refreshTracks()` : elle
reconstruit `tracks` à chaque appel et ne préservait explicitement que les pistes
`.webKeyboard` à travers cette reconstruction — les pistes `.remote` (appartenant à la couche
réseau, jamais recréées ici) étaient silencieusement perdues à chaque appel (`tracks`,
`scene-tree`, `midi-mode`…) jusqu'à ce que leur propriétaire rejoue une note ou réannonce sa
piste. Corrigé en étendant le filtre de préservation à `.webKeyboard` **et** `.remote`.

Deux rendus de la même donnée : `Sources/JamShack/main.swift`'s `printSceneTree()` (ASCII,
`printTreeLine` — box-drawing `├─`/`└─`/`│` maison, aucun helper de ce genre n'existait avant)
pour le terminal (`scene-tree`), et `AppCore.WebConsoleSceneState`/`WebConsoleSceneClientState`
(`ImprovSession.buildWebConsoleSceneState()`, un champ `scene` de plus dans `WebConsoleState`,
toujours présent comme `wheel`/`palette`) pour la console web — un nouvel onglet `Scene` à
côté de `Run` (`activeTab`/`renderTabBar()`/`setTab()` en JS, `renderSceneTree()` en HTML
imbriqué plutôt qu'en box-drawing, plus naturel dans un navigateur). `WebConsoleTrackState` a
gagné `isListening`/`canHaveSound`/`soundEnabled`/`instrumentName` pour cet usage — inutiles
pour l'onglet `Run` (qui ne reçoit déjà que des pistes en écoute), nécessaires pour l'arbre de
scène, qui liste toute piste qu'elle écoute ou non.

**Troisième onglet `Infos`** (console web) : texte statique (le titre de page, déplacé hors du
`<body>` fixe dans cet onglet — plus affiché en permanence au-dessus de `Run`/`Scene`), `ternaire
à 3 branches` dans `refresh()`. La ligne "Dernier evt" (dernier événement MIDI brut) a été
retirée de l'onglet `Run` — jugée peu utile face à la portée musicale, qui montre déjà
l'historique des notes/accords joués. `renderTrack`/`sceneTrackLineHTML` n'affichent plus
`[track.id]` en préfixe du libellé — pour une piste `clavier-web:<uuid>` ça exposait l'uuid
brut du client sans utilité pour une page en lecture seule (rien à taper) ; le libellé seul
(déjà l'alias choisi pour une piste clavier virtuel) suffit.

**Clavier virtuel — deux onglets `Clavier`/`Infos`** (même mécanisme que la console web, état
`activeVKTab`/`setVKTab()`, mais bascule juste le `display` de deux conteneurs déjà construits
au lieu de reconstruire le HTML — cette page met déjà à jour ses sous-conteneurs en place à
chaque sondage plutôt que de reconstruire une grande chaîne HTML, voir plus haut) : `Infos`
récupère la ligne identité/réglages et le texte d'aide, libérant de la place dans `Clavier`.

**Menu terminal, catégorie Scene** (`Sources/JamShack/main.swift`) : `MenuItem.header("Scene")`
juste avant "Sauvegarder scene.../Charger scene..." dupliquait le nom de la catégorie
elle-même (déjà affiché en vidéo inverse juste au-dessus une fois le menu ouvert) — repérable
comme "un sous-menu qui a l'air désactivé" (un second "Scene" en grisé, sans lien apparent avec
le premier). Renommé en "Fichier de scene", et le séparateur juste avant supprimé (il faisait
double emploi avec l'en-tête lui-même).

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
  - **Le prompt de composition est toujours recomposé à partir de trois éléments gérés
    séparément — jamais chargé/remplacé comme un tout** (voir §LLMEngine pour le principe) :
    `currentTextCompositionPrompt()`/`currentSoundTrackCompositionPrompt()` appellent
    systématiquement `LLMPieceComposer.buildPrompt(...)` avec la phrase de cadrage active
    (`current[Text|SoundTrack]FramingSentence()`) et les indications actives
    (`additionalCompositionInstructions` / `activeSoundTrackCompositionInstructions`) —
    aucun court-circuit par un « prompt complet chargé » (mécanisme retiré, voir plus bas).
    `composeFromText`/`composeSoundTrackToPieces` passent par ces deux méthodes plutôt que
    d'appeler `buildPrompt` directement — un seul point de résolution.
  - `setPromptsFolder(_:)` crée (si absents) et pointe **cinq** sous-dossiers fixes sous une
    racine unique (auto-écoutée au démarrage comme `Pieces`/`SoundFonts`/`SoundTracks`, voir
    plus bas — le dossier racine s'appelle `Composition IA` par défaut, choisi par
    l'utilisateur, aucun renommage des identifiants Swift internes) :
    - `Cadrage Composition Descriptive`/`Cadrage Composition Soundtrack` — phrases de
      cadrage (voir ci-dessous).
    - `composition Descriptive` — descriptions complètes (titre+texte+indications, texte
      uniquement) ; peuplé en appelant `listCompositionFiles(in:)` (méthode déjà existante,
      inchangée) sur ce sous-dossier — `compositionFolder` n'est plus réglable
      indépendamment, toujours dérivé de `promptsFolder`.
    - `Indications Soundtracks` — indications de style sauvegardées (soundtrack, voir
      plus bas).
    - `Export` — prompts complets exportés (texte et soundtrack mélangés), jamais relus par
      l'application.
  - **Phrase de cadrage — override étroit, sans risque pour le schéma** :
    `activeTextFramingSentence`/`activeSoundTrackFramingSentence` (`nil` = valeur par défaut,
    même convention que `additionalCompositionInstructions`).
    `current[Text|SoundTrack]FramingSentence() -> String` ne lève jamais — il y a toujours une
    valeur, l'override ou la constante par défaut de `LLMPieceComposer`.
    `set[Text|SoundTrack]FramingSentence(_:)` fixe un nouvel override en mémoire (vide efface,
    retour au défaut) ; `save[Text|SoundTrack]FramingSentence(as:)`/
    `use[Text|SoundTrack]FramingSentence(named:/atIndex:)`/`reset[Text|SoundTrack]FramingSentence()`
    persistent/rechargent/effacent, sur les sous-dossiers `Cadrage...`.
  - **Indications de style pour la soundtrack — nouveau, mêmes conventions que la phrase de
    cadrage** : `activeSoundTrackCompositionInstructions: String?` (`nil` = aucune — pas de
    valeur par défaut à substituer, contrairement à la phrase de cadrage),
    `soundTrackInstructionsFiles: [String]`. `currentSoundTrackCompositionInstructions()`/
    `setSoundTrackCompositionInstructions(_:)` (vide efface) ;
    `saveSoundTrackCompositionInstructions(as:)` lève `noSoundTrackCompositionInstructions`
    si rien n'est actif (rien de sensé à sauvegarder, contrairement à la phrase de cadrage qui
    a toujours une valeur par défaut) ; `use/resetSoundTrackCompositionInstructions` complètent
    le quatuor. Ajouté parce que la composition depuis une soundtrack n'avait jusqu'ici aucune
    notion d'indications de style (contrairement au texte, qui les bundle dans sa description
    — voir plus bas) ; une soundtrack n'a pas d'équivalent "description" où les loger, donc
    son propre emplacement dédié.
  - **Prompt complet — consultable et exportable, jamais rechargeable** :
    `exportTextCompositionPrompt(as:)`/`exportSoundTrackCompositionPrompt(as:)` écrivent
    `currentTextCompositionPrompt()`/`currentSoundTrackCompositionPrompt()` dans `Export/` —
    aucun effet sur une composition future, contrairement à l'ancien mécanisme
    `save/use/resetTextCompositionPrompt` (retiré entièrement, avec `activeTextCompositionPrompt`/
    `activeSoundTrackCompositionPrompt`/`textPromptFiles`/`soundTrackPromptFiles`) : ce
    mécanisme permettait de recharger un prompt complet comme override, avec le risque réel
    d'y perdre le schéma JSON en l'éditant à la main — remplacé par les deux leviers plus
    étroits ci-dessus (phrase de cadrage, indications), qui ne peuvent structurellement pas
    casser le schéma puisqu'ils ne le touchent jamais.
  - **Descriptions de composition — sauvegarder/recharger titre+texte+indications (texte
    uniquement)** : struct `CompositionDescription` (`title: String?`, `sourceText: String`,
    `additionalInstructions: String?`, fichier dédié `AppCore/CompositionDescription.swift`)
    et `compositionFolder`/`compositionFiles`/`currentCompositionFilePath` — mêmes
    conventions que `pieceFolder`/`pieceFiles`/`currentPieceFilePath` (voir plus bas),
    appliquées à cette struct plutôt qu'à un `Piece`, mais dérivées de `setPromptsFolder`
    plutôt que réglables indépendamment (voir plus haut — remplace l'ancien dossier racine
    séparé `Composition/` d'une itération précédente).
    `listCompositionFiles(in:)`/`loadCompositionDescription(fromJSONFile:/named:/atIndex:)`/
    `saveCompositionDescription(toJSONFile:/as:/())` sont les miroirs exacts de
    `listPieceFiles`/`loadPiece(...)`/`savePiece(...)`, à une différence près :
    `saveCompositionDescription(toJSONFile:)` **met à jour `compositionFiles`** après une
    sauvegarde réussie dans le dossier déjà listé (contrairement à `savePiece`, qui ne le
    fait pas pour `pieceFiles`) — une description est pensée pour être re-choisie tout de
    suite après l'avoir sauvegardée, contrairement à un `Piece` qu'on re-liste rarement dans
    la même session. `loadCompositionDescription` applique le contenu chargé via les mêmes
    setters que l'assistant "Decrire le morceau..." (`setCompositionTitle`/`setSourceText`/
    `setAdditionalCompositionInstructions`) — se comporte donc exactement comme si on l'avait
    retapé à la main.
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
  - **Pseudo (`localClientName`/`pseudo <nom>`) et `TrackInfo.ownerName`** : avant ce champ,
    une piste distante n'affichait que `remote:<uuid>@<piste>` — illisible pour savoir qui
    joue quoi. `clientIDToClientName: [String: String]` (serveur uniquement, alimenté par le
    `clientName` du `hello` de chaque client) permet à `addOrUpdateRemoteTrack` de renseigner
    `TrackInfo.ownerName` dès l'arrivée d'un `trackAnnounce`/`noteEvent` — donc déjà visible
    localement sur le serveur, pas seulement une fois diffusé. `broadcastSyncSoon()` résout le
    nom du propriétaire de **chaque** piste diffusée (`track.ownerName` pour une piste
    `.remote`, `localClientName` pour une piste locale au serveur lui-même) dans
    `RemoteTrackSnapshot.clientName` ; `mergeRemoteSnapshot` le recopie tel quel dans
    `ownerName` côté client — même principe « le serveur résout une fois, chaque client
    réaffiche » que `remoteChordDisplay` juste au-dessus. `ownerName` reste `nil` pour toute
    piste locale (jamais besoin de s'étiqueter soi-même). Nettoyé dans `stopServer()`/
    `handleClientDisconnected` en même temps que `connectionIDToClientID`.
- **Console web (`startWebConsole`/`stopWebConsole`)** : un miroir en lecture seule de l'écran
  `run`, servi dans un navigateur via `WebConsole` (§WebConsole) — indépendant de
  `networkRole`/de la session collaborative ci-dessus (les deux peuvent tourner en même
  temps). `startWebConsole(port:)` démarre un `HTTPServer` puis une minuterie 150ms
  (`startWebConsoleRefreshTimer`, même cadence que `startSyncBroadcastTimer`) qui recalcule
  `buildWebConsoleState()` et encode le résultat en JSON dans `webConsoleStateCache` — chaque
  `GET /state` ne fait que relire ce cache (`webConsoleStateQueue.sync`), jamais recalculer à
  la demande, pour que le coût reste constant quel que soit le nombre de clients/la fréquence
  de sondage de chacun. `buildWebConsoleState()` transpose la même donnée que
  `renderConsoleFrame(mode: .run)` (`JamShack/main.swift`) — pistes en écoute, lecture d'un
  `Piece`/d'une `SoundTrack` — en valeurs déjà résolues (classes de hauteur 0…11 pour
  l'accord/le mode, libellés déjà formatés via `Self.describe`) plutôt qu'en `RecognizedChord`/
  `RecognizedMode` bruts, pour que `app.js` n'ait plus qu'à peindre, jamais à ré-interpréter de
  la théorie musicale côté navigateur.

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

## JamShack — l'interface en ligne de commande

Trois modes d'affichage coexistent, tous alimentés par le même `ImprovSession` :
- **Command** — REPL classique (le prompt `>`), commandes tapées au clavier, mode par défaut.
- **`run`** — écran figé redessiné en direct, focalisé sur l'activité musicale en cours.
- **`config`** — écran figé redessiné en direct, focalisé sur l'état de la session et le
  détail du morceau actif.

### Fichiers

- **`main.swift`** : boucle REPL + `executeCommand(_:_:)` (aiguillage unique de commandes,
  partagé par le REPL et les actions de menu) + `renderConsoleFrame(mode:)`/
  `runConsoleScreen(mode:)` — un seul mécanisme de redessin-en-place partagé par les deux
  écrans figés (`ConsoleScreenMode.run`/`.config`), deux contenus distincts. `tokenizeCommandLine(_:)`
  découpe une ligne tapée en tokens, avec support des spans `"..."` pour les noms de fichiers
  contenant des espaces (ex. `use-sample "The Fox and The Crow General MIDI SoundFont Ultimate.sf2"`).
- **`Menu.swift`** : mode brut du terminal (`termios`), lecture touche par touche
  (`readKey() -> Key?`), système de menus déroulants façon DOS (mnémoniques soulignés,
  navigation aux flèches, Échap pour ouvrir/fermer sans passer par une lettre).
  `stdinHasByteAvailable()` (privé) utilise `poll(2)` avec un délai nul pour lire sans
  bloquer, sans jamais toucher aux drapeaux du descripteur — voir "Concurrence et E/S
  terminal" ci-dessous pour pourquoi c'est important. `MenuItem.separator`/
  `MenuItem.header(_:)` : deux façons de grouper des items apparentés dans un menu déroulant
  plat (ce système n'a pas de sous-menus imbriqués) — un simple trait, ou un titre estompé
  non sélectionnable ; les deux partagent le même flag `isSeparator`, sauté par la navigation
  aux flèches (`handleMenuKey`) pour ne jamais s'arrêter sur une ligne non actionnable (et ne
  jamais planter sur un menu réduit à 0 item sélectionnable).
- **`Keyboard.swift`** : rendu ASCII d'un clavier de piano (1 caractère/demi-ton) — touches
  blanches sur 3 lignes, noires sur 2 (`blackZoneRows: 2, whiteZoneRows: 1`), largeur bornée à
  ~70 colonnes pour ne jamais flirter avec la largeur du terminal (cause racine d'un ancien
  bug de scintillement, voir plus bas).
- **`TextStyle.swift`** : mise en forme ANSI cohérente (libellé en gras/couleur, valeur en
  clair) pour lire un écran d'un coup d'œil.

### Écrans `run`/`config`

`runConsoleScreen(mode:)` garde `mode` comme variable locale mutable :
- **Tab** bascule `.run` ↔ `.config` directement dans la boucle, sans repasser par Command, et
  sans toucher à un menu ouvert (même système de menus dans les deux écrans, seul le contenu
  en dessous change).
- **q** (`case .char("q") where !computerKeyboardSourceActive`) quitte l'écran, retour à
  Command — même chemin de sortie que Ctrl+C (`consoleShouldStop = true`), une alternative
  volontairement "moins violente". Ctrl+C reste fonctionnel en secours, notamment le seul
  moyen de sortir pendant que la piste clavier intercepte toutes les lettres pour jouer des
  notes (`q` s'efface alors vers la note comme n'importe quelle autre lettre).
- L'astuce clavier (`"(lettre: ouvre un menu, fleches, Entree, Echap, Tab: change d'ecran, q:
  quitte l'ecran)"`) s'affiche sous la barre de menu, seulement quand aucun menu n'est ouvert
  (remplacée par le contenu du dropdown sinon).

`renderConsoleFrame(mode:)` accumule toute la frame (curseur-home, chaque ligne, `\x1B[J`
final) dans une seule `String`, puis fait un seul `print` à la fin — un unique appel par
frame, jamais un par ligne (voir "Concurrence et E/S terminal" pour ce qui a réellement causé
le scintillement observé avant ce point).

### Menus

Barre de menu façon interface DOS graphique, sept catégories (`menuCategories`, `main.swift`) :

| Menu (mnémonique) | Contenu |
|---|---|
| **JamShack (S)** | Menu principal, ouvert par défaut. Groupes séparés par des traits : infos/aide ; choisir chacun des dossiers (morceaux/sons/soundtracks/**guides musicaux**/**scènes**/**composition IA**/**réglages** — ce dernier remplace l'ancien choix indépendant de dossier de connexions LLM, toujours dans `Settings/` désormais) ; choisir une connexion LLM (isolée dans son propre groupe) ; choisir la palette de couleur (`ColorPalette`, voir plus bas) ; mode MIDI fusionné/individuel ; démarrer/arrêter la console web et le clavier virtuel (§WebConsole) ; quitter. Point d'entrée unique pour toute la configuration de session — aucun autre menu ne propose de choisir un dossier ou une connexion. |
| **Scene (n)** | Lister/activer/arrêter les pistes d'entrée, *séparateur*, activer/désactiver leur son, *séparateur*, choisir un son, *séparateur*, sauvegarder/charger une scène (configuration d'instruments : actif, son actif, quel son). Les actions qui demandent une piste et la sélection d'instrument dans "Choisir un son..." présentent `session.tracks` numérotée (`printNumberedTracks()`) — le choix accepte un numéro ou l'id littéral (`resolvedTrackIDText(_:)`, même convention que `resolvedSampleName`). |
| **Guide Musicaux (G)** | Voir l'écran Guide Musical, *séparateur*, créer un nouveau guide musical (boucle "ajouter un mode" jusqu'à tonique vide) / ajouter un mode au guide musical en cours — chaque ajout présente `printNumberedScales()`, les 33 entrées de `ScaleLibrary.all` (déjà en ordre famille→degré, voir §MusicTheoryKit) groupées sous un en-tête par famille, chaque ligne montrant `popularName` **et** `systematicName` (ex. `"altered (Altered / Super Locrian / Ionian #1)"`) — les deux appellations du PDF source, pas seulement le nom usuel —, `resolvedScaleID(_:)` résolvant un numéro contre cette même liste à plat (numéro ou id littéral, même convention que `resolvedTrackIDText`) — corrigé le 2026-07-11, ne listait auparavant que la famille 1 (7 modes majeurs) alors que `guide-add-mode`/`ScaleLibrary.byID` acceptaient déjà n'importe laquelle des 33 —, puis une progression d'accords optionnelle prise dans `chordprogressions.json` (voir §Progressions d'accords), *séparateur*, charger/sauvegarder(-sous) un guide musical, *séparateur*, démarrer/arrêter le guide musical (aussi accessible par la barre d'espace sur l'écran Guide Musical). |
| **Enregistrement (E)** | Démarrer/arrêter/voir/jouer un enregistrement, *séparateur*, charger/sauvegarder, *séparateur*, composer un morceau à partir de l'enregistrement, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser la phrase de cadrage, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser les indications de style, *séparateur*, voir/exporter le prompt de composition. Ordre — cadrage puis indications avant le prompt — délibéré (voir §LLMEngine/§AppCore). |
| **Morceaux (M)** | 4 groupes : écouter/voir le morceau ; choisir le son de lecture, d'une piste, ou des accords d'une section (`pieceDetailLines()` numérote visuellement chaque section — `"Section 1: A"` — et chaque piste — `"piste 1 '...'"` — pour que l'utilisateur sache directement quel numéro saisir) ; charger la démo/un morceau, sauvegarder ; `MenuItem.header("Assistant IA")` — sous-section réservée, sans item pour l'instant, en attente d'une future fonction de modification par dialogue applicable à n'importe quel morceau. |
| **Composition (C)** | Décrire le morceau (assistant titre → description → indications → composition), composer à partir de la description, voir la description, *séparateur*, charger/sauvegarder(-sous) une description, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser la phrase de cadrage, *séparateur*, voir/exporter le prompt de composition. |
| **Jam Session (J)** | Démarrer/arrêter une jam session, rejoindre, trouver (découverte), quitter — session collaborative. Les trois premiers items appellent `promptForPseudo()` avant de continuer. |

Convention des mnémoniques : pas toujours la première lettre du titre (`JamShack`→`S` pour ne
pas entrer en collision avec `Jam Session`→`J`, `Scene`→`n` pour ne pas entrer en collision
avec `JamShack`→`S`...) — choisies pour éviter toute collision entre menus (voir le commentaire
de `renderMenuBar`).

Instrument par piste/accord depuis le menu **Morceaux** : "Choisir le son d'une piste..."/
"Choisir le son des accords d'une section..." affichent `show-piece`, demandent un numéro de
section (et de piste pour le premier), listent `session.sampleFiles`, puis appellent
`set-track-instrument`/`set-chord-instrument` — mêmes commandes que celles tapables
directement en mode Command.

### Concurrence et E/S terminal — leçon retenue

`readKey()` lit stdin sans bloquer via `poll(2)` (`stdinHasByteAvailable()`), jamais via
`O_NONBLOCK` sur le descripteur. Raison, trouvée en corrigeant un vrai bug de scintillement/
plantage : sous l'attachement standard d'un terminal (`login_tty(3)`), stdin/stdout/stderr
partagent la **même** description de fichier ouverte — rendre stdin non bloquant rendait donc
silencieusement stdout non bloquant aussi, et une écriture qui tombait sur un tampon pty plein
renvoyait EAGAIN (données perdues en silence avec `print`, exception fatale avec
`FileHandle.write`). Corrigé à la racine (fonction `setStdinNonBlocking` supprimée
entièrement) plutôt qu'en changeant le nombre de `print`/le mode de bufferisation de stdout
(deux pistes explorées d'abord, ni l'une ni l'autre n'étaient la vraie cause). Voir la mémoire
`feedback-debug-verify-dont-theorize` pour la méthodologie de diagnostic qui a permis de le
retrouver (reproduire le crash avant de théoriser, ne pas empiler des correctifs non vérifiés).

Autres commandes CLI : réseau (`server`/`stop-server`/`client`/`discover`/`disconnect`, menu
Jam Session), pseudo (`pseudo [nom]` — affiche/change `localClientName`, voir §AppCore pour
`ownerName`), console web (`web-console [port]`/`web-console stop`, menu JamShack — voir
§WebConsole), composition (`title`/`indications`/`show-description`/`compose [titre]`),
descriptions (`use-description`/`save-description`/`save-description-as` — dossier fixe, dérivé
de `prompts <dossier>`), phrases de cadrage
(`show-*-framing`/`set-*-framing`/`save-*-framing`/`use-*-framing`/`reset-*-framing`),
indications soundtrack
(`show/set/save/use/reset-soundtrack-instructions`), prompt complet
(`show-*-prompt`/`export-*-prompt` — consultable et exportable, jamais rechargeable) — liste
complète et à jour dans `Docs/GUIDE_UTILISATEUR.md`.

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
`MusicTheoryKit/`. Compteur de vérifications à jour : **540 checks, 0 échec**, stable sur
plusieurs exécutions répétées.

## Vérification/tests

```sh
cd MusicTheoryKit
swift build                 # compile tout
swift run SanityChecks      # exécute tous les checks (seul moyen de "tester" ici)
swift run JamShack         # lance l'application
```

## Limites connues

- **Détection polyphonique au micro** : heuristique de pics spectraux, pas une vraie
  transcription d'accords. Fonctionne bien sur un accord clair ; peut se tromper sur des
  textures denses ou des timbres riches en harmoniques.
- **Micro : macOS uniquement.** Portage iOS/iPadOS à faire (configuration `AVAudioSession`).
- **Piste `clavier` (terminal) sans vrai maintien** : limite du terminal (aucun événement de
  relâchement), pas du code — le clavier virtuel du navigateur (§WebConsole), lui, reçoit un
  vrai `keyup` et tient réellement la note.
- **Aucune interface graphique** : tout passe par le CLI ; la couche `AppCore` est conçue
  pour qu'une interface SwiftUI puisse s'y brancher sans réécriture, mais cette étape n'a
  pas encore été commencée (bloquée par l'absence d'Xcode sur cette machine).
- **Session collaborative sans authentification ni chiffrement** : TCP en clair, tout client
  qui atteint le port est accepté (design délibéré pour cette première version — voir §AppCore).
  Ne pas exposer ce port au-delà d'un réseau de confiance (LAN/VPN).
- **Console web sans authentification ni chiffrement** : même mise en garde que ci-dessus,
  pour la même raison (HTTP en clair, aucun contrôle d'accès) — voir §WebConsole/§AppCore.
  Lecture seule cela dit (aucune action possible depuis le navigateur), donc un risque plus
  limité que la session collaborative.
- **Clavier virtuel sans authentification ni chiffrement, et sans limite de connexions** :
  même mise en garde, mais celui-ci N'EST PAS en lecture seule — n'importe qui atteignant le
  port peut jouer/relâcher des notes sur une piste de son choix (`?client=<id>` n'est pas un
  secret, juste un identifiant d'appareil).
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
