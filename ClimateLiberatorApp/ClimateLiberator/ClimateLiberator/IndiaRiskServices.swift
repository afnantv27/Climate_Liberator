import Foundation
import SQLite3

// SQLite uses SQLITE_TRANSIENT to copy bound text values immediately.
private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

struct IndiaDatabaseStatusSnapshot {
    let databaseConnected: Bool
    let schemaReady: Bool
    let buildingCount: Int
    let portfolioSummary: IndiaPortfolioRiskSummary
    let topRiskConcentrations: [IndiaRiskConcentration]
    let statusMessage: String
}

struct IndiaNearbyLookupSnapshot {
    let buildings: [IndiaNearbyBuilding]
    let summary: IndiaBuildingLookupSummary
    let statusMessage: String
}

struct IndiaDemoPortfolioFeedSnapshot {
    let overview: IndiaDemoPortfolioOverview?
    let comparison: IndiaDemoPortfolioComparisonSummary?
    let trust: IndiaDemoPortfolioTrustSummary?
}

struct IndiaPortfolioHierarchySummary: Codable, Hashable, Identifiable {
    let id: String
    let level: String
    let stateCode: String
    let districtName: String?
    let assetCount: Int
    let highRiskCount: Int
    let mediumRiskCount: Int
    let lowRiskCount: Int
    let averageBurnProbability: Double?
}

struct IndiaPortfolioRollupSnapshot: Codable, Hashable {
    let databasePath: String
    let databaseModifiedAt: Date?
    let generatedAt: Date
    let buildingCount: Int
    let portfolioSummary: IndiaPortfolioRiskSummary
    let topRiskConcentrations: [IndiaRiskConcentration]
    let hierarchySummaries: [IndiaPortfolioHierarchySummary]
    let statusMessage: String
}

enum IndiaRiskStoreError: LocalizedError {
    case databaseUnavailable
    case schemaIncomplete
    case writeFailed(message: String)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            return "India risk database is not available for writing."
        case .schemaIncomplete:
            return "India risk database schema is incomplete for wildfire assessments."
        case .writeFailed(let message):
            return message
        }
    }
}

protocol IndiaRiskRepository {
    func loadDatabaseStatus(at path: String) -> IndiaDatabaseStatusSnapshot
    func loadNearbyBuildings(at path: String,
                             latitude: Double,
                             longitude: Double,
                             radiusMeters: Double) -> IndiaNearbyLookupSnapshot
    func persistWildfireAssessments(databasePath: String,
                                    request: IndiaWildfireRiskLinkRequest,
                                    grid: IndiaWildfireRiskGrid) throws -> IndiaWildfireRiskLinkResult
}

protocol IndiaRiskExporting {
    func buildOEDExport(at path: String) -> (result: IndiaOEDExportResult?, errorMessage: String?)
}

protocol IndiaDemoFeedProviding {
    func loadDemoPortfolioFeeds() -> IndiaDemoPortfolioFeedSnapshot
}

protocol IndiaPortfolioRollupLoading {
    func loadPortfolioRollupSnapshot(at path: String, modifiedAt: Date?) -> IndiaPortfolioRollupSnapshot
}

protocol IndiaPortfolioRollupCaching {
    func cachedRollupSnapshot(for path: String, modifiedAt: Date?) -> IndiaPortfolioRollupSnapshot?
    func storeRollupSnapshot(_ snapshot: IndiaPortfolioRollupSnapshot)
    func removeRollupSnapshot(for path: String)
}

protocol IndiaPortfolioRollupServicing {
    func loadPortfolioRollupSnapshot(at path: String) -> IndiaPortfolioRollupSnapshot
    func invalidateCache(for path: String)
}

struct FileIndiaDemoFeedService: IndiaDemoFeedProviding {
    private let demoFeedDirectory: String

    init(demoFeedDirectory: String = IndiaRiskStore.defaultDemoFeedDirectory()) {
        self.demoFeedDirectory = demoFeedDirectory
    }

    func loadDemoPortfolioFeeds() -> IndiaDemoPortfolioFeedSnapshot {
        let availability = AppActionSupport.pathAvailability(
            path: demoFeedDirectory,
            expectation: .directory,
            emptyReason: "Portfolio demo feed directory is not configured.",
            missingReason: "Portfolio demo feed directory is not available."
        )
        guard availability.isEnabled else {
            return IndiaDemoPortfolioFeedSnapshot(overview: nil, comparison: nil, trust: nil)
        }

        let decoder = JSONDecoder()
        let root = URL(fileURLWithPath: demoFeedDirectory, isDirectory: true)
        return IndiaDemoPortfolioFeedSnapshot(
            overview: loadDemoFeed(named: "portfolio_overview.json", as: IndiaDemoPortfolioOverview.self, decoder: decoder, root: root),
            comparison: loadDemoFeed(named: "portfolio_comparison_summary.json", as: IndiaDemoPortfolioComparisonSummary.self, decoder: decoder, root: root),
            trust: loadDemoFeed(named: "portfolio_trust_summary.json", as: IndiaDemoPortfolioTrustSummary.self, decoder: decoder, root: root)
        )
    }

    private func loadDemoFeed<T: Decodable>(named fileName: String,
                                            as type: T.Type,
                                            decoder: JSONDecoder,
                                            root: URL) -> T? {
        let url = root.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return nil
        }
        return try? decoder.decode(T.self, from: data)
    }
}

