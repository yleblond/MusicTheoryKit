import Foundation

/// The UI display language — independent of command names/syntax, which are never translated.
/// French is the authored reference language; English and German are translations of it.
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case fr, en, de
}

/// On-disk shape of `Settings/language.json` — a singleton value (unlike `ColorPaletteFile`'s
/// flat list), since there is exactly one currently-selected language, not several to pick
/// among. See `ImprovSession.loadOrCreateLanguageSetting(fromJSONFile:)`.
public struct LanguageSettingFile: Codable {
    public var language: AppLanguage
    public init(language: AppLanguage) {
        self.language = language
    }
}

/// One case per translatable static UI string (menu titles/items, screen/section headers, tab
/// names, field labels, static prompts/placeholders) — see `L10nTable.swift` for the actual
/// FR/EN/DE text. A flat enum (not nested/namespaced), mirroring the flat-switch convention
/// already used by `executeCommand`. A typo in a key is a compile error, not a silent runtime
/// miss — important since this project has no XCTest to catch it at test time.
///
/// Explicitly OUT of scope (stay French, looked up nowhere): dynamic/interpolated session-log
/// and action-confirmation messages, transient status/log-style `print()` lines that aren't
/// persistent screen elements, and `printHelp()`'s command-reference dump.
public enum L10nKey: String, CaseIterable, Sendable {
    // MARK: - Screen tabs (terminal console + web console tab bar)
    case tabRun, tabConfig, tabGuideMusical, tabScene, tabCommandes, tabInfos, tabClavier

    // MARK: - Menu category titles (shared by terminal `menuCategories` and web `MENU_ACTIONS`)
    case catJamShack, catScene, catGuideMusicaux, catEnregistrement, catMorceaux, catComposition, catJamSession

    // MARK: - "JamShack" category items
    case menuInfos, menuAide
    case menuChoisirDossierMorceaux, menuChoisirDossierSons, menuChoisirDossierSoundtracks
    case menuChoisirDossierGuides, menuChoisirDossierScenes, menuChoisirDossierReglages, menuChoisirDossierCompositionIA
    case menuChoisirConnexionLLM
    case menuChoisirPalette
    case menuMidiModeFusionne, menuMidiModeIndividuel
    case menuDemarrerConsoleWeb, menuArreterConsoleWeb
    case menuDemarrerClavierVirtuel, menuArreterClavierVirtuel
    case menuLangueFr, menuLangueEn, menuLangueDe
    case menuQuitter

    // MARK: - "Scene" category items
    case menuListerInstruments, menuActiverInstrument, menuArreterInstrument
    case menuActiverSonInstrument, menuDesactiverSonInstrument
    case menuChoisirSonPourInstrument
    case headerFichierDeScene, menuSauvegarderScene, menuChargerScene
    case headerRoles, menuNouvelleScene, menuListerRoles, menuAjouterRole
    case menuAttacherInstrumentARole, menuDetacherRole, menuChoisirSonDunRole

    // MARK: - "Guide Musicaux" category items
    case menuVoirGuideMusical, menuNouveauGuideMusical, menuAjouterModeAuGuide
    case menuChargerGuideMusical, menuSauvegarderGuideMusical, menuSauvegarderGuideMusicalSous
    case menuDemarrerGuideMusical, menuArreterGuideMusical

    // MARK: - "Enregistrement" category items
    case menuDemarrerEnregistrement, menuArreterEnregistrement, menuVoirEnregistrement, menuJouerEnregistrement
    case menuChargerEnregistrement, menuSauvegarderEnregistrement, menuSauvegarderEnregistrementSous
    case menuComposerDepuisEnregistrement
    case menuVoirPhraseDeCadrage, menuModifierPhraseDeCadrage, menuSauvegarderPhraseDeCadrage
    case menuChargerPhraseDeCadrage, menuRevenirPhraseDeCadrageParDefaut
    case menuVoirIndicationsStyle, menuModifierIndicationsStyle, menuSauvegarderIndicationsStyle
    case menuChargerIndicationsStyle, menuRevenirIndicationsStyleParDefaut
    case menuVoirPromptComposition, menuExporterPromptComposition

    // MARK: - "Morceaux" category items
    case menuEcouterMorceau, menuVoirMorceau
    case menuChoisirSonLectureMorceau, menuChoisirSonDunePiste, menuChoisirSonAccordsSection
    case menuChargerDemo, menuChargerMorceau, menuSauvegarderMorceau, menuSauvegarderMorceauSous
    case headerAssistantIA

    // MARK: - "Composition" category items
    case menuDecrireMorceau, menuComposerDepuisDescription, menuVoirDescription
    case menuChargerDescription, menuSauvegarderDescriptionSous, menuSauvegarderDescription

