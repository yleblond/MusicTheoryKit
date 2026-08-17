import Foundation
import Compression

/// Reads plain ZIP archives (the container format behind MusicXML's `.mxl` and MuseScore's
/// `.mscz`) — hand-rolled, same "no third-party dependency" style as `SMFReader`: ZIP's central
/// directory/local file header structure is simple and well documented, and Apple's own
/// `Compression` framework (available on every platform this project targets) already decodes
/// the raw DEFLATE stream a ZIP "deflate" entry stores, so nothing beyond Foundation is needed.
///
/// Deliberately v1: no ZIP64 (needed only past ~4GB or 65535 entries, never for a score file),
/// no encryption, no multi-disk archives.
public enum ZipArchiveReader {
    public enum ZipArchiveError: Error, Equatable {
        case notAZipArchive
        case entryNotFound(String)
        case unsupportedCompressionMethod(Int)
        case corruptArchive
    }

    /// Every entry name in the archive, in central-directory order.
    public static func listEntryNames(data: Data) throws -> [String] {
        try centralDirectory(data: data).map(\.name)
    }

    /// Decompressed bytes of one named entry — exact match only (ZIP entry names are
    /// case-sensitive, forward-slash-separated paths).
    public static func extract(entryName: String, from data: Data) throws -> Data {
        guard let record = try centralDirectory(data: data).first(where: { $0.name == entryName }) else {
            throw ZipArchiveError.entryNotFound(entryName)
        }
        return try extract(record: record, data: data)
    }

    // MARK: - Central directory

    private struct CentralDirectoryRecord {
        let name: String
        let compressionMethod: Int
        let compressedSize: Int
        let uncompressedSize: Int
        let localHeaderOffset: Int
    }

    /// Locates the End Of Central Directory record (scanning backward from EOF, since it can be
    /// followed by a variable-length, usually-empty comment), then walks the fixed-size Central
    /// Directory it points to.
    private static func centralDirectory(data: Data) throws -> [CentralDirectoryRecord] {
        let bytes = [UInt8](data)
        guard bytes.count >= 22 else { throw ZipArchiveError.notAZipArchive }

        // The EOCD record is at least 22 bytes; its comment field can push it up to 22 + 65535.
        let searchFloor = max(0, bytes.count - 22 - 65535)
        var eocdOffset: Int?
        var i = bytes.count - 22
        while i >= searchFloor {
            if bytes[i] == 0x50, bytes[i + 1] == 0x4B, bytes[i + 2] == 0x05, bytes[i + 3] == 0x06 {
                eocdOffset = i
                break
            }
            i -= 1
        }
        guard let eocdOffset else { throw ZipArchiveError.notAZipArchive }

        var cursor = LittleEndianCursor(bytes: bytes, offset: eocdOffset + 4)
        _ = try cursor.readUInt16() // disk number
        _ = try cursor.readUInt16() // disk with CD start
        _ = try cursor.readUInt16() // CD entries on this disk
        let totalEntries = Int(try cursor.readUInt16())
        _ = try cursor.readUInt32() // CD size
        let cdOffset = Int(try cursor.readUInt32())

        guard cdOffset >= 0, cdOffset <= bytes.count else { throw ZipArchiveError.corruptArchive }
        var cdCursor = LittleEndianCursor(bytes: bytes, offset: cdOffset)
        var records: [CentralDirectoryRecord] = []
        for _ in 0..<totalEntries {
            guard try cdCursor.readUInt32() == 0x02014B50 else { throw ZipArchiveError.corruptArchive }
            _ = try cdCursor.readUInt16() // version made by
            _ = try cdCursor.readUInt16() // version needed
            _ = try cdCursor.readUInt16() // general purpose flag
            let method = Int(try cdCursor.readUInt16())
            _ = try cdCursor.readUInt16() // last mod time
            _ = try cdCursor.readUInt16() // last mod date
            _ = try cdCursor.readUInt32() // crc32
            let compressedSize = Int(try cdCursor.readUInt32())
            let uncompressedSize = Int(try cdCursor.readUInt32())
            let nameLength = Int(try cdCursor.readUInt16())
            let extraLength = Int(try cdCursor.readUInt16())
            let commentLength = Int(try cdCursor.readUInt16())
            _ = try cdCursor.readUInt16() // disk number start
            _ = try cdCursor.readUInt16() // internal file attributes
            _ = try cdCursor.readUInt32() // external file attributes
            let localHeaderOffset = Int(try cdCursor.readUInt32())
            let nameBytes = try cdCursor.readBytes(nameLength)
            try cdCursor.skip(extraLength)
            try cdCursor.skip(commentLength)
            let name = String(bytes: nameBytes, encoding: .utf8) ?? ""
            records.append(CentralDirectoryRecord(
                name: name, compressionMethod: method, compressedSize: compressedSize,
                uncompressedSize: uncompressedSize, localHeaderOffset: localHeaderOffset
            ))
        }
        return records
    }

