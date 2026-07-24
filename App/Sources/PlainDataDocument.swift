import SwiftUI
import UniformTypeIdentifiers

/// Minimal `FileDocument` wrapping already-serialized bytes — hands `ImprovSession`'s
/// existing JSON-writing methods (which write to a file path, not a `Data` value) to
/// SwiftUI's `.fileExporter` on iOS, without duplicating any JSON-encoding logic here: the
/// caller writes to a temp file via the normal AppCore API first, reads the bytes back, then
/// wraps them in this for the export sheet.
struct PlainDataDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    static var writableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
