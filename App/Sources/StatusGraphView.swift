import SwiftUI
import AppCore
import Localization
import MusicTheoryKit

/// "Accueil" — a read-only diagram of the app's live topology, its own top-level tab (not a
/// Settings sub-tab — self-explanatory entry point, house icon, per explicit request) showing:
/// the App, branching to every live input source (grouped by kind — clavier principal, MIDI,
/// microphone, clavier virtuel, réseau), annotating whichever one currently feeds the "clavier
/// principal" (`session.theoryLiveInputSourceID`) with its own sound + tuning, then the active
/// scene's roles on the right, linked to whichever source each is attached to. Purely
/// observational — no scene picker, no editing the links from here (deferred, see this struct's
/// own doc comment on phase 2).
///
/// Source -> role is confirmed strictly 1-for-1 in practice: `ImprovSession.attachInstrument
/// (_:toRole:)` auto-detaches a track from any OTHER role before attaching it to a new one (its
/// own doc comment calls this "the invariant that an instrument occupies only one role"), and the
/// role-editing picker (`SceneLayoutView`) only ever offers `session.unassignedInstruments()`.
/// So sorting attached roles by their own source's row position (`layout(...)` below) yields an
/// EXACT zero-crossing result, not just a heuristic.
///
/// Server/client hierarchy (Server -> Client -> [Device] -> Source columns), per explicit
/// request: both Jam Session server kinds (`.server`/`.gameCenterServer` in
/// `session.networkRole`), the web-keyboard server (`session.virtualKeyboardPort`), and the local
/// "Sources MIDI Locales" hub are ALWAYS shown, even inactive — their own node's border/opacity
/// is the same 3-state activity language every other node uses, just without a `.playing`
/// sub-state of their own beyond aggregating their children's. A connected Jam Session
/// participant's own tracks are `TrackID.remote(clientID:trackID:)` — `trackID` is decoded via
/// `TrackID(wireIDText:)` (the exact wire format
/// `ImprovSession.announceTrackToServerIfClient`/`forwardNoteEventToServerIfClient` already send)
/// so a remote participant's own MIDI split shows the same Device-column grouping a local split
/// does — just parented to that participant's own Client node instead of straight to App.
///
/// The source currently feeding Théorie's own live-match/observation point
/// (`session.theoryLiveInputSourceID`) gets a RED ring, independent of the green activity
/// language — confirmed against `ImprovSession.setTheoryLiveInputSource`: picking one only ever
/// starts/enables sound on that ONE track (restoring whatever the previous pick had before it was
/// touched) and never mutates any OTHER track — so it is purely an observation choice, never a
/// cause of some other source going quiet, and the diagram must not conflate the two.
struct StatusGraphView: View {
    let session: ImprovSession
    var isDetachedWindow: Bool = false

    #if os(macOS) || os(visionOS)
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow
    #endif

    // MARK: - Node activity (3-state marking, per explicit request)

    /// `.neutral` — not listening / no sound enabled (or, for a role, attached to such a source,
    /// or not attached at all; or, for a server/client hub, not currently running/connected).
    /// `.active` — listening AND sound-enabled (or a server/client that IS running/connected),
    /// but nothing held right now. `.playing` — same as `.active`, plus at least one pitch
    /// actually held THIS INSTANT (a hub aggregates `.playing` from any of its own children) —
    /// free to compute live since `session.tracks`/`heldPitches` are already `@Observable` (same
    /// principle `ChordLibraryView.liveHeldPitches` already relies on for its own re-render).
    private enum NodeActivity: Equatable {
        case neutral, active, playing

        var strokeColor: Color {
            switch self {
            case .neutral: return .secondary.opacity(0.35)
            case .active, .playing: return .green
            }
        }
        var lineWidth: CGFloat { self == .neutral ? 1 : 2 }
        var dash: [CGFloat] { self == .neutral ? [4, 3] : [] }
        var fillOpacity: Double { self == .playing ? 0.28 : 0 }
    }

    private struct SourceNode {
        let id: TrackID
        let label: String
        let activity: NodeActivity
        /// Non-nil only for whichever source is `session.theoryLiveInputSourceID` — its own
        /// sound + active tuning, per explicit request.
        let mainKeyboardAnnotation: String?
        /// Non-nil only for a `.midiSplitZone` track — that zone's own source pitch range and,
        /// if it applies an octave shift, its transposed range too (e.g. "C3–F8 → C4–F9").
        let splitRangeAnnotation: String?
        /// `nil` connects straight to the App node (every local, non-networked source, as
        /// before) — otherwise the id of a hub node (device/client/server) in an earlier column.
        let parentID: String?
    }

    private enum SourceRow: Identifiable {
        case header(String)
        case node(SourceNode)
        var id: String {
            switch self {
            case .header(let title): return "sh-\(title)"
            case .node(let node): return "sn-\(node.id)"
            }
        }
    }

