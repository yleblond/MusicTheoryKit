import Foundation

/// One instrument/preset entry read from a SoundFont2 (`.sf2`) file's `phdr` (preset headers)
/// sub-chunk. A single `.sf2` commonly bundles dozens of these (e.g. a full General MIDI bank),
/// each independently loadable via `AVAudioUnitSampler.loadSoundBankInstrument(program:bankMSB:
/// bankLSB:)` — but that API can only ever load *one* preset at a time, it has no way to
/// enumerate what else is in the file. `SoundFontPresetReader` fills that gap by parsing the
/// file's own RIFF structure instead.
public struct SoundFontPreset: Equatable, Sendable {
    public let name: String
    public let program: UInt16
    /// Raw `wBank` value as stored in the file's `phdr` record (SoundFont2 spec: a 16-bit word;
    /// by convention 0-127 for melodic banks, 128 reserved for percussion) — not yet mapped to
    /// `AVAudioUnitSampler`'s separate `bankMSB`/`bankLSB` parameters.
    public let bank: UInt16

    public init(name: String, program: UInt16, bank: UInt16) {
        self.name = name
        self.program = program
        self.bank = bank
    }

    public var identity: SoundFontPresetIdentity {
        SoundFontPresetIdentity(program: program, bank: bank)
    }
}

/// The `program`/`bank` pair that identifies one preset within a multi-preset `.sf2` file —
/// split out from `SoundFontPreset` (which also carries the preset's display `name`) so it can
/// be used as a storage key on its own, e.g. by `AppCore.SoundEntry` to say *which* preset of a
/// file an alias/favorite applies to. Deliberately kept as the raw SoundFont2 values rather than
/// pre-converted to `AVAudioUnitSampler`'s separate `bankMSB`/`bankLSB` — that conversion belongs
/// where the sound is actually loaded, not in a settings/identity model.
public struct SoundFontPresetIdentity: Codable, Equatable, Hashable, Sendable {
    public var program: UInt16
    public var bank: UInt16

    public init(program: UInt16, bank: UInt16) {
        self.program = program
        self.bank = bank
    }
}

public enum SoundFontPresetReaderError: Error, Equatable {
    case notARIFFFile
    case notASoundFontFile
    case missingChunk(String)
    case truncatedData
}

/// Human-readable metadata from a `.sf2` file's own `INFO` chunk — bank name, the engineer/
/// author, product, copyright/license terms, free-text comments, the software used to author
/// it. Every field is independently optional: the SoundFont2 spec requires none of them beyond
/// the version stamps this type doesn't bother surfacing (`ifil`/`iver`, internal/technical, not
/// generally interesting to a user). See `SoundFontPresetReader.info(at:)`.
public struct SoundFontInfo: Codable, Equatable, Sendable {
    public var bankName: String?
    public var soundEngine: String?
    public var creationDate: String?
    public var engineer: String?
    public var product: String?
    public var copyright: String?
    public var comment: String?
    public var software: String?

    public init(
        bankName: String? = nil, soundEngine: String? = nil, creationDate: String? = nil,
        engineer: String? = nil, product: String? = nil, copyright: String? = nil,
        comment: String? = nil, software: String? = nil
    ) {
        self.bankName = bankName
        self.soundEngine = soundEngine
        self.creationDate = creationDate
        self.engineer = engineer
        self.product = product
        self.copyright = copyright
        self.comment = comment
        self.software = software
    }

    public var isEmpty: Bool {
        bankName == nil && soundEngine == nil && creationDate == nil && engineer == nil
            && product == nil && copyright == nil && comment == nil && software == nil
    }
}

/// Reads the list of presets/instruments bundled inside a `.sf2` file by walking its RIFF
/// structure down to the `pdta` LIST's `phdr` sub-chunk. Reads only chunk headers plus the
/// (small — tens of bytes per preset) `phdr` chunk itself, never the bulk sample data (`sdta`,
/// which is most of a `.sf2`'s size) — important since a downloaded/untrusted SoundFont library
/// file can be very large.
public enum SoundFontPresetReader {
    private static let recordSize = 38

    public static func presets(at url: URL) throws -> [SoundFontPreset] {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try presets(readingFrom: handle)
    }

    /// Reads the file's `INFO` chunk, if any — every field is best-effort: a `.dls`, a
    /// corrupt/truncated `.sf2`, or an `.sf2` with no `INFO` chunk at all (technically allowed
    /// by the spec, though rare in practice) all just return an all-`nil` `SoundFontInfo`
    /// instead of throwing, since missing metadata is never a reason to refuse showing whatever
    /// else is known about the file (name, size, sync state...). Independent of `presets(at:)`:
    /// `INFO` and `pdta` are sibling top-level chunks, read in whatever order they appear.
    public static func info(at url: URL) throws -> SoundFontInfo {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return (try? info(readingFrom: handle)) ?? SoundFontInfo()
    }

    static func info(readingFrom handle: FileHandle) throws -> SoundFontInfo {
        let riffHeader = try readExactly(handle, 12)
        guard riffHeader[0..<4].elementsEqual(Array("RIFF".utf8)), riffHeader[8..<12].elementsEqual(Array("sfbk".utf8)) else {
            return SoundFontInfo()
        }
        while let (id, size) = try readChunkHeader(handle) {
            let sizeInt = Int(size)
            if id == "LIST" {
                let listType = try readExactly(handle, 4)
                let remaining = sizeInt - 4
                if String(decoding: listType, as: UTF8.self) == "INFO" {
                    return try readInfoSubChunks(handle, remainingBytes: remaining)
                }
                try skip(handle, remaining)
            } else {
                try skip(handle, sizeInt)
            }
            if sizeInt % 2 == 1 { try skip(handle, 1) }
        }
        return SoundFontInfo()
    }

