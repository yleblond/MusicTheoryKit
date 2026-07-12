# Guide utilisateur — Music Improv Assistant

Manuel d'utilisation de l'application en ligne de commande, dans son état à la fin de la
session du 2026-07-12. Un terme ambigu ou peu clair ? Voir `Docs/GLOSSAIRE.md`.

## Lancer l'application

Depuis le dossier `MusicTheoryKit/` :

```sh
swift run JamShack
```

Au démarrage, l'application charge automatiquement les dossiers de travail par défaut, situés
à côté de `MusicTheoryKit/` et organisés en trois racines : `Settings/` (palettes de couleur,
progressions d'accords, connexions LLM — voir §13/§6/menu **JamShack > Choisir dossier de
réglages...**), `User/` (morceaux `Pieces/`, scènes `Scenes/`, guides musicaux `Sequences/`,
soundtracks `SoundTracks/`, composition IA `Composition IA/`), `Library/` (`SoundFonts/`) —
pas besoin de les indiquer à chaque lancement.

Trois modes d'utilisation (voir §8) :
- **Le mode `Command`** : tape une commande, appuie sur Entrée, lis le résultat. C'est le
  mode par défaut au démarrage.
- **Le mode `run`** : un tableau de bord fixe, focalisé sur l'activité musicale en direct
  (claviers, accords), avec un menu déroulant façon DOS. On y entre avec la commande `run`,
  on en sort avec la touche **q**.
- **Le mode `config`** : même principe, focalisé sur la configuration active et le détail du
  morceau chargé. Commande `config`, touche **q** pour sortir.

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

Joue le morceau courant. En mode `run` pendant la lecture, on voit apparaître :
- **Le déroulé de la composition** — la liste des accords du morceau, celui en cours de
  lecture surligné entre crochets.
- **Un second clavier**, « Clavier composé, en cours de jeu » — montre les notes que le
  morceau est en train de jouer, colorées de la même façon que le clavier d'écoute (voir
  §5), avec la ligne de marqueurs du mode de la section en cours.

## 3. Sources d'entrée — les pistes (« tracks »)

Chaque source d'entrée est une **piste** indépendante, avec sa propre écoute, son propre son
(sauf le micro) et sa propre reconnaissance d'accord/mode — écouter deux pistes à la fois,
c'est voir deux claviers séparés, chacun avec son propre accord détecté. Les pistes
possibles :

| Id à taper | Piste | Peut avoir du son ? |
|---|---|---|
| `midi` | Tout le MIDI visible, fusionné en un seul flux (mode MIDI par défaut) | Oui |
| `midi:1`, `midi:2`, ... | Un port MIDI précis (uniquement en mode MIDI « individuel », voir §3.1) | Oui |
| `clavier` | Le clavier de l'ordinateur, tapé comme un piano virtuel (voir §3.2) | Oui |
| `micro` | Le microphone, détection de note(s) par FFT (voir §3.3) | **Non** (voir plus bas) |

Commandes communes à toutes les pistes :

| Commande | Effet |
|---|---|
| `tracks` | Liste toutes les pistes et leur état (écoute, son, instrument). |
| `track <id> on` | Démarre l'écoute de cette piste (recomence à reconnaître accord/mode). |
| `track <id> off` | Arrête l'écoute de cette piste (efface son accord/mode en cours). |
| `track <id> son on` | Fait sonner cette piste à travers l'application (impossible sur `micro`). |
| `track <id> son off` | Coupe le son de cette piste (sans oublier l'instrument choisi). |
| `track <id> instrument <n\|nom>` | Charge un instrument (voir §7) sur cette piste et active son son. |

Écoute et son sont **indépendants** : on peut écouter une piste sans la faire sonner (par
exemple un vrai clavier MIDI qui fait déjà son propre son), ou lui donner un instrument
particulier différent des autres pistes actives — chaque piste avec le son activé sonne avec
son propre timbre, simultanément aux autres.

### 3.1 — MIDI : fusionné ou individuel

```
midi-mode fusionne       # une seule piste 'midi', qui écoute toutes les sources visibles
midi-mode individuel     # une piste par port MIDI visible ('midi:1', 'midi:2', ...)
```

Menu **JamShack > Mode MIDI: fusionné/individuel** fait la même chose.

Changer de mode reconstruit la liste des pistes MIDI (et arrête celles qui écoutaient) —
utile pour distinguer un vrai clavier MIDI d'un bus IAC virtuel non désiré, par exemple, en
n'écoutant que le port qui nous intéresse (`track midi:2 on`).

### 3.2 — Piste clavier (le clavier de l'ordinateur comme piano virtuel)

```
track clavier on
```

Active à la fois l'écoute de cette piste et, en mode `run`, l'interception des touches
du clavier physique comme des notes. Disposition des touches — identique à « Musical
Typing » de GarageBand, pour rester familière :

```
Touches altérées :   W  E     T  Y  U     O  P
Touches blanches :  A  S  D  F  G  H  J  K  L  ;
```

`A` joue le Do (C4), et ainsi de suite en montant.

**Limite importante, propre au terminal** : un terminal ne détecte jamais le relâchement
d'une touche — seulement qu'elle a été tapée. Chaque frappe déclenche donc une note « pincée »
qui s'éteint automatiquement après ~300 ms, plutôt qu'un vrai maintien tant qu'on garde le
doigt appuyé. Ce n'est pas un bug à corriger : c'est une limite du terminal lui-même.

**Pendant que cette piste écoute, les raccourcis-lettre du menu sont désactivés en mode
`run`** (les lettres jouent des notes à la place). Pour revenir au menu : appuie sur
**Échap**. La navigation aux flèches, Entrée et Échap fonctionne normalement une fois dans
le menu. `track clavier off` rend les raccourcis-lettre au menu.

### 3.3 — Piste micro (détection de note(s) par microphone)

```
track micro on
```

Utilise le microphone par défaut et détecte la ou les notes jouées par transformée de
Fourier (FFT) — **peut détecter plusieurs notes en même temps**, donc reconnaître un accord
joué à la voix ou à l'instrument devant le micro.

**Champ « Micro » dans `status`/`run`** — toujours affiché avec le niveau brut capté, même
en silence :
- `Micro: (coupée)` — la piste n'écoute pas.
- `Micro: (silence, niveau 0.0010)` — écoute, rien de détecté en ce moment.
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
note). Cette piste ne peut **jamais** avoir de son (`track micro son on` échoue
volontairement) : elle capte déjà un vrai son acoustique, et la faire aussi sonner à travers
l'application risquerait un effet larsen (le micro capterait le haut-parleur en boucle).

## 4. Simuler des notes sans matériel

```
press <hauteur 0-127>
release <hauteur 0-127>
```

Utile pour tester sans clavier MIDI branché.

## 5. Reconnaissance d'accords et de modes

Chaque piste en écoute (MIDI, clavier ordinateur, micro) a sa **propre** reconnaissance,
indépendante des autres — écouter `midi` et `clavier` en même temps affiche deux accords
détectés séparément, pas un seul mélangé. Pour chaque piste, l'application essaie en
permanence de reconnaître :
- **L'accord tenu** (`Chord`) — basé sur les notes réellement tenues en même temps sur
  cette piste.
- **Le ou les modes/gammes en cours** (`Modes`) — basé sur un historique pondéré des notes
  récemment jouées sur cette piste (une gamme se joue en général mélodiquement, pas en
  accord plaqué).

Sur le clavier de chaque piste affiché en mode `run` :
- **Magenta** : la fondamentale de l'accord reconnu.
- **Jaune** : les autres notes de l'accord.
- **Vert** : une note tenue mais hors de l'accord reconnu.
- **Blanc** : une note tenue sans accord reconnu du tout.
- **Ligne cyan au-dessus du clavier** : les notes appartenant au mode détecté.

## 6. Composer à partir d'un texte, avec une IA

### Le plus simple : l'assistant « Décrire le morceau... » du menu Composition

