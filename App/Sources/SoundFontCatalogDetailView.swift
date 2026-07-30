import SwiftUI
import AppCore
import Localization

/// Fiche détaillée for one `SoundFontCatalogEntry` — name, author, description, license block
/// (with attribution notice when required), size, a link back to the original source, and the
/// install/update action itself. See `SoundFontCatalogView` for the list this is presented from.
struct SoundFontCatalogDetailView: View {
    let session: ImprovSession
    let entry: SoundFontCatalogEntry
    let isInstalled: Bool
    let hasUpdate: Bool
    let installPhase: SoundFontInstallPhase?
    let onInstall: () -> Void
    let onUpdate: () -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(entry.localizedSummary(session.currentLanguage))
                    row(L10n.string(.appFormatCatalogueParAuteur, session.currentLanguage, entry.author), nil)
                    row(L10n.string(.appLabelTaille, session.currentLanguage), ByteCountFormatter.string(fromByteCount: entry.sizeBytes, countStyle: .file))
                } header: {
                    Text(entry.displayName)
                }

                Section {
                    row(L10n.string(.appLabelLicence, session.currentLanguage), entry.license.name)
                    if entry.license.attributionRequired {
                        Text(L10n.string(.appLabelAttributionRequise, session.currentLanguage))
                            .font(.caption).foregroundStyle(.orange)
                    }
                    if let licenseURL = entry.license.url {
                        Link(L10n.string(.appButtonEnSavoirPlus, session.currentLanguage), destination: licenseURL)
                    }
                } header: {
                    Text(L10n.string(.appLabelLicence, session.currentLanguage))
                }

                if let infoURL = entry.infoURL {
                    Section {
                        Link(L10n.string(.appButtonEnSavoirPlus, session.currentLanguage), destination: infoURL)
                    }
                }

                Section {
                    if let installPhase {
                        VStack(spacing: 8) {
                            switch installPhase {
                            case .downloading(let fraction):
                                ProgressView(value: fraction)
                                Text(L10n.string(.appFormatTelechargementPourcent, session.currentLanguage, Int((fraction * 100).rounded())))
                                    .font(.caption).foregroundStyle(.secondary)
                            case .installing:
                                ProgressView().controlSize(.small)
                                Text(L10n.string(.appLabelInstallationEnCours, session.currentLanguage))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            // Cancelling mid-"installing" wouldn't stop much (the network part
                            // is already done, and the hash+copy step that's left is short and
                            // synchronous) — hiding the button there avoids implying a click
                            // would do anything visible.
                            if case .downloading = installPhase {
                                Button(L10n.string(.appButtonAbandonner, session.currentLanguage), role: .destructive) { onCancel() }
                            }
                        }
                        .frame(maxWidth: .infinity)
                    } else if hasUpdate {
                        Button(L10n.string(.appButtonMettreAJour, session.currentLanguage)) { onUpdate() }
                    } else if isInstalled {
                        HStack {
                            Spacer()
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Spacer()
                        }
                    } else {
                        Button(L10n.string(.appButtonInstaller, session.currentLanguage)) { onInstall() }
                    }
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string(.appButtonFermer, session.currentLanguage)) { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func row(_ label: String, _ value: String?) -> some View {
        HStack {
            Text(label).foregroundStyle(value == nil ? .primary : .secondary)
            if let value {
                Spacer()
                Text(value).multilineTextAlignment(.trailing)
            }
        }
    }
}