    /// A generic small box for the Server/Client/Device columns — same visual language as a
    /// `SourceNode`/`RoleNode`, just identified by a composite string id (not a `TrackID`) since
    /// these represent a grouping, not one addressable live track.
    private struct HubNode: Identifiable {
        let id: String
        let label: String
        let subtitle: String?
        let activity: NodeActivity
        /// `nil` connects straight to the App node (a local MIDI split device, or either Jam
        /// Session server, or the web-keyboard server) — otherwise a Client hub's own id (a
        /// remote split device, or a Jam Session client itself).
        let parentID: String?
    }

    private struct RoleNode {
        let id: UUID
        let name: String
        let detail: String
        let activity: NodeActivity
        let attachedTrackID: TrackID?
    }

    private enum RoleRow: Identifiable {
        case header(String)
        case node(RoleNode)
        var id: String {
            switch self {
            case .header(let title): return "rh-\(title)"
            case .node(let node): return "rn-\(node.id)"
            }
        }
    }

    private struct DiagramLayout {
        var serverNodes: [(node: HubNode, centerY: CGFloat)] = []
        var clientNodes: [(node: HubNode, centerY: CGFloat)] = []
        var deviceNodes: [(node: HubNode, centerY: CGFloat)] = []
        var sourceRows: [(row: SourceRow, centerY: CGFloat)] = []
        var roleRows: [(row: RoleRow, centerY: CGFloat)] = []
        var sourceCenterY: [TrackID: CGFloat] = [:]
        var sourceActivityByID: [TrackID: NodeActivity] = [:]
        /// Unified lookup for every hub node (server/client/device) by its own composite id —
        /// how a child (client under a server, device under a client, source under any of them)
        /// finds its own parent's position when drawing its connecting line.
        var hubCenterY: [String: CGFloat] = [:]
        var totalHeight: CGFloat = 0
        var appCenterY: CGFloat = 0
        /// Column X positions — computed once per `layout`, NOT static constants, because an
        /// empty Client or Device column (e.g. no Jam Session participant, no split MIDI device)
        /// must collapse instead of leaving a fixed-width gap of dead space (see `columnXPositions`
        /// below for how these are assigned).
        var serverX: CGFloat = 0
        var clientX: CGFloat = 0
        var deviceX: CGFloat = 0
        var sourceX: CGFloat = 0
        var roleX: CGFloat = 0
        var totalWidth: CGFloat = 0
    }

    // MARK: - Layout constants

    private static let appWidth: CGFloat = 150
    private static let hubWidth: CGFloat = 190
    private static let nodeWidth: CGFloat = 240
    private static let nodeRowHeight: CGFloat = 46
    private static let headerRowHeight: CGFloat = 20
    private static let rowSpacing: CGFloat = 8
    private static let columnGap: CGFloat = 56
    private static let leftMargin: CGFloat = 24
    private static let topMargin: CGFloat = 24

    private static let appX: CGFloat = leftMargin
    /// Y for the horizontal "bus" run of a link that skips over one or more populated columns
    /// (see `stroke(from:to:activity:)`) — comfortably above `topMargin` so that run never
    /// shares a row with any node, in any column.
    private static let aerialY: CGFloat = 8

    // MARK: - Data — local sources

    private func activity(isListening: Bool, soundEnabled: Bool, heldPitches: Set<Int>) -> NodeActivity {
        guard isListening, soundEnabled else { return .neutral }
        return heldPitches.isEmpty ? .active : .playing
    }

    /// Every user-visible track — excludes `.dissonancePreview` (a permanent but never-user-
    /// facing track, see `TrackID.dissonancePreview`'s own doc comment).
    private var sourceTracks: [TrackInfo] {
        session.tracks.filter {
            if case .dissonancePreview = $0.id { return false }
            return true
        }
    }

    private func category(for id: TrackID) -> String {
        switch id {
        case .computerKeyboard: return L10n.string(.appTabClavierPrincipal, session.currentLanguage)
        case .midiMerged, .midiSource, .midiSplitZone: return L10n.string(.appTabMIDI, session.currentLanguage)
        case .microphone: return L10n.string(.appTabMicrophone, session.currentLanguage)
        case .webKeyboard: return L10n.string(.fieldClavierVirtuel, session.currentLanguage)
        case .remote: return L10n.string(.fieldReseau, session.currentLanguage)
        case .dissonancePreview: return ""
        }
    }

    private func temperamentLabel(forID id: String) -> String {
        switch id {
        case "equal": return L10n.string(.appTemperamentEqual, session.currentLanguage)
        case "pythagorean": return L10n.string(.appTemperamentPythagorean, session.currentLanguage)
        case "justIntonation": return L10n.string(.appTemperamentJustIntonation, session.currentLanguage)
        case "werckmeisterIII": return L10n.string(.appTemperamentWerckmeisterIII, session.currentLanguage)
        default: return id
        }
    }

    /// The parent MIDI source's index, only for a LOCAL split zone — the piece that lets zone
    /// rows be re-grouped by their real originating device for the Device column.
    private func midiSplitSourceIndex(for id: TrackID) -> Int? {
        if case .midiSplitZone(let sourceIndex, _) = id { return sourceIndex }
        return nil
    }

