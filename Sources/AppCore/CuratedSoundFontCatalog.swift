import Foundation
import SoundFontModel

/// One soundfont the app itself offers, described by a small JSON manifest hosted on static
/// hosting — never bundled with the app itself (keeps the app's own download size small; see
/// `KnowledgeBase/SoundfontMgt/soundfontmgt.txt`).
public struct CuratedSoundFontDescriptor: Codable, Equatable, Sendable, Identifiable {
    public var id: String { downloadURL.absoluteString }
    public let displayName: String
    public let downloadURL: URL
    public let fileSize: Int64
    public let tags: [String]

    public init(displayName: String, downloadURL: URL, fileSize: Int64, tags: [String] = []) {
        self.displayName = displayName
        self.downloadURL = downloadURL
        self.fileSize = fileSize
        self.tags = tags
    }
}

public enum CuratedSoundFontCatalogError: Error, CustomStringConvertible {
    case network(Error)
    case invalidResponse

    public var description: String {
        switch self {
        case .network(let error): return "network error: \(error)"
        case .invalidResponse: return "the catalog manifest did not have the expected shape"
        }
    }
}

/// The app's short list of "offered" soundfonts — a curated soundfont is otherwise a perfectly
/// ordinary imported one (see `SoundFontOrigin.curated`, `ImprovSession.installCuratedSoundFont`):
/// same file layout, same import code path via `SoundFontLibrary.importFile`, the only
/// difference being where to re-download it from if the local file ever disappears.
public enum CuratedSoundFontCatalog {
    /// Blocks the calling thread until the manifest download completes — same
    /// "no async main, keep call sites plain synchronous code" bridge as `LLMEngine`'s own
    /// `syncDataTask`, not reused directly since it isn't `public` outside that module.
    public static func fetch(manifestURL: URL) throws -> [CuratedSoundFontDescriptor] {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Data, Error> = .failure(CuratedSoundFontCatalogError.invalidResponse)
        URLSession.shared.dataTask(with: manifestURL) { data, response, error in
            if let error {
                result = .failure(CuratedSoundFontCatalogError.network(error))
            } else if let data, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) {
                result = .success(data)
            } else {
                result = .failure(CuratedSoundFontCatalogError.invalidResponse)
            }
            semaphore.signal()
        }.resume()
        semaphore.wait()
        let data = try result.get()
        return try JSONDecoder().decode([CuratedSoundFontDescriptor].self, from: data)
    }

    /// Downloads `descriptor`'s file to a temp location — the caller (`ImprovSession
    /// .installCuratedSoundFont`) then imports it through the exact same
    /// `SoundFontLibrary.importFile` path as a user-picked file, tagging its origin so it can be
    /// re-downloaded later if the local copy disappears.
    static func download(_ descriptor: CuratedSoundFontDescriptor) throws -> URL {
        let semaphore = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<URL, Error> = .failure(CuratedSoundFontCatalogError.invalidResponse)
        URLSession.shared.downloadTask(with: descriptor.downloadURL) { location, response, error in
            defer { semaphore.signal() }
            if let error {
                result = .failure(CuratedSoundFontCatalogError.network(error))
                return
            }
            guard let location, let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                result = .failure(CuratedSoundFontCatalogError.invalidResponse)
                return
            }
            // `location` is deleted the moment this completion handler returns — move it
            // somewhere this call can still read it from afterward.
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension((descriptor.downloadURL.pathExtension.isEmpty ? "sf2" : descriptor.downloadURL.pathExtension))
            do {
                try FileManager.default.moveItem(at: location, to: destination)
                result = .success(destination)
            } catch {
                result = .failure(error)
            }
        }.resume()
        semaphore.wait()
        return try result.get()
    }
}
