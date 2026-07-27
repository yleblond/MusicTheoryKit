# Backlog

Idées et chantiers identifiés mais pas encore engagés. Chaque entrée garde le contexte
nécessaire pour être reprise sans redérivation ; à supprimer ou déplacer vers le README/
CHANGELOG une fois traitée.

## Prioritaire

1. **Support des presets multiples au sein d'un même fichier SoundFont (.sf2).** Un `.sf2` peut
   contenir plusieurs dizaines d'instruments/presets différents (comme une banque General MIDI
   complète), chacun identifié par un triplet `program`/`bankMSB`/`bankLSB`. Aujourd'hui, le
   code ne charge jamais que le premier (`program=0`, bank GM par défaut) et n'a aucun moyen de
   lire/lister les autres presets d'un fichier donné — un `.sf2` multi-instruments est donc
   traité comme un son unique, les autres presets étant invisibles pour l'utilisateur.

   Points de blocage identifiés (2026-07-27) :
   - `Sources/AudioEngine/SamplerUnit.swift:47` (`loadSample(at:program:)`) et ses 3 clones —
     `PiecePlayer.swift:206`, `SoundTrackPlayer.swift:38`, `GuideAuditionPlayer.swift:45` —
     appellent tous `loadSoundBankInstrument`/`loadInstrument` avec `program: UInt8 = 0` fixe et
     bank GM par défaut ; aucun n'expose `bankMSB`/`bankLSB` en paramètre appelant. Commentaire
     explicite à `PiecePlayer.swift:204-205` : *"program 0 = first instrument in the bank"*.
   - Aucun parsing du format SoundFont2 (chunks `phdr`/`pbag`/etc.) n'existe dans le repo pour
     extraire la liste des presets (nom, program, bank) d'un fichier `.sf2` — c'est le morceau
     technique le plus conséquent du chantier.
   - `Sources/AppCore/SoundSettings.swift:12-22` (`SoundEntry`) modélise un "son" uniquement par
     `path` (fichier) + `alias` + `isFavorite` — aucune notion de preset. Alias (`soundAlias`,
     `ImprovSession.swift:2383`) et favoris (`isSoundFavorite`, ligne 2387) font tous deux un
     lookup linéaire sur `path` seul, via la même structure/mutateur (`updateSoundEntry`, ligne
     2413) — donc une même extension de clé (fichier + program/bank composite) couvre alias et
     favoris en un seul changement.
   - Catalogue actuel (`sampleFiles`, `ImprovSession.swift:72`, peuplé par `listSampleFiles`,
     ligne 2295) : un fichier = une entrée, quel que soit son nombre de presets internes.
   - `App/Sources/SoundsView.swift` (onglet "Sons") liste les fichiers à plat (`soundRow`, ligne
     199) ; il faudra passer à une liste à deux niveaux (fichier → presets).
   - Trace de raffinement futur déjà envisagée mais non implémentée : `PieceModel/Track.swift:8`,
     champ `instrument: String` commenté *"free-form for now (e.g. General MIDI program name,
     later)"*.

   Étapes du chantier : (a) parseur minimal des presets d'un `.sf2` ; (b) étendre `SoundEntry` à
   un identifiant composite (fichier + program/bankMSB/bankLSB) ; (c) propager ce triplet dans
   les 4 points d'appel `loadSample`/`loadSoundBankInstrument` ; (d) UI à deux niveaux dans
   `SoundsView.swift`.

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
3. **Revérifier le binding réseau avant tout usage hors LAN de confiance.** Console web,
   clavier virtuel et jam session n'ont ni authentification ni chiffrement (limite déjà
   documentée dans le README) et rien n'empêche aujourd'hui ces serveurs d'écouter sur toutes
   les interfaces réseau plutôt que juste le LAN local. Pas un problème à la maison, mais à
   vérifier avant un usage sur réseau partagé (café, conférence).

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

## Fonctionnalités (2026-07-27)