    /// Decodes a REMOTE track's own wire-format `trackID` string back into a structured
    /// `TrackID` — the exact same format `TrackID.wireIDText`/`init?(wireIDText:)` already round-
    /// trip for every LOCAL track kind (confirmed: the sending side literally calls
    /// `track.id.wireIDText`/`track.wireIDText` when announcing to — or forwarding events from —
    /// a Jam Session server). `nil` for `.remote`'s own unrecognized/opaque cases, or for
    /// anything that isn't `.remote` at all — never crashes on an unexpected shape (e.g. a future
    /// or older client sending an id this build doesn't know).
    private func decodedRemoteKind(_ id: TrackID) -> TrackID? {
        guard case .remote(_, let wireID) = id else { return nil }
        return TrackID(wireIDText: wireID)
    }

    private func sourceNode(for track: TrackInfo, parentID: String?) -> SourceNode {
        let act = activity(isListening: track.isListening, soundEnabled: track.soundEnabled, heldPitches: track.heldPitches)
        var annotation: String?
        if track.id == session.theoryLiveInputSourceID {
            let soundLabel = session.theoryAuditionSound().map { session.displayName(forSamplePath: $0.path, preset: $0.preset) }
            annotation = "\(soundLabel ?? "—") · \(temperamentLabel(forID: session.tuningConfiguration.temperamentID))"
        }
        return SourceNode(
            id: track.id, label: track.label, activity: act, mainKeyboardAnnotation: annotation,
            splitRangeAnnotation: splitRangeLabel(for: track.id), parentID: parentID
        )
    }

    /// Only for a LOCAL split zone (`decodedRemoteKind` deliberately not consulted here — a
    /// remote participant's own zone index refers to THEIR device list, not
    /// `session.availableMIDISourceDescriptors()`, so resolving it against this session's split
    /// config would be plain wrong): that zone's own source pitch range, and its transposed
    /// range too when `octaveShift != 0` (omitted when the shift is 0 — the two ranges would be
    /// identical, redundant to show twice).
    private func splitRangeLabel(for id: TrackID) -> String? {
        guard case .midiSplitZone(let sourceIndex, let zoneID) = id else { return nil }
        guard let split = session.activeMIDIKeyboardSplit(atSourceIndex: sourceIndex),
              let zone = split.zones.first(where: { $0.id == zoneID }) else { return nil }
        let sourceRange = "\(noteLabel(zone.lowPitch))–\(noteLabel(zone.highPitch))"
        guard zone.octaveShift != 0 else { return sourceRange }
        let shift = zone.octaveShift * 12
        let transposedRange = "\(noteLabel(zone.lowPitch + shift))–\(noteLabel(zone.highPitch + shift))"
        return "\(sourceRange) → \(transposedRange)"
    }

    /// Same note-naming convention as `MIDIKeyboardSplitEditorView.noteLabel(forMidiPitch:)`.
    private func noteLabel(_ midi: Int) -> String {
        let pitchClass = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return "\(session.notationStyle.rootName(PitchClass(pitchClass), preferFlats: false))\(octave)"
    }

    // MARK: - Data — Jam Session (server/client hierarchy)

    /// One entry per currently-connected participant (works for EITHER Jam Session server kind —
    /// `ImprovSession.connectedClients()` itself is gated to `networkRole.isServerRole` and
    /// returns `[]` otherwise, so this is always safe to read) — a participant with no announced
    /// track yet still shows up here, per that method's own doc comment.
    private var jamSessionClients: [(clientID: String, name: String)] {
        session.networkRole.isServerRole ? session.connectedClients() : []
    }

    private func remoteTracks(forClientID clientID: String) -> [TrackInfo] {
        sourceTracks.filter { if case .remote(let cid, _) = $0.id { return cid == clientID }; return false }
    }

    private var webKeyboardTracks: [TrackInfo] {
        sourceTracks.filter { if case .webKeyboard = $0.id { return true }; return false }
    }

