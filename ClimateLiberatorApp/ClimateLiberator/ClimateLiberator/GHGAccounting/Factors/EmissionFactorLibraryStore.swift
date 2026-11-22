import Foundation
import Combine

@MainActor
final class EmissionFactorLibraryStore: ObservableObject {
    @Published private(set) var connectors: [EmissionFactorConnector] = [] { didSet { factorIndex = nil } }
    @Published private(set) var cachedFactors: [String: [EmissionFactor]] = [:] { didSet { factorIndex = nil } }
    @Published private(set) var customFactors: [EmissionFactor] = [] { didSet { factorIndex = nil } }
    @Published private(set) var syncingConnectorIDs: Set<String> = []
    @Published private(set) var lastWarnings: [String] = []
    @Published var statusMessage = "Reference library loaded. Connect a database to add more factors."

    static let customConnectorID = "custom"
    static let maxCachedFactorsPerConnector = 20_000

    let locations: GHGDataLocations
    let service: EmissionFactorConnectorService
    let secrets: SecretStoring
    /// False in tests: nothing is read from or written to disk.
    private let persists: Bool

    init(locations: GHGDataLocations = .current,
         service: EmissionFactorConnectorService = EmissionFactorConnectorService(),
         secrets: SecretStoring = KeychainSecretStore(),
         loadFromDisk: Bool = true) {
        self.locations = locations
        self.service = service
        self.secrets = secrets
        self.persists = loadFromDisk
        if loadFromDisk { load() } else { connectors = [.bundled] }
    }

    // MARK: Reading

    /// Factor plus its lower-cased search text, built once per change to the sources.
    private struct IndexedFactor {
        let factor: EmissionFactor
        let searchText: String
        let lowercasedName: String
    }

    private struct FactorIndex {
        let entries: [IndexedFactor]
        let byID: [String: Int]
    }

    private var factorIndex: FactorIndex?

    private var index: FactorIndex {
        if let factorIndex { return factorIndex }
        var seen = Set<String>()
        var entries: [IndexedFactor] = []
        func add(_ factors: [EmissionFactor]) {
            for factor in factors where seen.insert(factor.id).inserted {
                let searchText = [factor.name, factor.category, factor.region, factor.source, factor.activityUnit]
                    .joined(separator: " ").lowercased()
                entries.append(IndexedFactor(factor: factor, searchText: searchText, lowercasedName: factor.name.lowercased()))
            }
        }
        add(customFactors)
        for connector in connectors where connector.isEnabled {
            if connector.kind == .bundled { add(EmissionFactorSeedLibrary.factors) }
            else { add(cachedFactors[connector.id] ?? []) }
        }
        let built = FactorIndex(entries: entries,
                                byID: Dictionary(entries.enumerated().map { pair in (pair.element.factor.id, pair.offset) },
                                                 uniquingKeysWith: { first, _ in first }))
        factorIndex = built
        return built
    }

    var allFactors: [EmissionFactor] { index.entries.map(\.factor) }

    var factorCount: Int { index.entries.count }

    func factor(id: String) -> EmissionFactor? {
        let index = index
        return index.byID[id].map { index.entries[$0].factor }
    }

    func connector(id: String) -> EmissionFactorConnector? { connectors.first { $0.id == id } }

    /// Fuel quantities can cross volume → mass → energy when the factor carries fuel properties.
    nonisolated static func isCompatible(_ factor: EmissionFactor, with dimension: UnitDimension?) -> Bool {
        guard let dimension else { return true }
        guard let factorDimension = factor.unitDefinition?.dimension else { return false }
        if factorDimension == dimension { return true }
        let fuelChain: Set<UnitDimension> = [.volume, .mass, .energy]
        guard fuelChain.contains(dimension), fuelChain.contains(factorDimension) else { return false }
        let needsDensity = dimension == .volume || factorDimension == .volume
        let needsNCV = dimension == .energy || factorDimension == .energy
        return (!needsDensity || factor.densityKgPerLitre != nil) && (!needsNCV || factor.netCalorificValueMJPerKg != nil)
    }

