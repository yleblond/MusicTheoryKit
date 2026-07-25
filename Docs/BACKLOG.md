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