struct SQLiteIndiaRiskRepository: IndiaRiskRepository {
    func loadDatabaseStatus(at path: String) -> IndiaDatabaseStatusSnapshot {
        guard let db = IndiaSQLiteSupport.openDatabase(at: path, writable: false) else {
            let availability = AppActionSupport.pathAvailability(
                path: path,
                expectation: .file,
                emptyReason: "Set the India risk database path.",
                missingReason: "India database file not found at the current path."
            )
            return IndiaDatabaseStatusSnapshot(
                databaseConnected: false,
                schemaReady: false,
                buildingCount: 0,
                portfolioSummary: .empty,
                topRiskConcentrations: [],
                statusMessage: availability.reason ?? "India database not found. Create or point to india_risk.db."
            )
        }
        defer { sqlite3_close(db) }

        guard IndiaSQLiteSupport.tableExists("building_stock", in: db),
              IndiaSQLiteSupport.tableExists("datasets", in: db) else {
            return IndiaDatabaseStatusSnapshot(
                databaseConnected: true,
                schemaReady: false,
                buildingCount: 0,
                portfolioSummary: .empty,
                topRiskConcentrations: [],
                statusMessage: "Database found, but the expected Climate Liberator tables are missing."
            )
        }

        let buildingCount = IndiaSQLiteSupport.scalarInt(db, sql: "SELECT COUNT(*) FROM building_stock;")
        let datasetCount = IndiaSQLiteSupport.scalarInt(db, sql: "SELECT COUNT(*) FROM datasets;")
        let statusMessage = buildingCount == 0
            ? "Database connected. \(datasetCount) datasets registered, but no building stock imported yet."
            : "Database connected. \(buildingCount) buildings available for site screening."

        return IndiaDatabaseStatusSnapshot(
            databaseConnected: true,
            schemaReady: true,
            buildingCount: buildingCount,
            portfolioSummary: .empty,
            topRiskConcentrations: [],
            statusMessage: statusMessage
        )
    }

    func loadNearbyBuildings(at path: String,
                             latitude: Double,
                             longitude: Double,
                             radiusMeters: Double) -> IndiaNearbyLookupSnapshot {
        guard let db = IndiaSQLiteSupport.openDatabase(at: path, writable: false) else {
            return IndiaNearbyLookupSnapshot(
                buildings: [],
                summary: IndiaBuildingLookupSummary(buildingCount: 0, totalFootprintM2: 0, totalBuiltUpM2: 0),
                statusMessage: "India database not available."
            )
        }
        defer { sqlite3_close(db) }

        let latDelta = radiusMeters / 111_320.0
        let lonScale = max(cos(latitude * .pi / 180.0), 0.1)
        let lonDelta = radiusMeters / (111_320.0 * lonScale)

        let sql = """
        SELECT
            b.building_id,
            COALESCE(b.district_name, ''),
            COALESCE(b.state_code, ''),
            COALESCE(b.latitude, 0),
            COALESCE(b.longitude, 0),
            b.area_m2,
            b.total_built_up_m2,
            b.building_floor_count,
            b.landuse,
            (
                SELECT ra.risk_band
                FROM risk_assessments ra
                WHERE ra.building_id = b.building_id
                ORDER BY ra.created_at DESC
                LIMIT 1
            ) AS risk_band,
            (
                SELECT ra.scenario_label
                FROM risk_assessments ra
                WHERE ra.building_id = b.building_id
                ORDER BY ra.created_at DESC
                LIMIT 1
            ) AS scenario_label
        FROM building_stock b
        WHERE b.latitude BETWEEN ? AND ?
          AND b.longitude BETWEEN ? AND ?
        LIMIT 250;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return IndiaNearbyLookupSnapshot(
                buildings: [],
                summary: IndiaBuildingLookupSummary(buildingCount: 0, totalFootprintM2: 0, totalBuiltUpM2: 0),
                statusMessage: "Could not query nearby buildings from the India database."
            )
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, latitude - latDelta)
        sqlite3_bind_double(statement, 2, latitude + latDelta)
        sqlite3_bind_double(statement, 3, longitude - lonDelta)
        sqlite3_bind_double(statement, 4, longitude + lonDelta)

        var results: [IndiaNearbyBuilding] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let buildingLatitude = sqlite3_column_double(statement, 3)
            let buildingLongitude = sqlite3_column_double(statement, 4)
            let distance = IndiaSQLiteSupport.haversineDistanceMeters(
                lat1: latitude,
                lon1: longitude,
                lat2: buildingLatitude,
                lon2: buildingLongitude
            )
            guard distance <= radiusMeters else { continue }

            results.append(
                IndiaNearbyBuilding(
                    id: IndiaSQLiteSupport.stringColumn(statement, index: 0),
                    districtName: IndiaSQLiteSupport.stringColumn(statement, index: 1),
                    stateCode: IndiaSQLiteSupport.stringColumn(statement, index: 2),
                    latitude: buildingLatitude,
                    longitude: buildingLongitude,
                    areaM2: IndiaSQLiteSupport.nullableDouble(statement, index: 5),
                    builtUpM2: IndiaSQLiteSupport.nullableDouble(statement, index: 6),
                    floorCount: IndiaSQLiteSupport.nullableInt(statement, index: 7),
                    landuse: IndiaSQLiteSupport.nullableString(statement, index: 8),
                    distanceMeters: distance,
                    riskBand: IndiaSQLiteSupport.nullableString(statement, index: 9),
                    scenarioLabel: IndiaSQLiteSupport.nullableString(statement, index: 10)
                )
            )
        }

        results.sort { $0.distanceMeters < $1.distanceMeters }
        let buildings = Array(results.prefix(25))
        let summary = IndiaBuildingLookupSummary(
            buildingCount: buildings.count,
            totalFootprintM2: buildings.compactMap(\.areaM2).reduce(0, +),
            totalBuiltUpM2: buildings.compactMap(\.builtUpM2).reduce(0, +)
        )
        let statusMessage = buildings.isEmpty
            ? "No imported buildings were found within \(Int(radiusMeters)) m of the selected site."
            : "Found \(buildings.count) nearby buildings within \(Int(radiusMeters)) m of the selected site."

        return IndiaNearbyLookupSnapshot(buildings: buildings, summary: summary, statusMessage: statusMessage)
    }

    func persistWildfireAssessments(databasePath: String,
                                    request: IndiaWildfireRiskLinkRequest,
                                    grid: IndiaWildfireRiskGrid) throws -> IndiaWildfireRiskLinkResult {
        guard let db = IndiaSQLiteSupport.openDatabase(at: databasePath, writable: true) else {
            throw IndiaRiskStoreError.databaseUnavailable
        }
        defer { sqlite3_close(db) }

        guard IndiaSQLiteSupport.tableExists("building_stock", in: db),
              IndiaSQLiteSupport.tableExists("risk_assessments", in: db) else {
            throw IndiaRiskStoreError.schemaIncomplete
        }

        try ensureRiskAssessmentIndexes(in: db)
        try ensureWildfireRunRecord(in: db, request: request)
        let candidates = try fetchBuildingCandidates(
            in: db,
            latitude: request.siteLatitude,
            longitude: request.siteLongitude,
            radiusMeters: request.searchRadiusMeters
        )

        guard !candidates.isEmpty else {
            return IndiaWildfireRiskLinkResult(candidateCount: 0, storedCount: 0, highRiskCount: 0, mediumRiskCount: 0, lowRiskCount: 0)
        }

        let activeCells = grid.activeCells()
        guard !activeCells.isEmpty else {
            return IndiaWildfireRiskLinkResult(candidateCount: candidates.count, storedCount: 0, highRiskCount: 0, mediumRiskCount: 0, lowRiskCount: 0)
        }

        let insertSQL = """
        INSERT OR REPLACE INTO risk_assessments (
            assessment_id,
            run_id,
            site_asset_id,
            building_id,
            hazard_type,
            scenario_label,
            burn_probability,
            expected_exposed_area_m2,
            distance_to_fire_m,
            risk_band,
            assessment_notes
        )
        VALUES (?, ?, ?, ?, 'wildfire', ?, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw IndiaRiskStoreError.writeFailed(message: "Could not prepare risk assessment insert statement.")
        }
        defer { sqlite3_finalize(statement) }

        var storedCount = 0
        var highRiskCount = 0
        var mediumRiskCount = 0
        var lowRiskCount = 0

        for candidate in candidates {
            let sampledROS = grid.sampledValue(latitude: candidate.latitude, longitude: candidate.longitude)
            let nearestDistance = nearestActiveDistance(
                latitude: candidate.latitude,
                longitude: candidate.longitude,
                activeCells: activeCells
            )
            let normalizedProbability = normalizeBurnProbability(sampledROS, maxROS: grid.maxValue)
            let riskBand = riskBand(forProbability: normalizedProbability, nearestDistanceMeters: nearestDistance)
            let exposureBase = candidate.builtUpM2 ?? candidate.areaM2 ?? 0
            let expectedExposedArea = exposureBase > 0 ? exposureBase * normalizedProbability : nil
            let provenance = IndiaWildfireRiskProvenance(
                linkageVersion: "wildfire-india-v1",
                sourceRasterPath: request.sourceRasterPath,
                outputDirectory: request.outputDirectory,
                simulatorLabel: request.simulatorLabel,
                scenarioLabel: request.scenarioLabel,
                siteLatitude: request.siteLatitude,
                siteLongitude: request.siteLongitude,
                searchRadiusMeters: request.searchRadiusMeters,
                ignitionCell: request.ignitionCell,
                gridWidth: grid.width,
                gridHeight: grid.height,
                gridMinLon: grid.minLon,
                gridMaxLon: grid.maxLon,
                gridMinLat: grid.minLat,
                gridMaxLat: grid.maxLat,
                gridMaxValue: grid.maxValue,
                sampledROS: sampledROS,
                nearestFireDistanceMeters: nearestDistance
            )

            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)

            let assessmentID = "\(request.runID)::\(candidate.buildingID)"
            IndiaSQLiteSupport.bindText(statement, index: 1, value: assessmentID)
            IndiaSQLiteSupport.bindText(statement, index: 2, value: request.runID)
            IndiaSQLiteSupport.bindNullableText(statement, index: 3, value: candidate.siteAssetID)
            IndiaSQLiteSupport.bindText(statement, index: 4, value: candidate.buildingID)
            IndiaSQLiteSupport.bindText(statement, index: 5, value: request.scenarioLabel)
            IndiaSQLiteSupport.bindDouble(statement, index: 6, value: normalizedProbability)
            IndiaSQLiteSupport.bindNullableDouble(statement, index: 7, value: expectedExposedArea)
            IndiaSQLiteSupport.bindNullableDouble(statement, index: 8, value: nearestDistance)
            IndiaSQLiteSupport.bindText(statement, index: 9, value: riskBand)
            IndiaSQLiteSupport.bindText(statement, index: 10, value: encodeProvenance(provenance))

            guard sqlite3_step(statement) == SQLITE_DONE else {
                let errorMessage = IndiaSQLiteSupport.sqliteErrorMessage(from: db) ?? "Unknown SQLite write failure."
                throw IndiaRiskStoreError.writeFailed(message: errorMessage)
            }

            storedCount += 1
            switch riskBand.lowercased() {
            case "high": highRiskCount += 1
            case "medium": mediumRiskCount += 1
            default: lowRiskCount += 1
            }
        }