    // MARK: - "Jam Session" category items
    case menuDemarrerJamSession, menuArreterJamSession, menuRejoindreJamSession
    case menuTrouverJamSession, menuQuitterJamSession

    // MARK: - Field labels (TextStyle.field first argument)
    case fieldPiece, fieldFichier, fieldPlaying, fieldRecording, fieldSoundtrack, fieldPlayingSoundtrack
    case fieldReseau, fieldConsoleWeb, fieldClavierVirtuel, fieldPaletteDeCouleur, fieldModeMidi
    case fieldTempo, fieldTonalite, fieldDernierEvt, fieldMicro, fieldSon, fieldChord, fieldModes
    case fieldDuree, fieldEvenements, fieldPistes, fieldTitre, fieldIndications, fieldDescription, fieldPseudo, fieldRole

    // MARK: - Headings
    case headingDetailMorceauActif, headingDerouleComposition
    case headingClavierComposeEnCours, headingClavierSoundtrackEnCours
    case headingSequence, headingClavierGuide

    // MARK: - Placeholders / fallback text
    case placeholderAucun, placeholderAucune, placeholderLibre, placeholderInactive, placeholderInactif
    case placeholderSolo, placeholderCoupee, placeholderJamaisSauvegarde, placeholderJamaisSauvegardee
    case placeholderAucunRoleDeclare, placeholderAucuneSectionEncore
    case placeholderAucunMorceauCharge, placeholderAucuneSoundtrack
    case placeholderAucunePisteEnEcoute, placeholderPasAccordMorceau
    case placeholderAucuneSequenceGuide, placeholderSequenceVideGuide, placeholderEtapeNeResoutPas
    case placeholderGuideNonDemarre, placeholderRoueNonDisponible
    case placeholderAucuneSceneActive, placeholderAucunRolePourEnAjouter

    // MARK: - Format-string keys (static fragment, %d/%@ substituted)
    case formatSection, formatClientsConnectes, formatSuiteAccordsNamed, fieldSuiteAccords
    case formatInstrumentsNonAttaches

    // MARK: - Static console hint / status lines
    case hintMenuControls, labelEcranPrefix

    // MARK: - Static prompt text (promptLine call sites)
    case promptChargerSceneDemarrage, promptQuelSon, promptNomNouveauRole1, promptNomNouveauRole2
    case promptAttacherAQuelRole, promptRejoindreQuelServeur, promptTonPseudo
    case promptDossierMorceaux, promptDossierSons, promptDossierSoundtracks, promptDossierGuides
    case promptDossierScenes, promptDossierReglages, promptDossierCompositionIA
    case promptUtiliserQuelleConnexion, promptUtiliserQuellePalette
    case promptPortDefaut8080, promptPortDefaut8081
    case promptActiverQuelInstrument, promptActiverAussiSon, promptArreterQuelInstrument
    case promptActiverSonQuelInstrument, promptDesactiverSonQuelInstrument, promptPourQuelInstrument
    case promptNomDeLaScene, promptChargerQuelleScene, promptTitreDeLaScene
    case promptNomDuRole, promptQuelRole, promptQuelInstrument, promptQuelSonVideAucun
    case promptTitreDeLaSequence, promptTonique1, promptTonique2, promptIdGamme, promptProgressionAccords
    case promptChargerQuelleSequence, promptNomDeSauvegarde
    case promptPistesAEnregistrer, promptChargerQuelEnregistrement
    case promptNomDuMorceauIA, promptCombienDeCandidats
    case promptNomSauvegardePhraseDeCadrage, promptChargerQuellePhraseDeCadrage
    case promptIndicationsDeStyle, promptNomSauvegardeIndications, promptChargerQuellesIndications
    case promptChargerQuelMorceau, promptQuelleSection, promptQuellePiste, promptQuelSonOuVide
    case promptTitreDuMorceau, promptChargerQuelleDescription, promptNomExportPrompt
    case promptServeurDefautLocalhost, promptChargerQuelSon, promptPortDefaut7777
    case replModeCommand, replTapeAide

    // MARK: - Static multi-line paste prompts
    case pastePasteText, pastePasteDescription, pastePasteFraming

    // MARK: - Web console: extra field labels not needed by the terminal (structured form
    // fields — the terminal collects the same information via inline prompts instead)
    case fieldInstrument, fieldSection, fieldPiste, fieldEcoute, optionActiver, optionArreter
    case fieldTonique, fieldGamme, fieldProgression, fieldNombreCandidats, fieldPort, fieldHote

