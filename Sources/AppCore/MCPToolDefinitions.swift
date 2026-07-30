import Foundation

/// One argument a menu action / MCP tool accepts — a hand-ported mirror of the same action's
/// entry in `MENU_ACTIONS` (`Sources/WebConsole/StaticAssets.swift`), which is JavaScript
/// embedded in a Swift string constant (the web console's own UI), not a native Swift value
/// this file could just import directly. This is the exact same "accepted duplication" the
/// Python `mcp-server/server.py` already had (see `ImprovSession.performMenuAction`'s own doc
/// comment) — now hand-ported to Swift instead of Python, same shape, same action names, same
/// fields. Kept deliberately minimal: only what's needed to generate an MCP JSON Schema and to
/// build the `[String: String]` query dict `performMenuAction` already expects — not a
/// general-purpose UI field descriptor (no `kind`/`placeholderKey`/`list` — those drive the web
/// console's own `<select>`/`<input>` rendering, meaningless to an MCP tool call).
public struct MCPActionField: Sendable {
    public let name: String
    public let optional: Bool
    public let description: String

    public init(name: String, optional: Bool = false, description: String) {
        self.name = name
        self.optional = optional
        self.description = description
    }
}

public struct MCPActionDefinition: Sendable {
    public let action: String
    public let description: String
    public let fields: [MCPActionField]

    public init(action: String, description: String, fields: [MCPActionField] = []) {
        self.action = action
        self.description = description
        self.fields = fields
    }
}

