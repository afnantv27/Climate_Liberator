import Foundation
import SQLite3

/// Writable data belongs to the current user; application resources are read-only seeds.
struct AppDataLocations: Sendable {
    let root: URL

    nonisolated init(root: URL) { self.root = root }

    nonisolated static var current: AppDataLocations {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return AppDataLocations(root: support.appendingPathComponent("ClimateLiberator", isDirectory: true))
    }

    nonisolated var starterDirectory: URL { root.appendingPathComponent("StarterData-v1", isDirectory: true) }
    nonisolated var installedIndiaDatabase: URL { root.appendingPathComponent("Data/India/india_risk.db") }
    nonisolated var selectedIndiaDatabase: URL {
        FileManager.default.fileExists(atPath: installedIndiaDatabase.path)
            ? installedIndiaDatabase : starterDirectory.appendingPathComponent("India/india_demo.db")
    }
    nonisolated var studyDirectory: URL { starterDirectory.appendingPathComponent("Studies/India-Demo-S", isDirectory: true) }
    nonisolated var runsDirectory: URL { root.appendingPathComponent("Runs", isDirectory: true) }

    nonisolated static var applicationSupportDirectory: URL { current.root }
    nonisolated static var indiaDatabaseURL: URL { current.selectedIndiaDatabase }
    nonisolated static var indiaDemoDirectory: URL { current.starterDirectory.appendingPathComponent("India/demo", isDirectory: true) }
    nonisolated static var exportsDirectory: URL { current.root.appendingPathComponent("Exports", isDirectory: true) }
    nonisolated static var forecastProcessedDirectory: URL { current.root.appendingPathComponent("Data/Forecast/processed", isDirectory: true) }
    nonisolated static var forecastManifestsDirectory: URL { forecastProcessedDirectory.appendingPathComponent("manifests", isDirectory: true) }
    nonisolated static var starterStudyDirectory: URL { current.studyDirectory }
    nonisolated static var bundledEngineURL: URL { Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/Cell2Fire") }
    nonisolated static var previewEngineURL: URL { current.root.appendingPathComponent("Engines/climate-liberator-engine") }
}

enum AppDataSetupError: LocalizedError {
    case missingStarterResources
    case invalidDatabase(String)

    nonisolated var errorDescription: String? {
        switch self {
        case .missingStarterResources:
            return "Starter data is missing from this app build. Rebuild or reinstall Climate Liberator."
        case .invalidDatabase(let detail):
            return "The India database could not be installed: \(detail)"
        }
    }
}

enum AppDataBootstrap {
    nonisolated static func prepare() throws {
        guard let source = Bundle.main.url(forResource: "StarterData", withExtension: "bundle") else {
            throw AppDataSetupError.missingStarterResources
        }
        try prepare(locations: .current, starterSource: source)
    }