    /// Every leaf source row this screen ever shows, in fixed top-to-bottom order: the local
    /// direct categories first (unchanged from before), then web-keyboard clients (parented to
    /// the web-keyboard server hub), then each Jam Session client's own sources (parented to
    /// that client's hub, or to a per-client Device hub when a remote source decodes as a split
    /// MIDI zone) — a header row precedes each group exactly like the local MIDI/owner grouping
    /// already did.
    private var sourceRowsUnpositioned: [SourceRow] {
        var rows: [SourceRow] = []

        // Local, non-networked categories — unchanged.
        let directCategories = [
            L10n.string(.appTabClavierPrincipal, session.currentLanguage),
            L10n.string(.appTabMIDI, session.currentLanguage),
            L10n.string(.appTabMicrophone, session.currentLanguage),
        ]
        var byCategory: [String: [TrackInfo]] = [:]
        var order: [String] = []
        for track in sourceTracks {
            switch track.id {
            case .webKeyboard, .remote: continue // handled separately below
            default: break
            }
            let key = category(for: track.id)
            if byCategory[key] == nil { order.append(key) }
            byCategory[key, default: []].append(track)
        }
        for categoryName in directCategories where order.contains(categoryName) {
            guard let tracks = byCategory[categoryName], !tracks.isEmpty else { continue }
            rows.append(.header(categoryName))
            for track in tracks {
                let parentID: String?
                if let sourceIndex = midiSplitSourceIndex(for: track.id) {
                    parentID = "device:local:\(sourceIndex)"
                } else if categoryName == L10n.string(.appTabMIDI, session.currentLanguage) {
                    parentID = "hub:localmidi"
                } else {
                    parentID = nil
                }
                rows.append(.node(sourceNode(for: track, parentID: parentID)))
            }
        }

        // Web keyboard clients — parented to the (always-present) web-keyboard server hub.
        let webTracks = webKeyboardTracks
        if !webTracks.isEmpty {
            rows.append(.header(L10n.string(.fieldClavierVirtuel, session.currentLanguage)))
            for track in webTracks { rows.append(.node(sourceNode(for: track, parentID: "server:webkeyboard"))) }
        }

        // Jam Session clients — parented to their own Client hub, or a per-client Device hub for
        // a remote source that decodes as a split MIDI zone (same grouping as local splits, one
        // level deeper).
        for client in jamSessionClients {
            rows.append(.header("· \(client.name)"))
            let tracks = remoteTracks(forClientID: client.clientID)
            for track in tracks {
                let parentID: String
                if let decoded = decodedRemoteKind(track.id), let sourceIndex = midiSplitSourceIndex(for: decoded) {
                    parentID = "device:remote:\(client.clientID):\(sourceIndex)"
                } else {
                    parentID = "client:\(client.clientID)"
                }
                rows.append(.node(sourceNode(for: track, parentID: parentID)))
            }
        }

        return rows
    }

    // MARK: - Data — scene roles

    private func roleNode(for role: SceneRole, sourceActivityByID: [TrackID: NodeActivity]) -> RoleNode {
        let act = role.attachedTrackID.flatMap { sourceActivityByID[$0] } ?? .neutral
        let soundText = role.soundName.map { session.displayName(forSamplePath: $0, preset: role.soundPreset) } ?? "—"
        let volumeText = String(format: "%.0f%%", role.volume * 100)
        return RoleNode(id: role.id, name: role.name, detail: "\(soundText) · \(volumeText)", activity: act, attachedTrackID: role.attachedTrackID)
    }

    /// Attached roles first, ordered by their own source's row position (exact zero-crossing —
    /// see this struct's own doc comment); unattached roles form their own trailing group.
    private func roleRowsUnpositioned(sourceCenterY: [TrackID: CGFloat], sourceActivityByID: [TrackID: NodeActivity]) -> [RoleRow] {
        guard let scene = session.currentScene else { return [] }
        let attached = scene.roles.filter { $0.attachedTrackID != nil }
        let unattached = scene.roles.filter { $0.attachedTrackID == nil }
        let sortedAttached = attached.sorted { lhs, rhs in
            let lY = lhs.attachedTrackID.flatMap { sourceCenterY[$0] } ?? .greatestFiniteMagnitude
            let rY = rhs.attachedTrackID.flatMap { sourceCenterY[$0] } ?? .greatestFiniteMagnitude
            return lY < rY
        }
        var rows: [RoleRow] = sortedAttached.map { .node(roleNode(for: $0, sourceActivityByID: sourceActivityByID)) }
        if !unattached.isEmpty {
            rows.append(.header(L10n.string(.appHeadingRolesNonUtilises, session.currentLanguage)))
            rows.append(contentsOf: unattached.map { .node(roleNode(for: $0, sourceActivityByID: sourceActivityByID)) })
        }
        return rows
    }

    // MARK: - Layout

