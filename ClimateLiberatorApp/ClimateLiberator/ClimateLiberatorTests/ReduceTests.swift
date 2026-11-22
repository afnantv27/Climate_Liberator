import XCTest
@testable import ClimateLiberator

/// Targets, pathways, measure costs and the credit ledger.
@MainActor
final class ReduceTests: XCTestCase {

    private func year(_ year: Int, scope1: Double, scope2: Double, revenue: Double? = nil) -> ClientYearFigures {
        var figures = ClientYearFigures(clientID: UUID(), fiscalYearStart: year)
        figures.scope1 = scope1
        figures.scope2 = scope2
        figures.revenueCrore = revenue
        return figures
    }

    private func target(base: Int = 2023, target: Int = 2030, percent: Double = 42) -> ReductionTarget {
        var item = ReductionTarget(baseYear: base, targetYear: target)
        item.reductionPercent = percent
        return item
    }

    // MARK: Targets

    func testLinearPathAndStatus() throws {
        let history = [year(2023, scope1: 600, scope2: 400), year(2025, scope1: 520, scope2: 330)]
        let assessment = TargetAssessor.assess(target(), history: history)
        XCTAssertEqual(assessment.baseValue, 1_000)
        XCTAssertEqual(try XCTUnwrap(assessment.targetValue), 580, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(assessment.annualRate), 6, accuracy: 1e-9)
        // Allowed in FY 2025-26: 1000 − 2 × 60 = 880; reported 850 → on track.
        XCTAssertEqual(try XCTUnwrap(assessment.pathValue(2025)), 880, accuracy: 1e-9)
        XCTAssertEqual(assessment.status, .onTrack)
        XCTAssertEqual(try XCTUnwrap(assessment.gapAtLatest), -30, accuracy: 1e-9)
    }

    func testOffTrackNoBaselineAndAchieved() {
        let behind = TargetAssessor.assess(target(), history: [year(2023, scope1: 600, scope2: 400), year(2025, scope1: 600, scope2: 390)])
        XCTAssertEqual(behind.status, .offTrack)
        XCTAssertEqual(TargetAssessor.assess(target(), history: [year(2025, scope1: 1, scope2: 1)]).status, .noBaseline)
        XCTAssertEqual(TargetAssessor.assess(target(), history: [year(2023, scope1: 600, scope2: 400)]).status, .notStarted)
        let done = TargetAssessor.assess(target(), history: [year(2023, scope1: 600, scope2: 400), year(2026, scope1: 300, scope2: 200)])
        XCTAssertEqual(done.status, .achieved)
    }

    func testBaseValueOverrideAndIntensityTargets() throws {
        var override = target()
        override.baseValueOverride = 2_000
        XCTAssertEqual(TargetAssessor.assess(override, history: []).baseValue, 2_000)

        var intensity = target()
        intensity.kind = .intensityRevenue
        let assessment = TargetAssessor.assess(intensity, history: [year(2023, scope1: 600, scope2: 400, revenue: 50)])
        XCTAssertEqual(try XCTUnwrap(assessment.baseValue), 20, accuracy: 1e-9)
        let rateCheck = try XCTUnwrap(assessment.checks().first)
        XCTAssertNil(rateCheck.passed, "Absolute rates do not apply to intensity targets")
    }

