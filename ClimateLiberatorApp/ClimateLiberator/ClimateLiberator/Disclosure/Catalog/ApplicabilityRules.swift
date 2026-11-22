import Foundation

/// Which frameworks apply to a company in a given financial year.
///
/// Rules as understood when last checked; regulators change them often, so every
/// result carries `rulesCheckedOn` and the UI asks users to confirm with SEBI's
/// latest circulars and their assurance provider.
nonisolated enum ApplicabilityRules {
    static let rulesCheckedOn = "November 2026"

    /// BRSR Core assessment-or-assurance glide path: financial year start → top N listed by market cap.
    /// SEBI circular of 12 July 2023 as amended 28 March 2025.
    static let coreGlidePath: [(fiscalYearStart: Int, topN: Int)] = [
        (2023, 150), (2024, 250), (2025, 500), (2026, 1_000),
    ]

    nonisolated enum Requirement: String, Sendable {
        case mandatory, voluntary, notApplicable
        var title: String {
            switch self {
            case .mandatory: return "Mandatory"
            case .voluntary: return "Voluntary"
            case .notApplicable: return "Not applicable"
            }
        }
    }

    nonisolated struct Finding: Identifiable, Sendable {
        let framework: DisclosureFramework
        let requirement: Requirement
        let reason: String
        var id: String { framework.rawValue }
    }

    /// Top-N cut-off for BRSR Core assessment or assurance in the year, if any.
    static func coreCutoff(fiscalYearStart: Int) -> Int? {
        coreGlidePath.last { $0.fiscalYearStart <= fiscalYearStart }?.topN
    }

    static func assess(_ profile: CompanyProfile, fiscalYearStart: Int) -> [Finding] {
        let period = ReportingPeriod.label(fiscalYearStart)
        var findings: [Finding] = []

        // BRSR: top 1,000 listed entities by market capitalisation.
        if !profile.isListed {
            findings.append(Finding(framework: .brsr, requirement: .voluntary,
                                    reason: "BRSR is mandated for listed entities; an unlisted company may report voluntarily."))
        } else if let rank = profile.marketCapRank {
            findings.append(rank <= 1_000
                ? Finding(framework: .brsr, requirement: .mandatory,
                          reason: "Listed and ranked \(rank) by market capitalisation: within the top 1,000 that must file a BRSR.")
                : Finding(framework: .brsr, requirement: .voluntary,
                          reason: "Ranked \(rank): outside the top 1,000, so BRSR is voluntary."))
        } else {
            findings.append(Finding(framework: .brsr, requirement: .mandatory,
                                    reason: "Listed: mandatory if within the top 1,000 by market capitalisation. Enter the rank to confirm."))
        }

        // BRSR Core assessment or assurance glide path.
        if profile.isListed, let cutoff = coreCutoff(fiscalYearStart: fiscalYearStart) {
            if let rank = profile.marketCapRank {
                findings.append(rank <= cutoff
                    ? Finding(framework: .brsrCore, requirement: .mandatory,
                              reason: "\(period): top \(cutoff) need independent assessment or assurance of BRSR Core; ranked \(rank).")
                    : Finding(framework: .brsrCore, requirement: .voluntary,
                              reason: "\(period): assessment or assurance applies to the top \(cutoff); ranked \(rank). Core KPIs are still reported in the BRSR."))
            } else {
                findings.append(Finding(framework: .brsrCore, requirement: .mandatory,
                                        reason: "\(period): assessment or assurance applies to the top \(cutoff). Enter the rank to confirm."))
            }
        } else {
            findings.append(Finding(framework: .brsrCore, requirement: .voluntary,
                                    reason: "No BRSR Core assessment or assurance requirement identified for \(period)."))
        }

        // IFRS S2: not adopted in India as of the check date.
        findings.append(Finding(framework: .ifrsS2, requirement: .voluntary,
                                reason: "Not mandated in India. Report when investors, lenders or an overseas listing ask for it; much of the data is shared with BRSR."))
        return findings
    }

    /// Value-chain disclosures (BRSR Core for partners with ≥2% of purchases or sales).
    static func valueChainNote(fiscalYearStart: Int) -> String {
        fiscalYearStart >= 2025
            ? "Value-chain BRSR Core disclosures are voluntary for the top 250, with assessment or assurance of them voluntary from FY 2026-27 (partners with 2% or more of purchases or sales)."
            : "Value-chain BRSR Core disclosures were not yet in force."
    }
}
