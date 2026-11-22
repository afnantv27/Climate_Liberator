import Foundation

// MARK: - Connector configuration
//
// A connector describes how to pull emission factors from one online source.
// Two generic kinds (CSV over HTTPS, JSON/REST with a field mapping) cover most
// databases — a published Google Sheet, a GitHub-hosted CSV, a Supabase/PostgREST
// table, Airtable, or an in-house API. Climatiq has a dedicated adapter because
// its search and estimate endpoints have a fixed schema.
// Secrets are never stored here; they live in the Keychain (SecretStore.swift).

nonisolated enum ConnectorKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case bundled, csv, json, climatiq

    var id: String { rawValue }
    var title: String {
        switch self {
        case .bundled: return "Bundled reference library"
        case .csv: return "CSV over HTTPS"
        case .json: return "JSON / REST API"
        case .climatiq: return "Climatiq API"
        }
    }
}

nonisolated enum ConnectorAuthStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, bearer, header, query

    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "No authentication"
        case .bearer: return "Bearer token"
        case .header: return "API key in header"
        case .query: return "API key in query parameter"
        }
    }
}

/// Where each emission-factor field lives in a source record. CSV fields are
/// column headers (matched case-insensitively); JSON fields are dot paths
/// (e.g. `fields.Factor`). Defaults are common column names; a field whose
/// column is absent is simply left empty.
nonisolated struct FieldMapping: Codable, Hashable, Sendable {
    /// JSON only: dot path to the array of records. Empty = the top-level array.
    var resultsPath: String = ""
    var id: String = "id"
    var name: String = "name"
    var category: String = "category"
    var region: String = "region"
    var year: String = "year"
    /// Full factor unit such as "kg/kWh" or "tCO2e per MWh".
    var unit: String = "unit"
    /// Alternative to `unit` when the source only names the activity unit.
    var activityUnit: String = ""
    var co2e: String = "co2e"
    var co2: String = "co2"
    var ch4: String = "ch4"
    var n2o: String = "n2o"
    var source: String = "source"
    /// Field holding "AR4"/"AR5"/"AR6" for the published CO2e.
    var gwpBasis: String = "gwp"
    /// Mass unit of the value fields when `unit` holds only the activity unit.
    var numeratorUnit: String = "kg"

    /// Column names expected in a hand-made factor CSV.
    static let standardCSV = FieldMapping()
}

nonisolated struct EmissionFactorConnector: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var name: String
    var kind: ConnectorKind
    /// May contain `{query}`, replaced with the percent-encoded search text.
    var urlTemplate: String
    var authStyle: ConnectorAuthStyle = .none
    /// Header or query-parameter name for `.header` / `.query` auth.
    var authName: String = ""
    var mapping = FieldMapping()
    var csvDelimiter: String = ","
    var defaultGWPBasis: GWPSet?
    var climatiqDataVersion: String = "^37"
    var climatiqRegion: String = ""
    var isEnabled: Bool = true
    var lastSyncedAt: Date?
    var lastStatus: String?
    var factorCount: Int = 0

    var supportsRemoteSearch: Bool { kind == .climatiq || urlTemplate.contains("{query}") }
    var needsSecret: Bool { kind == .climatiq || authStyle != .none }

    static let bundled = EmissionFactorConnector(
        id: EmissionFactorSeedLibrary.connectorID,
        name: "Reference library (IPCC 2006 defaults + CEA grid)",
        kind: .bundled,
        urlTemplate: ""
    )

    nonisolated enum Preset: String, CaseIterable, Identifiable, Sendable {
        case climatiq, csv, json, supabase, airtable
        var id: String { rawValue }
        var title: String {
            switch self {
            case .climatiq: return "Climatiq (API key)"
            case .csv: return "CSV file on the web (Google Sheet, GitHub, open data portal)"
            case .json: return "Custom JSON / REST API"
            case .supabase: return "Supabase / PostgREST table"
            case .airtable: return "Airtable base"
            }
        }
    }

    static func make(_ preset: Preset) -> EmissionFactorConnector {
        let id = UUID().uuidString
        switch preset {
        case .climatiq:
            return EmissionFactorConnector(id: id, name: "Climatiq", kind: .climatiq,
                                           urlTemplate: "https://api.climatiq.io/data/v1/search",
                                           authStyle: .bearer, climatiqRegion: "IN")
        case .csv:
            return EmissionFactorConnector(id: id, name: "Web CSV", kind: .csv,
                                           urlTemplate: "https://example.org/emission_factors.csv")
        case .json:
            var mapping = FieldMapping()
            mapping.resultsPath = "results"
            return EmissionFactorConnector(id: id, name: "REST API", kind: .json,
                                           urlTemplate: "https://example.org/api/factors?search={query}",
                                           authStyle: .bearer, mapping: mapping)
        case .supabase:
            return EmissionFactorConnector(id: id, name: "Supabase table", kind: .json,
                                           urlTemplate: "https://YOUR-PROJECT.supabase.co/rest/v1/emission_factors?select=*&name=ilike.*{query}*",
                                           authStyle: .header, authName: "apikey")
        case .airtable:
            var mapping = FieldMapping()
            mapping.resultsPath = "records"
            mapping.id = "id"
            mapping.name = "fields.Name"
            mapping.unit = "fields.Unit"
            mapping.co2e = "fields.CO2e"
            mapping.region = "fields.Region"
            mapping.year = "fields.Year"
            mapping.source = "fields.Source"
            return EmissionFactorConnector(id: id, name: "Airtable", kind: .json,
                                           urlTemplate: "https://api.airtable.com/v0/YOUR_BASE_ID/YOUR_TABLE",
                                           authStyle: .bearer, mapping: mapping)
        }
    }
}

