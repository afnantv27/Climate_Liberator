import Foundation
import CoreLocation

enum EnterpriseSurface: String, Codable, CaseIterable, Hashable {
    case dashboard
    case portfolio
    case forecast
    case simulation
    case disclosure
    case artifactRegistry
    case platform
}

enum EnterpriseServiceLevelClass: String, Codable, CaseIterable, Hashable {
    case interactiveRequest
    case asyncJobSubmission
    case asyncJobQueueStart
    case asyncJobCompletion
    case artifactFetch
    case artifactGeneration
}

enum EnterprisePercentileTarget: Int, Codable, CaseIterable, Hashable {
    case p50 = 50
    case p95 = 95
    case p99 = 99
}

struct EnterpriseAvailabilityObjective: Identifiable, Codable, Hashable {
    let surface: EnterpriseSurface
    let targetPercent: Double
    let note: String

    var id: String {
        "\(surface.rawValue)-availability"
    }
}

struct EnterpriseServiceLevelObjective: Identifiable, Codable, Hashable {
    let surface: EnterpriseSurface
    let metricClass: EnterpriseServiceLevelClass
    let percentile: EnterprisePercentileTarget
    let targetMilliseconds: Int
    let note: String

    var id: String {
        "\(surface.rawValue)-\(metricClass.rawValue)-\(percentile.rawValue)"
    }
}

struct EnterpriseCapacityTarget: Codable, Hashable {
    let concurrentAnalysts: Int
    let sustainedInteractiveRequestsPerMinute: Int
    let burstInteractiveRequestsPerMinute: Int
    let activeSimulationWorkerSlots: Int
    let sustainedSimulationSubmissionsPerHour: Int
    let queuedJobsWithoutDegradation: Int
    let committedAssetCount: Int
    let validatedStretchAssetCount: Int
    let committedDisclosureBundles: Int
    let validatedStretchDisclosureBundles: Int
    let committedForecastLocations: Int
}

enum EnterpriseObjectiveCatalog {
    static let availabilityObjectives: [EnterpriseAvailabilityObjective] = [
        .init(surface: .platform, targetPercent: 99.9, note: "Monthly platform availability"),
        .init(surface: .dashboard, targetPercent: 99.9, note: "Interactive dashboard and control-plane availability"),
        .init(surface: .simulation, targetPercent: 99.5, note: "Simulation orchestration availability"),
        .init(surface: .artifactRegistry, targetPercent: 99.9, note: "Artifact retrieval availability")
    ]

    static let serviceLevelObjectives: [EnterpriseServiceLevelObjective] = [
        .init(surface: .dashboard, metricClass: .interactiveRequest, percentile: .p95, targetMilliseconds: 800, note: "Dashboard summary payload"),
        .init(surface: .dashboard, metricClass: .interactiveRequest, percentile: .p99, targetMilliseconds: 1_500, note: "Dashboard summary payload escalation threshold"),
        .init(surface: .portfolio, metricClass: .interactiveRequest, percentile: .p95, targetMilliseconds: 250, note: "Nearby asset lookup at 100k assets"),
        .init(surface: .portfolio, metricClass: .interactiveRequest, percentile: .p99, targetMilliseconds: 600, note: "Nearby asset lookup escalation threshold"),
        .init(surface: .portfolio, metricClass: .artifactFetch, percentile: .p95, targetMilliseconds: 1_000, note: "Grouped rollup at 100k assets"),
        .init(surface: .portfolio, metricClass: .artifactFetch, percentile: .p99, targetMilliseconds: 2_500, note: "Grouped rollup escalation threshold"),
        .init(surface: .disclosure, metricClass: .artifactFetch, percentile: .p95, targetMilliseconds: 500, note: "Disclosure bundle discovery at 1,000 bundles"),
        .init(surface: .disclosure, metricClass: .artifactFetch, percentile: .p99, targetMilliseconds: 1_000, note: "Disclosure bundle discovery escalation threshold"),
        .init(surface: .forecast, metricClass: .artifactFetch, percentile: .p95, targetMilliseconds: 300, note: "Forecast trust/artifact retrieval"),
        .init(surface: .forecast, metricClass: .artifactFetch, percentile: .p99, targetMilliseconds: 800, note: "Forecast trust/artifact retrieval escalation threshold"),
        .init(surface: .simulation, metricClass: .asyncJobSubmission, percentile: .p95, targetMilliseconds: 1_000, note: "Simulation submission acknowledgment"),
        .init(surface: .simulation, metricClass: .asyncJobQueueStart, percentile: .p95, targetMilliseconds: 30_000, note: "Simulation queue start under nominal load"),
        .init(surface: .simulation, metricClass: .artifactGeneration, percentile: .p95, targetMilliseconds: 10_000, note: "Artifact registration after worker completion")
    ]

