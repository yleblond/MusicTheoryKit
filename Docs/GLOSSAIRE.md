# Glossaire — Music Improv Assistant

Termes qui désignent des choses différentes selon le contexte, ou qui reviennent souvent dans
le code/la documentation sans être définis sur place. À consulter en cas de doute plutôt que
de deviner — voir `ARCHITECTURE.md` (référence technique) et `GUIDE_UTILISATEUR.md` (manuel)
pour le détail de chaque fonctionnalité.

## Les deux modes de morceau : `Piece` vs `SoundTrack`

Deux schémas `Codable` **délibérément incompatibles**, pas des variantes l'un de l'autre :

- **`Piece`** (module `PieceModel`) — un morceau structuré en mesures/temps/accords, avec
  tempo et tonalité. Chargé/composé/joué avec `load`/`compose`/`play`, menu **Morceaux**.
- **`SoundTrack`** (module `SoundTrackModel`) — un enregistrement événementiel brut
  (« telle hauteur, à tel instant en secondes »), sans tempo ni mesure. Capturé avec
  `record start`/`record stop`, menu **Enregistrement**. Peut servir de matière première pour
  qu'une IA en déduise un `Piece` plausible (`compose-piece-from-soundtrack`), mais ne se
  charge jamais directement comme un `Piece`.

## « Track »/« piste » — trois notions distinctes

Le mot revient dans trois contextes qui n'ont rien à voir entre eux :

- **`PieceModel.Track`** — une partie d'instrument *à l'intérieur d'un `Piece`* (mélodie
  écrite + fragments), avec son propre `instrument: String`. Se manipule avec
  `set-track-instrument`, menu **Morceaux**.
- **`AppCore.TrackInfo` / `TrackID`** — une *source d'entrée en direct* (MIDI, clavier
  ordinateur, micro, ou une piste distante `.remote(...)`), listée dans `session.tracks`. Se
  manipule avec `track <id> on/off/son/instrument`, menu **Scene**. C'est ce sens-là que
  visent les libellés du menu **Scene** (« Activer un instrument... » = démarrer
  l'écoute d'une `TrackInfo`, pas d'un `PieceModel.Track`).
- **`SoundTrack.trackIDs`** — l'ensemble des `TrackID` (au sens ci-dessus) ayant contribué au
  moins un événement à un enregistrement donné ; un simple `Set` calculé, pas un type à part.

À l'écrit, cette doc et le guide utilisateur réservent « piste » aux `TrackInfo`/`TrackID`
(sources d'entrée) et parlent explicitement de « piste mélodique » ou de `Track` du morceau
pour l'autre sens.

## `Soundtrack` (module/concept) vs `Enregistrement` (menu) vs `soundtrack` (nom de commande)

Un seul concept, trois habillages selon le contexte :

- **`SoundTrackModel`/`SoundTrack`** — le nom du module et du type Swift (voir plus haut).
- **Menu Enregistrement** — le nom du menu dans l'interface, et le vocabulaire des libellés
  qu'il affiche (« Jouer l'enregistrement », « Voir l'enregistrement »...) — plus parlant que
  l'anglicisme pour un utilisateur final.
- **`soundtrack` dans les noms de commande** (`play-soundtrack`, `use-soundtrack`,
  `save-soundtrack-as`, `show-soundtrack-prompt`...) — vocabulaire de commande, resté en
  anglais pour rester court, jamais renommé quand le menu a été rebaptisé « Enregistrement ».

Les trois désignent exactement la même fonctionnalité ; seul l'habillage change.

## Les trois modes d'affichage

- **`Command`** — le REPL classique (prompt `>`), un aller-retour commande/réponse à la fois.
  Mode par défaut au lancement.
- **`run`** — écran figé redessiné en direct, focalisé sur l'activité musicale en cours
  (claviers, accords/modes détectés). Commande `run`, touche **q** ou Ctrl+C pour sortir.
- **`config`** — même principe, focalisé sur la configuration de session et le détail du
  morceau actif. Commande `config`, mêmes touches de sortie.

**`console` n'existe plus** : c'était l'écran unique d'origine, qui combinait tout ce que
`run` et `config` montrent séparément aujourd'hui — retiré, pas juste renommé, quand l'écran
est devenu trop chargé pour rester lisible. Toute référence à `console` dans du code ou de la
documentation ancienne désigne ce qui s'appelle maintenant `run` (pour l'activité musicale) ou
`config` (pour l'état de session).

## `console` (retiré) vs **Console Web** — deux choses sans rapport, malgré le nom

Facile à confondre à cause du nom, mais ce sont deux concepts complètement différents :

- **`console`** (voir juste au-dessus) — un ancien écran *terminal*, retiré, remplacé par
  `run`/`config`.
- **Console Web** (`web-console`, menu **JamShack**) — un **nouveau** serveur HTTP fait main
  (module `WebConsole`), qui sert une page dans un **navigateur** — un miroir en lecture seule
  de l'écran `run`, pas un mode d'affichage du terminal. Les deux n'ont aucun lien de code ou
  d'historique ; le nom se recoupe par coïncidence (« console » au sens large de « tableau de
  bord »).

## Console Web vs Clavier virtuel — deux serveurs HTTP distincts, volontairement

`web-console` et `virtual-keyboard` (`ImprovSession.startWebConsole`/`startVirtualKeyboard`,
module `WebConsole`) sont deux `HTTPServer` séparés, sur des ports indépendants — pas deux
routes d'un seul serveur. La Console Web reste strictement en lecture seule (aucune route
n'accepte d'entrée) ; le Clavier virtuel est strictement l'inverse, une page qui ne fait que
jouer (`GET /note-on`/`GET /note-off`, piste dédiée `TrackID.webKeyboard(clientID:)` — une par
navigateur connecté, voir `ImprovSession.ensureWebKeyboardTrack`). Choix délibéré pour garder
la Console Web simple plutôt que d'y ajouter un mode « clavier actif ».

