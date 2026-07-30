import SwiftUI
import AppCore
import Localization

/// "Stockage" sub-tab of "Sons": the storage-profile picker, local/iCloud usage bars with
/// stepper-adjustable thresholds, and the destructive "Nettoyer la bibliothèque" reset — all
/// split out of `SoundLibraryView` (which now only handles browsing/importing files) so that
/// screen isn't a mix of "pick a file" and "manage disk space" concerns.
struct SoundStorageView: View {
    let session: ImprovSession

    @State private var storageProfile: DeviceStorageProfile = DeviceStorageProfile.current
    @State private var actionError: String?
    @State private var showCleanConfirmation = false
    @State private var isCleaning = false

    private static let thresholdStep: Int64 = 500_000_000
    private static let thresholdRange: ClosedRange<Int64> = 500_000_000...500_000_000_000
    private static let defaultThreshold: Int64 = 1_000_000_000

    var body: some View {
        Form {
            if let actionError {
                Section {
                    Text(actionError).foregroundStyle(.red).font(.caption)
                }
            }

            Section {
                Picker(L10n.string(.appHeadingProfilStockage, session.currentLanguage), selection: $storageProfile) {
                    Text(L10n.string(.appOptionProfilEconome, session.currentLanguage)).tag(DeviceStorageProfile.economical)
                    Text(L10n.string(.appOptionProfilStandard, session.currentLanguage)).tag(DeviceStorageProfile.standard)
                    Text(L10n.string(.appOptionProfilGenereux, session.currentLanguage)).tag(DeviceStorageProfile.generous)
                }
                .onChange(of: storageProfile) { _, newValue in DeviceStorageProfile.current = newValue }
            } header: {
                Text(L10n.string(.appHeadingProfilStockage, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintProfilStockageExplication, session.currentLanguage))
            }

            Section {
                thresholdStepper(
                    label: L10n.string(.appLabelSeuilLocal, session.currentLanguage),
                    valueBytes: localThresholdBinding
                )
                StorageUsageBar(segments: localUsage.segments, thresholdFraction: localUsage.thresholdFraction, language: session.currentLanguage)
                if localUsage.thresholdFraction != nil {
                    Text(L10n.string(.appHintSeuilDepasse, session.currentLanguage)).font(.caption2).foregroundStyle(.orange)
                }

                thresholdStepper(
                    label: L10n.string(.appLabelSeuilICloud, session.currentLanguage),
                    valueBytes: cloudThresholdBinding
                )
                .padding(.top, 10)
                if syncedUsage.segments.isEmpty {
                    Text(L10n.string(.appLabelLocalUniquement, session.currentLanguage)).font(.caption2).foregroundStyle(.secondary)
                } else {
                    StorageUsageBar(segments: syncedUsage.segments, thresholdFraction: syncedUsage.thresholdFraction, language: session.currentLanguage)
                    if syncedUsage.thresholdFraction != nil {
                        Text(L10n.string(.appHintSeuilDepasse, session.currentLanguage)).font(.caption2).foregroundStyle(.orange)
                    }
                }
            } header: {
                Text(L10n.string(.appHeadingUtilisationStockage, session.currentLanguage))
            } footer: {
                Text(L10n.string(.appHintPasDeQuotaICloud, session.currentLanguage))
            }

            Section {
                Button(role: .destructive) {
                    showCleanConfirmation = true
                } label: {
                    if isCleaning {
                        ProgressView().controlSize(.small)
                    } else {
                        Label(L10n.string(.appButtonNettoyerBibliotheque, session.currentLanguage), systemImage: "trash.fill")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(isCleaning)
            } footer: {
                Text(L10n.string(.appHintNettoyerBibliotheque, session.currentLanguage))
            }
        }
        #if os(macOS)
        .formStyle(.grouped)
        #endif
        .alert(
            L10n.string(.appAlertNettoyerBibliotheque, session.currentLanguage),
            isPresented: $showCleanConfirmation
        ) {
            Button(L10n.string(.appButtonNettoyerBibliotheque, session.currentLanguage), role: .destructive) {
                cleanLibrary()
            }
            Button(L10n.string(.appAnnuler, session.currentLanguage), role: .cancel) {}
        } message: {
            Text(L10n.string(.appHintNettoyerBibliotheque, session.currentLanguage))
        }
    }

    /// Label stacked above the stepper (rather than beside it) so it always has room to wrap —
    /// squeezed next to a narrow control, "Limite iCloud (tous les appareils)" was wrapping onto
    /// several lines with barely any width to do it in.
    @ViewBuilder
    private func thresholdStepper(label: String, valueBytes: Binding<Int64>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Stepper(value: valueBytes, in: Self.thresholdRange, step: Int(Self.thresholdStep)) {
                Text("\(gbText(valueBytes.wrappedValue)) \(L10n.string(.appUnitGo, session.currentLanguage))")
            }
        }
    }

    private func gbText(_ bytes: Int64) -> String {
        String(format: "%.1f", Double(bytes) / 1_000_000_000)
    }

    private var localThresholdBinding: Binding<Int64> {
        Binding(
            get: { LocalStorageThreshold.bytes ?? Self.defaultThreshold },
            set: { LocalStorageThreshold.bytes = $0 }
        )
    }

    private var cloudThresholdBinding: Binding<Int64> {
        Binding(
            get: { session.cloudStorageThresholdBytes ?? Self.defaultThreshold },
            set: { newValue in
                do {
                    try session.setCloudStorageThresholdBytes(newValue)
                } catch {
                    actionError = "\(error)"
                }
            }
        )
    }

    /// Every soundfont actually resident on THIS device's disk right now — local-only files
    /// (always resident) plus any `.synced` file that happens to be downloaded here — since
    /// that's what genuinely counts against this device's own free space, regardless of where
    /// each file's "home" is considered to be.
    private var localUsage: (segments: [StorageSegment], thresholdFraction: Double?) {
        let resident = session.soundFonts.filter { session.soundFontPath(forHash: $0.hash) != nil }
        return StorageSegment.build(
            from: resident, threshold: LocalStorageThreshold.bytes,
            deviceFreeSpace: DeviceFreeSpace.availableBytes(), language: session.currentLanguage
        )
    }

    /// Every `.synced` soundfont regardless of download state on this device — this is what
    /// actually occupies space in the app's iCloud Drive container (hence every device signed
    /// into the account), not just what happens to be downloaded here right now. No free-space
    /// segment unless a threshold is set: Apple exposes no API to read the account's remaining
    /// iCloud quota (see `appHintPasDeQuotaICloud`).
    private var syncedUsage: (segments: [StorageSegment], thresholdFraction: Double?) {
        let synced = session.soundFonts.filter { $0.syncPreference == .synced }
        return StorageSegment.build(
            from: synced, threshold: session.cloudStorageThresholdBytes, deviceFreeSpace: nil, language: session.currentLanguage
        )
    }

    /// Wipes the entire soundfont library (see `ImprovSession.wipeSoundFontLibrary()`) —
    /// deliberately NOT `Task.detached`: it touches `modelContext` directly, thread-confined to
    /// the main thread/actor.
    private func cleanLibrary() {
        guard !isCleaning else { return }
        isCleaning = true
        Task {
            await Task.yield()
            defer { isCleaning = false }
            session.wipeSoundFontLibrary()
        }
    }
}
