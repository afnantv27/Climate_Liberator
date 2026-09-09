import XCTest
import SQLite3
@testable import ClimateLiberator

@MainActor
final class IndiaPortabilityTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func starter() throws -> URL {
        try XCTUnwrap(Bundle.main.url(forResource: "StarterData", withExtension: "bundle"))
    }

    private func open(_ url: URL) throws -> OpaquePointer {
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(url.path, &db), SQLITE_OK)
        return try XCTUnwrap(db)
    }

    private func execute(_ db: OpaquePointer, _ sql: String) throws {
        let code = sqlite3_exec(db, sql, nil, nil, nil)
        guard code == SQLITE_OK else {
            throw NSError(domain: "SQLiteTest", code: Int(code), userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errmsg(db))])
        }
    }

    func testFreshInstallHasWritableIndiaSeedAndPreservesEdits() throws {
        let locations = AppDataLocations(root: try root())
        try AppDataBootstrap.prepare(locations: locations, starterSource: starter())
        let status = SQLiteIndiaRiskRepository().loadDatabaseStatus(at: locations.selectedIndiaDatabase.path)
        XCTAssertTrue(status.schemaReady)
        XCTAssertEqual(status.buildingCount, 12)
        XCTAssertTrue(status.statusMessage.contains("Synthetic"))
        let marker = locations.studyDirectory.appendingPathComponent("user-edits.txt")
        try "retain".write(to: marker, atomically: true, encoding: .utf8)
        try AppDataBootstrap.prepare(locations: locations, starterSource: starter())
        XCTAssertEqual(try String(contentsOf: marker, encoding: .utf8), "retain")
        XCTAssertTrue(FileManager.default.isWritableFile(atPath: locations.studyDirectory.path))
    }

    func testImportIncludesCommittedWALAndRejectsInvalidReplacement() throws {
        let locations = AppDataLocations(root: try root())
        try AppDataBootstrap.prepare(locations: locations, starterSource: starter())
        let source = locations.root.appendingPathComponent("source.db")
        try FileManager.default.copyItem(at: locations.selectedIndiaDatabase, to: source)
        let db = try open(source)
        defer { sqlite3_close(db) }
        try execute(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0; DELETE FROM building_stock WHERE building_id='SYNTHETIC-IN-001';")
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path + "-wal"))
        try AppDataBootstrap.installIndiaDatabase(from: source, locations: locations)
        XCTAssertEqual(SQLiteIndiaRiskRepository().loadDatabaseStatus(at: locations.selectedIndiaDatabase.path).buildingCount, 11)
        let invalid = locations.root.appendingPathComponent("bad.db")
        try "not a database".write(to: invalid, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try AppDataBootstrap.installIndiaDatabase(from: invalid, locations: locations))
        XCTAssertEqual(SQLiteIndiaRiskRepository().loadDatabaseStatus(at: locations.selectedIndiaDatabase.path).buildingCount, 11)
        try execute(db, "DELETE FROM building_stock WHERE building_id='SYNTHETIC-IN-002';")
        try AppDataBootstrap.installIndiaDatabase(from: source, locations: locations)
        XCTAssertEqual(SQLiteIndiaRiskRepository().loadDatabaseStatus(at: locations.selectedIndiaDatabase.path).buildingCount, 10)
        let saved = try FileManager.default.contentsOfDirectory(atPath: locations.installedIndiaDatabase.deletingLastPathComponent().path)
        XCTAssertTrue(saved.contains { $0.hasPrefix("india_risk-before-import-") })
    }

    func testNearbySearchFindsClosestBeyondOldSQLLimit() throws {
        let locations = AppDataLocations(root: try root())
        try AppDataBootstrap.prepare(locations: locations, starterSource: starter())
        let db = try open(locations.selectedIndiaDatabase)
        defer { sqlite3_close(db) }
        try execute(db, """
            DELETE FROM building_stock;
            WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<300)
            INSERT INTO building_stock(building_id,source_dataset_id,latitude,longitude)
            SELECT 'far-'||x,'synthetic-india-v1',12.975,77.598 FROM n;
            INSERT INTO building_stock(building_id,source_dataset_id,latitude,longitude)
            VALUES('closest','synthetic-india-v1',12.9716,77.5946);
            """)
        let result = SQLiteIndiaRiskRepository().loadNearbyBuildings(at: locations.selectedIndiaDatabase.path,
            latitude: 12.9716, longitude: 77.5946, radiusMeters: 750)
        XCTAssertEqual(result.buildings.first?.id, "closest")
        XCTAssertEqual(result.buildings.count, 25)
        XCTAssertNil(IndiaNearbySearchBounds(latitude: .nan, longitude: 0, radiusMeters: 10))
        XCTAssertNil(IndiaNearbySearchBounds(latitude: 12, longitude: 77, radiusMeters: -.infinity))
    }

    func testRollupCacheInvalidatesAfterWALCommit() throws {
        let locations = AppDataLocations(root: try root())
        try AppDataBootstrap.prepare(locations: locations, starterSource: starter())
        let db = try open(locations.selectedIndiaDatabase)
        defer { sqlite3_close(db) }
        try execute(db, "PRAGMA journal_mode=WAL; PRAGMA wal_autocheckpoint=0;")
        let service = IndiaPortfolioRollupService(cacheStore: FileIndiaPortfolioRollupCacheStore(cacheURL: locations.root.appendingPathComponent("cache.json")))
        let before = service.loadPortfolioRollupSnapshot(at: locations.selectedIndiaDatabase.path)
        XCTAssertEqual(before.buildingCount, 12, before.statusMessage)
        try execute(db, "DELETE FROM building_stock WHERE building_id='SYNTHETIC-IN-001';")
        XCTAssertEqual(service.loadPortfolioRollupSnapshot(at: locations.selectedIndiaDatabase.path).buildingCount, 11)
    }

    func testRollupCountsLatestAssessmentPerBuildingNotHistoryOrOtherHazards() throws {
        let locations = AppDataLocations(root: try root())
        try AppDataBootstrap.prepare(locations: locations, starterSource: starter())
        let db = try open(locations.selectedIndiaDatabase)
        defer { sqlite3_close(db) }
        try execute(db, """
            INSERT INTO risk_assessments(assessment_id,building_id,hazard_type,analysis_scope,risk_band,scenario_label,created_at)
            VALUES ('old','SYNTHETIC-IN-001','wildfire','building','high','old','2026-01-01'),
                   ('new','SYNTHETIC-IN-001','wildfire','building','low','new','2026-02-01'),
                   ('flood','SYNTHETIC-IN-001','flood','building','high','flood','2026-03-01');
            """)
        let snapshot = SQLiteIndiaPortfolioRollupSnapshotLoader().loadPortfolioRollupSnapshot(at: locations.selectedIndiaDatabase.path, modifiedAt: nil)
        XCTAssertEqual(snapshot.portfolioSummary.assessedAssets, 1, snapshot.statusMessage)
        XCTAssertEqual(snapshot.portfolioSummary.highRiskAssets, 0)
        XCTAssertEqual(snapshot.portfolioSummary.lowRiskAssets, 1)
        XCTAssertEqual(snapshot.portfolioSummary.uniqueScenarios, 1)
        XCTAssertEqual(snapshot.topRiskConcentrations.first?.assetCount, 1)
    }

    func testHundredThousandAssetLookupAndRollupBenchmark() throws {
        let locations = AppDataLocations(root: try root())
        try AppDataBootstrap.prepare(locations: locations, starterSource: starter())
        let db = try open(locations.selectedIndiaDatabase)
        defer { sqlite3_close(db) }
        try execute(db, """
            BEGIN;
            DELETE FROM building_stock;
            WITH RECURSIVE n(x) AS (SELECT 1 UNION ALL SELECT x+1 FROM n WHERE x<100000)
            INSERT INTO building_stock(building_id,source_dataset_id,state_code,district_name,latitude,longitude,area_m2)
            SELECT 'asset-'||x,'synthetic-india-v1','KA','district-'||(x%20),12.8+(x%400)*0.001,77.4+(x/400)*0.001,100 FROM n;
            INSERT INTO risk_assessments(assessment_id,building_id,hazard_type,analysis_scope,burn_probability,risk_band,scenario_label)
            SELECT 'risk-'||building_id,building_id,'wildfire','building',0.2,'low','synthetic' FROM building_stock;
            COMMIT;
            """)
        let repository = SQLiteIndiaRiskRepository()
        var timings: [Double] = []
        for _ in 0..<20 {
            let start = ProcessInfo.processInfo.systemUptime
            let result = repository.loadNearbyBuildings(at: locations.selectedIndiaDatabase.path,
                latitude: 12.9716, longitude: 77.5946, radiusMeters: 750)
            timings.append(ProcessInfo.processInfo.systemUptime - start)
            XCTAssertEqual(result.buildings.count, 25)
        }
        timings.sort()
        let service = IndiaPortfolioRollupService(cacheStore: FileIndiaPortfolioRollupCacheStore(cacheURL: locations.root.appendingPathComponent("cache.json")))
        let start = ProcessInfo.processInfo.systemUptime
        let snapshot = service.loadPortfolioRollupSnapshot(at: locations.selectedIndiaDatabase.path)
        let cold = ProcessInfo.processInfo.systemUptime - start
        let warmStart = ProcessInfo.processInfo.systemUptime
        XCTAssertEqual(service.loadPortfolioRollupSnapshot(at: locations.selectedIndiaDatabase.path).buildingCount, 100000)
        let warm = ProcessInfo.processInfo.systemUptime - warmStart
        XCTAssertEqual(snapshot.portfolioSummary.assessedAssets, 100000)
        print("INDIA_BENCHMARK assets=100000 samples=20 nearby_p50_s=\(timings[9]) nearby_p95_s=\(timings[18]) rollup_cold_s=\(cold) rollup_warm_s=\(warm)")
    }
}
