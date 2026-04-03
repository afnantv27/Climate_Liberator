import XCTest
import CoreLocation
import SQLite3
@testable import ClimateLiberator

@MainActor
final class ClimateLiberatorTests: XCTestCase {
    func testRunConfigurationRoundTrip() throws {
        let service = SimulationRunConfigService()
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
            numberOfSimulations: 4,
            numberOfThreads: 8,
            seed: 123,
            selectedScenarioID: nil,
            scenarioName: "Baseline",
            tcfdScenarioLabel: "Board-ready baseline",
            scenarioPathway: "SSP2-4.5",
            scenarioHorizon: "0-3 years"
        )

        let data = try service.exportData(for: document)
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).appendingPathExtension("json")
        try data.write(to: tempURL)
        let decoded = try service.importDocument(from: tempURL)

        XCTAssertEqual(decoded.hazardType, "wildfire")
        XCTAssertEqual(decoded.binaryPath, document.binaryPath)
        XCTAssertEqual(decoded.inputFolder, document.inputFolder)
        XCTAssertEqual(decoded.outputFolder, document.outputFolder)
        XCTAssertEqual(decoded.scenarioName, document.scenarioName)
        XCTAssertEqual(decoded.tcfdScenarioLabel, document.tcfdScenarioLabel)
        XCTAssertEqual(decoded.scenarioPathway, document.scenarioPathway)
        XCTAssertEqual(decoded.scenarioHorizon, document.scenarioHorizon)
    }

    func testReviewDiscoveryRootsPreferClimateLiberatorBundleDirectory() {
        let service = SimulationReviewDiscoveryService()
        let outputRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleRoot = outputRoot.appendingPathComponent("_climateliberator", isDirectory: true)
        try? FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)

        let roots = service.discoveryRoots(for: outputRoot.path)
        XCTAssertEqual(roots, [bundleRoot])
    }

    func testForecastEvidencePromotionSeparatesExecutiveAndDisclosure() throws {
        let snapshotStore = InMemoryForecastSnapshotStore()
        let manager = ForecastEvidencePromotionManager(snapshotStore: snapshotStore)
        let context = ForecastSnapshotContext(
            providerID: "processed_build",
            providerLabel: "Processed Build Feed",
            sourceMode: .processedFeed,
            horizon: .shortTerm,
            confidence: .high,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_000),
            validFrom: Date(timeIntervalSince1970: 1_700_000_000),
            validTo: Date(timeIntervalSince1970: 1_700_003_600),
            locationLabel: "Bengaluru, India",
            coordinate: .init(latitude: 12.9716, longitude: 77.5946),
            statusSummary: "Processed feed active",
            weatherCards: [
                ForecastMetricCard(id: "temp", title: "Mean Temperature", value: "27 C", detail: "Mean")
            ],
            airQualityCards: []
        )

        _ = try manager.persistOperationalSnapshot(from: context)
        let executive = try manager.promoteSnapshot(from: context, to: .executiveEligible)
        XCTAssertEqual(executive.executiveEligibleSnapshots.count, 1)
        XCTAssertEqual(executive.disclosureEligibleSnapshots.count, 0)

        let disclosure = try manager.promoteSnapshot(from: context, to: .disclosureEligible)
        XCTAssertEqual(disclosure.executiveEligibleSnapshots.count, 2)
        XCTAssertEqual(disclosure.disclosureEligibleSnapshots.count, 1)
    }

    func testTCFDWorkflowPolicyRequiresApprovalEvidenceBeforeApproval() {
        let policy = TCFDReviewWorkflowPolicy()
        let record = makeBoardReadyReviewRecord()

        let readyForBoardIssues = policy.readyForBoardIssues(for: record, comparisonIssues: [])
        XCTAssertTrue(readyForBoardIssues.isEmpty)

        let issues = policy.approvalIssues(for: record, readyForBoardIssues: readyForBoardIssues)
        XCTAssertTrue(issues.contains("Approval evidence is incomplete."))
        XCTAssertTrue(issues.contains("Approved-at timestamp is missing."))
    }

    func testTCFDWorkflowPolicyFlagsIncompleteThresholdBreachActions() {
        let policy = TCFDReviewWorkflowPolicy()
        var record = makeBoardReadyReviewRecord()
        record.thresholds = ThresholdEvaluationSummary(
            status: .breached,
            totalTargets: 1,
            breachedCount: 1,
            nearLimitCount: 0,
            evaluations: [
                ThresholdMetricEvaluation(
                    targetBandID: UUID(uuidString: "00000000-0000-0000-0000-000000000111"),
                    metricName: "Burn Probability",
                    observedValue: 0.32,
                    observedDisplayValue: "0.32",
                    thresholdDisplayValue: "0.20",
                    status: .breached
                )
            ],
            evaluatedAt: Date(timeIntervalSince1970: 1_700_005_400)
        )
        record.thresholdBreachActions = [
            ThresholdBreachAction(
                metricName: "Burn Probability",
                breachSummary: "Observed burn probability exceeded the target band.",
                businessImpactSummary: "",
                responseType: .mitigate,
                actionOwner: nil,
                targetDate: nil,
                status: .open,
                managementRationale: ""
            )
        ]

        let issues = policy.thresholdBreachWorkflowIssues(for: record, requireRationale: true)
        XCTAssertTrue(issues.contains("Assign an owner for the Burn Probability breach action."))
        XCTAssertTrue(issues.contains("Set a target date for the Burn Probability breach action."))
        XCTAssertTrue(issues.contains("Summarize business impact for the Burn Probability breach action."))
        XCTAssertTrue(issues.contains("Add management rationale for the Burn Probability breach action."))
    }

    func testOEDImportServiceBuildsCanonicalArtifactFromFolderPackage() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let locationURL = tempRoot.appendingPathComponent("location.csv")
        let accountURL = tempRoot.appendingPathComponent("account.csv")
        let artifactDirectory = tempRoot.appendingPathComponent("artifacts", isDirectory: true)

        try """
        LocID,PerilID,Latitude,Longitude,TIV_Building,TIV_Contents,CurrencyCode,OccupancyCode,ConstructionCode,AssetName,AccNumber
        LOC-001,WF,12.9716,77.5946,1500000,250000,INR,UTILITY,RC,Substation Alpha,ACC-001
        LOC-002,WF,13.0827,80.2707,2200000,400000,INR,UTILITY,RC,Substation Beta,ACC-002
        """.write(to: locationURL, atomically: true, encoding: .utf8)

        try """
        AccNumber,AccName,CurrencyCode
        ACC-001,Utility South,INR
        ACC-002,Utility East,INR
        """.write(to: accountURL, atomically: true, encoding: .utf8)

        let service = OEDExposureImportService(
            artifactDirectory: artifactDirectory.path,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        let artifact = try service.importOEDPackage(from: tempRoot.path)

        XCTAssertEqual(artifact.summary.locationCount, 2)
        XCTAssertEqual(artifact.summary.accountCount, 2)
        XCTAssertEqual(artifact.summary.perilCodes, ["WF"])
        XCTAssertEqual(artifact.summary.currencyCodes, ["INR"])
        XCTAssertEqual(artifact.summary.geocodedLocationCount, 2)
        XCTAssertEqual(artifact.summary.financialLocationCount, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: artifact.artifactPath))
    }

    func testOEDImportServiceRejectsMissingRequiredLocationColumns() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let locationURL = tempRoot.appendingPathComponent("location.csv")

        try """
        Latitude,Longitude,AssetName
        12.9716,77.5946,Substation Alpha
        """.write(to: locationURL, atomically: true, encoding: .utf8)

        let service = OEDExposureImportService(
            artifactDirectory: tempRoot.appendingPathComponent("artifacts").path,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )

        XCTAssertThrowsError(try service.importOEDPackage(from: locationURL.path)) { error in
            XCTAssertTrue(error.localizedDescription.contains("missing required column"))
        }
    }

    func testExposureArtifactLoaderAndOverviewUseLatestPersistedImport() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let artifactsURL = tempRoot.appendingPathComponent("artifacts", isDirectory: true)
        let packageA = tempRoot.appendingPathComponent("package-a", isDirectory: true)
        let packageB = tempRoot.appendingPathComponent("package-b", isDirectory: true)
        try FileManager.default.createDirectory(at: packageA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: packageB, withIntermediateDirectories: true)

        try """
        LocID,PerilID,Latitude,Longitude,TIV_Building,CurrencyCode,OccupancyCode,ConstructionCode,AssetName,AccNumber
        LOC-001,WF,12.9716,77.5946,1000000,INR,UTILITY,RC,Substation Alpha,ACC-001
        """.write(to: packageA.appendingPathComponent("location.csv"), atomically: true, encoding: .utf8)

        try """
        LocID,PerilID,Latitude,Longitude,TIV_Building,TIV_Contents,CurrencyCode,OccupancyCode,ConstructionCode,AssetName,AccNumber
        LOC-010,WF,11.0168,76.9558,2500000,450000,INR,UTILITY,STEEL,Substation Delta,ACC-010
        LOC-011,FL,,,,,INR,WATER,RC,Reservoir East,ACC-010
        """.write(to: packageB.appendingPathComponent("location.csv"), atomically: true, encoding: .utf8)

        let serviceA = OEDExposureImportService(
            artifactDirectory: artifactsURL.path,
            now: { Date(timeIntervalSince1970: 1_700_000_000) }
        )
        let serviceB = OEDExposureImportService(
            artifactDirectory: artifactsURL.path,
            now: { Date(timeIntervalSince1970: 1_700_000_100) }
        )

        _ = try serviceA.importOEDPackage(from: packageA.path)
        _ = try serviceB.importOEDPackage(from: packageB.path)

        let loader = FileExposureImportArtifactLoader(artifactDirectory: artifactsURL.path)
        let latest = try loader.loadLatestPersistedImport()
        let overview = latest.map { ExposurePortfolioOverviewBuilder().makeOverview(from: $0) }

        XCTAssertEqual(latest?.artifact.summary.locationCount, 2)
        XCTAssertEqual(latest?.portfolio.locations.count, 2)
        XCTAssertEqual(overview?.locationCount, 2)
        XCTAssertEqual(overview?.geocodedLocationCount, 1)
        XCTAssertEqual(overview?.currencyCodes, ["INR"])
        XCTAssertEqual(overview?.perilMix.first?.code, "FL")
        XCTAssertEqual(overview?.perilMix.first?.count, 1)
        XCTAssertEqual(overview?.occupancyMix.first?.code, "UTILITY")
        XCTAssertEqual(overview?.sampleLocations.first?.name, "Substation Delta")
    }

    func testEnterpriseObjectiveCatalogDefinesReferenceSLOsAndCapacity() {
        let objectives = EnterpriseObjectiveCatalog.serviceLevelObjectives
        let availability = EnterpriseObjectiveCatalog.availabilityObjectives
        let capacity = EnterpriseObjectiveCatalog.referenceCapacity

        XCTAssertTrue(objectives.contains {
            $0.surface == .dashboard &&
            $0.metricClass == .interactiveRequest &&
            $0.percentile == .p95 &&
            $0.targetMilliseconds == 800
        })
        XCTAssertTrue(objectives.contains {
            $0.surface == .simulation &&
            $0.metricClass == .asyncJobSubmission &&
            $0.percentile == .p95 &&
            $0.targetMilliseconds == 1_000
        })
        XCTAssertTrue(availability.contains {
            $0.surface == .platform && $0.targetPercent == 99.9
        })
        XCTAssertEqual(capacity.concurrentAnalysts, 50)
        XCTAssertEqual(capacity.committedAssetCount, 100_000)
        XCTAssertEqual(capacity.validatedStretchDisclosureBundles, 2_000)
    }

    func testEnterpriseServiceLevelReportBuilderComputesPercentiles() {
        let samples: [EnterpriseLatencySample] = [
            .init(surface: .simulation, metricClass: .asyncJobCompletion, durationMilliseconds: 100, success: true),
            .init(surface: .simulation, metricClass: .asyncJobCompletion, durationMilliseconds: 200, success: true),
            .init(surface: .simulation, metricClass: .asyncJobCompletion, durationMilliseconds: 300, success: false),
            .init(surface: .simulation, metricClass: .asyncJobCompletion, durationMilliseconds: 400, success: true),
            .init(surface: .simulation, metricClass: .asyncJobCompletion, durationMilliseconds: 500, success: true)
        ]

        let report = EnterpriseServiceLevelReportBuilder().build(from: samples).first

        XCTAssertEqual(report?.sampleCount, 5)
        XCTAssertEqual(report?.p50Milliseconds, 300)
        XCTAssertEqual(report?.p95Milliseconds, 500)
        XCTAssertEqual(report?.p99Milliseconds, 500)
        XCTAssertNotNil(report)
        XCTAssertEqual(report?.successRate ?? 0, 0.8, accuracy: 0.0001)
    }

    func testIndiaPortfolioRollupServiceCachesLoadedSnapshots() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        let databaseURL = tempRoot.appendingPathComponent("india_rollup.db")
        FileManager.default.createFile(atPath: databaseURL.path, contents: Data(), attributes: nil)
        let modifiedAt = try? databaseURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate

        let expectedSnapshot = IndiaPortfolioRollupSnapshot(
            databasePath: databaseURL.path,
            databaseModifiedAt: modifiedAt,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_100),
            buildingCount: 2,
            portfolioSummary: IndiaPortfolioRiskSummary(
                assessedAssets: 2,
                highRiskAssets: 1,
                mediumRiskAssets: 1,
                lowRiskAssets: 0,
                uniqueScenarios: 1,
                latestAssessmentAt: "2026-04-03T00:00:00Z"
            ),
            topRiskConcentrations: [
                IndiaRiskConcentration(id: "MH", stateCode: "MH", assetCount: 2, highRiskCount: 1, averageBurnProbability: 0.61)
            ],
            hierarchySummaries: [
                IndiaPortfolioHierarchySummary(
                    id: "state:MH:*",
                    level: "state",
                    stateCode: "MH",
                    districtName: nil,
                    assetCount: 2,
                    highRiskCount: 1,
                    mediumRiskCount: 1,
                    lowRiskCount: 0,
                    averageBurnProbability: 0.61
                )
            ],
            statusMessage: "Cached summary"
        )

        let loader = CountingIndiaPortfolioRollupLoader(snapshot: expectedSnapshot)
        let cache = InMemoryIndiaPortfolioRollupCache()
        let service = IndiaPortfolioRollupService(loader: loader, cacheStore: cache)

        let first = service.loadPortfolioRollupSnapshot(at: databaseURL.path)
        let second = service.loadPortfolioRollupSnapshot(at: databaseURL.path)

        XCTAssertEqual(loader.loadCount, 1)
        XCTAssertEqual(first, expectedSnapshot)
        XCTAssertEqual(second, expectedSnapshot)
    }

    func testSQLiteIndiaPortfolioRollupSnapshotLoaderBuildsHierarchySummaries() throws {
        let databaseURL = try makeIndiaPortfolioRollupDatabase()
        let loader = SQLiteIndiaPortfolioRollupSnapshotLoader()
        let snapshot = loader.loadPortfolioRollupSnapshot(at: databaseURL.path, modifiedAt: Date(timeIntervalSince1970: 1_700_000_000))

        XCTAssertEqual(snapshot.buildingCount, 4)
        XCTAssertEqual(snapshot.portfolioSummary.assessedAssets, 4)
        XCTAssertEqual(snapshot.portfolioSummary.highRiskAssets, 2)
        XCTAssertEqual(snapshot.portfolioSummary.mediumRiskAssets, 1)
        XCTAssertEqual(snapshot.portfolioSummary.lowRiskAssets, 1)
        XCTAssertEqual(snapshot.portfolioSummary.uniqueScenarios, 2)
        XCTAssertEqual(snapshot.portfolioSummary.latestAssessmentAt, "2026-04-03T00:00:00Z")
        XCTAssertEqual(snapshot.topRiskConcentrations.count, 2)
        XCTAssertTrue(snapshot.topRiskConcentrations.contains { $0.stateCode == "GJ" && $0.assetCount == 2 && $0.highRiskCount == 1 })
        XCTAssertTrue(snapshot.topRiskConcentrations.contains { $0.stateCode == "MH" && $0.assetCount == 2 && $0.highRiskCount == 1 })
        XCTAssertTrue(snapshot.hierarchySummaries.contains { $0.level == "state" && $0.stateCode == "MH" })
        XCTAssertTrue(snapshot.hierarchySummaries.contains { $0.level == "district" && $0.stateCode == "MH" && $0.districtName == "Mumbai" })
        XCTAssertTrue(snapshot.hierarchySummaries.contains {
            $0.level == "state" &&
            $0.stateCode == "MH" &&
            $0.assetCount == 2 &&
            $0.highRiskCount == 1 &&
            $0.mediumRiskCount == 1 &&
            $0.lowRiskCount == 0
        })
        XCTAssertTrue(snapshot.hierarchySummaries.contains {
            $0.level == "district" &&
            $0.stateCode == "GJ" &&
            $0.districtName == "Ahmedabad" &&
            $0.assetCount == 1 &&
            $0.highRiskCount == 1
        })
        XCTAssertTrue(snapshot.statusMessage.contains("cached rollups") || snapshot.statusMessage.contains("portfolio database"))
    }

    func testIndiaRiskStoreRefreshUsesHierarchyAwareRollupSnapshot() {
        let databasePath = "/tmp/india-risk-rollup-\(UUID().uuidString).db"
        let repository = StubIndiaRiskRepository(
            databaseStatus: IndiaDatabaseStatusSnapshot(
                databaseConnected: true,
                schemaReady: true,
                buildingCount: 4,
                portfolioSummary: .empty,
                topRiskConcentrations: [],
                statusMessage: "Database connected. 4 buildings available for site screening."
            )
        )
        let demoFeedService = StubIndiaDemoFeedService(snapshot: IndiaDemoPortfolioFeedSnapshot(overview: nil, comparison: nil, trust: nil))
        let expectedRollup = IndiaPortfolioRollupSnapshot(
            databasePath: databasePath,
            databaseModifiedAt: nil,
            generatedAt: Date(timeIntervalSince1970: 1_700_000_200),
            buildingCount: 4,
            portfolioSummary: IndiaPortfolioRiskSummary(
                assessedAssets: 4,
                highRiskAssets: 2,
                mediumRiskAssets: 1,
                lowRiskAssets: 1,
                uniqueScenarios: 2,
                latestAssessmentAt: "2026-04-03T00:00:00Z"
            ),
            topRiskConcentrations: [
                IndiaRiskConcentration(id: "MH", stateCode: "MH", assetCount: 2, highRiskCount: 1, averageBurnProbability: 0.52)
            ],
            hierarchySummaries: [
                IndiaPortfolioHierarchySummary(
                    id: "state:MH:*",
                    level: "state",
                    stateCode: "MH",
                    districtName: nil,
                    assetCount: 2,
                    highRiskCount: 1,
                    mediumRiskCount: 1,
                    lowRiskCount: 0,
                    averageBurnProbability: 0.52
                )
            ],
            statusMessage: "India portfolio database is connected. 4 assessed assets are now served through cached rollups."
        )
        let rollupService = StubIndiaPortfolioRollupService(snapshot: expectedRollup)
        let exportService = StubIndiaRiskExportService()
        let store = IndiaRiskStore(
            databasePath: databasePath,
            repository: repository,
            exportService: exportService,
            demoFeedService: demoFeedService,
            rollupService: rollupService
        )

        let expectation = expectation(description: "rollup refresh completes")
        store.refreshDatabaseStatus()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            XCTAssertEqual(store.buildingCount, 4)
            XCTAssertEqual(store.portfolioSummary, expectedRollup.portfolioSummary)
            XCTAssertEqual(store.topRiskConcentrations, expectedRollup.topRiskConcentrations)
            XCTAssertEqual(store.portfolioHierarchySummaries, expectedRollup.hierarchySummaries)
            XCTAssertEqual(store.statusMessage, expectedRollup.statusMessage)
            XCTAssertEqual(rollupService.loadCount, 1)
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2.0)
    }

    func testDisclosureBundleServiceCountsRunManifestsInsideClimateLiberatorBundleRoot() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleRoot = tempRoot.appendingPathComponent("_climateliberator", isDirectory: true)
        let runOne = bundleRoot.appendingPathComponent("run-001", isDirectory: true)
        let runTwo = bundleRoot.appendingPathComponent("run-002", isDirectory: true)
        try FileManager.default.createDirectory(at: runOne, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runTwo, withIntermediateDirectories: true)
        try "{}".write(to: runOne.appendingPathComponent("run_manifest.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: runTwo.appendingPathComponent("run_manifest.json"), atomically: true, encoding: .utf8)

        let service = LocalDisclosureBundleService()
        let inventory = service.inventory(for: tempRoot.path)

        XCTAssertEqual(inventory.roots, [bundleRoot])
        XCTAssertEqual(inventory.runManifestCount, 2)
    }

    func testObservedSimulationEngineRecordsTelemetryAndArtifacts() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let telemetryRoot = tempRoot.appendingPathComponent("observability", isDirectory: true)
        let registryRoot = tempRoot.appendingPathComponent("artifact-registry", isDirectory: true)
        let outputRoot = tempRoot.appendingPathComponent("output", isDirectory: true)
        try? FileManager.default.createDirectory(at: outputRoot, withIntermediateDirectories: true)

        let manifestURL = outputRoot.appendingPathComponent("output_manifest.json")
        let runArtifactURL = outputRoot.appendingPathComponent("run_artifact.json")
        try? "{}".write(to: manifestURL, atomically: true, encoding: .utf8)
        try? "{}".write(to: runArtifactURL, atomically: true, encoding: .utf8)

        let recorder = FileEnterpriseObservabilityRecorder(directoryURL: telemetryRoot)
        let registry = FileArtifactRegistryService(directoryURL: registryRoot)
        let engine = EnterpriseObservedSimulationEngineService(
            base: FakeSimulationEngineService(
                result: .success(
                    SimulationEngineExecutionResult(
                        mode: .climateLiberatorRuntimePreview,
                        engineLabel: "Climate Liberator Runtime preview",
                        terminationStatus: 0,
                        stdout: "native ok",
                        stderr: "",
                        outputManifestURL: manifestURL,
                        runManifestURL: manifestURL,
                        runArtifactURL: runArtifactURL,
                        artifactIndexURL: outputRoot.appendingPathComponent("artifact_index.json")
                    )
                )
            ),
            artifactRegistry: registry,
            observability: recorder
        )

        let expectation = expectation(description: "simulation completes")
        let request = SimulationEngineRequest(
            mode: .climateLiberatorRuntimePreview,
            legacyBinaryPath: "/tmp/Cell2Fire",
            simulatorCode: "S",
            inputFolder: "/tmp/input",
            outputFolder: outputRoot.path,
            includeROS: true,
            weatherPeriodMinutes: 60,
            firePeriodLength: 60,
            outputFormat: .asc,
            numberOfSimulations: 1,
            numberOfThreads: 2,
            seed: 42
        )

        engine.run(request: request, onStandardOutput: nil, onStandardError: nil) { result in
            switch result {
            case .success(let execution):
                XCTAssertEqual(execution.engineLabel, "Climate Liberator Runtime preview")
            case .failure(let error):
                XCTFail("Observed simulation wrapper returned failure: \(error.localizedDescription)")
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 2)

        let samples = recorder.recentSamples(limit: 10)
        XCTAssertTrue(samples.contains { $0.metricClass == .asyncJobSubmission })
        XCTAssertTrue(samples.contains { $0.metricClass == .asyncJobQueueStart })
        XCTAssertTrue(samples.contains { $0.metricClass == .asyncJobCompletion && $0.success })
        XCTAssertTrue(samples.contains { $0.metricClass == .artifactGeneration && $0.success })

        let records = registry.loadRecords(kind: .simulation)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.engineLabel, "Climate Liberator Runtime preview")
        XCTAssertEqual(records.first?.outputDirectory, outputRoot.path)
    }

    func testEnterprisePlatformBuildsReadinessSummaryFromTelemetryAndArtifacts() {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputRoot = tempRoot.appendingPathComponent("output", isDirectory: true)
        let climateRoot = outputRoot.appendingPathComponent("_climateliberator", isDirectory: true)
        let runRoot = climateRoot.appendingPathComponent("run-001", isDirectory: true)
        try? FileManager.default.createDirectory(at: runRoot, withIntermediateDirectories: true)
        try? "{}".write(to: runRoot.appendingPathComponent("run_manifest.json"), atomically: true, encoding: .utf8)

        let recorder = InMemoryEnterpriseObservabilityRecorder(samples: [
            EnterpriseLatencySample(surface: .dashboard, metricClass: .interactiveRequest, durationMilliseconds: 320, success: true),
            EnterpriseLatencySample(surface: .simulation, metricClass: .asyncJobCompletion, durationMilliseconds: 1_900, success: true)
        ])
        let registry = InMemoryArtifactRegistryService(records: [
            EnterpriseArtifactRecord(kind: .simulation,
                                     engineLabel: "Climate Liberator Runtime preview",
                                     runID: "run-001",
                                     outputDirectory: outputRoot.path,
                                     manifestURL: runRoot.appendingPathComponent("run_manifest.json").path,
                                     artifactURL: nil)
        ])
        let portfolioQueries = LocalPortfolioQueryService()
        let forecastArtifacts = LocalForecastArtifactService(repository: EmptyForecastFeedRepository(),
                                                             evidenceManager: ForecastEvidencePromotionManager(snapshotStore: InMemoryForecastSnapshotStore()))
        let disclosureBundles = LocalDisclosureBundleService()
        let platform = ClimateLiberatorEnterprisePlatform(
            availabilityObjectives: EnterpriseObjectiveCatalog.availabilityObjectives,
            serviceLevelObjectives: EnterpriseObjectiveCatalog.serviceLevelObjectives,
            referenceCapacity: EnterpriseObjectiveCatalog.referenceCapacity,
            observability: recorder,
            artifactRegistry: registry,
            portfolioQueries: portfolioQueries,
            forecastArtifacts: forecastArtifacts,
            disclosureBundles: disclosureBundles,
            dashboard: LocalEnterpriseDashboardService(
                availabilityObjectives: EnterpriseObjectiveCatalog.availabilityObjectives,
                serviceLevelObjectives: EnterpriseObjectiveCatalog.serviceLevelObjectives,
                observability: recorder,
                artifactRegistry: registry,
                disclosureBundles: disclosureBundles
            ),
            portfolio: LocalEnterprisePortfolioService(base: portfolioQueries),
            forecast: LocalEnterpriseForecastService(base: forecastArtifacts),
            simulationStatus: LocalEnterpriseSimulationStatusService(artifactRegistry: registry),
            artifactManifests: LocalEnterpriseArtifactManifestService(artifactRegistry: registry),
            disclosure: LocalEnterpriseDisclosureBundleClient(base: disclosureBundles),
            simulationEngine: FakeSimulationEngineService(result: .failure(NSError(domain: "test", code: 1)))
        )

        let summary = platform.readinessSummary(outputFolder: outputRoot.path)

        XCTAssertEqual(summary.activeArtifactCount, 1)
        XCTAssertEqual(summary.disclosureManifestCount, 1)
        XCTAssertEqual(summary.latestSimulationEngineLabel, "Climate Liberator Runtime preview")
        XCTAssertEqual(summary.measuredSurfaceCount, 2)
        XCTAssertTrue(summary.surfaceReadiness.contains { $0.surface == .dashboard && $0.healthLabel == "Healthy" })
    }

    func testEnterpriseDashboardServiceReturnsExplicitSummaryContract() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outputRoot = tempRoot.appendingPathComponent("output", isDirectory: true)
        let bundleRoot = outputRoot.appendingPathComponent("_climateliberator/run-001", isDirectory: true)
        try FileManager.default.createDirectory(at: bundleRoot, withIntermediateDirectories: true)
        try "{}".write(to: bundleRoot.appendingPathComponent("run_manifest.json"), atomically: true, encoding: .utf8)

        let recorder = InMemoryEnterpriseObservabilityRecorder(samples: [
            EnterpriseLatencySample(surface: .dashboard, metricClass: .interactiveRequest, durationMilliseconds: 280, success: true),
            EnterpriseLatencySample(surface: .artifactRegistry, metricClass: .artifactGeneration, durationMilliseconds: 900, success: true)
        ])
        let registry = InMemoryArtifactRegistryService(records: [
            EnterpriseArtifactRecord(kind: .simulation,
                                     engineLabel: "Climate Liberator Runtime preview",
                                     runID: "run-001",
                                     outputDirectory: outputRoot.path,
                                     manifestURL: bundleRoot.appendingPathComponent("run_manifest.json").path,
                                     artifactURL: bundleRoot.appendingPathComponent("run_artifact.json").path)
        ])

        let service = LocalEnterpriseDashboardService(
            availabilityObjectives: EnterpriseObjectiveCatalog.availabilityObjectives,
            serviceLevelObjectives: EnterpriseObjectiveCatalog.serviceLevelObjectives,
            observability: recorder,
            artifactRegistry: registry,
            disclosureBundles: LocalDisclosureBundleService()
        )

        let response = service.fetchSummary(request: EnterpriseDashboardSummaryRequest(outputFolder: outputRoot.path, sampleLimit: 10))

        XCTAssertEqual(response.activeArtifactCount, 1)
        XCTAssertEqual(response.disclosureManifestCount, 1)
        XCTAssertEqual(response.latestSimulationEngineLabel, "Climate Liberator Runtime preview")
        XCTAssertEqual(response.coverageLabel, "2/7 surfaces measured")
        XCTAssertTrue(response.surfaceReadiness.contains { $0.surface == .dashboard && $0.healthLabel == "Healthy" })
    }

    func testEnterpriseArtifactManifestServiceFiltersLatestSimulationRecord() {
        let oldRecord = EnterpriseArtifactRecord(kind: .simulation,
                                                 recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                                 engineLabel: "Legacy Cell2Fire backend",
                                                 runID: "run-001",
                                                 outputDirectory: "/tmp/output",
                                                 manifestURL: "/tmp/output/old_output_manifest.json",
                                                 artifactURL: "/tmp/output/old_run_artifact.json")
        let newRecord = EnterpriseArtifactRecord(kind: .simulation,
                                                 recordedAt: Date(timeIntervalSince1970: 1_700_000_600),
                                                 engineLabel: "Climate Liberator Runtime preview",
                                                 runID: "run-002",
                                                 outputDirectory: "/tmp/output",
                                                 manifestURL: "/tmp/output/output_manifest.json",
                                                 artifactURL: "/tmp/output/run_artifact.json")
        let registry = InMemoryArtifactRegistryService(records: [oldRecord, newRecord])
        let service = LocalEnterpriseArtifactManifestService(artifactRegistry: registry)

        let response = service.fetchManifests(request: EnterpriseArtifactManifestRequest(kind: .simulation,
                                                                                         outputDirectory: "/tmp/output",
                                                                                         latestOnly: true))

        XCTAssertEqual(response.records.count, 1)
        XCTAssertEqual(response.records.first?.runID, "run-002")
        XCTAssertEqual(response.records.first?.engineLabel, "Climate Liberator Runtime preview")
    }

    func testEnterpriseSimulationStatusServiceInfersStatusFromArtifactRegistry() {
        let registry = InMemoryArtifactRegistryService(records: [
            EnterpriseArtifactRecord(kind: .simulation,
                                     recordedAt: Date(timeIntervalSince1970: 1_700_000_900),
                                     engineLabel: "Climate Liberator Runtime preview",
                                     runID: "run-101",
                                     outputDirectory: "/tmp/output-101",
                                     manifestURL: "/tmp/output-101/output_manifest.json",
                                     artifactURL: "/tmp/output-101/run_artifact.json",
                                     metadata: [
                                        "correlation_id": "corr-101",
                                        "termination_status": "0"
                                     ])
        ])
        let service = LocalEnterpriseSimulationStatusService(artifactRegistry: registry)

        let response = service.fetchStatus(request: EnterpriseSimulationStatusRequest(correlationID: "corr-101"))
        let unknown = service.fetchStatus(request: EnterpriseSimulationStatusRequest(correlationID: "missing"))

        XCTAssertEqual(response.status, .completed)
        XCTAssertEqual(response.runID, "run-101")
        XCTAssertEqual(response.outputManifestURL, "/tmp/output-101/output_manifest.json")
        XCTAssertEqual(response.correlationID, "corr-101")
        XCTAssertEqual(unknown.status, .unknown)
    }

    func testEnterpriseDashboardServiceHonorsSampleLimitInSummaryRequest() {
        let recorder = InMemoryEnterpriseObservabilityRecorder(samples: [
            EnterpriseLatencySample(surface: .dashboard, metricClass: .interactiveRequest, durationMilliseconds: 180, success: true),
            EnterpriseLatencySample(surface: .dashboard, metricClass: .interactiveRequest, durationMilliseconds: 220, success: true),
            EnterpriseLatencySample(surface: .portfolio, metricClass: .interactiveRequest, durationMilliseconds: 260, success: true)
        ])
        let service = LocalEnterpriseDashboardService(
            availabilityObjectives: EnterpriseObjectiveCatalog.availabilityObjectives,
            serviceLevelObjectives: EnterpriseObjectiveCatalog.serviceLevelObjectives,
            observability: recorder,
            artifactRegistry: InMemoryArtifactRegistryService(),
            disclosureBundles: StaticDisclosureBundleService(inventory: DisclosureBundleInventory(roots: [], runManifestCount: 0))
        )

        let response = service.fetchSummary(request: EnterpriseDashboardSummaryRequest(outputFolder: "/tmp/output", sampleLimit: 1))

        XCTAssertEqual(response.measuredSurfaceCount, 1)
        XCTAssertEqual(response.coverageLabel, "1/7 surfaces measured")
        XCTAssertTrue(response.surfaceReadiness.contains {
            $0.surface == .portfolio &&
            $0.latestReport?.sampleCount == 1 &&
            $0.healthLabel == "Healthy"
        })
        XCTAssertTrue(response.surfaceReadiness.contains { $0.surface == .dashboard && $0.healthLabel == "Unmeasured" })
    }

    func testEnterpriseArtifactManifestServiceFiltersByRunIDAndOutputDirectory() {
        let registry = InMemoryArtifactRegistryService(records: [
            EnterpriseArtifactRecord(kind: .simulation,
                                     recordedAt: Date(timeIntervalSince1970: 1_700_000_000),
                                     engineLabel: "Legacy Cell2Fire backend",
                                     runID: "run-001",
                                     outputDirectory: "/tmp/output-a",
                                     manifestURL: "/tmp/output-a/output_manifest.json",
                                     artifactURL: "/tmp/output-a/run_artifact.json"),
            EnterpriseArtifactRecord(kind: .simulation,
                                     recordedAt: Date(timeIntervalSince1970: 1_700_000_600),
                                     engineLabel: "Climate Liberator Runtime preview",
                                     runID: "run-002",
                                     outputDirectory: "/tmp/output-b",
                                     manifestURL: "/tmp/output-b/output_manifest.json",
                                     artifactURL: "/tmp/output-b/run_artifact.json"),
            EnterpriseArtifactRecord(kind: .forecast,
                                     recordedAt: Date(timeIntervalSince1970: 1_700_000_800),
                                     outputDirectory: "/tmp/output-b",
                                     manifestURL: "/tmp/output-b/forecast_overview.json",
                                     artifactURL: nil)
        ])
        let service = LocalEnterpriseArtifactManifestService(artifactRegistry: registry)

        let response = service.fetchManifests(request: EnterpriseArtifactManifestRequest(kind: .simulation,
                                                                                         runID: "run-002",
                                                                                         outputDirectory: "/tmp/output-b"))

        XCTAssertEqual(response.records.count, 1)
        XCTAssertEqual(response.records.first?.runID, "run-002")
        XCTAssertEqual(response.records.first?.outputDirectory, "/tmp/output-b")
        XCTAssertEqual(response.records.first?.manifestURL, "/tmp/output-b/output_manifest.json")
    }

    func testEnterpriseSimulationStatusServiceMarksNonZeroTerminationAsFailed() {
        let registry = InMemoryArtifactRegistryService(records: [
            EnterpriseArtifactRecord(kind: .simulation,
                                     recordedAt: Date(timeIntervalSince1970: 1_700_001_200),
                                     engineLabel: "Climate Liberator Runtime preview",
                                     runID: "run-201",
                                     outputDirectory: "/tmp/output-201",
                                     manifestURL: "/tmp/output-201/output_manifest.json",
                                     artifactURL: "/tmp/output-201/run_artifact.json",
                                     metadata: [
                                        "correlation_id": "corr-201",
                                        "termination_status": "7"
                                     ])
        ])
        let service = LocalEnterpriseSimulationStatusService(artifactRegistry: registry)

        let response = service.fetchStatus(request: EnterpriseSimulationStatusRequest(outputDirectory: "/tmp/output-201"))

        XCTAssertEqual(response.status, .failed)
        XCTAssertEqual(response.runID, "run-201")
        XCTAssertEqual(response.correlationID, "corr-201")
        XCTAssertEqual(response.outputManifestURL, "/tmp/output-201/output_manifest.json")
        XCTAssertEqual(response.artifactURL, "/tmp/output-201/run_artifact.json")
    }

    func testEnterpriseDisclosureBundleClientReturnsInventoryResponse() throws {
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundleRoot = tempRoot.appendingPathComponent("_climateliberator", isDirectory: true)
        let runOne = bundleRoot.appendingPathComponent("run-001", isDirectory: true)
        let runTwo = bundleRoot.appendingPathComponent("run-002", isDirectory: true)
        try FileManager.default.createDirectory(at: runOne, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: runTwo, withIntermediateDirectories: true)
        try "{}".write(to: runOne.appendingPathComponent("run_manifest.json"), atomically: true, encoding: .utf8)
        try "{}".write(to: runTwo.appendingPathComponent("run_manifest.json"), atomically: true, encoding: .utf8)

        let client = LocalEnterpriseDisclosureBundleClient(base: LocalDisclosureBundleService())
        let response = client.fetchBundles(request: EnterpriseDisclosureBundleRequest(outputFolder: tempRoot.path))

        XCTAssertEqual(response.inventory.roots, [bundleRoot])
        XCTAssertEqual(response.inventory.runManifestCount, 2)
    }
}

