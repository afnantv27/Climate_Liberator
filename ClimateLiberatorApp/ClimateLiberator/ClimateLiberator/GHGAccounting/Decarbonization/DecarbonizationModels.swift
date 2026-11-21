import Foundation

// Decarbonisation scenarios, independent of the accounting framework.
//
// The engine works on `ScenarioLine`s (one emission source each). An adapter turns
// a framework's inventory into lines — `GPCScenarioBaselineAdapter` for city
// inventories today; a corporate (GHG Protocol) adapter can be added later without
// touching the catalog or the engine.

// MARK: - Emission sources seen by the engine

/// Energy carrier of an emission line, used to match measures to sources.
nonisolated enum EnergyCarrier: String, Codable, CaseIterable, Hashable, Sendable {
    case gridElectricity, petrol, diesel, lpg, naturalGas, kerosene, fuelOil, coal, biomass, biogas
}

/// One emission source in a scenario baseline.
nonisolated struct ScenarioLine: Identifiable, Sendable {
    let id: String
    let label: String
    /// Framework source key, e.g. GPC "I.1.2". Measures select lines by key prefix.
    let sourceKey: String
    /// Top-level group used for growth rates and charts, e.g. GPC sector "I".
    let groupKey: String
    let carriers: Set<EnergyCarrier>
    let isGridElectricity: Bool
    /// Gas masses in tonnes (biogenic CO2 kept separately, as in the inventory).
    var gases: GasAmounts
    /// Final energy in kWh, when the activity can be converted to energy.
    var energyKWh: Double?
    /// Activity mass in tonnes, for waste lines.
    var massTonnes: Double?
    /// Grid electricity added by a fuel switch. It is priced at the year's grid factor
    /// when created, so the grid pathway does not clean it a second time.
    var isAddedLoad = false

    func co2eTonnes(_ gwp: GWPSet) -> Double { gases.co2e(gwp) }

    /// Scales every quantity of the line, e.g. after an efficiency gain.
    mutating func scale(by factor: Double) {
        gases = gases.scaled(by: factor)
        energyKWh = energyKWh.map { $0 * factor }
        massTonnes = massTonnes.map { $0 * factor }
    }
}

/// The base-year emission lines a scenario starts from.
nonisolated struct ScenarioBaseline: Sendable {
    let baseYear: Int
    let gwp: GWPSet
    let lines: [ScenarioLine]
    /// Base-year grid factor (kg CO2e per kWh) applied to electricity added by fuel switches.
    let gridFactorKgPerKWh: Double
    /// Display names for group keys, e.g. "I" → "Stationary energy".
    let groupTitles: [String: String]
    /// Lines left out because they cannot be projected (shown as warnings).
    var notes: [String] = []
    /// Where electricity added by a fuel switch is reported, e.g. GPC "I.1.1" → "I.1.2".
    var electricitySourceKey: @Sendable (String) -> String = { $0 }

    var totalTonnes: Double { lines.reduce(0) { $0 + $1.co2eTonnes(gwp) } }
}

// MARK: - Catalog definitions (code, not persisted)

nonisolated enum MeasureCategory: String, CaseIterable, Identifiable, Sendable {
    case buildings, transport, waste, wastewater, energySupply, landUse

    var id: String { rawValue }
    var title: String {
        switch self {
        case .buildings: return "Buildings & Industry"
        case .transport: return "Transport"
        case .waste: return "Solid Waste"
        case .wastewater: return "Wastewater"
        case .energySupply: return "Energy Supply"
        case .landUse: return "Land Use & Removals"
        }
    }
    var systemImage: String {
        switch self {
        case .buildings: return "building.2"
        case .transport: return "bus"
        case .waste: return "trash"
        case .wastewater: return "drop"
        case .energySupply: return "bolt"
        case .landUse: return "leaf"
        }
    }
}

