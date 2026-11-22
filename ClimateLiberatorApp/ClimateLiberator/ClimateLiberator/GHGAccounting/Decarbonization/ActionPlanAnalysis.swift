import Foundation

/// Cost and delivery figures for one measure, from its plan and its target-year cut.
nonisolated struct MeasureEconomics: Identifiable, Sendable {
    let measureID: String
    /// Target-year cut credited to the measure (t CO2e; removals for land-use measures).
    let abatementTonnes: Double
    /// Capital cost × capital recovery factor + running cost − savings, per year.
    let annualisedCost: Double?
    let capitalCost: Double?

    var id: String { measureID }

    /// Cost per tonne in the target year. Negative = the measure saves money.
    /// nil when costs are missing or the measure does not cut emissions.
    var costPerTonne: Double? {
        guard let annualisedCost, abatementTonnes > 0 else { return nil }
        return annualisedCost / abatementTonnes
    }
}

/// Why a measure has no cost per tonne, so the plan can say what to fix.
nonisolated enum CostGap: String, Sendable {
    /// Adoption is 0% in the scenario, so the measure does nothing.
    case noAdoption
    /// The rollout starts after the target year.
    case startsAfterTarget
    /// It adds emissions in the target year (e.g. a fuel switch onto today's grid).
    case addsEmissions
    /// It cuts nothing: no matching sources in the inventory, or a required input is 0.
    case noCut
    /// A capital cost without a lifetime cannot be annualised.
    case needsLifetime
    /// No costs or savings entered.
    case noCosts

    /// A few words for the measure list.
    var label: String {
        switch self {
        case .noAdoption: return "0% adoption"
        case .startsAfterTarget: return "Starts too late"
        case .addsEmissions: return "Adds emissions"
        case .noCut: return "No cut"
        case .needsLifetime: return "Add lifetime"
        case .noCosts: return "No cost"
        }
    }

    /// What is wrong and how to fix it.
    func advice(targetYear: Int) -> String {
        switch self {
        case .noAdoption: return "Adoption is 0% in Scenarios, so it cuts nothing. Raise its adoption."
        case .startsAfterTarget: return "Rollout starts after \(String(targetYear)). Move the start year earlier in Scenarios."
        case .addsEmissions: return "It adds emissions in \(String(targetYear)), so it has no cost per tonne cut."
        case .noCut: return "It cuts nothing in \(String(targetYear)). Check its inputs in Scenarios and the matching inventory sources."
        case .needsLifetime: return "Add a lifetime to spread the capital cost."
        case .noCosts: return "Enter costs to calculate."
        }
    }

    /// The problem is the measure's cut (fixed in Scenarios), not its costs.
    var isAboutTheCut: Bool { self != .needsLifetime && self != .noCosts }
}

/// Something missing or inconsistent in one measure's plan.
nonisolated struct PlanIssue: Identifiable, Hashable, Sendable {
    enum Kind: Hashable, Sendable {
        /// No cost per tonne for a reason other than missing costs.
        case cost(CostGap)
        case noOwner
        case noFunding
        /// Marked Under Way or Completed, but the rollout starts in a later year.
        case startedBeforeRollout(startYear: Int)
        /// Marked Completed, but full adoption is planned for a later year.
        case completedBeforeRollout(fullYear: Int)
    }

    let measureID: String
    let kind: Kind

    var id: String { "\(measureID)|\(kind)" }

    /// Changes the plan's figures, not only its paperwork.
    var affectsFigures: Bool {
        if case .cost = kind { return true }
        return false
    }

    func message(targetYear: Int) -> String {
        switch kind {
        case .cost(let gap): return gap.advice(targetYear: targetYear)
        case .noOwner: return "No owner assigned."
        case .noFunding: return "No funding source set."
        case .startedBeforeRollout(let year): return "Status says work has started, but the rollout begins in \(String(year))."
        case .completedBeforeRollout(let year): return "Marked Completed, but full adoption is planned for \(String(year))."
        }
    }
}

/// One bar of a marginal abatement cost curve.
nonisolated struct MACSegment: Identifiable, Sendable {
    let measureID: String
    let startTonnes: Double
    let endTonnes: Double
    let costPerTonne: Double
    var id: String { measureID }
    var widthTonnes: Double { endTonnes - startTonnes }
}

