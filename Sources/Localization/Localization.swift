import Foundation
import SwiftData

/// The UI display language — independent of command names/syntax, which are never translated.
/// French is the authored reference language; every other case is a translation of it.
public enum AppLanguage: String, Codable, CaseIterable, Sendable, Hashable {
    case fr, en, de, ja, zhHans, it, es, pt, ru
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

/// The SwiftData-backed singleton counterpart of `LanguageSettingFile` — see
/// `AppCore.ColorPaletteRecord`'s doc comment for the split rationale shared by every settings
/// record in this migration wave. `language` is the raw `AppLanguage` string, not the enum
/// itself, so a future language added to `AppLanguage` never requires a schema migration.
@Model
public final class LanguageSettingRecord {
    public var language: String = AppLanguage.fr.rawValue

    public init(_ language: AppLanguage) {
        self.language = language.rawValue
    }

    public var asAppLanguage: AppLanguage {
        AppLanguage(rawValue: language) ?? .fr
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
    case tabRun, tabConfig, tabGuideMusical, tabScene, tabObserver, tabCommandes, tabInfos, tabClavier

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
    case menuLangueFr, menuLangueEn, menuLangueDe, menuLangueJa, menuLangueZhHans, menuLangueIt, menuLangueEs, menuLanguePt, menuLangueRu
    case headerReglagesLumi
    case menuLumiCouleurRacine, menuLumiCouleurGamme, menuLumiLuminosite
    case menuLumiAutoRunActiver, menuLumiAutoRunDesactiver
    case menuLumiAutoGuideActiver, menuLumiAutoGuideDesactiver
    case menuRefreshMidi
    case promptLumiCouleurRacineHex, promptLumiCouleurGammeHex, promptLumiLuminosite0100
    case fieldLumiAutoRun, fieldLumiAutoGuide
    case fieldLumiCouleurRacine, fieldLumiCouleurGamme, fieldLumiLuminosite
    case menuQuitter

    // MARK: - "Scene" category items
    case menuListerInstruments, menuActiverInstrument, menuArreterInstrument
    case menuActiverSonInstrument, menuDesactiverSonInstrument
    case menuChoisirSonPourInstrument
    case menuChoisirModeReconnaissanceMicro
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
    case fieldModeReconnaissance
    case fieldDuree, fieldEvenements, fieldPistes, fieldTitre, fieldIndications, fieldDescription, fieldPseudo, fieldRole

    // MARK: - Headings
    case headingDetailMorceauActif, headingDerouleComposition
    case headingClavierComposeEnCours, headingClavierSoundtrackEnCours
    case headingSequence, headingClavierGuide, headingClavierAccordGuide
    case headingTablatureGuide, placeholderPasDePositionGuitareStandard

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
    case promptQuelModeDeReconnaissance
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
    case fieldInstrument, fieldSection, fieldPiste, fieldEcoute, optionArreter
    case optionMonoHeuristique, optionMonoHPS, optionPolyLatched, optionPolySliding
    case fieldTonique, fieldGamme, fieldProgression, fieldNombreCandidats, fieldPort, fieldHote

    // MARK: - Web console: short placeholder hints for MENU_ACTIONS text fields (distinct from
    // the terminal's full-sentence prompts — a placeholder is a hint shown INSIDE an empty
    // input, so it stays a short noun phrase, not a question)
    case placeholderCheminDuDossier, placeholderPort8080, placeholderPort8081, placeholderPort7777
    case placeholderNom, placeholderTitreCourt, placeholderIndicationsCourt
    case placeholderPistesSepareesParEspace, placeholderSectionNum, placeholderPisteNum
    case placeholderPseudoCourt, placeholderHoteCourt, placeholderUn
    case placeholderLumiCouleurHex, placeholderLumiLuminosite

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
    /// Web console's own Guide panel headings — plain (no baked-in arrow hint), unlike the
    /// terminal's `headingClavierGuide`/`headingClavierAccordGuide` which still carry theirs
    /// inline. `hintNavigationGuideWeb` is the single italic line shown once beneath the mode+
    /// chord detail text instead, consolidating both hints in one place.
    case headingModeEtAccordGuideWeb, hintNavigationGuideWeb
    case headingPartitionGuideWeb
    /// Shorter than the terminal/virtual-keyboard page's own `headingTablatureGuide` ("Tablature
    /// guitare:") — web-console-only wording, doesn't affect either of those.
    case headingTablatureGuideWeb
    case fallbackTiret, fallbackConnexionPerdue, fallbackConnexionPerdueDetail

    // MARK: - Web page titles
    case titleConsoleWeb, titleClavierVirtuel

    // MARK: - Virtual keyboard page
    case vkHeading, vkHint, vkPromptDisplayName, vkPromptNewName, vkDefaultAlias
    case vkChanger, vkVousPrefix, vkDispositionClavierPrefix, vkHeadingGuide
    case vkPlaceholderAucuneNote, placeholderAucunAccordVK, placeholderPisteNonInitialisee

    // MARK: - App (SwiftUI native): shared buttons / alerts / defaults reused across screens
    case appChoisirEllipsis, appChangerEllipsis, appCreer, appAnnuler, appButtonSauvegarderDansCeDossier
    case appButtonArreter, appButtonDemarrer, appNouveauGuide, appNouvelleScene, appNouvelleComposition, appButtonReglages
    case appModeApp, appModeLumi, appHeadingNotesEtAccords
    case appHeadingCadrageTexte, appHeadingCadrageSoundtrack, appHeadingIndicationsSoundtrack
    case appButtonSauvegarderSous
    case appButtonSuggererParIA
    case appDefaultNouvellePalette, appDefaultGuideTitle, appDefaultMorceauFilename
    /// "%@ (canal %d)" — reused everywhere a MIDI-capable track's own label is shown, next
    /// to `ImprovSession.displayedChannel(for:)`.
    case appFormatCanalMidi

    // MARK: - App: main TabView + JamShack sidebar + sub-tab sidebars (accessibility labels)
    case appTabStudio, appTabEnregistrements, appStatusDemarrage
    case appTabSons, appTabMIDI, appTabMicrophone, appTabCouleurs, appTabLangue, appTabLLM
    case appTabFichierMorceau, appTabFichierSoundtrack
    case appTabFichierComposition, appTabComposerCourt

    // MARK: - App: Composition tab (Fichier + Composer sub-tabs)
    case appPlaceholderTitreMorceau, appPlaceholderIndicationsStyleOpt, appHeadingDescriptionMorceau
    case appHintDecrisMorceauTexteLibre, appStatusCompositionEnCours, appButtonComposerDepuisDescription
    case appHeadingCompositionIA, appHintUtiliseConnexionLLMSeule
    case appPlaceholderAucunDossierCompositionIA, appButtonSauvegarderDescriptionDossier, appHeadingDossierCompositionIA

    // MARK: - App: JamShack > Sons (still-used leftover from the removed "Dossiers" tab)
    case appLabelDossierSons

    // MARK: - App: Guide tab (list -> configuration flow)
    case appPlaceholderAucunDossierGuides, appHeadingDossierGuides
    case appFieldProgressionAccordsGuide, appOptionAucuneFem
    case appButtonAjouterModeAuGuide, appHeadingAjouterUnMode
    case appHeadingClavierDuMode, appHeadingClavierAccord
    case appButtonDemarrerLeGuide, appButtonArreterLeGuide, appButtonPrecedent, appButtonSuivant, appLabelEnDirect
    case appHeadingEtapes
    case appFormatSuiteAccordsPrefix, appLabelSuiteAccordsSansNom

    // MARK: - App: Morceaux tab (Fichier/Play sub-tabs)
    case appHeadingJouer, appPlaceholderAucunSonFavori, appHeadingSonDeLecture, appHintSonParDefaut
    case appPlaceholderAucunMorceauChargeOnglet, appPlaceholderAucunMorceauChargePoint
    case appButtonChargerLaDemo, appHeadingMorceauCharge
    case appPlaceholderAucunDossierMorceaux, appHeadingDossierMorceaux
    case appFormatFragmentsBPM

    // MARK: - App: Enregistrement tab (Fichier/Record/Play/IA sub-tabs)
    case appPlaceholderAucunDossierSoundtracks, appHeadingDossierSoundtracks
    case appStatusEnregistrementEnCours, appButtonArreterEnregistrement, appButtonDemarrerEnregistrement
    case appHintChoisisPistesEnregistrer
    case appPlaceholderAucunEnregistrementRecordFichier, appPlaceholderAucunEnregistrementRecord
    case appFormatEvenementsDuree, appHeadingEnregistrementActuel
    case appPlaceholderTitreOptionnel, appButtonComposerDepuisEnregistrement
    case appHeadingCompositionIADepuisEnregistrement, appHintUtiliseConnexionLLMEtDossier

    // MARK: - App: Scene tab (Fichier/Disposition sub-tabs)
    case appButtonRechargerScene, appHintRechargeScene
    case appPlaceholderAucunDossierScenes, appHeadingDossierScenes
    case appButtonExporter, appButtonImporter
    case appButtonRenommer, appAlertRenommerScene, appAlertRenommerGuide, appPlaceholderSansNom
    case appModeEdition, appModeLecture
    case appAlertNouveauRole, appPlaceholderNomExPiano1, appButtonAjouter
    case appPlaceholderTousInstrumentsAffectes, appHeadingInstrumentsNonAffectes
    case appButtonAjouterUnRole, appButtonAjouterUnRoleEllipsis, appButtonCreerEtAttacher
    case appMenuAttacherA, appButtonDetacher, appLabelLibre
    case appPlaceholderAucunSonFavoriParenthese, appButtonAucun, appButtonSupprimer
    case appFormatOccupeParRole
    case appFieldVolume

    // MARK: - App: JamShack > Sons (SoundsView)
    case appPlaceholderAucunSonTrouve, appPlaceholderRechercherSonAlias, appFormatSonsCompte
    case appHintCocheEtoileFavoris, appFieldAlias
    case appToggleModeTestSon, appFieldSourceTest, appPlaceholderChoisirSourceTest
    case appHeadingTesterLeSon, appHintTesterLeSon
    case appPlaceholderRechercherFichier, appPlaceholderChoisirFichierSons
    case appHeadingFichiersSoundfont, appFormatFichiersCompte
    case appButtonTelecharger, appLabelSynchronise, appLabelLocalUniquement, appLabelNonTelecharge
    case appHeadingProfilStockage, appOptionProfilEconome, appOptionProfilStandard, appOptionProfilGenereux
    case appTabBibliotheque, appTabFavoris, appTabStockage
    case appAlertSupprimerSoundFont, appHintSupprimerSoundFont, appPlaceholderAucunFavori
    case appHintSyncBadgeToggle
    case appToggleFichierPartage, appButtonFermer
    case appLabelNomFichier, appLabelTaille, appLabelAjouteLe, appLabelOrigine
    case appOptionOrigineImporte, appOptionOrigineCuree, appLabelEtiquettes
    case appHeadingMetadonneesFichier, appLabelBanque, appLabelMoteurSonore, appLabelDateCreationFichier
    case appLabelIngenieur, appLabelProduit, appLabelCopyright, appLabelCommentaire, appLabelLogiciel
    case appPlaceholderAucuneMetadonnee, appHintTelechargerPourMetadonnees
    case appHeadingUtilisationStockage, appLabelStockageLocal, appLabelStockageICloud
    case appLabelAutresFichiers, appLabelEspaceLibre, appHintPasDeQuotaICloud
    case appHintProfilStockageExplication
    case appLabelSeuilLocal, appLabelSeuilICloud, appUnitGo, appHintSeuilDepasse
    case appButtonNettoyerBibliotheque, appAlertNettoyerBibliotheque, appHintNettoyerBibliotheque

    // MARK: - App: JamShack > Sons > Catalogue de banques offertes
    case appButtonParcourirCatalogue, appHeadingCatalogue, appButtonInstaller
    case appFormatCatalogueParAuteur, appHintCatalogueImportManuelAussi
    case appButtonEnSavoirPlus, appLabelAttributionRequise, appLabelLicence
    case appLabelCatalogueMiseAJourDisponible, appButtonMettreAJour
    case appPlaceholderRechercherCatalogue, appLabelRecommande
    case appHeadingCredits, appPlaceholderAucunCredit, appHintCredits
    case appPlaceholderAucuneEntreeCatalogue
    case appButtonAbandonner, appFormatTelechargementPourcent, appLabelInstallationEnCours

    // MARK: - App: JamShack > I.A. > Serveur MCP
    case appToggleServeurMCP, appFormatHintServeurMCP, appPlaceholderDossierDuProjet, appButtonCopier

    // MARK: - App: JamShack > Clavier ordinateur
    case appTabClavierOrdinateur, appLabelClavierOrdinateurActif

    // MARK: - App: JamShack > MIDI
    case appOptionFusionne, appOptionIndividuel, appHintModeMidiDetail
    case appButtonRafraichirListeMidi, appPlaceholderAucuneSourceMidi, appHeadingSourcesMidiVisibles

    // MARK: - App: JamShack > Couleurs (palette + LUMI settings + LUMI tester)
    case appButtonNouvellePalette, appHeadingCouleurRacine, appHeadingCouleurGamme, appFormatLuminositePourcent
    case appToggleModeRunPropagation, appToggleModeGuidePropagation
    case appHeadingLumiKeys, appHintPropagationAutoLumi
    case appButtonListerDestinationsMidi, appPlaceholderAucuneDestinationMidi
    case appFieldIDAppareilHex, appPlaceholder34
    case appButtonTesterModePiano, appButtonTesterCarteGuide, appHeadingTesteurLumi, appHintTesteurLumiDetail
    case appFieldNomCapital, appHeadingNomPalette, appHeadingCouleursParNote, appButtonEnregistrer, appNavTitleModifierPalette

    // MARK: - App: JamShack > Langue
    case appFieldLangue, appHeadingLangueInterface, appHintLangueAppliqueAussi

    // MARK: - App: JamShack > LLM
    case appPlaceholderAucuneConnexionLLM, appHeadingConnexionsLLM, appStatusTestEnCours, appButtonTesterConnexion
    case appButtonAjouterConnexionLLM, appButtonDepuisUnModele, appButtonImporterFichierJSON
    case appHeadingConnexionActive, appHintEnvoiePromptMinimal, appFormatClefAPI, appButtonSauvegarderLaClef
    case appWarningClefTexteClair, appFieldFournisseur, appFieldModele

    // MARK: - App: Microphone tab
    case appLabelMicrophoneActif, appButtonDemarrerEcoute, appHeadingReconnaissance, appHeadingMicrophone
    case appHintDetectionMicrophone, appButtonReinitialiser, appHeadingNiveau, appHeadingCalibrationNiveau
    case appFieldAffichage, appLabelNotesRecues, appLabelSpectrometre, appHintSpectreFFT, appToggleActiverSpectrometre
    case appButtonTerminerCapture, appButtonCapturer, appLabelNoteFaible, appLabelNoteForte
    case appHintCalibrationNiveau, appFormatEnCoursDeCapture
    case appLabelSpectrogramme, appHintSpectrogramme, appLabelCalibrationCourt
    case appToggleAfficherNotesSpectrogramme
    case appFieldPaletteSpectrogramme, appPaletteThermique, appPaletteBleu, appPaletteNiveauxDeGris

    // MARK: - App: Serveurs tab
    case appHintServeurPremierPlan, appFormatRejoinsMoiSur, appHintConsoleWebCaption, appHintClavierVirtuelCaption

    // MARK: - App: Jam Session tab
    case appFormatGameCenterErreur, appHintNomAfficheParticipants
    case appHeadingCetAppareil, appHeadingAppareilsConnectes
    case appButtonReorganiser, appButtonTerminerReorganisation
    case appButtonVoirLeGuide
    case appHeadingEcouterLeGuide, appFieldVitesse
    case appSectionHebergerReseauLocal, appFormatServeurActifPort, appButtonArreterLeServeur
    case appSectionRejoindreReseauLocal, appFormatConnecteA, appButtonSeDeconnecter
    case appSectionOrganisateurGameCenter, appLabelSessionGameCenterActive, appButtonArreterLaSession
    case appSectionParticipantGameCenter, appHintModeIsole
    case appPlaceholder7777, appPlaceholderLocalhost, appButtonDemarrerLeServeur, appButtonSeConnecter
    case appStatusRecherche, appButtonRechercherReseauLocal, appPlaceholderAucunServeurTrouve
    case appHeadingRechercher, appHintServeurReseauLocal
    case appStatusConnexionGameCenter, appButtonInviterTrouverParticipants, appHintOuvreFenetreGameCenterOrganisateur
    case appButtonRejoindreViaGameCenter, appHintAccepteInvitationGameCenter
    case appModeIsole, appModeJamGameCenterOrganisateur, appModeJamGameCenterParticipant
    case appModeJamLocaleOrganisateur, appModeJamLocaleParticipant
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
