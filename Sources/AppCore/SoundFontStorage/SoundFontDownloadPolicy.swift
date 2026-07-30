import Foundation

/// What to do about a `.synced` soundfont's bytes on THIS device — being indexed (visible in
/// `ImprovSession.soundFonts`, presets browsable) never implies being downloaded here; that is
/// a separate, per-device decision (see `SoundFontDownloadPolicy`).
public enum SoundFontLocalDownloadDecision: Equatable, Sendable {
    /// Start `startDownloadingUbiquitousItem` immediately, no prompt.
    case autoDownload
    /// Leave it as metadata-only for now — the user can still download it manually later.
    case metadataOnly
    /// Ask before downloading, with a reason to phrase the prompt around.
    case askUser(reason: PromptReason)

    public enum PromptReason: Equatable, Sendable {
        case largeFile
        case lowLocalSpaceButHighPriority
        case largeFavorite
    }
}

/// Decides, per soundfont and per device, whether to materialize a `.synced` soundfont's bytes
/// locally right now. Deliberately a pure function of its inputs (no I/O, no singletons) so it's
/// trivially unit-testable — callers are responsible for supplying real measurements
/// (`DeviceFreeSpace.availableBytes()`, `DeviceStorageProfile.current`,
/// `SoundFontLocalUsageLedger.wasUsedRecently(_:)`).
///
/// The local free-space floor is always the final word, even for a favorite: this never
/// recommends a download that would push the device below its own safety margin — at most it
/// asks the user to decide, it never silently forces the issue.
public enum SoundFontDownloadPolicy {
    struct Thresholds: Equatable {
        /// Never recommend a download that would leave less than this much local space free.
        let localFreeSpaceFloor: Int64
        /// At/under this size, download automatically without asking (once the floor above is
        /// satisfied).
        let autoDownloadSizeCeiling: Int64
        /// Above `autoDownloadSizeCeiling` but at/under this size: ask before downloading — a
        /// favorite/recently-used soundfont skips the prompt and downloads anyway.
        let promptSizeCeiling: Int64
    }

    static func thresholds(for profile: DeviceStorageProfile) -> Thresholds {
        switch profile {
        case .economical:
            return Thresholds(localFreeSpaceFloor: 5_000_000_000, autoDownloadSizeCeiling: 150_000_000, promptSizeCeiling: 500_000_000)
        case .standard:
            return Thresholds(localFreeSpaceFloor: 10_000_000_000, autoDownloadSizeCeiling: 500_000_000, promptSizeCeiling: 2_000_000_000)
        case .generous:
            return Thresholds(localFreeSpaceFloor: 20_000_000_000, autoDownloadSizeCeiling: 2_000_000_000, promptSizeCeiling: .max)
        }
    }

    /// `isFavorite`/`recentlyUsedOnThisDevice` are both "the user demonstrably cares about
    /// this" signals — either one is enough to relax the size-based caution by one step, but
    /// neither can ever override the free-space floor.
    public static func decide(
        fileSize: Int64,
        currentFreeSpace: Int64,
        profile: DeviceStorageProfile,
        isFavorite: Bool,
        recentlyUsedOnThisDevice: Bool
    ) -> SoundFontLocalDownloadDecision {
        let thresholds = thresholds(for: profile)
        let highPriority = isFavorite || recentlyUsedOnThisDevice
        let wouldFitWithinFloor = (currentFreeSpace - fileSize) >= thresholds.localFreeSpaceFloor

        guard wouldFitWithinFloor else {
            return highPriority ? .askUser(reason: .lowLocalSpaceButHighPriority) : .metadataOnly
        }
        if fileSize <= thresholds.autoDownloadSizeCeiling {
            return .autoDownload
        }
        if fileSize <= thresholds.promptSizeCeiling {
            return highPriority ? .autoDownload : .askUser(reason: .largeFile)
        }
        return highPriority ? .askUser(reason: .largeFavorite) : .metadataOnly
    }
}