private final class InMemoryForecastSnapshotStore: ForecastEvidenceSnapshotStore {
    private var snapshots: [ForecastEvidenceSnapshot] = []

    func saveSnapshot(_ snapshot: ForecastEvidenceSnapshot) throws {
        snapshots.removeAll { $0.id == snapshot.id }
        snapshots.append(snapshot)
        snapshots.sort { $0.capturedAt > $1.capturedAt }
    }

    func loadSnapshots() -> [ForecastEvidenceSnapshot] {
        snapshots
    }
}

private struct EmptyForecastFeedRepository: ForecastFeedRepository {
    func loadProcessedFeed(near coordinate: CLLocationCoordinate2D, horizon: ForecastHorizon) -> ProcessedForecastFeed? {
        nil
    }

    func loadBuildSupportFeeds() -> ForecastBuildSupportFeeds {
        ForecastBuildSupportFeeds(overview: nil, providerTrust: nil, warningSummary: nil)
    }
}

private final class InMemoryEnterpriseObservabilityRecorder: EnterpriseObservabilityRecording {
    private(set) var samples: [EnterpriseLatencySample]

    init(samples: [EnterpriseLatencySample] = []) {
        self.samples = samples
    }

    func record(_ sample: EnterpriseLatencySample) {
        samples.append(sample)
    }