    func testReferenceChecks() throws {
        var sbti = target(base: 2023, target: 2031, percent: 42)   // 5.25% a year
        sbti.framework = .sbtiNearTerm
        let today = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 22))!
        let checks = TargetAssessment(target: sbti, baseValue: 1_000, latestYear: nil, latestValue: nil, status: .notStarted)
            .checks(today: today)
        XCTAssertEqual(checks.first?.passed, true, "5.25% a year meets 4.2%")
        XCTAssertEqual(checks.first { $0.title.contains("years ahead") }?.passed, true, "FY 2031-32 is 5 years after FY 2026-27")
        XCTAssertEqual(checks.first { $0.title.contains("Base year") }?.passed, true)

        let weak = TargetAssessment(target: target(percent: 21), baseValue: 1_000, latestYear: nil, latestValue: nil, status: .notStarted)
        XCTAssertEqual(weak.checks(today: today).first?.passed, false, "3% a year is below 4.2%")
    }

    // MARK: Pathway

    func testProjectionCountsOnlyFutureCommittedMeasures() throws {
        let history = [year(2023, scope1: 600, scope2: 400), year(2025, scope1: 520, scope2: 330)]
        let assessment = TargetAssessor.assess(target(), history: history)
        var solar = ReductionMeasure(startYear: 2027)
        solar.scope = .scope2
        solar.annualAbatement = 150
        var alreadyRunning = ReductionMeasure(startYear: 2024)
        alreadyRunning.annualAbatement = 500
        var idea = ReductionMeasure(startYear: 2027)
        idea.annualAbatement = 900
        idea.status = .idea
        var scope3 = ReductionMeasure(startYear: 2027)
        scope3.scope = .scope3
        scope3.annualAbatement = 900

        let projection = ReductionPathway.projectedValues(assessment: assessment, measures: [solar, alreadyRunning, idea, scope3],
                                                          through: 2030)
        XCTAssertEqual(projection[2026], 850)
        XCTAssertEqual(projection[2027], 700)
        // Target 580 in FY 2030-31; projection 700 → 120 short.
        XCTAssertEqual(try XCTUnwrap(ReductionPathway.shortfall(assessment: assessment, measures: [solar])), 120, accuracy: 1e-9)

        let points = ReductionPathway.points(for: assessment, history: history, measures: [solar])
        XCTAssertEqual(points.first?.year, 2023)
        XCTAssertEqual(points.last?.year, 2030)
        XCTAssertEqual(points.first { $0.year == 2025 }?.actual, 850)
    }

    // MARK: Measures

    func testMeasureCostUsesCapitalRecovery() throws {
        var measure = ReductionMeasure(startYear: 2026)
        measure.annualAbatement = 100
        measure.capitalCost = 1_000_000
        measure.lifetimeYears = 10
        measure.annualSavings = 200_000
        let economics = MeasureCosting.economics(of: measure, discountRate: 0)
        // 1,000,000 / 10 − 200,000 = −100,000 a year → −1,000 ₹ per tonne.
        XCTAssertEqual(try XCTUnwrap(economics.costPerTonne), -1_000, accuracy: 1e-9)

        measure.lifetimeYears = nil
        let noLifetime = MeasureCosting.economics(of: measure, discountRate: 0.08)
        XCTAssertNil(noLifetime.costPerTonne)
        XCTAssertEqual(MeasureCosting.gap(of: measure, economics: noLifetime), "Add lifetime")
    }

    // MARK: Credits

    func testCreditLedgerTotalsAndIssues() throws {
        var retired = CarbonCredit(vintageYear: 2017)
        retired.quantity = 300
        retired.status = .retired
        retired.retiredForYear = 2025
        retired.projectType = .biochar
        var held = CarbonCredit(vintageYear: 2024)
        held.quantity = 200
        held.evidence = "https://registry.example/123"
        let ledger = CreditLedger(credits: [retired, held])
        XCTAssertEqual(ledger.held, 200)
        XCTAssertEqual(ledger.retiredQuantity(forYear: 2025), 300)
        XCTAssertEqual(try XCTUnwrap(ledger.removalShare(forYear: 2025)), 1, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(ledger.coverage(ofEmissions: 1_200, forYear: 2025)), 0.25, accuracy: 1e-9)
        let messages = ledger.issues.map(\.message).joined(separator: "\n")
        XCTAssertTrue(messages.contains("retirement date"))
        XCTAssertTrue(messages.contains("serial numbers"))
        XCTAssertTrue(messages.contains("vintage 2017"))
        XCTAssertTrue(messages.contains("registry record"))
        XCTAssertFalse(ledger.issues.contains { $0.creditID == held.id }, "Held credits with evidence are fine")
    }

    // MARK: Store

    func testStoreCreatesPlansOnFirstEditOnly() {
        let store = ReductionStore(loadFromDisk: false)
        let client = UUID()
        XCTAssertTrue(store.plan(for: client).isEmpty)
        store.update(client, clientName: "Moulding Co") { _ in }
        XCTAssertNil(store.plans[client], "No change, no plan")
        store.upsertTarget(target(), client: client, name: "Moulding Co")
        XCTAssertEqual(store.plans[client]?.targets.count, 1)
        XCTAssertTrue(store.isUnsaved(client))
        XCTAssertEqual(store.unsavedItemNames, ["Moulding Co"])
        XCTAssertTrue(store.save(clientID: client))
        XCTAssertFalse(store.isUnsaved(client))
    }

    func testPlanCodecRoundTrip() throws {
        var plan = ReductionPlan(clientID: UUID(), clientName: "Codec Co")
        plan.updatedAt = Date(timeIntervalSince1970: 1_750_000_000)
        plan.targets = [target()]
        var credit = CarbonCredit(vintageYear: 2024)
        credit.retirementDate = Date(timeIntervalSince1970: 1_760_000_000)
        plan.credits = [credit]
        let data = try AppJSON.encoder().encode(plan)
        XCTAssertEqual(try AppJSON.decoder().decode(ReductionPlan.self, from: data), plan)
    }
}
