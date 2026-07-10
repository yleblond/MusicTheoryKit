# Music Improv Assistant

Un assistant d'improvisation et de composition musicale, en Swift — écoute en direct
(MIDI/clavier/micro), reconnaissance d'accords et de modes en temps réel, composition assistée
par IA (à partir d'un texte ou d'un enregistrement), lecture multi-timbrale de morceaux
structurés, et une session collaborative en réseau local. Piloté aujourd'hui par une interface
en ligne de commande avec menus façon DOS, mais construit sur une couche applicative
(`AppCore`) entièrement indépendante de la présentation — pensée pour qu'une future interface
graphique (SwiftUI) puisse s'y brancher sans rien réécrire.

## Démarrer

```sh
cd MusicTheoryKit
swift run JamShack
```

Au lancement, l'application écoute automatiquement ses dossiers de travail par défaut
(morceaux, sons, connexions LLM, soundtracks, composition IA), situés à côté de
`MusicTheoryKit/`. Tape `help` pour la liste des commandes, ou utilise les menus (`run`/
`config`, voir plus bas).

**Environnement requis** : macOS, les Command Line Tools suffisent (Xcode complet non
nécessaire pour utiliser l'application — seulement pour lancer `swift test`, voir plus bas).

## Fonctionnalités

### Écoute en direct et reconnaissance

- **Plusieurs sources d'entrée simultanées**, chacune avec sa propre écoute et sa propre
  reconnaissance : MIDI (fusionné ou un flux par port), le clavier de l'ordinateur (disposition
  façon « Musical Typing » de GarageBand), et le microphone (détection de plusieurs notes à la
  fois par FFT — un vrai accord joué à la voix ou à l'instrument).
- **Reconnaissance d'accords et de modes en temps réel**, indépendante pour chaque piste :
  l'accord tenu (comparaison par score de Jaccard contre toute la bibliothèque théorique) et
  le(s) mode(s) en cours (historique pondéré à décroissance exponentielle des notes récentes).
- **Bibliothèque théorique complète** : 33 gammes réparties en 7 familles, un vocabulaire
  d'accords (triades + septièmes), toutes dérivées algorithmiquement — jamais saisies à la main.
- **Clavier ASCII coloré en direct** dans le terminal (fondamentale, notes de l'accord, notes
  hors accord, notes du mode) pour chaque piste en écoute.
- **Guide musical** : construire une séquence de modes à parcourir en jouant (flèches
  gauche/droite ou barre d'espace pour démarrer/arrêter), avec un écran dédié affichant le
  clavier du mode courant et ses voisins sur le cycle des quintes.
- **Cercle des quintes visuel** (console web) : les 12 tonalités, 3 anneaux d'accords
  (majeur/mineur/diminué), le contour des 7 accords diatoniques de la tonalité active, et le
  nom du mode en cours — recalculé automatiquement selon la piste/le morceau/le guide actif.

### Morceaux et lecture

- **Deux modèles de morceau, volontairement incompatibles** : un `Piece` structuré (mesures,
  temps, accords avec inversions/basses alternatives/arpèges, lignes mélodiques réutilisables)
  et une `SoundTrack` événementielle (un enregistrement brut, note par note, en temps réel —
  sans grille métrique).
- **Lecture multi-timbrale** : chaque piste mélodique et l'accompagnement d'accords de chaque
  section d'un morceau peuvent avoir leur propre instrument (fichier SoundFont/DLS/aupreset),
  plusieurs timbres sonnant simultanément via des moteurs audio indépendants.
- **Enregistrement en temps réel** de n'importe quelle combinaison de pistes en écoute, rejoué
  ensuite tel quel, ou envoyé à l'IA pour en déduire un `Piece` structuré (tempo, tonalité,
  progression d'accords plausible).

### Composition assistée par IA

- **Trois fournisseurs LLM pris en charge** : Ollama (local), tout serveur compatible OpenAI
  (LM Studio, llama.cpp…), et Claude — aucune clé API stockée en clair, seulement le nom d'une
  variable d'environnement à définir.
- **Composer à partir d'un texte** (poème, paroles…) ou **à partir d'un enregistrement**
  (déduction de tempo/tonalité/accords à partir d'une performance réelle), avec des indications
  de style facultatives dans les deux cas.
- **Validation stricte de toute suggestion de l'IA** avant de l'utiliser : gamme/accord
  invalide, note hors plage, section sans accord valide → rejetés avec un avertissement plutôt
  qu'injectés tels quels dans le morceau.
- **Le prompt envoyé à l'IA est toujours recomposé à partir de parties indépendantes**
  (phrase de cadrage, données, indications de style), jamais chargé/remplacé comme un bloc —
  chaque partie se prévisualise, se sauvegarde et se recharge séparément, et le prompt complet
  résultant reste consultable et exportable pour référence.

### Session collaborative et suivi à distance

- **Jam Session** : héberger ou rejoindre une session sur le réseau local (découverte
  automatique via Bonjour), chaque participant voit apparaître les pistes de tout le monde,
  avec reconnaissance d'accord/mode calculée une seule fois côté serveur. Le son reste toujours
  une décision locale — jamais forcé par le réseau.
- **Console Web** : un miroir en lecture seule de l'activité musicale, dans un navigateur —
  utile pour l'afficher sur un second écran, via un petit serveur HTTP fait main (aucune
  dépendance tierce). Mise en page adaptative (deux colonnes, profite de l'espace sur un grand
  écran, repasse en une colonne sur un écran étroit).
- **Clavier virtuel** : un piano interactif dans le navigateur (souris, tactile — vraiment
  multi-touch —, ou clavier de l'ordinateur avec un vrai maintien de note), serveur HTTP
  distinct de la console web. Plusieurs navigateurs peuvent s'y connecter à la fois, chacun
  avec sa propre piste et son propre nom affiché.
- **Palettes de couleur** : une couleur par note (et une couleur de texte assortie, pour
  rester lisible sur chaque fond), plusieurs jeux au choix (`palettes.json`, modifiable à la
  main), propre à chaque instance lancée — s'applique à la console web et au clavier virtuel
  de cette même instance, sans recharger la page.

### Interface en ligne de commande

- **Menus déroulants façon interface DOS** (mnémoniques, navigation aux flèches), et trois
  écrans figés redessinés en direct — `run` (activité musicale en cours), `config`
  (configuration de session et détail du morceau actif), `guide` (le guide musical, voir
  plus haut) — bascule instantanée entre les trois (Tab) sans repasser par le mode commande.
  Lancement direct sur `run` après le choix éventuel d'une scène au démarrage.

## Architecture

Aucune dépendance tierce — uniquement les frameworks système Apple
(`Network`/`AVFoundation`/`CoreMIDI`/`Accelerate`). Logique applicative entièrement
indépendante de la présentation (`AppCore`), pour qu'une future interface graphique puisse s'y
brancher sans réécriture.

```
MusicTheoryKit    théorie musicale pure (gammes, accords) — aucune dépendance
PieceModel        modèle de morceau structuré (mesures/accords/mélodie), Codable
SoundTrackModel   modèle d'enregistrement événementiel (secondes), Codable
RecognitionEngine reconnaissance d'accords/modes à partir d'un flux de notes
MIDIEngine        entrée MIDI (parsing pur + wrapper CoreMIDI)
AudioEngine        lecture Piece/SoundTrack, écoute micro (FFT)
LLMEngine          composition assistée par IA (3 fournisseurs), validation stricte
NetEngine          transport réseau de la session collaborative (TCP fait main)
WebConsole         serveur HTTP fait main pour la console web et le clavier virtuel
AppCore            ImprovSession — tout l'état et la logique applicative
JamShack          l'exécutable : REPL + écrans figés + menus
SanityChecks       exécutable de test de secours (voir ci-dessous)
```

Pour le détail complet (modules, concurrence, points de conception), voir
[`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md).

## Documentation

- [`Docs/GUIDE_UTILISATEUR.md`](Docs/GUIDE_UTILISATEUR.md) — manuel d'utilisation complet,
  section par section, avec toutes les commandes.
- [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md) — documentation technique (modules, modèle de
  concurrence, choix de conception).
- [`Docs/GLOSSAIRE.md`](Docs/GLOSSAIRE.md) — désambiguïsation des termes qui désignent des
  choses différentes selon le contexte.

## Tester

```sh
cd MusicTheoryKit
swift build                 # compile tout
swift run SanityChecks      # exécute tous les checks (515 a ce jour, 0 echec)
```

Cette machine de développement n'a que les Command Line Tools (pas Xcode complet), donc
`swift test` échoue (`XCTest` indisponible). De vrais fichiers `XCTest` existent dans `Tests/`
pour le jour où Xcode sera installé ; en attendant, `SanityChecks` rejoue chaque cas à la main
et reste le seul moyen de vérifier la logique dans cet environnement.

## Limites connues

- Détection polyphonique au micro : heuristique de pics spectraux, pas une vraie transcription
  d'accords — fonctionne bien sur un accord clair.
- Microphone : macOS uniquement (portage iOS/iPadOS non fait).
- Session collaborative, console web et clavier virtuel sans authentification ni chiffrement —
  à réserver à un réseau de confiance (LAN/VPN), jamais exposés directement sur Internet.
- Aucune interface graphique à ce jour — tout passe par la ligne de commande.

Détail complet dans [`Docs/ARCHITECTURE.md`](Docs/ARCHITECTURE.md#limites-connues).
