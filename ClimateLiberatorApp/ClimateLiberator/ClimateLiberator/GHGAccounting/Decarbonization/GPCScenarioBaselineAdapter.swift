import Foundation

/// Turns a GPC city inventory into a scenario baseline: one line per entry counted in
/// the inventory's reporting level (BASIC or BASIC+), with final energy and waste mass
/// where they can be derived from the activity data.
nonisolated enum GPCScenarioBaselineAdapter {
    /// CEA v21 weighted average, used when the inventory has no grid electricity in kWh.
    static let fallbackGridFactorExternalID = "cea-v21-fy2025-weighted-average"

    static func baseline(for inventory: GPCInventory, summary: GPCInventorySummary) -> ScenarioBaseline {
        let level = inventory.targetLevel
        var lines: [ScenarioLine] = []
        for entry in inventory.entries {
            guard entry.method != .notationKey,
                  let reference = entry.reference, reference.sector != .otherScope3,
                  level == .basic ? reference.inBasic : reference.inBasicPlus,
                  let outcome = summary.outcomes[entry.id], outcome.error == nil else { continue }
            let isGrid = reference.scope == .two
            let amounts = quantities(for: entry)
            lines.append(ScenarioLine(
                id: entry.id.uuidString,
                label: entry.label.isEmpty ? reference.title : entry.label,
                sourceKey: reference.id,
                groupKey: reference.sector.rawValue,
                carriers: isGrid ? [.gridElectricity] : carriers(for: entry),
                isGridElectricity: isGrid,
                gases: outcome.gasesTonnes,
                energyKWh: amounts.energyKWh,
                massTonnes: amounts.massTonnes))
        }

        var notes: [String] = []
        let grid = lines.filter { $0.isGridElectricity && ($0.energyKWh ?? 0) > 0 }
        let gridKWh = grid.reduce(0) { $0 + ($1.energyKWh ?? 0) }
        let gridTonnes = grid.reduce(0) { $0 + $1.co2eTonnes(inventory.gwpSet) }
        let fallback = EmissionFactorSeedLibrary.factors
            .first { $0.externalID == fallbackGridFactorExternalID }?.gases?.co2 ?? 0.710
        if gridKWh == 0 {
            notes.append("No grid electricity in kWh: added electricity uses the CEA average of \(fallback) kg CO2/kWh.")
        }
        return ScenarioBaseline(
            baseYear: inventory.inventoryYear,
            gwp: inventory.gwpSet,
            lines: lines,
            gridFactorKgPerKWh: gridKWh > 0 ? gridTonnes * 1_000 / gridKWh : fallback,
            groupTitles: Dictionary(uniqueKeysWithValues: GPCSector.allCases.map { ($0.rawValue, $0.shortTitle) }),
            notes: notes,
            electricitySourceKey: { GPCScenarioBaselineAdapter.electricityKey($0) })
    }

    /// GPC reports a sub-sector's grid energy under ".2": "I.1.1" → "I.1.2", "II.1.1" → "II.1.2".
    static func electricityKey(_ key: String) -> String {
        var parts = key.split(separator: ".").map(String.init)
        guard parts.count == 3 else { return key }
        parts[2] = "2"
        return parts.joined(separator: ".")
    }

    /// Final energy (kWh) and mass (t) of an activity entry, when its units allow.
    static func quantities(for entry: GPCInventoryEntry) -> (energyKWh: Double?, massTonnes: Double?) {
        guard entry.method == .activity, let quantity = entry.activityQuantity, let factor = entry.factor,
              let unit = UnitRegistry.resolve(entry.activityUnit.isEmpty ? factor.activityUnit : entry.activityUnit) else {
            return (nil, nil)
        }
        var trail: [CalculationStep] = []
        var energy: Double?
        if let kWh = UnitRegistry.resolve("kWh") {
            energy = try? EmissionCalculator.convertQuantity(quantity, from: unit, to: kWh, factor: factor, trail: &trail)
        }
        var mass: Double?
        if unit.dimension == .mass, let tonne = UnitRegistry.resolve("t") {
            mass = UnitRegistry.convert(quantity, from: unit, to: tonne)
        }
        return (energy, mass)
    }

    /// Energy carriers named by the entry's factor or label.
    static func carriers(for entry: GPCInventoryEntry) -> Set<EnergyCarrier> {
        let text = [entry.factor?.externalID ?? "", entry.factor?.name ?? "", entry.label].joined(separator: " ").lowercased()
        let rules: [(EnergyCarrier, [String])] = [
            (.lpg, ["lpg"]),
            (.petrol, ["petrol", "gasoline"]),
            (.diesel, ["diesel"]),
            (.naturalGas, ["natural gas", "natural-gas", "cng", "png"]),
            (.kerosene, ["kerosene"]),
            (.fuelOil, ["furnace", "residual fuel", "fuel oil"]),
            (.coal, ["coal", "lignite", "coke"]),
            (.biomass, ["wood", "biomass", "charcoal", "firewood"]),
            (.biogas, ["biogas"]),
        ]
        return Set(rules.filter { _, words in words.contains { text.contains($0) } }.map(\.0))
    }
}
