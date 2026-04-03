import Foundation
import Combine

struct IndiaNearbyBuilding: Identifiable, Codable, Hashable {
    let id: String
    let districtName: String
    let stateCode: String
    let latitude: Double
    let longitude: Double
    let areaM2: Double?
    let builtUpM2: Double?
    let floorCount: Int?
    let landuse: String?
    let distanceMeters: Double
    let riskBand: String?
    let scenarioLabel: String?
}

struct IndiaBuildingLookupSummary: Codable, Hashable {
    let buildingCount: Int
    let totalFootprintM2: Double
    let totalBuiltUpM2: Double
}

struct IndiaPortfolioRiskSummary: Codable, Hashable {
    let assessedAssets: Int
    let highRiskAssets: Int
    let mediumRiskAssets: Int
    let lowRiskAssets: Int
    let uniqueScenarios: Int
    let latestAssessmentAt: String?

    static let empty = IndiaPortfolioRiskSummary(
        assessedAssets: 0,
        highRiskAssets: 0,
        mediumRiskAssets: 0,
        lowRiskAssets: 0,
        uniqueScenarios: 0,
        latestAssessmentAt: nil
    )
}

struct IndiaDemoPortfolioOverview: Codable, Hashable {
    let portfolioID: String
    let portfolioName: String
    let asOf: String
    let siteCount: Int
    let assessedSiteCount: Int
    let scenarioCount: Int
    let highRiskSiteCount: Int
    let mediumRiskSiteCount: Int
    let lowRiskSiteCount: Int
    let totalExpectedExposedAreaM2: Double
    let latestRunIDs: [String]

    enum CodingKeys: String, CodingKey {
        case portfolioID = "portfolio_id"
        case portfolioName = "portfolio_name"
        case asOf = "as_of"
        case siteCount = "site_count"
        case assessedSiteCount = "assessed_site_count"
        case scenarioCount = "scenario_count"
        case highRiskSiteCount = "high_risk_site_count"
        case mediumRiskSiteCount = "medium_risk_site_count"
        case lowRiskSiteCount = "low_risk_site_count"
        case totalExpectedExposedAreaM2 = "total_expected_exposed_area_m2"
        case latestRunIDs = "latest_run_ids"
    }
}

struct IndiaDemoPortfolioComparisonSummary: Codable, Hashable {
    let portfolioID: String
    let baselineRunID: String
    let baselineScenarioLabel: String
    let comparatorRunID: String
    let comparatorScenarioLabel: String
    let deltaHighRiskSiteCount: Int
    let deltaExpectedExposedAreaM2: Double
    let worsenedSiteCount: Int
    let improvedSiteCount: Int
    let comparisonReady: Bool

    enum CodingKeys: String, CodingKey {
        case portfolioID = "portfolio_id"
        case baselineRunID = "baseline_run_id"
        case baselineScenarioLabel = "baseline_scenario_label"
        case comparatorRunID = "comparator_run_id"
        case comparatorScenarioLabel = "comparator_scenario_label"
        case deltaHighRiskSiteCount = "delta_high_risk_site_count"
        case deltaExpectedExposedAreaM2 = "delta_expected_exposed_area_m2"
        case worsenedSiteCount = "worsened_site_count"
        case improvedSiteCount = "improved_site_count"
        case comparisonReady = "comparison_ready"
    }
}

struct IndiaDemoPortfolioTrustSummary: Codable, Hashable {
    let portfolioID: String
    let portfolioName: String
    let asOf: String
    let assessedSiteCount: Int
    let artifactBackedSiteCount: Int
    let plannedOnlySiteCount: Int
    let missingProvenanceSiteCount: Int
    let preparedInstanceReferencedRunCount: Int
    let artifactBackedRunCount: Int

    enum CodingKeys: String, CodingKey {
        case portfolioID = "portfolio_id"
        case portfolioName = "portfolio_name"
        case asOf = "as_of"
        case assessedSiteCount = "assessed_site_count"
        case artifactBackedSiteCount = "artifact_backed_site_count"
        case plannedOnlySiteCount = "planned_only_site_count"
        case missingProvenanceSiteCount = "missing_provenance_site_count"
        case preparedInstanceReferencedRunCount = "prepared_instance_referenced_run_count"
        case artifactBackedRunCount = "artifact_backed_run_count"
    }
}

struct IndiaRiskConcentration: Identifiable, Codable, Hashable {
    let id: String
    let stateCode: String
    let assetCount: Int
    let highRiskCount: Int
    let averageBurnProbability: Double?
}

struct IndiaOEDExportResult: Codable, Hashable {
    let filePath: String
    let rowCount: Int
    let sourceLabel: String
}

