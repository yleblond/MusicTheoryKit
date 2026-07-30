import CryptoKit
import Foundation

/// Content-hashes a soundfont file — the only stable identity a `.sf2`/`.dls` can have, since
/// the user is free to rename or move the file at any time (see `SoundFontEntry.hash`). Always
/// streamed in fixed-size chunks: these files can be several gigabytes, and must never be
/// loaded whole into memory just to compute a digest.
public enum SoundFontHasher {
    public enum HashError: Error {
        case couldNotOpenFile
    }

    private static let chunkSize = 1 << 20 // 1 MB

    public static func sha256Hex(ofFileAt url: URL) throws -> String {
        guard let handle = FileHandle(forReadingAtPath: url.path) else { throw HashError.couldNotOpenFile }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    /// Copies `source` to `destination` while hashing it in the same pass — avoids reading a
    /// multi-gigabyte file twice (once to copy, once to hash) on import.
    @discardableResult
    public static func copyAndHash(from source: URL, to destination: URL) throws -> String {
        guard let input = FileHandle(forReadingAtPath: source.path) else { throw HashError.couldNotOpenFile }
        defer { try? input.close() }
        FileManager.default.createFile(atPath: destination.path, contents: nil)
        guard let output = FileHandle(forWritingAtPath: destination.path) else { throw HashError.couldNotOpenFile }
        defer { try? output.close() }
        var hasher = SHA256()
        while let chunk = try input.read(upToCount: chunkSize), !chunk.isEmpty {
            hasher.update(data: chunk)
            output.write(chunk)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }
}
