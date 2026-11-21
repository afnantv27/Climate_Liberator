import Foundation

// Thin adapters to other modules. Only this folder knows about GHG Accounting and the
// wildfire evidence pipeline; the rest of the Disclosure module stays independent.

// MARK: - GHG Accounting

/// Scope totals from a GHG Accounting inventory, ready to import.
nonisolated struct GHGInventoryTotals: Identifiable, Hashable, Sendable {
    let id: UUID
    let name: String
    let year: Int
    let scope1: Double
    let scope2: Double
    let scope3: Double
    let isUnsaved: Bool

    var sourceNote: String { "GHG Accounting inventory “\(name)”" }
}

enum GHGInventoryBridge {
    /// UserDefaults key the GHG Accounting workspace reads when it appears.
    static let pendingToolKey = GHGTool.pendingRequestKey

    static func totals(from store: GPCInventoryStore) -> [GHGInventoryTotals] {
        store.inventories.map { totals(for: $0, isUnsaved: store.isUnsaved($0.id)) }
    }

    /// Scope 1 includes every in-boundary source; Scope 3 includes "other scope 3".
    nonisolated static func totals(for inventory: GPCInventory, isUnsaved: Bool = false) -> GHGInventoryTotals {
        let summary = GPCInventorySummary.make(inventory)
        return GHGInventoryTotals(id: inventory.id, name: inventory.displayName, year: inventory.inventoryYear,
                                  scope1: summary.territorialTotal, scope2: summary.scope2Total,
                                  scope3: summary.scope3Total + summary.otherScope3Total, isUnsaved: isUnsaved)
    }

    /// Opens the emission-factor calculator when the GHG Accounting workspace appears.
    static func requestCalculator() {
        UserDefaults.standard.set(GHGTool.calculator.rawValue, forKey: pendingToolKey)
    }
}

// MARK: - Wildfire simulation packages

/// A simulation evidence package that can back a physical-risk assessment.
nonisolated struct SimulationEvidenceCandidate: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let generatedAt: Date
    let folderPath: String
    let scenario: String
    let horizon: String
    let burntPercent: Double?
    let exposureCrore: Double?
    let grossLossCrore: Double?
    let insuredLossCrore: Double?
}

enum WildfireEvidenceBridge {
    static func candidates(from store: TCFDReviewStore) -> [SimulationEvidenceCandidate] {
        store.bundles.map { candidate($0) }
    }

    static func candidate(_ bundle: TCFDRunArtifactBundle) -> SimulationEvidenceCandidate {
        let effects = bundle.reviewRecord?.financialEffects
        // Package amounts are in the package currency; only rupees convert to crore.
        let isRupees = (effects?.currencyCode ?? "INR").uppercased() == "INR"
        func crore(_ value: Double?) -> Double? {
            guard isRupees, let value else { return nil }
            return value / 10_000_000
        }
        let scenario = [bundle.scenarioName, bundle.tcfdScenarioLabel, bundle.scenarioPathway]
            .compactMap { $0 }.filter { !$0.isEmpty }.first ?? "Wildfire run"
        return SimulationEvidenceCandidate(id: bundle.runID,
                                           title: "Wildfire simulation \(bundle.runID)",
                                           generatedAt: bundle.generatedAt,
                                           folderPath: bundle.bundleURL,
                                           scenario: scenario,
                                           horizon: bundle.scenarioHorizon ?? "",
                                           burntPercent: bundle.totalBurntPercent,
                                           exposureCrore: crore(effects?.exposureValue),
                                           grossLossCrore: crore(effects?.estimatedGroundUpLoss),
                                           insuredLossCrore: crore(effects?.estimatedInsuredLoss))
    }
}

// MARK: - Physical-risk drafting

/// Draft IFRS S2 text for physical-risk assessments. Wildfire assessments reuse the
/// platform's IFRS S2 report surface (which describes the Cell2Fire pipeline); other
/// hazards get a neutral description.
enum PhysicalRiskDrafting {
    static func paragraphs(for engagement: DisclosureEngagement) -> [String] {
        engagement.physicalRisks.compactMap { paragraph(for: $0, engagement: engagement) }
    }

    static func paragraph(for risk: PhysicalRiskAssessment, engagement: DisclosureEngagement) -> String? {
        guard let assessed = risk.valueAssessedCrore, assessed > 0 else { return nil }
        if risk.hazard == .wildfire {
            let surface = DisclosureReportSurface(entityName: engagement.companyName, reportingPeriod: engagement.periodLabel)
            let result = PortfolioLossResult(peril: .wildfire, assetCount: risk.assetsAssessed ?? 0,
                                             totalInsuredValue: assessed * 10_000_000,
                                             groundUpLoss: (risk.grossLossCrore ?? 0) * 10_000_000,
                                             insuredLoss: (risk.insuredLossCrore ?? 0) * 10_000_000)
            var text = surface.render(result).strategy.joined(separator: " ")
            if let share = risk.vulnerableShare {
                text += " Assets worth \(DisclosureFormat.value(risk.valueVulnerableCrore, unit: "₹ crore")) (\(DisclosureFormat.percent(share)) of value assessed) lie within the modelled hazard footprint."
            }
            return text
        }
        var sentences: [String] = []
        let context = [risk.scenario, risk.horizon].filter { !$0.isEmpty }.joined(separator: ", ")
        let assets = risk.assetsAssessed.map { "\($0) assets" } ?? "assets"
        sentences.append("\(risk.hazard.title) risk was assessed for \(assets) worth \(DisclosureFormat.value(assessed, unit: "₹ crore"))\(context.isEmpty ? "" : " under \(context)").")
        if let share = risk.vulnerableShare {
            sentences.append("Assets worth \(DisclosureFormat.value(risk.valueVulnerableCrore, unit: "₹ crore")) (\(DisclosureFormat.percent(share))) were found vulnerable.")
        }
        if let gross = risk.grossLossCrore {
            sentences.append("Modelled gross loss is \(DisclosureFormat.value(gross, unit: "₹ crore")) (\(DisclosureFormat.percent(gross / assessed)) of value assessed).")
        }
        if let insured = risk.insuredLossCrore {
            sentences.append("Estimated net insured loss is \(DisclosureFormat.value(insured, unit: "₹ crore")).")
        }
        return sentences.joined(separator: " ")
    }
}
