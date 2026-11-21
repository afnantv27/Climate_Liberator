import Foundation

// MARK: - Results

/// Reduction credited to one measure in one year (t CO2e; removals for removal measures).
nonisolated struct MeasureWedge: Identifiable, Hashable, Sendable {
    let measureID: String
    let tonnes: Double
    var id: String { measureID }
}

nonisolated struct ScenarioYearResult: Identifiable, Sendable {
    let year: Int
    /// Business as usual: base-year emissions grown with activity, factors frozen.
    let bauTonnes: Double
    /// Gross emissions after measures.
    let scenarioTonnes: Double
    /// Carbon removals, reported separately.
    let removalsTonnes: Double
    /// Reductions in the order the measures were applied.
    let wedges: [MeasureWedge]

    var id: Int { year }
    var netTonnes: Double { scenarioTonnes - removalsTonnes }
    func wedge(_ measureID: String) -> Double { wedges.first { $0.measureID == measureID }?.tonnes ?? 0 }
}

nonisolated struct ScenarioProjection: Sendable {
    let baseYear: Int
    let baseTonnes: Double
    let years: [ScenarioYearResult]
    let warnings: [String]

    var target: ScenarioYearResult? { years.last }
    func year(_ year: Int) -> ScenarioYearResult? { years.first { $0.year == year } }
}

/// Stand-alone effect of one measure on the base inventory.
nonisolated struct MeasurePotential: Identifiable, Sendable {
    let measureID: String
    let matchingLineCount: Int
    /// Emissions of the matching sources (t CO2e).
    let matchingTonnes: Double
    let adoption: Double
    /// Reduction at `adoption` with typical, low and high parameter values (t CO2e).
    let typicalTonnes: Double
    let lowTonnes: Double
    let highTonnes: Double
    /// Share of the matching sources' emissions removed at 100% adoption.
    let cutOfMatchingAtFullAdoption: Double
    let baseTonnes: Double
    let needsInput: Bool

    var id: String { measureID }
    var isApplicable: Bool { matchingLineCount > 0 }
    var shareOfBase: Double { baseTonnes > 0 ? typicalTonnes / baseTonnes : 0 }
}

typealias EmissionFactorLookup = @Sendable (String) -> EmissionFactor?

// MARK: - Engine

