import Foundation

/// One year on the pathway chart.
nonisolated struct PathwayPoint: Identifiable, Sendable {
    let year: Int
    /// Reported value.
    let actual: Double?
    /// Straight line from base to target.
    let allowed: Double?
    /// Latest reported value minus the committed measures that start later.
    let withMeasures: Double?
    var id: Int { year }
}

/// Where reported emissions and committed measures lead, against a target.
/// Only absolute targets get a "with measures" line: measures are in tonnes.
nonisolated enum ReductionPathway {
    static func points(for assessment: TargetAssessment, history: [ClientYearFigures],
                       measures: [ReductionMeasure]) -> [PathwayPoint] {
        let target = assessment.target
        let reported = Dictionary(history.compactMap { figures in
            TargetAssessor.value(of: target, in: figures).map { (figures.fiscalYearStart, $0) }
        }, uniquingKeysWith: { _, last in last })
        let firstYear = min(target.baseYear, reported.keys.min() ?? target.baseYear)
        let lastYear = max(target.targetYear, reported.keys.max() ?? target.targetYear)
        guard firstYear <= lastYear else { return [] }
        let projection = projectedValues(assessment: assessment, measures: measures, through: lastYear)
        return (firstYear...lastYear).map { year in
            PathwayPoint(year: year,
                         actual: year == target.baseYear ? (reported[year] ?? assessment.baseValue) : reported[year],
                         allowed: year >= target.baseYear ? assessment.pathValue(year) : nil,
                         withMeasures: projection[year])
        }
    }

    /// Projected value per year after the latest report, from committed measures.
    static func projectedValues(assessment: TargetAssessment, measures: [ReductionMeasure], through lastYear: Int) -> [Int: Double] {
        let target = assessment.target
        guard target.kind == .absolute,
              let startYear = assessment.latestYear ?? (assessment.baseValue != nil ? target.baseYear : nil),
              let startValue = assessment.latestValue ?? assessment.baseValue,
              startYear < lastYear else { return [:] }
        // Measures already running by the latest report are inside the reported figure.
        let future = measures.filter { $0.status.isCommitted && $0.scope.isCovered(by: target.coverage) && $0.startYear > startYear }
        var values: [Int: Double] = [startYear: startValue]
        for year in (startYear + 1)...lastYear {
            let cut = future.filter { $0.startYear <= year }.reduce(0) { $0 + ($1.annualAbatement ?? 0) }
            values[year] = max(0, startValue - cut)
        }
        return values
    }

    /// Projected minus allowed in the target year; positive = measures fall short.
    static func shortfall(assessment: TargetAssessment, measures: [ReductionMeasure]) -> Double? {
        let year = assessment.target.targetYear
        guard let projected = projectedValues(assessment: assessment, measures: measures, through: year)[year],
              let allowed = assessment.targetValue else { return nil }
        return projected - allowed
    }
}
