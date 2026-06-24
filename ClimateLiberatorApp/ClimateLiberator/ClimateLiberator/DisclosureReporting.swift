import Foundation

// MARK: - Climate physical-risk disclosure (stage 5, disclosure audience)
//
// The second ReportSurface alongside InsurerReportSurface. Both consume the same
// PortfolioLossResult; this one renders it as an IFRS S2 + SEBI BRSR draft.
//
// IFRS S2 uses the same four content pillars as TCFD (Governance, Strategy, Risk
// Management, Metrics & Targets) — TCFD was folded into IFRS S2. SEBI BRSR is the
// Indian listed-company mandate; climate physical risk maps to BRSR Principle 6
// (Environment).

/// A structured climate physical-risk disclosure draft.
struct ClimateDisclosureDraft: Sendable, Hashable {
    let standard: String          // "IFRS S2"
    let entityName: String
    let reportingPeriod: String
    let peril: Peril
    let governance: [String]
    let strategy: [String]
    let riskManagement: [String]
    let metricsAndTargets: [DisclosureMetric]
    let brsr: BRSRDisclosure
}

struct DisclosureMetric: Sendable, Hashable {
    let label: String
    let value: String
    /// Indicative IFRS S2 placement for the metric.
    let reference: String
}

/// SEBI BRSR cross-reference (Business Responsibility & Sustainability Report).
struct BRSRDisclosure: Sendable, Hashable {
    let principle: String         // "Principle 6 — Environment"
    let section: String           // "Climate-related physical risk"
    let indicators: [BRSRIndicator]
}

struct BRSRIndicator: Sendable, Hashable {
    let indicator: String
    let response: String
}

/// Renders the shared loss result into an IFRS S2 + BRSR disclosure draft.
struct DisclosureReportSurface: ReportSurface {
    let audience: ReportAudience = .disclosure
    let entityName: String
    let reportingPeriod: String

    init(entityName: String = "the entity", reportingPeriod: String = "the reporting period") {
        self.entityName = entityName
        self.reportingPeriod = reportingPeriod
    }

    func render(_ result: PortfolioLossResult) -> ClimateDisclosureDraft {
        let perilName = result.peril.rawValue
        let perilTitle = perilName.capitalized
        let lossPct = result.meanDamageFraction * 100
        let lossPctText = String(format: "%.1f%%", lossPct)
        let tiv = Self.inrCrore(result.totalInsuredValue)
        let grossLoss = Self.inrCrore(result.groundUpLoss)
        let insuredLoss = Self.inrCrore(result.insuredLoss)

        let governance = [
            "The board, through its Risk Management Committee, oversees climate-related physical risks, including \(perilName) hazard to the asset portfolio.",
            "Management reviews modelled physical-risk results for \(reportingPeriod) before they are disclosed.",
        ]

        let strategy = [
            "\(perilTitle) is identified as an acute physical climate hazard affecting \(result.assetCount) assessed assets held by \(entityName).",
            "Modelled gross loss is \(lossPctText) of total insured value (\(tiv)).",
            "Estimated gross (ground-up) loss for the modelled event set is \(grossLoss); estimated net insured loss is \(insuredLoss).",
            "Resilience is assessed through hazard scenario modelling (Cell2Fire) across the asset portfolio.",
        ]

        let riskManagement = [
            "Physical risk is identified and assessed through a hazard → exposure → vulnerability → financial pipeline.",
            "Hazard footprints are generated per scenario; exposure is screened by location; vulnerability curves translate hazard intensity to a damage ratio; financial layering yields gross and insured loss.",
        ]

        let metrics = [
            DisclosureMetric(label: "Assets assessed for \(perilName) physical risk",
                             value: "\(result.assetCount)",
                             reference: "IFRS S2 — Metrics & Targets"),
            DisclosureMetric(label: "Total insured value assessed",
                             value: tiv,
                             reference: "IFRS S2 — Metrics & Targets"),
            DisclosureMetric(label: "Modelled gross loss as share of insured value",
                             value: lossPctText,
                             reference: "IFRS S2 para 29(c) — assets vulnerable to physical risk"),
            DisclosureMetric(label: "Estimated gross loss (modelled)",
                             value: grossLoss,
                             reference: "IFRS S2 — Strategy (financial effects)"),
            DisclosureMetric(label: "Estimated net insured loss",
                             value: insuredLoss,
                             reference: "IFRS S2 — Strategy (financial effects)"),
        ]

        let brsr = BRSRDisclosure(
            principle: "Principle 6 — Environment",
            section: "Climate-related physical risk",
            indicators: [
                BRSRIndicator(indicator: "Climate-related physical risks identified", response: perilTitle),
                BRSRIndicator(indicator: "Number of assets assessed for physical climate risk", response: "\(result.assetCount)"),
                BRSRIndicator(indicator: "Estimated financial implication of physical climate risk (net)", response: insuredLoss),
                BRSRIndicator(indicator: "Modelled gross loss as share of insured value", response: lossPctText),
            ]
        )

        return ClimateDisclosureDraft(
            standard: "IFRS S2",
            entityName: entityName,
            reportingPeriod: reportingPeriod,
            peril: result.peril,
            governance: governance,
            strategy: strategy,
            riskManagement: riskManagement,
            metricsAndTargets: metrics,
            brsr: brsr
        )
    }

    /// Format a currency amount in Indian crore (₹1 crore = 10,000,000).
    static func inrCrore(_ amount: Double) -> String {
        String(format: "₹%.2f crore", amount / 10_000_000)
    }
}
