import Foundation

// Climate action plan: who delivers each measure, when, at what cost and with which
// money — the step after a decarbonisation scenario. Framework-neutral, like the
// scenario engine: a corporate plan can reuse these types.
//
// Saved inside the scenario (`ScenarioMeasureSelection.plan`, `DecarbonizationScenario
// .planSettings`). Decoding tolerates missing keys, so fields can be added later
// without breaking saved inventories.

/// Delivery status of a measure.
nonisolated enum ActionStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case proposed, approved, underway, completed

    var id: String { rawValue }
    var title: String {
        switch self {
        case .proposed: return "Proposed"
        case .approved: return "Approved"
        case .underway: return "Under Way"
        case .completed: return "Completed"
        }
    }
}

/// How far the city government controls a measure.
nonisolated enum CityInfluence: String, Codable, CaseIterable, Identifiable, Sendable {
    /// City-owned assets and services (street lights, waste fleet, parks).
    case direct
    /// The city regulates, incentivises or partners (building rules, solar drives).
    case enable
    /// National or state policy the city can only push for (grid mix, fuel standards).
    case advocate

    var id: String { rawValue }
    var title: String {
        switch self {
        case .direct: return "Direct Control"
        case .enable: return "Enable"
        case .advocate: return "Advocate"
        }
    }
    var detail: String {
        switch self {
        case .direct: return "City-owned assets and services"
        case .enable: return "City regulates, incentivises or partners"
        case .advocate: return "National or state policy"
        }
    }
}

/// Benefits beyond emissions, used to rank and justify measures.
nonisolated enum CoBenefit: String, Codable, CaseIterable, Identifiable, Sendable {
    case airQuality, health, savings, energySecurity, jobs, mobility, sanitation, resourceRecovery, greenSpace, resilience, equity

    var id: String { rawValue }
    var title: String {
        switch self {
        case .airQuality: return "Cleaner Air"
        case .health: return "Public Health"
        case .savings: return "Lower Bills"
        case .energySecurity: return "Energy Security"
        case .jobs: return "Local Jobs"
        case .mobility: return "Better Mobility"
        case .sanitation: return "Sanitation"
        case .resourceRecovery: return "Resource Recovery"
        case .greenSpace: return "Green Space"
        case .resilience: return "Climate Resilience"
        case .equity: return "Access & Equity"
        }
    }
    var systemImage: String {
        switch self {
        case .airQuality: return "aqi.low"
        case .health: return "heart"
        case .savings: return "indianrupeesign.circle"
        case .energySecurity: return "bolt.shield"
        case .jobs: return "person.2"
        case .mobility: return "figure.walk"
        case .sanitation: return "drop"
        case .resourceRecovery: return "arrow.3.trianglepath"
        case .greenSpace: return "tree"
        case .resilience: return "shield.lefthalf.filled"
        case .equity: return "hand.raised"
        }
    }
}

/// Main source of money for a measure.
nonisolated enum FundingSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case municipalBudget, stateScheme, centralScheme, privateInvestment, households, userCharges, bonds, climateFinance, csr, carbonCredits, notNeeded

    var id: String { rawValue }
    var title: String {
        switch self {
        case .municipalBudget: return "Municipal Budget"
        case .stateScheme: return "State Scheme"
        case .centralScheme: return "Central Scheme"
        case .privateInvestment: return "Private Investment / PPP"
        case .households: return "Households and Businesses"
        case .userCharges: return "User Charges or Tariffs"
        case .bonds: return "Municipal or Green Bonds"
        case .climateFinance: return "Climate Finance / Development Bank"
        case .csr: return "CSR Funds"
        case .carbonCredits: return "Carbon Credit Revenue"
        case .notNeeded: return "No City Funding Needed"
        }
    }
}