    static let referenceCapacity = EnterpriseCapacityTarget(
        concurrentAnalysts: 50,
        sustainedInteractiveRequestsPerMinute: 200,
        burstInteractiveRequestsPerMinute: 600,
        activeSimulationWorkerSlots: 8,
        sustainedSimulationSubmissionsPerHour: 20,
        queuedJobsWithoutDegradation: 100,
        committedAssetCount: 100_000,
        validatedStretchAssetCount: 250_000,
        committedDisclosureBundles: 1_000,
        validatedStretchDisclosureBundles: 2_000,
        committedForecastLocations: 500
    )
}

struct EnterpriseLatencySample: Identifiable, Codable, Hashable {
    let id: UUID
    let surface: EnterpriseSurface
    let metricClass: EnterpriseServiceLevelClass
    let durationMilliseconds: Int
    let success: Bool
    let recordedAt: Date
    let correlationID: String
    let metadata: [String: String]

    init(id: UUID = UUID(),
         surface: EnterpriseSurface,
         metricClass: EnterpriseServiceLevelClass,
         durationMilliseconds: Int,
         success: Bool,
         recordedAt: Date = Date(),
         correlationID: String = UUID().uuidString,
         metadata: [String: String] = [:]) {
        self.id = id
        self.surface = surface
        self.metricClass = metricClass
        self.durationMilliseconds = durationMilliseconds
        self.success = success
        self.recordedAt = recordedAt
        self.correlationID = correlationID
        self.metadata = metadata
    }
}

struct EnterpriseServiceLevelReport: Identifiable, Hashable {
    let surface: EnterpriseSurface
    let metricClass: EnterpriseServiceLevelClass
    let sampleCount: Int
    let successRate: Double
    let p50Milliseconds: Int
    let p95Milliseconds: Int
    let p99Milliseconds: Int

    var id: String {
        "\(surface.rawValue)-\(metricClass.rawValue)"
    }
}

struct EnterpriseServiceLevelReportBuilder {
    private struct ReportGroupKey: Hashable {
        let surface: EnterpriseSurface
        let metricClass: EnterpriseServiceLevelClass
    }

    func build(from samples: [EnterpriseLatencySample]) -> [EnterpriseServiceLevelReport] {
        let grouped = Dictionary(grouping: samples) {
            ReportGroupKey(surface: $0.surface, metricClass: $0.metricClass)
        }
        return grouped.map { key, values in
            let durations = values.map { $0.durationMilliseconds }.sorted()
            let successes = values.filter(\.success).count
            return EnterpriseServiceLevelReport(
                surface: key.surface,
                metricClass: key.metricClass,
                sampleCount: values.count,
                successRate: values.isEmpty ? 0 : Double(successes) / Double(values.count),
                p50Milliseconds: percentile(50, from: durations),
                p95Milliseconds: percentile(95, from: durations),
                p99Milliseconds: percentile(99, from: durations)
            )
        }
        .sorted { lhs, rhs in
            if lhs.surface == rhs.surface {
                return lhs.metricClass.rawValue < rhs.metricClass.rawValue
            }
            return lhs.surface.rawValue < rhs.surface.rawValue
        }
    }

    private func percentile(_ percentile: Int, from sortedValues: [Int]) -> Int {
        guard !sortedValues.isEmpty else { return 0 }
        let index = Int(ceil((Double(percentile) / 100.0) * Double(sortedValues.count))) - 1
        return sortedValues[max(0, min(index, sortedValues.count - 1))]
    }
}

protocol EnterpriseObservabilityRecording {
    func record(_ sample: EnterpriseLatencySample)
    func recentSamples(limit: Int) -> [EnterpriseLatencySample]
}