    private var layout: DiagramLayout {
        var result = DiagramLayout()
        var sourceActivityByID: [TrackID: NodeActivity] = [:]

        // 1. Source rows — concrete sequential Y, exactly as before.
        var y: CGFloat = 0
        for row in sourceRowsUnpositioned {
            let height: CGFloat = { if case .header = row { return Self.headerRowHeight } else { return Self.nodeRowHeight } }()
            let center = y + height / 2
            result.sourceRows.append((row, center))
            if case .node(let node) = row {
                result.sourceCenterY[node.id] = center
                sourceActivityByID[node.id] = node.activity
                result.sourceActivityByID[node.id] = node.activity
            }
            y += height + Self.rowSpacing
        }
        let sourcesHeight = y

        // 2. Device column — one hub per MIDI source (local OR remote) that's currently split
        // into zones, centered on the mean Y of its own zone rows. A local device's parent is
        // App (`parentID: nil`); a remote one's parent is that participant's own Client hub.
        struct DeviceKey: Hashable { let clientID: String?; let sourceIndex: Int }
        var zoneIDsByDevice: [DeviceKey: [TrackID]] = [:]
        var deviceOrder: [DeviceKey] = []
        for (row, _) in result.sourceRows {
            guard case .node(let node) = row else { continue }
            let key: DeviceKey
            if let sourceIndex = midiSplitSourceIndex(for: node.id) {
                key = DeviceKey(clientID: nil, sourceIndex: sourceIndex)
            } else if case .remote(let clientID, _) = node.id, let decoded = decodedRemoteKind(node.id), let sourceIndex = midiSplitSourceIndex(for: decoded) {
                key = DeviceKey(clientID: clientID, sourceIndex: sourceIndex)
            } else {
                continue
            }
            if zoneIDsByDevice[key] == nil { deviceOrder.append(key) }
            zoneIDsByDevice[key, default: []].append(node.id)
        }
        if !deviceOrder.isEmpty {
            let midiSourceNames = session.availableMIDISources()
            for key in deviceOrder {
                let zoneIDs = zoneIDsByDevice[key] ?? []
                let ys = zoneIDs.compactMap { result.sourceCenterY[$0] }
                guard !ys.isEmpty else { continue }
                let centerY = ys.reduce(0, +) / CGFloat(ys.count)
                let deviceActivity: NodeActivity
                if zoneIDs.contains(where: { sourceActivityByID[$0] == .playing }) {
                    deviceActivity = .playing
                } else if zoneIDs.contains(where: { sourceActivityByID[$0] == .active }) {
                    deviceActivity = .active
                } else {
                    deviceActivity = .neutral
                }
                let id: String
                let parentID: String?
                let label: String
                if let clientID = key.clientID {
                    id = "device:remote:\(clientID):\(key.sourceIndex)"
                    parentID = "client:\(clientID)"
                    label = "MIDI \(key.sourceIndex + 1)"
                } else {
                    id = "device:local:\(key.sourceIndex)"
                    parentID = "hub:localmidi"
                    label = midiSourceNames.indices.contains(key.sourceIndex) ? midiSourceNames[key.sourceIndex] : "MIDI \(key.sourceIndex + 1)"
                }
                result.deviceNodes.append((HubNode(id: id, label: label, subtitle: nil, activity: deviceActivity, parentID: parentID), centerY))
                result.hubCenterY[id] = centerY
            }
        }

        // Gathers a hub's own children (its Device hubs, and/or any of its non-split sources
        // directly) — shared by the Client column below AND every Server-column hub, since both
        // are "does this thing have any live activity under it" in the same shape.
        func childSummary(forParentID id: String) -> (centerYs: [CGFloat], anyActive: Bool, anyPlaying: Bool) {
            var centerYs: [CGFloat] = []
            var anyActive = false
            var anyPlaying = false
            for (device, centerY) in result.deviceNodes where device.parentID == id {
                centerYs.append(centerY)
                if device.activity == .playing { anyPlaying = true }
                if device.activity == .active { anyActive = true }
            }
            for (row, centerY) in result.sourceRows {
                guard case .node(let node) = row, node.parentID == id else { continue }
                centerYs.append(centerY)
                if let act = result.sourceActivityByID[node.id] {
                    if act == .playing { anyPlaying = true }
                    if act == .active { anyActive = true }
                }
            }
            return (centerYs, anyActive, anyPlaying)
        }

        // 3. Client column — one hub per connected Jam Session participant, centered on the mean
        // Y of its own children (its Device hubs, and/or any of its non-split sources directly).
        for client in jamSessionClients {
            let id = "client:\(client.clientID)"
            let summary = childSummary(forParentID: id)
            let centerY = summary.centerYs.isEmpty ? 0 : summary.centerYs.reduce(0, +) / CGFloat(summary.centerYs.count)
            let activity: NodeActivity = summary.anyPlaying ? .playing : .active // connected = at least active
            result.clientNodes.append((HubNode(id: id, label: client.name, subtitle: nil, activity: activity, parentID: nil), centerY))
            result.hubCenterY[id] = centerY
        }

        // 4. Server column — ALWAYS 4 fixed nodes (per explicit request, extended to also cover
        // local MIDI so it shares the same "always shown, active/inactive" visual language as the
        // network hubs): Sources MIDI Locales, Jam Session Local, Jam Session Game Center, Web
        // Keyboard. Positioned at the mean Y of its own clients/sources when it has any, else
        // stacked sequentially so the always-shown, currently-empty case still reads cleanly.
        var serverCursorY: CGFloat = 0
        func placeServer(id: String, labelKey: L10nKey, isActive: Bool, childCenterYs: [CGFloat], anyPlaying: Bool) {
            let sequential = serverCursorY + Self.nodeRowHeight / 2
            let centerY = childCenterYs.isEmpty ? sequential : max(sequential, childCenterYs.reduce(0, +) / CGFloat(childCenterYs.count))
            let activity: NodeActivity = isActive ? (anyPlaying ? .playing : .active) : .neutral
            let subtitle = isActive ? nil : L10n.string(.placeholderInactif, session.currentLanguage)
            result.serverNodes.append((HubNode(id: id, label: L10n.string(labelKey, session.currentLanguage), subtitle: subtitle, activity: activity, parentID: nil), centerY))
            result.hubCenterY[id] = centerY
            serverCursorY = centerY + Self.nodeRowHeight / 2 + Self.rowSpacing
        }

        let localMIDISummary = childSummary(forParentID: "hub:localmidi")
        let hasLocalMIDI = !session.availableMIDISources().isEmpty
        placeServer(id: "hub:localmidi", labelKey: .appLabelSourcesMIDILocales, isActive: hasLocalMIDI, childCenterYs: localMIDISummary.centerYs, anyPlaying: localMIDISummary.anyPlaying)

        let isLocalServer: Bool = { if case .server = session.networkRole { return true }; return false }()
        let localClientYs = result.clientNodes.map(\.centerY)
        let localAnyPlaying = result.clientNodes.contains { $0.node.activity == .playing }
        placeServer(id: "server:local", labelKey: .appLabelServeurJamSessionLocal, isActive: isLocalServer, childCenterYs: isLocalServer ? localClientYs : [], anyPlaying: localAnyPlaying)

        let isGameCenterServer: Bool = { if case .gameCenterServer = session.networkRole { return true }; return false }()
        placeServer(id: "server:gamecenter", labelKey: .appLabelServeurJamSessionGameCenter, isActive: isGameCenterServer, childCenterYs: isGameCenterServer ? localClientYs : [], anyPlaying: isGameCenterServer && localAnyPlaying)

        let webSummary = childSummary(forParentID: "server:webkeyboard")
        let webActive = session.virtualKeyboardPort != nil
        placeServer(id: "server:webkeyboard", labelKey: .appLabelServeurClavierWeb, isActive: webActive, childCenterYs: webSummary.centerYs, anyPlaying: webSummary.anyPlaying)

        // A role attached to a source is pinned to that EXACT source's own centerY — per
        // explicit request, so the connecting line is a straight horizontal segment instead of
        // a diagonal one. Safe against overlap: source->role stays strictly 1-for-1 (see this
        // struct's own doc comment) and attached roles are processed in ascending source-Y order
        // (`roleRowsUnpositioned`'s own sort), so pinned centers only ever increase; `max(...)`
        // is a defensive floor, not something normal data should ever need. Headers/unattached
        // roles fall back to sequential stacking, continuing from wherever the last pinned role
        // left off.
        y = 0
        for row in roleRowsUnpositioned(sourceCenterY: result.sourceCenterY, sourceActivityByID: sourceActivityByID) {
            switch row {
            case .header:
                let center = y + Self.headerRowHeight / 2
                result.roleRows.append((row, center))
                y += Self.headerRowHeight + Self.rowSpacing
            case .node(let node):
                if let trackID = node.attachedTrackID, let sourceY = result.sourceCenterY[trackID] {
                    let center = max(sourceY, y + Self.nodeRowHeight / 2)
                    result.roleRows.append((row, center))
                    y = center + Self.nodeRowHeight / 2 + Self.rowSpacing
                } else {
                    let center = y + Self.nodeRowHeight / 2
                    result.roleRows.append((row, center))
                    y += Self.nodeRowHeight + Self.rowSpacing
                }
            }
        }
        let rolesHeight = y

        let serverColumnHeight = serverCursorY
        result.totalHeight = max(sourcesHeight, rolesHeight, serverColumnHeight, Self.nodeRowHeight)
        result.appCenterY = result.totalHeight / 2

        // 5. Column X positions — assigned last, now that we know which of Client/Device
        // actually have any nodes to show. An empty column (no Jam Session participant, no
        // split MIDI device) is skipped entirely rather than reserving its `hubWidth +
        // columnGap` as dead space — this is what used to leave a huge unexplained gap before
        // "LUMI Keys BLOCK" whenever no Jam Session was running (the empty Client column's
        // width was reserved regardless).
        result.serverX = Self.appX + Self.appWidth + Self.columnGap
        var cursorX = result.serverX + Self.hubWidth + Self.columnGap
        if !result.clientNodes.isEmpty {
            result.clientX = cursorX
            cursorX = result.clientX + Self.hubWidth + Self.columnGap
        } else {
            result.clientX = cursorX
        }
        if !result.deviceNodes.isEmpty {
            result.deviceX = cursorX
            cursorX = result.deviceX + Self.hubWidth + Self.columnGap
        } else {
            result.deviceX = cursorX
        }
        result.sourceX = cursorX
        result.roleX = result.sourceX + Self.nodeWidth + Self.columnGap
        result.totalWidth = result.roleX + Self.nodeWidth + Self.leftMargin

        return result
    }