Menu **Composition > Décrire le morceau...** guide tout le processus en une seule action :
il demande le **titre** du morceau, puis sa **description** (poème, paroles… terminée par
une ligne vide), puis des **indications de style** facultatives (ex. « romantique, mode
mineur »), et lance directement la composition. Le morceau obtenu porte le titre tapé (pas
celui que l'IA aurait choisi elle-même) ; la description et les indications sont toutes les
deux envoyées à l'IA. **Composition > Voir la description** affiche à tout moment le titre,
la description et les indications actuellement en mémoire.

Ça suppose qu'une connexion LLM a déjà été choisie (menu **JamShack**, voir plus bas) — sinon
l'assistant s'arrête avec une erreur claire à l'étape de composition, sans rien perdre : la
description et les indications restent en mémoire, il suffit de choisir une connexion puis de
relancer **Composition > Composer à partir de la description**.

### Étape par étape (ou en ligne de commande)

| Étape | Commande |
|---|---|
| 1. Titre du morceau, facultatif | `title <texte>` (vide efface) |
| 2. Coller la description (poème, paroles…) | `paste-text` (terminer par une ligne vide) |
| 3. Indications de style, facultatif | `indications <texte>` (vide efface) |
| 4. Choisir un dossier de réglages (connexions LLM, entre autres) | `settings <dossier>` (par défaut : `Settings/` ; menu **JamShack**) |
| 5. Choisir une connexion | `use-llm <numéro ou nom>` (menu **JamShack**) |
| 6. Voir ce qui sera envoyé | `show-description` (titre/description/indications) |
| 7. Composer | `compose [titre]` (le titre, s'il est donné, remplace celui que l'IA aurait choisi) |
| 8. Voir le résultat | `show-piece` (menu **Morceaux**) |

`new-piece <titre>` reste disponible séparément pour démarrer un morceau **vierge** (sans
IA, à composer à la main plus tard) — l'assistant "Décrire le morceau..." ne l'utilise pas,
il compose directement.

**Le prompt envoyé à l'IA n'est jamais chargé/remplacé en un bloc** — il est toujours
recomposé à partir de trois éléments gérés séparément : la **phrase de cadrage**, les
**données** (la description ci-dessus, ou l'enregistrement pour une soundtrack, voir §10), et
les **indications de style**. Chacun se sauvegarde/recharge indépendamment ; seul le résultat
final (le prompt complet) se consulte et s'exporte, jamais ne se recharge comme un tout — voir
les trois sous-sections suivantes.

### Sauvegarder et recharger une description

Une fois tapés, le titre/la description/les indications de style peuvent être sauvegardés
comme un tout, pour les réutiliser plus tard sans tout retaper :

```
save-description-as <nom>      # sauvegarde titre+description+indications actuels sous ce nom
save-description               # resauvegarde sous le meme nom (une fois deja sauvegarde une fois)
use-description <numero|nom>   # recharge une description sauvegardee (remplace titre/description/indications en cours)
```

Menu **Composition > Charger une description.../Sauvegarder la description sous.../Sauvegarder
la description** fait la même chose. Sauvegardée dans le sous-dossier `composition
Descriptive` du dossier de composition IA (voir plus bas) — un simple fichier `.json` (titre +
texte + indications), à ne pas confondre avec un morceau composé (`.json` aussi, mais dans le
dossier `Pieces/`, structuré en mesures/accords). Pas d'équivalent pour la soundtrack — c'est
un enregistrement déjà sauvegardé en tant que tel (§10), pas un texte à décrire.

Trois connexions d'exemple sont fournies dans `Settings/LLMConnections/` :
- `ollama-local.json` — un serveur Ollama local, pas de clé.
- `openai-compatible.json` — OpenAI ou tout serveur compatible (LM Studio, llama.cpp…),
  nécessite `OPENAI_API_KEY` dans l'environnement.
- `anthropic-claude.json` — Claude, nécessite `ANTHROPIC_API_KEY` dans l'environnement.

**Aucun fichier de connexion ne contient de clé réelle** — seulement le nom de la variable
d'environnement à définir avant de lancer l'application. La réponse du modèle est toujours
validée avant d'être utilisée (gamme/accord invalide, note hors plage → rejetés avec un
avertissement plutôt qu'acceptés tels quels).

### Modifier la phrase de cadrage

La **phrase de cadrage** (le tout premier paragraphe du prompt, avant le schéma JSON) se gère
à part — l'éditer ne touche jamais au schéma ni aux données, donc pas de risque de casser la
validation de la réponse :

```
show-text-framing              # affiche la phrase de cadrage active (texte)
show-soundtrack-framing        # idem pour la soundtrack

set-text-framing                # colle une nouvelle phrase (terminer par une ligne vide)
set-soundtrack-framing

save-text-framing <nom>         # sauvegarde la phrase active, dans Cadrage Composition Descriptive/
save-soundtrack-framing <nom>   # dans Cadrage Composition Soundtrack/
use-text-framing <numero|nom>   # recharge une phrase sauvegardee
use-soundtrack-framing <numero|nom>
reset-text-framing              # revient a la phrase par defaut
reset-soundtrack-framing
```

Menu **Composition**/**Enregistrement > Voir/Modifier/Sauvegarder/Charger la phrase de
cadrage.../Revenir à la phrase de cadrage par défaut** fait la même chose.

### Indications de style pour la soundtrack

Composer à partir d'une soundtrack n'avait jusqu'ici pas de notion d'indications de style
(contrairement au texte, qui les bundle dans sa description) — ajoutées comme leur propre
élément sauvegardable/rechargeable, puisqu'une soundtrack n'a pas de "description" où les
loger :

```
show-soundtrack-instructions            # affiche les indications actives
set-soundtrack-instructions [texte]     # les change (vide efface)
save-soundtrack-instructions <nom>      # sauvegarde, dans Indications Soundtracks/
use-soundtrack-instructions <numero|nom>
reset-soundtrack-instructions           # efface (aucune)
```

Menu **Enregistrement > Voir/Modifier/Sauvegarder/Charger les indications de style.../Revenir
aux indications de style par défaut** fait la même chose.

### Voir et exporter le prompt complet

Le prompt complet — cadrage + schéma JSON + données + indications, tel qu'il serait réellement
envoyé — se consulte à tout moment, et s'**exporte** pour référence/débogage (jamais rechargé :
voir plus haut pourquoi) :

```
show-text-prompt               # affiche le prompt exact qu'utiliserait 'compose' maintenant
show-soundtrack-prompt         # idem pour 'compose-piece-from-soundtrack'

export-text-prompt <nom>       # ecrit le prompt courant dans Export/, sans effet sur la composition
export-soundtrack-prompt <nom>
```

Menu **Composition**/**Enregistrement > Voir le prompt de composition.../Exporter le prompt de
composition...** fait la même chose. **Ce que contient le prompt** : la phrase de cadrage,
puis le schéma JSON exact attendu en réponse (titre/tempo/tonalité/accords/mélodie, avec la
liste réelle des gammes/accords disponibles — c'est ce schéma qui permet de valider la réponse
de l'IA plutôt que de lui faire confiance), puis les données (texte collé ou événements de la
soundtrack) et les indications.

### Le dossier de composition IA

Tous ces éléments (phrases de cadrage, descriptions, indications soundtrack, exports) vivent
sous un même dossier racine :

```
prompts <dossier>   # pointe le dossier de composition IA (par defaut "User/Composition IA/"), cree ses sous-dossiers si absents
```

Menu **JamShack > Choisir dossier de composition IA...** fait la même chose. Sous-dossiers
créés automatiquement : `Cadrage Composition Descriptive/`, `Cadrage Composition Soundtrack/`,
`composition Descriptive/` (descriptions), `Indications Soundtracks/`, `Export/`.

## 7. Choisir un instrument

```
samples <dossier>          # liste les .sf2/.dls/.aupreset du dossier (par défaut SoundFonts/)
use-sample <numéro ou nom>
```

Remplace le synthétiseur de base par un son chargé depuis un fichier SoundFont/DLS/aupreset —
c'est le son **par défaut** utilisé par toute piste/accord qui n'a pas son propre instrument.

### Un instrument différent par piste mélodique et par accompagnement

Un morceau (`Piece`) peut associer un fichier son différent à chaque piste mélodique et à
l'accompagnement d'accords de chaque section, pour un rendu plus riche qu'un seul synthé
partagé par tout le morceau :

```
show-piece                                          # affiche les numeros de section/piste
set-track-instrument <section> <piste> <nom-sample>  # ex: set-track-instrument 1 1 mcb.sf2
set-chord-instrument <section> <nom-sample>          # ex: set-chord-instrument 1 East_West_-_The_Ultimate_Piano_Collection.sf2
save                                                 # ou save-as <nom> — sinon le changement ne survit pas au rechargement
```

Menu **Morceaux > Choisir le son d'une piste.../Choisir le son des accords d'une section...**
fait exactement la même chose que les deux commandes ci-dessus.

- `<nom-sample>` est un nom de fichier du dossier de sons courant (le même que `samples`/
  `use-sample`) — `mcb.sf2`, `Nokia_Tongbao_Bank__Series_30__8-bit.sf2`, etc.
- Passer une chaîne vide (`set-track-instrument 1 1 ""`) revient au son par défaut.
- Un fichier introuvable ne fait pas échouer la lecture : `play` affiche un avertissement
  (« instrument '...' introuvable — son par défaut utilisé ») et continue avec le
  synthétiseur de base pour cette piste/ces accords uniquement.
- Chaque instrument distinct sonne via son propre moteur audio, indépendant des autres —
  plusieurs pistes/accords peuvent donc sonner avec des timbres vraiment différents en même
  temps (même mécanisme que les pistes d'entrée en direct, voir §3).
- Les morceaux créés avant cette fonctionnalité (ou par l'IA, voir §6) n'ont pas
  d'instrument propre par défaut — ils sonnent exactement comme avant, avec le son choisi
  par `use-sample`.

## 8. Les écrans `run`/`config` — tableaux de bord et menu façon DOS

Trois modes d'affichage coexistent :
- **Command** — le mode par défaut, celui de toutes les commandes de ce guide (le prompt `>`).
- **`run`** — écran figé, redessiné en direct, focalisé sur **l'activité musicale en cours** :
  claviers des pistes en écoute, accord/mode détectés, clavier de lecture d'un morceau/d'un
  enregistrement.
- **`config`** — écran figé, redessiné en direct, focalisé sur **l'état de la session et le
  morceau actif** : dossiers/connexions configurés, drapeaux (lecture/enregistrement...), et
  la structure complète du morceau chargé (sections, accords, instruments).

```
run       # activite musicale en direct
config    # configuration + detail du morceau actif
```

Les deux occupent le terminal jusqu'à la touche **q** (retour au mode Command) — Ctrl+C
fonctionne toujours aussi, en secours, mais **q** est plus doux et suffit dans l'immense
majorité des cas. Séparer les deux évite un tableau de bord unique qui grossit sans fin à
mesure que l'application gagne des fonctionnalités — chaque écran reste court et rapide à
lire pour ce qu'on est en train de faire (jouer, vs. vérifier la configuration).

**Passer de l'un à l'autre sans repasser par Command** : appuie sur **Tab** à tout moment
dans `run`/`config` — bascule directement vers l'autre écran, y compris si un menu est
ouvert (le menu déroulé reste affiché, seul le contenu en dessous change).

**Le menu** : une barre de menus en haut de l'écran, façon interface DOS graphique de
l'époque.
- **Ouvrir un menu** : taper la lettre soulignée du menu, ou naviguer aux flèches ← →.
- **Se déplacer dans un menu ouvert** : flèches ↑ ↓, flèches ← → pour changer de menu.
- **Valider** : Entrée.
- **Fermer le menu déroulé** : Échap.
- **Changer d'écran (`run` ↔ `config`)** : Tab, sans passer par Échap ni par Command.
- **Quitter l'écran, retour à Command** : **q** (fonctionne même si un menu est ouvert). Ctrl+C
  marche aussi, gardé en secours, mais pas nécessaire pour un usage normal.

Menus disponibles :

| Menu | Contenu |
|---|---|
| **JamShack** | Menu principal (premier de la barre, s'ouvre par défaut) : (1) infos (status), aide ; (2) choisir chacun des dossiers (morceaux/sons/soundtracks/**guides musicaux**/**scènes**/**composition IA**/**réglages** — ce dernier remplace l'ancien choix indépendant de dossier de connexions LLM ; palettes de couleur, progressions d'accords et connexions LLM vivent tous sous ce même dossier de réglages, par défaut `Settings/`) ; (3) choisir une connexion LLM, isolée dans son propre groupe ; (3bis) choisir la palette de couleur (voir §13) ; (4) mode MIDI fusionné/individuel ; (5) démarrer/arrêter la console web (voir §11) et le clavier virtuel (voir §12) ; (6) quitter. Point d'entrée unique pour la configuration de la session — dossiers, connexion LLM et mode MIDI ne se réglent que depuis ce menu. |
| **Scene** | Voir le plan de scène en arbre (`scene-tree`) — l'application, ses instruments locaux, l'état de la console web et du clavier virtuel, et en mode serveur la liste des clients connectés avec leurs propres instruments (voir §9) —, activer/arrêter un instrument, *séparateur*, activer/désactiver le son d'un instrument, *séparateur*, choisir un son pour un instrument, *séparateur*, sauvegarder/charger une scène (la configuration complète des instruments : actif, son actif, quel son), *séparateur* **Rôles** — nouvelle scène (à base de rôles), lister les rôles, ajouter un rôle, attacher un instrument à un rôle, détacher un rôle, choisir le son d'un rôle (voir §15 pour le concept). Les actions qui demandent de choisir un instrument présentent la liste numérotée (voir §3) — répondre par le numéro évite d'avoir à retaper `midi:1`/`clavier`/etc. |
| **Guide Musicaux** | Voir l'écran Guide Musical, *séparateur*, créer un nouveau guide musical (propose d'ajouter un mode en boucle jusqu'à laisser la tonique vide) / ajouter un mode au guide musical en cours — chaque ajout propose d'abord la liste numérotée des **33 gammes/modes des 7 familles** de `MusicTheoryKit` (les 7 modes majeurs usuels, puis mineur mélodique, mineur harmonique, majeur harmonique, diminué, tons entiers, augmenté — un numéro suffit, plus besoin de connaître l'id écrit), chaque ligne affichant les deux appellations (nom courant et nom systématique, ex. « Altered / Super Locrian / Ionian #1 »), puis une liste numérotée de progressions d'accords (blues, ii-V-I, cadence andalouse…, tirée de `chordprogressions.json` dans le dossier de réglages) à attacher à cette étape, ou de laisser vide pour n'en attacher aucune, *séparateur*, charger un guide musical / sauvegarder le guide musical (sous...), *séparateur*, démarrer/arrêter le guide musical — aussi accessible directement par la barre d'espace une fois sur l'écran Guide Musical. Note : la roue des quintes n'affiche le contour diatonique/chiffrage romain que pour les 7 modes majeurs — un mode d'une autre famille reste jouable et reconnu, juste sans ce contour sur la roue. |
| **Enregistrement** | Démarrer/arrêter un enregistrement, voir l'enregistrement, jouer l'enregistrement, *séparateur*, charger/sauvegarder l'enregistrement, *séparateur*, composer un morceau à partir de l'enregistrement en le nommant (voir §10), *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser la phrase de cadrage, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser les indications de style, *séparateur*, voir/exporter le prompt de composition (voir §6). |
| **Morceaux** | Quatre groupes, séparés par des traits : (1) écouter/voir le morceau ; (2) choisir le son par défaut de lecture, ou le son d'une piste/des accords d'une section (voir §7 — la structure affichée numérote les sections et les pistes, pour savoir directement quel numéro saisir) ; (3) charger la démo, charger un morceau, sauvegarder le morceau, sauvegarder le morceau sous ; (4) **Assistant IA** — pour l'instant un intitulé de sous-section réservé, sans action, en attente d'une future fonction de modification par dialogue (« plus vite », « moins vite »…) applicable à n'importe quel morceau. |
| **Composition** | Décrire le morceau (assistant titre → description → indications → composition, voir §6), composer à partir de la description, voir la description, *séparateur*, charger une description/sauvegarder la description (sous...), *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser la phrase de cadrage, *séparateur*, voir/exporter le prompt de composition. |
| **Jam Session** | Démarrer/arrêter une jam session, rejoindre une jam session, trouver une jam session (découverte), quitter la jam session — session collaborative (voir §9). Les trois premiers items demandent le pseudo à afficher aux autres avant de continuer. |

Les *séparateurs* sont de simples traits horizontaux dans le menu déroulant, pour grouper des
items apparentés — jamais sélectionnables (les flèches ↑ ↓ passent par-dessus). Une
**sous-section nommée** (ex. « Assistant IA » dans Morceaux) fonctionne pareil, mais affiche
un titre au lieu d'un simple trait — utile quand un menu n'a pas de vrais sous-menus imbriqués.

Une action de menu bascule temporairement en mode d'écran normal (pour pouvoir répondre à
ses questions), puis revient au tableau de bord une fois terminée (« Entrée pour revenir »).

**Ce que montre `run`**, du haut vers le bas :
- Barre de menu (avec l'astuce clavier en dessous, tant qu'aucun menu n'est ouvert).
- Dernier événement MIDI reçu.
- *Pour chaque piste en écoute* : son nom, son état de son (ou le niveau du micro), l'accord
  détecté (`Chord`), les modes détectés (`Modes`), et son propre clavier (C3–B5).
- *Pendant la lecture d'un morceau ou d'un enregistrement* : le déroulé de la composition
  (morceau) puis un clavier montrant ce qui est en train de jouer.

**Ce que montre `config`**, du haut vers le bas :
- Barre de menu (même comportement).
- Piece / Fichier / Playing / Recording / Soundtrack / Reseau / Mode MIDI.
- Détail complet du morceau actif : titre, tempo, tonalité, puis chaque section (accords par
  mesure et instrument, pistes mélodiques et leur instrument) — le même contenu que
  `show-piece`, tenu à jour en direct.

## 9. Session collaborative — serveur et clients

Plusieurs personnes peuvent partager la même écoute/reconnaissance d'accords, un peu comme un
serveur de jeu en LAN : l'une héberge (« serveur »), les autres se connectent (« clients »),
et chacun voit les pistes de tout le monde apparaître dans sa propre liste de pistes.

### Choisir son pseudo

```
pseudo               # affiche le pseudo actuel (par defaut "player")
pseudo Marie Curie    # le change (plusieurs mots acceptes, pas besoin de guillemets)
```

Ce pseudo est envoyé aux autres participants dès qu'on héberge ou qu'on rejoint une session —
c'est ce qui permet à chacun de voir **qui** joue une piste distante, plutôt qu'un simple
identifiant UUID illisible. Menu **Jam Session > Demarrer une jam session.../Rejoindre une jam
session.../Trouver une jam session...** demandent systématiquement le pseudo en premier (vide =
garder celui déjà en place) — inutile de taper `pseudo` séparément si on passe par le menu.

### Héberger

```
server            # port 7777 par defaut
server 9000       # ou un port au choix
```

Accepte n'importe quel client qui atteint ce port — **il n'y a pour l'instant aucun mot de
passe ni chiffrement** : à réserver à un réseau de confiance (le même Wi-Fi/LAN, ou un VPN),
jamais exposé directement sur Internet. `stop-server` arrête l'hébergement.

Le serveur s'annonce automatiquement sur le réseau local (Bonjour) sous le nom du
participant (voir `localClientName`) — pas d'étape supplémentaire pour être visible via
`discover` (ci-dessous), même en gardant un simple `server` sans argument.

### Rejoindre — en connaissant déjà l'adresse

```
client                        # localhost:7777 par defaut
client 192.168.1.42            # meme port (7777), autre machine
client 192.168.1.42 9000       # host et port explicites
```

Toute piste déjà en écoute chez soi est annoncée immédiatement au serveur en rejoignant — pas
besoin de tout réactiver. `disconnect` quitte la session.

### Rejoindre — par découverte automatique

```
discover
```

Recherche les serveurs visibles sur le réseau local pendant quelques secondes, puis propose
une liste numérotée :

```
Recherche de serveurs sur le reseau local...
  1. player
  2. clavier-de-marie
Rejoindre quel serveur (numero, vide pour abandonner):
```

Tape le numéro pour rejoindre, ou laisse vide (Entrée) pour abandonner sans se connecter.
Menu **Jam Session > Decouvrir des serveurs...** fait exactement la même chose.

**Si `discover` ne trouve jamais rien** :
1. Vérifier qu'un `server` tourne bien de l'autre côté, sur le **même réseau local** (la
   découverte ne traverse pas un VPN ni un routeur vers un autre sous-réseau).
2. macOS peut demander une autorisation « Réseau local » au premier essai (Réglages Système
   > Confidentialité et sécurité > Réseau local) — l'accorder si elle apparaît.
3. En dernier recours, se connecter par adresse connue (`client <IP> <port>`, IP visible sur
   la machine qui héberge via `ifconfig`/Réglages Système > Réseau).

### Ce qui est partagé, et ce qui reste local

- **Les pistes de tout le monde apparaissent chez tout le monde** — `tracks`/`status`/`run`
  listent, en plus des pistes locales habituelles (`midi`, `clavier`, `micro`), une
  entrée par piste distante, sous la forme `remote:<identifiant>@<piste>` (copie-colle cet
  identifiant depuis la liste plutôt que de le retaper — c'est un UUID). À côté, suivi d'un
  tiret, le **pseudo** de son propriétaire (« — Marie Curie ») — voir « Choisir son pseudo »
  ci-dessus ; sans pseudo choisi par ce participant, rien ne s'affiche après le nom de piste.
- **La reconnaissance d'accord/mode d'une piste distante est calculée par le serveur**, pas
  recalculée chez chaque client — c'est lui qui « fait autorité ». Une piste distante ne peut
  donc pas être démarrée/arrêtée depuis ailleurs que sa propre machine (`track <id> on/off`
  échoue avec un message explicite si on essaie sur une piste `remote:...`).
- **Le son reste toujours une décision locale**, exactement comme pour n'importe quelle piste
  (voir §3) : `track remote:<id>@<piste> son on` et `track remote:<id>@<piste> instrument
  <n|nom>` fonctionnent normalement — si l'instrument demandé n'est pas disponible chez soi,
  ça reste sur le son par défaut, sans jamais forcer quoi que ce soit venant du réseau.
- **L'identifiant de participant est propre à ce lancement** de l'application (pas encore
  conservé d'un lancement à l'autre) — après un `quit`/relance, on rejoint comme un nouveau
  participant.

## 10. Enregistrement — le mode Soundtrack (événementiel)

Un second mode, à côté du `Piece` (mesures/accords, §1-§2) : un enregistrement **en temps
réel** d'une ou plusieurs pistes — juste « telle note, à tel instant en secondes » — sans
tempo, sans mesure. Les deux modes ne sont **pas interchangeables** : une Soundtrack ne se
charge pas comme un morceau, et réciproquement.

### Enregistrer

```
record start                  # capture toutes les pistes actuellement en ecoute
record start clavier          # ou seulement celles listees explicitement
...joue quelque chose (press/release, ou un vrai clavier MIDI)...
record stop
```

`record stop` affiche la durée et le nombre d'événements capturés, et la garde en mémoire
comme soundtrack courante (voir `show-soundtrack`).

### Jouer, sauvegarder, charger

```
play-soundtrack                     # rejoue la soundtrack courante, en temps reel
soundtracks <dossier>               # liste les .json (par defaut SoundTracks/)
use-soundtrack <numero ou nom>
save-soundtrack-as <nom>
show-soundtrack                     # titre, duree, nombre d'evenements, pistes capturees
```

En mode `run`, tant que la lecture est en cours, un troisième clavier apparaît
(« Clavier soundtrack, en cours de jeu ») — sans coloration accord/mode (une Soundtrack est
un enregistrement brut, pas un morceau analysé), juste les notes tenues.

Menu **Enregistrement** : les mêmes actions, avec des libellés en « enregistrement » plutôt
qu'en « soundtrack » (Jouer/Charger/Sauvegarder/Voir l'enregistrement) — même objet, juste un
nom plus parlant que le mot anglais dans l'interface.

### Déduire un Piece Model par IA

Menu **Enregistrement > Composer un morceau à partir de l'enregistrement...**.
À partir d'une soundtrack, essaie d'en déduire un tempo, une tonalité et une progression
d'accords plausibles, et crée le résultat comme un nouveau morceau (même validation stricte
que la composition à partir d'un texte, §6 — un ID de gamme/accord invalide est rejeté,
jamais injecté tel quel) :

```
compose-piece-from-soundtrack                    # 1 candidat par defaut, titre choisi par l'IA
compose-piece-from-soundtrack 3                  # 3 candidats independants
compose-piece-from-soundtrack 1 Mon Morceau      # nomme le morceau (et son fichier) soi-meme
```

Chaque candidat qui survit à la validation est sauvegardé comme un fichier de morceau à part
dans le dossier de morceaux (`<titre>-candidat-N.json` s'il y en a plusieurs) — à inspecter
ensuite avec `pieces`/`use-piece`/`show-piece` comme n'importe quel autre morceau. Le dernier
candidat généré devient aussi le morceau courant. Le titre (dernier argument, plusieurs mots
acceptés) remplace celui que l'IA aurait choisi — pour tous les candidats du même appel, s'il
y en a plusieurs, seul le suffixe `-candidat-N` les distingue alors.

Comme pour le texte, des **indications de style** facultatives peuvent orienter la
composition (`set-soundtrack-instructions <texte>`, ou menu **Enregistrement > Modifier les
indications de style...**) — voir §6 pour les détails (sauvegarde/rechargement, phrase de
cadrage, export du prompt complet).

**Pas encore possible** (prévu plus tard) : enregistrer une nouvelle soundtrack *pendant*
qu'un `Piece` joue, et l'intégrer directement dans ce morceau.

## 11. Console Web — suivre l'activité depuis un navigateur

Un second écran, en lecture seule, dans un navigateur — utile pour afficher l'activité
musicale (claviers, accords, modes) sur un autre écran/appareil que celui où tourne
l'application, sans repasser par le terminal. Ce n'est **pas** un quatrième mode d'affichage
au sens du §8 (Command/`run`/`config`) : c'est un petit serveur HTTP, indépendant, qui tourne
*en plus* de ce que fait déjà le terminal.

```
web-console 8080       # demarre la console web sur ce port (defaut 8080)
web-console stop       # arrete la console web
```

Menu **JamShack > Demarrer la console web.../Arreter la console web** fait la même chose (le
port est demandé, vide = 8080). Une fois démarrée, ouvre `http://localhost:<port>` dans un
navigateur (sur la même machine, ou une autre machine du même réseau local via l'adresse IP
de celle qui héberge) — la page se rafraîchit d'elle-même environ 4 fois par seconde, tant
qu'elle reste ouverte, sans rien à faire de plus.

**Ce qui s'affiche** : un clavier par piste en écoute (mêmes couleurs que le terminal — magenta
la fondamentale, jaune les autres notes de l'accord, vert une note tenue hors accord, une ligne
cyan pour le mode détecté — voir §5), sa portée musicale (voir plus bas) puis, juste en dessous,
l'accord/les modes détectés — et, pendant la lecture, le clavier du morceau ou de
l'enregistrement en cours. Un simple miroir de ce que montre l'écran `run` (§8) — la console
web n'a aucun contrôle ni menu, elle ne fait qu'afficher (pour jouer depuis un navigateur, voir
§12, une page distincte). Une piste `clavier-web:<id>` (voir §12) n'affiche jamais son
identifiant technique ici, seulement son alias — rien à taper depuis une page en lecture seule.

**Portée musicale** : sous chaque clavier (piste en écoute, morceau/enregistrement en lecture),
une petite portée à deux clés (sol et fa, Sol2-Do6) affiche, de gauche à droite, un **historique
des derniers accords/notes joués** (jusqu'à 20 événements) plutôt que seulement l'instant présent
— une note seule tenue sans accord reconnu compte comme un événement à part entière (en gris),
au même titre qu'un accord ; la durée réelle de chaque événement n'est pas encore prise en compte
(un retraitement futur, peut-être assisté par IA, pourrait l'ajouter). Pas d'armure — chaque
altération (dièse/bémol) est notée note par note, puisque le mode réellement joué n'est pas
toujours fiable en temps réel ; les noms de note utilisés sont toujours ceux, dièses uniquement,
déjà utilisés partout ailleurs dans l'app (roue des quintes, claviers) plutôt qu'une orthographe
théorique par tonalité. Défile horizontalement si besoin, comme les claviers.

**Disposition en deux colonnes** : le cercle des quintes à gauche, et à droite d'abord "le
clavier du mode" — celui du guide musical s'il est en cours (menu **Guide Musicaux**), sinon
celui du morceau/de l'enregistrement en cours de lecture — puis chaque piste active, la
sienne. Cette disposition est désormais la même que le guide soit actif ou non.

**Quatre onglets** : `Run` (ce qui précède — l'activité musicale en cours), `Scene` — le même
plan de scène qu'affiche `scene-tree` dans le terminal (voir §9), mais en liste imbriquée
plutôt qu'en dessin ASCII : l'application, ses instruments locaux, l'état de la console web et
du clavier virtuel, en mode serveur la liste des clients connectés avec leurs propres
instruments, et depuis peu les **rôles de la scène active** (voir §15) — `Commandes`, une
télécommande complète de l'application depuis le navigateur (voir §16) — et `Infos`, une
simple description statique de la page. Basculer d'un onglet à l'autre ne recharge pas la page.

**Largeur adaptative** : la page s'élargit pour profiter de l'espace disponible sur un grand
écran (cercle des quintes agrandi, largeur totale plafonnée pour rester lisible plutôt que de
s'étirer à l'infini), et repasse en une seule colonne sur un écran étroit ; chaque clavier,
de largeur fixe par nature, défile horizontalement dans son propre espace au lieu de casser
la page si la fenêtre est plus étroite que lui.

**Fonctionnement interne** (pour comprendre ce qu'on voit) : l'état affiché est recalculé côté
application environ toutes les 150ms et mis en cache — chaque `GET /state` du navigateur
renvoie juste ce dernier instantané, sans jamais recalculer quoi que ce soit à la demande.
Ça veut dire que **plusieurs navigateurs/onglets peuvent se connecter en même temps** (mono ou
multi-client, au choix), chacun à son propre rythme, sans surcharger l'application.

**Limites assumées pour cette première version** : pas de HTTPS ni d'authentification (même
mise en garde que pour **Jam Session**, §9 — à réserver à un réseau de confiance) ; pas de
connexion permanente (WebSocket/SSE), juste un sondage régulier côté navigateur — si la page
affiche « connexion perdue », vérifie que l'application tourne toujours et que
`web-console stop` n'a pas été appelé.

## 12. Clavier virtuel — jouer depuis un navigateur (souris/tactile/clavier)

Une seconde page web, distincte de la console web (§11) et volontairement séparée d'elle :
là où la console web n'affiche que (aucun contrôle), celle-ci **joue** — un piano interactif
dans le navigateur.

```
virtual-keyboard 8081       # demarre le clavier virtuel sur ce port (defaut 8081)
virtual-keyboard stop       # arrete le clavier virtuel
```

Menu **JamShack > Demarrer le clavier virtuel.../Arreter le clavier virtuel** fait la même
chose (le port est demandé, vide = 8081).

**Plusieurs navigateurs à la fois, chacun sa piste** : ouvrir la page depuis plusieurs
appareils/onglets (plusieurs personnes sur plusieurs tablettes, par exemple) donne à
**chacun sa propre piste** (`clavier-web:<identifiant>`, visible dans `tracks`, au même titre
que `midi` ou `clavier` — voir §3) — pas une piste unique partagée où tout le monde jouerait
mélangé. Au premier chargement, la page demande un nom à afficher (« Alice », « Bob »...) —
gardé par le navigateur (il ne redemande plus aux rechargements suivants sur le même
appareil ; un lien « changer » permet de le modifier). Ce nom devient le libellé de la piste
dans `tracks`/`status`, pour savoir qui joue quoi. La piste apparaît dès la première note
jouée (pas avant) ; sonoriser cette piste, ou l'enregistrer, se fait comme n'importe quelle
autre (`track clavier-web:<id> son on`, `record start clavier-web:<id>`...), l'identifiant
exact se copiant depuis `tracks`. Arrêter le clavier virtuel supprime toutes les pistes
connectées d'un coup.

**Deux onglets** : `Clavier` (tout le contenu graphique/interactif ci-dessous) et `Infos` — ton
nom/réglages (alias, disposition QWERTY/QWERTZ) et le petit texte d'aide (flèches, Tab, Échap),
déplacés dans cet onglet séparé pour laisser plus de place au clavier lui-même dans l'onglet
`Clavier`.

**Mise en page** : deux colonnes — à gauche l'info du guide musical (s'il est en cours) et le
cercle des quintes (élargi de 20% par rapport à la première version) ; à droite, en vis-à-vis
et **tous de la même largeur, alignés au même bord gauche** (celle du piano) : la vue
d'ensemble du clavier (voir « Glissement d'octave » plus bas) + le piano interactif, sa portée
musicale, puis l'accord/le mode détecté — chacun sur sa propre ligne, sans étiquette. Les
étiquettes de note la plus grave/aiguë de la vue d'ensemble (ex. « F2 »/« B4 ») se calent sur
ces mêmes bords gauche/droite ; les touches de la vue d'ensemble elle-même sont légèrement en
retrait des deux bords pour leur laisser la place.

**Taille adaptée à l'écran** : toute cette mise en page (roue + clavier) se redimensionne comme
un seul bloc pour tenir dans la largeur de fenêtre disponible — pensée pour rester utilisable
sans défilement horizontal sur un MacBook 13 pouces ou un iPad 11 pouces (en orientation
paysage), et s'agrandit proportionnellement sur un écran plus grand plutôt que de rester petite.
Un iPhone/écran très étroit en portrait n'est pas encore la cible d'une mise en page dédiée (à
venir) — le bloc s'y réduit simplement au minimum plutôt que de casser, mais reste peu
confortable pour l'instant.

**Cinq façons de jouer, en même temps si besoin** :
- **Souris/tactile** : clique ou touche directement une touche du piano affiché.
  Vraiment multi-tactile — sur un iPad/écran tactile, plusieurs doigts sur plusieurs touches
  jouent un accord, chaque doigt suivi indépendamment.
- **Cercle des quintes**, toujours affiché (guide en cours ou non) : clique/touche une case
  pour jouer l'accord (majeur/mineur/diminué) qu'elle représente — la case et les touches du
  piano concernées s'allument tant que la pression est maintenue. Sans guide en cours, la
  roue reste jouable mais s'affiche « nue » (juste la grille de 36 accords colorés) — pas de
  contour des 7 accords diatoniques, pas de nom de mode actif ni de chiffre romain, puisqu'il
  n'y a alors pas de tonalité de référence à laquelle les rattacher. Dès que l'accord de TA
  piste (celui joué au piano/clavier, affiché en dessous — voir plus loin) est reconnu, la
  case correspondante s'entoure d'un anneau magenta dans la roue — que le guide soit actif ou
  non.
- **Clavier de l'ordinateur** : deux paires de rangées superposées couvrant environ 2,5
  octaves — la touche `` ` `` + la rangée de chiffres + `qwertyuiop` pour le registre grave (de
  Fa à Si, `` ` `` à `P`), `S D G H J` + la rangée du bas (`zxcvbnm`) pour le registre aigu qui suit juste
  au-dessus (de Do à Si, `Z` à `M`, directement à la suite du Si grave). La lettre qui joue chaque
  note est affichée directement sur la touche (majuscule, blanc sur les touches noires, noir
  sur les blanches, bien centrée sur la partie visible des touches Do/Fa/Mi/Si) ; le nom de la
  touche (C3, C4...) apparaît en bas des touches Do. Le mappage se fait par **position
  physique de la touche**, pas par caractère — reste donc correct même sur un clavier
  QWERTZ/AZERTY. La lettre *affichée*, elle, doit en plus savoir laquelle des deux
  dispositions (QWERTY ou QWERTZ) tu utilises réellement — seuls Y et Z diffèrent entre les
  deux pour les touches utilisées ici : un lien **Disposition clavier : QWERTY/QWERTZ —
  changer**, juste sous ton nom, bascule l'un vers l'autre et retient le choix (comme
  l'alias). Deviné automatiquement au premier chargement quand le navigateur le permet
  (Chrome/Edge, et seulement si la page est ouverte en HTTPS ou en `http://localhost` — pas
  depuis l'adresse réseau d'un autre appareil), sinon QWERTY par défaut : à corriger à la main
  une fois avec ce lien si besoin, ça reste ensuite.
- **Glissement d'octave** : juste au-dessus du piano, une vue d'ensemble du clavier complet
  (Do-1 à Do8) — largeur alignée sur celle du piano, tout comme la portée et le panneau
  accord/mode juste en dessous — entoure d'un cadre rouge la tranche actuellement jouable,
  flanquée à gauche de la note la plus grave et à droite de la plus aiguë, avec une flèche
  **◂/▸** de chaque côté. Pour déplacer toute la zone jouable par pas d'une octave (de C0 à
  C6) : clique une flèche, appuie sur **flèche gauche/droite** au clavier, ou — sur un clavier
  ISO — les touches **<** et **-** juste à côté du Shift (absentes sur certains claviers US ;
  les flèches et fléches-clavier restent le moyen universel). Clique ou touche directement un
  point de la petite vue d'ensemble pour y sauter d'un coup plutôt que pas à pas — elle se cale
  toujours sur l'un des mêmes crans fixes (C0..C6), jamais sur une note arbitraire au pixel
  près. Le piano affiché juste en-dessous s'ajuste pour montrer exactement la tranche jouable
  au clavier de l'ordinateur à cet instant. Changer d'octave relâche d'abord toutes les notes
  en cours (comme Échap), la zone affichée changeant entièrement. Le repère d'octave (« C3 »,
  « C4 »...) sous chaque touche Do est en bleu azur, pour rester bien visible.

**Différence importante avec la piste `clavier` du terminal** : un terminal ne voit jamais le
relâchement d'une touche (§3.2), donc chaque frappe y déclenche une note "pincée" de ~300ms.
Un navigateur, lui, reçoit un vrai événement de relâchement (`keyup`) — une touche tenue sur le
clavier virtuel **tient vraiment** la note jusqu'au relâchement, comme un vrai instrument.

**Ce qui s'affiche** : les mêmes couleurs de rôle que partout ailleurs dans l'app (magenta la
fondamentale, jaune les autres notes de l'accord, vert une note tenue hors accord — voir §5),
plus la ligne de degrés au-dessus du clavier puis, en dessous du piano, la même portée musicale
(historique inclus, voir §11) que la console web pour les notes de TA piste, et enfin l'accord
détecté et les modes candidats — chacun sur sa propre ligne, sans étiquette.

**Si un guide musical est en cours** : son titre et la liste de ses étapes s'affichent (à
gauche), et le cercle des quintes (voir plus haut) retrouve son contour des 7 accords
diatoniques et son nom de mode actif, calculés sur la tonalité du **guide**. La ligne de
degrés au-dessus du clavier bascule elle aussi sur les notes du mode du guide plutôt que sur
l'accord détecté de cette piste (qui reste, lui, personnel — chacun voit son propre accord
détecté, mais tout le monde voit les mêmes degrés de référence et le même guide). **Tab**
avance d'une étape, **Maj+Tab** recule — une action globale (le même guide pour tout le
monde), comme les flèches gauche/droite de l'écran `.guide` du terminal.

**Touche non relâchée** : `GET /note-on`/`GET /note-off` sont deux connexions HTTP
indépendantes (pas de garantie d'ordre entre elles) — une frappe très rapide peut, rarement,
laisser une note affichée comme tenue alors qu'elle a bien été relâchée. **Échap** relâche
alors tout le clavier virtuel d'un coup (interroge la session elle-même sur ce qu'elle tient
encore, pas la mémoire locale du navigateur qui pourrait aussi être fausse).

## 13. Palette de couleur — une couleur par note, dans la console web et le clavier virtuel

Chaque note (chacun des 12 demi-tons) a sa propre couleur, utilisée pour les pastilles de
degré au-dessus des claviers et pour les accords du cercle des quintes — la même couleur
partout où cette note apparaît, quel que soit le mode/l'accord. Chaque note a aussi sa propre
**couleur de texte**, choisie pour rester lisible sur son propre fond (le chiffre du degré
dans sa pastille, le nom/degré affiché dans chaque case du cercle des quintes) : dans la
palette **Default**, tout le texte est blanc sauf sur les notes La, Mi et Si (les 3 fonds les
plus clairs de cette palette), en noir ; les deux autres palettes ont leur propre choix.
Plusieurs jeux de couleurs possibles, listés dans `Settings/palettes.json` (créé
automatiquement au premier lancement, avec trois palettes de départ : **Default**
— extraite de la roue physique photographiée dans `Sources/Colors/Colors.PNG` —, **Contraste**
et **Pastel**) ; le modifier à la main pour ajouter ses propres palettes. Une palette
ajoutée à la main sans préciser `textColors` reçoit automatiquement une couleur de texte
calculée (blanc ou noir selon la luminosité perçue du fond) plutôt que d'échouer au
chargement.

```
use-palette 2          # palette active par numero (voir menu JamShack pour la liste)
use-palette Pastel     # ou par nom
```

Menu **JamShack > Choisir palette de couleur...** fait la même chose, avec la liste
numérotée et la palette active repérée. Le choix est **propre à cette instance de
l'application** — jamais écrit dans `palettes.json` (qui ne liste que ce qui est
*disponible*, pas ce qui est *actif*) — et repasse sur la première palette du fichier à
chaque relance. S'applique aussitôt à la console web et au clavier virtuel de cette même
instance, sans recharger la page (le changement apparaît dans les ~250ms du prochain
sondage).

## 14. Progressions d'accords — bibliothèque pour le guide musical

En ajoutant un mode au guide musical (menu **Guide Musicaux**, voir §8), on peut lui attacher
une **progression d'accords** prise dans une bibliothèque de templates, écrite en notation
relative (chiffres romains) : `I` = accord majeur sur le 1er degré, `vi` = accord mineur sur
le 6e, `vii°` = accord diminué sur le 7e — la casse indique la qualité (majuscule = majeur,
minuscule = mineur), appliquée telle quelle quel que soit le mode choisi pour l'étape
(exactement comme dans un livre de blues/jazz : "I-IV-V" désigne toujours trois accords
majeurs). Une étape avec une progression attachée devient presque un mini-morceau (mode +
suite d'accords), à ceci près qu'il manque encore les lignes mélodiques.

Ces templates vivent dans `Settings/chordprogressions.json` (créé automatiquement au premier
lancement avec une bibliothèque de départ : Blues 12 mesures, ii-V-I, Pop I-V-vi-IV, Années 50,
Canon, Cadence andalouse, Progression circulaire, Rock mineur) — modifiable à la main pour en
ajouter d'autres, même convention que `palettes.json` (un seul fichier listant plusieurs
templates).

## 15. Scènes — sauvegarder/recharger une configuration d'instruments, avec des rôles

Une **scène** sauvegarde une configuration d'instruments (voir §3) pour la retrouver plus tard
sans tout reconfigurer à la main — pratique pour passer d'une configuration "répétition solo"
à "groupe complet" en une commande. Deux façons de l'utiliser :

**Sans rien déclarer à l'avance** (le plus simple) : `save-scene <nom>` capture directement
l'état courant de chaque piste locale (écoute, son, instrument) — exactement comme avant. Au
rechargement (`use-scene <n|nom>`), chaque piste retrouvée est réappliquée telle quelle.

**Avec des rôles déclarés** (recommandé si les instruments changent d'une session à l'autre —
un clavier MIDI qui n'est pas toujours branché, par exemple) : un **rôle** ("Piano 1", "Basse
Guitare", "Saxophoniste"...) est un poste déclaré à l'avance, avec son propre son, indépendant
de l'instrument physique/virtuel qui l'occupera cette fois-ci.

```
scene-new <titre>                    # cree une scene vide, a base de roles
scene-role-add <nom>                 # ajoute un role ("Piano 1", "Basse"...)
scene-role-sound <role> <son|vide>   # son de ce role (s'applique a qui l'occupe)
scene-role-listen <role> on|off      # ecoute declaree pour ce role
scene-role-attach <role> <id>        # attache un instrument (id: midi, clavier... voir §3) a ce role
scene-role-detach <role>             # detache l'instrument de ce role (le role reste declare)
scene-role-remove <role>             # supprime le role de la scene active
scene-roles                          # liste les roles et ce qui les occupe (ou "libre")
save-scene <nom>                     # sauvegarde la scene active (roles + leur son, PAS l'attache)
use-scene <n|nom>                    # charge une scene, tente de reattacher chaque role automatiquement
```

**Ce qui rend un rôle différent d'avant** : au rechargement, l'application essaie de
reconnaître le MÊME instrument qu'à la sauvegarde (pour un port MIDI, via un identifiant
CoreMIDI stable, pas juste "le port qui porte ce numéro-là maintenant" — un vrai clavier
débranché puis rebranché est ainsi retrouvé même si l'ordre des ports a changé). **Si aucun
instrument ne correspond, le rôle reste explicitement libre** — annoncé clairement dans le
message de chargement ("2 réattachés automatiquement, 1 libre") plutôt que silencieusement
ignoré comme c'était le cas avant l'introduction des rôles.

**Attacher un instrument qui vient de se connecter** : en tapant `track <id> on` alors qu'une
scène (à base de rôles) est active et que cet instrument n'est encore attaché à aucun rôle,
l'application propose directement la liste des rôles libres (ou de créer un nouveau rôle à la
volée). La commande `tracks` rappelle aussi, en une ligne, combien d'instruments actifs ne sont
attachés à aucun rôle.

**Un instrument n'occupe jamais deux rôles à la fois** : l'attacher à un second rôle le
détache automatiquement du premier (un déplacement, pas une erreur) — les deux mouvements sont
journalisés.

**Limite actuelle, assumée** : les rôles ne fonctionnent qu'en solo/standalone pour l'instant —
un participant connecté à une jam session (§9) ne peut pas encore revendiquer un rôle sur une
scène partagée. Cette extension est conçue mais délibérément différée à une prochaine session
(voir `Docs/BACKLOG.md`).

## 16. Onglet Commandes (console web) — piloter l'application depuis un navigateur

En plus des onglets `Run`/`Scene`/`Infos` (lecture seule, §11), l'onglet **Commandes** de la
console web est une vraie télécommande : chaque action du menu déroulant du terminal (§8) y a
son équivalent, accessible depuis un navigateur — utile pour piloter l'application depuis un
autre appareil (tablette, téléphone) sans taper de commande.

Les actions sont groupées en sous-onglets, un par catégorie du menu terminal (JamShack, Scene,
Guide Musicaux, Enregistrement, Morceaux, Composition, Jam Session) — chaque action montre le
ou les champs qu'elle attend (menu déroulant pré-rempli avec les valeurs valides du moment,
champ texte, case à cocher...), suivi d'un bouton pour valider ; le résultat s'affiche
immédiatement en haut de l'onglet.

