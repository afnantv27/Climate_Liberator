import Foundation

/// Narrative disclosures: IFRS S2 core content and BRSR qualitative items. Each
/// carries a checklist of what a reviewer or assurance provider will look for.
nonisolated enum NarrativeCatalog {

    static let all: [NarrativeRequirement] = ifrs + brsr

    private static let index: [String: NarrativeRequirement] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func requirement(_ id: String) -> NarrativeRequirement? { index[id] }

    static func requirements(for framework: DisclosureFramework) -> [NarrativeRequirement] {
        all.filter { $0.framework == framework }
    }

    /// Required narratives for the frameworks in scope (BRSR Core adds none of its own).
    static func required(in scope: Set<DisclosureFramework>) -> [NarrativeRequirement] {
        all.filter { $0.required && scope.contains($0.framework) }
    }

    static func inScope(_ scope: Set<DisclosureFramework>) -> [NarrativeRequirement] {
        all.filter { scope.contains($0.framework) }
    }

    private static func n(_ id: String, _ title: String, _ framework: DisclosureFramework, _ pillar: NarrativePillar,
                          _ reference: String, required: Bool = true, metrics: [String] = [],
                          guidance: String, elements: [String]) -> NarrativeRequirement {
        NarrativeRequirement(id: id, title: title, framework: framework, pillar: pillar, reference: reference,
                             guidance: guidance, elements: elements, linkedMetrics: metrics, required: required)
    }

    // MARK: IFRS S2

    private static let ifrs: [NarrativeRequirement] = [
        n("s2.basis", "Basis of preparation and transition reliefs", .ifrsS2, .basis, "IFRS S1 / S2 App. C",
          guidance: "State that the disclosures follow IFRS S2, the reporting entity and period (same as the financial statements), and any transition reliefs used.",
          elements: ["Statement of compliance (or the extent of it)",
                     "Reporting entity and period match the financial statements",
                     "Transition reliefs used (e.g. no comparatives, no Scope 3 in the first year)",
                     "Significant judgements and measurement uncertainty"]),
        n("s2.gov.board", "Board oversight of climate-related risks and opportunities", .ifrsS2, .governance, "IFRS S2 6(a)",
          guidance: "Who on the board (or which committee) oversees climate matters and how.",
          elements: ["Body or individual responsible, and where this is set out (terms of reference, mandates)",
                     "How it ensures the right skills and competencies are available",
                     "How and how often it is informed",
                     "How climate is considered in strategy, major transactions and risk management",
                     "How it oversees targets, and whether performance metrics feed remuneration"]),
        n("s2.gov.management", "Management's role", .ifrsS2, .governance, "IFRS S2 6(b)",
          guidance: "The management positions or committees that run climate-related matters day to day.",
          elements: ["Roles or committees delegated, and how they are overseen",
                     "Controls and procedures used, and how they are integrated with other internal functions"]),
        n("s2.str.risks", "Climate-related risks and opportunities", .ifrsS2, .strategy, "IFRS S2 10–12",
          guidance: "Describe each material risk and opportunity. The Risks & Opportunities register drafts this.",
          elements: ["Each risk and opportunity described",
                     "Physical (acute, chronic) or transition risk",
                     "Time horizon over which each could arise",
                     "How short, medium and long term are defined and linked to planning horizons"]),
        n("s2.str.businessModel", "Effects on the business model and value chain", .ifrsS2, .strategy, "IFRS S2 13",
          guidance: "Current and expected effects, and where in the value chain they are concentrated.",
          elements: ["Current and anticipated effects on the business model and value chain",
                     "Where effects are concentrated (geographies, facilities, asset types)"]),
        n("s2.str.decisions", "Strategy, decision-making and transition plan", .ifrsS2, .strategy, "IFRS S2 14",
          metrics: ["s2.capitalDeployed"],
          guidance: "How climate shapes strategy and resource allocation, including any transition plan.",
          elements: ["Changes to the business model and resource allocation",
                     "Direct and indirect mitigation and adaptation efforts",
                     "Transition plan, key assumptions and dependencies",
                     "How climate targets will be achieved",
                     "How these activities are resourced",
                     "Progress against plans disclosed previously"]),
        n("s2.str.financial", "Current and anticipated financial effects", .ifrsS2, .strategy, "IFRS S2 15–21",
          metrics: [MetricID.physicalVulnerableAmount, "s2.transitionVulnerableAmount"],
          guidance: "Effects on financial position, performance and cash flows, now and over each horizon. Quantitative where possible; say why if not.",
          elements: ["Effects on financial position, performance and cash flows in the period",
                     "Risks with a significant chance of material adjustment next year",
                     "Anticipated changes over the short, medium and long term (incl. investment and disposal plans)",
                     "Single amounts or ranges, or reasons a quantitative estimate is not given"]),
        n("s2.str.resilience", "Climate resilience and scenario analysis", .ifrsS2, .strategy, "IFRS S2 22",
          guidance: "How resilient strategy and business model are, assessed with scenario analysis. Wildfire and other simulations can be cited as inputs.",
          elements: ["Implications of the assessment for strategy",
                     "Significant areas of uncertainty",
                     "Capacity to adjust or adapt (finance, assets, investment)",
                     "Scenarios used, sources and whether a 1.5 °C-aligned scenario is included",
                     "Time horizons and operations covered, key assumptions",
                     "When the analysis was carried out"]),
        n("s2.rm.process", "Risk management processes", .ifrsS2, .riskManagement, "IFRS S2 25",
          guidance: "How climate risks and opportunities are identified, assessed, prioritised and monitored, and how this fits overall risk management.",
          elements: ["Inputs and parameters used (data sources, operations covered)",
                     "Whether and how scenario analysis informs identification",
                     "How nature, likelihood and magnitude are assessed",
                     "How climate risks are prioritised against other risks",
                     "How they are monitored, and changes from the prior period",
                     "Processes for opportunities",
                     "Integration with the overall risk management process"]),
        n("s2.mt.ghg", "GHG measurement approach", .ifrsS2, .metricsTargets, "IFRS S2 29(a)",
          metrics: [MetricID.scope1, MetricID.scope2, MetricID.scope3, "ghg.scope3Categories"],
          guidance: "How Scope 1, 2 and 3 were measured.",
          elements: ["Measurement approach (GHG Protocol or a jurisdictional method), inputs and assumptions",
                     "Consolidation approach and reasons",
                     "Scope 2 location-based, plus contractual instruments",
                     "Scope 3 categories included and data sources",
                     "Changes from the prior period"]),
        n("s2.mt.metrics", "Other cross-industry metrics", .ifrsS2, .metricsTargets, "IFRS S2 29(b)–(g)",
          metrics: ["s2.transitionVulnerableAmount", MetricID.physicalVulnerableAmount, "s2.opportunityAlignedAmount",
                    "s2.capitalDeployed", "s2.internalCarbonPrice", "s2.remunerationLinkedShare"],
          guidance: "Explain the amounts reported for transition and physical risk, opportunities, capital deployment, internal carbon prices and remuneration.",
          elements: ["How 'vulnerable' and 'aligned' were determined",
                     "How the internal carbon price is applied in decisions",
                     "How climate considerations factor into executive remuneration"]),
        n("s2.mt.industry", "Industry-based metrics", .ifrsS2, .metricsTargets, "IFRS S2 32", required: false,
          guidance: "Metrics for the company's industry; the ISSB's industry-based guidance (SASB-derived) helps identify them.",
          elements: ["Industry or industries identified", "Metrics reported, with values and units"]),
        n("s2.mt.targets", "Climate-related targets", .ifrsS2, .metricsTargets, "IFRS S2 33–36",
          guidance: "Each target, how it was set and progress against it.",
          elements: ["Metric used, objective, part of the entity covered",
                     "Period, base period, milestones and interim targets",
                     "Absolute or intensity target",
                     "How the latest international climate agreement informed it",
                     "Whether it was validated by a third party; how it is reviewed",
                     "Performance against the target and analysis of trends",
                     "For GHG targets: gases, scopes, gross or net, and any carbon credits relied on"]),
    ]

    // MARK: BRSR

    private static let brsr: [NarrativeRequirement] = [
        n("brsr.a.business", "Business activities, products and services", .brsr, .brsrA, "BRSR A · II",
          guidance: "Main business activities (≥90% of turnover) and products or services with NIC codes.",
          elements: ["Business activities with description and % of turnover",
                     "Products or services with NIC code and % of turnover"]),
        n("brsr.a.operations", "Operations and markets served", .brsr, .brsrA, "BRSR A · III",
          guidance: "Plants and offices, markets served and customer types.",
          elements: ["Number of plants and offices, national and international",
                     "Markets served (states, countries)",
                     "Export contribution as % of turnover",
                     "Types of customers"]),
        n("brsr.a.entities", "Holding, subsidiary and associate companies", .brsr, .brsrA, "BRSR A · V",
          guidance: "Group entities and whether they take part in the company's business-responsibility initiatives.",
          elements: ["Names and type of each entity, % shares held",
                     "Whether each participates in the BRSR initiatives"]),
        n("brsr.a.csr", "CSR details", .brsr, .brsrA, "BRSR A · VI",
          guidance: "Whether CSR applies under section 135 of the Companies Act, 2013, with turnover and net worth.",
          elements: ["CSR applicable (yes/no)", "Turnover (₹)", "Net worth (₹)"]),
        n("brsr.a.complaints", "Complaints and grievances", .brsr, .brsrA, "BRSR A · VII",
          guidance: "Grievance mechanisms and complaints by stakeholder group, current and prior year.",
          elements: ["Mechanism in place for each stakeholder group (with web link)",
                     "Complaints filed and pending at year end, with remarks"]),
        n("brsr.b.director", "Statement by the director responsible for the BRSR", .brsr, .brsrB, "BRSR B · 7",
          guidance: "Highlights ESG challenges, targets and achievements. Usually written last, once the data is final.",
          elements: ["ESG-related challenges", "Targets", "Achievements in the year"]),
        n("brsr.p6.ghgProjects", "Projects to reduce GHG emissions", .brsr, .brsrC, "BRSR P6 · EI 8",
          metrics: [MetricID.scope12],
          guidance: "Projects related to reducing greenhouse gas emissions, if any.",
          elements: ["Project description", "Expected or achieved reduction"]),
        n("brsr.p6.wastePractices", "Waste management practices", .brsr, .brsrC, "BRSR P6 · EI 10",
          metrics: [MetricID.wasteTotal, MetricID.wasteRecovered],
          guidance: "Practices adopted to manage waste and reduce hazardous and toxic chemicals.",
          elements: ["Practices adopted", "Strategy to reduce hazardous and toxic chemicals"]),
        n("brsr.p6.sensitiveAreas", "Operations in ecologically sensitive areas", .brsr, .brsrC, "BRSR P6 · EI 11",
          guidance: "Operations or offices in or around ecologically sensitive areas, and whether approvals are complied with.",
          elements: ["Location and type of operations", "Compliance with environmental approvals or clearances"]),
        n("brsr.p6.compliance", "Compliance with environmental law", .brsr, .brsrC, "BRSR P6 · EI 13",
          guidance: "Whether the company complies with applicable environmental law and regulations, with details of any non-compliance.",
          elements: ["Compliance status", "Details of any non-compliance and corrective action"]),
        n("brsr.p6.continuity", "Business continuity and disaster management", .brsr, .brsrC, "BRSR P6 · LI 5", required: false,
          guidance: "Business continuity and disaster management plan, in brief or as a web link. Physical-risk assessments support this.",
          elements: ["Plan described or linked"]),
    ]
}
