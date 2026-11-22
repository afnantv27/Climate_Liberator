import Foundation

// A client's reduction plan: targets, measures and carbon credits. One file per
// client (the plan's id is the client's id). Emissions themselves are not stored
// here; they come from the client's reported figures (`ClientYearFigures`).

// MARK: - Targets

nonisolated enum TargetKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case absolute, intensityRevenue, intensityOutput

    var id: String { rawValue }
    var title: String {
        switch self {
        case .absolute: return "Absolute"
        case .intensityRevenue: return "Intensity per revenue"
        case .intensityOutput: return "Intensity per output"
        }
    }
}

/// Why the target exists; decides which reference checks are shown.
nonisolated enum TargetFramework: String, Codable, CaseIterable, Identifiable, Sendable {
    case sbtiNearTerm, ccts, customer, voluntary

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sbtiNearTerm: return "SBTi near-term"
        case .ccts: return "CCTS intensity target"
        case .customer: return "Customer requirement"
        case .voluntary: return "Own commitment"
        }
    }
}

nonisolated struct ReductionTarget: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var coverage: EmissionScopeCoverage = .scope12
    var kind: TargetKind = .absolute
    var framework: TargetFramework = .voluntary
    /// Financial years by start year (2023 = FY 2023-24).
    var baseYear: Int
    var targetYear: Int
    /// Reduction from the base-year value, in percent (42 = 42%).
    var reductionPercent: Double = 42
    /// Base-year value to use instead of reported figures (e.g. a recalculated baseline).
    var baseValueOverride: Double?
    /// Minimum linear reduction per year (percent of base) the target must reach.
    var minimumAnnualRate: Double = 4.2
    var notes = ""

    init(baseYear: Int, targetYear: Int) {
        self.baseYear = baseYear
        self.targetYear = targetYear
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        return "\(DisplayFormat.number(reductionPercent))% \(coverage.title) by \(ReportingPeriod.label(targetYear))"
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, coverage, kind, framework, baseYear, targetYear, reductionPercent, baseValueOverride, minimumAnnualRate, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        name = try c.value(.name, default: "")
        coverage = try c.value(.coverage, default: .scope12)
        kind = try c.value(.kind, default: .absolute)
        framework = try c.value(.framework, default: .voluntary)
        baseYear = try c.value(.baseYear, default: 2023)
        targetYear = try c.value(.targetYear, default: 2030)
        reductionPercent = try c.value(.reductionPercent, default: 42)
        baseValueOverride = try c.decodeIfPresent(Double.self, forKey: .baseValueOverride)
        minimumAnnualRate = try c.value(.minimumAnnualRate, default: 4.2)
        notes = try c.value(.notes, default: "")
    }
}

// MARK: - Measures

nonisolated enum MeasureStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case idea, planned, inProgress, done

    var id: String { rawValue }
    var title: String {
        switch self {
        case .idea: return "Idea"
        case .planned: return "Planned"
        case .inProgress: return "In progress"
        case .done: return "Done"
        }
    }
    /// Ideas are not counted towards the projected pathway.
    var isCommitted: Bool { self != .idea }
}

nonisolated enum MeasureScope: String, Codable, CaseIterable, Identifiable, Sendable {
    case scope1, scope2, scope3

    var id: String { rawValue }
    var title: String {
        switch self {
        case .scope1: return "Scope 1"
        case .scope2: return "Scope 2"
        case .scope3: return "Scope 3"
        }
    }
    func isCovered(by coverage: EmissionScopeCoverage) -> Bool {
        switch coverage {
        case .scope12: return self != .scope3
        case .scope3: return self == .scope3
        case .scope123: return true
        }
    }
}

/// One reduction action, e.g. "Rooftop solar 500 kWp" or "Boiler fuel switch to biomass".
nonisolated struct ReductionMeasure: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title = ""
    var scope: MeasureScope = .scope2
    /// First financial year the measure cuts emissions.
    var startYear: Int
    /// Emissions avoided per year once running (tCO2e).
    var annualAbatement: Double?
    /// ₹ — capital, yearly running cost, yearly savings.
    var capitalCost: Double?
    var annualOperatingCost: Double?
    var annualSavings: Double?
    var lifetimeYears: Double?
    var status: MeasureStatus = .planned
    var owner = ""
    var notes = ""

    init(startYear: Int) {
        self.startYear = startYear
    }

    var displayName: String {
        let trimmed = title.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled measure" : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, scope, startYear, annualAbatement, capitalCost, annualOperatingCost, annualSavings, lifetimeYears
        case status, owner, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        title = try c.value(.title, default: "")
        scope = try c.value(.scope, default: .scope2)
        startYear = try c.value(.startYear, default: 2026)
        annualAbatement = try c.decodeIfPresent(Double.self, forKey: .annualAbatement)
        capitalCost = try c.decodeIfPresent(Double.self, forKey: .capitalCost)
        annualOperatingCost = try c.decodeIfPresent(Double.self, forKey: .annualOperatingCost)
        annualSavings = try c.decodeIfPresent(Double.self, forKey: .annualSavings)
        lifetimeYears = try c.decodeIfPresent(Double.self, forKey: .lifetimeYears)
        status = try c.value(.status, default: .planned)
        owner = try c.value(.owner, default: "")
        notes = try c.value(.notes, default: "")
    }
}