nonisolated struct ConnectorFetchReport: Sendable {
    var factors: [EmissionFactor]
    var skipped: Int
    var warnings: [String]
}

nonisolated enum ConnectorError: LocalizedError, Equatable, Sendable {
    case invalidURL(String)
    case insecureURL
    case missingSecret
    case emptyQuery
    case http(status: Int, detail: String)
    case decoding(String)
    case tooLarge
    case unsupportedEstimate(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let url): return "\"\(url)\" is not a valid URL."
        case .insecureURL: return "Use an https:// address (plain http is only allowed for localhost)."
        case .missingSecret: return "This database needs an API key. Add it in the connector settings; it is stored in your Keychain."
        case .emptyQuery: return "Type a search term first — this database is searched remotely."
        case .http(let status, let detail): return "The database answered HTTP \(status). \(detail)"
        case .decoding(let detail): return "The response could not be read: \(detail)"
        case .tooLarge: return "The response is larger than 50 MB. Filter it on the server (e.g. with {query})."
        case .unsupportedEstimate(let detail): return detail
        }
    }
}

// MARK: - HTTP

nonisolated protocol HTTPDataLoading: Sendable {
    func load(_ request: URLRequest) async throws -> (Data, URLResponse)
}

nonisolated struct URLSessionHTTPLoader: HTTPDataLoading {
    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        try await URLSession.shared.data(for: request)
    }
}

// MARK: - Service

