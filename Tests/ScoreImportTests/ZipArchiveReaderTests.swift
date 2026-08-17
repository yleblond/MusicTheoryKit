import XCTest
import Compression
@testable import ScoreImport

final class ZipArchiveReaderTests: XCTestCase {
    // MARK: - Byte-building helpers (deliberately independent of ZipArchiveReader's own reading code)

    private func u16(_ value: Int) -> [UInt8] { [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)] }
    private func u32(_ value: Int) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF), UInt8((value >> 16) & 0xFF), UInt8((value >> 24) & 0xFF)]
    }

    private func deflate(_ input: [UInt8]) -> [UInt8] {
        var destination = [UInt8](repeating: 0, count: input.count + 128)
        let count = destination.withUnsafeMutableBufferPointer { dst in
            input.withUnsafeBufferPointer { src in
                compression_encode_buffer(dst.baseAddress!, dst.count, src.baseAddress!, input.count, nil, COMPRESSION_ZLIB)
            }
        }
        return Array(destination.prefix(count))
    }

    /// Builds a minimal, single-or-multi-entry ZIP archive by hand (local file headers + central
    /// directory + end-of-central-directory record) — the same "construct the exact byte format
    /// from scratch" convention `SMFReaderTests` already uses for MIDI fixtures.
    private func makeZip(entries: [(name: String, content: [UInt8], compress: Bool)]) -> Data {
        var body: [UInt8] = []
        var centralDirectory: [UInt8] = []

        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let stored = entry.content
            let compressed = entry.compress ? deflate(stored) : stored
            let method = entry.compress ? 8 : 0
            let localHeaderOffset = body.count

            let localHeader: [UInt8] =
                u32(0x0403_4B50) + u16(20) + u16(0) + u16(method) + u16(0) + u16(0) +
                u32(0) + u32(compressed.count) + u32(stored.count) + u16(nameBytes.count) + u16(0)
            body += localHeader + nameBytes + compressed

            let centralEntry: [UInt8] =
                u32(0x0201_4B50) + u16(20) + u16(20) + u16(0) + u16(method) + u16(0) + u16(0) +
                u32(0) + u32(compressed.count) + u32(stored.count) + u16(nameBytes.count) + u16(0) + u16(0) +
                u16(0) + u16(0) + u32(0) + u32(localHeaderOffset)
            centralDirectory += centralEntry + nameBytes
        }

        let centralDirectoryOffset = body.count
        let eocd: [UInt8] =
            u32(0x0605_4B50) + u16(0) + u16(0) + u16(entries.count) + u16(entries.count) +
            u32(centralDirectory.count) + u32(centralDirectoryOffset) + u16(0)

        return Data(body + centralDirectory + eocd)
    }

    // MARK: - Tests

    func testStoredEntryRoundTrips() throws {
        let content = Array("<hello>world</hello>".utf8)
        let zip = makeZip(entries: [(name: "score.xml", content: content, compress: false)])

        XCTAssertEqual(try ZipArchiveReader.listEntryNames(data: zip), ["score.xml"])
        XCTAssertEqual(try ZipArchiveReader.extract(entryName: "score.xml", from: zip), Data(content))
    }

    func testDeflatedEntryRoundTrips() throws {
        // Long and repetitive enough that DEFLATE actually compresses it, not just passes it
        // through — a real test of the decompression path, not an accidental no-op.
        let content = Array(String(repeating: "<note><pitch>C4</pitch></note>", count: 50).utf8)
        let zip = makeZip(entries: [(name: "score.xml", content: content, compress: true)])

        XCTAssertEqual(try ZipArchiveReader.extract(entryName: "score.xml", from: zip), Data(content))
    }

    func testMultipleEntriesAreAllListedAndExtractableIndependently() throws {
        let container = Array("<container/>".utf8)
        let score = Array(String(repeating: "abc", count: 30).utf8)
        let zip = makeZip(entries: [
            (name: "META-INF/container.xml", content: container, compress: false),
            (name: "score.xml", content: score, compress: true),
        ])

        XCTAssertEqual(try ZipArchiveReader.listEntryNames(data: zip), ["META-INF/container.xml", "score.xml"])
        XCTAssertEqual(try ZipArchiveReader.extract(entryName: "META-INF/container.xml", from: zip), Data(container))
        XCTAssertEqual(try ZipArchiveReader.extract(entryName: "score.xml", from: zip), Data(score))
    }

    func testMissingEntryThrows() throws {
        let zip = makeZip(entries: [(name: "a.xml", content: [1, 2, 3], compress: false)])
        XCTAssertThrowsError(try ZipArchiveReader.extract(entryName: "missing.xml", from: zip)) { error in
            XCTAssertEqual(error as? ZipArchiveReader.ZipArchiveError, .entryNotFound("missing.xml"))
        }
    }

    func testNonZipDataThrowsNotAZipArchive() {
        XCTAssertThrowsError(try ZipArchiveReader.listEntryNames(data: Data("not a zip".utf8))) { error in
            XCTAssertEqual(error as? ZipArchiveReader.ZipArchiveError, .notAZipArchive)
        }
    }
}
