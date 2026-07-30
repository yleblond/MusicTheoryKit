import Foundation
import SoundFontModel
import Localization

/// One category a `SoundFontCatalogEntry` can belong to — purely for grouping the catalog
/// browser UI, no other behavior attached.
public struct SoundFontCatalogCategory: Equatable, Sendable, Identifiable {
    public let id: String
    public let name: [AppLanguage: String]
    public let order: Int

    public init(id: String, name: [AppLanguage: String], order: Int) {
        self.id = id
        self.name = name
        self.order = order
    }

    public func localizedName(_ language: AppLanguage) -> String {
        name[language] ?? name[.fr] ?? name[.en] ?? id
    }
}

/// A soundfont the app itself offers a one-tap install for — described entirely in Swift source
/// (see `CuratedSoundFontCatalog.entries`), never fetched from a server: adding, correcting, or removing
/// an entry always ships as part of a normal app release, exactly like any other code change.
/// This is a deliberate choice, not a placeholder for a future server — see
/// `KnowledgeBase/SoundfontMgt/SPEC-catalogue-soundfonts.md` §1 for the full reasoning (mainly:
/// the catalog's own quality bar depends on every entry being individually license-verified at
/// curation time, which a live server can't enforce any better than a reviewed PR can).
///
/// `downloadURL` always points at the file's own original host — never a copy mirrored on our
/// own infrastructure (see `download(_:)`). This is a deliberate reversal of an early draft of
/// the SPEC above, which proposed mirroring every file on our own CDN; see the same document's
/// amended §4 for why that was dropped (lighter legal posture since we never redistribute a copy
/// ourselves, at the cost of no control over the origin's own uptime/Range support/content
/// stability — accepted trade-offs, not oversights).
public struct SoundFontCatalogEntry: Equatable, Sendable, Identifiable {
    public let id: String
    public let displayName: String
    public let author: String
    public let categoryId: String
    public let summary: [AppLanguage: String]
    public let license: License
    /// The file's own direct, versioned URL at its original host — chosen at curation time
    /// specifically to avoid an alias like `latest` that could silently change content underneath
    /// a pinned `sha256` (see `download(_:)`'s integrity check).
    public let downloadURL: URL
    /// A human-readable page about this soundfont (license text, author's own site) — shown as
    /// "en savoir plus" in the detail screen; may differ from `downloadURL` (often a directory
    /// listing or README rather than the file itself).
    public let infoURL: URL?
    public let sizeBytes: Int64
    public let sha256: String
    public let format: Format
    /// Bumped whenever `downloadURL`/`sha256` changes for the same `id` in a later app release —
    /// compared against `SoundFontOrigin.curated(catalogVersion:)` to surface "update available"
    /// (see `ImprovSession.catalogUpdates`).
    public let version: String
    public let recommended: Bool
    public let tags: [String]

    public init(
        id: String, displayName: String, author: String, categoryId: String,
        summary: [AppLanguage: String], license: License, downloadURL: URL, infoURL: URL?,
        sizeBytes: Int64, sha256: String, format: Format, version: String,
        recommended: Bool = false, tags: [String] = []
    ) {
        self.id = id
        self.displayName = displayName
        self.author = author
        self.categoryId = categoryId
        self.summary = summary
        self.license = license
        self.downloadURL = downloadURL
        self.infoURL = infoURL
        self.sizeBytes = sizeBytes
        self.sha256 = sha256
        self.format = format
        self.version = version
        self.recommended = recommended
        self.tags = tags
    }

    public func localizedSummary(_ language: AppLanguage) -> String {
        summary[language] ?? summary[.fr] ?? summary[.en] ?? ""
    }

    public struct License: Equatable, Sendable {
        public let name: String
        public let spdxId: String?
        public let url: URL?
        /// Whether the license (or, as with FluidR3, a condition attached to it — see
        /// `ImprovSession.installCuratedSoundFont`) requires this soundfont to appear in a
        /// visible credits screen once installed. Not about redistribution rights — those don't
        /// come up at all here, since we never host a copy ourselves (see this type's own doc
        /// comment).
        public let attributionRequired: Bool

