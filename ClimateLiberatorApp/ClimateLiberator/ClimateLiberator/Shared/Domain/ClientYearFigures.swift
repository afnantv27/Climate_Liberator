import Foundation

/// Headline environmental figures for one client and one financial year.
///
/// The common currency between modules: data modules (today Disclosure's KPI Data,
/// later corporate inventories) produce it; Clusters, Reduce and Home consume it.
/// Every value is optional because real data arrives piece by piece.
nonisolated struct ClientYearFigures: Hashable, Sendable {
    let clientID: UUID
    /// First calendar year of the Indian financial year (2025 = FY 2025-26).
    let fiscalYearStart: Int
    var scope1: Double?
    var scope2: Double?
    var scope3: Double?
    /// Total energy consumed (GJ) and the renewable part of it.
    var energyGJ: Double?
    var renewableEnergyGJ: Double?
    var waterConsumptionKL: Double?
    var wasteGeneratedT: Double?
    /// Revenue from operations (₹ crore).
    var revenueCrore: Double?
    var output: Double?
    var outputUnit: String = ""
    /// Where the figures came from, e.g. "KPI Data · FY 2025-26".
    var source: String = ""

    init(clientID: UUID, fiscalYearStart: Int) {
        self.clientID = clientID
        self.fiscalYearStart = fiscalYearStart
    }

    /// Scope 1 + 2 when both are known.
    var scope12: Double? {
        guard let scope1, let scope2 else { return nil }
        return scope1 + scope2
    }

    /// tCO2e per ₹ crore of revenue.
    var intensityPerRevenue: Double? { Self.ratio(scope12, revenueCrore) }
    /// tCO2e per unit of output (unit in `outputUnit`).
    var intensityPerOutput: Double? { Self.ratio(scope12, output) }
    /// GJ per ₹ crore of revenue.
    var energyPerRevenue: Double? { Self.ratio(energyGJ, revenueCrore) }
    /// Renewable share of energy, 0–1.
    var renewableShare: Double? { Self.ratio(renewableEnergyGJ, energyGJ) }

    var hasEmissions: Bool { scope12 != nil }

    static func ratio(_ numerator: Double?, _ denominator: Double?) -> Double? {
        guard let numerator, let denominator, denominator > 0 else { return nil }
        return numerator / denominator
    }
}

/// Which emissions a target or comparison covers.
nonisolated enum EmissionScopeCoverage: String, Codable, CaseIterable, Identifiable, Sendable {
    case scope12, scope3, scope123

    var id: String { rawValue }
    var title: String {
        switch self {
        case .scope12: return "Scope 1 + 2"
        case .scope3: return "Scope 3"
        case .scope123: return "Scope 1 + 2 + 3"
        }
    }

    /// The covered total; nil if any covered part is missing.
    func value(in figures: ClientYearFigures) -> Double? {
        switch self {
        case .scope12: return figures.scope12
        case .scope3: return figures.scope3
        case .scope123:
            guard let scope12 = figures.scope12, let scope3 = figures.scope3 else { return nil }
            return scope12 + scope3
        }
    }
}
