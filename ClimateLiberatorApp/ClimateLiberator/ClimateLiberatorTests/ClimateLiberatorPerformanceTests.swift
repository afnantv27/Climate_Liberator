import SQLite3
import XCTest
import SQLite3
@testable import ClimateLiberator

@MainActor
final class ClimateLiberatorPerformanceTests: XCTestCase {
    func testSimulationOutputTreeBuildPerformance() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let rosDir = tempRoot.appendingPathComponent("RateOfSpread", isDirectory: true)
        let overlaysDir = tempRoot.appendingPathComponent("overlays", isDirectory: true)
        try FileManager.default.createDirectory(at: rosDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: overlaysDir, withIntermediateDirectories: true)

        for index in 0..<120 {
            let fileName = String(format: "ROSFile%03d.asc", index)
            try "ncols 2\nnrows 2\nxllcorner 0\nyllcorner 0\ncellsize 1\nNODATA_value -9999\n1 2\n3 4\n"
                .write(to: rosDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }
        for index in 0..<30 {
            let fileName = String(format: "overlay%03d.asc", index)
            try "ncols 2\nnrows 2\nxllcorner 0\nyllcorner 0\ncellsize 1\nNODATA_value -9999\n1 2\n3 4\n"
                .write(to: overlaysDir.appendingPathComponent(fileName), atomically: true, encoding: .utf8)
        }

        let service = SimulationOutputTreeService()
        measure(metrics: [XCTClockMetric()]) {
            _ = service.buildOutputTree(rateOfSpreadBase: tempRoot.path,
                                        earthEngineOverlaysDirectory: overlaysDir,
                                        limits: OutputTreeDiscoveryLimits(maxDepth: 4, maxNodes: 300))
        }
    }

    func testForecastMetricCardBuilderPerformance() {
        let builder = ForecastMetricCardBuilder()
        let weather = OpenMeteoWeatherResponse(
            daily: .init(
                temperature2MMean: Array(repeating: 27.4, count: 90),
                temperature2MMax: Array(repeating: 33.1, count: 90),
                temperature2MMin: Array(repeating: 20.2, count: 90),
                precipitationSum: Array(repeating: 5.6, count: 90),
                soilTemperature0cmMean: Array(repeating: 24.2, count: 90),
                relativeHumidity2MMean: Array(repeating: 68.0, count: 90),
                et0FaoEvapotranspiration: Array(repeating: 2.4, count: 90),
                shortwaveRadiationSum: Array(repeating: 18.6, count: 90),
                soilMoisture0To1cmMean: Array(repeating: 0.23, count: 90),
                windSpeed10MMean: Array(repeating: 13.2, count: 90)
            ),
            dailyUnits: .init(
                temperature2MMean: "C",
                temperature2MMax: "C",
                temperature2MMin: "C",
                precipitationSum: "mm",
                soilTemperature0cmMean: "C",
                relativeHumidity2MMean: "%",
                et0FaoEvapotranspiration: "mm",
                shortwaveRadiationSum: "MJ/m2",
                soilMoisture0To1cmMean: "m3/m3",
                windSpeed10MMean: "km/h"
            )
        )

        let air = OpenMeteoAirQualityResponse(
            hourly: .init(
                usAQI: Array(repeating: 82.0, count: 48),
                pm10: Array(repeating: 46.0, count: 48),
                pm25: Array(repeating: 21.0, count: 48),
                ozone: Array(repeating: 71.0, count: 48),
                nitrogenDioxide: nil,
                sulphurDioxide: nil,
                carbonMonoxide: nil
            ),
            hourlyUnits: .init(usAQI: nil, pm10: "ug/m3", pm25: "ug/m3", ozone: "ug/m3")
        )

        measure(metrics: [XCTClockMetric()]) {
            _ = builder.buildWeatherCards(from: weather)
            _ = builder.buildAirQualityCards(from: air)
        }
    }

    func testRunConfigurationRoundTripPerformance() throws {
        let service = SimulationRunConfigService()
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        let document = OperationalRunConfigDocument(
            schemaVersion: 1,
            hazardType: "wildfire",
            exportedAt: Date(timeIntervalSince1970: 1_700_000_000),
            binaryPath: "/tmp/Cell2Fire",
            inputFolder: "/tmp/input",
            outputFolder: "/tmp/output",
            simulatorCode: "S",
            includeROS: true,
            weatherPeriodMinutes: 60,
            outputFormat: "asc",
            numberOfSimulations: 20,
            numberOfThreads: 8,
            seed: 321,
            selectedScenarioID: nil,
            scenarioName: "Stress",
            tcfdScenarioLabel: "Stress Test",
            scenarioPathway: "SSP5-8.5",
            scenarioHorizon: "5-20 years"
        )

        measure(metrics: [XCTClockMetric()]) {
            do {
                let data = try service.exportData(for: document)
                try data.write(to: tempURL, options: .atomic)
                _ = try service.importDocument(from: tempURL)
            } catch {
                XCTFail("Round-trip performance failed: \(error.localizedDescription)")
            }
        }
    }