    /// Local search over every enabled source. All words must match.
    func search(_ text: String, dimension: UnitDimension? = nil, limit: Int = 200) -> [EmissionFactor] {
        let words = text.lowercased().split(whereSeparator: { $0 == " " || $0 == "," }).map(String.init)
        let matches = index.entries.filter { entry in
            guard Self.isCompatible(entry.factor, with: dimension) else { return false }
            return words.allSatisfy { entry.searchText.contains($0) }
        }
        let first = words.first ?? ""
        return matches.sorted { lhs, rhs in
            let lhsPrefix = lhs.lowercasedName.hasPrefix(first)
            let rhsPrefix = rhs.lowercasedName.hasPrefix(first)
            if lhsPrefix != rhsPrefix { return lhsPrefix }
            return lhs.factor.name.localizedCaseInsensitiveCompare(rhs.factor.name) == .orderedAscending
        }.prefix(limit).map(\.factor)
    }

    // MARK: Secrets

    func hasSecret(for connectorID: String) -> Bool {
        !(secrets.secret(for: connectorID) ?? "").isEmpty
    }

    func setSecret(_ secret: String, for connectorID: String) {
        do {
            try secrets.setSecret(secret.trimmingCharacters(in: .whitespacesAndNewlines), for: connectorID)
            statusMessage = secret.isEmpty ? "API key removed." : "API key saved to your Keychain."
        } catch {
            statusMessage = error.localizedDescription
        }
        objectWillChange.send()
    }

    // MARK: Connector management

    @discardableResult
    func addConnector(_ preset: EmissionFactorConnector.Preset) -> EmissionFactorConnector {
        let connector = EmissionFactorConnector.make(preset)
        connectors.append(connector)
        saveConnectors()
        return connector
    }

    func updateConnector(_ connector: EmissionFactorConnector) {
        guard let index = connectors.firstIndex(where: { $0.id == connector.id }) else { return }
        connectors[index] = connector
        saveConnectors()
    }

    func setEnabled(_ enabled: Bool, connectorID: String) {
        guard let index = connectors.firstIndex(where: { $0.id == connectorID }) else { return }
        connectors[index].isEnabled = enabled
        saveConnectors()
    }

    func removeConnector(id: String) {
        guard id != EmissionFactorSeedLibrary.connectorID else { return }
        connectors.removeAll { $0.id == id }
        cachedFactors[id] = nil
        try? secrets.setSecret(nil, for: id)
        if persists { try? FileManager.default.removeItem(at: locations.cacheFile(for: id)) }
        saveConnectors()
        statusMessage = "Database removed. Inventory entries keep their own copy of any factor they used."
    }

    // MARK: Sync and search

    /// Fetches factors. Connectors that search remotely merge results into the cache;
    /// download-everything connectors replace it.
    func sync(connectorID: String, query: String = "") async {
        guard let connector = connector(id: connectorID), connector.kind != .bundled else { return }
        syncingConnectorIDs.insert(connectorID)
        defer { syncingConnectorIDs.remove(connectorID) }
        do {
            let report = try await service.fetch(connector, secret: secrets.secret(for: connectorID), query: query)
            var updated = connector
            if connector.supportsRemoteSearch {
                var merged = Dictionary((cachedFactors[connectorID] ?? []).map { ($0.id, $0) }, uniquingKeysWith: { _, new in new })
                for factor in report.factors { merged[factor.id] = factor }
                cachedFactors[connectorID] = Array(merged.values.prefix(Self.maxCachedFactorsPerConnector))
            } else {
                cachedFactors[connectorID] = Array(report.factors.prefix(Self.maxCachedFactorsPerConnector))
            }
            if persists { try? GHGJSON.write(cachedFactors[connectorID] ?? [], to: locations.cacheFile(for: connectorID)) }
            updated.lastSyncedAt = Date()
            updated.factorCount = cachedFactors[connectorID]?.count ?? 0
            updated.lastStatus = "\(report.factors.count) factor(s) fetched" + (report.skipped > 0 ? ", \(report.skipped) skipped" : "")
            updateConnector(updated)
            lastWarnings = report.warnings
            statusMessage = "\(connector.name): \(updated.lastStatus ?? "")."
        } catch {
            var updated = connector
            updated.lastStatus = error.localizedDescription
            updateConnector(updated)
            lastWarnings = []
            statusMessage = "\(connector.name): \(error.localizedDescription)"
        }
    }