final class IndiaRiskStore: ObservableObject {
    private struct NearbyLookupCacheKey: Hashable {
        let databasePath: String
        let latitudeBucket: Int
        let longitudeBucket: Int
        let radiusBucket: Int

        init(databasePath: String, latitude: Double, longitude: Double, radiusMeters: Double) {
            self.databasePath = databasePath
            self.latitudeBucket = Int((latitude * 100_000).rounded())
            self.longitudeBucket = Int((longitude * 100_000).rounded())
            self.radiusBucket = Int(radiusMeters.rounded())
        }
    }

    private let databaseQueue = DispatchQueue(label: "com.climateliberator.india-risk.db", qos: .utility)
    private let repository: IndiaRiskRepository
    private let exportService: IndiaRiskExporting
    private let demoFeedService: IndiaDemoFeedProviding
    private let rollupService: IndiaPortfolioRollupServicing
    private var nearbyLookupCache: [NearbyLookupCacheKey: IndiaNearbyLookupSnapshot] = [:]

    @Published var databasePath: String
    @Published private(set) var buildingCount = 0
    @Published private(set) var nearbyBuildings: [IndiaNearbyBuilding] = []
    @Published private(set) var lookupSummary = IndiaBuildingLookupSummary(buildingCount: 0, totalFootprintM2: 0, totalBuiltUpM2: 0)
    @Published private(set) var portfolioSummary = IndiaPortfolioRiskSummary.empty
    @Published private(set) var topRiskConcentrations: [IndiaRiskConcentration] = []
    @Published private(set) var portfolioHierarchySummaries: [IndiaPortfolioHierarchySummary] = []
    @Published private(set) var demoPortfolioOverview: IndiaDemoPortfolioOverview?
    @Published private(set) var demoComparisonSummary: IndiaDemoPortfolioComparisonSummary?
    @Published private(set) var demoTrustSummary: IndiaDemoPortfolioTrustSummary?
    @Published private(set) var statusMessage = "India data hub ready."
    @Published private(set) var lastOEDExport: IndiaOEDExportResult?
    @Published var radiusMeters = 750.0
    @Published private(set) var databaseConnected = false
    @Published private(set) var schemaReady = false

    convenience init(databasePath: String = IndiaRiskStore.defaultDatabasePath()) {
        self.init(
            databasePath: databasePath,
            repository: SQLiteIndiaRiskRepository(),
            exportService: SQLiteIndiaOEDExportService(),
            demoFeedService: FileIndiaDemoFeedService(),
            rollupService: IndiaPortfolioRollupService()
        )
    }

    init(databasePath: String,
         repository: IndiaRiskRepository,
         exportService: IndiaRiskExporting,
         demoFeedService: IndiaDemoFeedProviding,
         rollupService: IndiaPortfolioRollupServicing) {
        self.databasePath = databasePath
        self.repository = repository
        self.exportService = exportService
        self.demoFeedService = demoFeedService
        self.rollupService = rollupService
    }

    var databaseAvailability: ActionAvailability {
        let baseAvailability = AppActionSupport.pathAvailability(
            path: databasePath,
            expectation: .file,
            emptyReason: "Set the India risk database path.",
            missingReason: "India database file not found at the current path."
        )
        guard baseAvailability.isEnabled else {
            return baseAvailability
        }
        guard schemaReady else {
            return .unavailable("The database is reachable, but the Climate Liberator schema is incomplete.")
        }
        return .ready
    }

    var lookupAvailability: ActionAvailability {
        let databaseAvailability = databaseAvailability
        guard databaseAvailability.isEnabled else {
            return databaseAvailability
        }
        guard buildingCount > 0 else {
            return .unavailable("Import approved GOBS state CSVs or client asset data before screening a site.")
        }
        return .ready
    }

    var oedExportAvailability: ActionAvailability {
        let databaseAvailability = databaseAvailability
        guard databaseAvailability.isEnabled else {
            return databaseAvailability
        }
        guard buildingCount > 0 else {
            return .unavailable("Import approved GOBS state CSVs or client asset data before exporting OED-style exposure.")
        }
        return .ready
    }

    var nearbyEmptyStateMessage: String {
        if !databaseAvailability.isEnabled {
            return databaseAvailability.reason ?? "Connect the India risk database to continue."
        }
        if buildingCount == 0 {
            return "The India database is connected, but no building stock has been imported yet."
        }
        return "No imported buildings were found within \(Int(radiusMeters)) m of the selected site."
    }

