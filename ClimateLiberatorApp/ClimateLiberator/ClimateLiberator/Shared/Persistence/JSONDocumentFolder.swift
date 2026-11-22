import Foundation

/// JSON coders used for every saved file: readable, stable key order, ISO dates.
nonisolated enum AppJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// A folder holding one JSON file per document, named by the document's UUID.
///
/// Stores own their in-memory state and unsaved tracking; this type only does the
/// file work, so it can be tested without any UI and reused by every module.
nonisolated struct JSONDocumentFolder<Document: Codable & Identifiable & Sendable>: Sendable where Document.ID == UUID {
    let directory: URL

    init(directory: URL) {
        self.directory = directory
    }

    /// A folder under the app's data directory, e.g. `AppData/Clients`.
    static func appData(_ name: String) -> JSONDocumentFolder {
        JSONDocumentFolder(directory: AppDataLocations.current.root.appendingPathComponent(name, isDirectory: true))
    }

    func fileURL(_ id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).json")
    }

    func exists(_ id: UUID) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(id).path)
    }

    /// Every readable document, plus the names of files that could not be read.
    func loadAll() -> (documents: [Document], unreadable: [String]) {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var documents: [Document] = []
        var unreadable: [String] = []
        for file in files where file.pathExtension.lowercased() == "json" {
            do {
                documents.append(try read(file))
            } catch {
                unreadable.append(file.lastPathComponent)
            }
        }
        return (documents, unreadable)
    }

    func read(_ file: URL) throws -> Document {
        try AppJSON.decoder().decode(Document.self, from: Data(contentsOf: file))
    }

    /// Writes atomically, so a crash mid-save never leaves a half-written file.
    func write(_ document: Document) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try AppJSON.encoder().encode(document).write(to: fileURL(document.id), options: .atomic)
    }

    /// Moves the file to the Trash so a deletion can be undone in Finder.
    func trash(_ id: UUID) throws {
        let url = fileURL(id)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
