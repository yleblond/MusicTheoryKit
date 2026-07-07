# Documentation technique — Music Improv Assistant

Documentation du code généré dans ce package Swift. Reflète l'état du code à la fin de la
session du 2026-07-07. Pour l'historique détaillé des décisions/itérations, voir la mémoire
`project_improv_app_roadmap.md` ; pour la définition des termes ambigus/récurrents
(« piste », « prompt de composition », les trois écrans...), voir `Docs/GLOSSAIRE.md`.

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
  seulement en théorie) : deux processus `ImprovCLI` séparés sur cette machine, l'un en
  `server`, l'autre tapant `discover`, se voient bien l'un l'autre — voir §AppCore.
- **`FramedConnection`/`NetworkServer`/`NetworkClient` sont `@unchecked Sendable`** : chaque
  propriété mutable n'est touchée que depuis la queue série dédiée à cette instance — même
  raisonnement que celui déjà appliqué à `ImprovSession` (voir plus bas).

## WebConsole — serveur HTTP fait main pour la console web

Un second transport réseau, indépendant de `NetEngine` : là où `NetEngine` fait du TCP+JSON
fait main pour la session collaborative, `WebConsole` fait du HTTP/1.1 fait main (toujours
`Network.framework`, toujours aucune dépendance tierce) pour servir une page/un script à un
navigateur — voir §AppCore pour qui le pilote et §ImprovCLI pour la commande/le menu.
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
  `renderConsoleFrame(mode: .run)` (`ImprovCLI/main.swift`) — pistes en écoute, lecture d'un
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

## ImprovCLI — l'interface en ligne de commande

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

Barre de menu façon interface DOS graphique, six catégories (`menuCategories`, `main.swift`) :

| Menu (mnémonique) | Contenu |
|---|---|
| **MusicLab (L)** | Menu principal, ouvert par défaut. 6 groupes séparés par des traits : infos/aide ; choisir chacun des dossiers (morceaux/sons/soundtracks/connexions LLM/**composition IA**) ; choisir une connexion LLM (isolée dans son propre groupe) ; mode MIDI fusionné/individuel ; démarrer/arrêter la console web (§WebConsole) ; quitter. Point d'entrée unique pour toute la configuration de session — aucun autre menu ne propose de choisir un dossier ou une connexion. |
| **Instruments (I)** | Lister/activer/arrêter les pistes d'entrée, *séparateur*, activer/désactiver leur son, *séparateur*, choisir un son. Les quatre actions qui demandent une piste (`Activer/Arreter un instrument...`, `Activer/Desactiver le son...`) et la sélection d'instrument dans "Choisir un son..." présentent `session.tracks` numérotée (`printNumberedTracks()`) — le choix accepte un numéro ou l'id littéral (`resolvedTrackIDText(_:)`, même convention que `resolvedSampleName`). |
| **Morceaux (M)** | 4 groupes : écouter/voir le morceau ; choisir le son de lecture, d'une piste, ou des accords d'une section (`pieceDetailLines()` numérote visuellement chaque section — `"Section 1: A"` — et chaque piste — `"piste 1 '...'"` — pour que l'utilisateur sache directement quel numéro saisir) ; charger la démo/un morceau, sauvegarder ; `MenuItem.header("Assistant IA")` — sous-section réservée, sans item pour l'instant, en attente d'une future fonction de modification par dialogue applicable à n'importe quel morceau. |
| **Enregistrement (E)** | Démarrer/arrêter/voir/jouer un enregistrement, *séparateur*, charger/sauvegarder, *séparateur*, composer un morceau à partir de l'enregistrement, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser la phrase de cadrage, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser les indications de style, *séparateur*, voir/exporter le prompt de composition. Ordre — cadrage puis indications avant le prompt — délibéré (voir §LLMEngine/§AppCore). |
| **Composition (C)** | Décrire le morceau (assistant titre → description → indications → composition), composer à partir de la description, voir la description, *séparateur*, charger/sauvegarder(-sous) une description, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser la phrase de cadrage, *séparateur*, voir/exporter le prompt de composition. |
| **Jam Session (J)** | Démarrer/arrêter une jam session, rejoindre, trouver (découverte), quitter — session collaborative. Les trois premiers items appellent `promptForPseudo()` avant de continuer. |

Convention des mnémoniques : pas toujours la première lettre du titre (`MusicLab`→`L`,
`Composition`→`C`...) — choisies pour éviter toute collision entre menus (voir le commentaire
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
`ownerName`), console web (`web-console [port]`/`web-console stop`, menu MusicLab — voir
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
`MusicTheoryKit/`. Compteur de vérifications à jour : **309 checks, 0 échec**, stable sur
plusieurs exécutions répétées.

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
- **Console web sans authentification ni chiffrement** : même mise en garde que ci-dessus,
  pour la même raison (HTTP en clair, aucun contrôle d'accès) — voir §WebConsole/§AppCore.
  Lecture seule cela dit (aucune action possible depuis le navigateur), donc un risque plus
  limité que la session collaborative.
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