    func refreshDatabaseStatus() {
        nearbyLookupCache.removeAll()
        nearbyBuildings = []
        lookupSummary = IndiaBuildingLookupSummary(buildingCount: 0, totalFootprintM2: 0, totalBuiltUpM2: 0)
        portfolioSummary = .empty
        topRiskConcentrations = []
        portfolioHierarchySummaries = []
        demoPortfolioOverview = nil
        demoComparisonSummary = nil
        demoTrustSummary = nil
        statusMessage = "Checking India database…"

        let path = databasePath
        databaseQueue.async { [weak self] in
            guard let self else { return }
            let databaseSnapshot = self.repository.loadDatabaseStatus(at: path)
            let demoFeeds = self.demoFeedService.loadDemoPortfolioFeeds()
            let rollupSnapshot = self.rollupService.loadPortfolioRollupSnapshot(at: path)
            DispatchQueue.main.async {
                guard self.databasePath == path else { return }
                self.databaseConnected = databaseSnapshot.databaseConnected
                self.schemaReady = databaseSnapshot.schemaReady
                self.buildingCount = databaseSnapshot.buildingCount
                self.portfolioSummary = rollupSnapshot.portfolioSummary
                self.topRiskConcentrations = rollupSnapshot.topRiskConcentrations
                self.portfolioHierarchySummaries = rollupSnapshot.hierarchySummaries
                self.demoPortfolioOverview = demoFeeds.overview
                self.demoComparisonSummary = demoFeeds.comparison
                self.demoTrustSummary = demoFeeds.trust
                self.statusMessage = rollupSnapshot.statusMessage.isEmpty ? databaseSnapshot.statusMessage : rollupSnapshot.statusMessage
            }
        }
    }

    func lookupNearbyBuildings(latitude: Double, longitude: Double) {
        let availability = lookupAvailability
        guard availability.isEnabled else {
            nearbyBuildings = []
            lookupSummary = IndiaBuildingLookupSummary(buildingCount: 0, totalFootprintM2: 0, totalBuiltUpM2: 0)
            statusMessage = availability.reason ?? "India database not available."
            return
        }
        nearbyBuildings = []
        lookupSummary = IndiaBuildingLookupSummary(buildingCount: 0, totalFootprintM2: 0, totalBuiltUpM2: 0)
        statusMessage = "Looking up nearby buildings…"

        let path = databasePath
        let radiusMeters = self.radiusMeters
        let cacheKey = NearbyLookupCacheKey(databasePath: path,
                                            latitude: latitude,
                                            longitude: longitude,
                                            radiusMeters: radiusMeters)
        if let cached = nearbyLookupCache[cacheKey] {
            nearbyBuildings = cached.buildings
            lookupSummary = cached.summary
            statusMessage = cached.statusMessage
            return
        }
        databaseQueue.async { [weak self] in
            guard let self else { return }
            let snapshot = self.repository.loadNearbyBuildings(at: path,
                                                               latitude: latitude,
                                                               longitude: longitude,
                                                               radiusMeters: radiusMeters)
            DispatchQueue.main.async {
                guard self.databasePath == path else { return }
                self.nearbyLookupCache[cacheKey] = snapshot
                self.nearbyBuildings = snapshot.buildings
                self.lookupSummary = snapshot.summary
                self.statusMessage = snapshot.statusMessage
            }
        }
    }

    func exportPortfolioAsOEDCSV() {
        let availability = oedExportAvailability
        guard availability.isEnabled else {
            statusMessage = availability.reason ?? "India exposure export is not available."
            return
        }

        statusMessage = "Exporting OED-style portfolio CSV…"
        let path = databasePath
        databaseQueue.async { [weak self] in
            guard let self else { return }
            let exportOutcome = self.exportService.buildOEDExport(at: path)
            DispatchQueue.main.async {
                guard self.databasePath == path else { return }
                if let export = exportOutcome.result {
                    self.lastOEDExport = export
                    self.statusMessage = "Exported \(export.rowCount) OED-style exposure row(s) from \(export.sourceLabel)."
                } else {
                    let message = exportOutcome.errorMessage ?? "Could not export the OED-style portfolio file."
                    self.statusMessage = message
                }
            }
        }
    }

    func persistWildfireAssessments(request: IndiaWildfireRiskLinkRequest,
                                    grid: IndiaWildfireRiskGrid) throws -> IndiaWildfireRiskLinkResult {
        try repository.persistWildfireAssessments(databasePath: databasePath, request: request, grid: grid)
    }

    static func defaultDatabasePath() -> String {
        "/Users/afnan/Desktop/Build/india-risk-data/db/india_risk.db"
    }

    static func defaultDemoFeedDirectory() -> String {
        "/Users/afnan/Desktop/Build/india-risk-data/data/processed/demo"
    }
}