nonisolated struct EmissionFactorConnectorService: Sendable {
    let loader: HTTPDataLoading
    static let maxResponseBytes = 50 * 1_024 * 1_024

    init(loader: HTTPDataLoading = URLSessionHTTPLoader()) {
        self.loader = loader
    }

    func fetch(_ connector: EmissionFactorConnector, secret: String?, query: String) async throws -> ConnectorFetchReport {
        switch connector.kind {
        case .bundled:
            return ConnectorFetchReport(factors: EmissionFactorSeedLibrary.factors, skipped: 0, warnings: [])
        case .csv, .json:
            let request = try makeRequest(connector, secret: secret, query: query)
            let data = try await send(request)
            let now = Date()
            // Parse off the main actor: published CSVs can hold tens of thousands of rows.
            return try await Task.detached(priority: .userInitiated) {
                if connector.kind == .csv {
                    return try Self.parseCSV(data, connector: connector, retrievedAt: now)
                }
                return try Self.parseJSON(data, connector: connector, retrievedAt: now)
            }.value
        case .climatiq:
            let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { throw ConnectorError.emptyQuery }
            let request = try makeRequest(connector, secret: secret, query: trimmed)
            let data = try await send(request)
            return try Self.parseClimatiq(data, connector: connector, retrievedAt: Date())
        }
    }

    // MARK: Requests

    func makeRequest(_ connector: EmissionFactorConnector, secret: String?, query: String) throws -> URLRequest {
        let trimmedSecret = secret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if connector.needsSecret && trimmedSecret.isEmpty { throw ConnectorError.missingSecret }

        var components: URLComponents
        if connector.kind == .climatiq {
            guard let base = URLComponents(string: connector.urlTemplate) else {
                throw ConnectorError.invalidURL(connector.urlTemplate)
            }
            components = base
            var items = [
                URLQueryItem(name: "query", value: query),
                URLQueryItem(name: "data_version", value: connector.climatiqDataVersion),
                URLQueryItem(name: "results_per_page", value: "100"),
            ]
            let region = connector.climatiqRegion.trimmingCharacters(in: .whitespaces)
            if !region.isEmpty { items.append(URLQueryItem(name: "region", value: region)) }
            components.queryItems = (components.queryItems ?? []) + items
        } else {
            let encoded = query.addingPercentEncoding(withAllowedCharacters: Self.queryValueAllowed) ?? ""
            let resolved = connector.urlTemplate.replacingOccurrences(of: "{query}", with: encoded)
            guard let parsed = URLComponents(string: resolved) else { throw ConnectorError.invalidURL(resolved) }
            components = parsed
        }
        if connector.authStyle == .query, !connector.authName.isEmpty {
            components.queryItems = (components.queryItems ?? []) + [URLQueryItem(name: connector.authName, value: trimmedSecret)]
        }
        guard let url = components.url, let host = url.host, !host.isEmpty else {
            throw ConnectorError.invalidURL(connector.urlTemplate)
        }
        let scheme = url.scheme?.lowercased()
        let isLocal = host == "localhost" || host == "127.0.0.1"
        guard scheme == "https" || (scheme == "http" && isLocal) else { throw ConnectorError.insecureURL }

        var request = URLRequest(url: url, timeoutInterval: 30)
        request.setValue(connector.kind == .csv ? "text/csv, text/plain, */*" : "application/json",
                         forHTTPHeaderField: "Accept")
        switch connector.authStyle {
        case .bearer: request.setValue("Bearer \(trimmedSecret)", forHTTPHeaderField: "Authorization")
        case .header where !connector.authName.isEmpty: request.setValue(trimmedSecret, forHTTPHeaderField: connector.authName)
        default: break
        }
        return request
    }

    private static let queryValueAllowed: CharacterSet = {
        var set = CharacterSet.urlQueryAllowed
        set.remove(charactersIn: "&=+#?")
        return set
    }()

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await loader.load(request)
        guard data.count <= Self.maxResponseBytes else { throw ConnectorError.tooLarge }
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let snippet = String(decoding: data.prefix(300), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw ConnectorError.http(status: http.statusCode, detail: snippet)
        }
        return data
    }

    // MARK: Generic parsing

    static func parseCSV(_ data: Data, connector: EmissionFactorConnector, retrievedAt: Date) throws -> ConnectorFetchReport {
        guard let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            throw ConnectorError.decoding("the file is not UTF-8 text")
        }
        let rawDelimiter = connector.csvDelimiter.trimmingCharacters(in: .whitespaces).lowercased()
        let delimiter: Character = (rawDelimiter == "\\t" || rawDelimiter == "tab") ? "\t" : (connector.csvDelimiter.first ?? ",")
        let table = CSVTable(text: text, delimiter: delimiter)
        guard !table.header.isEmpty else { throw ConnectorError.decoding("no header row found") }

        var report = ConnectorFetchReport(factors: [], skipped: 0, warnings: [])
        for (index, row) in table.rows.enumerated() {
            let lookup: (String) -> String? = { key in table.value(key, in: row) }
            switch makeFactor(lookup, connector: connector, rowNumber: index + 2, retrievedAt: retrievedAt) {
            case .success(let factor): report.factors.append(factor)
            case .failure(let reason): report.skipped += 1; Self.note(reason, in: &report)
            }
        }
        if report.factors.isEmpty {
            report.warnings.insert("No factors matched the field mapping. Columns found: \(table.header.joined(separator: ", ")).", at: 0)
        }
        return report
    }

    static func parseJSON(_ data: Data, connector: EmissionFactorConnector, retrievedAt: Date) throws -> ConnectorFetchReport {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]) }
        catch { throw ConnectorError.decoding(error.localizedDescription) }
        guard let records = JSONPath.array(at: connector.mapping.resultsPath, in: root) else {
            throw ConnectorError.decoding("no array found at \"\(connector.mapping.resultsPath.isEmpty ? "(top level)" : connector.mapping.resultsPath)\"")
        }
        var report = ConnectorFetchReport(factors: [], skipped: 0, warnings: [])
        for (index, record) in records.enumerated() {
            let lookup: (String) -> String? = { key in JSONPath.string(at: key, in: record) }
            switch makeFactor(lookup, connector: connector, rowNumber: index + 1, retrievedAt: retrievedAt) {
            case .success(let factor): report.factors.append(factor)
            case .failure(let reason): report.skipped += 1; Self.note(reason, in: &report)
            }
        }
        if report.factors.isEmpty, let first = records.first as? [String: Any] {
            report.warnings.insert("No factors matched the field mapping. Keys in the first record: \(first.keys.sorted().joined(separator: ", ")).", at: 0)
        }
        return report
    }

    nonisolated struct SkipReason: Error, Sendable { let message: String }

    private static func note(_ reason: SkipReason, in report: inout ConnectorFetchReport) {
        if report.warnings.count < 10 { report.warnings.append(reason.message) }
    }

    /// Builds one factor from a record, given a key → string accessor.
    static func makeFactor(_ field: (String) -> String?,
                           connector: EmissionFactorConnector,
                           rowNumber: Int,
                           retrievedAt: Date) -> Result<EmissionFactor, SkipReason> {
        let map = connector.mapping
        func text(_ key: String) -> String? {
            guard !key.isEmpty, let raw = field(key)?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return nil }
            return raw
        }
        guard let name = text(map.name) else { return .failure(SkipReason(message: "Record \(rowNumber): no name in \"\(map.name)\".")) }

        var numeratorToKg = FactorUnitExpression.parseMassNumerator(map.numeratorUnit) ?? 1
        var activity: UnitDefinition?
        var unitText = ""
        if let raw = text(map.unit) {
            unitText = raw
            if let expression = FactorUnitExpression.parse(raw) {
                numeratorToKg = expression.numeratorToKg
                activity = expression.activityUnit
            } else {
                activity = UnitRegistry.resolve(raw)
            }
        } else if let raw = text(map.activityUnit) {
            unitText = raw
            activity = UnitRegistry.resolve(raw)
        }
        guard let activity else {
            return .failure(SkipReason(message: "Record \(rowNumber) (\(name)): unit \"\(unitText)\" not recognised."))
        }

        func number(_ key: String) -> Double? { text(key).flatMap(Self.parseNumber) }
        let co2e = number(map.co2e).map { $0 * numeratorToKg }
        var gases = GasAmounts()
        if let value = number(map.co2) { gases.co2 = value * numeratorToKg }
        if let value = number(map.ch4) { gases.ch4NonFossil = value * numeratorToKg }
        if let value = number(map.n2o) { gases.n2o = value * numeratorToKg }
        guard co2e != nil || !gases.isEmpty else {
            return .failure(SkipReason(message: "Record \(rowNumber) (\(name)): no numeric value."))
        }

        let region = text(map.region) ?? ""
        let year = text(map.year).flatMap { raw -> Int? in
            if let whole = Int(raw) { return whole }
            guard let value = Double(raw), value.isFinite, abs(value) < 100_000 else { return nil }
            return Int(value)
        }
        let externalID = text(map.id) ?? [name, activity.symbol, region, year.map(String.init) ?? ""].joined(separator: "|")
        let basis = text(map.gwpBasis).flatMap(Self.parseGWP) ?? connector.defaultGWPBasis

        return .success(EmissionFactor(
            id: "\(connector.id):\(externalID)",
            externalID: externalID,
            name: name,
            category: text(map.category) ?? "",
            region: region,
            year: year,
            activityUnit: activity.symbol,
            gases: gases.isEmpty ? nil : gases,
            co2ePerUnit: co2e,
            co2eBasis: basis,
            source: text(map.source) ?? connector.name,
            sourceURL: nil,
            connectorID: connector.id,
            notes: unitText.isEmpty ? nil : "Published unit: \(unitText)",
            retrievedAt: retrievedAt,
            uncertaintyPercent: nil,
            densityKgPerLitre: nil,
            netCalorificValueMJPerKg: nil
        ))
    }

    static func parseNumber(_ raw: String) -> Double? {
        let cleaned = raw.replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
        guard let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    static func parseGWP(_ raw: String) -> GWPSet? {
        let lower = raw.lowercased()
        if lower.contains("ar6") { return .ar6 }
        if lower.contains("ar5") { return .ar5 }
        if lower.contains("ar4") { return .ar4 }
        return nil
    }

    // MARK: Climatiq

    static func parseClimatiq(_ data: Data, connector: EmissionFactorConnector, retrievedAt: Date) throws -> ConnectorFetchReport {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data) }
        catch { throw ConnectorError.decoding(error.localizedDescription) }
        guard let results = JSONPath.array(at: "results", in: root) else {
            throw ConnectorError.decoding("Climatiq response has no results array")
        }
        var report = ConnectorFetchReport(factors: [], skipped: 0, warnings: [])
        var missingValues = 0
        for record in results {
            func text(_ path: String) -> String? {
                guard let value = JSONPath.string(at: path, in: record), !value.isEmpty else { return nil }
                return value
            }
            func number(_ path: String) -> Double? { text(path).flatMap(Self.parseNumber) }
            guard let id = text("id"), let name = text("name"), let unit = text("unit"),
                  let expression = FactorUnitExpression.parse(unit) else {
                report.skipped += 1
                continue
            }
            let scale = expression.numeratorToKg
            var gases = GasAmounts()
            gases.co2 = (number("constituent_gases.co2") ?? 0) * scale
            gases.ch4Fossil = (number("constituent_gases.ch4_fossil") ?? 0) * scale
            gases.ch4NonFossil = (number("constituent_gases.ch4_biogenic") ?? 0) * scale
            if gases.ch4Fossil == 0, gases.ch4NonFossil == 0 {
                gases.ch4NonFossil = (number("constituent_gases.ch4") ?? 0) * scale
            }
            gases.n2o = (number("constituent_gases.n2o") ?? 0) * scale
            gases.otherCO2e = (number("constituent_gases.co2e_other") ?? 0) * scale
            let total = number("factor").map { $0 * scale }
            if total == nil && gases.isEmpty { missingValues += 1 }

            var metadata: [String: String] = ["data_version": connector.climatiqDataVersion]
            for key in ["unit_type", "activity_id", "source_dataset", "sector"] {
                if let value = text(key) { metadata[key] = value }
            }
            let region = text("region_name") ?? text("region") ?? ""
            report.factors.append(EmissionFactor(
                id: "\(connector.id):\(id)",
                externalID: id,
                name: name,
                category: text("category") ?? "",
                region: region,
                year: number("year").flatMap { abs($0) < 100_000 ? Int($0) : nil },
                activityUnit: expression.activityUnit.symbol,
                gases: gases.isEmpty ? nil : gases,
                co2ePerUnit: total,
                co2eBasis: text("factor_calculation_method").flatMap(Self.parseGWP),
                source: "Climatiq — \(text("source") ?? "unknown source")",
                sourceURL: text("source_link"),
                connectorID: connector.id,
                notes: text("description"),
                retrievedAt: retrievedAt,
                uncertaintyPercent: number("uncertainty"),
                densityKgPerLitre: nil,
                netCalorificValueMJPerKg: nil,
                metadata: metadata
            ))
        }
        if missingValues > 0 {
            report.warnings.append("\(missingValues) Climatiq factor(s) came without values (plan restriction). Use \"Estimate with Climatiq\" for those.")
        }
        if report.skipped > 0 {
            report.warnings.append("\(report.skipped) result(s) skipped because their unit could not be read.")
        }
        return report
    }

    /// Uses Climatiq's estimate endpoint for factors whose value is not exposed in search.
    func climatiqEstimate(factor: EmissionFactor, quantity: Double, unit: String,
                          connector: EmissionFactorConnector, secret: String?) async throws -> Double {
        let key = secret?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !key.isEmpty else { throw ConnectorError.missingSecret }
        guard let definition = UnitRegistry.resolve(unit) else {
            throw ConnectorError.unsupportedEstimate("Unit \"\(unit)\" is not recognised.")
        }
        let parameters = try Self.climatiqParameters(unitType: factor.metadata["unit_type"] ?? "",
                                                     quantity: quantity, unit: definition)
        let body: [String: Any] = [
            "emission_factor": ["id": factor.externalID,
                                "data_version": factor.metadata["data_version"] ?? connector.climatiqDataVersion],
            "parameters": parameters,
        ]
        guard let url = URL(string: "https://api.climatiq.io/data/v1/estimate") else {
            throw ConnectorError.invalidURL("estimate")
        }
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data = try await send(request)
        guard let root = try? JSONSerialization.jsonObject(with: data),
              let co2e = JSONPath.string(at: "co2e", in: root).flatMap(Self.parseNumber) else {
            throw ConnectorError.decoding("estimate response has no co2e value")
        }
        let unitLabel = JSONPath.string(at: "co2e_unit", in: root) ?? "kg"
        let toKg = FactorUnitExpression.parseMassNumerator(unitLabel) ?? 1
        return co2e * toKg
    }

    static func climatiqParameters(unitType: String, quantity: Double, unit: UnitDefinition) throws -> [String: Any] {
        func climatiqUnit(_ definition: UnitDefinition) -> String {
            switch definition.symbol {
            case "L": return "l"
            case "mL": return "ml"
            case "US gal": return "gallon_us"
            case "UK gal": return "gallon_uk"
            default: return definition.currency?.lowercased() ?? definition.symbol
            }
        }
        let expected: [String: UnitDimension] = [
            "Energy": .energy, "Weight": .mass, "Volume": .volume, "Distance": .distance, "Money": .money, "Number": .count,
        ]
        guard let dimension = expected[unitType] else {
            throw ConnectorError.unsupportedEstimate("Climatiq unit type \"\(unitType)\" needs more than one input; estimate it in Climatiq directly.")
        }
        guard unit.dimension == dimension else {
            throw ConnectorError.unsupportedEstimate("This factor expects \(unitType.lowercased()) but \(unit.symbol) is \(unit.dimension.title.lowercased()).")
        }
        switch dimension {
        case .energy: return ["energy": quantity, "energy_unit": climatiqUnit(unit)]
        case .mass: return ["weight": quantity, "weight_unit": climatiqUnit(unit)]
        case .volume: return ["volume": quantity, "volume_unit": climatiqUnit(unit)]
        case .distance: return ["distance": quantity, "distance_unit": climatiqUnit(unit)]
        case .money: return ["money": quantity, "money_unit": climatiqUnit(unit)]
        default: return ["number": quantity]
        }
    }
}