    private static func readInfoSubChunks(_ handle: FileHandle, remainingBytes: Int) throws -> SoundFontInfo {
        var remaining = remainingBytes
        var info = SoundFontInfo()
        while remaining >= 8 {
            guard let (id, size) = try readChunkHeader(handle) else { break }
            remaining -= 8
            let sizeInt = Int(size)
            let bytes = try readExactly(handle, sizeInt)
            remaining -= sizeInt
            if sizeInt % 2 == 1 { try skip(handle, 1); remaining -= 1 }
            let text = decodeCString(bytes[...])
            guard !text.isEmpty else { continue }
            switch id {
            case "INAM": info.bankName = text
            case "isng": info.soundEngine = text
            case "ICRD": info.creationDate = text
            case "IENG": info.engineer = text
            case "IPRD": info.product = text
            case "ICOP": info.copyright = text
            case "ICMT": info.comment = text
            case "ISFT": info.software = text
            default: break
            }
        }
        return info
    }

    static func presets(readingFrom handle: FileHandle) throws -> [SoundFontPreset] {
        let riffHeader = try readExactly(handle, 12)
        guard riffHeader[0..<4].elementsEqual(Array("RIFF".utf8)) else {
            throw SoundFontPresetReaderError.notARIFFFile
        }
        guard riffHeader[8..<12].elementsEqual(Array("sfbk".utf8)) else {
            throw SoundFontPresetReaderError.notASoundFontFile
        }

        while let (id, size) = try readChunkHeader(handle) {
            let sizeInt = Int(size)
            if id == "LIST" {
                let listType = try readExactly(handle, 4)
                let listTypeString = String(decoding: listType, as: UTF8.self)
                let remaining = sizeInt - 4
                if listTypeString == "pdta" {
                    return try readPhdr(fromPdtaBody: handle, remainingBytes: remaining)
                }
                try skip(handle, remaining)
            } else {
                try skip(handle, sizeInt)
            }
            if sizeInt % 2 == 1 { try skip(handle, 1) } // RIFF chunks are word-aligned
        }
        throw SoundFontPresetReaderError.missingChunk("pdta")
    }

    private static func readPhdr(fromPdtaBody handle: FileHandle, remainingBytes: Int) throws -> [SoundFontPreset] {
        var remaining = remainingBytes
        while remaining >= 8 {
            guard let (id, size) = try readChunkHeader(handle) else { break }
            remaining -= 8
            let sizeInt = Int(size)
            if id == "phdr" {
                let bytes = try readExactly(handle, sizeInt)
                return try parsePhdr(bytes)
            }
            try skip(handle, sizeInt)
            remaining -= sizeInt
            if sizeInt % 2 == 1 { try skip(handle, 1); remaining -= 1 }
        }
        throw SoundFontPresetReaderError.missingChunk("phdr")
    }

    /// Each `phdr` record is 38 bytes (20-byte name + 3 `WORD`s + 3 unused `DWORD`s); the chunk
    /// always ends with one terminal "EOP" sentinel record (used only to close out the last
    /// preset's zone range), which is dropped from the returned list.
    private static func parsePhdr(_ bytes: [UInt8]) throws -> [SoundFontPreset] {
        guard bytes.count >= recordSize, bytes.count % recordSize == 0 else {
            throw SoundFontPresetReaderError.truncatedData
        }
        let recordCount = bytes.count / recordSize
        var presets: [SoundFontPreset] = []
        presets.reserveCapacity(recordCount - 1)
        for index in 0..<(recordCount - 1) {
            let offset = index * recordSize
            let name = decodeCString(bytes[offset..<(offset + 20)])
            let program = readUInt16LE(bytes, at: offset + 20)
            let bank = readUInt16LE(bytes, at: offset + 22)
            presets.append(SoundFontPreset(name: name, program: program, bank: bank))
        }
        return presets
    }

    private static func decodeCString(_ bytes: ArraySlice<UInt8>) -> String {
        String(decoding: bytes.prefix { $0 != 0 }, as: UTF8.self)
    }

    private static func readUInt16LE(_ bytes: [UInt8], at offset: Int) -> UInt16 {
        UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32LE(_ bytes: [UInt8], at offset: Int) -> UInt32 {
        UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    private static func readChunkHeader(_ handle: FileHandle) throws -> (id: String, size: UInt32)? {
        guard let idBytes = try handle.read(upToCount: 4) else { return nil }
        guard idBytes.count == 4 else {
            if idBytes.isEmpty { return nil }
            throw SoundFontPresetReaderError.truncatedData
        }
        let sizeBytes = try readExactly(handle, 4)
        let id = String(decoding: idBytes, as: UTF8.self)
        let size = readUInt32LE(sizeBytes, at: 0)
        return (id, size)
    }

    private static func readExactly(_ handle: FileHandle, _ count: Int) throws -> [UInt8] {
        guard count > 0 else { return [] }
        guard let data = try handle.read(upToCount: count), data.count == count else {
            throw SoundFontPresetReaderError.truncatedData
        }
        return [UInt8](data)
    }

    private static func skip(_ handle: FileHandle, _ count: Int) throws {
        guard count > 0 else { return }
        try handle.seek(toOffset: handle.offset() + UInt64(count))
    }
}
