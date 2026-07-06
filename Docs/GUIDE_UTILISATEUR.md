# Guide utilisateur — Music Improv Assistant

Manuel d'utilisation de l'application en ligne de commande, dans son état à la fin de la
session du 2026-07-06.

## Lancer l'application

Depuis le dossier `MusicTheoryKit/` :

```sh
swift run ImprovCLI
```

Au démarrage, l'application charge automatiquement les dossiers de travail par défaut
(`Pieces/`, `SoundFonts/`, `LLMConnections/`, situés à côté de `MusicTheoryKit/`) — pas
besoin de les indiquer à chaque lancement.

Deux modes d'utilisation :
- **Le mode ligne de commande (REPL)** : tape une commande, appuie sur Entrée, lis le
  résultat. C'est le mode par défaut au démarrage.
- **Le mode `watch`** : un tableau de bord fixe qui se met à jour en direct, avec un menu
  déroulant façon DOS. On y entre avec la commande `watch`, on en sort avec Ctrl+C.

Tape `help` à tout moment pour la liste des commandes.

---

## 1. Charger et gérer un morceau

| Commande | Effet |
|---|---|
| `load-demo` | Charge un morceau de démonstration (une progression ii-V-I en Do majeur). |
| `pieces <dossier>` | Liste les morceaux (`.json`) du dossier. |
| `use-piece <numéro ou nom>` | Charge un morceau de la liste. |
| `load <chemin.json>` | Charge un morceau depuis un chemin explicite. |
| `new-piece <titre>` | Démarre un morceau vierge (point de départ pour composer, à la main ou via l'IA). |
| `save` | Ressauvegarde le morceau courant au même endroit qu'au chargement. |
| `save-as <nom>` | Sauvegarde sous un nouveau nom, dans le dossier de morceaux courant. |
| `show-piece` | Affiche la structure du morceau (sections, accords par mesure, nombre de notes de mélodie). |

Trois morceaux d'exemple sont fournis dans `Pieces/` (trois modes différents, 4 à 6 accords
chacun avec une ligne mélodique).

## 2. Jouer un morceau

```
play
```

Joue le morceau courant. En mode `watch` pendant la lecture, on voit apparaître :
- **Le déroulé de la composition** — la liste des accords du morceau, celui en cours de
  lecture surligné entre crochets.
- **Un second clavier**, « Clavier composé, en cours de jeu » — montre les notes que le
  morceau est en train de jouer, colorées de la même façon que le clavier d'écoute (voir
  §5), avec la ligne de marqueurs du mode de la section en cours.

## 3. Sources d'entrée — le menu « Source »

Trois façons de « jouer » des notes dans l'application, chacune avec ses propres limites :

### 3.1 — Source MIDI (un vrai clavier/instrument MIDI)

| Commande | Effet |
|---|---|
| `sources` | Liste les sources MIDI visibles (numérotées ; `*` marque celle sélectionnée). |
| `use-midi-source <n\|all>` | N'écoute qu'une seule source, ou revient à toutes (par défaut). |
| `listen` | Écoute le MIDI, avec le son produit par l'application (synthétiseur intégré ou son chargé, voir §7). |
| `listen --listen-only` | Écoute sans faire sonner l'appli — utile si le clavier fait déjà son propre son. |
| `stop-listen` | Arrête l'écoute MIDI. |

### 3.2 — Source clavier (le clavier de l'ordinateur comme piano virtuel)

```
keyboard-source
```

Bascule ce mode (une deuxième fois pour le désactiver). Utile en mode `watch` uniquement.
Disposition des touches — identique à « Musical Typing » de GarageBand, pour rester
familière :

```
Touches altérées :   W  E     T  Y  U     O  P
Touches blanches :  A  S  D  F  G  H  J  K  L  ;
```

`A` joue le Do (C4), et ainsi de suite en montant.

**Limite importante, propre au terminal** : un terminal ne détecte jamais le relâchement
d'une touche — seulement qu'elle a été tapée. Chaque frappe déclenche donc une note « pincée »
qui s'éteint automatiquement après ~300 ms, plutôt qu'un vrai maintien tant qu'on garde le
doigt appuyé. Ce n'est pas un bug à corriger : c'est une limite du terminal lui-même.

**Pendant que cette source est active, les raccourcis-lettre du menu sont désactivés** (les
lettres jouent des notes à la place). Pour revenir au menu : appuie sur **Échap**. La
navigation aux flèches, Entrée et Échap fonctionne normalement une fois dans le menu.

### 3.3 — Source micro (détection de note(s) par microphone)

```
microphone-source
```