        return IndiaWildfireRiskLinkResult(
            candidateCount: candidates.count,
            storedCount: storedCount,
            highRiskCount: highRiskCount,
            mediumRiskCount: mediumRiskCount,
            lowRiskCount: lowRiskCount
        )
    }

    private func currentDatabaseModifiedAt(at path: String) -> Date? {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }

    private func ensureRiskAssessmentIndexes(in db: OpaquePointer?) throws {
        try IndiaSQLiteSupport.execute(
            db,
            sql: "CREATE INDEX IF NOT EXISTS idx_risk_assessments_building_hazard_created ON risk_assessments(building_id, hazard_type, created_at DESC);"
        )
        try IndiaSQLiteSupport.execute(
            db,
            sql: "CREATE INDEX IF NOT EXISTS idx_risk_assessments_site_hazard_created ON risk_assessments(site_asset_id, hazard_type, created_at DESC);"
        )
        try IndiaSQLiteSupport.execute(
            db,
            sql: "CREATE INDEX IF NOT EXISTS idx_risk_assessments_run_id ON risk_assessments(run_id);"
        )
    }

    private func ensureWildfireRunRecord(in db: OpaquePointer?,
                                         request: IndiaWildfireRiskLinkRequest) throws {
        let insertSQL = """
        INSERT OR IGNORE INTO wildfire_runs (
            run_id,
            engine_name,
            generated_at,
            scenario_label,
            run_artifact_path,
            weather_input_format,
            ignition_input_mode,
            provenance_json
        )
        VALUES (?, ?, CURRENT_TIMESTAMP, ?, ?, ?, ?, ?);
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, insertSQL, -1, &statement, nil) == SQLITE_OK else {
            throw IndiaRiskStoreError.writeFailed(message: "Could not prepare wildfire run insert statement.")
        }
        defer { sqlite3_finalize(statement) }

        IndiaSQLiteSupport.bindText(statement, index: 1, value: request.runID)
        IndiaSQLiteSupport.bindText(statement, index: 2, value: "Climate Liberator")
        IndiaSQLiteSupport.bindText(statement, index: 3, value: request.scenarioLabel)
        IndiaSQLiteSupport.bindText(statement, index: 4, value: request.outputDirectory)
        IndiaSQLiteSupport.bindText(statement, index: 5, value: "csv")
        IndiaSQLiteSupport.bindText(statement, index: 6, value: request.ignitionCell == nil ? "implicit_grid" : "cell_selection")

        let provenancePayload = [
            "source_raster_path": request.sourceRasterPath,
            "simulator_label": request.simulatorLabel,
            "site_latitude": String(request.siteLatitude),
            "site_longitude": String(request.siteLongitude)
        ]
        let provenanceJSON = "{"
            + provenancePayload.map { key, value in "\"\(key)\":\"\(value.replacingOccurrences(of: "\"", with: "\\\""))\"" }
                .sorted()
                .joined(separator: ",")
            + "}"
        IndiaSQLiteSupport.bindText(statement, index: 7, value: provenanceJSON)

        guard sqlite3_step(statement) == SQLITE_DONE else {
            let errorMessage = IndiaSQLiteSupport.sqliteErrorMessage(from: db) ?? "Unknown SQLite write failure."
            throw IndiaRiskStoreError.writeFailed(message: errorMessage)
        }
    }

    private func fetchBuildingCandidates(in db: OpaquePointer?,
                                         latitude: Double,
                                         longitude: Double,
                                         radiusMeters: Double) throws -> [IndiaWildfireBuildingCandidate] {
        let latDelta = radiusMeters / 111_320.0
        let lonScale = max(cos(latitude * .pi / 180.0), 0.1)
        let lonDelta = radiusMeters / (111_320.0 * lonScale)

        let includeSiteLinks = IndiaSQLiteSupport.tableExists("site_building_links", in: db)
        let sql: String = includeSiteLinks ? """
            SELECT
                b.building_id,
                (
                    SELECT sbl.site_asset_id
                    FROM site_building_links sbl
                    WHERE sbl.building_id = b.building_id
                    ORDER BY COALESCE(sbl.distance_m, 999999999) ASC, sbl.created_at DESC
                    LIMIT 1
                ) AS site_asset_id,
                COALESCE(b.latitude, 0),
                COALESCE(b.longitude, 0),
                b.area_m2,
                b.total_built_up_m2
            FROM building_stock b
            WHERE b.latitude BETWEEN ? AND ?
              AND b.longitude BETWEEN ? AND ?
            LIMIT 250;
            """ : """
            SELECT
                b.building_id,
                NULL AS site_asset_id,
                COALESCE(b.latitude, 0),
                COALESCE(b.longitude, 0),
                b.area_m2,
                b.total_built_up_m2
            FROM building_stock b
            WHERE b.latitude BETWEEN ? AND ?
              AND b.longitude BETWEEN ? AND ?
            LIMIT 250;
            """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw IndiaRiskStoreError.writeFailed(message: "Could not query building candidates for wildfire linkage.")
        }
        defer { sqlite3_finalize(statement) }

        sqlite3_bind_double(statement, 1, latitude - latDelta)
        sqlite3_bind_double(statement, 2, latitude + latDelta)
        sqlite3_bind_double(statement, 3, longitude - lonDelta)
        sqlite3_bind_double(statement, 4, longitude + lonDelta)

        var candidates: [IndiaWildfireBuildingCandidate] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let candidate = IndiaWildfireBuildingCandidate(
                buildingID: IndiaSQLiteSupport.stringColumn(statement, index: 0),
                siteAssetID: IndiaSQLiteSupport.nullableString(statement, index: 1),
                latitude: sqlite3_column_double(statement, 2),
                longitude: sqlite3_column_double(statement, 3),
                areaM2: IndiaSQLiteSupport.nullableDouble(statement, index: 4),
                builtUpM2: IndiaSQLiteSupport.nullableDouble(statement, index: 5)
            )

            let distance = IndiaSQLiteSupport.haversineDistanceMeters(
                lat1: latitude,
                lon1: longitude,
                lat2: candidate.latitude,
                lon2: candidate.longitude
            )
            guard distance <= radiusMeters else { continue }
            candidates.append(candidate)
        }

        candidates.sort {
            IndiaSQLiteSupport.haversineDistanceMeters(lat1: latitude, lon1: longitude, lat2: $0.latitude, lon2: $0.longitude)
                < IndiaSQLiteSupport.haversineDistanceMeters(lat1: latitude, lon1: longitude, lat2: $1.latitude, lon2: $1.longitude)
        }
        return candidates
    }

    private func normalizeBurnProbability(_ sampledROS: Double?, maxROS: Double) -> Double {
        guard let sampledROS, sampledROS > 0 else { return 0 }
        let denominator = max(maxROS, 0.0001)
        return min(1.0, sampledROS / denominator)
    }

    private func riskBand(forProbability probability: Double, nearestDistanceMeters: Double?) -> String {
        if probability >= 0.66 || nearestDistanceMeters == 0 { return "High" }
        if probability >= 0.33 || (nearestDistanceMeters ?? .greatestFiniteMagnitude) <= 250 { return "Medium" }
        return "Low"
    }

    private func nearestActiveDistance(latitude: Double,
                                       longitude: Double,
                                       activeCells: [IndiaWildfireActiveCell]) -> Double? {
        guard !activeCells.isEmpty else { return nil }
        var bestDistance: Double?
        for cell in activeCells {
            let distance = IndiaSQLiteSupport.haversineDistanceMeters(lat1: latitude,
                                                                      lon1: longitude,
                                                                      lat2: cell.latitude,
                                                                      lon2: cell.longitude)
            if let currentBest = bestDistance {
                if distance < currentBest {
                    bestDistance = distance
                }
            } else {
                bestDistance = distance
            }
        }
        return bestDistance
    }

    private func encodeProvenance(_ provenance: IndiaWildfireRiskProvenance) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(provenance),
              let text = String(data: data, encoding: .utf8) else {
            return "{\"linkageVersion\":\"wildfire-india-v1\"}"
        }
        return text
    }
}

final class FileIndiaPortfolioRollupCacheStore: IndiaPortfolioRollupCaching {
    private struct CacheEnvelope: Codable {
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable {
        let databaseModifiedAt: Date?
        let snapshot: IndiaPortfolioRollupSnapshot
    }

    private let queue = DispatchQueue(label: "com.climateliberator.india-rollup-cache", qos: .utility)
    private let cacheURL: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder
    private var inMemoryEntries: [String: CacheEntry] = [:]
    private var isLoaded = false

    init(cacheURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/ClimateLiberator/_climateliberator/india/rollup-cache.json", isDirectory: false)) {
        self.cacheURL = cacheURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func cachedRollupSnapshot(for path: String, modifiedAt: Date?) -> IndiaPortfolioRollupSnapshot? {
        queue.sync {
            loadIfNeeded()
            guard let entry = inMemoryEntries[path], entry.databaseModifiedAt == modifiedAt else {
                return nil
            }
            return entry.snapshot
        }
    }

    func storeRollupSnapshot(_ snapshot: IndiaPortfolioRollupSnapshot) {
        queue.sync {
            loadIfNeeded()
            inMemoryEntries[snapshot.databasePath] = CacheEntry(
                databaseModifiedAt: snapshot.databaseModifiedAt,
                snapshot: snapshot
            )
            persist()
        }
    }

    func removeRollupSnapshot(for path: String) {
        queue.sync {
            loadIfNeeded()
            inMemoryEntries.removeValue(forKey: path)
            persist()
        }
    }

    private func loadIfNeeded() {
        guard !isLoaded else { return }
        isLoaded = true
        guard let data = try? Data(contentsOf: cacheURL),
              let envelope = try? decoder.decode(CacheEnvelope.self, from: data) else {
            return
        }
        inMemoryEntries = envelope.entries
    }

    private func persist() {
        do {
            let directory = cacheURL.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let envelope = CacheEnvelope(entries: inMemoryEntries)
            let data = try encoder.encode(envelope)
            try data.write(to: cacheURL, options: .atomic)
        } catch {
            // Cache failures should never block the app.
        }
    }
}

struct SQLiteIndiaPortfolioRollupSnapshotLoader: IndiaPortfolioRollupLoading {
    func loadPortfolioRollupSnapshot(at path: String, modifiedAt: Date?) -> IndiaPortfolioRollupSnapshot {
        guard let db = IndiaSQLiteSupport.openDatabase(at: path, writable: false) else {
            return IndiaPortfolioRollupSnapshot(
                databasePath: path,
                databaseModifiedAt: modifiedAt,
                generatedAt: Date(),
                buildingCount: 0,
                portfolioSummary: .empty,
                topRiskConcentrations: [],
                hierarchySummaries: [],
                statusMessage: "India portfolio database is not available."
            )
        }
        defer { sqlite3_close(db) }

        guard IndiaSQLiteSupport.tableExists("building_stock", in: db),
              IndiaSQLiteSupport.tableExists("datasets", in: db) else {
            return IndiaPortfolioRollupSnapshot(
                databasePath: path,
                databaseModifiedAt: modifiedAt,
                generatedAt: Date(),
                buildingCount: 0,
                portfolioSummary: .empty,
                topRiskConcentrations: [],
                hierarchySummaries: [],
                statusMessage: "Database found, but the expected Climate Liberator India tables are missing."
            )
        }

        let buildingCount = IndiaSQLiteSupport.scalarInt(db, sql: "SELECT COUNT(*) FROM building_stock;")
        let portfolioSummary = loadPortfolioSummary(from: db)
        let topRiskConcentrations = loadTopRiskConcentrations(from: db)
        let hierarchySummaries = loadHierarchySummaries(from: db)

        let statusMessage: String
        if buildingCount == 0 {
            statusMessage = "India portfolio database is connected, but no building stock has been imported yet."
        } else if portfolioSummary.assessedAssets == 0 {
            statusMessage = "India portfolio database is connected. \(buildingCount) buildings are ready for hierarchy-aware summary caching."
        } else {
            statusMessage = "India portfolio database is connected. \(portfolioSummary.assessedAssets) assessed assets are now served through cached rollups."
        }

        return IndiaPortfolioRollupSnapshot(
            databasePath: path,
            databaseModifiedAt: modifiedAt,
            generatedAt: Date(),
            buildingCount: buildingCount,
            portfolioSummary: portfolioSummary,
            topRiskConcentrations: topRiskConcentrations,
            hierarchySummaries: hierarchySummaries,
            statusMessage: statusMessage
        )
    }

    private func loadPortfolioSummary(from db: OpaquePointer?) -> IndiaPortfolioRiskSummary {
        let sql = """
        SELECT
            COUNT(*) AS assessed_assets,
            SUM(CASE WHEN LOWER(COALESCE(risk_band, '')) = 'high' THEN 1 ELSE 0 END) AS high_assets,
            SUM(CASE WHEN LOWER(COALESCE(risk_band, '')) = 'medium' THEN 1 ELSE 0 END) AS medium_assets,
            SUM(CASE WHEN LOWER(COALESCE(risk_band, '')) = 'low' THEN 1 ELSE 0 END) AS low_assets,
            COUNT(DISTINCT NULLIF(TRIM(COALESCE(scenario_label, '')), '')) AS unique_scenarios,
            MAX(created_at) AS latest_assessment_at
        FROM risk_assessments
        WHERE hazard_type = 'wildfire';
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return .empty
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return .empty }

        return IndiaPortfolioRiskSummary(
            assessedAssets: Int(sqlite3_column_int(statement, 0)),
            highRiskAssets: Int(sqlite3_column_int(statement, 1)),
            mediumRiskAssets: Int(sqlite3_column_int(statement, 2)),
            lowRiskAssets: Int(sqlite3_column_int(statement, 3)),
            uniqueScenarios: Int(sqlite3_column_int(statement, 4)),
            latestAssessmentAt: IndiaSQLiteSupport.nullableString(statement, index: 5)
        )
    }

    private func loadTopRiskConcentrations(from db: OpaquePointer?) -> [IndiaRiskConcentration] {
        let sql = """
        SELECT
            COALESCE(NULLIF(TRIM(COALESCE(b.state_code, '')), ''), 'Unknown') AS state_code,
            COUNT(*) AS asset_count,
            SUM(CASE WHEN LOWER(COALESCE(ra.risk_band, '')) = 'high' THEN 1 ELSE 0 END) AS high_assets,
            AVG(ra.burn_probability) AS avg_burn_probability
        FROM risk_assessments ra
        LEFT JOIN building_stock b ON b.building_id = ra.building_id
        WHERE ra.hazard_type = 'wildfire'
        GROUP BY state_code
        ORDER BY high_assets DESC, asset_count DESC, avg_burn_probability DESC, state_code ASC
        LIMIT 4;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var results: [IndiaRiskConcentration] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let stateCode = IndiaSQLiteSupport.stringColumn(statement, index: 0)
            results.append(
                IndiaRiskConcentration(
                    id: stateCode,
                    stateCode: stateCode,
                    assetCount: Int(sqlite3_column_int(statement, 1)),
                    highRiskCount: Int(sqlite3_column_int(statement, 2)),
                    averageBurnProbability: IndiaSQLiteSupport.nullableDouble(statement, index: 3)
                )
            )
        }
        return results
    }

    private func loadHierarchySummaries(from db: OpaquePointer?) -> [IndiaPortfolioHierarchySummary] {
        let sql = """
        SELECT
            'state' AS level,
            COALESCE(NULLIF(TRIM(COALESCE(b.state_code, '')), ''), 'Unknown') AS state_code,
            NULL AS district_name,
            COUNT(*) AS asset_count,
            SUM(CASE WHEN LOWER(COALESCE(ra.risk_band, '')) = 'high' THEN 1 ELSE 0 END) AS high_assets,
            SUM(CASE WHEN LOWER(COALESCE(ra.risk_band, '')) = 'medium' THEN 1 ELSE 0 END) AS medium_assets,
            SUM(CASE WHEN LOWER(COALESCE(ra.risk_band, '')) = 'low' THEN 1 ELSE 0 END) AS low_assets,
            AVG(ra.burn_probability) AS avg_burn_probability
        FROM risk_assessments ra
        LEFT JOIN building_stock b ON b.building_id = ra.building_id
        WHERE ra.hazard_type = 'wildfire'
        GROUP BY state_code
        UNION ALL
        SELECT
            'district' AS level,
            COALESCE(NULLIF(TRIM(COALESCE(b.state_code, '')), ''), 'Unknown') AS state_code,
            COALESCE(NULLIF(TRIM(COALESCE(b.district_name, '')), ''), 'Unknown') AS district_name,
            COUNT(*) AS asset_count,
            SUM(CASE WHEN LOWER(COALESCE(ra.risk_band, '')) = 'high' THEN 1 ELSE 0 END) AS high_assets,
            SUM(CASE WHEN LOWER(COALESCE(ra.risk_band, '')) = 'medium' THEN 1 ELSE 0 END) AS medium_assets,
            SUM(CASE WHEN LOWER(COALESCE(ra.risk_band, '')) = 'low' THEN 1 ELSE 0 END) AS low_assets,
            AVG(ra.burn_probability) AS avg_burn_probability
        FROM risk_assessments ra
        LEFT JOIN building_stock b ON b.building_id = ra.building_id
        WHERE ra.hazard_type = 'wildfire'
        GROUP BY state_code, district_name
        ORDER BY high_assets DESC, asset_count DESC, state_code ASC, district_name ASC
        LIMIT 12;
        """

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        var results: [IndiaPortfolioHierarchySummary] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let level = IndiaSQLiteSupport.stringColumn(statement, index: 0)
            let stateCode = IndiaSQLiteSupport.stringColumn(statement, index: 1)
            let districtName = IndiaSQLiteSupport.nullableString(statement, index: 2)
            let assetCount = Int(sqlite3_column_int(statement, 3))
            let highRiskCount = Int(sqlite3_column_int(statement, 4))
            let mediumRiskCount = Int(sqlite3_column_int(statement, 5))
            let lowRiskCount = Int(sqlite3_column_int(statement, 6))
            let averageBurnProbability = IndiaSQLiteSupport.nullableDouble(statement, index: 7)
            let id = "\(level):\(stateCode):\(districtName ?? "*")"

            results.append(
                IndiaPortfolioHierarchySummary(
                    id: id,
                    level: level,
                    stateCode: stateCode,
                    districtName: districtName,
                    assetCount: assetCount,
                    highRiskCount: highRiskCount,
                    mediumRiskCount: mediumRiskCount,
                    lowRiskCount: lowRiskCount,
                    averageBurnProbability: averageBurnProbability
                )
            )
        }
        return results
    }
}

final class IndiaPortfolioRollupService: IndiaPortfolioRollupServicing {
    private let loader: IndiaPortfolioRollupLoading
    private let cacheStore: IndiaPortfolioRollupCaching

    init(loader: IndiaPortfolioRollupLoading = SQLiteIndiaPortfolioRollupSnapshotLoader(),
         cacheStore: IndiaPortfolioRollupCaching = FileIndiaPortfolioRollupCacheStore()) {
        self.loader = loader
        self.cacheStore = cacheStore
    }

    func loadPortfolioRollupSnapshot(at path: String) -> IndiaPortfolioRollupSnapshot {
        let modifiedAt = currentDatabaseModifiedAt(at: path)
        if let cached = cacheStore.cachedRollupSnapshot(for: path, modifiedAt: modifiedAt) {
            return cached
        }
        let snapshot = loader.loadPortfolioRollupSnapshot(at: path, modifiedAt: modifiedAt)
        cacheStore.storeRollupSnapshot(snapshot)
        return snapshot
    }

    func invalidateCache(for path: String) {
        cacheStore.removeRollupSnapshot(for: path)
    }

    private func currentDatabaseModifiedAt(at path: String) -> Date? {
        guard let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.contentModificationDateKey]) else {
            return nil
        }
        return values.contentModificationDate
    }
}

struct SQLiteIndiaOEDExportService: IndiaRiskExporting {
    func buildOEDExport(at path: String) -> (result: IndiaOEDExportResult?, errorMessage: String?) {
        guard let db = IndiaSQLiteSupport.openDatabase(at: path, writable: false) else {
            return (nil, "India database not available for OED export.")
        }
        defer { sqlite3_close(db) }

        guard IndiaSQLiteSupport.tableExists("building_stock", in: db) else {
            return (nil, "Building stock table is missing from the India database.")
        }

        let useSiteAssets = IndiaSQLiteSupport.tableExists("site_assets", in: db)
            && IndiaSQLiteSupport.scalarInt(db, sql: "SELECT COUNT(*) FROM site_assets;") > 0
        let query = useSiteAssets ? siteAssetOEDQuery : buildingStockOEDQuery

        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, query, -1, &statement, nil) == SQLITE_OK else {
            return (nil, "Could not prepare the OED export query.")
        }
        defer { sqlite3_finalize(statement) }

        var rows: [String] = [
            "LocID,PerilID,CoverageTypeID,AreaPerilID,VulnerabilityID,TIV_Building,TIV_Contents,Latitude,Longitude,OccupancyCode,ConstructionCode,AssetName,StateCode,DistrictName,ScenarioLabel,RiskBand,CurrencyCode,ValuationBasis"
        ]
        var rowCount = 0

        while sqlite3_step(statement) == SQLITE_ROW {
            let locationID = IndiaSQLiteSupport.stringColumn(statement, index: 0)
            let assetName = csvSafe(IndiaSQLiteSupport.nullableString(statement, index: 1))
            let stateCode = IndiaSQLiteSupport.nullableString(statement, index: 2) ?? "IN-UNK"
            let districtName = IndiaSQLiteSupport.nullableString(statement, index: 3) ?? "Unknown"
            let latitude = IndiaSQLiteSupport.nullableDouble(statement, index: 4) ?? 0
            let longitude = IndiaSQLiteSupport.nullableDouble(statement, index: 5) ?? 0
            let areaM2 = IndiaSQLiteSupport.nullableDouble(statement, index: 6) ?? IndiaSQLiteSupport.nullableDouble(statement, index: 7) ?? 0
            let occupancyRaw = IndiaSQLiteSupport.nullableString(statement, index: 8) ?? IndiaSQLiteSupport.nullableString(statement, index: 9) ?? ""
            let scenarioLabel = csvSafe(IndiaSQLiteSupport.nullableString(statement, index: 10))
            let riskBand = csvSafe(IndiaSQLiteSupport.nullableString(statement, index: 11))

            let occupancyCode = oedOccupancyCode(from: occupancyRaw, assetName: assetName)
            let constructionCode = oedConstructionCode(from: occupancyRaw, assetName: assetName)
            let vulnerabilityID = "WF-\(occupancyCode)-\(constructionCode)"
            let districtToken = districtName.replacingOccurrences(of: " ", with: "_").uppercased()
            let areaPerilID = "IN-\(stateCode)-\(districtToken)"
            let tivBuilding = max(areaM2, 0) * 35_000
            let tivContents = tivBuilding * 0.20

            rows.append([
                csvSafe(locationID),
                "WF",
                "1",
                csvSafe(areaPerilID),
                csvSafe(vulnerabilityID),
                decimalString(tivBuilding),
                decimalString(tivContents),
                decimalString(latitude),
                decimalString(longitude),
                csvSafe(occupancyCode),
                csvSafe(constructionCode),
                assetName,
                csvSafe(stateCode),
                csvSafe(districtName),
                scenarioLabel,
                riskBand,
                "INR",
                csvSafe("Area proxy at INR 35,000/m2 building and 20% contents")
            ].joined(separator: ","))
            rowCount += 1
        }

        guard rowCount > 0 else {
            return (nil, "No rows were available for OED-style export.")
        }

        let exportDirectory = NSString(string: "/Users/afnan/Desktop/Build/india-risk-data/data/exports").expandingTildeInPath
        do {
            try FileManager.default.createDirectory(atPath: exportDirectory, withIntermediateDirectories: true)
            let timestamp = ISO8601DateFormatter.compactTimestamp.string(from: Date())
            let fileName = useSiteAssets ? "india_portfolio_sites_oed_\(timestamp).csv" : "india_building_stock_oed_\(timestamp).csv"
            let filePath = (exportDirectory as NSString).appendingPathComponent(fileName)
            try rows.joined(separator: "\n").write(toFile: filePath, atomically: true, encoding: .utf8)
            return (IndiaOEDExportResult(filePath: filePath, rowCount: rowCount, sourceLabel: useSiteAssets ? "site assets" : "building stock"), nil)
        } catch {
            return (nil, "Could not write the OED-style export file.")
        }
    }

    private var siteAssetOEDQuery: String {
        """
        SELECT
            sa.site_asset_id,
            sa.site_name,
            sa.state_code,
            sa.district_name,
            sa.latitude,
            sa.longitude,
            sa.building_area_m2,
            sa.plot_area_m2,
            sa.occupancy_type,
            NULL AS landuse,
            (
                SELECT ra.scenario_label
                FROM risk_assessments ra
                WHERE ra.site_asset_id = sa.site_asset_id
                ORDER BY ra.created_at DESC
                LIMIT 1
            ) AS scenario_label,
            (
                SELECT ra.risk_band
                FROM risk_assessments ra
                WHERE ra.site_asset_id = sa.site_asset_id
                ORDER BY ra.created_at DESC
                LIMIT 1
            ) AS risk_band
        FROM site_assets sa
        ORDER BY COALESCE(sa.state_code, ''), COALESCE(sa.district_name, ''), sa.site_asset_id;
        """
    }

    private var buildingStockOEDQuery: String {
        """
        SELECT
            b.building_id,
            b.building_id AS asset_name,
            b.state_code,
            b.district_name,
            b.latitude,
            b.longitude,
            b.total_built_up_m2,
            b.area_m2,
            NULL AS occupancy_type,
            b.landuse,
            (
                SELECT ra.scenario_label
                FROM risk_assessments ra
                WHERE ra.building_id = b.building_id
                ORDER BY ra.created_at DESC
                LIMIT 1
            ) AS scenario_label,
            (
                SELECT ra.risk_band
                FROM risk_assessments ra
                WHERE ra.building_id = b.building_id
                ORDER BY ra.created_at DESC
                LIMIT 1
            ) AS risk_band
        FROM building_stock b
        ORDER BY COALESCE(b.state_code, ''), COALESCE(b.district_name, ''), b.building_id;
        """
    }

    private func oedOccupancyCode(from rawValue: String, assetName: String) -> String {
        let normalized = "\(rawValue) \(assetName)".lowercased()
        if normalized.contains("substation") { return "UTILITY_SUBSTATION" }
        if normalized.contains("distribution") || normalized.contains("line yard") { return "UTILITY_DISTRIBUTION" }
        if normalized.contains("ops") || normalized.contains("control") { return "UTILITY_OPERATIONS" }
        if normalized.contains("industrial") { return "INDUSTRIAL_GENERIC" }
        return "GENERIC_PORTFOLIO"
    }

    private func oedConstructionCode(from rawValue: String, assetName: String) -> String {
        let normalized = "\(rawValue) \(assetName)".lowercased()
        if normalized.contains("yard") || normalized.contains("substation") { return "UTILITY_COMPOSITE" }
        if normalized.contains("warehouse") || normalized.contains("industrial") { return "INDUSTRIAL_MASONRY" }
        return "GENERIC_MASONRY"
    }

    private func csvSafe(_ value: String?) -> String {
        let text = value ?? ""
        let escaped = text.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func decimalString(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}

private struct IndiaWildfireBuildingCandidate {
    let buildingID: String
    let siteAssetID: String?
    let latitude: Double
    let longitude: Double
    let areaM2: Double?
    let builtUpM2: Double?
}

private struct IndiaWildfireRiskProvenance: Codable {
    let linkageVersion: String
    let sourceRasterPath: String
    let outputDirectory: String
    let simulatorLabel: String
    let scenarioLabel: String
    let siteLatitude: Double
    let siteLongitude: Double
    let searchRadiusMeters: Double
    let ignitionCell: Int?
    let gridWidth: Int
    let gridHeight: Int
    let gridMinLon: Double
    let gridMaxLon: Double
    let gridMinLat: Double
    let gridMaxLat: Double
    let gridMaxValue: Double
    let sampledROS: Double?
    let nearestFireDistanceMeters: Double?
}

private enum IndiaSQLiteSupport {
    static func openDatabase(at path: String, writable: Bool) -> OpaquePointer? {
        let availability = AppActionSupport.pathAvailability(
            path: path,
            expectation: .file,
            emptyReason: "Set the India risk database path.",
            missingReason: "India database file not found at the current path."
        )
        guard availability.isEnabled else { return nil }

        var db: OpaquePointer?
        let resolvedPath = NSString(string: path).expandingTildeInPath
        let flags = writable ? SQLITE_OPEN_READWRITE : SQLITE_OPEN_READONLY
        guard sqlite3_open_v2(resolvedPath, &db, flags, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            return nil
        }
        return db
    }

    static func tableExists(_ tableName: String, in db: OpaquePointer?) -> Bool {
        let sql = "SELECT name FROM sqlite_master WHERE type='table' AND name=? LIMIT 1;"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, (tableName as NSString).utf8String, -1, nil)
        return sqlite3_step(statement) == SQLITE_ROW
    }

    static func scalarInt(_ db: OpaquePointer?, sql: String) -> Int {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            return 0
        }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW else { return 0 }
        return Int(sqlite3_column_int(statement, 0))
    }

    static func stringColumn(_ statement: OpaquePointer?, index: Int32) -> String {
        guard let value = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: value)
    }

    static func nullableString(_ statement: OpaquePointer?, index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return stringColumn(statement, index: index)
    }

    static func nullableDouble(_ statement: OpaquePointer?, index: Int32) -> Double? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return sqlite3_column_double(statement, index)
    }

    static func nullableInt(_ statement: OpaquePointer?, index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    static func execute(_ db: OpaquePointer?, sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw IndiaRiskStoreError.writeFailed(message: sqliteErrorMessage(from: db) ?? "SQLite execution failed.")
        }
    }

    static func bindText(_ statement: OpaquePointer?, index: Int32, value: String) {
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, sqliteTransient)
    }

    static func bindNullableText(_ statement: OpaquePointer?, index: Int32, value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, (value as NSString).utf8String, -1, sqliteTransient)
    }

    static func bindDouble(_ statement: OpaquePointer?, index: Int32, value: Double) {
        sqlite3_bind_double(statement, index, value)
    }

    static func bindNullableDouble(_ statement: OpaquePointer?, index: Int32, value: Double?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_double(statement, index, value)
    }

    static func sqliteErrorMessage(from db: OpaquePointer?) -> String? {
        guard let message = sqlite3_errmsg(db) else { return nil }
        return String(cString: message)
    }

    static func haversineDistanceMeters(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let earthRadius = 6_371_000.0
        let dLat = (lat2 - lat1) * .pi / 180.0
        let dLon = (lon2 - lon1) * .pi / 180.0
        let a = sin(dLat / 2) * sin(dLat / 2) +
            cos(lat1 * .pi / 180.0) * cos(lat2 * .pi / 180.0) *
            sin(dLon / 2) * sin(dLon / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadius * c
    }
}

private extension ISO8601DateFormatter {
    static let compactTimestamp: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter
    }()
}
