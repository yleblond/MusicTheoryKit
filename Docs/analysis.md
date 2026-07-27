# Analyse du code JamShack — sécurité, distribution App Store, ergonomie

Analyse ponctuelle du code Swift produit à date (App/Sources, Sources/*), menée en lisant le
code directement (pas de supposition non vérifiée). Pour chaque point : est-il déjà connu
(documenté dans `Docs/BACKLOG.md`) ou nouveau, sévérité, référence fichier:ligne.

## 1. Failles / faiblesses de sécurité

### 🔴 Nouveau, le plus sérieux — écriture de fichier arbitraire via la console web, sans CSRF

`Sources/AppCore/ImprovSession.swift:3308` : l'action `piece-save-as` de la route
`/menu-action` appelle directement `savePiece(as: value)` avec le paramètre de requête brut.
`savePiece(as:)` (`ImprovSession.swift:940-948`) écrit tel quel dès que `value` contient un
`/` — un chemin absolu est accepté sans validation.

Concrètement : tant que la console web tourne (`web-console-start`), n'importe quelle page
ouverte dans un navigateur sur la même machine ou le même réseau local peut déclencher
`http://<mac>:8080/menu-action?action=piece-save-as&value=/chemin/de/mon/choix.json` via un
simple `<img src="...">` — aucune authentification, aucun jeton CSRF, aucune vérification
d'origine dans tout le serveur HTTP fait main (`WebConsole/HTTPConnection.swift`). Ça écrit le
morceau actuellement chargé en session à l'emplacement de son choix (dans les limites du
sandbox de l'app).

Le même mécanisme (`folder-pieces`, `folder-samples`, `piece-load`, `/piece-detail`) permet de
lister et lire le contenu de dossiers arbitraires accessibles à l'app — potentiellement le
dossier de réglages contenant `llm-api-keys.json` en clair (voir plus bas).

### 🟠 Déjà documenté dans BACKLOG, confirmé toujours actif

`NetworkServer.swift:5-8` l'assume explicitement ("deliberately promiscuous... no
auth/allow-list") — tout appareil qui découvre le service Bonjour `_musicimprov._tcp` ou
atteint le port peut rejoindre une jam session et injecter des `NetMessage`. Idem pour la
console web : aucune des ~70 actions de `/menu-action` n'est protégée.

### 🟠 Nouveau — DoS par mémoire non bornée

`FramedConnection.drainCompleteFrames()` (`NetEngine/FramedConnection.swift:92-96`) lit une
longueur `UInt32` puis attend ce nombre d'octets sans plafond ; `HTTPConnection.
handleRequestIfComplete()` (`WebConsole/HTTPConnection.swift:44-63`) accumule jusqu'à trouver
`\r\n\r\n` sans plafond non plus. Un pair malveillant qui envoie beaucoup de données sans
jamais compléter la trame fait croître le buffer indéfiniment.

### 🟡 Déjà connu et accepté

Clés API LLM stockées en JSON clair (`Sources/AppCore/LLMAPIKeysFile.swift`) — migration
Keychain déjà planifiée dans le backlog.

### ✅ Vérifié et sain

Parsing MIDI/SysEx correctement borné (`MIDINoteEvent.swift`), `SamplerUnit` clampe
pitch/vélocité/canal, aucun secret commité dans git, aucun SDK d'analytics/tracking tiers.

## 2. Points de friction pour la distribution App Store (macOS + iOS)

- **`PrivacyInfo.xcprivacy` absent** — Apple l'exige de plus en plus systématiquement (APIs
  "raison requise"), son absence déclenche souvent un avertissement/blocage à l'upload.
- **`ITSAppUsesNonExemptEncryption` absent d'`Info.plist`** — pas bloquant en soi, mais fera
  surgir la question de conformité export à chaque soumission tant que ce n'est pas explicité.
- **Game Center à moitié câblé** : le mode "Jam Game Center" reste sélectionnable dans
  `JamSessionView.swift:70-71` même sans l'entitlement `com.apple.developer.game-center`
  (volontairement pas encore ajouté, cf. commentaire dans `App/project.yml:58` — ça demande un
  vrai profil de provisioning). Ça ne crashe pas (erreur affichée), mais un reviewer qui
  clique sur ce mode tombe sur une fonctionnalité visiblement cassée → risque réel de rejet
  Guideline 2.1/4.2 si soumis tel quel.
- **Testabilité solo (Guideline 4.2)** : les fonctionnalités collaboratives (jam réseau, Game
  Center) demandent un second appareil/joueur pour être testées — prévoir des notes de review
  explicites expliquant comment tester en solo (Studio/Guide/Composition fonctionnent seuls,
  eux).
- **Bonne nouvelle** : `NSMicrophoneUsageDescription`/`NSLocalNetworkUsageDescription`/
  `NSBonjourServices` sont présents et cohérents avec le comportement réel — l'audio n'est
  jamais transmis (analyse FFT locale uniquement), les appels LLM n'envoient que du texte
  (notes/accords), jamais l'audio brut. Pas de décalage entre le texte affiché et ce que fait
  réellement le code, ce qui est exactement ce que la review vérifie.
- Aucun `TODO`/`fatalError` bloquant trouvé sur un chemin UI atteignable ; le premier
  lancement sans configuration se dégrade proprement (pas de crash).
- Icônes au format moderne (1024 unique, iOS génère le reste) — valide.

## 3. Points d'ergonomie délicats

- **La couleur est le seul vecteur d'info** sur les vues dessinées à la main (clavier, cercle
  des quintes, mini-piano), et il n'y a **aucun** `accessibilityLabel` dans tout `JamShackUI`
  — invisible en VoiceOver, et ambigu pour un daltonien : par exemple `chordRoot` (rouge
  `#e91e63`) vs `heldOutsideChord` (vert `#4caf50`) dans `PitchKeyboardView.swift:38-48` ne se
  distinguent que par la teinte, sans forme/texte de secours. Aggravé par le fait que
  `NoteColorSettings.swift:17-19` n'a **aucune UI d'édition** — il faut éditer
  `note-colors.json` à la main pour changer une couleur.
- **Réglages éclatés** dans un onglet "JamShack" contenant 8 sous-onglets identifiés par icône
  seule, sans libellé visible (Sons/MIDI/Microphone/JamSession/Couleurs/LLM/Dossiers/Langue) —
  difficile à retrouver pour un utilisateur qui ne connaît pas déjà l'app.
- **Les 7 dossiers choisis** (pièces, samples, guides, scènes, réglages, prompts...) sont
  **perdus à chaque relance** (`FolderPickerRow.swift:14-15` — pas de bookmark de sécurité
  persistant, tradeoff assumé) : l'utilisateur doit tout re-sélectionner à chaque lancement.
- **Suppression sans confirmation** : le bouton "Supprimer" un rôle de scène
  (`SceneLayoutView.swift:247-253`) est marqué `.destructive` mais s'exécute immédiatement,
  sans alerte — alors que la création, elle, passe par une alerte.
- **Messages d'erreur non traduits** : la quasi-totalité des échecs
  (`catch { actionError = "\(error)" }`) affiche l'interpolation brute de l'erreur Swift, alors
  que le reste de l'app est intégralement localisé fr/en/de.
- **Vocabulaire propre à l'app à apprendre avant de commencer** : Scene, Role, Guide, Piece,
  Track... sans lexique ni info-bulle — notamment le sélecteur à 5 choix techniques de
  `JamSessionView.swift:21-33` (Isolé / Jam locale organisateur-participant / Game Center
  organisateur-participant).
- **Densité pendant le jeu** : `GuideLectureView.swift:92-134` affiche 4 panneaux simultanés —
  à surveiller pour la lisibilité en situation réelle de jeu (regard rapide pendant qu'on
  joue).

## À traiter en priorité

Le point qui mérite l'attention la plus immédiate est le premier de la section sécurité
(écriture de fichier arbitraire sans CSRF) : c'est concret, vérifié ligne par ligne, et
exploitable dès que la console web tourne — même sur un simple réseau domestique, une page
web quelconque ouverte dans un onglet suffit.