## `MenuItem.separator` vs `MenuItem.header(_:)`

Deux façons de structurer un menu déroulant plat (ce système de menus n'a pas de sous-menus
imbriqués) — les deux partagent le même flag interne `isSeparator` et la même protection
anti-crash dans la navigation aux flèches (jamais sélectionnables) :

- **`.separator`** — un simple trait horizontal, sans label. Sert juste à grouper visuellement
  des items apparentés.
- **`.header(_ title:)`** — un titre affiché en estompé, non sélectionnable. Sert à nommer une
  sous-section à l'intérieur d'un menu (ex. « Assistant IA » dans **Morceaux**) quand un
  simple trait ne suffirait pas à expliquer le regroupement.

## Instrument d'un `Track`/`Section` : `""` vs `nil` vs un vrai nom de fichier

Convention commune à `Track.instrument: String` et `Section.chordInstrument: String?` : une
chaîne vide (ou `nil` pour `chordInstrument`) veut dire *« pas d'instrument propre, utiliser
le son par défaut de la lecture »* — jamais une erreur, jamais un cas à part à gérer. Les
morceaux d'exemple et les morceaux composés par IA utilisent tous `""` comme valeur neutre
(un ancien placeholder textuel, `"piano"`, a été abandonné précisément parce qu'il se faisait
passer pour un vrai nom de fichier à résoudre, et échouait donc systématiquement).

## Prompt de composition : deux prompts distincts, jamais confondus

- **Prompt « texte »** (`show-text-prompt`/`compose`, menu **Composition**) — construit à
  partir de `sourceText`/`compositionTitle`/`additionalCompositionInstructions`.
- **Prompt « soundtrack »** (`show-soundtrack-prompt`/`compose-piece-from-soundtrack`, menu
  **Enregistrement**) — construit à partir de la `SoundTrack` courante.

