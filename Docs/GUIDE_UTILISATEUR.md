# Guide utilisateur — Music Improv Assistant

Manuel d'utilisation de l'application en ligne de commande, dans son état à la fin de la
session du 2026-07-07. Un terme ambigu ou peu clair ? Voir `Docs/GLOSSAIRE.md`.

## Lancer l'application

Depuis le dossier `MusicTheoryKit/` :

```sh
swift run JamShack
```

Au démarrage, l'application charge automatiquement les dossiers de travail par défaut
(`Pieces/`, `SoundFonts/`, `LLMConnections/`, situés à côté de `MusicTheoryKit/`) — pas
besoin de les indiquer à chaque lancement.

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
| 4. Choisir un dossier de connexions LLM | `llm-connections <dossier>` (par défaut : `LLMConnections/` ; menu **JamShack**) |
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

Trois connexions d'exemple sont fournies dans `LLMConnections/` :
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
prompts <dossier>   # pointe le dossier de composition IA (par defaut "Composition IA/"), cree ses sous-dossiers si absents
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
| **JamShack** | Menu principal (premier de la barre, s'ouvre par défaut) : (1) infos (status), aide ; (2) choisir chacun des dossiers (morceaux/sons/soundtracks/**guides musicaux**/**scènes**/connexions LLM/**composition IA**) ; (3) choisir une connexion LLM, isolée dans son propre groupe ; (4) mode MIDI fusionné/individuel ; (5) démarrer/arrêter la console web (voir §11) ; (6) quitter. Point d'entrée unique pour la configuration de la session — dossiers, connexion LLM et mode MIDI ne se réglent que depuis ce menu. |
| **Scene** | Lister les instruments, activer/arrêter un instrument, *séparateur*, activer/désactiver le son d'un instrument, *séparateur*, choisir un son pour un instrument, *séparateur*, sauvegarder/charger une scène (la configuration complète des instruments : actif, son actif, quel son). Les actions qui demandent de choisir un instrument présentent la liste numérotée (voir §3) — répondre par le numéro évite d'avoir à retaper `midi:1`/`clavier`/etc. |
| **Morceaux** | Quatre groupes, séparés par des traits : (1) écouter/voir le morceau ; (2) choisir le son par défaut de lecture, ou le son d'une piste/des accords d'une section (voir §7 — la structure affichée numérote les sections et les pistes, pour savoir directement quel numéro saisir) ; (3) charger la démo, charger un morceau, sauvegarder le morceau, sauvegarder le morceau sous ; (4) **Assistant IA** — pour l'instant un intitulé de sous-section réservé, sans action, en attente d'une future fonction de modification par dialogue (« plus vite », « moins vite »…) applicable à n'importe quel morceau. |
| **Guide Musicaux** | Voir l'écran Guide Musical, *séparateur*, créer un nouveau guide musical (propose d'ajouter un mode en boucle jusqu'à laisser la tonique vide) / ajouter un mode au guide musical en cours, *séparateur*, charger un guide musical / sauvegarder le guide musical (sous...), *séparateur*, démarrer/arrêter le guide musical — aussi accessible directement par la barre d'espace une fois sur l'écran Guide Musical. |
| **Enregistrement** | Démarrer/arrêter un enregistrement, voir l'enregistrement, jouer l'enregistrement, *séparateur*, charger/sauvegarder l'enregistrement, *séparateur*, composer un morceau à partir de l'enregistrement en le nommant (voir §10), *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser la phrase de cadrage, *séparateur*, voir/modifier/sauvegarder/charger/réinitialiser les indications de style, *séparateur*, voir/exporter le prompt de composition (voir §6). |
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

**Ce qui s'affiche** : le dernier événement MIDI reçu, un clavier par piste en écoute (mêmes
couleurs que le terminal — magenta la fondamentale, jaune les autres notes de l'accord, vert
une note tenue hors accord, une ligne cyan pour le mode détecté — voir §5), et, pendant la
lecture, le clavier du morceau ou de l'enregistrement en cours. Un simple miroir de ce que
montre l'écran `run` (§8) — la console web n'a aucun contrôle ni menu, elle ne fait qu'afficher
(pour jouer depuis un navigateur, voir §12, une page distincte).

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

