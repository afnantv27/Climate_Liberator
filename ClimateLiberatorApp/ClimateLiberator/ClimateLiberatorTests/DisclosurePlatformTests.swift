import XCTest
@testable import ClimateLiberator

/// Disclosure platform: catalog integrity, calculations, checks, workflow,
/// persistence and reports.
@MainActor
final class DisclosurePlatformTests: XCTestCase {

    private var tempRoot: URL!

    override func setUpWithError() throws {
        tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent("DisclosureTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempRoot)
    }

    private func makeStore() -> DisclosureStore {
        DisclosureStore(locations: DisclosureDataLocations(root: tempRoot.appendingPathComponent("Data"),
                                                           exportsDirectory: tempRoot.appendingPathComponent("Exports")))
    }

    private func engagement(_ values: [String: Double], prior: [String: Double] = [:],
                            frameworks: Set<DisclosureFramework> = [.brsr, .brsrCore]) -> DisclosureEngagement {
        var engagement = DisclosureEngagement(fiscalYearStart: 2025)
        engagement.frameworks = frameworks
        for (id, value) in values {
            var entry = engagement.metric(id)
            entry.current = value
            engagement.metrics[id] = entry
        }
        for (id, value) in prior {
            var entry = engagement.metric(id)
            entry.prior = value
            engagement.metrics[id] = entry
        }
        return engagement
    }

    // MARK: Catalog

    func testCatalogIdsAreUniqueAndReferencesResolve() {
        let ids = MetricCatalog.all.map(\.id)
        XCTAssertEqual(ids.count, Set(ids).count, "Duplicate metric ids")
        for definition in MetricCatalog.all {
            for input in definition.derivation?.inputs ?? [] {
                XCTAssertNotNil(MetricCatalog.metric(input), "\(definition.id) uses unknown input \(input)")
            }
        }
        let narrativeIDs = NarrativeCatalog.all.map(\.id)
        XCTAssertEqual(narrativeIDs.count, Set(narrativeIDs).count, "Duplicate narrative ids")
        for requirement in NarrativeCatalog.all {
            XCTAssertFalse(requirement.elements.isEmpty, "\(requirement.id) has no checklist")
            for id in requirement.linkedMetrics {
                XCTAssertNotNil(MetricCatalog.metric(id), "\(requirement.id) links unknown metric \(id)")
            }
        }
    }

    func testEveryCoreAttributeHasMetrics() {
        for attribute in BRSRCoreAttribute.allCases {
            XCTAssertFalse(MetricCatalog.metrics(in: attribute).isEmpty, "No KPI for Core attribute \(attribute.rawValue)")
        }
    }

    func testRequiredInputsIncludeDenominatorsOfDerivedMetrics() {
        let required = Set(MetricCatalog.requiredInputs(for: [.brsrCore]).map(\.id))
        XCTAssertTrue(required.contains(MetricID.revenue))
        XCTAssertTrue(required.contains(MetricID.pppRate))
        XCTAssertTrue(required.contains(MetricID.scope1))
        XCTAssertFalse(required.contains(MetricID.scope12), "Calculated metrics are not inputs")
    }

    // MARK: Calculations

    func testPPPIntensity() throws {
        // 44,200 tCO2e; revenue ₹2,450 crore; PPP ₹21 per $ → 44,200 ÷ (2,450 × 10⁷ ÷ 21 ÷ 10⁶) ≈ 37.886
        let values = MetricResolver(engagement([MetricID.scope1: 40_000, MetricID.scope2: 4_200,
                                                MetricID.revenue: 2_450, MetricID.pppRate: 21]))
        XCTAssertEqual(values[MetricID.scope12].current, 44_200)
        let intensity = try XCTUnwrap(values[MetricID.ghgIntensityPPP].current)
        XCTAssertEqual(intensity, 44_200 * 21 / (2_450 * 10), accuracy: 0.001)
        XCTAssertEqual(intensity, 37.886, accuracy: 0.001)
        XCTAssertNil(MetricResolver.perPPP(100, revenueCrore: 0, rate: 21))
        XCTAssertNil(MetricResolver.perPPP(100, revenueCrore: 10, rate: nil))
    }

    func testPartialAndNotApplicableInputs() {
        var partial = engagement([MetricID.scope1: 1_000])
        XCTAssertEqual(MetricResolver(partial)[MetricID.scope12].current, 1_000)
        XCTAssertTrue(MetricResolver(partial)[MetricID.scope12].isPartial)

        var entry = MetricEntry()
        entry.notApplicable = true
        entry.notApplicableReason = "No purchased electricity"
        partial.metrics[MetricID.scope2] = entry
        let resolved = MetricResolver(partial)[MetricID.scope12]
        XCTAssertEqual(resolved.current, 1_000)
        XCTAssertFalse(resolved.isPartial, "Not applicable counts as zero, not missing")
    }

    // MARK: Data checks

    func testDataChecksFlagNegativesPercentagesAndVariance() {
        var test = engagement([MetricID.scope1: -5, MetricID.revenue: 1_000],
                              prior: [MetricID.revenue: 500])
        test.profile.legalName = "Test Co"
        let ids = Set(DataQualityChecks.run(test, fileExists: { _ in true }).map(\.id))
        XCTAssertTrue(ids.contains { $0.hasPrefix("negative.\(MetricID.scope1)") })
        XCTAssertTrue(ids.contains("variance.\(MetricID.revenue)"), "A 100% change needs an explanation")

        var explained = test
        explained.metrics[MetricID.revenue]?.varianceExplanation = "Acquisition of a second plant"
        XCTAssertFalse(DataQualityChecks.run(explained, fileExists: { _ in true }).map(\.id).contains("variance.\(MetricID.revenue)"))
    }

    func testDeadlineChecks() {
        var test = DisclosureEngagement(fiscalYearStart: 2025)
        let today = Date()
        test.filingDeadline = today.addingTimeInterval(-86_400)
        XCTAssertTrue(DataQualityChecks.run(test, today: today).map(\.id).contains("deadline.passed"))
        test.filingDeadline = today.addingTimeInterval(5 * 86_400)
        XCTAssertTrue(DataQualityChecks.run(test, today: today).map(\.id).contains("deadline.near"))
    }

    // MARK: Workflow

    func testWorkflowTransitions() {
        XCTAssertEqual(WorkflowEngine.actions(from: .notStarted), [.start, .submit])
        XCTAssertEqual(WorkflowEngine.actions(from: .readyForReview), [.approve, .requestChanges])
        XCTAssertEqual(WorkflowEngine.status(after: .approve), .approved)
        XCTAssertFalse(WorkflowEngine.canApply(.submit, status: .inProgress, isAnswered: false), "Cannot submit an empty value")
        XCTAssertTrue(WorkflowEngine.canApply(.submit, status: .inProgress, isAnswered: true))
        XCTAssertFalse(WorkflowEngine.canApply(.approve, status: .inProgress, isAnswered: true))
        XCTAssertEqual(WorkflowEngine.statusAfterEdit(.approved), .inProgress)
        XCTAssertEqual(WorkflowEngine.statusAfterEdit(.readyForReview), .readyForReview)
    }

    func testEditingApprovedValueWithdrawsApprovalAndIsAudited() throws {
        let store = makeStore()
        let created = store.createEngagement(companyName: "Test Co", fiscalYearStart: 2025, frameworks: [.brsr],
                                             isListed: true, marketCapRank: 400, sector: .manufacturing)
        let id = created.id
        store.updateMetric(MetricID.scope1, in: id) { $0.current = 100 }
        XCTAssertTrue(store.review(.submit, metric: MetricID.scope1, in: id))
        XCTAssertTrue(store.review(.approve, metric: MetricID.scope1, in: id))
        XCTAssertEqual(store.engagement(id)?.metric(MetricID.scope1).status, .approved)

        store.updateMetric(MetricID.scope1, in: id) { $0.current = 120 }
        let entry = try XCTUnwrap(store.engagement(id)?.metric(MetricID.scope1))
        XCTAssertEqual(entry.status, .inProgress)
        XCTAssertTrue(entry.approvedBy.isEmpty)
        XCTAssertTrue(store.engagement(id)?.activity.contains { $0.action == "Approval withdrawn" } ?? false)

        // Writing back an unchanged value is not an edit.
        let count = store.engagement(id)?.activity.count
        store.updateMetric(MetricID.scope1, in: id) { $0.current = 120 }
        XCTAssertEqual(store.engagement(id)?.activity.count, count)
    }

    func testSignOffLocksAndReopenUnlocks() {
        let store = makeStore()
        let id = store.createEngagement(companyName: "Lock Co", fiscalYearStart: 2025, frameworks: [.brsr],
                                        isListed: false, marketCapRank: nil, sector: .itServices).id
        store.signOff(id: id, statement: "Approved")
        XCTAssertTrue(store.engagement(id)?.isLocked ?? false)
        store.updateMetric(MetricID.scope1, in: id) { $0.current = 5 }
        XCTAssertNil(store.engagement(id)?.metric(MetricID.scope1).current, "Signed-off engagements are read-only")
        store.reopen(id: id, reason: "Restatement")
        XCTAssertFalse(store.engagement(id)?.isLocked ?? true)
        store.updateMetric(MetricID.scope1, in: id) { $0.current = 5 }
        XCTAssertEqual(store.engagement(id)?.metric(MetricID.scope1).current, 5)
    }

    func testSignOffBlockersListUnapprovedItems() {
        let blockers = WorkflowEngine.signOffBlockers(DisclosureEngagement(fiscalYearStart: 2025), issues: [])
        XCTAssertTrue(blockers.contains { $0.contains("required data point") })
        XCTAssertTrue(blockers.contains { $0.contains("approver") })
    }

    func testRollForwardMovesValuesToPriorYear() {
        var source = engagement([MetricID.scope1: 900, MetricID.revenue: 2_000])
        source.metrics[MetricID.scope1]?.method = "Fuel × CEA factors"
        source.narratives["s2.gov.board"] = { var entry = NarrativeEntry(); entry.text = "The board oversees…"; entry.status = .approved; return entry }()
        let next = RollForward.nextYear(from: source, user: "Tester")
        XCTAssertEqual(next.fiscalYearStart, 2026)
        XCTAssertEqual(next.metric(MetricID.scope1).prior, 900)
        XCTAssertNil(next.metric(MetricID.scope1).current)
        XCTAssertEqual(next.metric(MetricID.scope1).method, "Fuel × CEA factors")
        XCTAssertEqual(next.narrative("s2.gov.board").status, .inProgress, "Last year's text is a draft, not approved")
        XCTAssertNotEqual(next.id, source.id)
    }

    // MARK: Data request round trip

    func testDataRequestRoundTrip() throws {
        let source = engagement([MetricID.scope1: 1_234.5])
        let csv = DataRequest.template(for: source)
        XCTAssertTrue(csv.hasPrefix(DataRequest.header.joined(separator: ",")))

        let result = DataRequest.parse(csv)
        let scope1 = try XCTUnwrap(result.updates.first { $0.metricID == MetricID.scope1 })
        XCTAssertEqual(scope1.current, 1_234.5)

        let bad = DataRequest.parse("metric_id,current_value\nunknown.metric,5\n\(MetricID.scope1),abc\n")
        XCTAssertEqual(bad.skipped.count, 2)
    }

    // MARK: Persistence

    func testCodecRoundTripAndTolerantDecoding() throws {
        var original = engagement([MetricID.scope1: 10], frameworks: [.brsr, .ifrsS2])
        original.profile.legalName = "Round Trip Ltd"
        // JSON dates keep whole seconds.
        original.createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        original.updatedAt = original.createdAt
        original.issues.append({ var issue = MaterialIssue(); issue.title = "Water stress"; return issue }())
        let url = tempRoot.appendingPathComponent("engagement.json")
        try DisclosureJSON.write(original, to: url)
        let decoded = try DisclosureJSON.read(from: url)
        XCTAssertEqual(decoded, original)

        let minimal = Data(#"{"fiscalYearStart": 2024, "profile": {"legalName": "Old File Co"}}"#.utf8)
        let old = try DisclosureJSON.decoder().decode(DisclosureEngagement.self, from: minimal)
        XCTAssertEqual(old.companyName, "Old File Co")
        XCTAssertEqual(old.policies.count, 9)
        XCTAssertEqual(old.frameworks, [.brsr, .brsrCore])
    }

    func testNothingIsSavedUntilAsked() throws {
        let store = makeStore()
        let id = store.createEngagement(companyName: "Unsaved Co", fiscalYearStart: 2025, frameworks: [.brsr],
                                        isListed: false, marketCapRank: nil, sector: .itServices).id
        let file = store.locations.engagementFile(id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        XCTAssertTrue(store.isUnsaved(id))
        XCTAssertTrue(store.save(id: id))
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
        XCTAssertFalse(store.isUnsaved(id))
    }

    // MARK: Reports

    func testExampleBuildsEveryReportInEveryFormat() {
        let example = DisclosureExample.engagement(user: "Tester")
        for kind in ReportKind.allCases {
            let document = ReportBuilder.build(kind, engagement: example)
            XCTAssertFalse(document.blocks.isEmpty, "\(kind) is empty")
            XCTAssertFalse(ReportRenderer.render(document, as: .markdown).isEmpty)
            let html = ReportRenderer.render(document, as: .html)
            XCTAssertTrue(html.contains("<html"))
            XCTAssertFalse(html.contains("<script"), "Values must be escaped")
        }
    }

    func testHTMLEscapesUserText() {
        var document = ReportDocument(title: "T", subtitle: "")
        document.paragraph("<script>alert(1)</script> & more")
        let html = ReportRenderer.render(document, as: .html)
        XCTAssertFalse(html.contains("<script>alert"))
        XCTAssertTrue(html.contains("&lt;script&gt;"))
    }

    func testExampleIsMostlyReady() {
        let readiness = ReadinessAnalyzer.analyze(DisclosureExample.engagement(user: "Tester"))
        XCTAssertGreaterThan(readiness.overallAnswered, 0.5)
        XCTAssertFalse(readiness.coreRows.isEmpty)
    }

    // MARK: Applicability

    func testApplicabilityGlidePath() {
        var profile = CompanyProfile()
        profile.isListed = true
        profile.marketCapRank = 420
        func requirement(_ framework: DisclosureFramework, _ year: Int) -> ApplicabilityRules.Requirement? {
            ApplicabilityRules.assess(profile, fiscalYearStart: year).first { $0.framework == framework }?.requirement
        }
        XCTAssertEqual(requirement(.brsr, 2025), .mandatory)
        XCTAssertEqual(requirement(.brsrCore, 2024), .voluntary, "Top 250 in FY 2024-25")
        XCTAssertEqual(requirement(.brsrCore, 2025), .mandatory, "Top 500 in FY 2025-26")
        XCTAssertEqual(requirement(.ifrsS2, 2025), .voluntary)

        profile.isListed = false
        XCTAssertEqual(requirement(.brsr, 2025), .voluntary)
    }

    func testLastCompletedFinancialYear() {
        let calendar = Calendar(identifier: .gregorian)
        let november = calendar.date(from: DateComponents(year: 2026, month: 11, day: 21))!
        let february = calendar.date(from: DateComponents(year: 2026, month: 2, day: 1))!
        XCTAssertEqual(NewEngagementSheet.lastCompletedYear(today: november), 2025)
        XCTAssertEqual(NewEngagementSheet.lastCompletedYear(today: february), 2024)
    }
}