1. **Intégrer le serveur MCP (actuellement `mcp-server/`, Python externe) directement dans
   l'app Swift**, plutôt que de le garder comme process séparé à lancer/configurer à la main.
   Ajouter son démarrage dans le même sous-onglet que "Connexion LLM" (`JamShackLLMView`) — ce
   sous-onglet contiendrait alors deux sections : Connexion LLM et Serveur MCP. Point à
   éclaircir à l'implémentation : le serveur MCP actuel est un simple proxy HTTP vers les routes
   `/menu-action`/`/menu-lists` déjà exposées par `WebConsole` (voir `mcp-server/README.md`) —
   un portage Swift devra définir son propre transport MCP (stdio pour un client comme Claude
   Desktop, ou HTTP+SSE), pas juste réutiliser tel quel le protocole HTTP existant. **Sorti
   explicitement d'un premier plan d'implémentation (2026-07-26)** — trop gros pour être bundlé
   avec le reste, mérite sa propre exploration dédiée.

2. **Gestion multi-microphone**, avec possibilité d'ajuster individuellement le niveau d'entrée
   de chacun. Étend le flux de calibration/spectroscope micro existant (mono aujourd'hui) à
   plusieurs entrées simultanées — implique probablement une UI de calibration par device et un
   mixage des niveaux en amont de la détection FFT plutôt qu'un simple choix de device unique.

3. **Connexion à des librairies/repositories de fichiers SoundFont publics** : accès à la
   librairie, listing, download et test du son avant usage. Nécessite un client réseau vers un
   ou plusieurs dépôts publics (à identifier), un cache local des fichiers téléchargés, et un
   aperçu sonore avant de les rendre disponibles au reste de l'app. Le download comme le "test
   du son" doivent afficher une progression si le chargement n'est pas instantané (voir item 6
   ci-dessous, qui couvre l'état actuel du chargement local).

4. **Layout portrait / layout dédié iPhone.** L'app est aujourd'hui pensée pour un usage
   paysage/tablette-desktop (voir aussi l'item "Clavier virtuel : adapter la taille du piano à
   la largeur de la page" ci-dessus, qui ne couvre que le paysage). Un vrai layout portrait/iPhone
   est un chantier distinct : réorganisation des colonnes/panneaux, pas seulement un
   redimensionnement du clavier.

5. **Sorties MIDI** : pouvoir jouer vers d'autres devices MIDI externes pour le rendu sonore, en
   plus (ou à la place) du rendu interne actuel. Implique de brancher une sortie CoreMIDI
   (sélection du device de destination) en parallèle du chemin de synthèse/audio existant.

6. **Afficher une progression pendant le chargement d'un son (SoundFont), partout où ça a du
   sens.** Aujourd'hui `SamplerUnit.loadSample(at:)` (`Sources/AudioEngine/SamplerUnit.swift`)
   charge le fichier de façon synchrone (`loadSoundBankInstrument`/`loadInstrument`) sans aucun
   état de progression, et son point d'entrée `ImprovSession.setInstrument(named:for:)`
   (`Sources/AppCore/ImprovSession.swift:2205`) est appelé directement depuis l'UI sans
   `async`/`Task` — toute latence de lecture disque bloque l'appelant sans feedback visuel.
   Concerné dès maintenant : le bouton "test du son" de `App/Sources/SoundsView.swift` (section
   "Sound test mode", ~lignes 23-196, appel en ligne 228), qui se contente de changer l'icône du
   haut-parleur une fois le chargement terminé, sans indicateur pendant. Deviendra plus
   nécessaire encore une fois l'item 3 (librairies SoundFont publiques, avec download réseau)
   implémenté. À explorer : rendre `setInstrument`/`loadSample` asynchrones avec un état de
   chargement observable, et l'exposer dans `SoundsView` (et tout autre écran de sélection
   d'instrument par piste) via un indicateur (spinner ou barre) le temps du chargement.