final class FileEnterpriseObservabilityRecorder: EnterpriseObservabilityRecording {
    private let directoryURL: URL
    private let samplesURL: URL
    private let queue = DispatchQueue(label: "com.climateliberator.enterprise-observability", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/ClimateLiberator/_climateliberator/observability", isDirectory: true)) {
        self.directoryURL = directoryURL
        self.samplesURL = directoryURL.appendingPathComponent("latency-samples.json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func record(_ sample: EnterpriseLatencySample) {
        queue.sync {
            do {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                var current = loadSamples()
                current.append(sample)
                let capped = Array(current.suffix(2_000))
                let data = try encoder.encode(capped)
                try data.write(to: samplesURL, options: .atomic)
            } catch {
                // Enterprise telemetry should never break the main workflow.
            }
        }
    }

    func recentSamples(limit: Int) -> [EnterpriseLatencySample] {
        queue.sync {
            let samples = loadSamples()
            guard limit > 0 else { return samples }
            return Array(samples.suffix(limit))
        }
    }

    private func loadSamples() -> [EnterpriseLatencySample] {
        guard let data = try? Data(contentsOf: samplesURL),
              let decoded = try? decoder.decode([EnterpriseLatencySample].self, from: data) else {
            return []
        }
        return decoded
    }
}

enum EnterpriseArtifactKind: String, Codable, CaseIterable, Hashable {
    case simulation
    case forecast
    case exposure
    case disclosure
}

struct EnterpriseArtifactRecord: Identifiable, Codable, Hashable {
    let id: UUID
    let kind: EnterpriseArtifactKind
    let recordedAt: Date
    let engineLabel: String?
    let runID: String?
    let outputDirectory: String
    let manifestURL: String?
    let artifactURL: String?
    let metadata: [String: String]

    init(id: UUID = UUID(),
         kind: EnterpriseArtifactKind,
         recordedAt: Date = Date(),
         engineLabel: String? = nil,
         runID: String? = nil,
         outputDirectory: String,
         manifestURL: String? = nil,
         artifactURL: String? = nil,
         metadata: [String: String] = [:]) {
        self.id = id
        self.kind = kind
        self.recordedAt = recordedAt
        self.engineLabel = engineLabel
        self.runID = runID
        self.outputDirectory = outputDirectory
        self.manifestURL = manifestURL
        self.artifactURL = artifactURL
        self.metadata = metadata
    }
}

protocol ArtifactRegistryServicing {
    @discardableResult
    func registerSimulationExecution(result: SimulationEngineExecutionResult,
                                     request: SimulationEngineRequest,
                                     correlationID: String) throws -> EnterpriseArtifactRecord
    func loadRecords(kind: EnterpriseArtifactKind?) -> [EnterpriseArtifactRecord]
}

final class FileArtifactRegistryService: ArtifactRegistryServicing {
    private let directoryURL: URL
    private let registryURL: URL
    private let queue = DispatchQueue(label: "com.climateliberator.enterprise-artifact-registry", qos: .utility)
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directoryURL: URL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Documents/ClimateLiberator/_climateliberator/artifact-registry", isDirectory: true)) {
        self.directoryURL = directoryURL
        self.registryURL = directoryURL.appendingPathComponent("artifact-registry.json", isDirectory: false)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    func registerSimulationExecution(result: SimulationEngineExecutionResult,
                                     request: SimulationEngineRequest,
                                     correlationID: String) throws -> EnterpriseArtifactRecord {
        try queue.sync {
            try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
            var records = loadAllRecords()
            let runID = result.runArtifactURL?.deletingPathExtension().lastPathComponent
            let record = EnterpriseArtifactRecord(
                kind: .simulation,
                engineLabel: result.engineLabel,
                runID: runID,
                outputDirectory: request.outputFolder,
                manifestURL: result.outputManifestURL?.path,
                artifactURL: result.runArtifactURL?.path,
                metadata: [
                    "correlation_id": correlationID,
                    "engine_mode": result.mode.rawValue,
                    "termination_status": String(result.terminationStatus),
                    "simulator_code": request.simulatorCode
                ]
            )

            records.removeAll {
                $0.kind == .simulation &&
                $0.outputDirectory == record.outputDirectory &&
                $0.runID == record.runID &&
                $0.manifestURL == record.manifestURL
            }
            records.append(record)
            let data = try encoder.encode(records.sorted { $0.recordedAt < $1.recordedAt })
            try data.write(to: registryURL, options: .atomic)
            return record
        }
    }

    func loadRecords(kind: EnterpriseArtifactKind? = nil) -> [EnterpriseArtifactRecord] {
        queue.sync {
            let records = loadAllRecords()
            guard let kind else { return records }
            return records.filter { $0.kind == kind }
        }
    }

    private func loadAllRecords() -> [EnterpriseArtifactRecord] {
        guard let data = try? Data(contentsOf: registryURL),
              let decoded = try? decoder.decode([EnterpriseArtifactRecord].self, from: data) else {
            return []
        }
        return decoded
    }
}

protocol PortfolioQueryServicing {
    func databaseStatus(at path: String) -> IndiaDatabaseStatusSnapshot
    func nearbyLookup(at path: String, latitude: Double, longitude: Double, radiusMeters: Double) -> IndiaNearbyLookupSnapshot
    func buildOEDExport(at path: String) -> (result: IndiaOEDExportResult?, errorMessage: String?)
}

struct LocalPortfolioQueryService: PortfolioQueryServicing {
    private let repository: IndiaRiskRepository
    private let exporter: IndiaRiskExporting