**Ce qui n'y est volontairement pas** : les écrans en lecture seule (statut, activité en
direct, plan de scène) — déjà couverts par les onglets `Run`/`Scene`/`Infos`. L'onglet
Commandes ne fait qu'agir, jamais qu'afficher.

**Les listes déroulantes restent à jour** même si le changement vient d'ailleurs (le terminal,
un autre onglet de navigateur, un autre participant de la jam session) — rafraîchies toutes
les 2 secondes en tâche de fond, sans jamais effacer un champ texte en cours de frappe.

## 17. Serveur MCP — piloter l'application depuis un assistant IA (Claude, etc.)

Un petit serveur séparé (dossier `mcp-server/`, en Python, hors du programme Swift lui-même)
qui expose les mêmes actions que l'onglet Commandes (§16) comme des *tools* MCP (Model Context
Protocol) — de quoi demander à un assistant compatible (Claude Desktop, Claude Code...) de
piloter directement l'application depuis une conversation : charger un morceau, démarrer une
piste, composer à partir d'une description, gérer une scène et ses rôles, etc.

**Mise en place** (voir `mcp-server/README.md` pour le détail) :

```sh
cd mcp-server
python3 -m venv .venv
.venv/bin/pip install -r requirements.txt
```

Puis, dans la configuration MCP du client (Claude Desktop, par exemple) :