        public init(name: String, spdxId: String? = nil, url: URL? = nil, attributionRequired: Bool) {
            self.name = name
            self.spdxId = spdxId
            self.url = url
            self.attributionRequired = attributionRequired
        }
    }

    /// `AVAudioUnitSampler` cannot read `.sf3` (Ogg Vorbis-compressed samples) — `CuratedSoundFontCatalog
    /// .entries` must never actually contain one, but the case exists so a mis-curated entry fails
    /// a compile-time-adjacent check (`CuratedSoundFontCatalog.installableEntries`) instead of silently
    /// shipping a bank nothing can load.
    public enum Format: String, Sendable {
        case sf2, sf3, dls
    }
}

public enum CuratedSoundFontCatalogError: Error, CustomStringConvertible {
    case network(Error)
    case invalidResponse
    /// The downloaded file's hash doesn't match `SoundFontCatalogEntry.sha256` — either the
    /// transfer was corrupted, or the origin silently replaced the file at that URL since this
    /// entry was curated. Never installed either way (see `ImprovSession
    /// .installCuratedSoundFont`'s doc comment for why this can't self-heal without a new
    /// release).
    case integrityCheckFailed
    case insufficientDiskSpace(required: Int64, available: Int64)

    public var description: String {
        switch self {
        case .network(let error): return "network error: \(error)"
        case .invalidResponse: return "the download did not have the expected shape"
        case .integrityCheckFailed: return "the downloaded file doesn't match what was expected — try again, or report this bank as broken"
        case .insufficientDiskSpace(let required, let available):
            let formatter = ByteCountFormatter()
            return "not enough free space: needs \(formatter.string(fromByteCount: required)), \(formatter.string(fromByteCount: available)) available"
        }
    }
}

/// How far along installing one `SoundFontCatalogEntry` is — surfaced to the UI so a long
/// (multi-hundred-megabyte) transfer never just shows an indefinite spinner. `.downloading`
/// carries a real fraction (from `URLSessionDownloadDelegate`, updated a few times per second);
/// `.installing` covers the brief hash+copy+index step afterward, which has no meaningful
/// fraction of its own (see `SoundFontHasher.copyAndHash` — a single streamed pass, not worth
/// instrumenting for what's normally a few seconds even for a 200 MB file).
public enum SoundFontInstallPhase: Equatable, Sendable {
    case downloading(fractionCompleted: Double)
    case installing
}

/// Delegate-based progress + cancellation support for `CuratedSoundFontCatalog.download`.
/// `URLSessionDownloadDelegate`'s callbacks fire on a background queue (this file passes
/// `delegateQueue: nil`), so neither closure is safe to touch UI-facing state from directly —
/// `download(_:onProgress:)` itself re-dispatches `onProgress` to the main actor before calling
/// through to the caller's own closure; `onCompletion` only ever resumes a continuation and does
/// its own (thread-safe) file move, so it doesn't need that hop. `@unchecked Sendable` because
/// every stored closure is only ever invoked from that one delegate queue, never concurrently
/// with itself — same rationale as `SoundFontLibrary`'s own `NSMetadataQuery` callbacks.
private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private let onCompletion: (URL?, URLResponse?, Error?) -> Void
    /// Set once a completion has already been delivered — `didCompleteWithError` fires after
    /// `didFinishDownloadingTo` even on success (with `error == nil`), and must not re-signal.
    private var didComplete = false

    init(onProgress: @escaping (Double) -> Void, onCompletion: @escaping (URL?, URLResponse?, Error?) -> Void) {
        self.onProgress = onProgress
        self.onCompletion = onCompletion
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64, totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        guard !didComplete else { return }
        didComplete = true
        onCompletion(location, downloadTask.response, nil)
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error, !didComplete else { return }
        didComplete = true
        onCompletion(nil, nil, error)
    }
}