**Trois façons de jouer, en même temps si besoin** :
- **Souris/tactile** : clique ou touche directement une touche du piano affiché.
  Vraiment multi-tactile — sur un iPad/écran tactile, plusieurs doigts sur plusieurs touches
  jouent un accord, chaque doigt suivi indépendamment.
- **Clavier de l'ordinateur** : même disposition « Musical Typing » que la piste `clavier` du
  terminal (§3.2) — `A S D F G H J K L ;` pour les touches blanches, `W E T Y U O P` pour les
  noires.

**Différence importante avec la piste `clavier` du terminal** : un terminal ne voit jamais le
relâchement d'une touche (§3.2), donc chaque frappe y déclenche une note "pincée" de ~300ms.
Un navigateur, lui, reçoit un vrai événement de relâchement (`keyup`) — une touche tenue sur le
clavier virtuel **tient vraiment** la note jusqu'au relâchement, comme un vrai instrument.

**Ce qui s'affiche** : les mêmes couleurs de rôle que partout ailleurs dans l'app (magenta la
fondamentale, jaune les autres notes de l'accord, vert une note tenue hors accord — voir §5),
plus la ligne de degrés au-dessus du clavier et le libellé accord/mode détecté au-dessus.

**Touche non relâchée** : `GET /note-on`/`GET /note-off` sont deux connexions HTTP
indépendantes (pas de garantie d'ordre entre elles) — une frappe très rapide peut, rarement,
laisser une note affichée comme tenue alors qu'elle a bien été relâchée. **Échap** relâche
alors tout le clavier virtuel d'un coup (interroge la session elle-même sur ce qu'elle tient
encore, pas la mémoire locale du navigateur qui pourrait aussi être fausse).

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
llm-connections <dir>   liste les connexions LLM (.json) du dossier
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
show-piece              affiche la structure du morceau courant
status                  affiche l'état courant
run                     écran fixe: activité musicale en direct (q pour revenir)
config                  écran fixe: configuration active et détail du morceau (q pour revenir)
web-console [port]      demarre la console web (miroir de 'run' dans un navigateur, defaut port 8080)
web-console stop        arrete la console web
virtual-keyboard [port] demarre le clavier virtuel (piano interactif dans un navigateur, piste 'clavier-web', defaut port 8081)
virtual-keyboard stop   arrete le clavier virtuel
quit                    quitte
```

## Dépannage rapide

| Symptôme | Piste |
|---|---|
| Le micro ne détecte jamais rien | Vérifier la permission microphone (Réglages Système > Confidentialité et sécurité > Microphone) et le niveau affiché — voir §3.3. |
| Les lettres tapées en `run` ouvrent un menu au lieu de jouer une note | La piste « clavier » n'écoute pas — `track clavier on` (ou menu Scene). |
| Impossible de sortir de la piste « clavier » pour ouvrir un menu | Appuyer sur **Échap**. |
| Une note reste affichée/jouée sans s'arrêter après `play` | Devrait être corrigé (filet de sécurité en fin de lecture) — si le problème réapparaît, le signaler. |
| Le clavier ASCII scintille ou se déforme | Devrait être corrigé (largeur de ligne bornée) — si ça persiste, vérifier la largeur du terminal (≥ 80 colonnes recommandé). |
| `compose` échoue avec une erreur réseau | Vérifier que le serveur (Ollama local) tourne, ou que la variable d'environnement de clé API est bien définie pour la connexion choisie. |
| `client` échoue ou reste sans piste distante visible | Vérifier host/port, que `server` tourne bien de l'autre côté, et qu'aucun pare-feu ne bloque le port — voir §9. |
| `discover` ne trouve jamais rien | Même réseau local requis (pas de VPN/sous-réseau différent) ; vérifier la permission « Réseau local » ; sinon se connecter par adresse connue (`client <IP> <port>`) — voir §9. |
| `track remote:...` refuse `on`/`off` | Normal : une piste distante est démarrée/arrêtée sur sa propre machine, pas depuis ailleurs — voir §9. |
| La console web affiche « connexion perdue » | Vérifier que l'application tourne toujours et que `web-console stop` n'a pas été appelé — voir §11. |
| `web-console <port>` echoue | Le port est peut-être déjà utilisé par une autre application — réessayer avec un autre port. |
| `virtual-keyboard <port>` echoue | Même cause/solution que `web-console <port>` ci-dessus — un port différent (`web-console` et `virtual-keyboard` ne peuvent pas non plus partager le même port entre eux). |