    func recentSamples(limit: Int) -> [EnterpriseLatencySample] {
        guard limit > 0 else { return samples }
        return Array(samples.suffix(limit))
    }
}

private final class InMemoryArtifactRegistryService: ArtifactRegistryServicing {
    private(set) var records: [EnterpriseArtifactRecord]

    init(records: [EnterpriseArtifactRecord] = []) {
        self.records = records
    }

    @discardableResult
    func registerSimulationExecution(result: SimulationEngineExecutionResult,
                                     request: SimulationEngineRequest,
                                     correlationID: String) throws -> EnterpriseArtifactRecord {
        let record = EnterpriseArtifactRecord(kind: .simulation,
                                              engineLabel: result.engineLabel,
                                              runID: result.runArtifactURL?.deletingPathExtension().lastPathComponent,
                                              outputDirectory: request.outputFolder,
                                              manifestURL: result.outputManifestURL?.path,
                                              artifactURL: result.runArtifactURL?.path,
                                              metadata: ["correlation_id": correlationID])
        records.append(record)
        return record
    }

    func loadRecords(kind: EnterpriseArtifactKind?) -> [EnterpriseArtifactRecord] {
        guard let kind else { return records }
        return records.filter { $0.kind == kind }
    }
}

private struct StaticDisclosureBundleService: DisclosureBundleServicing {
    let inventory: DisclosureBundleInventory