/// The app's short list of "offered" soundfonts — a curated soundfont is otherwise a perfectly
/// ordinary imported one (see `SoundFontOrigin.curated`, `ImprovSession.installCuratedSoundFont`):
/// same file layout, same import code path via `SoundFontLibrary.importFile`, the only
/// difference being where to re-download it from if the local file ever disappears.
public enum CuratedSoundFontCatalog {
    public static let categories: [SoundFontCatalogCategory] = [
        SoundFontCatalogCategory(id: "gm", name: [.fr: "General MIDI", .en: "General MIDI"], order: 1),
    ]

    /// **Curation status (30/07/2026): one verified entry.** Every field below (size, sha256,
    /// license text, author names) was checked against the file actually served at `downloadURL`
    /// at curation time — see `KnowledgeBase/SoundfontMgt/SPEC-catalogue-soundfonts.md` §4.3 for
    /// the procedure. Several other candidates from that document's §12 were deliberately left
    /// out rather than added with guessed/unverified data:
    /// - FluidR3 GM (member.keymusician.com) was unreachable when this list was curated —
    ///   revisit once/if the host is confirmed back up.
    /// - The entire FreePats catalog (Salamander Grand Piano, the FreePats GM set, synth
    ///   pads/effects) is only distributed as `.7z`/`.tar.xz`/`.tar.bz2` archives, never a bare
    ///   `.sf2` — installing from one would require an in-app archive extractor (no public
    ///   Foundation API covers 7z, and `.tar` has no built-in reader either), which is real new
    ///   scope, not a hosting choice, and out of scope here. Revisit if that's ever built.
    public static let entries: [SoundFontCatalogEntry] = [
        SoundFontCatalogEntry(
            id: "musescore-general",
            displayName: "MuseScore General",
            author: "S. Christian Collins, Frank Wen, Michael Cowgill",
            categoryId: "gm",
            summary: [
                .fr: "Banque General MIDI complète et polyvalente, dérivée de FluidR3. Le meilleur point de départ.",
                .en: "Complete, versatile General MIDI bank, derived from FluidR3. The best starting point.",
            ],
            license: SoundFontCatalogEntry.License(
                name: "MIT",
                spdxId: "MIT",
                url: URL(string: "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General_License.md"),
                attributionRequired: true
            ),
            downloadURL: URL(string: "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/MuseScore_General.sf2")!,
            infoURL: URL(string: "https://ftp.osuosl.org/pub/musescore/soundfont/MuseScore_General/"),
            sizeBytes: 215_614_036,
            sha256: "ee51d2c4b1525e70f19a45909c4fd7a2e26d91d115fa89dbf5a6bc413d8b9bf3",
            format: .sf2,
            version: "0.2",
            recommended: true,
            tags: ["gm", "orchestral", "complet"]
        ),
    ]

    /// `entries`, filtered to formats this app can actually load — defensive against a future
    /// entry being added with `format: .sf3`/anything `AVAudioUnitSampler` can't read (see
    /// `SoundFontCatalogEntry.Format`'s own doc comment).
    public static var installableEntries: [SoundFontCatalogEntry] {
        entries.filter { $0.format == .sf2 || $0.format == .dls }
    }

    public static func category(withId id: String) -> SoundFontCatalogCategory? {
        categories.first { $0.id == id }
    }