/// Which lines a measure acts on.
nonisolated struct SourceSelector: Sendable {
    /// Source-key prefixes (e.g. "I.1", "II.1"). Empty matches every key.
    var keyPrefixes: [String] = []
    /// The line must use one of these carriers. Empty matches any carrier.
    var carriers: Set<EnergyCarrier> = []
    /// true: grid electricity only; false: everything except grid electricity; nil: both.
    var gridElectricity: Bool?

    func matches(_ line: ScenarioLine) -> Bool {
        if let gridElectricity, line.isGridElectricity != gridElectricity { return false }
        if !carriers.isEmpty, carriers.isDisjoint(with: line.carriers) { return false }
        if keyPrefixes.isEmpty { return true }
        return keyPrefixes.contains { Self.key(line.sourceKey, hasPrefix: $0) }
    }

    /// "I.1" matches "I.1" and "I.1.2" but not "I.10".
    static func key(_ key: String, hasPrefix prefix: String) -> Bool {
        key == prefix || key.hasPrefix(prefix + ".")
    }
}

/// A published source behind a default value.
nonisolated struct MeasureSource: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let publisher: String
    let url: String
}

/// An input of a measure, with a typical value and a low–high range.
nonisolated struct MeasureParameter: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let unit: String
    let typical: Double
    let low: Double
    let high: Double
    let sourceIDs: [String]
    /// The default is an assumption (no published source): replace it with local data.
    var isAssumption = false
    /// The measure has no effect until the user enters a value (e.g. a count).
    var requiresInput = false
    var note = ""
}

/// What a measure does to matching lines at 100% adoption.
nonisolated enum MeasureEffect: Sendable {
    /// Cut activity (energy, fuel, waste) by a fraction — efficiency or avoided demand.
    case reduceActivity(fraction: Double)
    /// Save a fixed amount of grid electricity per year, spread over matching lines.
    case saveGridElectricity(kWhPerYear: Double)
    /// Replace fuel with grid electricity; kWh of electricity per kWh of fuel replaced.
    case switchToGridElectricity(kWhPerKWhReplaced: Double)
    /// Replace fuel with another fuel from the factor library; kWh used per kWh replaced.
    case switchToFactor(factorExternalID: String, kWhPerKWhReplaced: Double)
    /// Send waste to another treatment (factor per tonne) instead of disposal.
    case divertWaste(treatmentExternalID: String)
    /// Cut fossil CO2 only (e.g. blending biofuel).
    case reduceFossilCO2(fraction: Double)
    /// Cut CH4 only (e.g. gas capture, aerobic treatment).
    case reduceMethane(fraction: Double)
    /// Supply this share of grid electricity from zero-emission sources (adoption is the share).
    case replaceGridSupply
    /// Grid emission factor path, kg CO2e/kWh by year (adoption = share of the path achieved).
    case gridEmissionFactorPath([YearValue])
    /// Carbon removed per year, reported separately from emissions.
    case removeCarbon(tonnesPerYear: Double)

    var stage: MeasureStage {
        switch self {
        case .reduceActivity, .saveGridElectricity: return .demand
        case .switchToGridElectricity, .switchToFactor, .divertWaste, .reduceFossilCO2: return .fuelSwitch
        case .reduceMethane: return .methane
        case .replaceGridSupply: return .cleanSupply
        case .gridEmissionFactorPath: return .grid
        case .removeCarbon: return .removal
        }
    }
}

/// Order in which measures are applied, so savings are never counted twice:
/// use less → switch fuels → capture methane → clean supply → cleaner grid → removals.
nonisolated enum MeasureStage: Int, Comparable, Sendable {
    case demand, fuelSwitch, methane, cleanSupply, grid, removal
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
}

nonisolated struct YearValue: Hashable, Sendable {
    let year: Int
    let value: Double
}