    // MARK: - Body

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            let layout = layout
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in draw(in: context, layout: layout) }
                appNodeView
                    .position(x: Self.appX + Self.appWidth / 2, y: Self.topMargin + layout.appCenterY)
                ForEach(layout.serverNodes, id: \.node.id) { entry in
                    hubNodeView(entry.node)
                        .position(x: layout.serverX + Self.hubWidth / 2, y: Self.topMargin + entry.centerY)
                }
                ForEach(layout.clientNodes, id: \.node.id) { entry in
                    hubNodeView(entry.node)
                        .position(x: layout.clientX + Self.hubWidth / 2, y: Self.topMargin + entry.centerY)
                }
                ForEach(layout.deviceNodes, id: \.node.id) { entry in
                    hubNodeView(entry.node)
                        .position(x: layout.deviceX + Self.hubWidth / 2, y: Self.topMargin + entry.centerY)
                }
                ForEach(layout.sourceRows, id: \.row.id) { entry in
                    sourceRowView(entry.row)
                        .position(x: layout.sourceX + Self.nodeWidth / 2, y: Self.topMargin + entry.centerY)
                }
                ForEach(layout.roleRows, id: \.row.id) { entry in
                    roleRowView(entry.row)
                        .position(x: layout.roleX + Self.nodeWidth / 2, y: Self.topMargin + entry.centerY)
                }
                if session.currentScene == nil {
                    Text(L10n.string(.placeholderAucuneSceneActive, session.currentLanguage))
                        .font(.caption).foregroundStyle(.secondary)
                        .position(x: layout.roleX + Self.nodeWidth / 2, y: Self.topMargin + Self.nodeRowHeight / 2)
                }
            }
            .frame(width: layout.totalWidth, height: Self.topMargin * 2 + layout.totalHeight, alignment: .topLeading)
            .padding(.bottom, 24)
        }
        #if os(macOS) || os(visionOS)
        .overlay(alignment: .topTrailing) {
            detachButton
                .padding(.horizontal)
                .padding(.top, 6)
        }
        #endif
    }

    /// Every node with a `parentID` draws exactly one line back to it (or to the App node when
    /// `nil`) — a single generic mechanism now that Server/Client/Device/Source all carry the
    /// same "who's my parent" concept, via the unified `hubCenterY` lookup for hub parents.
    private func draw(in context: GraphicsContext, layout: DiagramLayout) {
        let appPoint = CGPoint(x: Self.appX + Self.appWidth, y: Self.topMargin + layout.appCenterY)

        func parentPoint(_ parentID: String?, exitX: CGFloat) -> CGPoint? {
            guard let parentID else { return appPoint }
            guard let y = layout.hubCenterY[parentID] else { return nil }
            return CGPoint(x: exitX, y: Self.topMargin + y)
        }

        /// Right-angle (horizontal/vertical only) connector, per explicit request — a straight
        /// diagonal line reads ambiguously once a row's Y is pinned away from its natural
        /// sequential slot (e.g. a role aligned to its attached source's exact row).
        ///
        /// General rule for where to bend: a link between ADJACENT columns (`to.x - from.x`
        /// is exactly one `columnGap` — the normal case, nothing else ever sits in that gap)
        /// bends at that gap's own midpoint, same as before. A link that SKIPS at least one
        /// populated column (e.g. Clavier ordinateur or a Jam Session Client connecting
        /// straight back to the App node, bypassing Serveur/Client/Device columns entirely)
        /// instead bends UP into the immediately-following gap first, travels across at a
        /// shared aerial Y strictly above every row in every column, then drops straight down
        /// into the destination — never once running a horizontal segment through the row-span
        /// of an intervening column's boxes, which the old single-midpoint bend could do
        /// whenever more than one column lay between `from` and `to`.
        func stroke(from: CGPoint, to: CGPoint, activity: NodeActivity) {
            var path = Path()
            path.move(to: from)
            let horizontalGap = to.x - from.x
            let skipsAColumn = horizontalGap > Self.columnGap + 1
            if from.y == to.y && !skipsAColumn {
                path.addLine(to: to)
            } else if skipsAColumn {
                // Deliberately NOT `from.x + columnGap / 2` — that's the exact midpoint a plain
                // adjacent-column bend in this same gap already uses (e.g. every Serveur-column
                // node's own App-> link), so sharing it would cross this riser right through
                // those other bends. A small fixed inset instead keeps it visually separate
                // while still landing safely inside the (always node-free) gap.
                let bendX = from.x + 8
                path.addLine(to: CGPoint(x: bendX, y: from.y))
                path.addLine(to: CGPoint(x: bendX, y: Self.aerialY))
                path.addLine(to: CGPoint(x: to.x, y: Self.aerialY))
                path.addLine(to: to)
            } else {
                let midX = (from.x + to.x) / 2
                path.addLine(to: CGPoint(x: midX, y: from.y))
                path.addLine(to: CGPoint(x: midX, y: to.y))
                path.addLine(to: to)
            }
            context.stroke(path, with: .color(activity.strokeColor), lineWidth: activity.lineWidth)
        }

        /// Which column a node's own parent lives in — "server:" and "hub:" (the always-shown
        /// local-MIDI hub) share the same column, everything else is its own prefix.
        func hubExitX(forParentID id: String?) -> CGFloat {
            switch id {
            case nil: return Self.appX + Self.appWidth
            case .some(let id) where id.hasPrefix("device:"): return layout.deviceX + Self.hubWidth
            case .some(let id) where id.hasPrefix("client:"): return layout.clientX + Self.hubWidth
            case .some: return layout.serverX + Self.hubWidth
            }
        }

        for (node, centerY) in layout.serverNodes {
            guard let from = parentPoint(node.parentID, exitX: Self.appX + Self.appWidth) else { continue }
            stroke(from: from, to: CGPoint(x: layout.serverX, y: Self.topMargin + centerY), activity: node.activity)
        }
        for (node, centerY) in layout.clientNodes {
            guard let from = parentPoint(node.parentID, exitX: layout.serverX + Self.hubWidth) else { continue }
            stroke(from: from, to: CGPoint(x: layout.clientX, y: Self.topMargin + centerY), activity: node.activity)
        }
        for (node, centerY) in layout.deviceNodes {
            guard let from = parentPoint(node.parentID, exitX: hubExitX(forParentID: node.parentID)) else { continue }
            stroke(from: from, to: CGPoint(x: layout.deviceX, y: Self.topMargin + centerY), activity: node.activity)
        }
        for (row, centerY) in layout.sourceRows {
            guard case .node(let node) = row else { continue }
            guard let from = parentPoint(node.parentID, exitX: hubExitX(forParentID: node.parentID)) else { continue }
            stroke(from: from, to: CGPoint(x: layout.sourceX, y: Self.topMargin + centerY), activity: node.activity)
        }
        for (row, centerY) in layout.roleRows {
            guard case .node(let node) = row, let trackID = node.attachedTrackID, let sourceY = layout.sourceCenterY[trackID] else { continue }
            let start = CGPoint(x: layout.sourceX + Self.nodeWidth, y: Self.topMargin + sourceY)
            let end = CGPoint(x: layout.roleX, y: Self.topMargin + centerY)
            stroke(from: start, to: end, activity: node.activity)
        }
    }

    private var appNodeView: some View {
        Text("JamShack")
            .font(.headline)
            .padding(.horizontal, 12).padding(.vertical, 10)
            .frame(width: Self.appWidth, height: Self.nodeRowHeight)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private func sourceRowView(_ row: SourceRow) -> some View {
        switch row {
        case .header(let title):
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
                .frame(width: Self.nodeWidth, alignment: .leading)
        case .node(let node):
            let subtitle = [node.splitRangeAnnotation, node.mainKeyboardAnnotation].compactMap { $0 }.joined(separator: " · ")
            nodeBox(
                title: node.label, subtitle: subtitle.isEmpty ? nil : subtitle, activity: node.activity,
                isMainKeyboardSource: node.id == session.theoryLiveInputSourceID
            )
        }
    }

    @ViewBuilder
    private func roleRowView(_ row: RoleRow) -> some View {
        switch row {
        case .header(let title):
            Text(title).font(.caption).bold().foregroundStyle(.secondary)
                .frame(width: Self.nodeWidth, alignment: .leading)
        case .node(let node):
            nodeBox(title: node.name, subtitle: node.detail, activity: node.activity)
        }
    }

    /// `isMainKeyboardSource` marks the source currently feeding Théorie's live-match/observation
    /// point (`session.theoryLiveInputSourceID`) — a RED ring, deliberately independent of the
    /// green activity language: per explicit request, being "clavier principal" is purely an
    /// observation choice (which track the main-keyboard component previews) and must never read
    /// as if it were what turns other sources' own listening on or off — it doesn't.
    private func nodeBox(title: String, subtitle: String?, activity: NodeActivity, width: CGFloat = Self.nodeWidth, isMainKeyboardSource: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline).bold().lineLimit(1)
            if let subtitle {
                Text(subtitle).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: width, height: Self.nodeRowHeight, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.green.opacity(activity.fillOpacity))
        )
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isMainKeyboardSource ? Color.red : activity.strokeColor,
                    style: StrokeStyle(lineWidth: isMainKeyboardSource ? 2.5 : activity.lineWidth, dash: isMainKeyboardSource ? [] : activity.dash)
                )
        )
    }

    /// Server/Client/Device column node — same box, `hubWidth` instead of `nodeWidth`.
    private func hubNodeView(_ node: HubNode) -> some View {
        nodeBox(title: node.label, subtitle: node.subtitle, activity: node.activity, width: Self.hubWidth)
    }

    #if os(macOS) || os(visionOS)
    @ViewBuilder
    private var detachButton: some View {
        if isDetachedWindow {
            Button {
                dismissWindow(id: AuxiliaryWindowID.home.rawValue)
            } label: {
                Label(L10n.string(.appButtonReintegrer, session.currentLanguage), systemImage: "arrow.down.right.and.arrow.up.left")
            }
        } else {
            Button {
                openWindow(id: AuxiliaryWindowID.home.rawValue)
            } label: {
                Image(systemName: "rectangle.on.rectangle")
            }
        }
    }
    #endif
}

#Preview {
    StatusGraphView(session: ImprovSession())
}
