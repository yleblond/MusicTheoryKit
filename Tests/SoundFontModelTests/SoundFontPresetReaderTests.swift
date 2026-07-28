import XCTest
@testable import SoundFontModel

/// `SoundFontPresetReader` has no real `.sf2` fixture to read (none checked into the repo, and
/// pulling in a real SoundFont just for this would be a large/unlicensed binary asset) — so
/// these tests build minimal synthetic RIFF/`sfbk` byte buffers by hand instead, exercising the
/// exact chunk-walking logic (`LIST`/`pdta`/`phdr`) against known bytes.
final class SoundFontPresetReaderTests: XCTestCase {
    func testReadsPresetsFromPhdrChunkAndDropsTerminalSentinel() throws {
        let data = makeMinimalSoundFont(presets: [
            ("Grand Piano", program: 0, bank: 0),
            ("Church Organ", program: 19, bank: 0),
            ("Marching Snare", program: 38, bank: 128),
        ])
        let url = try writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let presets = try SoundFontPresetReader.presets(at: url)

        XCTAssertEqual(presets, [
            SoundFontPreset(name: "Grand Piano", program: 0, bank: 0),
            SoundFontPreset(name: "Church Organ", program: 19, bank: 0),
            SoundFontPreset(name: "Marching Snare", program: 38, bank: 128),
        ])
    }

    func testSkipsUnrelatedListChunksBeforePdta() throws {
        var data = riffHeader(formType: "sfbk")
        data += listChunk(type: "INFO", body: chunk(id: "ifil", body: [0, 0, 0, 0]))
        data += listChunk(type: "pdta", body: chunk(id: "phdr", body: phdrRecords(presets: [
            ("Solo Sound", program: 5, bank: 0),
        ])))
        let url = try writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        let presets = try SoundFontPresetReader.presets(at: url)

        XCTAssertEqual(presets, [SoundFontPreset(name: "Solo Sound", program: 5, bank: 0)])
    }

    func testThrowsOnNonRIFFFile() throws {
        let url = try writeTempFile(Array("not a sound font".utf8))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SoundFontPresetReader.presets(at: url)) { error in
            XCTAssertEqual(error as? SoundFontPresetReaderError, .notARIFFFile)
        }
    }

    func testThrowsOnRIFFFileThatIsNotASoundFont() throws {
        let url = try writeTempFile(riffHeader(formType: "WAVE"))
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SoundFontPresetReader.presets(at: url)) { error in
            XCTAssertEqual(error as? SoundFontPresetReaderError, .notASoundFontFile)
        }
    }

    func testThrowsWhenPdtaChunkIsMissing() throws {
        var data = riffHeader(formType: "sfbk")
        data += listChunk(type: "INFO", body: chunk(id: "ifil", body: [0, 0, 0, 0]))
        let url = try writeTempFile(data)
        defer { try? FileManager.default.removeItem(at: url) }

        XCTAssertThrowsError(try SoundFontPresetReader.presets(at: url)) { error in
            XCTAssertEqual(error as? SoundFontPresetReaderError, .missingChunk("pdta"))
        }
    }

    // MARK: - Synthetic SF2 byte builders

    private func makeMinimalSoundFont(presets: [(String, program: UInt16, bank: UInt16)]) -> [UInt8] {
        var data = riffHeader(formType: "sfbk")
        data += listChunk(type: "pdta", body: chunk(id: "phdr", body: phdrRecords(presets: presets)))
        return data
    }

    private func riffHeader(formType: String) -> [UInt8] {
        // Size field left at 0 — the reader never reads the top-level RIFF size, only walks
        // chunks until EOF or it finds what it's after.
        Array("RIFF".utf8) + uint32LE(0) + Array(formType.utf8)
    }

    private func listChunk(type: String, body: [UInt8]) -> [UInt8] {
        chunk(id: "LIST", body: Array(type.utf8) + body)
    }

    private func chunk(id: String, body: [UInt8]) -> [UInt8] {
        var bytes = Array(id.utf8) + uint32LE(UInt32(body.count)) + body
        if body.count % 2 == 1 { bytes.append(0) } // word-align, like a real RIFF writer would
        return bytes
    }

    private func phdrRecords(presets: [(String, program: UInt16, bank: UInt16)]) -> [UInt8] {
        var bytes: [UInt8] = []
        for (name, program, bank) in presets {
            bytes += phdrRecord(name: name, program: program, bank: bank)
        }
        bytes += phdrRecord(name: "EOP", program: 0, bank: 0) // terminal sentinel
        return bytes
    }

    private func phdrRecord(name: String, program: UInt16, bank: UInt16) -> [UInt8] {
        var nameBytes = Array(name.utf8.prefix(20))
        nameBytes += Array(repeating: UInt8(0), count: 20 - nameBytes.count)
        return nameBytes
            + uint16LE(program)
            + uint16LE(bank)
            + uint16LE(0) // wPresetBagNdx — unused by the reader
            + uint32LE(0) // dwLibrary
            + uint32LE(0) // dwGenre
            + uint32LE(0) // dwMorphology
    }

    private func uint16LE(_ value: UInt16) -> [UInt8] {
        [UInt8(value & 0xFF), UInt8((value >> 8) & 0xFF)]
    }

    private func uint32LE(_ value: UInt32) -> [UInt8] {
        [
            UInt8(value & 0xFF),
            UInt8((value >> 8) & 0xFF),
            UInt8((value >> 16) & 0xFF),
            UInt8((value >> 24) & 0xFF),
        ]
    }

    private func writeTempFile(_ bytes: [UInt8]) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".sf2")
        try Data(bytes).write(to: url)
        return url
    }
}