/// Measures and target-year cut behind one co-benefit.
nonisolated struct CoBenefitCoverage: Identifiable, Sendable {
    let benefit: CoBenefit
    let measures: Int
    let tonnes: Double
    var id: CoBenefit { benefit }
}

/// Plan-wide figures shown above the action plan.
nonisolated struct ActionPlanSummary: Sendable {
    let economics: [MeasureEconomics]
    let measureCount: Int
    /// Target-year cut of all measures (t CO2e).
    let totalCutTonnes: Double
    /// Part of that cut whose measures have costs entered.
    let costedCutTonnes: Double
    let totalCapitalCost: Double
    /// Annualised cost of the costed measures.
    let totalAnnualisedCost: Double
    let ownersAssigned: Int
    let fundingAssigned: Int
    /// Why each measure without a cost per tonne has none, by measure ID.
    let gaps: [String: CostGap]
    /// Measures with costs entered that cannot be drawn on the cost curve, in catalog order.
    let notCharted: [String]

    var costedCount: Int { economics.filter { $0.costPerTonne != nil }.count }

    /// Cut-weighted average cost per tonne of the costed measures.
    var averageCostPerTonne: Double? { costedCutTonnes > 0 ? totalAnnualisedCost / costedCutTonnes : nil }
    var costedShare: Double { totalCutTonnes > 0 ? costedCutTonnes / totalCutTonnes : 0 }
}

/// Residual emissions in the target year, reported the GPC way: gross emissions,
/// in-boundary removals and credits from outside the boundary kept apart.
nonisolated struct ResidualEmissions: Sendable {
    let grossTonnes: Double
    let removalsTonnes: Double
    let creditsTonnes: Double
    /// Ceiling on credits, if the plan sets one.
    let creditCapTonnes: Double?

    var netOfRemovals: Double { grossTonnes - removalsTonnes }
    var netWithCredits: Double { netOfRemovals - creditsTonnes }
    var exceedsCap: Bool { creditCapTonnes.map { creditsTonnes > $0 + 0.5 } ?? false }
}

