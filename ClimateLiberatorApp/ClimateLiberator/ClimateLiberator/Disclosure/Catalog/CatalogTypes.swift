import Foundation

// Types describing what each framework asks for. Instances live in the catalog files;
// nothing here is persisted.

// MARK: - BRSR structure

/// The nine principles of the National Guidelines on Responsible Business Conduct.
nonisolated enum BRSRPrinciple: Int, CaseIterable, Identifiable, Sendable {
    case p1 = 1, p2, p3, p4, p5, p6, p7, p8, p9

    var id: Int { rawValue }
    var code: String { "P\(rawValue)" }
    var title: String {
        switch self {
        case .p1: return "Ethics, transparency and accountability"
        case .p2: return "Sustainable and safe goods and services"
        case .p3: return "Well-being of employees"
        case .p4: return "Responsiveness to stakeholders"
        case .p5: return "Human rights"
        case .p6: return "Environment"
        case .p7: return "Responsible public policy advocacy"
        case .p8: return "Inclusive growth and equitable development"
        case .p9: return "Responsible consumer engagement"
        }
    }
    var statement: String {
        switch self {
        case .p1: return "Businesses should conduct and govern themselves with integrity, and in a manner that is ethical, transparent and accountable."
        case .p2: return "Businesses should provide goods and services in a manner that is sustainable and safe."
        case .p3: return "Businesses should respect and promote the well-being of all employees, including those in their value chains."
        case .p4: return "Businesses should respect the interests of and be responsive to all their stakeholders."
        case .p5: return "Businesses should respect and promote human rights."
        case .p6: return "Businesses should respect and make efforts to protect and restore the environment."
        case .p7: return "Businesses, when engaging in influencing public and regulatory policy, should do so in a manner that is responsible and transparent."
        case .p8: return "Businesses should promote inclusive growth and equitable development."
        case .p9: return "Businesses should engage with and provide value to their consumers in a responsible manner."
        }
    }
}

/// The nine BRSR Core attributes (SEBI, July 2023; assessment or assurance from March 2025).
nonisolated enum BRSRCoreAttribute: Int, CaseIterable, Identifiable, Sendable {
    case ghg = 1, water, energy, circularity, wellbeing, gender, inclusion, fairness, openness

    var id: Int { rawValue }
    var title: String {
        switch self {
        case .ghg: return "GHG footprint"
        case .water: return "Water footprint"
        case .energy: return "Energy footprint"
        case .circularity: return "Embracing circularity"
        case .wellbeing: return "Employee well-being and safety"
        case .gender: return "Gender diversity"
        case .inclusion: return "Inclusive development"
        case .fairness: return "Fairness with customers and suppliers"
        case .openness: return "Openness of business"
        }
    }
    var systemImage: String {
        switch self {
        case .ghg: return "smoke"
        case .water: return "drop"
        case .energy: return "bolt"
        case .circularity: return "arrow.3.trianglepath"
        case .wellbeing: return "cross.case"
        case .gender: return "person.2"
        case .inclusion: return "building.2"
        case .fairness: return "scalemass"
        case .openness: return "eye"
        }
    }
}

nonisolated enum BRSRSection: String, Sendable {
    case a = "A", b = "B", c = "C"
}

nonisolated enum IndicatorLevel: String, Sendable {
    /// Section A or B general disclosure.
    case general
    /// Section C essential indicator (mandatory).
    case essential
    /// Section C leadership indicator (voluntary).
    case leadership
}

/// Where a data point sits in BRSR.
nonisolated struct BRSRLink: Hashable, Sendable {
    let section: BRSRSection
    let principle: BRSRPrinciple?
    let level: IndicatorLevel
    /// "P6 · EI 7", "A · IV".
    let reference: String

    static func essential(_ principle: BRSRPrinciple, _ question: String) -> BRSRLink {
        BRSRLink(section: .c, principle: principle, level: .essential, reference: "\(principle.code) · EI \(question)")
    }
    static func leadership(_ principle: BRSRPrinciple, _ question: String) -> BRSRLink {
        BRSRLink(section: .c, principle: principle, level: .leadership, reference: "\(principle.code) · LI \(question)")
    }
    static func sectionA(_ part: String) -> BRSRLink {
        BRSRLink(section: .a, principle: nil, level: .general, reference: "A · \(part)")
    }
}