    func discoveryRoots(for outputFolder: String) -> [URL] {
        inventory.roots
    }

    func inventory(for outputFolder: String) -> DisclosureBundleInventory {
        inventory
    }
}

private struct FakeSimulationEngineService: SimulationEngineServicing {
    let result: Result<SimulationEngineExecutionResult, Error>

    func cancel() {}

    func run(request: SimulationEngineRequest,
             onStandardOutput: ((String) -> Void)?,
             onStandardError: ((String) -> Void)?,
             completion: @escaping (Result<SimulationEngineExecutionResult, Error>) -> Void) {
        completion(result)
    }
}

private struct StubIndiaRiskRepository: IndiaRiskRepository {
    let databaseStatus: IndiaDatabaseStatusSnapshot

    func loadDatabaseStatus(at path: String) -> IndiaDatabaseStatusSnapshot {
        databaseStatus
    }

    func loadNearbyBuildings(at path: String,
                             latitude: Double,
                             longitude: Double,
                             radiusMeters: Double) -> IndiaNearbyLookupSnapshot {
        IndiaNearbyLookupSnapshot(
            buildings: [],
            summary: IndiaBuildingLookupSummary(buildingCount: 0, totalFootprintM2: 0, totalBuiltUpM2: 0),
            statusMessage: "No nearby lookup data."
        )
    }