    // MARK: - Entry extraction

    private static func extract(record: CentralDirectoryRecord, data: Data) throws -> Data {
        let bytes = [UInt8](data)
        var cursor = LittleEndianCursor(bytes: bytes, offset: record.localHeaderOffset)
        guard try cursor.readUInt32() == 0x04034B50 else { throw ZipArchiveError.corruptArchive }
        _ = try cursor.readUInt16() // version needed
        _ = try cursor.readUInt16() // general purpose flag
        _ = try cursor.readUInt16() // compression method (trusted from the central directory instead)
        _ = try cursor.readUInt16() // last mod time
        _ = try cursor.readUInt16() // last mod date
        _ = try cursor.readUInt32() // crc32
        _ = try cursor.readUInt32() // compressed size
        _ = try cursor.readUInt32() // uncompressed size
        let nameLength = Int(try cursor.readUInt16())
        let extraLength = Int(try cursor.readUInt16())
        try cursor.skip(nameLength)
        try cursor.skip(extraLength)

        let compressedBytes = try cursor.readBytes(record.compressedSize)

        switch record.compressionMethod {
        case 0: // stored — no compression
            return Data(compressedBytes)
        case 8: // deflate — a ZIP "deflate" entry is a raw DEFLATE stream (no zlib/gzip wrapper),
            // exactly what `COMPRESSION_ZLIB` decodes despite the confusingly zlib-flavored name.
            return try inflate(compressedBytes, uncompressedSize: record.uncompressedSize)
        default:
            throw ZipArchiveError.unsupportedCompressionMethod(record.compressionMethod)
        }
    }

    private static func inflate(_ compressedBytes: [UInt8], uncompressedSize: Int) throws -> Data {
        guard uncompressedSize > 0 else { return Data() }
        var destination = [UInt8](repeating: 0, count: uncompressedSize)
        let decodedCount = destination.withUnsafeMutableBufferPointer { destinationBuffer -> Int in
            compressedBytes.withUnsafeBufferPointer { sourceBuffer -> Int in
                compression_decode_buffer(
                    destinationBuffer.baseAddress!, uncompressedSize,
                    sourceBuffer.baseAddress!, compressedBytes.count,
                    nil, COMPRESSION_ZLIB
                )
            }
        }
        guard decodedCount == uncompressedSize else { throw ZipArchiveError.corruptArchive }
        return Data(destination)
    }
}

/// A byte-offset cursor over an in-memory ZIP archive — little-endian, unlike SMF's `ByteCursor`
/// (MIDI is big-endian; ZIP is little-endian), so kept as its own type rather than shared.
private struct LittleEndianCursor {
    let bytes: [UInt8]
    var offset: Int

    init(bytes: [UInt8], offset: Int) {
        self.bytes = bytes
        self.offset = offset
    }

    mutating func readBytes(_ count: Int) throws -> [UInt8] {
        guard count >= 0, offset + count <= bytes.count else { throw ZipArchiveReader.ZipArchiveError.corruptArchive }
        defer { offset += count }
        return Array(bytes[offset ..< offset + count])
    }

    mutating func readUInt16() throws -> UInt16 {
        let b = try readBytes(2)
        return UInt16(b[0]) | UInt16(b[1]) << 8
    }

    mutating func readUInt32() throws -> UInt32 {
        let b = try readBytes(4)
        return UInt32(b[0]) | UInt32(b[1]) << 8 | UInt32(b[2]) << 16 | UInt32(b[3]) << 24
    }

    mutating func skip(_ count: Int) throws {
        guard count >= 0, offset + count <= bytes.count else { throw ZipArchiveReader.ZipArchiveError.corruptArchive }
        offset += count
    }
}
