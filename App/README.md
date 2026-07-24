# JamShackApp (SwiftUI, iOS + macOS)

Petite coquille Xcode qui embarque le package SPM (`../Package.swift`) comme dépendance locale
et expose les vues de `JamShackUI`. La logique/les vues restent dans le package (buildable,
testable, prévisualisable sans Xcode) ; ce projet n'existe que pour ce que SPM seul ne peut pas
fournir proprement : Info.plist (permissions micro/réseau local, Bonjour), entitlements
(App Sandbox), icône, et un vrai chemin de signature/distribution.

Généré via [XcodeGen](https://github.com/yonaskolb/XcodeGen) à partir de `project.yml` —
`project.yml` est la source de vérité, `JamShackApp.xcodeproj` est committé pour que le projet
s'ouvre directement sans installer XcodeGen, mais toute modification de la configuration du
projet (nouvelle permission, nouveau réglage de build...) doit passer par `project.yml` puis :

```sh
brew install xcodegen   # si pas déjà installé
cd App
xcodegen generate
```

## Ouvrir / lancer

```sh
open App/JamShackApp.xcodeproj
```

Deux schemes : `JamShackApp_iOS` (simulateur/appareil) et `JamShackApp_macOS`. Vérifié en ligne
de commande :

```sh
xcodebuild -project App/JamShackApp.xcodeproj -scheme JamShackApp_macOS -destination 'platform=macOS' build
xcodebuild -project App/JamShackApp.xcodeproj -scheme JamShackApp_iOS -destination 'platform=iOS Simulator,name=iPhone 17' build
```
