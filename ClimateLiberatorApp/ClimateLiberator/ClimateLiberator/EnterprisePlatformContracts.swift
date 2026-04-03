import Foundation
import CoreLocation

struct EnterpriseDashboardSummaryRequest {
    let outputFolder: String
    let sampleLimit: Int

    init(outputFolder: String, sampleLimit: Int = 500) {
        self.outputFolder = outputFolder
        self.sampleLimit = sampleLimit
    }
}

struct EnterpriseDashboardSummaryResponse {
    let generatedAt: Date
    let measuredSurfaceCount: Int
    let totalSurfaceCount: Int
    let availabilityObjectiveCount: Int
    let serviceLevelObjectiveCount: Int
    let activeArtifactCount: Int
    let disclosureManifestCount: Int
    let latestSimulationEngineLabel: String?
    let surfaceReadiness: [EnterpriseSurfaceReadiness]

    var coverageLabel: String {
        "\(measuredSurfaceCount)/\(totalSurfaceCount) surfaces measured"
    }

    var readinessSummary: EnterpriseReadinessSummary {
        EnterpriseReadinessSummary(
            generatedAt: generatedAt,
            measuredSurfaceCount: measuredSurfaceCount,
            totalSurfaceCount: totalSurfaceCount,
            availabilityObjectiveCount: availabilityObjectiveCount,
            serviceLevelObjectiveCount: serviceLevelObjectiveCount,
            activeArtifactCount: activeArtifactCount,
            disclosureManifestCount: disclosureManifestCount,
            latestSimulationEngineLabel: latestSimulationEngineLabel,
            surfaceReadiness: surfaceReadiness
        )
    }
}

struct EnterprisePortfolioDatabaseStatusRequest {
    let databasePath: String
}

struct EnterprisePortfolioDatabaseStatusResponse {
    let snapshot: IndiaDatabaseStatusSnapshot
}

struct EnterprisePortfolioNearbyLookupRequest {
    let databasePath: String
    let latitude: Double
    let longitude: Double
    let radiusMeters: Double
}

struct EnterprisePortfolioNearbyLookupResponse {
    let snapshot: IndiaNearbyLookupSnapshot
}

struct EnterprisePortfolioOEDExportRequest {
    let databasePath: String
}

struct EnterprisePortfolioOEDExportResponse {
    let result: IndiaOEDExportResult?
    let errorMessage: String?
}

struct EnterpriseForecastFeedRequest {
    let coordinate: CLLocationCoordinate2D
    let horizon: ForecastHorizon

    init(latitude: Double, longitude: Double, horizon: ForecastHorizon) {
        self.coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        self.horizon = horizon
    }

    init(coordinate: CLLocationCoordinate2D, horizon: ForecastHorizon) {
        self.coordinate = coordinate
        self.horizon = horizon
    }
}

extension EnterpriseForecastFeedRequest: Hashable {
    static func == (lhs: EnterpriseForecastFeedRequest, rhs: EnterpriseForecastFeedRequest) -> Bool {
        lhs.coordinate.latitude == rhs.coordinate.latitude &&
        lhs.coordinate.longitude == rhs.coordinate.longitude &&
        lhs.horizon == rhs.horizon
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(coordinate.latitude)
        hasher.combine(coordinate.longitude)
        hasher.combine(horizon)
    }
}

struct EnterpriseForecastFeedResponse {
    let feed: ProcessedForecastFeed?
}

struct EnterpriseForecastSupportFeedsRequest {
    init() {}
}

struct EnterpriseForecastSupportFeedsResponse {
    let feeds: ForecastBuildSupportFeeds
}

struct EnterpriseForecastSnapshotsRequest {
    init() {}
}

struct EnterpriseForecastSnapshotsResponse {
    let collections: ForecastSnapshotCollections
}

enum EnterpriseSimulationJobStatus: String, Codable, Hashable {
    case accepted
    case running
    case completed
    case failed
    case unknown
}

struct EnterpriseSimulationSubmissionRequest {
    let engineRequest: SimulationEngineRequest
    let correlationID: String?

    init(engineRequest: SimulationEngineRequest, correlationID: String? = nil) {
        self.engineRequest = engineRequest
        self.correlationID = correlationID
    }
}

struct EnterpriseSimulationSubmissionResponse {
    let correlationID: String
    let acceptedAt: Date
    let mode: SimulationEngineMode
    let engineLabel: String
}

struct EnterpriseSimulationStatusRequest {
    let correlationID: String?
    let runID: String?
    let outputDirectory: String?

    init(correlationID: String? = nil, runID: String? = nil, outputDirectory: String? = nil) {
        self.correlationID = correlationID
        self.runID = runID
        self.outputDirectory = outputDirectory
    }
}

struct EnterpriseSimulationStatusResponse {
    let status: EnterpriseSimulationJobStatus
    let engineLabel: String?
    let runID: String?
    let outputDirectory: String?
    let outputManifestURL: String?
    let artifactURL: String?
    let lastUpdatedAt: Date?
    let correlationID: String?
    let metadata: [String: String]
}

struct EnterpriseArtifactManifestRequest {
    let kind: EnterpriseArtifactKind?
    let runID: String?
    let outputDirectory: String?
    let latestOnly: Bool

    init(kind: EnterpriseArtifactKind? = nil,
         runID: String? = nil,
         outputDirectory: String? = nil,
         latestOnly: Bool = false) {
        self.kind = kind
        self.runID = runID
        self.outputDirectory = outputDirectory
        self.latestOnly = latestOnly
    }
}

struct EnterpriseArtifactManifestResponse {
    let generatedAt: Date
    let records: [EnterpriseArtifactRecord]
}

struct EnterpriseDisclosureBundleRequest {
    let outputFolder: String
}

struct EnterpriseDisclosureBundleResponse {
    let inventory: DisclosureBundleInventory
}

protocol EnterpriseDashboardServicing {
    func fetchSummary(request: EnterpriseDashboardSummaryRequest) -> EnterpriseDashboardSummaryResponse
}

protocol EnterprisePortfolioServicing {
    func fetchDatabaseStatus(request: EnterprisePortfolioDatabaseStatusRequest) -> EnterprisePortfolioDatabaseStatusResponse
    func fetchNearbyLookup(request: EnterprisePortfolioNearbyLookupRequest) -> EnterprisePortfolioNearbyLookupResponse
    func exportOED(request: EnterprisePortfolioOEDExportRequest) -> EnterprisePortfolioOEDExportResponse
}

protocol EnterpriseForecastServicing {
    func fetchProcessedFeed(request: EnterpriseForecastFeedRequest) -> EnterpriseForecastFeedResponse
    func fetchSupportFeeds(request: EnterpriseForecastSupportFeedsRequest) -> EnterpriseForecastSupportFeedsResponse
    func fetchSnapshots(request: EnterpriseForecastSnapshotsRequest) -> EnterpriseForecastSnapshotsResponse
}

protocol EnterpriseSimulationStatusServicing {
    func acknowledgeSubmission(request: EnterpriseSimulationSubmissionRequest) -> EnterpriseSimulationSubmissionResponse
    func fetchStatus(request: EnterpriseSimulationStatusRequest) -> EnterpriseSimulationStatusResponse
}

protocol EnterpriseArtifactManifestServicing {
    func fetchManifests(request: EnterpriseArtifactManifestRequest) -> EnterpriseArtifactManifestResponse
}

protocol EnterpriseDisclosureBundleClientServicing {
    func fetchBundles(request: EnterpriseDisclosureBundleRequest) -> EnterpriseDisclosureBundleResponse
}
