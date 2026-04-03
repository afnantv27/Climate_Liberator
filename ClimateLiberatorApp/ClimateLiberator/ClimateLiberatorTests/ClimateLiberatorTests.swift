import XCTest
import CoreLocation
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