```json
{
  "mcpServers": {
    "jamshack": {
      "command": "/chemin/absolu/vers/mcp-server/.venv/bin/python3",
      "args": ["/chemin/absolu/vers/mcp-server/server.py"],
      "env": { "JAMSHACK_BASE_URL": "http://localhost:8080" }
    }
  }
}
```

**La console web doit déjà tourner** (`web-console 8080` ou menu **JamShack > Demarrer la
console web...**) — le serveur MCP n'est qu'un relais vers elle, il ne fait tourner aucune
logique musicale lui-même.

**Ce qui est exposé** : un *tool* par action (mêmes catégories que §16), plus des *tools* de
lecture pour donner à l'assistant une vraie vue sur le contenu — la structure complète d'un
morceau (nombre de sections, lignes mélodiques, accords par section), la description en
attente de composition (avec le prompt exact qui serait envoyé), la structure complète d'un
guide musical chargé, et le détail d'un enregistrement.

**Expérimental** : toutes les actions sont exposées sans réglage fin des permissions pour
l'instant (tout ou rien) — un mécanisme plus sélectif est une étape volontairement différée.

## Liste complète des commandes

`help` les affiche déjà regroupées par catégorie (Général / Morceaux / Pistes d'entrée /
Scene / Soundtrack / Composition / Guide Musicaux / Session collaborative) — la liste
ci-dessous reste à plat pour une recherche rapide.

