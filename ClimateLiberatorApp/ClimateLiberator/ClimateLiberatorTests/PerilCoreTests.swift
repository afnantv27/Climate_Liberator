import XCTest
@testable import ClimateLiberator

/// Proves the peril-agnostic core (PerilCoreModel/PerilCoreAdapters) composes
/// stages 1–4 correctly, using stubs for the hazard surface so the test does
/// not depend on running the engine.
@MainActor
final class PerilCoreTests: XCTestCase {

    /// A hazard surface that returns the same intensity everywhere (or nil).
    private struct ConstantHazard: HazardSurface {
        let peril: Peril = .wildfire
        let value: Double?
        func intensity(latitude: Double, longitude: Double) -> Double? { value }
    }

    private struct StubAsset: ExposureAsset {
        let assetID: String
        let latitude: Double
        let longitude: Double
        let totalInsuredValue: Double
        let assetType: String
    }

    /// Deterministic vulnerability so pipeline tests verify composition, not curve params.
    private struct StubVulnerability: VulnerabilityCurve {
        let peril: Peril = .wildfire
        let ratio: Double
        func damageRatio(intensity: Double, assetType: String) -> Double { ratio }
    }

    private func makeAssets() -> [any ExposureAsset] {
        [
            StubAsset(assetID: "a", latitude: 0, longitude: 0, totalInsuredValue: 1_000_000, assetType: "residential"),
            StubAsset(assetID: "b", latitude: 1, longitude: 1, totalInsuredValue: 500_000, assetType: "industrial"),
        ]
    }

    func testPipelineComputesGroundUpAndInsuredLoss() {
        let result = PerilPipeline.loss(
            peril: .wildfire,
            hazard: ConstantHazard(value: 5.0),          // positive fire activity everywhere
            exposure: makeAssets(),
            vulnerability: StubVulnerability(ratio: 1.0),  // intensity > 0 → total loss
            financial: LayeredFinancialModel()
        )
        XCTAssertEqual(result.assetCount, 2)
        XCTAssertEqual(result.totalInsuredValue, 1_500_000, accuracy: 0.001)
        XCTAssertEqual(result.groundUpLoss, 1_500_000, accuracy: 0.001)
        XCTAssertEqual(result.insuredLoss, 1_500_000, accuracy: 0.001)
        XCTAssertEqual(result.meanDamageFraction, 1.0, accuracy: 0.001)
    }

    func testAssetsOutsideFootprintIncurNoLoss() {
        let result = PerilPipeline.loss(
            peril: .wildfire,
            hazard: ConstantHazard(value: nil),           // outside footprint everywhere
            exposure: makeAssets(),
            vulnerability: StubVulnerability(ratio: 1.0),
            financial: LayeredFinancialModel()
        )
        XCTAssertEqual(result.totalInsuredValue, 1_500_000, accuracy: 0.001)
        XCTAssertEqual(result.groundUpLoss, 0, accuracy: 0.001)
        XCTAssertEqual(result.insuredLoss, 0, accuracy: 0.001)
    }

    func testDeductibleReducesInsuredLoss() {
        let result = PerilPipeline.loss(
            peril: .wildfire,
            hazard: ConstantHazard(value: 5.0),
            exposure: [makeAssets()[0]],                  // single 1,000,000 asset
            vulnerability: StubVulnerability(ratio: 1.0),
            financial: LayeredFinancialModel(),
            deductibleFraction: 0.1,
            limitFraction: 1
        )
        // GUL = 1,000,000; 10% deductible = 100,000 → insured = 900,000
        XCTAssertEqual(result.groundUpLoss, 1_000_000, accuracy: 0.001)
        XCTAssertEqual(result.insuredLoss, 900_000, accuracy: 0.001)
    }

    func testWildfireGridConformsToHazardSurface() {
        let grid = IndiaWildfireRiskGrid(width: 2, height: 1,
                                         minLon: 0, maxLon: 2, minLat: 0, maxLat: 1,
                                         maxValue: 9, values: [9, nil])
        XCTAssertEqual(grid.peril, .wildfire)
        XCTAssertEqual(grid.intensity(latitude: 0.5, longitude: 0.5), 9)   // column 0 center
        XCTAssertNil(grid.intensity(latitude: 0.5, longitude: 1.5))         // column 1 is nil
    }

    func testInsurerReportSurfaceRenders() {
        let result = PortfolioLossResult(peril: .wildfire, assetCount: 3,
                                         totalInsuredValue: 100, groundUpLoss: 40, insuredLoss: 30)
        let surface = InsurerReportSurface()
        XCTAssertEqual(surface.audience, .insurer)
        let summary = surface.render(result)
        XCTAssertEqual(summary.assetCount, 3)
        XCTAssertEqual(summary.insuredLoss, 30, accuracy: 0.001)
    }
}
