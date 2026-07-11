# Backlog

Idées et chantiers identifiés mais pas encore engagés. Chaque entrée garde le contexte
nécessaire pour être reprise sans redérivation ; à supprimer ou déplacer vers le README/
CHANGELOG une fois traitée.

## Stabilisation de l'environnement (2026-07-11)

1. **Installer Xcode complet.** `SanityChecks` est un miroir tenu à la main des fichiers
   `Tests/*` (547 checks aujourd'hui) — le vrai risque n'est pas qu'il soit faux maintenant,
   mais qu'il dérive silencieusement si un futur test XCTest est ajouté sans son pendant
   `SanityChecks`. Installer Xcode permettrait de repasser sur `swift test` et de laisser
   `SanityChecks` devenir obsolète comme prévu à l'origine (voir `Docs/ARCHITECTURE.md` et
   la limite documentée dans le README).
2. **Remplacer les queues série manuelles de `ImprovSession` par un `actor`.** La concurrence
   repose aujourd'hui sur la discipline (queues dédiées + compteur `playbackGeneration` à
   vérifier à chaque nouvelle feature touchant l'état partagé), pas sur le compilateur. Trois
   crashs réels ont déjà eu lieu sur exactement ce pattern (voir l'historique de
   `ImprovSession.swift`). Passer l'état mutable en `actor` ferait respecter l'isolation par
   le type-system plutôt que par une règle à se rappeler.
3. **Ajouter des stress-tests automatisés dans `SanityChecks`** pour les scénarios déjà connus
   fragiles (notes rapprochées au clavier ordinateur, `play()` appelé en chevauchement) — un
   seul run propre ne prouve rien pour ce genre de bug de concurrence intermittente. Une
   variante "répéter N fois" de ces checks transformerait une vérification manuelle par
   session pty en filet permanent, exécuté à chaque `swift run SanityChecks`.
4. **Revérifier le binding réseau avant tout usage hors LAN de confiance.** Console web,
   clavier virtuel et jam session n'ont ni authentification ni chiffrement (limite déjà
   documentée dans le README) et rien n'empêche aujourd'hui ces serveurs d'écouter sur toutes
   les interfaces réseau plutôt que juste le LAN local. Pas un problème à la maison, mais à
   vérifier avant un usage sur réseau partagé (café, conférence).

## Fonctionnalités (2026-07-11)

1. **Portée musicale classique (piano, clés de sol et fa).** Représenter :
   - en mode `run` : les notes jouées / accords détectés en direct,
   - en mode `guide` : les accords à jouer de l'étape courante.

   Question ouverte à trancher : le choix des altérations. Pour le guide, c'est simple (le
   mode de l'étape est connu, les altérations s'en déduisent). Pour `run`, le mode n'est pas
   toujours fiable en temps réel — probablement partir d'une portée sans altération à la clé
   et gérer les altérations accord par accord (dièse/bémol par note plutôt qu'une armure
   globale) plutôt que d'essayer de deviner une tonalité.

2. **Meilleure détection micro pour le jeu au piano.** Le piano introduit trois sources de
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

3. **Exposer toute la bibliothèque de modes/échelles au moment de composer**, pas seulement
   les modes principaux déjà présentés sur le cercle des quintes. La source est
   `KnowledgeBase/Modes/scales_of_harmonies.pdf` (33 gammes / 7 familles, déjà à la base de
   `MusicTheoryKit`, mais pas toutes proposées dans l'UI d'ajout de mode à un morceau/guide).
   À faire en même temps : vérifier que les notes du mode choisi — y compris les modes moins
   courants — sont bien répercutées sur tous les affichages de clavier existants (mode-marker
   row, "Notes du mode", clavier virtuel), pas seulement sur les modes déjà couverts
   aujourd'hui.