/// Where a data point sits in IFRS S2.
nonisolated struct IFRSLink: Hashable, Sendable {
    /// "29(a)(i)(1)".
    let paragraph: String
    /// false: supports the disclosure but is not itself required (e.g. a breakdown).
    let required: Bool

    var reference: String { "IFRS S2 \(paragraph)" }

    static func required(_ paragraph: String) -> IFRSLink { IFRSLink(paragraph: paragraph, required: true) }
    static func supporting(_ paragraph: String) -> IFRSLink { IFRSLink(paragraph: paragraph, required: false) }
}

// MARK: - Metrics

nonisolated enum MetricKind: String, Sendable {
    case quantity, percent, count, money, ratio, text
}

/// Groups used to navigate the KPI workbench.
nonisolated enum MetricGroup: String, CaseIterable, Identifiable, Sendable {
    case denominators, ghg, energy, water, waste, air, safety, workforce, gender, inclusion, fairness, openness, climateRisk

    var id: String { rawValue }
    var title: String {
        switch self {
        case .denominators: return "Financials & Denominators"
        case .ghg: return "GHG Emissions"
        case .energy: return "Energy"
        case .water: return "Water"
        case .waste: return "Waste & Circularity"
        case .air: return "Air Emissions & Credits"
        case .safety: return "Well-being & Safety"
        case .workforce: return "Workforce"
        case .gender: return "Gender Diversity"
        case .inclusion: return "Inclusive Development"
        case .fairness: return "Customers & Suppliers"
        case .openness: return "Openness of Business"
        case .climateRisk: return "Climate Risk (IFRS S2)"
        }
    }
    var systemImage: String {
        switch self {
        case .denominators: return "indianrupeesign.circle"
        case .ghg: return "smoke"
        case .energy: return "bolt"
        case .water: return "drop"
        case .waste: return "arrow.3.trianglepath"
        case .air: return "wind"
        case .safety: return "cross.case"
        case .workforce: return "person.3"
        case .gender: return "person.2"
        case .inclusion: return "building.2"
        case .fairness: return "scalemass"
        case .openness: return "eye"
        case .climateRisk: return "thermometer.sun"
        }
    }
}

/// How a calculated metric is derived from others. Missing inputs are skipped in
/// sums (the result is flagged partial); ratios need every denominator.
nonisolated enum Derivation: Hashable, Sendable {
    /// Σ inputs.
    case sum([String])
    /// Σ numerator ÷ Σ denominator × scale.
    case ratio(numerator: [String], denominator: [String], scale: Double)
    /// Σ inputs ÷ revenue adjusted for purchasing power parity, per million international $.
    case perPPPRevenue([String])
    /// Σ inputs ÷ revenue from operations, per ₹ crore.
    case perRevenue([String])
    /// Σ inputs ÷ physical output.
    case perOutput([String])

    var inputs: [String] {
        switch self {
        case .sum(let ids): return ids
        case .ratio(let numerator, let denominator, _): return numerator + denominator
        case .perPPPRevenue(let ids): return ids + [MetricID.revenue, MetricID.pppRate]
        case .perRevenue(let ids): return ids + [MetricID.revenue]
        case .perOutput(let ids): return ids + [MetricID.output]
        }
    }
}