    nonisolated static func prepare(locations: AppDataLocations, starterSource: URL) throws {
        let fm = FileManager.default
        for relative in ["", "Runs", "Exports", "Data/India", "Data/Forecast/processed/manifests", "Engines"] {
            try fm.createDirectory(at: locations.root.appendingPathComponent(relative), withIntermediateDirectories: true)
        }
        guard !fm.fileExists(atPath: locations.starterDirectory.path) else { return }
        for required in ["India/india_demo.db", "Studies/India-Demo-S/fuels.asc", "manifest.json"] {
            guard fm.fileExists(atPath: starterSource.appendingPathComponent(required).path) else {
                throw AppDataSetupError.missingStarterResources
            }
        }
        let staging = locations.root.appendingPathComponent(".starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: staging) }
        try fm.copyItem(at: starterSource, to: staging)
        // Publish the complete seed in one rename; upgrades never overwrite user data.
        try fm.moveItem(at: staging, to: locations.starterDirectory)
    }

    /// SQLite backup takes a consistent snapshot, including committed WAL transactions.
    nonisolated static func installIndiaDatabase(from source: URL, locations: AppDataLocations = .current) throws {
        let fm = FileManager.default
        let destination = locations.installedIndiaDatabase
        guard source.standardizedFileURL.resolvingSymlinksInPath() != destination.standardizedFileURL.resolvingSymlinksInPath() else { return }
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".import-\(UUID().uuidString).db")
        defer { try? fm.removeItem(at: staging) }
        var input: OpaquePointer?
        guard sqlite3_open_v2(source.path, &input, SQLITE_OPEN_READONLY, nil) == SQLITE_OK, let input else {
            if let input { sqlite3_close(input) }
            throw AppDataSetupError.invalidDatabase("file cannot be opened")
        }
        defer { sqlite3_close(input) }
        sqlite3_busy_timeout(input, 5000)
        guard sqlite3_exec(input, "BEGIN", nil, nil, nil) == SQLITE_OK else {
            throw AppDataSetupError.invalidDatabase("source snapshot cannot be started")
        }
        defer { sqlite3_exec(input, "ROLLBACK", nil, nil, nil) }
        // Validate the query and assessment-write contract before replacing an installed database.
        for query in [
            "SELECT dataset_id FROM datasets LIMIT 0",
            "SELECT building_id,state_code,district_name,latitude,longitude,area_m2,total_built_up_m2,building_floor_count,landuse FROM building_stock LIMIT 0",
            "SELECT assessment_id,run_id,site_asset_id,building_id,hazard_type,scenario_label,burn_probability,expected_exposed_area_m2,distance_to_fire_m,risk_band,assessment_notes,created_at FROM risk_assessments LIMIT 0",
            "SELECT run_id,engine_name,generated_at,scenario_label,run_artifact_path,weather_input_format,ignition_input_mode,provenance_json FROM wildfire_runs LIMIT 0"
        ] {
            var statement: OpaquePointer?
            let code = sqlite3_prepare_v2(input, query, -1, &statement, nil)
            if let statement { sqlite3_finalize(statement) }
            guard code == SQLITE_OK else { throw AppDataSetupError.invalidDatabase("required schema columns are missing") }
        }
        var output: OpaquePointer?
        guard sqlite3_open_v2(staging.path, &output, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil) == SQLITE_OK, let output else {
            if let output { sqlite3_close(output) }
            throw AppDataSetupError.invalidDatabase("temporary database cannot be created")
        }
        var backupCode: Int32 = SQLITE_ERROR
        if let backup = sqlite3_backup_init(output, "main", input, "main") {
            backupCode = sqlite3_backup_step(backup, -1)
            let finishCode = sqlite3_backup_finish(backup)
            if finishCode != SQLITE_OK { backupCode = finishCode }
        }
        // Keep the installed snapshot self-contained and add indexes used by the app.
        let indexCode = backupCode == SQLITE_DONE ? sqlite3_exec(output, "PRAGMA journal_mode=DELETE; CREATE INDEX IF NOT EXISTS idx_cl_building_coordinates ON building_stock(latitude,longitude); CREATE INDEX IF NOT EXISTS idx_cl_assessment_latest ON risk_assessments(building_id,created_at DESC);", nil, nil, nil) : SQLITE_ERROR
        var integrity: OpaquePointer?
        let prepared = sqlite3_prepare_v2(output, "PRAGMA quick_check", -1, &integrity, nil)
        let valid = prepared == SQLITE_OK && sqlite3_step(integrity) == SQLITE_ROW
            && sqlite3_column_text(integrity, 0).map { String(cString: $0) == "ok" } == true
        sqlite3_finalize(integrity)
        sqlite3_close(output)
        guard backupCode == SQLITE_DONE, indexCode == SQLITE_OK, valid else {
            throw AppDataSetupError.invalidDatabase("snapshot failed or the source is busy; close writers and retry")
        }
        // Do not replace an open WAL database: existing connections may still own its sidecars.
        if fm.fileExists(atPath: destination.path + "-wal") || fm.fileExists(atPath: destination.path + "-shm") {
            throw AppDataSetupError.invalidDatabase("the installed database is in use; close other database tools and retry")
        }
        if fm.fileExists(atPath: destination.path) {
            let backup = "india_risk-before-import-\(UUID().uuidString).db"
            _ = try fm.replaceItemAt(destination, withItemAt: staging, backupItemName: backup, options: .withoutDeletingBackupItem)
        } else {
            try fm.moveItem(at: staging, to: destination)
        }
    }
}

extension Notification.Name {
    static let climateLiberatorIndiaDataChanged = Notification.Name("climateliberator.indiaDataChanged")
}