**Nom de fichier contenant des espaces** : entourez-le de guillemets, par exemple
`use-sample "The Fox and The Crow General MIDI SoundFont Ultimate.sf2"`.

```
help                    affiche l'aide
load-demo               charge le morceau de démonstration (ii-V-I)
pieces <dossier>        liste les fichiers .json (morceaux) du dossier
use-piece <n|nom>       charge un morceau
load <chemin.json>      charge un morceau depuis un chemin explicite
save                    resauvegarde le morceau courant
save-as <nom>           sauvegarde sous un nouveau nom
play                    joue le morceau courant
tracks                  liste les pistes d'entrée (MIDI/clavier/micro) et leur état
scene-tree              plan de scène en arbre (instruments, consoles, clients connectés — voir §9)
scenes <dossier>        liste les fichiers .json (scènes) du dossier
use-scene <n|nom>       charge une scène (réattache automatiquement chaque rôle si possible — voir §15)
save-scene <nom>        sauvegarde la scène active (rôles + leur son, jamais l'attache — voir §15)
scene-new <titre>       crée une scène vide, à base de rôles (voir §15)
scene-roles             liste les rôles de la scène active et ce qui les occupe
scene-role-add <nom>    ajoute un rôle à la scène active
scene-role-sound <role> <son|vide>  son de ce rôle
scene-role-listen <role> on|off     écoute déclarée pour ce rôle
scene-role-attach <role> <id>       attache un instrument (voir §3) à ce rôle
scene-role-detach <role>            détache l'instrument de ce rôle
scene-role-remove <role>            supprime le rôle de la scène active
midi-mode <fusionne|individuel>  MIDI en une piste fusionnée, ou une piste par port
track <id> on|off       démarre/arrête l'écoute d'une piste (id: midi, midi:<n>, clavier, micro)
track <id> son on|off   active/désactive le son d'une piste (impossible pour 'micro')
track <id> instrument <n|nom>  charge un instrument sur cette piste (active son son)
record start [<id> ...] demarre l'enregistrement (toutes les pistes en ecoute, ou celles listees)
record stop             arrete l'enregistrement en cours
play-soundtrack         joue la soundtrack courante (mode temporel)
soundtracks <dossier>   liste les fichiers .json (soundtracks) du dossier
use-soundtrack <n|nom>  charge une soundtrack
save-soundtrack         resauvegarde la soundtrack courante
save-soundtrack-as <nom>  sauvegarde sous un nouveau nom
show-soundtrack         affiche les infos de la soundtrack courante
compose-piece-from-soundtrack [n] [titre]  demande a l'IA d'en deduire n Piece Model (defaut 1), nomme <titre> s'il est donne
pseudo [nom]            affiche/change le pseudo affiche aux autres participants (defaut "player")
server [port]           demarre un serveur collaboratif (defaut port 7777)
stop-server             arrete le serveur
client [host] [port]    rejoint un serveur (defaut localhost:7777)
discover                recherche des serveurs sur le reseau local et propose de rejoindre
disconnect              se deconnecte du serveur
press <hauteur>         simule l'appui d'une touche (0-127) sur la piste 'clavier'
release <hauteur>       simule le relâchement d'une touche sur la piste 'clavier'
samples <dossier>       liste les fichiers .sf2/.dls/.aupreset du dossier
use-sample <n|nom>      charge le son par defaut de la lecture du morceau
set-track-instrument <section> <piste> <nom|vide>  instrument d'une piste melodique (voir §7)
set-chord-instrument <section> <nom|vide>           instrument des accords d'une section (voir §7)
new-piece <titre>       démarre un morceau vierge (sans IA)
title [texte]           titre du morceau a composer (vide efface)
paste-text              colle la description du morceau (poème...), terminée par une ligne vide
indications [texte]     indications de style additionnelles (vide efface)
show-description        affiche le titre, la description et les indications en cours
use-description <n|nom> charge une description sauvegardee (remplace titre/description/indications)
save-description-as <nom>  sauvegarde titre+description+indications sous ce nom
save-description        resauvegarde sous le meme nom
settings <dossier>      pointe le dossier de réglages (palettes, progressions d'accords, connexions LLM — voir §13/§14)
use-llm <n|nom>         choisit une connexion LLM
compose [titre]         demande à l'IA de composer à partir de la description, nomme <titre> s'il est donné
prompts <dossier>       pointe le dossier de composition IA (sous-dossiers crees si absents)
show-text-framing / show-soundtrack-framing  affiche la phrase de cadrage active
set-text-framing / set-soundtrack-framing     colle une nouvelle phrase de cadrage
save-text-framing <nom> / save-soundtrack-framing <nom>  sauvegarde la phrase de cadrage active
use-text-framing <n|nom> / use-soundtrack-framing <n|nom>  charge une phrase de cadrage sauvegardee
reset-text-framing / reset-soundtrack-framing  revient a la phrase de cadrage par defaut
show-soundtrack-instructions      affiche les indications de style actives (soundtrack)
set-soundtrack-instructions [texte]  indications de style pour la soundtrack (vide efface)
save-soundtrack-instructions <nom>   sauvegarde les indications de style actives
use-soundtrack-instructions <n|nom>  charge des indications de style sauvegardees
reset-soundtrack-instructions        efface les indications de style (aucune)
show-text-prompt / show-soundtrack-prompt  affiche le prompt complet qui serait envoye maintenant
export-text-prompt <nom> / export-soundtrack-prompt <nom>  exporte le prompt complet (jamais recharge)
guide                   ecran Guide Musical (sequence de modes a naviguer en direct)
guides <dossier>        liste les fichiers .json (guides musicaux) du dossier
use-guide <n|nom>       charge un guide musical
save-guide              resauvegarde le guide musical courant
save-guide-as <nom>     sauvegarde sous un nouveau nom
guide-new <titre>       demarre une sequence de guide vierge
guide-add-mode <tonique> <id-gamme> [progression]  ajoute une etape (numero ou id de gamme/progression)
guide-start [n]         demarre le guide a l'etape n (defaut 0)
guide-stop              arrete le guide musical
show-piece              affiche la structure du morceau courant
status                  affiche l'état courant
run                     écran fixe: activité musicale en direct (q pour revenir)
config                  écran fixe: configuration active et détail du morceau (q pour revenir)
web-console [port]      demarre la console web (miroir de 'run' dans un navigateur, defaut port 8080)
web-console stop        arrete la console web
virtual-keyboard [port] demarre le clavier virtuel (piano interactif dans un navigateur, piste 'clavier-web', defaut port 8081)
virtual-keyboard stop   arrete le clavier virtuel
use-palette <n ou nom>  choisit la palette de couleur active (console web + clavier virtuel, propre a cette instance)
quit                    quitte
```

