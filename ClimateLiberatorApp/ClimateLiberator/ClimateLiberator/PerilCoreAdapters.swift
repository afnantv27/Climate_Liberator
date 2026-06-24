import Foundation

// MARK: - Adapters: existing types conform to the peril-agnostic core
//
// These conformances prove the core protocols fit the code we already have,
// rather than being an aspirational top-down design. See PerilCoreModel.swift
// and docs/product-architecture.md.

// MARK: Stage 1 — the wildfire ROS grid already is a hazard surface

extension IndiaWildfireRiskGrid: HazardSurface {
    var peril: Peril { .wildfire }

    func intensity(latitude: Double, longitude: Double) -> Double? {
        sampledValue(latitude: latitude, longitude: longitude)
    }
}

/// Cell2Fire as a `HazardModel` plug-in.
///
/// `makeHazardSurface` is the integration seam: it delegates to the wildfire
/// grid-producing pipeline (engine run + ROS raster parse) injected at init.
/// Today the app builds that grid in ContentView+Simulation; wiring this model
/// into that flow is the next integration step. The conformance establishes that
/// the peril-agnostic core can treat Cell2Fire as a swappable hazard source.
struct WildfireHazardModel: HazardModel {
    let peril: Peril = .wildfire
    // A synchronous, Sendable provider. The producing work (engine output parse)
    // is file I/O, so it is sync; the protocol method stays async for engines that
    // need it. Storing an async closure here crashes under MainActor-default
    // isolation (Builtin.ImplicitActor retain on a bad address), so we keep it sync.
    private let produceSurface: @Sendable (HazardRequest) throws -> HazardSurface

    init(produceSurface: @escaping @Sendable (HazardRequest) throws -> HazardSurface) {
        self.produceSurface = produceSurface
    }

    func makeHazardSurface(_ request: HazardRequest) async throws -> HazardSurface {
        try produceSurface(request)
    }
}

// MARK: Stage 2 — an India building footprint is an exposure asset

extension IndiaNearbyBuilding: ExposureAsset {
    var assetID: String { id }

    /// TIV proxy consistent with IndiaRiskServices (footprint area × unit cost).
    var totalInsuredValue: Double { (areaM2 ?? 0) * 35_000 }

    var assetType: String { landuse ?? "unknown" }
}

// MARK: Stage 3 — wildfire vulnerability lives in WildfireVulnerability.swift

// MARK: Stage 4 — the existing loss engine, behind the protocol

/// Wraps `FinancialLossEngine` (GUL/IL/RI layering). `damageRatio` already folds
/// in hazard probability × vulnerability, so burn probability is passed as 1.0.
struct LayeredFinancialModel: FinancialModel {
    func loss(totalInsuredValue: Double,
              damageRatio: Double,
              deductibleFraction: Double,
              limitFraction: Double) -> FinancialLossLayer {
        FinancialLossEngine.computeLoss(tiv: totalInsuredValue,
                                        burnProbability: 1.0,
                                        vulnerabilityRatio: damageRatio,
                                        deductiblePct: deductibleFraction,
                                        limitPct: limitFraction)
    }
}

// MARK: Stage 5 — a minimal insurer reporting surface

struct InsurerLossSummary: Sendable, Hashable {
    let peril: Peril
    let assetCount: Int
    let totalInsuredValue: Double
    let groundUpLoss: Double
    let insuredLoss: Double
}

/// The insurer view over the shared loss result. The disclosure (IFRS S2 / BRSR)
/// surface is the second `ReportSurface` to add — it consumes the same result.
struct InsurerReportSurface: ReportSurface {
    let audience: ReportAudience = .insurer

    func render(_ result: PortfolioLossResult) -> InsurerLossSummary {
        InsurerLossSummary(peril: result.peril,
                           assetCount: result.assetCount,
                           totalInsuredValue: result.totalInsuredValue,
                           groundUpLoss: result.groundUpLoss,
                           insuredLoss: result.insuredLoss)
    }
}
