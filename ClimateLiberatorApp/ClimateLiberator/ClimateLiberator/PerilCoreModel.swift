import Foundation

// MARK: - Peril-agnostic core (see docs/product-architecture.md)
//
// The five stages of the core. Stages 1–4 are peril-agnostic; only stage 5
// forks by buyer. Peril-specific logic lives behind these protocols and must
// not leak upward. Wildfire (Cell2Fire) is the first implemented plug-in.

/// Perils the platform is being built to cover. Wildfire is implemented today;
/// the rest are placeholders for the multi-peril roadmap (flood/cyclone are the
/// high-value India perils to add next).
enum Peril: String, Codable, CaseIterable, Identifiable, Sendable {
    case wildfire, flood, cyclone, heat, drought
    var id: String { rawValue }
}

// MARK: - Stage 1: Hazard ("how intense, and where")

/// A hazard footprint that can be sampled at any coordinate. Intensity units are
/// peril-specific (wildfire: rate of spread; flood: depth in m; cyclone: wind).
protocol HazardSurface {
    var peril: Peril { get }
    /// Peril intensity at a coordinate, or nil if outside the footprint.
    func intensity(latitude: Double, longitude: Double) -> Double?
}

/// Minimal, peril-agnostic request to generate a hazard footprint.
struct HazardRequest: Sendable {
    let inputFolder: String
    let outputFolder: String
    let seed: Int

    init(inputFolder: String, outputFolder: String, seed: Int = 123) {
        self.inputFolder = inputFolder
        self.outputFolder = outputFolder
        self.seed = seed
    }
}

/// Produces a `HazardSurface` for one peril. Cell2Fire is the first plug-in.
protocol HazardModel {
    var peril: Peril { get }
    func makeHazardSurface(_ request: HazardRequest) async throws -> HazardSurface
}

// MARK: - Stage 2: Exposure ("what is at risk, where, worth how much")

/// A single insured / at-risk asset.
protocol ExposureAsset {
    var assetID: String { get }
    var latitude: Double { get }
    var longitude: Double { get }
    /// Total insured value (TIV) in currency units.
    var totalInsuredValue: Double { get }
    /// Occupancy / construction class used to pick a vulnerability curve.
    var assetType: String { get }
}

/// A set of exposure assets (a portfolio or study area).
protocol ExposureSet {
    var assets: [any ExposureAsset] { get }
}

// MARK: - Stage 3: Vulnerability ("intensity X on asset type Y → % damage")

/// Maps peril intensity on an asset type to a mean damage ratio in 0...1.
/// This is the current gap in the codebase; curves start crude and improve.
protocol VulnerabilityCurve {
    var peril: Peril { get }
    func damageRatio(intensity: Double, assetType: String) -> Double
}

// MARK: - Stage 4: Financial ("damage → money")

/// Turns a damage ratio + value into an insurance loss layering (GUL/IL/RI).
/// Buyer-agnostic: serves both insurer cat metrics and corporate $ impact.
protocol FinancialModel {
    func loss(totalInsuredValue: Double,
              damageRatio: Double,
              deductibleFraction: Double,
              limitFraction: Double) -> FinancialLossLayer
}

// MARK: - Stage 5: Reporting (two surfaces over the same numbers)

enum ReportAudience: String, Codable, Sendable {
    case insurer      // AAL, PML, exceedance curve, accumulation
    case disclosure   // IFRS S2 + SEBI BRSR
}

/// The shared output of stages 1–4 that both reporting surfaces consume.
struct PortfolioLossResult: Sendable, Hashable {
    let peril: Peril
    let assetCount: Int
    let totalInsuredValue: Double
    let groundUpLoss: Double
    let insuredLoss: Double

    var meanDamageFraction: Double {
        totalInsuredValue > 0 ? groundUpLoss / totalInsuredValue : 0
    }
}

/// Renders a loss result into a buyer-specific output. Only this stage forks.
protocol ReportSurface {
    associatedtype Output
    var audience: ReportAudience { get }
    func render(_ result: PortfolioLossResult) -> Output
}

// MARK: - The peril-agnostic core, composed

/// Composes stages 2–4 over a hazard surface to produce the shared loss result.
/// This is the whole point of the architecture: no peril-specific code above the
/// `HazardSurface`. Swapping wildfire for flood means swapping stages 1 and 3
/// only — this function does not change.
enum PerilPipeline {
    static func loss(peril: Peril,
                     hazard: HazardSurface,
                     exposure: [any ExposureAsset],
                     vulnerability: VulnerabilityCurve,
                     financial: FinancialModel,
                     deductibleFraction: Double = 0,
                     limitFraction: Double = 1) -> PortfolioLossResult {
        var groundUp = 0.0
        var insured = 0.0
        var tiv = 0.0

        for asset in exposure {
            tiv += asset.totalInsuredValue
            guard let intensity = hazard.intensity(latitude: asset.latitude,
                                                   longitude: asset.longitude) else { continue }
            let damage = vulnerability.damageRatio(intensity: intensity, assetType: asset.assetType)
            let layer = financial.loss(totalInsuredValue: asset.totalInsuredValue,
                                       damageRatio: damage,
                                       deductibleFraction: deductibleFraction,
                                       limitFraction: limitFraction)
            groundUp += layer.gul
            insured += layer.il
        }

        return PortfolioLossResult(peril: peril,
                                   assetCount: exposure.count,
                                   totalInsuredValue: tiv,
                                   groundUpLoss: groundUp,
                                   insuredLoss: insured)
    }
}
