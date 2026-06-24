import XCTest
@testable import ClimateLiberator

@MainActor
final class DisclosureReportingTests: XCTestCase {

    // 100 crore TIV, 40 crore gross, 36 crore net.
    private let result = PortfolioLossResult(
        peril: .wildfire,
        assetCount: 250,
        totalInsuredValue: 1_000_000_000,
        groundUpLoss: 400_000_000,
        insuredLoss: 360_000_000
    )

    func testRendersIFRSAndBRSRDraft() {
        let surface = DisclosureReportSurface(entityName: "Acme Ltd", reportingPeriod: "FY2025-26")
        XCTAssertEqual(surface.audience, .disclosure)

        let draft = surface.render(result)
        XCTAssertEqual(draft.standard, "IFRS S2")
        XCTAssertEqual(draft.peril, .wildfire)
        XCTAssertFalse(draft.governance.isEmpty)
        XCTAssertFalse(draft.strategy.isEmpty)
        XCTAssertFalse(draft.riskManagement.isEmpty)

        // Metrics carry the real numbers.
        let metricValues = draft.metricsAndTargets.map(\.value)
        XCTAssertTrue(metricValues.contains("250"))
        XCTAssertTrue(metricValues.contains("₹100.00 crore"))   // TIV
        XCTAssertTrue(metricValues.contains("40.0%"))            // 400M / 1000M
        XCTAssertTrue(metricValues.contains("₹36.00 crore"))    // net insured loss
    }

    func testBRSRMapsToPrinciple6() {
        let draft = DisclosureReportSurface().render(result)
        XCTAssertEqual(draft.brsr.principle, "Principle 6 — Environment")
        let responses = draft.brsr.indicators.map(\.response)
        XCTAssertTrue(responses.contains("Wildfire"))
        XCTAssertTrue(responses.contains("250"))
        XCTAssertTrue(responses.contains("₹36.00 crore"))
    }

    /// The payoff: one PortfolioLossResult feeds both surfaces with consistent numbers.
    func testTwoSurfacesOverSameNumbers() {
        let insurer = InsurerReportSurface().render(result)
        let disclosure = DisclosureReportSurface().render(result)

        // Insurer summary and disclosure draft describe the same insured loss.
        let insurerNetCrore = DisclosureReportSurface.inrCrore(insurer.insuredLoss)
        let disclosureNet = disclosure.brsr.indicators
            .first { $0.indicator.contains("financial implication") }?.response
        XCTAssertEqual(insurerNetCrore, disclosureNet)
        XCTAssertEqual(insurer.peril, disclosure.peril)
        XCTAssertEqual(insurer.assetCount, 250)
    }

    func testCroreFormatting() {
        XCTAssertEqual(DisclosureReportSurface.inrCrore(10_000_000), "₹1.00 crore")
        XCTAssertEqual(DisclosureReportSurface.inrCrore(0), "₹0.00 crore")
    }
}