// MARK: - Carbon credits

nonisolated enum CreditRegistry: String, Codable, CaseIterable, Identifiable, Sendable {
    case verra, goldStandard, indianCarbonMarket, globalCarbonCouncil, puroEarth, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .verra: return "Verra (VCS)"
        case .goldStandard: return "Gold Standard"
        case .indianCarbonMarket: return "Indian Carbon Market"
        case .globalCarbonCouncil: return "Global Carbon Council"
        case .puroEarth: return "Puro.earth"
        case .other: return "Other"
        }
    }
}

nonisolated enum CreditProjectType: String, Codable, CaseIterable, Identifiable, Sendable {
    case renewableEnergy, energyEfficiency, cookstoves, methaneAvoidance, avoidedDeforestation
    case afforestation, soilCarbon, biochar, engineeredRemoval, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .renewableEnergy: return "Renewable energy"
        case .energyEfficiency: return "Energy efficiency"
        case .cookstoves: return "Clean cookstoves"
        case .methaneAvoidance: return "Methane capture / avoidance"
        case .avoidedDeforestation: return "Avoided deforestation (REDD+)"
        case .afforestation: return "Afforestation / reforestation"
        case .soilCarbon: return "Soil carbon"
        case .biochar: return "Biochar"
        case .engineeredRemoval: return "Engineered removal (e.g. DAC)"
        case .other: return "Other"
        }
    }
    /// Removals take carbon out of the atmosphere; the rest avoid or reduce emissions.
    var isRemoval: Bool {
        switch self {
        case .afforestation, .soilCarbon, .biochar, .engineeredRemoval: return true
        default: return false
        }
    }
}

nonisolated enum CreditStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case held, retired, cancelled

    var id: String { rawValue }
    var title: String {
        switch self {
        case .held: return "Held"
        case .retired: return "Retired"
        case .cancelled: return "Cancelled"
        }
    }
}

/// A block of carbon credits bought, held or retired for the client.
nonisolated struct CarbonCredit: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var registry: CreditRegistry = .verra
    var projectName = ""
    var projectID = ""
    var projectType: CreditProjectType = .renewableEnergy
    var country = "India"
    var vintageYear: Int
    var quantity: Double = 0
    var status: CreditStatus = .held
    var retirementDate: Date?
    /// Financial year the retirement is claimed against.
    var retiredForYear: Int?
    var serialNumbers = ""
    /// ₹ per tonne paid.
    var unitPrice: Double?
    /// File path or web link to the registry record or invoice.
    var evidence = ""
    var notes = ""

    init(vintageYear: Int) {
        self.vintageYear = vintageYear
    }

    var displayName: String {
        let trimmed = projectName.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "\(registry.title) credits" : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, registry, projectName, projectID, projectType, country, vintageYear, quantity, status
        case retirementDate, retiredForYear, serialNumbers, unitPrice, evidence, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        registry = try c.value(.registry, default: .other)
        projectName = try c.value(.projectName, default: "")
        projectID = try c.value(.projectID, default: "")
        projectType = try c.value(.projectType, default: .other)
        country = try c.value(.country, default: "")
        vintageYear = try c.value(.vintageYear, default: 2024)
        quantity = try c.value(.quantity, default: 0)
        status = try c.value(.status, default: .held)
        retirementDate = try c.decodeIfPresent(Date.self, forKey: .retirementDate)
        retiredForYear = try c.decodeIfPresent(Int.self, forKey: .retiredForYear)
        serialNumbers = try c.value(.serialNumbers, default: "")
        unitPrice = try c.decodeIfPresent(Double.self, forKey: .unitPrice)
        evidence = try c.value(.evidence, default: "")
        notes = try c.value(.notes, default: "")
    }
}

// MARK: - Plan

nonisolated struct ReductionPlan: Codable, Hashable, Identifiable, Sendable {
    /// Same as the client's id.
    var id: UUID
    /// Kept so the plan still has a name if the client is deleted.
    var clientName = ""
    var targets: [ReductionTarget] = []
    var measures: [ReductionMeasure] = []
    var credits: [CarbonCredit] = []
    /// Real discount rate for annualising capital costs. An assumption: use the client's own.
    var discountRate = 0.08
    var updatedAt = Date()

    init(clientID: UUID, clientName: String) {
        self.id = clientID
        self.clientName = clientName
    }

    var isEmpty: Bool { targets.isEmpty && measures.isEmpty && credits.isEmpty }

    private enum CodingKeys: String, CodingKey {
        case id, clientName, targets, measures, credits, discountRate, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        clientName = try c.value(.clientName, default: "")
        targets = try c.value(.targets, default: [])
        measures = try c.value(.measures, default: [])
        credits = try c.value(.credits, default: [])
        discountRate = try c.value(.discountRate, default: 0.08)
        updatedAt = try c.value(.updatedAt, default: Date())
    }
}