/// Plan details for one measure in a scenario.
nonisolated struct ActionPlanItem: Codable, Hashable, Sendable {
    /// Lead department or agency.
    var owner = ""
    /// Other agencies, utilities or groups involved.
    var partners = ""
    var status: ActionStatus = .proposed
    /// nil: the catalog suggestion applies.
    var influence: CityInfluence?
    /// nil: the catalog suggestion applies.
    var coBenefits: Set<CoBenefit>?
    var funding: FundingSource?
    /// Scheme, budget line or lender, e.g. "PM Surya Ghar".
    var fundingNote = ""
    /// Total investment to deliver the measure as planned, in the plan currency.
    var capitalCost: Double?
    /// Yearly running cost at full delivery (operation, maintenance, staff).
    var annualOperatingCost: Double?
    /// Yearly savings at full delivery (energy, fuel, avoided disposal).
    var annualSavings: Double?
    /// Years the investment lasts, for annualising the capital cost.
    var lifetimeYears: Double?
    var notes = ""

    init() {}

    var isEmpty: Bool { self == ActionPlanItem() }

    /// Any cost or saving entered.
    var hasCosts: Bool { capitalCost != nil || annualOperatingCost != nil || annualSavings != nil }

    private enum CodingKeys: String, CodingKey {
        case owner, partners, status, influence, coBenefits, funding, fundingNote
        case capitalCost, annualOperatingCost, annualSavings, lifetimeYears, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        owner = try c.decodeIfPresent(String.self, forKey: .owner) ?? ""
        partners = try c.decodeIfPresent(String.self, forKey: .partners) ?? ""
        status = try c.decodeIfPresent(ActionStatus.self, forKey: .status) ?? .proposed
        influence = try c.decodeIfPresent(CityInfluence.self, forKey: .influence)
        coBenefits = try c.decodeIfPresent(Set<CoBenefit>.self, forKey: .coBenefits)
        funding = try c.decodeIfPresent(FundingSource.self, forKey: .funding)
        fundingNote = try c.decodeIfPresent(String.self, forKey: .fundingNote) ?? ""
        capitalCost = try c.decodeIfPresent(Double.self, forKey: .capitalCost)
        annualOperatingCost = try c.decodeIfPresent(Double.self, forKey: .annualOperatingCost)
        annualSavings = try c.decodeIfPresent(Double.self, forKey: .annualSavings)
        lifetimeYears = try c.decodeIfPresent(Double.self, forKey: .lifetimeYears)
        notes = try c.decodeIfPresent(String.self, forKey: .notes) ?? ""
    }
}

/// Plan-wide settings for a scenario.
nonisolated struct ActionPlanSettings: Codable, Hashable, Sendable {
    var currencyCode = "INR"
    /// Real discount rate for annualising capital costs. An assumption: use your
    /// organisation's rate.
    var discountRate = 0.08
    /// Credits from projects outside the boundary planned for the target year.
    /// GPC: reported separately, never deducted from the inventory (Section 4.4, Chapter 11).
    var plannedCreditsTonnes: Double?
    /// Ceiling on credits as a share of target-year gross emissions (GPC Chapter 11
    /// asks cities to cap credits and reduce them over time).
    var creditCapShare: Double?

    init() {}

    private enum CodingKeys: String, CodingKey {
        case currencyCode, discountRate, plannedCreditsTonnes, creditCapShare
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        currencyCode = try c.decodeIfPresent(String.self, forKey: .currencyCode) ?? "INR"
        discountRate = try c.decodeIfPresent(Double.self, forKey: .discountRate) ?? 0.08
        plannedCreditsTonnes = try c.decodeIfPresent(Double.self, forKey: .plannedCreditsTonnes)
        creditCapShare = try c.decodeIfPresent(Double.self, forKey: .creditCapShare)
    }
}

/// GPC Chapter 11 goal types (base-year intensity goals need a population or GDP
/// projection and are not offered yet).
nonisolated enum ScenarioGoalType: String, Codable, CaseIterable, Identifiable, Sendable {
    /// % below base-year emissions.
    case baseYear
    /// % below business as usual in the target year.
    case baselineScenario
    /// An absolute level in the target year (0 = net zero).
    case fixedLevel

    var id: String { rawValue }
    var title: String {
        switch self {
        case .baseYear: return "Below Base Year"
        case .baselineScenario: return "Below Business as Usual"
        case .fixedLevel: return "Fixed Level"
        }
    }
}