/// Turns a scenario's plan into costs, a MAC curve, co-benefit coverage and CSV.
nonisolated enum ActionPlanAnalysis {

    /// Share of a capital cost paid each year over `years` at discount `rate`.
    static func capitalRecoveryFactor(rate: Double, years: Double) -> Double {
        guard years > 0 else { return 0 }
        guard rate > 0 else { return 1 / years }
        let growth = pow(1 + rate, years)
        return rate * growth / (growth - 1)
    }

    static func economics(of selection: ScenarioMeasureSelection, abatementTonnes: Double,
                          discountRate: Double) -> MeasureEconomics {
        let plan = selection.plan ?? ActionPlanItem()
        let running = (plan.annualOperatingCost ?? 0) - (plan.annualSavings ?? 0)
        let annualised: Double?
        if let capital = plan.capitalCost, capital != 0 {
            // A capital cost without a lifetime cannot be annualised.
            if let years = plan.lifetimeYears, years > 0 {
                annualised = capital * capitalRecoveryFactor(rate: discountRate, years: years) + running
            } else {
                annualised = nil
            }
        } else {
            annualised = plan.annualOperatingCost != nil || plan.annualSavings != nil ? running : nil
        }
        return MeasureEconomics(measureID: selection.measureID, abatementTonnes: abatementTonnes,
                                annualisedCost: annualised, capitalCost: plan.capitalCost)
    }

    /// Why a measure has no cost per tonne; nil when it has one. Cut problems come
    /// first: costs cannot help a measure that cuts nothing.
    static func costGap(of selection: ScenarioMeasureSelection, economics: MeasureEconomics, targetYear: Int) -> CostGap? {
        guard economics.costPerTonne == nil else { return nil }
        if selection.adoption <= 0 { return .noAdoption }
        if selection.startYear > targetYear { return .startsAfterTarget }
        if economics.abatementTonnes < 0 { return .addsEmissions }
        if economics.abatementTonnes == 0 { return .noCut }
        let plan = selection.plan ?? ActionPlanItem()
        if let capital = plan.capitalCost, capital != 0, (plan.lifetimeYears ?? 0) <= 0 { return .needsLifetime }
        return .noCosts
    }

    static func summary(of scenario: DecarbonizationScenario, result: ScenarioYearResult?) -> ActionPlanSummary {
        let rate = scenario.settings.discountRate
        var items: [MeasureEconomics] = []
        var gaps: [String: CostGap] = [:]
        var notCharted: [String] = []
        for selection in scenario.measures {
            let item = Self.economics(of: selection, abatementTonnes: result?.wedge(selection.measureID) ?? 0, discountRate: rate)
            items.append(item)
            guard let gap = costGap(of: selection, economics: item, targetYear: scenario.targetYear) else { continue }
            gaps[selection.measureID] = gap
            if selection.plan?.hasCosts == true { notCharted.append(selection.measureID) }
        }
        let costed = items.filter { $0.costPerTonne != nil }
        return ActionPlanSummary(
            economics: items,
            measureCount: scenario.measures.count,
            totalCutTonnes: items.reduce(0) { $0 + max(0, $1.abatementTonnes) },
            costedCutTonnes: costed.reduce(0) { $0 + $1.abatementTonnes },
            totalCapitalCost: items.reduce(0) { $0 + ($1.capitalCost ?? 0) },
            totalAnnualisedCost: costed.reduce(0) { $0 + ($1.annualisedCost ?? 0) },
            ownersAssigned: scenario.measures.filter { !($0.plan?.owner ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count,
            fundingAssigned: scenario.measures.filter { $0.plan?.funding != nil }.count,
            gaps: gaps,
            notCharted: notCharted.sorted { DecarbonizationMeasureCatalog.position(of: $0) < DecarbonizationMeasureCatalog.position(of: $1) })
    }

    /// Gaps and contradictions to fix before the plan is shared: issues that change the
    /// figures first, then missing owners and funding, then status/timeline clashes.
    /// Missing costs alone are not listed; the metrics already count costed measures.
    static func issues(of scenario: DecarbonizationScenario, summary: ActionPlanSummary, currentYear: Int) -> [PlanIssue] {
        var issues: [PlanIssue] = []
        for selection in scenario.measures {
            let id = selection.measureID
            let plan = selection.plan ?? ActionPlanItem()
            if let gap = summary.gaps[id], gap != .noCosts { issues.append(PlanIssue(measureID: id, kind: .cost(gap))) }
            if plan.owner.trimmingCharacters(in: .whitespaces).isEmpty { issues.append(PlanIssue(measureID: id, kind: .noOwner)) }
            if plan.funding == nil { issues.append(PlanIssue(measureID: id, kind: .noFunding)) }
            switch plan.status {
            case .underway where selection.startYear > currentYear, .completed where selection.startYear > currentYear:
                issues.append(PlanIssue(measureID: id, kind: .startedBeforeRollout(startYear: selection.startYear)))
            case .completed where selection.fullYear > currentYear:
                issues.append(PlanIssue(measureID: id, kind: .completedBeforeRollout(fullYear: selection.fullYear)))
            default:
                break
            }
        }
        func rank(_ issue: PlanIssue) -> Int {
            switch issue.kind {
            case .cost: return 0
            case .noOwner, .noFunding: return 1
            case .startedBeforeRollout, .completedBeforeRollout: return 2
            }
        }
        return issues.enumerated().sorted { lhs, rhs in
            (rank(lhs.element), DecarbonizationMeasureCatalog.position(of: lhs.element.measureID), lhs.offset)
                < (rank(rhs.element), DecarbonizationMeasureCatalog.position(of: rhs.element.measureID), rhs.offset)
        }.map { $0.element }
    }

    /// Measures ordered from cheapest to dearest per tonne, laid end to end by tonnes cut.
    static func macCurve(_ economics: [MeasureEconomics]) -> [MACSegment] {
        var start = 0.0
        return economics
            .compactMap { item in item.costPerTonne.map { (item, $0) } }
            .sorted { $0.1 < $1.1 }
            .map { item, cost in
                defer { start += item.abatementTonnes }
                return MACSegment(measureID: item.measureID, startTonnes: start,
                                  endTonnes: start + item.abatementTonnes, costPerTonne: cost)
            }
    }

    /// For each co-benefit: how many measures deliver it and their combined cut.
    static func coBenefitCoverage(of scenario: DecarbonizationScenario,
                                  result: ScenarioYearResult?) -> [CoBenefitCoverage] {
        CoBenefit.allCases.compactMap { benefit in
            let matching = scenario.measures.filter { ActionPlanCatalog.coBenefits(of: $0).contains(benefit) }
            guard !matching.isEmpty else { return nil }
            let tonnes = matching.reduce(0) { $0 + max(0, result?.wedge($1.measureID) ?? 0) }
            return CoBenefitCoverage(benefit: benefit, measures: matching.count, tonnes: tonnes)
        }
    }

    static func residualEmissions(of scenario: DecarbonizationScenario, result: ScenarioYearResult?) -> ResidualEmissions {
        let gross = result?.scenarioTonnes ?? 0
        let settings = scenario.settings
        return ResidualEmissions(grossTonnes: gross,
                                 removalsTonnes: result?.removalsTonnes ?? 0,
                                 creditsTonnes: max(0, settings.plannedCreditsTonnes ?? 0),
                                 creditCapTonnes: settings.creditCapShare.map { gross * $0 })
    }

    // MARK: Export

    private static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private static func number(_ value: Double) -> String { String(format: "%.3f", value) }

    static func csv(_ scenario: DecarbonizationScenario, result: ScenarioYearResult?) -> String {
        let currency = scenario.settings.currencyCode
        let rate = scenario.settings.discountRate
        let header = [
            "Measure", "Category", "City influence", "Status", "Owner", "Partners",
            "Start year", "Full year", "Adoption", "Cut in \(scenario.targetYear) (tCO2e)",
            "Capital cost (\(currency))", "Annual running cost (\(currency))", "Annual savings (\(currency))",
            "Lifetime (years)", "Cost per tonne (\(currency)/tCO2e)", "Funding", "Funding note", "Co-benefits", "Notes",
        ]
        var lines = [header.map(field).joined(separator: ",")]
        let ordered = scenario.measures.sorted {
            DecarbonizationMeasureCatalog.position(of: $0.measureID) < DecarbonizationMeasureCatalog.position(of: $1.measureID)
        }
        for selection in ordered {
            let measure = DecarbonizationMeasureCatalog.measure(selection.measureID)
            let plan = selection.plan ?? ActionPlanItem()
            let cut = result?.wedge(selection.measureID) ?? 0
            let money = economics(of: selection, abatementTonnes: cut, discountRate: rate)
            let benefits = CoBenefit.allCases.filter(ActionPlanCatalog.coBenefits(of: selection).contains).map(\.title)
            let row: [String] = [
                measure?.title ?? selection.measureID,
                measure?.category.title ?? "",
                ActionPlanCatalog.influence(of: selection).title,
                plan.status.title,
                plan.owner,
                plan.partners,
                String(selection.startYear),
                String(selection.fullYear),
                String(format: "%.0f%%", selection.adoption * 100),
                number(cut),
                plan.capitalCost.map { String(format: "%.0f", $0) } ?? "",
                plan.annualOperatingCost.map { String(format: "%.0f", $0) } ?? "",
                plan.annualSavings.map { String(format: "%.0f", $0) } ?? "",
                plan.lifetimeYears.map { String(format: "%g", $0) } ?? "",
                money.costPerTonne.map { String(format: "%.0f", $0) } ?? "",
                plan.funding?.title ?? "",
                plan.fundingNote,
                benefits.joined(separator: "; "),
                plan.notes,
            ]
            lines.append(row.map(field).joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func pathwayCSV(_ projection: ScenarioProjection) -> String {
        var lines = ["Year,Business as usual (tCO2e),Scenario gross (tCO2e),Removals (tCO2e),Scenario net (tCO2e)"]
        for year in projection.years {
            lines.append([String(year.year), number(year.bauTonnes), number(year.scenarioTonnes),
                          number(year.removalsTonnes), number(year.netTonnes)].joined(separator: ","))
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