    func testIndiaPortfolioRollupCachedLoadPerformance() throws {
        let databaseURL = try makeIndiaPortfolioRollupDatabaseForPerformance()
        let loader = SQLiteIndiaPortfolioRollupSnapshotLoader()
        let cache = InMemoryIndiaPortfolioRollupCache()
        let service = IndiaPortfolioRollupService(loader: loader, cacheStore: cache)

        _ = service.loadPortfolioRollupSnapshot(at: databaseURL.path)

        measure(metrics: [XCTClockMetric()]) {
            _ = service.loadPortfolioRollupSnapshot(at: databaseURL.path)
        }
    }

    private func makeIndiaPortfolioRollupDatabaseForPerformance() throws -> URL {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let databaseURL = tempRoot.appendingPathComponent("india_rollup.db")

        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(databaseURL.path, &db), SQLITE_OK)
        defer { sqlite3_close(db) }

        let statements = [
            """
            CREATE TABLE building_stock (
                building_id TEXT PRIMARY KEY,
                state_code TEXT,
                district_name TEXT,
                latitude REAL,
                longitude REAL,
                area_m2 REAL,
                total_built_up_m2 REAL,
                building_floor_count INTEGER,
                landuse TEXT
            );
            """,
            """
            CREATE TABLE datasets (
                dataset_id TEXT PRIMARY KEY,
                dataset_name TEXT
            );
            """,
            """
            CREATE TABLE risk_assessments (
                assessment_id TEXT PRIMARY KEY,
                run_id TEXT,
                building_id TEXT,
                hazard_type TEXT,
                scenario_label TEXT,
                burn_probability REAL,
                created_at TEXT,
                risk_band TEXT,
                site_asset_id TEXT
            );
            """
        ]

        for sql in statements {
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }

        let inserts = [
            "INSERT INTO datasets (dataset_id, dataset_name) VALUES ('ds-1', 'India baseline');",
            "INSERT INTO building_stock (building_id, state_code, district_name, latitude, longitude, area_m2, total_built_up_m2, building_floor_count, landuse) VALUES ('b1', 'MH', 'Mumbai', 19.07, 72.87, 100.0, 120.0, 10, 'utility');",
            "INSERT INTO building_stock (building_id, state_code, district_name, latitude, longitude, area_m2, total_built_up_m2, building_floor_count, landuse) VALUES ('b2', 'MH', 'Pune', 18.52, 73.85, 140.0, 150.0, 8, 'industrial');",
            "INSERT INTO building_stock (building_id, state_code, district_name, latitude, longitude, area_m2, total_built_up_m2, building_floor_count, landuse) VALUES ('b3', 'GJ', 'Ahmedabad', 23.02, 72.57, 90.0, 110.0, 12, 'utility');",
            "INSERT INTO building_stock (building_id, state_code, district_name, latitude, longitude, area_m2, total_built_up_m2, building_floor_count, landuse) VALUES ('b4', 'GJ', 'Surat', 21.17, 72.83, 80.0, 95.0, 6, 'residential');",
            "INSERT INTO risk_assessments (assessment_id, run_id, building_id, hazard_type, scenario_label, burn_probability, created_at, risk_band, site_asset_id) VALUES ('a1', 'run-1', 'b1', 'wildfire', 'Baseline', 0.61, '2026-04-03T00:00:00Z', 'High', NULL);",
            "INSERT INTO risk_assessments (assessment_id, run_id, building_id, hazard_type, scenario_label, burn_probability, created_at, risk_band, site_asset_id) VALUES ('a2', 'run-1', 'b2', 'wildfire', 'Baseline', 0.44, '2026-04-03T00:00:00Z', 'Medium', NULL);",
            "INSERT INTO risk_assessments (assessment_id, run_id, building_id, hazard_type, scenario_label, burn_probability, created_at, risk_band, site_asset_id) VALUES ('a3', 'run-1', 'b3', 'wildfire', 'Stress', 0.78, '2026-04-03T00:00:00Z', 'High', NULL);",
            "INSERT INTO risk_assessments (assessment_id, run_id, building_id, hazard_type, scenario_label, burn_probability, created_at, risk_band, site_asset_id) VALUES ('a4', 'run-1', 'b4', 'wildfire', 'Stress', 0.18, '2026-04-03T00:00:00Z', 'Low', NULL);"
        ]

        for sql in inserts {
            XCTAssertEqual(sqlite3_exec(db, sql, nil, nil, nil), SQLITE_OK)
        }

        return databaseURL
    }
}

private final class InMemoryIndiaPortfolioRollupCache: IndiaPortfolioRollupCaching {
    private var snapshot: IndiaPortfolioRollupSnapshot?

    func cachedRollupSnapshot(for path: String, modifiedAt: Date?) -> IndiaPortfolioRollupSnapshot? {
        guard let snapshot,
              snapshot.databasePath == path,
              snapshot.databaseModifiedAt == modifiedAt else {
            return nil
        }
        return snapshot
    }

    func storeRollupSnapshot(_ snapshot: IndiaPortfolioRollupSnapshot) {
        self.snapshot = snapshot
    }

    func removeRollupSnapshot(for path: String) {
        if snapshot?.databasePath == path {
            snapshot = nil
        }
    }
}