nonisolated struct MetricDefinition: Identifiable, Sendable {
    let id: String
    let title: String
    let unit: String
    let kind: MetricKind
    let group: MetricGroup
    let brsr: BRSRLink?
    let core: BRSRCoreAttribute?
    let ifrs: IFRSLink?
    /// What to report, where the data comes from, how it is checked.
    let guidance: String
    let derivation: Derivation?

    var isCalculated: Bool { derivation != nil }
    var isText: Bool { kind == .text }
    /// Counts and amounts cannot be negative; nothing in the catalog can.
    var allowsNegative: Bool { false }

    /// Frameworks that require this data point.
    var requiredBy: Set<DisclosureFramework> {
        var frameworks = Set<DisclosureFramework>()
        if let brsr, brsr.level != .leadership { frameworks.insert(.brsr) }
        if core != nil {
            frameworks.insert(.brsrCore)
            frameworks.insert(.brsr)
        }
        if let ifrs, ifrs.required { frameworks.insert(.ifrsS2) }
        return frameworks
    }

    /// Frameworks the data point appears in, required or voluntary.
    var usedBy: Set<DisclosureFramework> {
        var frameworks = requiredBy
        if brsr != nil { frameworks.insert(.brsr) }
        if ifrs != nil { frameworks.insert(.ifrsS2) }
        return frameworks
    }

    func isRequired(in scope: Set<DisclosureFramework>) -> Bool { !requiredBy.isDisjoint(with: scope) }
    func isUsed(in scope: Set<DisclosureFramework>) -> Bool { !usedBy.isDisjoint(with: scope) }

    /// "P6 · EI 7 · Core 1 · IFRS S2 29(a)".
    var referenceLine: String {
        var parts: [String] = []
        if let brsr { parts.append(brsr.reference) }
        if let core { parts.append("Core \(core.rawValue)") }
        if let ifrs { parts.append(ifrs.reference) }
        return parts.joined(separator: " · ")
    }
}

/// Ids used by code (derivations, checks, integrations).
nonisolated enum MetricID {
    static let revenue = "fin.revenue"
    static let pppRate = "fin.pppRate"
    static let output = "fin.output"
    static let outputUnit = "fin.outputUnit"
    static let totalWages = "fin.totalWages"
    static let scope1 = "ghg.scope1"
    static let scope2 = "ghg.scope2"
    static let scope12 = "ghg.scope12"
    static let scope3 = "ghg.scope3"
    static let ghgIntensityPPP = "ghg.intensityPPP"
    static let energyTotal = "energy.total"
    static let renewableShare = "energy.renewableShare"
    static let electricityNonRenewable = "energy.nonRenewableElectricity"
    static let electricityRenewable = "energy.renewableElectricity"
    static let waterWithdrawal = "water.withdrawalTotal"
    static let waterConsumption = "water.consumption"
    static let wasteTotal = "waste.total"
    static let wasteRecovered = "waste.recoveredTotal"
    static let wasteDisposed = "waste.disposedTotal"
    static let ltifr = "safety.ltifr"
    static let femaleWageShare = "gender.femaleWageShare"
    static let physicalVulnerableAmount = "s2.physicalVulnerableAmount"
    static let physicalVulnerableShare = "s2.physicalVulnerableShare"
}

// MARK: - Narratives

nonisolated enum NarrativePillar: String, CaseIterable, Identifiable, Sendable {
    case governance, strategy, riskManagement, metricsTargets, basis, brsrA, brsrB, brsrC

    var id: String { rawValue }
    var title: String {
        switch self {
        case .governance: return "Governance"
        case .strategy: return "Strategy"
        case .riskManagement: return "Risk Management"
        case .metricsTargets: return "Metrics & Targets"
        case .basis: return "Basis of Preparation"
        case .brsrA: return "BRSR Section A"
        case .brsrB: return "BRSR Section B"
        case .brsrC: return "BRSR Section C"
        }
    }
}

nonisolated struct NarrativeRequirement: Identifiable, Sendable {
    let id: String
    let title: String
    let framework: DisclosureFramework
    let pillar: NarrativePillar
    /// "IFRS S2 6(a)", "BRSR B · 7".
    let reference: String
    let guidance: String
    /// What the text should cover; ticked off by the preparer.
    let elements: [String]
    /// KPIs a reader expects next to this text.
    let linkedMetrics: [String]
    let required: Bool
}