    /// Runs `query` against every enabled remote-search database that is ready to use.
    func searchRemote(_ query: String) async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            statusMessage = "Type a search term to query connected databases."
            return
        }
        let targets = connectors.filter { $0.isEnabled && $0.supportsRemoteSearch && (!$0.needsSecret || hasSecret(for: $0.id)) }
        guard !targets.isEmpty else {
            statusMessage = "No connected database supports live search yet. Add Climatiq (with an API key) or a URL containing {query}."
            return
        }
        for connector in targets { await sync(connectorID: connector.id, query: trimmed) }
    }

    /// Fetches without saving, for the connector editor's preview.
    func test(_ connector: EmissionFactorConnector, secret: String?, query: String) async -> Result<ConnectorFetchReport, Error> {
        do { return .success(try await service.fetch(connector, secret: secret, query: query)) }
        catch { return .failure(error) }
    }

    func estimateWithClimatiq(_ factor: EmissionFactor, quantity: Double, unit: String) async throws -> Double {
        guard let connector = connector(id: factor.connectorID), connector.kind == .climatiq else {
            throw ConnectorError.unsupportedEstimate("Remote estimates are only available for Climatiq factors.")
        }
        return try await service.climatiqEstimate(factor: factor, quantity: quantity, unit: unit,
                                                  connector: connector, secret: secrets.secret(for: connector.id))
    }

    // MARK: Custom factors

    func saveCustomFactor(_ factor: EmissionFactor) {
        var stored = factor
        stored.connectorID = Self.customConnectorID
        if let index = customFactors.firstIndex(where: { $0.id == stored.id }) { customFactors[index] = stored }
        else { customFactors.append(stored) }
        persistCustomFactors()
    }

    func removeCustomFactor(id: String) {
        customFactors.removeAll { $0.id == id }
        persistCustomFactors()
    }

    /// Imports a local CSV using the same field mapping as web CSV connectors.
    func importCustomCSV(from url: URL, mapping: FieldMapping, delimiter: String = ",") {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            var connector = EmissionFactorConnector(id: Self.customConnectorID, name: url.deletingPathExtension().lastPathComponent,
                                                    kind: .csv, urlTemplate: "")
            connector.mapping = mapping
            connector.csvDelimiter = delimiter
            let report = try EmissionFactorConnectorService.parseCSV(data, connector: connector, retrievedAt: Date())
            for factor in report.factors { saveCustomFactor(factor) }
            lastWarnings = report.warnings
            statusMessage = "Imported \(report.factors.count) factor(s) from \(url.lastPathComponent)" + (report.skipped > 0 ? "; \(report.skipped) row(s) skipped." : ".")
        } catch {
            statusMessage = error.localizedDescription
        }
    }

    // MARK: Persistence

    private func load() {
        // `try?` flattens the optional result, so a missing or unreadable file yields [].
        var loaded: [EmissionFactorConnector] = (try? GHGJSON.read([EmissionFactorConnector].self, from: locations.connectorsFile)) ?? []
        if !loaded.contains(where: { $0.kind == .bundled }) { loaded.insert(.bundled, at: 0) }
        connectors = loaded
        for connector in loaded where connector.kind != .bundled {
            if let factors = try? GHGJSON.read([EmissionFactor].self, from: locations.cacheFile(for: connector.id)) {
                cachedFactors[connector.id] = factors
            }
        }
        customFactors = (try? GHGJSON.read([EmissionFactor].self, from: locations.customFactorsFile)) ?? []
    }

    private func saveConnectors() {
        guard persists else { return }
        do { try GHGJSON.write(connectors, to: locations.connectorsFile) }
        catch { statusMessage = "Could not save database settings: \(error.localizedDescription)" }
    }

    private func persistCustomFactors() {
        guard persists else { return }
        do { try GHGJSON.write(customFactors, to: locations.customFactorsFile) }
        catch { statusMessage = "Could not save custom factors: \(error.localizedDescription)" }
    }
}