    init(repository: IndiaRiskRepository = SQLiteIndiaRiskRepository(),
         exporter: IndiaRiskExporting = SQLiteIndiaOEDExportService()) {
        self.repository = repository
        self.exporter = exporter
    }

    func databaseStatus(at path: String) -> IndiaDatabaseStatusSnapshot {
        repository.loadDatabaseStatus(at: path)
    }

    func nearbyLookup(at path: String, latitude: Double, longitude: Double, radiusMeters: Double) -> IndiaNearbyLookupSnapshot {
        repository.loadNearbyBuildings(at: path, latitude: latitude, longitude: longitude, radiusMeters: radiusMeters)
    }

    func buildOEDExport(at path: String) -> (result: IndiaOEDExportResult?, errorMessage: String?) {
        exporter.buildOEDExport(at: path)
    }
}

protocol ForecastArtifactServicing {
    func loadProcessedFeed(near coordinate: CLLocationCoordinate2D, horizon: ForecastHorizon) -> ProcessedForecastFeed?
    func loadBuildSupportFeeds() -> ForecastBuildSupportFeeds
    func loadSnapshotCollections() -> ForecastSnapshotCollections
}

struct LocalForecastArtifactService: ForecastArtifactServicing {
    private let repository: ForecastFeedRepository
    private let evidenceManager: ForecastEvidencePromotionManaging

    init(repository: ForecastFeedRepository = BuildForecastFeedRepository(),
         evidenceManager: ForecastEvidencePromotionManaging = ForecastEvidencePromotionManager(snapshotStore: FileSystemForecastEvidenceSnapshotStore())) {
        self.repository = repository
        self.evidenceManager = evidenceManager
    }

    func loadProcessedFeed(near coordinate: CLLocationCoordinate2D, horizon: ForecastHorizon) -> ProcessedForecastFeed? {
        repository.loadProcessedFeed(near: coordinate, horizon: horizon)
    }

    func loadBuildSupportFeeds() -> ForecastBuildSupportFeeds {
        repository.loadBuildSupportFeeds()
    }

    func loadSnapshotCollections() -> ForecastSnapshotCollections {
        evidenceManager.loadSnapshotCollections()
    }
}

struct DisclosureBundleInventory: Hashable {
    let roots: [URL]
    let runManifestCount: Int
}

protocol DisclosureBundleServicing {
    func discoveryRoots(for outputFolder: String) -> [URL]
    func inventory(for outputFolder: String) -> DisclosureBundleInventory
}

struct LocalDisclosureBundleService: DisclosureBundleServicing {
    private let reviewDiscoveryService: SimulationReviewDiscoveryServicing

    init(reviewDiscoveryService: SimulationReviewDiscoveryServicing = SimulationReviewDiscoveryService()) {
        self.reviewDiscoveryService = reviewDiscoveryService
    }

    func discoveryRoots(for outputFolder: String) -> [URL] {
        reviewDiscoveryService.discoveryRoots(for: outputFolder)
    }

    func inventory(for outputFolder: String) -> DisclosureBundleInventory {
        let roots = discoveryRoots(for: outputFolder)
        let manifestCount = roots.reduce(into: 0) { count, root in
            guard FileManager.default.fileExists(atPath: root.path),
                  let enumerator = FileManager.default.enumerator(at: root,
                                                                 includingPropertiesForKeys: nil,
                                                                 options: [.skipsHiddenFiles]) else {
                return
            }
            for case let url as URL in enumerator where url.lastPathComponent == "run_manifest.json" {
                count += 1
            }
        }
        return DisclosureBundleInventory(roots: roots, runManifestCount: manifestCount)
    }
}

final class EnterpriseObservedSimulationEngineService: SimulationEngineServicing {
    private let base: SimulationEngineServicing
    private let artifactRegistry: ArtifactRegistryServicing
    private let observability: EnterpriseObservabilityRecording

    init(base: SimulationEngineServicing,
         artifactRegistry: ArtifactRegistryServicing,
         observability: EnterpriseObservabilityRecording) {
        self.base = base
        self.artifactRegistry = artifactRegistry
        self.observability = observability
    }

    func cancel() {
        base.cancel()
    }