## Dépannage rapide

| Symptôme | Piste |
|---|---|
| Le micro ne détecte jamais rien | Vérifier la permission microphone (Réglages Système > Confidentialité et sécurité > Microphone) et le niveau affiché — voir §3.3. |
| Les lettres tapées en `run` ouvrent un menu au lieu de jouer une note | La piste « clavier » n'écoute pas — `track clavier on` (ou menu Scene). |
| Impossible de sortir de la piste « clavier » pour ouvrir un menu | Appuyer sur **Échap**. |
| Une note reste affichée/jouée sans s'arrêter après `play` | Devrait être corrigé (filet de sécurité en fin de lecture) — si le problème réapparaît, le signaler. |
| Au clavier MIDI, une note reste affichée « tenue » après l'avoir relâchée | Devrait être corrigé (le parseur MIDI ne gérait pas le « running status », utilisé par une partie du matériel réel pour les note-off consécutifs) — si ça persiste, le signaler avec le modèle de clavier/interface utilisé. |
| Au clavier MIDI en mode individuel, une note jouée s'affiche deux fois | Vérifier `sources`/`tracks` : si le même clavier physique apparaît comme plusieurs sources MIDI visibles, chacune devient sa propre piste par design de ce mode — repasser en mode fusionné (menu JamShack) réunit tout en une seule piste. |
| Le clavier ASCII scintille ou se déforme | Devrait être corrigé (largeur de ligne bornée) — si ça persiste, vérifier la largeur du terminal (≥ 80 colonnes recommandé). |
| `compose` échoue avec une erreur réseau | Vérifier que le serveur (Ollama local) tourne, ou que la variable d'environnement de clé API est bien définie pour la connexion choisie. |
| `client` échoue ou reste sans piste distante visible | Vérifier host/port, que `server` tourne bien de l'autre côté, et qu'aucun pare-feu ne bloque le port — voir §9. |
| `discover` ne trouve jamais rien | Même réseau local requis (pas de VPN/sous-réseau différent) ; vérifier la permission « Réseau local » ; sinon se connecter par adresse connue (`client <IP> <port>`) — voir §9. |
| `track remote:...` refuse `on`/`off` | Normal : une piste distante est démarrée/arrêtée sur sa propre machine, pas depuis ailleurs — voir §9. |
| La console web affiche « connexion perdue » | Vérifier que l'application tourne toujours et que `web-console stop` n'a pas été appelé — voir §11. |
| `web-console <port>` echoue | Le port est peut-être déjà utilisé par une autre application — réessayer avec un autre port. |
| `virtual-keyboard <port>` echoue | Même cause/solution que `web-console <port>` ci-dessus — un port différent (`web-console` et `virtual-keyboard` ne peuvent pas non plus partager le même port entre eux). |