/// Every menu action `performMenuAction` already understands, exposed as an MCP tool — one
/// entry per `MENU_ACTIONS` item in `StaticAssets.swift`, same action name, same fields, same
/// order (JamShack, Scene, Guide Musicaux, Enregistrement, Morceaux, Composition, Jam Session).
/// 84 actions total — verified by reading `StaticAssets.swift` directly (an earlier research
/// summary had estimated 36, which undercounted; the direct source read here is authoritative).
public enum MCPToolDefinitions {
    public static let menuActions: [MCPActionDefinition] = [
        // MARK: - JamShack
        .init(action: "folder-pieces", description: "Charge les morceaux JSON existants d'un dossier (migration ponctuelle, plus nécessaire une fois migré).", fields: [.init(name: "value", description: "Chemin absolu du dossier")]),
        .init(action: "folder-samples", description: "Recharge la liste des fichiers son (soundfonts) d'un dossier.", fields: [.init(name: "value", description: "Chemin absolu du dossier")]),
        .init(action: "folder-soundtracks", description: "Charge les enregistrements JSON existants d'un dossier (migration ponctuelle).", fields: [.init(name: "value", description: "Chemin absolu du dossier")]),
        .init(action: "folder-guides", description: "Charge les guides musicaux JSON existants d'un dossier (migration ponctuelle).", fields: [.init(name: "value", description: "Chemin absolu du dossier")]),
        .init(action: "folder-scenes", description: "Charge les scènes JSON existantes d'un dossier (migration ponctuelle).", fields: [.init(name: "value", description: "Chemin absolu du dossier")]),
        .init(action: "folder-settings", description: "Définit le dossier de réglages (palettes, connexions LLM, etc.).", fields: [.init(name: "value", description: "Chemin absolu du dossier")]),
        .init(action: "folder-prompts", description: "Définit le dossier de composition IA (cadrages, exports de prompts).", fields: [.init(name: "value", description: "Chemin absolu du dossier")]),
        .init(action: "use-llm", description: "Active une connexion LLM enregistrée.", fields: [.init(name: "value", description: "Nom de la connexion LLM")]),
        .init(action: "use-palette", description: "Active une palette de couleurs enregistrée.", fields: [.init(name: "value", description: "Nom de la palette")]),
        .init(action: "midi-mode-merged", description: "Passe le mode MIDI en fusionné (une seule piste pour toutes les sources MIDI)."),
        .init(action: "midi-mode-individual", description: "Passe le mode MIDI en individuel (une piste par port MIDI visible)."),
        .init(action: "refresh-midi", description: "Rafraîchit la liste des ports MIDI visibles."),
        .init(action: "web-console-start", description: "Démarre la console web sur un port.", fields: [.init(name: "value", optional: true, description: "Port (défaut 8080)")]),
        .init(action: "web-console-stop", description: "Arrête la console web."),
        .init(action: "vk-start", description: "Démarre le clavier virtuel réseau sur un port.", fields: [.init(name: "value", optional: true, description: "Port (défaut 8081)")]),
        .init(action: "vk-stop", description: "Arrête le clavier virtuel réseau."),
        .init(action: "lumi-root-color", description: "Change la couleur des touches racines sur un clavier LUMI Keys.", fields: [.init(name: "value", description: "Couleur hexadécimale, ex. #FF0000")]),
        .init(action: "lumi-scale-color", description: "Change la couleur des touches de la gamme sur un clavier LUMI Keys.", fields: [.init(name: "value", description: "Couleur hexadécimale, ex. #00FF00")]),
        .init(action: "lumi-brightness", description: "Change la luminosité des LED d'un clavier LUMI Keys.", fields: [.init(name: "value", description: "Luminosité (0 à 1)")]),
        .init(action: "lumi-auto-run-on", description: "Active l'affichage automatique des notes jouées sur les LED LUMI."),
        .init(action: "lumi-auto-run-off", description: "Désactive l'affichage automatique des notes jouées sur les LED LUMI."),
        .init(action: "lumi-auto-guide-on", description: "Active l'affichage automatique du guide musical sur les LED LUMI."),
        .init(action: "lumi-auto-guide-off", description: "Désactive l'affichage automatique du guide musical sur les LED LUMI."),

        // MARK: - Scene
        .init(action: "track-on", description: "Active l'écoute/la reconnaissance d'une piste.", fields: [.init(name: "value", description: "Identifiant de piste")]),
        .init(action: "track-off", description: "Désactive l'écoute/la reconnaissance d'une piste.", fields: [.init(name: "value", description: "Identifiant de piste")]),
        .init(action: "track-sound-on", description: "Active le son d'une piste.", fields: [.init(name: "value", description: "Identifiant de piste")]),
        .init(action: "track-sound-off", description: "Désactive le son d'une piste.", fields: [.init(name: "value", description: "Identifiant de piste")]),
        .init(action: "track-instrument", description: "Choisit le fichier son (soundfont) d'une piste.", fields: [
            .init(name: "track", description: "Identifiant de piste"),
            .init(name: "value", description: "Nom du fichier son"),
        ]),
        .init(action: "track-recognition-mode", description: "Choisit le mode de reconnaissance micro d'une piste.", fields: [
            .init(name: "track", description: "Identifiant de piste"),
            .init(name: "value", description: "Mode : mono-heuristique, mono-hps, poly-latched, ou poly-glissant"),
        ]),
        .init(action: "scene-save", description: "Sauvegarde la scène courante sous un nom.", fields: [.init(name: "value", description: "Nom de la scène")]),
        .init(action: "scene-load", description: "Charge une scène enregistrée.", fields: [.init(name: "value", description: "Nom de la scène")]),
        .init(action: "scene-new", description: "Crée une nouvelle scène anonyme.", fields: [.init(name: "value", description: "Titre court")]),
        .init(action: "scene-role-add", description: "Ajoute un rôle à la scène courante.", fields: [.init(name: "value", description: "Nom du rôle")]),
        .init(action: "scene-role-sound", description: "Choisit le son d'un rôle de scène.", fields: [
            .init(name: "role", description: "Nom du rôle"),
            .init(name: "value", optional: true, description: "Nom du fichier son"),
        ]),
        .init(action: "scene-role-listen", description: "Active/désactive l'écoute d'un rôle de scène.", fields: [
            .init(name: "role", description: "Nom du rôle"),
            .init(name: "value", description: "on ou off"),
        ]),
        .init(action: "scene-role-attach", description: "Attache un instrument non affecté à un rôle de scène.", fields: [
            .init(name: "role", description: "Nom du rôle"),
            .init(name: "value", description: "Identifiant de l'instrument non affecté"),
        ]),
        .init(action: "scene-role-detach", description: "Détache l'instrument d'un rôle de scène.", fields: [.init(name: "value", description: "Nom du rôle")]),

        // MARK: - Guide Musicaux
        .init(action: "guide-new", description: "Crée un nouveau guide musical.", fields: [.init(name: "value", description: "Titre court")]),
        .init(action: "guide-add-mode", description: "Ajoute un mode (tonique+gamme, progression d'accords optionnelle) au guide courant.", fields: [
            .init(name: "tonic", description: "Note tonique, ex. C, D#, Bb"),
            .init(name: "scale", description: "Nom de la gamme"),
            .init(name: "progression", optional: true, description: "Nom d'un modèle de progression d'accords"),
        ]),
        .init(action: "guide-load", description: "Charge un guide musical enregistré.", fields: [.init(name: "value", description: "Nom du guide")]),
        .init(action: "guide-save", description: "Sauvegarde le guide courant (même nom)."),
        .init(action: "guide-save-as", description: "Sauvegarde le guide courant sous un nouveau nom.", fields: [.init(name: "value", description: "Nom du guide")]),
        .init(action: "guide-start", description: "Démarre la lecture du guide musical courant."),
        .init(action: "guide-stop", description: "Arrête la lecture du guide musical courant."),

        // MARK: - Enregistrement
        .init(action: "record-start", description: "Démarre l'enregistrement (pistes précisées, ou toutes par défaut).", fields: [.init(name: "value", optional: true, description: "Identifiants de pistes séparés par un espace")]),
        .init(action: "record-stop", description: "Arrête l'enregistrement en cours."),
        .init(action: "soundtrack-play", description: "Joue l'enregistrement courant."),
        .init(action: "soundtrack-load", description: "Charge un enregistrement sauvegardé.", fields: [.init(name: "value", description: "Nom de l'enregistrement")]),
        .init(action: "soundtrack-save", description: "Sauvegarde l'enregistrement courant (même nom)."),
        .init(action: "soundtrack-save-as", description: "Sauvegarde l'enregistrement courant sous un nouveau nom.", fields: [.init(name: "value", description: "Nom de l'enregistrement")]),
        .init(action: "soundtrack-compose", description: "Compose un ou plusieurs morceaux à partir de l'enregistrement courant, via le LLM actif.", fields: [
            .init(name: "value", optional: true, description: "Titre court du morceau"),
            .init(name: "count", optional: true, description: "Nombre de candidats à générer (défaut 1)"),
        ]),
        .init(action: "soundtrack-framing-set", description: "Modifie la phrase de cadrage active pour la composition depuis un enregistrement.", fields: [.init(name: "value", description: "Texte de la phrase de cadrage")]),
        .init(action: "soundtrack-framing-save", description: "Sauvegarde la phrase de cadrage courante sous un nom.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "soundtrack-framing-load", description: "Charge une phrase de cadrage enregistrée.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "soundtrack-framing-reset", description: "Revient à la phrase de cadrage par défaut."),
        .init(action: "soundtrack-instructions-set", description: "Modifie les indications de style actives pour l'enregistrement.", fields: [.init(name: "value", optional: true, description: "Texte des indications de style")]),
        .init(action: "soundtrack-instructions-save", description: "Sauvegarde les indications de style courantes sous un nom.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "soundtrack-instructions-load", description: "Charge des indications de style enregistrées.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "soundtrack-instructions-reset", description: "Revient aux indications de style par défaut (aucune)."),
        .init(action: "soundtrack-prompt-export", description: "Exporte le prompt complet de composition (enregistrement) dans un fichier texte.", fields: [.init(name: "value", description: "Nom du fichier d'export")]),

        // MARK: - Morceaux
        .init(action: "piece-play", description: "Joue le morceau courant."),
        .init(action: "piece-sample", description: "Choisit le fichier son utilisé pour la lecture du morceau courant.", fields: [.init(name: "value", description: "Nom du fichier son")]),
        .init(action: "piece-track-instrument", description: "Choisit le fichier son d'une piste précise du morceau courant.", fields: [
            .init(name: "section", description: "Numéro de section"),
            .init(name: "track", description: "Numéro de piste"),
            .init(name: "value", optional: true, description: "Nom du fichier son"),
        ]),
        .init(action: "piece-chord-instrument", description: "Choisit le fichier son des accords d'une section du morceau courant.", fields: [
            .init(name: "section", description: "Numéro de section"),
            .init(name: "value", optional: true, description: "Nom du fichier son"),
        ]),
        .init(action: "piece-load-demo", description: "Charge le morceau de démonstration."),
        .init(action: "piece-load", description: "Charge un morceau enregistré.", fields: [.init(name: "value", description: "Nom du morceau")]),
        .init(action: "piece-save", description: "Sauvegarde le morceau courant (même nom)."),
        .init(action: "piece-save-as", description: "Sauvegarde le morceau courant sous un nouveau nom.", fields: [.init(name: "value", description: "Nom du morceau")]),

        // MARK: - Composition
        .init(action: "composition-describe", description: "Définit la description texte libre du morceau à composer, via le LLM actif.", fields: [
            .init(name: "title", optional: true, description: "Titre court"),
            .init(name: "value", description: "Description texte libre du morceau souhaité"),
            .init(name: "instructions", optional: true, description: "Indications de style courtes"),
        ]),
        .init(action: "composition-compose", description: "Compose un morceau à partir de la description courante, via le LLM actif."),
        .init(action: "composition-load", description: "Charge une description de composition enregistrée.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "composition-save-as", description: "Sauvegarde la description de composition courante sous un nouveau nom.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "composition-save", description: "Sauvegarde la description de composition courante (même nom)."),
        .init(action: "text-framing-set", description: "Modifie la phrase de cadrage active pour la composition texte.", fields: [.init(name: "value", description: "Texte de la phrase de cadrage")]),
        .init(action: "text-framing-save", description: "Sauvegarde la phrase de cadrage courante sous un nom.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "text-framing-load", description: "Charge une phrase de cadrage enregistrée.", fields: [.init(name: "value", description: "Nom")]),
        .init(action: "text-framing-reset", description: "Revient à la phrase de cadrage par défaut."),
        .init(action: "text-prompt-export", description: "Exporte le prompt complet de composition (texte) dans un fichier texte.", fields: [.init(name: "value", description: "Nom du fichier d'export")]),

        // MARK: - Jam Session
        .init(action: "jam-start", description: "Démarre une Jam Session en tant qu'hôte.", fields: [
            .init(name: "pseudo", optional: true, description: "Pseudo court affiché aux autres participants"),
            .init(name: "value", optional: true, description: "Port (défaut 7777)"),
        ]),
        .init(action: "jam-stop", description: "Arrête la Jam Session hébergée."),
        .init(action: "jam-join", description: "Rejoint une Jam Session en indiquant son adresse.", fields: [
            .init(name: "pseudo", optional: true, description: "Pseudo court affiché aux autres participants"),
            .init(name: "host", description: "Adresse ou nom d'hôte"),
            .init(name: "port", optional: true, description: "Port (défaut 7777)"),
        ]),
        .init(action: "jam-discover", description: "Recherche les Jam Sessions annoncées sur le réseau local."),
        .init(action: "jam-connect-discovered", description: "Rejoint une Jam Session trouvée par la recherche réseau.", fields: [.init(name: "value", description: "Index (0-based) dans la liste des sessions trouvées")]),
        .init(action: "jam-leave", description: "Quitte la Jam Session rejointe."),
    ]
}