/// A decarbonisation measure in the catalog.
nonisolated struct DecarbonizationMeasure: Identifiable, Sendable {
    let id: String
    let title: String
    let category: MeasureCategory
    /// What the measure does, in one or two sentences.
    let summary: String
    /// Which emission sources it suits best.
    let bestFor: String
    /// What the adoption percentage means for this measure.
    let adoptionMeaning: String
    let defaultAdoption: Double
    let targets: SourceSelector
    let parameters: [MeasureParameter]
    var extraSourceIDs: [String] = []
    var caveat = ""
    /// Turns parameter values into an effect.
    let effect: @Sendable ([String: Double]) -> MeasureEffect

    var sourceIDs: [String] {
        var seen = Set<String>()
        return (parameters.flatMap(\.sourceIDs) + extraSourceIDs).filter { seen.insert($0).inserted }
    }

    var needsInput: Bool { parameters.contains(where: \.requiresInput) }

    func values(_ pick: (MeasureParameter) -> Double = \.typical) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: parameters.map { ($0.id, pick($0)) })
    }
}

// MARK: - Persisted scenario

/// A measure chosen for a scenario, with its rollout.
nonisolated struct ScenarioMeasureSelection: Codable, Hashable, Identifiable, Sendable {
    var measureID: String
    /// Share of matching activity covered at `fullYear` (0–1).
    var adoption: Double
    var startYear: Int
    var fullYear: Int
    var parameterOverrides: [String: Double] = [:]
    /// Owner, costs, funding and co-benefits (the action plan). nil until edited.
    var plan: ActionPlanItem?

    var id: String { measureID }

    /// Linear rollout: 0 before `startYear`, `adoption` from `fullYear`.
    func adoption(in year: Int) -> Double {
        guard year >= startYear else { return 0 }
        guard fullYear > startYear, year < fullYear else { return adoption }
        return adoption * Double(year - startYear + 1) / Double(fullYear - startYear + 1)
    }

    func values(for measure: DecarbonizationMeasure) -> [String: Double] {
        measure.values().merging(parameterOverrides) { _, override in override }
    }
}

/// A named decarbonisation pathway for one inventory.
nonisolated struct DecarbonizationScenario: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var targetYear: Int
    /// Annual business-as-usual growth in activity per group key (e.g. "II": 0.04). Missing = 0.
    var annualGrowth: [String: Double] = [:]
    var measures: [ScenarioMeasureSelection] = []
    /// Reduction goal as a fraction (e.g. 0.45 for −45%), against the base year or
    /// business as usual depending on `goalType`.
    var reductionTarget: Double?
    /// GPC goal type; nil means a base-year goal (scenarios saved before goal types).
    var goalType: ScenarioGoalType?
    /// Target-year emissions for a fixed-level goal (0 = net zero).
    var goalLevelTonnes: Double?
    /// Currency, discount rate and planned credits for the action plan.
    var planSettings: ActionPlanSettings?

    func growth(for group: String) -> Double { annualGrowth[group] ?? 0 }

    var goalKind: ScenarioGoalType { goalType ?? .baseYear }
    var settings: ActionPlanSettings { planSettings ?? ActionPlanSettings() }

    /// Emissions allowed in the target year by the goal, if one is set.
    func goalTonnes(baseTonnes: Double, bauTonnes: Double) -> Double? {
        switch goalKind {
        case .baseYear: return reductionTarget.map { baseTonnes * (1 - $0) }
        case .baselineScenario: return reductionTarget.map { bauTonnes * (1 - $0) }
        case .fixedLevel: return goalLevelTonnes
        }
    }

    /// Short label such as "−45% vs 2025", "−30% vs business as usual" or "Net zero".
    func goalLabel(baseYear: Int) -> String? {
        switch goalKind {
        case .baseYear:
            return reductionTarget.map { "−\(Self.percentText($0)) vs \(String(baseYear))" }
        case .baselineScenario:
            return reductionTarget.map { "−\(Self.percentText($0)) vs business as usual" }
        case .fixedLevel:
            guard let level = goalLevelTonnes else { return nil }
            return level <= 0 ? "Net zero" : "\(Int(level.rounded()).formatted()) t"
        }
    }

    private static func percentText(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0...1)))
    }
}