    // MARK: - Web console: short placeholder hints for MENU_ACTIONS text fields (distinct from
    // the terminal's full-sentence prompts — a placeholder is a hint shown INSIDE an empty
    // input, so it stays a short noun phrase, not a question)
    case placeholderCheminDuDossier, placeholderPort8080, placeholderPort8081, placeholderPort7777
    case placeholderNom, placeholderTitreCourt, placeholderIndicationsCourt
    case placeholderPistesSepareesParEspace, placeholderSectionNum, placeholderPisteNum
    case placeholderPseudoCourt, placeholderHoteCourt, placeholderUn

    // MARK: - Web console: MENU_ACTIONS item labels with no terminal equivalent (worded
    // differently from — or simply absent from — the terminal's own menu)
    case menuEcouteDunRole, menuAjouterModeAuGuideCourt, menuRechercherJamSessions, menuRejoindreSessionTrouvee
    /// Web console's `renderTrack` label — genuinely a different source string from the
    /// terminal's `fieldChord` ("Chord", left in English there): the web console has always
    /// shown this one in French ("Accord"), so it gets its own key rather than being forced to
    /// match the terminal's wording.
    case fieldAccordWeb
    /// Web console's shorter `renderRunTab` empty-state — distinct wording from the terminal's
    /// longer `placeholderAucunePisteEnEcoute` (no "menu Scene pour en activer une" hint, since
    /// the web console's equivalent action lives in the Commandes tab, not a dropdown menu).
    case placeholderAucunePisteEnEcouteWeb

    // MARK: - Web console: button / option / scene-tree / infos-tab static text
    case buttonOK, optionAucun, optionLibre
    case labelMode, labelSceneTree, labelInstrumentsLocaux, labelConsoleWebPrefix, labelClavierVirtuelPrefix
    case labelOui, labelNon, labelEcoutePrefix, labelSonPrefix, labelAucunInstrumentEncore
    case textInfosTab
    case headingCercleDesQuintes, headingGuide, headingMorceauEnCoursDeLecture, headingEnregistrementEnCoursDeLecture
    case fallbackTiret, fallbackConnexionPerdue, fallbackConnexionPerdueDetail

    // MARK: - Web page titles
    case titleConsoleWeb, titleClavierVirtuel

    // MARK: - Virtual keyboard page
    case vkHeading, vkHint, vkPromptDisplayName, vkPromptNewName, vkDefaultAlias
    case vkChanger, vkVousPrefix, vkDispositionClavierPrefix, vkHeadingGuide
    case vkPlaceholderAucuneNote, placeholderAucunAccordVK, placeholderPisteNonInitialisee
}

public enum L10n {
    /// Falls back to French, then to the raw key name, so a missing translation degrades
    /// gracefully instead of crashing — the `SanityChecks` completeness check is the real
    /// safety net for catching a missing entry during development.
    public static func string(_ key: L10nKey, _ language: AppLanguage) -> String {
        guard let entry = L10nTable.table[key] else { return key.rawValue }
        return entry[language] ?? entry[.fr] ?? key.rawValue
    }

    /// `String(format:)` wrapper for format-string keys (`%d`/`%@` placeholders).
    public static func string(_ key: L10nKey, _ language: AppLanguage, _ args: CVarArg...) -> String {
        String(format: string(key, language), arguments: args)
    }

    /// Renders every entry of `L10nTable.table` as a JS object literal
    /// `{ tabRun: { fr: '...', en: '...', de: '...' }, ... }` — generated once, in Swift, and
    /// embedded via string interpolation into `WebConsole/StaticAssets.swift`'s/
    /// `VirtualKeyboardAssets.swift`'s embedded `<script>` constants (both are plain compile-time
    /// Swift string literals, not a runtime template engine), so the FR/EN/DE text is written
    /// exactly once and never hand-copied into a second, JS-only table. Keyed by `L10nKey.rawValue`
    /// so a client-side `t(key, ...)` call uses the exact same key string as `L10n.string(.key, ...)`.
    public static var jsTableLiteral: String {
        func escape(_ text: String) -> String {
            text.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "'", with: "\\'")
                .replacingOccurrences(of: "\n", with: "\\n")
        }
        let entries = L10nKey.allCases.sorted { $0.rawValue < $1.rawValue }.compactMap { key -> String? in
            guard let translations = L10nTable.table[key] else { return nil }
            let fr = escape(translations[.fr] ?? "")
            let en = escape(translations[.en] ?? translations[.fr] ?? "")
            let de = escape(translations[.de] ?? translations[.fr] ?? "")
            return "  \(key.rawValue): { fr: '\(fr)', en: '\(en)', de: '\(de)' }"
        }
        return "const L10N = {\n" + entries.joined(separator: ",\n") + "\n};"
    }
}