/// Projects decarbonisation scenarios year by year.
///
/// Each year: grow the base lines with business-as-usual activity growth, then apply
/// the selected measures in stage order (demand → fuel switch → methane → clean supply
/// → grid → removals). Measures acting on the same lines compound on what is left,
/// so no tonne is cut twice. A measure's wedge is the drop in total emissions when it
/// is applied. Electricity added by a fuel switch is priced at that year's grid factor
/// (after any grid pathway in the scenario), so a switch's wedge is its real net effect
/// and the grid wedge covers the existing grid load only.
nonisolated enum DecarbonizationEngine {
    static let libraryFactors: EmissionFactorLookup = { externalID in
        EmissionFactorSeedLibrary.factors.first { $0.externalID == externalID }
    }

    static func project(_ baseline: ScenarioBaseline,
                        scenario: DecarbonizationScenario,
                        catalog: (String) -> DecarbonizationMeasure? = DecarbonizationMeasureCatalog.measure,
                        factors: @escaping EmissionFactorLookup = libraryFactors) -> ScenarioProjection {
        let selected = scenario.measures.compactMap { selection in catalog(selection.measureID).map { ($0, selection) } }
        let lastYear = max(baseline.baseYear, scenario.targetYear)
        var warnings = Set<String>()
        let years = (baseline.baseYear...lastYear).map { year -> ScenarioYearResult in
            let outcome = evaluate(baseline, year: year, growth: scenario.growth(for:), measures: selected, factors: factors)
            warnings.formUnion(outcome.warnings)
            return outcome.result
        }
        return ScenarioProjection(baseYear: baseline.baseYear, baseTonnes: baseline.totalTonnes,
                                  years: years, warnings: warnings.sorted() + baseline.notes)
    }

    /// Stand-alone potential of a measure at the given adoption, without growth or other measures.
    static func potential(of measure: DecarbonizationMeasure,
                          baseline: ScenarioBaseline,
                          adoption: Double,
                          year: Int,
                          overrides: [String: Double] = [:],
                          factors: @escaping EmissionFactorLookup = libraryFactors) -> MeasurePotential {
        let matching = baseline.lines.filter(measure.targets.matches)
        func run(_ values: [String: Double], share: Double) -> Double {
            let selection = ScenarioMeasureSelection(measureID: measure.id, adoption: share, startYear: baseline.baseYear,
                                                     fullYear: baseline.baseYear, parameterOverrides: values)
            return evaluate(baseline, year: year, growth: { _ in 0 }, measures: [(measure, selection)], factors: factors)
                .result.wedges.first?.tonnes ?? 0
        }
        let typical = measure.values().merging(overrides) { $1 }
        let central = run(typical, share: adoption)
        let low = run(measure.values(\.low).merging(overrides) { $1 }, share: adoption)
        let high = run(measure.values(\.high).merging(overrides) { $1 }, share: adoption)
        let matchingTonnes = matching.reduce(0) { $0 + $1.co2eTonnes(baseline.gwp) }
        let full = run(typical, share: 1)
        return MeasurePotential(measureID: measure.id, matchingLineCount: matching.count, matchingTonnes: matchingTonnes,
                                adoption: adoption, typicalTonnes: central,
                                lowTonnes: min(low, high, central), highTonnes: max(low, high, central),
                                cutOfMatchingAtFullAdoption: matchingTonnes > 0 ? full / matchingTonnes : 0,
                                baseTonnes: baseline.totalTonnes,
                                needsInput: measure.parameters.contains { $0.requiresInput && (typical[$0.id] ?? 0) == 0 })
    }

    // MARK: One year

    static func evaluate(_ baseline: ScenarioBaseline,
                         year: Int,
                         growth: (String) -> Double,
                         measures: [(DecarbonizationMeasure, ScenarioMeasureSelection)],
                         factors: @escaping EmissionFactorLookup) -> (result: ScenarioYearResult, warnings: Set<String>) {
        let gwp = baseline.gwp
        let elapsed = Double(max(0, year - baseline.baseYear))
        var lines = baseline.lines.map { line -> ScenarioLine in
            var grown = line
            let rate = growth(line.groupKey)
            if rate != 0 { grown.scale(by: pow(1 + rate, elapsed)) }
            return grown
        }
        let bau = total(lines, gwp)
        let ordered = measures.enumerated()
            .map { index, pair in (index: index, measure: pair.0, selection: pair.1, effect: pair.0.effect(pair.1.values(for: pair.0))) }
            .sorted { ($0.effect.stage, $0.index) < ($1.effect.stage, $1.index) }

        // Grid factor for new load this year, after any grid pathway in the scenario.
        var gridScale = 1.0
        for item in ordered {
            if case .gridEmissionFactorPath(let path) = item.effect {
                gridScale *= gridMultiplier(path, adoption: clamp(item.selection.adoption(in: year)), baseline: baseline, year: year)
            }
        }
        var context = Context(baseline: baseline, year: year, factors: factors,
                              addedLoadFactorKgPerKWh: baseline.gridFactorKgPerKWh * gridScale)

        var wedges: [MeasureWedge] = []
        var removals = 0.0
        for item in ordered {
            let adoption = min(max(item.selection.adoption(in: year), 0), 1)
            guard adoption > 0 else { continue }
            if case .removeCarbon(let tonnes) = item.effect {
                removals += adoption * tonnes
                wedges.append(MeasureWedge(measureID: item.measure.id, tonnes: adoption * tonnes))
                continue
            }
            let before = total(lines, gwp)
            context.measureTitle = item.measure.title
            apply(item.effect, adoption: adoption, selector: item.measure.targets, to: &lines, context: &context)
            wedges.append(MeasureWedge(measureID: item.measure.id, tonnes: before - total(lines, gwp)))
        }
        let result = ScenarioYearResult(year: year, bauTonnes: bau, scenarioTonnes: total(lines, gwp),
                                        removalsTonnes: removals, wedges: wedges)
        return (result, context.warnings)
    }

    // MARK: Effects

    private struct Context {
        let baseline: ScenarioBaseline
        let year: Int
        let factors: EmissionFactorLookup
        /// kg CO2e/kWh for electricity added by fuel switches in this year.
        let addedLoadFactorKgPerKWh: Double
        var measureTitle = ""
        var warnings = Set<String>()

        mutating func warn(_ text: String) { warnings.insert("\(measureTitle): \(text)") }
    }

    private static func apply(_ effect: MeasureEffect, adoption a: Double, selector: SourceSelector,
                              to lines: inout [ScenarioLine], context: inout Context) {
        let matching = lines.indices.filter { selector.matches(lines[$0]) }
        switch effect {
        case .reduceActivity(let fraction):
            let keep = 1 - a * clamp(fraction)
            for index in matching { lines[index].scale(by: keep) }

        case .saveGridElectricity(let kWh):
            let grid = matching.filter { lines[$0].isGridElectricity && (lines[$0].energyKWh ?? 0) > 0 }
            let available = grid.reduce(0) { $0 + (lines[$1].energyKWh ?? 0) }
            guard available > 0 else {
                if kWh > 0 { context.warn("no grid electricity in kWh to save from.") }
                return
            }
            let saved = min(a * kWh, available)
            if a * kWh > available { context.warn("savings capped at the electricity used.") }
            for index in grid { lines[index].scale(by: 1 - saved / available) }

        case .switchToGridElectricity(let ratio):
            for index in matching where !lines[index].isGridElectricity {
                guard let energy = lines[index].energyKWh, energy > 0 else {
                    context.warn("\(lines[index].label) has no energy quantity; it was cut but no electricity was added.")
                    lines[index].scale(by: 1 - a)
                    continue
                }
                let source = lines[index]
                lines[index].scale(by: 1 - a)
                addElectricity(kWh: energy * a * max(ratio, 0), for: source, to: &lines, context: context)
            }

        case .switchToFactor(let externalID, let ratio):
            guard let perKWh = gasesPerUnit(externalID, unit: "kWh", context: &context) else { return }
            for index in matching where !lines[index].isGridElectricity {
                guard let energy = lines[index].energyKWh, energy > 0 else {
                    context.warn("\(lines[index].label) has no energy quantity; skipped.")
                    continue
                }
                let source = lines[index]
                lines[index].scale(by: 1 - a)
                let kWh = energy * a * max(ratio, 0)
                merge(ScenarioLine(id: "\(source.id)→\(externalID)", label: "\(source.label) → switched fuel",
                                   sourceKey: source.sourceKey, groupKey: source.groupKey, carriers: [],
                                   isGridElectricity: false, gases: perKWh.scaled(by: kWh), energyKWh: kWh, massTonnes: nil),
                      into: &lines)
            }

        case .divertWaste(let externalID):
            guard let perTonne = gasesPerUnit(externalID, unit: "t", context: &context) else { return }
            for index in matching {
                let source = lines[index]
                lines[index].scale(by: 1 - a)
                guard let mass = source.massTonnes, mass > 0 else {
                    context.warn("\(source.label) has no tonnage; treatment emissions of the diverted waste are not added.")
                    continue
                }
                let diverted = mass * a
                merge(ScenarioLine(id: "\(source.id)→\(externalID)", label: "\(source.label) → diverted",
                                   sourceKey: source.sourceKey, groupKey: source.groupKey, carriers: [],
                                   isGridElectricity: false, gases: perTonne.scaled(by: diverted), energyKWh: nil, massTonnes: diverted),
                      into: &lines)
            }

        case .reduceFossilCO2(let fraction):
            let keep = 1 - a * clamp(fraction)
            for index in matching { lines[index].gases.co2 *= keep }

        case .reduceMethane(let fraction):
            let keep = 1 - a * clamp(fraction)
            for index in matching {
                lines[index].gases.ch4Fossil *= keep
                lines[index].gases.ch4NonFossil *= keep
            }

        case .replaceGridSupply:
            for index in matching where lines[index].isGridElectricity {
                lines[index].gases = lines[index].gases.scaled(by: 1 - a)
            }

        case .gridEmissionFactorPath(let path):
            let factor = gridMultiplier(path, adoption: a, baseline: context.baseline, year: context.year)
            for index in matching where lines[index].isGridElectricity && !lines[index].isAddedLoad {
                lines[index].gases = lines[index].gases.scaled(by: factor)
            }

        case .removeCarbon:
            break // handled by the caller: removals are reported separately
        }
    }

    /// Multiplier on base-year grid emissions for a grid pathway at the given adoption.
    static func gridMultiplier(_ path: [YearValue], adoption: Double, baseline: ScenarioBaseline, year: Int) -> Double {
        let base = baseline.gridFactorKgPerKWh
        guard base > 0 else { return 1 }
        let target = gridFactor(in: year, base: YearValue(year: baseline.baseYear, value: base), path: path)
        return max(0, 1 - adoption * (1 - target / base))
    }

    /// Grid factor in `year`, interpolated linearly through the path; flat after its last point.
    static func gridFactor(in year: Int, base: YearValue, path: [YearValue]) -> Double {
        let points = [base] + path.filter { $0.year > base.year }.sorted { $0.year < $1.year }
        if year <= base.year { return base.value }
        for (from, to) in zip(points, points.dropFirst()) where year <= to.year {
            return from.value + (to.value - from.value) * Double(year - from.year) / Double(to.year - from.year)
        }
        return points.last?.value ?? base.value
    }

    // MARK: Helpers

    private static func addElectricity(kWh: Double, for source: ScenarioLine, to lines: inout [ScenarioLine], context: Context) {
        guard kWh > 0 else { return }
        let key = context.baseline.electricitySourceKey(source.sourceKey)
        let co2 = kWh * context.addedLoadFactorKgPerKWh / 1_000
        merge(ScenarioLine(id: "electricity:\(key)", label: "New grid electricity (\(key))", sourceKey: key,
                           groupKey: source.groupKey, carriers: [.gridElectricity], isGridElectricity: true,
                           gases: GasAmounts(co2: co2), energyKWh: kWh, massTonnes: nil, isAddedLoad: true),
              into: &lines)
    }

    /// Adds a synthetic line, or grows an existing one with the same id.
    private static func merge(_ line: ScenarioLine, into lines: inout [ScenarioLine]) {
        if let index = lines.firstIndex(where: { $0.id == line.id }) {
            lines[index].gases = lines[index].gases + line.gases
            lines[index].energyKWh = (lines[index].energyKWh ?? 0) + (line.energyKWh ?? 0)
            lines[index].massTonnes = (lines[index].massTonnes ?? 0) + (line.massTonnes ?? 0)
        } else {
            lines.append(line)
        }
    }

    /// Gas masses (tonnes) per one `unit` of a library factor.
    private static func gasesPerUnit(_ externalID: String, unit: String, context: inout Context) -> GasAmounts? {
        guard let factor = context.factors(externalID),
              let result = try? EmissionCalculator.calculate(quantity: 1, unit: unit, factor: factor, gwp: context.baseline.gwp) else {
            context.warn("factor \(externalID) is missing from the library.")
            return nil
        }
        return result.gasesKg.scaled(by: 0.001)
    }

    private static func total(_ lines: [ScenarioLine], _ gwp: GWPSet) -> Double {
        lines.reduce(0) { $0 + $1.co2eTonnes(gwp) }
    }

    private static func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

// MARK: - Starter scenario

nonisolated extension DecarbonizationScenario {
    /// A first pathway: every measure that applies to the baseline, needs no local input
    /// and cuts emissions by the target year (judged alongside the grid pathway, since a
    /// fuel switch onto today's grid can add emissions), at its default adoption, rolled
    /// out from next year to the target year.
    static func starter(for baseline: ScenarioBaseline,
                        targetYear: Int? = nil,
                        catalog: [DecarbonizationMeasure] = DecarbonizationMeasureCatalog.measures,
                        factors: @escaping EmissionFactorLookup = DecarbonizationEngine.libraryFactors) -> DecarbonizationScenario {
        let target = targetYear ?? baseline.baseYear + 10
        let start = min(baseline.baseYear + 1, target)
        let candidates = catalog.filter { measure in
            !measure.needsInput && baseline.lines.contains(where: measure.targets.matches)
        }
        let gridPathways = candidates.filter { $0.effect($0.values()).stage == .grid }

        func cutsEmissions(_ measure: DecarbonizationMeasure) -> Bool {
            let together = gridPathways.filter { $0.id != measure.id } + [measure]
            let selections = together.map { item in
                (item, ScenarioMeasureSelection(measureID: item.id, adoption: item.defaultAdoption, startYear: target, fullYear: target))
            }
            return DecarbonizationEngine.evaluate(baseline, year: target, growth: { _ in 0 }, measures: selections, factors: factors)
                .result.wedge(measure.id) > 0
        }

        let measures = candidates.filter(cutsEmissions)
            .map { ScenarioMeasureSelection(measureID: $0.id, adoption: $0.defaultAdoption, startYear: start, fullYear: target) }
        return DecarbonizationScenario(name: "Low-Carbon Pathway \(target)", targetYear: target, measures: measures)
    }
}