    func persistWildfireAssessments(databasePath: String,
                                    request: IndiaWildfireRiskLinkRequest,
                                    grid: IndiaWildfireRiskGrid) throws -> IndiaWildfireRiskLinkResult {
        IndiaWildfireRiskLinkResult(candidateCount: 0, storedCount: 0, highRiskCount: 0, mediumRiskCount: 0, lowRiskCount: 0)
    }
}

private struct StubIndiaRiskExportService: IndiaRiskExporting {
    func buildOEDExport(at path: String) -> (result: IndiaOEDExportResult?, errorMessage: String?) {
        (nil, nil)
    }
}

private struct StubIndiaDemoFeedService: IndiaDemoFeedProviding {
    let snapshot: IndiaDemoPortfolioFeedSnapshot

    func loadDemoPortfolioFeeds() -> IndiaDemoPortfolioFeedSnapshot {
        snapshot
    }
}

private final class StubIndiaPortfolioRollupService: IndiaPortfolioRollupServicing {
    private(set) var loadCount = 0
    private let snapshot: IndiaPortfolioRollupSnapshot

    init(snapshot: IndiaPortfolioRollupSnapshot) {
        self.snapshot = snapshot
    }

    func loadPortfolioRollupSnapshot(at path: String) -> IndiaPortfolioRollupSnapshot {
        loadCount += 1
        return snapshot
    }

