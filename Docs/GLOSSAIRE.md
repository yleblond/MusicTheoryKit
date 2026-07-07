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
  manipule avec `track <id> on/off/son/instrument`, menu **Instruments**. C'est ce sens-là que
  visent les libellés du menu **Instruments** (« Activer un instrument... » = démarrer
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
- **Console Web** (`web-console`, menu **MusicLab**) — un **nouveau** serveur HTTP fait main
  (module `WebConsole`), qui sert une page dans un **navigateur** — un miroir en lecture seule
  de l'écran `run`, pas un mode d'affichage du terminal. Les deux n'ont aucun lien de code ou
  d'historique ; le nom se recoupe par coïncidence (« console » au sens large de « tableau de
  bord »).

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

## Candidat (`compose-piece-from-soundtrack`)

Quand `compose-piece-from-soundtrack <n>` est appelé avec `n > 1`, l'IA produit `n` tentatives
indépendantes de déduction d'un `Piece` à partir de la même `SoundTrack` — chacune qui survit
à la validation est sauvegardée comme un fichier séparé (`<titre>-candidat-N.json`), toutes
inspectables ensuite via `pieces`/`use-piece`. Le dernier candidat généré devient le morceau
courant, mais les autres restent sur disque — « candidat » ne désigne jamais un brouillon
jetable, seulement l'une de plusieurs propositions parallèles à comparer soi-même.