    /// Downloads `entry`'s file to a temp location, reporting progress via `onProgress`
    /// (fraction completed, called several times per second on the main actor) — the caller
    /// (`ImprovSession.installCuratedSoundFont`) then imports it through the exact same
    /// `SoundFontLibrary.importFile` path as a user-picked file, tagging its origin so it can be
    /// re-downloaded later if the local copy disappears. Checks free disk space up front
    /// (`entry.sizeBytes` plus a fixed margin for the temp copy) — never even starts a multi-
    /// hundred-megabyte transfer that's certain to fail partway through. Does NOT verify
    /// `sha256` itself: the caller already re-hashes the file while copying it into place (via
    /// `SoundFontLibrary.importFile` → `SoundFontHasher.copyAndHash`), so verifying here too
    /// would hash the same bytes twice for no benefit — see `ImprovSession
    /// .installCuratedSoundFont` for where the comparison against `entry.sha256` actually happens.
    ///
    /// Genuinely `async` (no thread-blocking wait anywhere) and cancellation-aware: cancelling
    /// the `Task` this call is running in (e.g. an "Abandonner" button calling `.cancel()` on a
    /// stored `Task` handle) aborts the underlying `URLSessionDownloadTask` via
    /// `withTaskCancellationHandler` and this function throws `CancellationError` — the UI can
    /// catch that specifically to end the operation quietly, without showing it as a failure.
    static func download(_ entry: SoundFontCatalogEntry, onProgress: @escaping @MainActor (Double) -> Void) async throws -> URL {
        let available = DeviceFreeSpace.availableBytes()
        let required = entry.sizeBytes + 50_000_000
        guard available >= required else {
            throw CuratedSoundFontCatalogError.insufficientDiskSpace(required: required, available: available)
        }

        var request = URLRequest(url: entry.downloadURL)
        // Some volunteer/university hosts filter or throttle requests with no/generic
        // User-Agent — a small courtesy given we're downloading straight from their server
        // rather than a mirror we control (see this file's own doc comment).
        request.setValue("JamShack/1.0 (+soundfont catalog)", forHTTPHeaderField: "User-Agent")

        // `withTaskCancellationHandler`'s `operation` and `onCancel` closures both need to reach
        // the same `URLSessionDownloadTask`, and the session/delegate must stay alive for the
        // whole transfer — a plain `URLSession` does NOT keep itself or its delegate alive on
        // its own once this function's synchronous setup returns, so all three are held here
        // rather than as bare locals.
        let handle = DownloadTaskHandle()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<URL, Error>) in
                let delegate = DownloadProgressDelegate(
                    onProgress: { fraction in Task { @MainActor in onProgress(fraction) } },
                    onCompletion: { location, response, error in
                        handle.session?.finishTasksAndInvalidate()
                        if let error {
                            let nsError = error as NSError
                            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorCancelled {
                                continuation.resume(throwing: CancellationError())
                            } else {
                                continuation.resume(throwing: CuratedSoundFontCatalogError.network(error))
                            }
                            return
                        }
                        guard let location, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                            continuation.resume(throwing: CuratedSoundFontCatalogError.invalidResponse)
                            return
                        }
                        // `location` is deleted the moment this delegate call returns — move it
                        // somewhere this call can still read it from afterward.
                        let destination = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension(entry.downloadURL.pathExtension.isEmpty ? "sf2" : entry.downloadURL.pathExtension)
                        do {
                            try FileManager.default.moveItem(at: location, to: destination)
                            continuation.resume(returning: destination)
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }
                )
                let session = URLSession(configuration: .ephemeral, delegate: delegate, delegateQueue: nil)
                let task = session.downloadTask(with: request)
                handle.delegate = delegate
                handle.session = session
                handle.task = task
                task.resume()
            }
        } onCancel: {
            handle.task?.cancel()
        }
    }
}

/// Keeps a download's `URLSession`/delegate/task triple alive for the operation's whole
/// lifetime and gives `withTaskCancellationHandler`'s `onCancel` closure something to reach —
/// see `CuratedSoundFontCatalog.download`'s own doc comment. `@unchecked Sendable`: every
/// stored property is written once synchronously before `task.resume()` and read only from
/// `onCancel`/the delegate's own completion callback, never mutated concurrently.
private final class DownloadTaskHandle: @unchecked Sendable {
    var session: URLSession?
    var delegate: DownloadProgressDelegate?
    var task: URLSessionDownloadTask?
}