    func run(request: SimulationEngineRequest,
             onStandardOutput: ((String) -> Void)?,
             onStandardError: ((String) -> Void)?,
             completion: @escaping (Result<SimulationEngineExecutionResult, Error>) -> Void) {
        let submittedAt = Date()
        let correlationID = UUID().uuidString

        observability.record(
            EnterpriseLatencySample(
                surface: .simulation,
                metricClass: .asyncJobSubmission,
                durationMilliseconds: 0,
                success: true,
                correlationID: correlationID,
                metadata: [
                    "engine_mode": request.mode.rawValue,
                    "simulator_code": request.simulatorCode
                ]
            )
        )

        observability.record(
            EnterpriseLatencySample(
                surface: .simulation,
                metricClass: .asyncJobQueueStart,
                durationMilliseconds: 0,
                success: true,
                correlationID: correlationID,
                metadata: [
                    "engine_mode": request.mode.rawValue,
                    "simulator_code": request.simulatorCode
                ]
            )
        )

        base.run(request: request, onStandardOutput: onStandardOutput, onStandardError: onStandardError) { [artifactRegistry, observability] result in
            let durationMilliseconds = max(0, Int(Date().timeIntervalSince(submittedAt) * 1_000))
            switch result {
            case .success(let execution):
                var metadata = [
                    "engine_mode": execution.mode.rawValue,
                    "engine_label": execution.engineLabel,
                    "simulator_code": request.simulatorCode,
                    "termination_status": String(execution.terminationStatus)
                ]

                if let record = try? artifactRegistry.registerSimulationExecution(result: execution,
                                                                                  request: request,
                                                                                  correlationID: correlationID) {
                    metadata["artifact_registry_id"] = record.id.uuidString
                }

                observability.record(
                    EnterpriseLatencySample(
                        surface: .simulation,
                        metricClass: .asyncJobCompletion,
                        durationMilliseconds: durationMilliseconds,
                        success: execution.terminationStatus == 0,
                        correlationID: correlationID,
                        metadata: metadata
                    )
                )

                if execution.outputManifestURL != nil || execution.runArtifactURL != nil {
                    observability.record(
                        EnterpriseLatencySample(
                            surface: .artifactRegistry,
                            metricClass: .artifactGeneration,
                            durationMilliseconds: durationMilliseconds,
                            success: true,
                            correlationID: correlationID,
                            metadata: metadata
                        )
                    )
                }

                completion(.success(execution))
            case .failure(let error):
                observability.record(
                    EnterpriseLatencySample(
                        surface: .simulation,
                        metricClass: .asyncJobCompletion,
                        durationMilliseconds: durationMilliseconds,
                        success: false,
                        correlationID: correlationID,
                        metadata: [
                            "engine_mode": request.mode.rawValue,
                            "simulator_code": request.simulatorCode,
                            "error": error.localizedDescription
                        ]
                    )
                )
                completion(.failure(error))
            }
        }
    }
}

struct ClimateLiberatorEnterprisePlatform {
    let availabilityObjectives: [EnterpriseAvailabilityObjective]
    let serviceLevelObjectives: [EnterpriseServiceLevelObjective]
    let referenceCapacity: EnterpriseCapacityTarget
    let observability: EnterpriseObservabilityRecording
    let artifactRegistry: ArtifactRegistryServicing
    let portfolioQueries: PortfolioQueryServicing
    let forecastArtifacts: ForecastArtifactServicing
    let disclosureBundles: DisclosureBundleServicing
    let simulationEngine: SimulationEngineServicing

    static func localDefault(baseSimulationEngine: SimulationEngineServicing = HybridSimulationEngineAdapter()) -> ClimateLiberatorEnterprisePlatform {
        let observability = FileEnterpriseObservabilityRecorder()
        let artifactRegistry = FileArtifactRegistryService()
        return ClimateLiberatorEnterprisePlatform(
            availabilityObjectives: EnterpriseObjectiveCatalog.availabilityObjectives,
            serviceLevelObjectives: EnterpriseObjectiveCatalog.serviceLevelObjectives,
            referenceCapacity: EnterpriseObjectiveCatalog.referenceCapacity,
            observability: observability,
            artifactRegistry: artifactRegistry,
            portfolioQueries: LocalPortfolioQueryService(),
            forecastArtifacts: LocalForecastArtifactService(),
            disclosureBundles: LocalDisclosureBundleService(),
            simulationEngine: EnterpriseObservedSimulationEngineService(
                base: baseSimulationEngine,
                artifactRegistry: artifactRegistry,
                observability: observability
            )
        )
    }
}
