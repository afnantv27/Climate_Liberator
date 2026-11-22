import XCTest
@testable import ClimateLiberator

/// Home's attention list: deadlines, targets, review queue and site coordinates.
@MainActor
final class HomeSummaryTests: XCTestCase {

    private let today = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 11, day: 22))!

    func testDeadlinesAreUrgentWhenCloseOrPassed() {
        var soon = DisclosureEngagement(fiscalYearStart: 2025)
        soon.profile.legalName = "Soon Co"
        soon.filingDeadline = today.addingTimeInterval(10 * 86_400)
        var late = DisclosureEngagement(fiscalYearStart: 2025)
        late.profile.legalName = "Late Co"
        late.filingDeadline = today.addingTimeInterval(-3 * 86_400)
        var done = DisclosureEngagement(fiscalYearStart: 2024)
        done.signOff = SignOff(approvedBy: "Approver", statement: "")

        let summary = HomeSummary.build(clients: [], engagements: [soon, late, done], plans: [], inventoryCount: 0, today: today)
        XCTAssertEqual(summary.activeEngagements, 2)
        XCTAssertEqual(summary.signedOffEngagements, 1)
        XCTAssertTrue(summary.attention.contains { $0.id == "deadline.\(soon.id)" && $0.severity == .urgent })
        XCTAssertTrue(summary.attention.contains { $0.id == "deadline.\(late.id)" && $0.title.contains("passed") })
        XCTAssertEqual(summary.attention.first?.severity, .urgent, "Most urgent first")
    }

    func testOffTrackTargetAndReviewQueue() {
        let clientID = UUID()
        var fy25 = DisclosureEngagement(fiscalYearStart: 2025)
        fy25.clientID = clientID
        var scope1 = MetricEntry()
        scope1.current = 1_000
        scope1.prior = 1_000
        scope1.status = .readyForReview
        var scope2 = MetricEntry()
        scope2.current = 0
        scope2.prior = 0
        fy25.metrics = [MetricID.scope1: scope1, MetricID.scope2: scope2]

        var plan = ReductionPlan(clientID: clientID, clientName: "Flat Co")
        var target = ReductionTarget(baseYear: 2024, targetYear: 2030)
        target.reductionPercent = 60
        plan.targets = [target]

        var client = Client(name: "Flat Co")
        client.id = clientID
        client.sites = [Site(name: "Plant")]

        let summary = HomeSummary.build(clients: [client], engagements: [fy25], plans: [plan], inventoryCount: 2, today: today)
        XCTAssertEqual(summary.targetCount, 1)
        XCTAssertEqual(summary.targetsOffTrack, 1)
        XCTAssertEqual(summary.itemsAwaitingReview, 1)
        XCTAssertEqual(summary.sitesWithoutCoordinates, 1)
        XCTAssertTrue(summary.attention.contains { $0.destination == .reductionPlan(clientID) })
        XCTAssertTrue(summary.attention.contains { $0.destination == .client(clientID) })
        XCTAssertEqual(summary.inventoryCount, 2)
    }
}
