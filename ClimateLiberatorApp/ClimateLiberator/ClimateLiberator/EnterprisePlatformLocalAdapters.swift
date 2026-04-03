import Foundation

struct LocalEnterpriseDashboardService: EnterpriseDashboardServicing {
    let availabilityObjectives: [EnterpriseAvailabilityObjective]
    let serviceLevelObjectives: [EnterpriseServiceLevelObjective]
    let observability: EnterpriseObservabilityRecording
    let artifactRegistry: ArtifactRegistryServicing
    let disclosureBundles: DisclosureBundleServicing

    func fetchSummary(request: EnterpriseDashboardSummaryRequest) -> EnterpriseDashboardSummaryResponse {
        let samples = observability.recentSamples(limit: request.sampleLimit)
        let reports = EnterpriseServiceLevelReportBuilder().build(from: samples)
        let surfaces = EnterpriseSurface.allCases
        let surfaceReadiness = surfaces.map { surface in
            EnterpriseSurfaceReadiness(
                surface: surface,
                latestReport: reports.first(where: { $0.surface == surface }),
                objectiveCount: serviceLevelObjectives.filter { $0.surface == surface }.count
            )
        }
        let artifacts = artifactRegistry.loadRecords(kind: nil)
        let disclosureInventory = disclosureBundles.inventory(for: request.outputFolder)
        let latestSimulationRecord = artifacts
            .filter { $0.kind == .simulation }
            .sorted { $0.recordedAt > $1.recordedAt }
            .first

        return EnterpriseDashboardSummaryResponse(
            generatedAt: Date(),
            measuredSurfaceCount: Set(reports.map(\.surface)).count,
            totalSurfaceCount: surfaces.count,
            availabilityObjectiveCount: availabilityObjectives.count,
            serviceLevelObjectiveCount: serviceLevelObjectives.count,
            activeArtifactCount: artifacts.count,
            disclosureManifestCount: disclosureInventory.runManifestCount,
            latestSimulationEngineLabel: latestSimulationRecord?.engineLabel,
            surfaceReadiness: surfaceReadiness
        )
    }
}

struct LocalEnterprisePortfolioService: EnterprisePortfolioServicing {
    let base: PortfolioQueryServicing

    func fetchDatabaseStatus(request: EnterprisePortfolioDatabaseStatusRequest) -> EnterprisePortfolioDatabaseStatusResponse {
        EnterprisePortfolioDatabaseStatusResponse(snapshot: base.databaseStatus(at: request.databasePath))
    }

    func fetchNearbyLookup(request: EnterprisePortfolioNearbyLookupRequest) -> EnterprisePortfolioNearbyLookupResponse {
        EnterprisePortfolioNearbyLookupResponse(
            snapshot: base.nearbyLookup(
                at: request.databasePath,
                latitude: request.latitude,
                longitude: request.longitude,
                radiusMeters: request.radiusMeters
            )
        )
    }

    func exportOED(request: EnterprisePortfolioOEDExportRequest) -> EnterprisePortfolioOEDExportResponse {
        let export = base.buildOEDExport(at: request.databasePath)
        return EnterprisePortfolioOEDExportResponse(result: export.result, errorMessage: export.errorMessage)
    }
}

struct LocalEnterpriseForecastService: EnterpriseForecastServicing {
    let base: ForecastArtifactServicing

    func fetchProcessedFeed(request: EnterpriseForecastFeedRequest) -> EnterpriseForecastFeedResponse {
        EnterpriseForecastFeedResponse(feed: base.loadProcessedFeed(near: request.coordinate, horizon: request.horizon))
    }

    func fetchSupportFeeds(request: EnterpriseForecastSupportFeedsRequest) -> EnterpriseForecastSupportFeedsResponse {
        EnterpriseForecastSupportFeedsResponse(feeds: base.loadBuildSupportFeeds())
    }

    func fetchSnapshots(request: EnterpriseForecastSnapshotsRequest) -> EnterpriseForecastSnapshotsResponse {
        EnterpriseForecastSnapshotsResponse(collections: base.loadSnapshotCollections())
    }
}

struct LocalEnterpriseSimulationStatusService: EnterpriseSimulationStatusServicing {
    let artifactRegistry: ArtifactRegistryServicing

    func acknowledgeSubmission(request: EnterpriseSimulationSubmissionRequest) -> EnterpriseSimulationSubmissionResponse {
        let correlationID = request.correlationID ?? UUID().uuidString
        return EnterpriseSimulationSubmissionResponse(
            correlationID: correlationID,
            acceptedAt: Date(),
            mode: request.engineRequest.mode,
            engineLabel: request.engineRequest.mode.label
        )
    }

    func fetchStatus(request: EnterpriseSimulationStatusRequest) -> EnterpriseSimulationStatusResponse {
        let record = artifactRegistry.loadRecords(kind: .simulation)
            .filter { record in
                if let correlationID = request.correlationID,
                   record.metadata["correlation_id"] != correlationID {
                    return false
                }
                if let runID = request.runID,
                   record.runID != runID {
                    return false
                }
                if let outputDirectory = request.outputDirectory,
                   record.outputDirectory != outputDirectory {
                    return false
                }
                return true
            }
            .sorted { $0.recordedAt > $1.recordedAt }
            .first

        guard let record else {
            return EnterpriseSimulationStatusResponse(
                status: .unknown,
                engineLabel: nil,
                runID: request.runID,
                outputDirectory: request.outputDirectory,
                outputManifestURL: nil,
                artifactURL: nil,
                lastUpdatedAt: nil,
                correlationID: request.correlationID,
                metadata: [:]
            )
        }

        let terminationStatus = Int(record.metadata["termination_status"] ?? "")
        let status: EnterpriseSimulationJobStatus
        if let terminationStatus {
            status = terminationStatus == 0 ? .completed : .failed
        } else {
            status = .completed
        }

        return EnterpriseSimulationStatusResponse(
            status: status,
            engineLabel: record.engineLabel,
            runID: record.runID,
            outputDirectory: record.outputDirectory,
            outputManifestURL: record.manifestURL,
            artifactURL: record.artifactURL,
            lastUpdatedAt: record.recordedAt,
            correlationID: record.metadata["correlation_id"] ?? request.correlationID,
            metadata: record.metadata
        )
    }
}

struct LocalEnterpriseArtifactManifestService: EnterpriseArtifactManifestServicing {
    let artifactRegistry: ArtifactRegistryServicing

    func fetchManifests(request: EnterpriseArtifactManifestRequest) -> EnterpriseArtifactManifestResponse {
        var records = artifactRegistry.loadRecords(kind: request.kind)
        if let runID = request.runID {
            records = records.filter { $0.runID == runID }
        }
        if let outputDirectory = request.outputDirectory {
            records = records.filter { $0.outputDirectory == outputDirectory }
        }
        records.sort { $0.recordedAt > $1.recordedAt }
        if request.latestOnly, let latest = records.first {
            records = [latest]
        }
        return EnterpriseArtifactManifestResponse(generatedAt: Date(), records: records)
    }
}

struct LocalEnterpriseDisclosureBundleClient: EnterpriseDisclosureBundleClientServicing {
    let base: DisclosureBundleServicing

    func fetchBundles(request: EnterpriseDisclosureBundleRequest) -> EnterpriseDisclosureBundleResponse {
        EnterpriseDisclosureBundleResponse(inventory: base.inventory(for: request.outputFolder))
    }
}