Bascule ce mode. Utilise le microphone par défaut et détecte la ou les notes jouées par
transformée de Fourier (FFT) — **peut détecter plusieurs notes en même temps**, donc
reconnaître un accord joué à la voix ou à l'instrument devant le micro.

**Champ « Micro » dans `status`/`watch`** — toujours affiché avec le niveau brut capté, même
en silence :
- `Micro: (coupée)` — la source n'est pas activée.
- `Micro: (silence, niveau 0.0010)` — activée, rien de détecté en ce moment.
- `Micro: C4 E4 G4 (niveau 0.0376)` — un accord détecté (ici, do-mi-sol).

**Si le niveau reste proche de zéro même en faisant du bruit** (dans `status`, un message
d'aide apparaît automatiquement) :
1. Vérifier que le micro n'est pas coupé (mute), et que c'est le bon périphérique d'entrée
   choisi dans les Réglages Système.
2. Vérifier la permission microphone : **Réglages Système > Confidentialité et sécurité >
   Microphone** — l'application (le terminal qui a lancé le binaire) doit y être autorisée.
   C'est la cause la plus fréquente d'un micro qui « ne réagit à rien ».
3. Si le niveau monte un peu mais reste toujours sous ~0.003, augmenter le volume d'entrée
   dans **Réglages Système > Son > Entrée**, ou se rapprocher/parler plus fort.

**Limites assumées** : la détection est monophonique-ou-presque — une heuristique de pics
spectraux, pas une vraie transcription d'accords. Elle fonctionne bien sur un accord clair
(testé avec un vrai accord de Do majeur joué physiquement), mais peut se tromper sur des
sons plus denses ou riches en harmoniques (peut confondre une harmonique avec une vraie
note). Ne fait **jamais** sonner ce qu'elle détecte à travers l'application elle-même — pour
éviter que le micro ne capte le haut-parleur en boucle.

## 4. Simuler des notes sans matériel

```
press <hauteur 0-127>
release <hauteur 0-127>
```

Utile pour tester sans clavier MIDI branché.

## 5. Reconnaissance d'accords et de modes

Dès qu'une source d'écoute est active (MIDI, clavier ordinateur ou micro), l'application
essaie en permanence de reconnaître :
- **L'accord tenu** (`Chord` dans `status`/`watch`) — basé sur les notes réellement tenues
  en même temps.
- **Le ou les modes/gammes en cours** (`Modes`) — basé sur un historique pondéré des notes
  récemment jouées (une gamme se joue en général mélodiquement, pas en accord plaqué).

Sur le clavier affiché en mode `watch` :
- **Magenta** : la fondamentale de l'accord reconnu.
- **Jaune** : les autres notes de l'accord.
- **Vert** : une note tenue mais hors de l'accord reconnu.
- **Blanc** : une note tenue sans accord reconnu du tout.
- **Ligne cyan au-dessus du clavier** : les notes appartenant au mode détecté.

## 6. Composer à partir d'un texte, avec une IA

Menu « IA » (ou commandes équivalentes) :

| Étape | Commande |
|---|---|
| 1. Nouveau morceau vierge | `new-piece <titre>` |
| 2. Coller un texte (poème, paroles…) | `paste-text` (terminer par une ligne vide) |
| 3. Choisir un dossier de connexions LLM | `llm-connections <dossier>` (par défaut : `LLMConnections/`) |
| 4. Choisir une connexion | `use-llm <numéro ou nom>` |
| 5. Composer | `compose` |
| 6. Voir le résultat | `show-piece` |

Trois connexions d'exemple sont fournies dans `LLMConnections/` :
- `ollama-local.json` — un serveur Ollama local, pas de clé.
- `openai-compatible.json` — OpenAI ou tout serveur compatible (LM Studio, llama.cpp…),
  nécessite `OPENAI_API_KEY` dans l'environnement.
- `anthropic-claude.json` — Claude, nécessite `ANTHROPIC_API_KEY` dans l'environnement.

**Aucun fichier de connexion ne contient de clé réelle** — seulement le nom de la variable
d'environnement à définir avant de lancer l'application. La réponse du modèle est toujours
validée avant d'être utilisée (gamme/accord invalide, note hors plage → rejetés avec un
avertissement plutôt qu'acceptés tels quels).

## 7. Choisir un instrument

```
samples <dossier>          # liste les .sf2/.dls/.aupreset du dossier (par défaut SoundFonts/)
use-sample <numéro ou nom>
```

Remplace le synthétiseur de base par un son chargé depuis un fichier SoundFont/DLS/aupreset.

## 8. Le mode `watch` — tableau de bord et menu façon DOS

```
watch
```

Occupe le terminal avec un écran figé qui se redessine en direct. Ctrl+C pour revenir au
mode ligne de commande normal.

**Le menu** : une barre de menus en haut de l'écran, façon interface DOS graphique de
l'époque.
- **Ouvrir un menu** : taper la lettre soulignée du menu, ou naviguer aux flèches ← →.
- **Se déplacer dans un menu ouvert** : flèches ↑ ↓, flèches ← → pour changer de menu.
- **Valider** : Entrée.
- **Fermer/revenir** : Échap.

Menus disponibles :

| Menu | Contenu |
|---|---|
| **Fichier** | Charger la démo, choisir un dossier de morceaux, charger un morceau, sauvegarder, sauvegarder sous, quitter. |
| **Lecture** | Jouer. |
| **Source** | Source MIDI (lister), choisir une source MIDI, Source clavier, Source micro. |
| **Écoute** | Écouter (avec son), Écouter (sans son), Arrêter l'écoute. |
| **Instrument** | Choisir un dossier de sons, choisir un son. |
| **IA** | Nouveau morceau, coller un texte, choisir un dossier de connexions LLM, choisir une connexion LLM, composer, voir le morceau. |

Une action de menu bascule temporairement en mode d'écran normal (pour pouvoir répondre à
ses questions), puis revient au tableau de bord une fois terminée (« Entrée pour revenir »).

