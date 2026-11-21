import Foundation

/// Worked example: a 2035 low-carbon pathway and action plan for the Iritty inventory.
///
/// ILLUSTRATIVE, like the inventory itself. Owners are the agencies that usually
/// deliver each measure in Kerala; adoption levels, years and the goal are example
/// choices. Only rooftop solar is costed, from the public figures below; every
/// other cost is left blank for local quotes.
nonisolated enum GPCExamplePathways {

    /// The Iritty example inventory with its example pathway and action plan.
    static func irittyWithPathway() -> GPCInventory {
        var inventory = GPCExampleInventories.iritty()
        inventory.decarbonizationScenarios = [irittyPathway(for: inventory)]
        return inventory
    }

    // MARK: Inputs for the costed measure (rooftop solar)

    enum Solar {
        /// Installed cost, ₹ per kWp. 2026 market guides put residential rooftop solar at
        /// about ₹45,000–65,000 per kWp; mid-range value.
        static let costPerKWp = 55_000.0
        /// kWh per kWp per year. KSEB: 4–5.5 units per kWp on a clear day; the monsoon
        /// lowers the yearly average, so a conservative value is used.
        static let yieldKWhPerKWp = 1_300.0
        /// Value of each kWh generated: KSERC average cost of supply for 2025-26, ₹7.17/kWh.
        static let avoidedCostPerKWh = 7.17
        /// Operation and maintenance, share of capital cost per year (assumption).
        static let maintenanceShare = 0.01
        /// Years (assumption: typical panel performance warranty).
        static let lifetimeYears = 25.0
    }

    // MARK: Pathway

    static func irittyPathway(for inventory: GPCInventory) -> DecarbonizationScenario {
        let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: GPCInventorySummary.make(inventory))
        let base = inventory.inventoryYear
        let target = base + 10

        // Activity grows with population: 2011 census to the 2025 projection.
        let years = 2025.0 - 2011.0
        let growth = pow(GPCExampleInventories.Iritty.population2025 / GPCExampleInventories.Iritty.population2011, 1 / years) - 1
        let groups = Set(baseline.lines.map(\.groupKey))

        var scenario = DecarbonizationScenario(
            name: "Iritty Low-Carbon Pathway \(target) (Example)",
            targetYear: target,
            annualGrowth: Dictionary(uniqueKeysWithValues: groups.map { ($0, growth) }))
        scenario.goalType = .baseYear
        scenario.reductionTarget = 0.30

        scenario.measures = examples.compactMap { example in
            guard DecarbonizationMeasureCatalog.measure(example.id) != nil else { return nil }
            var selection = ScenarioMeasureSelection(measureID: example.id, adoption: example.adoption,
                                                     startYear: base + example.startOffset, fullYear: base + example.fullOffset,
                                                     parameterOverrides: example.overrides)
            var plan = ActionPlanItem()
            plan.owner = example.owner
            plan.partners = example.partners
            plan.status = example.status
            plan.funding = example.funding
            plan.fundingNote = example.fundingNote
            plan.notes = example.notes
            selection.plan = plan
            return selection
        }
        costRooftopSolar(&scenario, baseline: baseline)
        return scenario
    }

    /// Sizes the rooftop solar programme from the electricity it replaces and costs it.
    private static func costRooftopSolar(_ scenario: inout DecarbonizationScenario, baseline: ScenarioBaseline) {
        guard let index = scenario.measures.firstIndex(where: { $0.measureID == "rooftop-solar" }),
              let measure = DecarbonizationMeasureCatalog.measure("rooftop-solar") else { return }
        let gridKWh = baseline.lines.filter(measure.targets.matches).reduce(0) { $0 + ($1.energyKWh ?? 0) }
        let solarKWh = gridKWh * scenario.measures[index].adoption
        let capacityKWp = solarKWh / Solar.yieldKWhPerKWp
        let capital = (capacityKWp * Solar.costPerKWp / 100_000).rounded() * 100_000
        var plan = scenario.measures[index].plan ?? ActionPlanItem()
        plan.capitalCost = capital
        plan.lifetimeYears = Solar.lifetimeYears
        plan.annualOperatingCost = (capital * Solar.maintenanceShare / 10_000).rounded() * 10_000
        plan.annualSavings = (solarKWh * Solar.avoidedCostPerKWh / 10_000).rounded() * 10_000
        plan.notes = String(format: """
            Illustrative costing, sized on base-year demand: %.0f kWp at ₹%.0f/kWp (2026 market range ₹45,000–65,000), \
            %.0f kWh/kWp a year (KSEB: 4–5.5 units a day on clear days), savings valued at KSERC's 2025-26 average \
            cost of supply (₹%.2f/kWh). O&M 1%% a year and a 25-year life are assumptions. PM Surya Ghar subsidy \
            lowers household cost, not the cost to society used here.
            """, capacityKWp, Solar.costPerKWp, Solar.yieldKWhPerKWp, Solar.avoidedCostPerKWh)
        scenario.measures[index].plan = plan
    }

    // MARK: Example measures

    private struct Example {
        let id: String
        let adoption: Double
        let startOffset: Int
        let fullOffset: Int
        let owner: String
        let partners: String
        let status: ActionStatus
        let funding: FundingSource?
        let fundingNote: String
        var overrides: [String: Double] = [:]
        var notes = "Illustrative. Cost not estimated: add local quotes."
    }

    private static let examples: [Example] = [
        // Buildings and energy
        Example(id: "biogas-cooking", adoption: 0.05, startOffset: 1, fullOffset: 5,
                owner: "Iritty Municipality (Haritha Keralam Mission)", partners: "Suchitwa Mission, Kudumbashree",
                status: .approved, funding: .stateScheme, fundingNote: "Source-level waste treatment support (check current Suchitwa Mission scheme)"),
        Example(id: "ecbc-buildings", adoption: 0.20, startOffset: 2, fullOffset: 10,
                owner: "Iritty Municipality (building permits)", partners: "Energy Management Centre Kerala",
                status: .proposed, funding: .households, fundingNote: "Developers and owners; enforced through building approvals"),
        Example(id: "rooftop-solar", adoption: 0.20, startOffset: 1, fullOffset: 7,
                owner: "Iritty Municipality with KSEB", partners: "ANERT, empanelled vendors, residents' associations",
                status: .underway, funding: .centralScheme, fundingNote: "PM Surya Ghar: Muft Bijli Yojana (households)"),
        Example(id: "green-power", adoption: 0.10, startOffset: 2, fullOffset: 5,
                owner: "Iritty Municipality (own buildings)", partners: "KSEB",
                status: .proposed, funding: .municipalBudget, fundingNote: "Green tariff or open access for municipal buildings"),
        Example(id: "grid-decarbonisation", adoption: 1.0, startOffset: 1, fullOffset: 7,
                owner: "Government of India (CEA) and KSEB", partners: "",
                status: .underway, funding: .notNeeded, fundingNote: "National power-sector plan; the city tracks it",
                notes: "Follows CEA's National Electricity Plan projection. Outside the city's control."),
        // Transport
        Example(id: "electric-two-wheelers", adoption: 0.30, startOffset: 1, fullOffset: 10,
                owner: "Iritty Municipality (public charging)", partners: "KSEB, Motor Vehicles Department, dealers",
                status: .proposed, funding: .centralScheme, fundingNote: "PM E-DRIVE (e-2W incentives and charging; check eligibility)"),
        Example(id: "electric-cars", adoption: 0.10, startOffset: 3, fullOffset: 10,
                owner: "Vehicle owners; municipality enables charging", partners: "KSEB",
                status: .proposed, funding: .households, fundingNote: ""),
        Example(id: "electric-buses", adoption: 0.30, startOffset: 2, fullOffset: 8,
                owner: "KSRTC", partners: "Iritty Municipality (depot and stops), KSEB",
                status: .proposed, funding: .stateScheme, fundingNote: "KSRTC fleet renewal (check national e-bus scheme eligibility)"),
        Example(id: "electric-waste-trucks", adoption: 0.05, startOffset: 1, fullOffset: 3,
                owner: "Iritty Municipality (health wing)", partners: "Haritha Karma Sena",
                status: .approved, funding: .municipalBudget, fundingNote: "Own fleet replacement"),
        Example(id: "modal-shift", adoption: 0.10, startOffset: 1, fullOffset: 10,
                owner: "Iritty Municipality (town planning)", partners: "KSRTC, Public Works Department",
                status: .proposed, funding: .municipalBudget, fundingNote: "Footpaths, cycle lanes and bus stops"),
        Example(id: "two-wheeler-efficiency", adoption: 0.30, startOffset: 2, fullOffset: 10,
                owner: "Government of India (fuel-efficiency norms)", partners: "",
                status: .proposed, funding: .notNeeded, fundingNote: "National vehicle standards",
                notes: "Outside the city's control."),
        Example(id: "ethanol-blending", adoption: 1.0, startOffset: 2, fullOffset: 5,
                owner: "Government of India (MoPNG)", partners: "Oil marketing companies",
                status: .proposed, funding: .notNeeded, fundingNote: "National blending programme",
                notes: "Assumes a move beyond E20, which has no national plan yet. Outside the city's control."),
        // Waste and wastewater
        Example(id: "waste-reduction", adoption: 0.10, startOffset: 1, fullOffset: 5,
                owner: "Iritty Municipality (Haritha Karma Sena)", partners: "Clean Kerala Company, Suchitwa Mission",
                status: .underway, funding: .centralScheme, fundingNote: "Swachh Bharat Mission-Urban 2.0"),
        Example(id: "septic-to-aerobic-stp", adoption: 0.30, startOffset: 2, fullOffset: 8,
                owner: "Iritty Municipality (engineering wing)", partners: "Kerala Water Authority, Suchitwa Mission",
                status: .proposed, funding: .centralScheme, fundingNote: "AMRUT 2.0 or SBM-U 2.0 used-water component (check)"),
        // Removals
        Example(id: "urban-trees", adoption: 0.80, startOffset: 1, fullOffset: 5,
                owner: "Iritty Municipality (parks)", partners: "Kerala Forest Department (social forestry), schools",
                status: .proposed, funding: .centralScheme, fundingNote: "Nagar Van Yojana (check; runs to 2026-27)",
                overrides: ["trees": 10_000],
                notes: "Illustrative: 10,000 trees. Removals are shown apart from emissions."),
    ]
}