    func invalidateCache(for path: String) {}
}

private final class CountingIndiaPortfolioRollupLoader: IndiaPortfolioRollupLoading {
    private(set) var loadCount = 0
    private let snapshot: IndiaPortfolioRollupSnapshot

    init(snapshot: IndiaPortfolioRollupSnapshot) {
        self.snapshot = snapshot
    }

    func loadPortfolioRollupSnapshot(at path: String, modifiedAt: Date?) -> IndiaPortfolioRollupSnapshot {
        loadCount += 1
        return snapshot
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

private func makeIndiaPortfolioRollupDatabase() throws -> URL {
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

private func makeBoardReadyReviewRecord() -> TCFDReviewRecord {
    let preparedAt = Date(timeIntervalSince1970: 1_700_000_000)
    let submittedAt = Date(timeIntervalSince1970: 1_700_003_600)
    let reviewedAt = Date(timeIntervalSince1970: 1_700_007_200)
    let preparedBy = PersonRef(name: "A. Analyst", title: "Climate Risk Analyst", email: "analyst@climateliberator.test")
    let riskOwner = PersonRef(name: "R. Owner", title: "Risk Owner", email: "risk@climateliberator.test")
    let managementOwner = PersonRef(name: "M. Owner", title: "Risk Director", email: "director@climateliberator.test")
    let executive = PersonRef(name: "E. Sponsor", title: "Chief Risk Officer", email: "cro@climateliberator.test")
    let approver = PersonRef(name: "B. Approver", title: "Board Secretary", email: "board@climateliberator.test")

    return TCFDReviewRecord(
        runID: "run-qa-0001",
        bundleID: "bundle-qa-0001",
        reviewStatus: .boardPackReady,
        packageState: .readyForBoard,
        decision: .none,
        escalationSeverity: .none,
        preparedBy: preparedBy,
        currentOwner: riskOwner,
        accountableExecutive: executive,
        approver: approver,
        dueDate: Date(timeIntervalSince1970: 1_700_086_400),
        preparedAt: preparedAt,
        submittedAt: submittedAt,
        reviewedAt: reviewedAt,
        approvedAt: nil,
        updatedAt: reviewedAt,
        governance: GovernanceAccountabilitySnapshot(
            boardCommittee: "Board Risk Committee",
            boardOversightRequired: true,
            managementOwner: managementOwner,
            riskOwner: riskOwner,
            financeReviewer: PersonRef(name: "F. Partner", title: "Finance Controller", email: "finance@climateliberator.test"),
            reviewCadence: "Quarterly",
            delegatedAuthoritySummary: "CRO may recommend board escalation after management review.",
            ermLinkageSummary: "Linked into the enterprise climate risk register."
        ),
        scenario: ReviewScenarioSnapshot(
            scenarioName: "Utility Baseline",
            tcfdScenarioLabel: "Board-ready baseline",
            simulatorLabel: "Cell2Fire",
            shortHorizonLabel: "0-3 years",
            mediumHorizonLabel: "3-10 years",
            longHorizonLabel: "10+ years",
            baselineScenarioName: "Utility Baseline",
            comparatorScenarioName: "High-wind stress",
            baselineRunID: "run-base-0001",
            comparatorRunID: "run-stress-0001",
            shortTermDeltaSummary: "Short-term exposure remains within tolerance.",
            mediumTermDeltaSummary: "Medium-term stress case increases exposure concentration by 8%.",
            longTermDeltaSummary: "Long-term resilience remains acceptable with planned mitigations.",
            resilienceConclusion: "Board pack supports continued mitigation investment.",
            wildfireAssumptionsSummary: "Static fuels, prepared ignition set, and observed seasonal weather assumptions."
        ),
        impactDrivers: [
            WildfireImpactDriverAssessment(
                category: .physical,
                driverName: "Substation perimeter exposure",
                shortTermView: "Elevated during dry season operations.",
                mediumTermView: "Moderate increase under stress scenario.",
                longTermView: "Managed with buffer clearing and suppression planning.",
                ermLinked: true,
                responseSummary: "Operations team assigned mitigation controls."
            ),
            WildfireImpactDriverAssessment(
                category: .transition,
                driverName: "Regulatory adaptation investment",
                shortTermView: "Capex requirement already identified.",
                mediumTermView: "Investment accelerates under high-wind scenario.",
                longTermView: "Long-term compliance remains manageable.",
                ermLinked: true,
                responseSummary: "Finance and risk teams aligned on capital program."
            ),
            WildfireImpactDriverAssessment(
                category: .opportunity,
                driverName: "Grid hardening opportunity",
                shortTermView: "Prioritized for highest-risk substations.",
                mediumTermView: "Improves resilience score under stress case.",
                longTermView: "Supports lower loss volatility and service continuity.",
                ermLinked: true,
                responseSummary: "Included in resilience roadmap."
            )
        ],
        roadmapStages: [
            RoadmapStageProgress(key: .packageGenerated, title: "Package Generated", detail: "Evidence package captured.", isComplete: true),
            RoadmapStageProgress(key: .thresholdsReviewed, title: "Thresholds Reviewed", detail: "Thresholds are within tolerance.", isComplete: true),
            RoadmapStageProgress(key: .financeReviewed, title: "Finance Reviewed", detail: "Finance methodology and quantified loss reviewed.", isComplete: true),
            RoadmapStageProgress(key: .boardReady, title: "Board Ready", detail: "Package is ready for board consideration.", isComplete: true)
        ],
        thresholds: ThresholdEvaluationSummary(
            status: .withinTolerance,
            totalTargets: 1,
            breachedCount: 0,
            nearLimitCount: 0,
            evaluations: [
                ThresholdMetricEvaluation(
                    targetBandID: UUID(uuidString: "00000000-0000-0000-0000-000000000101"),
                    metricName: "Burn Probability",
                    observedValue: 0.12,
                    observedDisplayValue: "0.12",
                    thresholdDisplayValue: "0.20",
                    status: .withinTolerance
                )
            ],
            evaluatedAt: Date(timeIntervalSince1970: 1_700_005_400)
        ),
        thresholdBreachActions: [],
        approvalEvidence: nil,
        reviewEvents: [
            ReviewEvent(timestamp: submittedAt, actor: preparedBy.name, action: "Submitted for Analyst Review", reviewStatus: .analystReview, note: "Initial disclosure package submitted."),
            ReviewEvent(timestamp: reviewedAt, actor: riskOwner.name, action: "Marked Board Pack Ready", reviewStatus: .boardPackReady, note: "Board-readiness checks passed.")
        ],
        financialEffects: FinancialEffectsReview(
            status: .quantified,
            planningImpactSummary: "Mitigation capex is within approved planning buffers.",
            financeReviewed: true,
            magnitudeBand: "Moderate",
            methodologyNote: "Indicative quantitative proxy based on asset exposure and modeled burn probability.",
            currencyCode: "INR",
            exposureValue: 10_000_000,
            burnProbabilityProxy: 0.12,
            vulnerabilityRatio: 0.2,
            deductiblePct: 0.05,
            limitPct: 0.8,
            estimatedGroundUpLoss: 240_000,
            estimatedInsuredLoss: 190_000,
            estimatedReinsuranceRecovery: 0
        ),
        provenance: ProvenanceSummary(
            manifestURL: "/tmp/run_manifest.json",
            reportURL: "/tmp/tcfd_report.md",
            mappingURL: "/tmp/tcfd_mapping.json",
            simulatorLabel: "Cell2Fire",
            inputFolder: "/tmp/input",
            outputDirectory: "/tmp/output",
            isComplete: true,
            artifactIndexURL: "/tmp/artifact_index.json",
            seed: 123,
            binaryHash: "sha256:test"
        ),
        conditions: [],
        reviewerNotes: "Package is ready for formal approval once evidence is confirmed."
    )
}
