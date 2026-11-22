import Foundation

/// Whether a client is on course for a target, from its reported figures.
nonisolated enum TargetStatus: String, Sendable {
    /// No base-year value: neither reported nor entered.
    case noBaseline
    /// Nothing reported after the base year yet.
    case notStarted
    case onTrack
    case offTrack
    case achieved

    var title: String {
        switch self {
        case .noBaseline: return "No baseline"
        case .notStarted: return "No progress data"
        case .onTrack: return "On track"
        case .offTrack: return "Off track"
        case .achieved: return "Achieved"
        }
    }
}

/// A reference check on a target's design (ambition, timeframe, base year).
nonisolated struct TargetCheck: Hashable, Sendable {
    let title: String
    /// nil = cannot be checked (e.g. intensity target against an absolute rate).
    let passed: Bool?
    let detail: String
}

nonisolated struct TargetAssessment: Sendable {
    let target: ReductionTarget
    /// Base-year value of the target metric (tCO2e, or intensity).
    let baseValue: Double?
    /// Latest reported year after the base year, and its value.
    let latestYear: Int?
    let latestValue: Double?
    let status: TargetStatus

    /// The value the target allows in its target year.
    var targetValue: Double? { baseValue.map { $0 * (1 - target.reductionPercent / 100) } }

    /// Linear reduction per year, percent of base (42% over 7 years = 6%).
    var annualRate: Double? {
        let years = target.targetYear - target.baseYear
        return years > 0 ? target.reductionPercent / Double(years) : nil
    }

    /// Value on the straight line from base to target in `year` (clamped to the ends).
    func pathValue(_ year: Int) -> Double? {
        guard let baseValue, let targetValue else { return nil }
        let span = Double(target.targetYear - target.baseYear)
        guard span > 0 else { return targetValue }
        let progress = min(1, max(0, Double(year - target.baseYear) / span))
        return baseValue + (targetValue - baseValue) * progress
    }

    /// Reported minus allowed in the latest year; positive = behind the line.
    var gapAtLatest: Double? {
        guard let latestYear, let latestValue, let allowed = pathValue(latestYear) else { return nil }
        return latestValue - allowed
    }

    /// Reference checks for the target's framework. SBTi numbers follow its
    /// near-term criteria (V1.3); always confirm with SBTi's current criteria.
    func checks(today: Date = Date()) -> [TargetCheck] {
        var checks: [TargetCheck] = []
        let years = target.targetYear - target.baseYear
        if years <= 0 {
            checks.append(TargetCheck(title: "Target year after base year", passed: false,
                                      detail: "The target year must come after the base year."))
            return checks
        }
        if let annualRate {
            let applies = target.kind == .absolute
            checks.append(TargetCheck(
                title: "At least \(DisplayFormat.number(target.minimumAnnualRate))% a year",
                passed: applies ? annualRate + 1e-9 >= target.minimumAnnualRate : nil,
                detail: applies
                    ? "\(DisplayFormat.number(annualRate))% of base-year emissions a year, linear."
                    : "Rates apply to absolute targets; intensity targets need their own sector pathway."))
        }
        if target.framework == .sbtiNearTerm {
            let current = ReportingPeriod.startYear(containing: today)
            let horizon = target.targetYear - current
            checks.append(TargetCheck(title: "5–10 years ahead", passed: (5...10).contains(horizon),
                                      detail: "Target year is \(horizon) years after this financial year."))
            checks.append(TargetCheck(title: "Base year 2015 or later", passed: target.baseYear >= 2015,
                                      detail: "Base year \(ReportingPeriod.label(target.baseYear))."))
            if target.coverage == .scope3 {
                checks.append(TargetCheck(title: "Scope 3 coverage", passed: nil,
                                          detail: "SBTi asks near-term Scope 3 targets to cover most Scope 3 emissions when they are a large share of the total."))
            }
        }
        return checks
    }
}

nonisolated enum TargetAssessor {
    /// The target metric for one year: total, or total per revenue / output.
    static func value(of target: ReductionTarget, in figures: ClientYearFigures) -> Double? {
        let emissions = target.coverage.value(in: figures)
        switch target.kind {
        case .absolute: return emissions
        case .intensityRevenue: return ClientYearFigures.ratio(emissions, figures.revenueCrore)
        case .intensityOutput: return ClientYearFigures.ratio(emissions, figures.output)
        }
    }

    static func assess(_ target: ReductionTarget, history: [ClientYearFigures]) -> TargetAssessment {
        let byYear = Dictionary(history.map { ($0.fiscalYearStart, $0) }, uniquingKeysWith: { _, last in last })
        let baseValue = target.baseValueOverride ?? byYear[target.baseYear].flatMap { value(of: target, in: $0) }
        let progress = history
            .filter { $0.fiscalYearStart > target.baseYear }
            .compactMap { figures in value(of: target, in: figures).map { (figures.fiscalYearStart, $0) } }
            .max { $0.0 < $1.0 }
        let partial = TargetAssessment(target: target, baseValue: baseValue, latestYear: progress?.0,
                                       latestValue: progress?.1, status: .noBaseline)
        return TargetAssessment(target: target, baseValue: baseValue, latestYear: progress?.0,
                                latestValue: progress?.1, status: status(partial))
    }

    private static func status(_ assessment: TargetAssessment) -> TargetStatus {
        guard assessment.baseValue != nil, let targetValue = assessment.targetValue else { return .noBaseline }
        guard let latest = assessment.latestValue, let gap = assessment.gapAtLatest else { return .notStarted }
        if latest <= targetValue { return .achieved }
        return gap <= 0 ? .onTrack : .offTrack
    }
}
