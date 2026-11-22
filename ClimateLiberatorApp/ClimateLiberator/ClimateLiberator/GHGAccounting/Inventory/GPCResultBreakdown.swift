import Foundation

/// Views of one reporting-level total (BASIC or BASIC+) for the results charts.
/// Every breakdown sums to the same total, so the charts always agree.
nonisolated struct GPCResultBreakdown: Sendable {
    nonisolated struct Slice: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        /// Grouping used for colour (sector, scope, data quality…).
        let group: String
        let value: Double
        /// For entries: GPC reference (e.g. "I.2.2") and the entry's own name, shown apart.
        var code = ""
        var name = ""
    }

    nonisolated struct WaterfallStep: Identifiable, Hashable, Sendable {
        let id: String
        let label: String
        let start: Double
        let end: Double
        let isTotal: Bool
        var value: Double { end - start }
    }

    let level: GPCReportingLevel
    let total: Double
    /// tCO2e by GPC sector, in sector order.
    let bySector: [Slice]
    /// Individual entries, largest first (group = sector).
    let topSources: [Slice]
    /// tCO2e by gas (CO2, CH4, N2O, F-gases, CO2e entered directly).
    let byGas: [Slice]
    /// tCO2e by sector (label) and data quality (group).
    let byQuality: [Slice]
    /// Sector contributions stacked up to the total.
    let waterfall: [WaterfallStep]

    var lowQualityShare: Double {
        guard total > 0 else { return 0 }
        return byQuality.filter { $0.group == GPCDataQuality.low.title }.reduce(0) { $0 + $1.value } / total
    }

    static func make(_ inventory: GPCInventory, summary: GPCInventorySummary, topCount: Int = 10) -> GPCResultBreakdown {
        let level = inventory.targetLevel
        let gwp = inventory.gwpSet
        var sectorTotals: [GPCSector: Double] = [:]
        var gasTotals: [String: Double] = [:]
        var qualityTotals: [String: Double] = [:]
        var sources: [Slice] = []

        for entry in inventory.entries {
            guard entry.method != .notationKey,
                  let reference = entry.reference, reference.sector != .otherScope3,
                  level == .basic ? reference.inBasic : reference.inBasicPlus,
                  let outcome = summary.outcomes[entry.id], outcome.error == nil else { continue }
            let value = outcome.co2eTonnes
            sectorTotals[reference.sector, default: 0] += value
            let name = entry.label.trimmingCharacters(in: .whitespaces).isEmpty ? reference.title : entry.label
            sources.append(Slice(id: entry.id.uuidString, label: "\(entry.referenceID) \(name)",
                                 group: reference.sector.shortTitle, value: value, code: entry.referenceID, name: name))
            qualityTotals["\(reference.sector.rawValue)|\(entry.dataQuality.rawValue)", default: 0] += value

            let gases = outcome.gasesTonnes
            gasTotals["CO2", default: 0] += gases.co2
            gasTotals["CH4", default: 0] += gases.ch4Fossil * gwp.ch4Fossil + gases.ch4NonFossil * gwp.ch4NonFossil
            gasTotals["N2O", default: 0] += gases.n2o * gwp.n2o
            gasTotals["F-gases", default: 0] += gases.sf6 * gwp.sf6 + gases.nf3 * gwp.nf3
            gasTotals["Entered as CO2e", default: 0] += gases.otherCO2e
        }

        let sectors = GPCSector.allCases.filter { (sectorTotals[$0] ?? 0) != 0 }
        let bySector = sectors.map { Slice(id: $0.rawValue, label: $0.shortTitle, group: $0.shortTitle, value: sectorTotals[$0] ?? 0) }
        let total = bySector.reduce(0) { $0 + $1.value }

        let byGas = ["CO2", "CH4", "N2O", "F-gases", "Entered as CO2e"].compactMap { gas -> Slice? in
            let value = gasTotals[gas] ?? 0
            return value == 0 ? nil : Slice(id: gas, label: gas, group: gas, value: value)
        }

        let byQuality = sectors.flatMap { sector in
            GPCDataQuality.allCases.compactMap { quality -> Slice? in
                let value = qualityTotals["\(sector.rawValue)|\(quality.rawValue)"] ?? 0
                return value == 0 ? nil : Slice(id: "\(sector.rawValue)|\(quality.rawValue)", label: sector.shortTitle,
                                               group: quality.title, value: value)
            }
        }

        var running = 0.0
        var waterfall: [WaterfallStep] = bySector.map { slice in
            defer { running += slice.value }
            return WaterfallStep(id: slice.id, label: slice.label, start: running, end: running + slice.value, isTotal: false)
        }
        if !waterfall.isEmpty {
            waterfall.append(WaterfallStep(id: "total", label: "\(level.title) total", start: 0, end: total, isTotal: true))
        }

        // Chart categories merge equal labels, so repeated labels get a counter.
        var labelCounts: [String: Int] = [:]
        let topSources = sources.sorted { $0.value > $1.value }.prefix(topCount).map { slice -> Slice in
            labelCounts[slice.label, default: 0] += 1
            let count = labelCounts[slice.label] ?? 1
            return count == 1 ? slice : Slice(id: slice.id, label: "\(slice.label) (\(count))", group: slice.group, value: slice.value,
                                              code: slice.code, name: "\(slice.name) (\(count))")
        }
        return GPCResultBreakdown(level: level, total: total, bySector: bySector, topSources: topSources,
                                  byGas: byGas, byQuality: byQuality, waterfall: waterfall)
    }
}