Chacun a son propre override sauvegardable/chargeable (`save-text-prompt`/`use-text-prompt`
vs `save-soundtrack-prompt`/`use-soundtrack-prompt`) et son propre retour au comportement par
défaut (`reset-text-prompt`/`reset-soundtrack-prompt`) — les deux mécanismes sont parallèles
mais totalement indépendants l'un de l'autre.

## Description vs phrase de cadrage vs indications vs prompt complet — quatre granularités différentes

Le prompt envoyé à l'IA **n'est jamais chargé/remplacé comme un seul bloc** — toujours
recomposé à partir d'éléments gérés (et sauvegardés) séparément, du plus étroit au plus
large :

- **Description** (`save-description-as`/`use-description`, menu **Composition**
  uniquement) — le **titre + le texte collé + les indications de style**, tel que tapé dans
  l'assistant "Decrire le morceau...". Un simple `.json` (`CompositionDescription`), dans le
  sous-dossier `composition Descriptive/` du dossier de composition IA — n'existe pas côté
  soundtrack (rien à "décrire", c'est un enregistrement, pas un texte ; voir "Indications"
  ci-dessous pour son équivalent côté soundtrack).
- **Phrase de cadrage** (`show/set/save/use/reset-text-framing` et `...-soundtrack-framing`,
  menus **Composition**/**Enregistrement**) — seulement le premier paragraphe du prompt, celui
  qui donne le ton/la tâche à l'IA, avant le schéma JSON. La modifier ne touche jamais au
  schéma ni aux données. Sauvegardée dans `Cadrage Composition Descriptive/`/
  `Cadrage Composition Soundtrack/`.
- **Indications de style** — pour le texte, bundlées dans la description ci-dessus
  (`indications [texte]`, pas de sauvegarde séparée). Pour la soundtrack, qui n'a pas de
  "description" où les loger, leur propre élément sauvegardable/rechargeable
  (`show/set/save/use/reset-soundtrack-instructions`), dans `Indications Soundtracks/`.
- **Prompt complet** (`show-text-prompt`/`show-soundtrack-prompt`) — le texte intégral
  effectivement envoyé à l'IA : phrase de cadrage + schéma JSON + données + indications.
  Consultable et **exportable** (`export-text-prompt`/`export-soundtrack-prompt`, dans
  `Export/`) pour référence/débogage, mais plus jamais rechargeable comme override — un ancien
  mécanisme de rechargement (`save/use/reset-text-prompt`) a été retiré précisément parce
  qu'il permettait de perdre le schéma JSON en éditant le prompt exporté à la main ; les deux
  leviers plus étroits ci-dessus (phrase de cadrage, indications) ne peuvent structurellement
  pas casser le schéma, puisqu'ils ne le touchent jamais.

Description + phrase de cadrage + indications se composent en un prompt complet, mais se
gèrent (et se sauvegardent) chacun séparément.

## `Jam Session` (menu) vs `server`/`client` (commandes) vs `Reseau` (champ de statut)

Encore un seul concept, trois habillages :

- **Menu Jam Session** — vocabulaire volontairement ludique (« Démarrer une jam session »,
  « Trouver une jam session... ») pour un utilisateur final, plutôt que le vocabulaire
  technique client/serveur.
- **Commandes `server`/`stop-server`/`client`/`discover`/`disconnect`** — vocabulaire de
  commande, jamais renommé.
- **Champ `Reseau`** (affiché par `status`/`config`/`tracks`) — un libellé d'état technique,
  distinct du nom du menu, montrant l'état de connexion actuel (hôte, port, rôle).

## Pseudo — `localClientName` / commande `pseudo` / champ réseau `clientName` / `TrackInfo.ownerName`

Un seul concept (le nom qu'un participant choisit d'afficher aux autres), quatre habillages
selon la couche :

- **`ImprovSession.localClientName`** — la propriété qui stocke le pseudo de *ce*
  participant (`"player"` par défaut). C'est aussi ce qui sert de nom de service Bonjour
  quand on héberge (`startServer`) — pas de champ séparé pour ça.
- **Commande `pseudo [nom]`** — l'habillage CLI pour lire/changer `localClientName`.
- **`clientName`** (champ de `NetMessage`/`RemoteTrackSnapshot`, module `NetEngine`) — le nom
  du fil : comment le pseudo voyage sur le réseau (envoyé une fois dans le `hello`, puis
  redistribué dans chaque `sync`).
- **`TrackInfo.ownerName`** — le pseudo *déjà résolu*, tel qu'affiché sur une piste `.remote`
  précise (« — Marie Curie » à côté du nom de la piste) — `nil` pour toute piste locale, la
  distinction entre « mon propre pseudo » et « le pseudo affiché sur une piste de quelqu'un
  d'autre » étant justement le point de ce champ. Voir §AppCore de `ARCHITECTURE.md` pour le
  détail de sa résolution côté serveur/côté client.

## `SanityChecks` vs `XCTest`

Cette machine n'a que les Command Line Tools (pas Xcode complet), donc `swift test` échoue
(`XCTest` indisponible). `SanityChecks` est un exécutable séparé qui **rejoue à la main**
chaque cas de test des vrais fichiers `XCTest` de `Tests/` (mêmes assertions, via `check`/
`checkNil`) — ce n'est pas un remplaçant définitif, c'est un filet de sécurité pour cet
environnement précis : toute nouvelle fonctionnalité doit gagner un cas dans les deux endroits
(le vrai test `XCTest`, prêt pour le jour où Xcode sera installé, **et** son miroir dans
`SanityChecks`, seul moyen actuel de le vérifier réellement).

## « Scène » — trois concepts sans rapport, malgré le nom

- **`AppCore.Scene`** (menu **Scene** > sauvegarder/charger une scène, commandes
  `save-scene`/`use-scene`) — une **configuration d'instruments sauvegardée**, depuis peu à
  base de **rôles** (voir la section suivante) plutôt que directement liée à un instrument
  précis : un instantané rechargeable, sans aucun rapport avec le réseau.
- **« Plan de scène »** (commande `scene-tree`, onglet **Scene** de la console web — voir
  `ARCHITECTURE.md` §"Plan de scène") — une **vue en arbre de qui est connecté et avec quels
  instruments**, en direct : l'application, ses instruments locaux, l'état de la console
  web/du clavier virtuel, et en mode serveur les clients de la Jam Session avec leurs propres
  pistes. Rien à sauvegarder ici — c'est un affichage, pas une configuration.
- **« Scene (lecture du morceau) »** — un intitulé de section dans `help` qui n'a en fait rien
  à voir avec les deux sens ci-dessus : il documente `samples`/`use-sample`/
  `set-track-instrument`, c'est-à-dire le choix du **son par défaut d'un morceau (`Piece`)**,
  pas une configuration d'instruments en direct ni un plan de scène réseau. Une coïncidence de
  nom héritée de l'historique du projet, pas un concept à part à retenir.

Les trois vivent dans le même vocabulaire « Scene »/« scène » (par coïncidence de nom), mais
ne partagent aucun code ni aucune donnée entre eux.

## « Rôle » (`AppCore.SceneRole`) — un poste déclaré, distinct de l'instrument qui l'occupe

Un **rôle** ("Piano 1", "Basse Guitare", "Saxophoniste"...) est un poste musical déclaré à
l'avance dans une scène (§ précédente), avec son propre son (`soundName`) — **indépendant** de
quel instrument physique/virtuel l'occupe cette session-ci (`attachedTrackID`, jamais
sauvegardé sur disque : uniquement l'état de la session en cours). C'est le correctif direct
d'un vrai problème : avant les rôles, une scène sauvegardée gardait l'instrument lié
directement à un `TrackID` (souvent un simple index de port MIDI, instable d'un branchement à
l'autre) — un clavier MIDI absent au rechargement faisait échouer silencieusement, sans le
moindre message. Commandes : `scene-new`/`scene-role-add`/`-sound`/`-listen`/`-attach`/
`-detach`/`-remove`/`scene-roles` (voir `GUIDE_UTILISATEUR.md` §15).

Attention à ne pas confondre avec la **rangée de degrés d'échelle** affichée sous chaque
clavier (badges 1 à 7) — un concept de théorie musicale sans aucun rapport, qui portait aussi
le nom « role-line » en commentaire de code jusqu'à cette même session ; renommé
« degree-line » précisément pour lever cette collision de vocabulaire avant qu'elle ne prête à
confusion avec le nouveau concept de rôle de scène.

**Limite actuelle, assumée** : un rôle ne peut être occupé que par un instrument de CETTE
machine (mode solo/standalone) — un participant connecté à une Jam Session ne peut pas encore
revendiquer un rôle sur une scène partagée. Extension déjà conçue, délibérément différée (voir
`Docs/BACKLOG.md`).

## Menu déroulant (terminal) vs onglet Commandes (console web) vs serveur MCP — trois façades, une seule logique

Trois interfaces différentes qui déclenchent exactement les mêmes actions (`ImprovSession`),
jamais une logique dupliquée trois fois :

- **Menu déroulant du terminal** — la référence historique, tapée au clavier ou navigable aux
  flèches en mode `run`/`config` (voir §8 du guide utilisateur).
- **Onglet Commandes** (console web) — le même ensemble d'actions, accessible depuis un
  navigateur (voir §16 du guide utilisateur) ; passe par `GET /menu-action` côté serveur.
- **Serveur MCP** (`mcp-server/`, dossier séparé, en Python) — le même ensemble d'actions
  encore, exposé comme des *tools* pour un assistant IA (voir §17 du guide utilisateur) ; un
  simple relais HTTP vers les mêmes routes que l'onglet Commandes, aucune logique dupliquée.

Les trois excluent volontairement les écrans en lecture seule (statut, activité en direct, plan
de scène) — ils ne servent qu'à agir, jamais à afficher ; ces écrans-là restent uniquement
accessibles depuis le terminal (`run`/`config`/`status`) ou les onglets `Run`/`Scene`/`Infos`
de la console web.

## « Progression d'accords » — deux notations, deux granularités

- **`Section.chords: [ChordEvent]`** (module `PieceModel`) — une progression **absolue et
  chronométrée** : chaque accord porte sa position exacte (mesure/temps/durée), son inversion,
  sa basse alternative, son style de jeu — la progression réelle d'un `Piece` composé/joué.
- **`ChordProgressionTemplate.degrees: [String]`** (module `AppCore`, fichier
  `chordprogressions.json`) — une progression **relative et sans timing**, en chiffres romains
  ("I", "vi", "vii°" — voir `MusicTheoryKit.RomanNumeralChord`), applicable à n'importe quel
  mode/tonique. Résolue en `[ChordReference]` (accords concrets, toujours sans timing) au
  moment où on l'attache à une étape du guide musical (`GuideStep.chordProgression`) — jamais
  stockée sous sa forme relative une fois attachée.

Le second n'est jamais qu'une bibliothèque de *templates* pour produire, une fois résolu
contre un mode, quelque chose qui ressemble au premier sans timing — les deux ne se
convertissent pas automatiquement l'un vers l'autre.

## Candidat (`compose-piece-from-soundtrack`)

Quand `compose-piece-from-soundtrack <n>` est appelé avec `n > 1`, l'IA produit `n` tentatives
indépendantes de déduction d'un `Piece` à partir de la même `SoundTrack` — chacune qui survit
à la validation est sauvegardée comme un fichier séparé (`<titre>-candidat-N.json`), toutes
inspectables ensuite via `pieces`/`use-piece`. Le dernier candidat généré devient le morceau
courant, mais les autres restent sur disque — « candidat » ne désigne jamais un brouillon
jetable, seulement l'une de plusieurs propositions parallèles à comparer soi-même.
