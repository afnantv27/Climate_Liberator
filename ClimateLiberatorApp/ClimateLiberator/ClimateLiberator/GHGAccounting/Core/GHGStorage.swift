import Foundation

/// Per-user storage for the GHG module, beside the app's other data.
nonisolated struct GHGDataLocations: Sendable {
    let root: URL

    init(root: URL) { self.root = root }

    static var current: GHGDataLocations {
        GHGDataLocations(root: AppDataLocations.current.root.appendingPathComponent("GHG", isDirectory: true))
    }

    var inventoriesDirectory: URL { root.appendingPathComponent("Inventories", isDirectory: true) }
    var factorCacheDirectory: URL { root.appendingPathComponent("FactorCache", isDirectory: true) }
    var connectorsFile: URL { root.appendingPathComponent("connectors.json") }
    var customFactorsFile: URL { root.appendingPathComponent("custom_factors.json") }
    var exportsDirectory: URL { AppDataLocations.exportsDirectory.appendingPathComponent("GHG", isDirectory: true) }

    func cacheFile(for connectorID: String) -> URL {
        let safe = connectorID.replacingOccurrences(of: "/", with: "_")
        return factorCacheDirectory.appendingPathComponent("\(safe).json")
    }
}

nonisolated enum GHGJSON {
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

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(value).write(to: url, options: .atomic)
    }

    /// Returns nil when the file does not exist yet.
    static func read<T: Decodable>(_ type: T.Type, from url: URL) throws -> T? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        return try decoder().decode(type, from: Data(contentsOf: url))
    }
}

/// Connected emission-factor databases, their cached factors and user-defined factors.
