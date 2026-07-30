import SwiftUI
import AppCore
import Localization
import SoundFontModel

/// Browse-and-install screen for `CuratedSoundFontCatalog.entries` — a convenience layer on top
/// of manual import, never a replacement for it: every entry here is downloaded by the app on
/// the user's behalf from a descriptor, but `.fileImporter`/drag & drop in `SoundLibraryView`
/// keep working exactly as before, at the same level, not tucked behind this screen. See
/// `KnowledgeBase/SoundfontMgt/SPEC-catalogue-soundfonts.md` for the full design.
struct SoundFontCatalogView: View {
    let session: ImprovSession

    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var installingId: String?
    @State private var installPhase: SoundFontInstallPhase?
    /// Retained so an "Abandonner" button can call `.cancel()` — see `cancelInstall()`.
    @State private var installTask: Task<Void, Never>?
    @State private var actionError: String?
    @State private var detailEntry: SoundFontCatalogEntry?
    @State private var showCredits = false

    private var installedEntryIds: Set<String> {
        Set(session.soundFonts.compactMap { entry -> String? in
            guard case .curated(_, let id, _) = entry.origin, !id.isEmpty else { return nil }
            return id
        })
    }

    /// Installed soundfont hash, keyed by the catalog entry id it came from an older version of
    /// — used both to show the "Mettre à jour" button and, once an update succeeds, to remove
    /// the superseded file (see `update(to:)`). Note: an updated bank gets a NEW file hash (it's
    /// different bytes), so any favorite/alias/scene role pointing at the OLD hash does not
    /// carry over automatically — a real, accepted limitation of hash-based identity, not a bug.
    private var installedHashByEntryId: [String: String] {
        Dictionary(uniqueKeysWithValues: session.soundFonts.compactMap { entry -> (String, String)? in
            guard case .curated(_, let id, _) = entry.origin, !id.isEmpty else { return nil }
            return (id, entry.hash)
        })
    }

    private var updatesAvailableByEntryId: Set<String> {
        Set(session.catalogUpdates.map { $0.latest.id })
    }

    private var filteredEntries: [SoundFontCatalogEntry] {
        let all = CuratedSoundFontCatalog.installableEntries.sorted { lhs, rhs in
            if lhs.recommended != rhs.recommended { return lhs.recommended }
            return lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
        }
        guard !searchText.isEmpty else { return all }
        return all.filter {
            $0.displayName.localizedCaseInsensitiveContains(searchText)
                || $0.author.localizedCaseInsensitiveContains(searchText)
                || $0.tags.contains { $0.localizedCaseInsensitiveContains(searchText) }
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let actionError {
                    Section {
                        Text(actionError).foregroundStyle(.red).font(.caption)
                    }
                }
                Section {
                    TextField(L10n.string(.appPlaceholderRechercherCatalogue, session.currentLanguage), text: $searchText)
                }
                if filteredEntries.isEmpty {
                    Section {
                        Text(L10n.string(.appPlaceholderAucuneEntreeCatalogue, session.currentLanguage))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Section {
                        ForEach(filteredEntries) { entry in
                            row(entry)
                        }
                    } footer: {
                        Text(L10n.string(.appHintCatalogueImportManuelAussi, session.currentLanguage))
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(L10n.string(.appHeadingCatalogue, session.currentLanguage))
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string(.appButtonFermer, session.currentLanguage)) { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button(L10n.string(.appHeadingCredits, session.currentLanguage)) { showCredits = true }
                }
            }
            .sheet(item: $detailEntry) { entry in
                SoundFontCatalogDetailView(
                    session: session, entry: entry,
                    isInstalled: installedEntryIds.contains(entry.id),
                    hasUpdate: updatesAvailableByEntryId.contains(entry.id),
                    installPhase: installingId == entry.id ? installPhase : nil,
                    onInstall: { install(entry) },
                    onUpdate: { update(to: entry) },
                    onCancel: cancelInstall
                )
            }
            .sheet(isPresented: $showCredits) {
                SoundFontCatalogCreditsView(session: session)
            }
        }
    }

    @ViewBuilder
    private func row(_ entry: SoundFontCatalogEntry) -> some View {
        Button {
            detailEntry = entry
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(entry.displayName)
                        if entry.recommended {
                            Text(L10n.string(.appLabelRecommande, session.currentLanguage))
                                .font(.caption2).padding(.horizontal, 6).padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }
                    }
                    if installingId == entry.id, let installPhase {
                        Text(progressText(installPhase)).font(.caption2).foregroundStyle(.secondary)
                    } else {
                        Text("\(L10n.string(.appFormatCatalogueParAuteur, session.currentLanguage, entry.author)) — \(ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))")
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if installingId == entry.id {
                    if case .downloading(let fraction) = installPhase {
                        ProgressView(value: fraction).progressViewStyle(.circular).controlSize(.small)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Button {
                        cancelInstall()
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }
                    .buttonStyle(.borderless)
                } else if updatesAvailableByEntryId.contains(entry.id) {
                    Image(systemName: "arrow.triangle.2.circlepath.circle.fill").foregroundStyle(.orange)
                } else if installedEntryIds.contains(entry.id) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func progressText(_ phase: SoundFontInstallPhase) -> String {
        switch phase {
        case .downloading(let fraction):
            return L10n.string(.appFormatTelechargementPourcent, session.currentLanguage, Int((fraction * 100).rounded()))
        case .installing:
            return L10n.string(.appLabelInstallationEnCours, session.currentLanguage)
        }
    }

    /// `installCuratedSoundFont` is `async` specifically so the network download can run
    /// genuinely off this (main) actor — see that method's own doc comment. This outer `Task`
    /// stays a plain, non-detached one (inherits the main actor from this button action), which
    /// is what lets execution — and every `onProgress` update — resume back here safely.
    /// `onProgress` reports 1.0 right as the transfer finishes; there's no separate signal for
    /// the brief hash+copy step afterward, so reaching 1.0 is treated as "now installing".
    private func install(_ entry: SoundFontCatalogEntry) {
        guard installingId == nil else { return }
        installingId = entry.id
        installPhase = .downloading(fractionCompleted: 0)
        actionError = nil
        installTask = Task {
            defer { installingId = nil; installPhase = nil; installTask = nil }
            do {
                try await session.installCuratedSoundFont(entry) { fraction in
                    installPhase = fraction >= 1 ? .installing : .downloading(fractionCompleted: fraction)
                }
            } catch is CancellationError {
                // A user-initiated "Abandonner" — not a failure, nothing to report.
            } catch {
                actionError = "\(error)"
            }
        }
    }

    /// Installs the newer version, then removes the superseded file only once the new one is
    /// confirmed in place — never the other way around, so a failed download/verification never
    /// leaves the user with neither copy (see `KnowledgeBase/SoundfontMgt/
    /// SPEC-catalogue-soundfonts.md` §9).
    private func update(to entry: SoundFontCatalogEntry) {
        guard installingId == nil else { return }
        let previousHash = installedHashByEntryId[entry.id]
        installingId = entry.id
        installPhase = .downloading(fractionCompleted: 0)
        actionError = nil
        installTask = Task {
            defer { installingId = nil; installPhase = nil; installTask = nil }
            do {
                try await session.installCuratedSoundFont(entry) { fraction in
                    installPhase = fraction >= 1 ? .installing : .downloading(fractionCompleted: fraction)
                }
                if let previousHash {
                    session.deleteSoundFont(hash: previousHash)
                }
            } catch is CancellationError {
            } catch {
                actionError = "\(error)"
            }
        }
    }

    private func cancelInstall() {
        installTask?.cancel()
    }
}
