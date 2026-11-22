import Foundation

// MARK: - Storage

/// Per-user storage for the Disclosure workspace, beside the app's other data.
nonisolated struct DisclosureDataLocations: Sendable {
    let root: URL
    let exportsDirectory: URL

    init(root: URL, exportsDirectory: URL) {
        self.root = root
        self.exportsDirectory = exportsDirectory
    }

    static var current: DisclosureDataLocations {
        DisclosureDataLocations(root: AppDataLocations.current.root.appendingPathComponent("Disclosure", isDirectory: true),
                                exportsDirectory: AppDataLocations.exportsDirectory.appendingPathComponent("Disclosure", isDirectory: true))
    }

    var engagementsDirectory: URL { root.appendingPathComponent("Engagements", isDirectory: true) }

    func engagementFile(_ id: UUID) -> URL {
        engagementsDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}

nonisolated enum DisclosureJSON {
    static func encoder() -> JSONEncoder { AppJSON.encoder() }
    static func decoder() -> JSONDecoder { AppJSON.decoder() }

    static func write(_ engagement: DisclosureEngagement, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(engagement).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> DisclosureEngagement {
        try decoder().decode(DisclosureEngagement.self, from: Data(contentsOf: url))
    }
}

// MARK: - Shared utilities under their Disclosure names

typealias DisclosureFormat = DisplayFormat
typealias DisclosureCSV = CSVText