**Ce que montre le tableau de bord**, du haut vers le bas :
- Barre de menu.
- Piece / Fichier / Playing / Source MIDI / Listening / Micro.
- Accord détecté (`Chord`) / Modes détectés (`Modes`).
- Dernier événement MIDI reçu.
- Notes du mode détecté (à plat).
- **Clavier joué** (C3–B5) — ce qui est actuellement tenu, toutes sources confondues.
- *Pendant la lecture d'un morceau uniquement* : le déroulé de la composition, puis un
  second clavier montrant ce que le morceau est en train de jouer.

## Liste complète des commandes

```
help                    affiche l'aide
load-demo               charge le morceau de démonstration (ii-V-I)
pieces <dossier>        liste les fichiers .json (morceaux) du dossier
use-piece <n|nom>       charge un morceau
load <chemin.json>      charge un morceau depuis un chemin explicite
save                    resauvegarde le morceau courant
save-as <nom>           sauvegarde sous un nouveau nom
play                    joue le morceau courant
sources                 liste les sources MIDI visibles (numérotées)
use-midi-source <n|all> n'écoute qu'une seule source, ou toutes
listen [--listen-only]  écoute le MIDI (avec ou sans son produit par l'appli)
stop-listen             arrête l'écoute MIDI
keyboard-source         bascule la source clavier (touches -> notes, dans 'watch')
microphone-source       bascule la source micro (détection par FFT, plusieurs notes)
press <hauteur>         simule l'appui d'une touche (0-127), sans matériel MIDI
release <hauteur>       simule le relâchement d'une touche
samples <dossier>       liste les fichiers .sf2/.dls/.aupreset du dossier
use-sample <n|nom>      charge l'instrument
new-piece <titre>       démarre un morceau vierge
paste-text              colle un texte (poème...), terminé par une ligne vide
llm-connections <dir>   liste les connexions LLM (.json) du dossier
use-llm <n|nom>         choisit une connexion LLM
compose                 demande à l'IA de composer à partir du texte collé
show-piece              affiche la structure du morceau courant
status                  affiche l'état courant
watch                   écran fixe qui se met à jour en direct (Ctrl+C pour revenir)
quit                    quitte
```

## Dépannage rapide

| Symptôme | Piste |
|---|---|
| Le micro ne détecte jamais rien | Vérifier la permission microphone (Réglages Système > Confidentialité et sécurité > Microphone) et le niveau affiché — voir §3.3. |
| Les lettres tapées en `watch` ouvrent un menu au lieu de jouer une note | La « Source clavier » n'est pas activée — `keyboard-source` (ou menu Source). |
| Impossible de sortir de « Source clavier » pour ouvrir un menu | Appuyer sur **Échap**. |
| Une note reste affichée/jouée sans s'arrêter après `play` | Devrait être corrigé (filet de sécurité en fin de lecture) — si le problème réapparaît, le signaler. |
| Le clavier ASCII scintille ou se déforme | Devrait être corrigé (largeur de ligne bornée) — si ça persiste, vérifier la largeur du terminal (≥ 80 colonnes recommandé). |
| `compose` échoue avec une erreur réseau | Vérifier que le serveur (Ollama local) tourne, ou que la variable d'environnement de clé API est bien définie pour la connexion choisie. |