// MARK: - CSV

/// RFC 4180 CSV reader (quoted fields, escaped quotes, CRLF/LF, BOM).
nonisolated struct CSVTable: Sendable {
    let header: [String]
    let rows: [[String]]
    private let index: [String: Int]

    init(text: String, delimiter: Character = ",") {
        let records = Self.records(in: text, delimiter: delimiter)
        let header = (records.first ?? []).map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        self.header = header
        self.rows = Array(records.dropFirst()).filter { row in row.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
        var index: [String: Int] = [:]
        for (position, name) in header.enumerated() where index[name.lowercased()] == nil {
            index[name.lowercased()] = position
        }
        self.index = index
    }

    /// Case-insensitive column lookup.
    func value(_ column: String, in row: [String]) -> String? {
        guard let position = index[column.trimmingCharacters(in: .whitespaces).lowercased()], position < row.count else { return nil }
        return row[position]
    }

    static func records(in rawText: String, delimiter: Character) -> [[String]] {
        var text = rawText
        if text.hasPrefix("\u{FEFF}") { text.removeFirst() }
        var records: [[String]] = []
        var record: [String] = []
        var field = ""
        var inQuotes = false
        let characters = Array(text)
        var position = 0
        while position < characters.count {
            let character = characters[position]
            if inQuotes {
                if character == "\"" {
                    if position + 1 < characters.count, characters[position + 1] == "\"" {
                        field.append("\"")
                        position += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else if character == "\"" {
                inQuotes = true
            } else if character == delimiter {
                record.append(field)
                field = ""
            } else if character == "\n" || character == "\r\n" || character == "\r" {
                record.append(field)
                records.append(record)
                record = []
                field = ""
            } else {
                field.append(character)
            }
            position += 1
        }
        if !field.isEmpty || !record.isEmpty {
            record.append(field)
            records.append(record)
        }
        return records
    }
}

// MARK: - JSON paths

/// Minimal dot-path access into JSONSerialization output ("records", "fields.Name", "items.0.id").
nonisolated enum JSONPath {
    static func value(at path: String, in object: Any) -> Any? {
        let trimmed = path.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty { return object }
        var current: Any? = object
        for component in trimmed.split(separator: ".").map(String.init) {
            if let dictionary = current as? [String: Any] {
                current = dictionary[component]
            } else if let array = current as? [Any], let position = Int(component), array.indices.contains(position) {
                current = array[position]
            } else {
                return nil
            }
        }
        return current
    }

    static func array(at path: String, in object: Any) -> [Any]? {
        value(at: path, in: object) as? [Any]
    }

    static func string(at path: String, in object: Any) -> String? {
        guard let value = value(at: path, in: object) else { return nil }
        switch value {
        case let string as String: return string
        case let number as NSNumber:
            // JSONSerialization booleans are NSNumbers too; they are not factor values.
            if CFGetTypeID(number) == CFBooleanGetTypeID() { return number.boolValue ? "true" : "false" }
            return number.stringValue
        case is NSNull: return nil
        default: return nil
        }
    }
}
