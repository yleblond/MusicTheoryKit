import SwiftUI
import AppCore

/// First sub-tab of the "JamShack" tab: pick every folder the app needs, mirroring the CLI's
/// own `catJamShack` menu category one-for-one (morceaux/sons/soundtracks/guides/scenes/
/// reglages/composition IA) — the single place all seven live now, instead of one-off pickers
/// scattered per screen (which is what left the scene folder with no way to browse it after
/// the scene screen was switched to single-file export/import).
struct JamShackFoldersView: View {
    let session: ImprovSession

    var body: some View {
        Form {
            Section {
                FolderPickerRow(
                    title: "Morceaux",
                    currentPath: session.pieceFolder,
                    fileCount: session.pieceFiles.isEmpty ? nil : session.pieceFiles.count
                ) { try session.listPieceFiles(in: $0) }
                FolderPickerRow(
                    title: "Sons (samples)",
                    currentPath: session.sampleFolder,
                    fileCount: session.sampleFiles.isEmpty ? nil : session.sampleFiles.count
                ) { try session.listSampleFiles(in: $0) }
                FolderPickerRow(
                    title: "Soundtracks",
                    currentPath: session.soundTrackFolder,
                    fileCount: session.soundTrackFiles.isEmpty ? nil : session.soundTrackFiles.count
                ) { try session.listSoundTrackFiles(in: $0) }
                FolderPickerRow(
                    title: "Guides",
                    currentPath: session.guideFolder,
                    fileCount: session.guideFiles.isEmpty ? nil : session.guideFiles.count
                ) { try session.listGuideFiles(in: $0) }
                FolderPickerRow(
                    title: "Scenes",
                    currentPath: session.sceneFolder,
                    fileCount: session.sceneFiles.isEmpty ? nil : session.sceneFiles.count
                ) { try session.listSceneFiles(in: $0) }
            } header: {
                Text("Contenus")
            }
            Section {
                FolderPickerRow(title: "Reglages", currentPath: session.settingsFolder, fileCount: nil) {
                    try session.setSettingsFolder($0)
                }
                FolderPickerRow(title: "Composition IA (prompts)", currentPath: session.promptsFolder, fileCount: nil) {
                    try session.setPromptsFolder($0)
                }
            } header: {
                Text("Configuration")
            } footer: {
                Text("Cree les sous-dossiers necessaires s'ils n'existent pas encore.")
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
    }
}

#Preview {
    JamShackFoldersView(session: ImprovSession())
}
