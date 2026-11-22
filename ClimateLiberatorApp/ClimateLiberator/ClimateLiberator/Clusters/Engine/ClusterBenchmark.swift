import Foundation

// Cluster benchmarking: compares the members of one industrial cluster on the same
// metrics and rolls their figures up. Pure functions over `ClientYearFigures`, so it
// does not care whether figures come from KPI Data or, later, corporate inventories.

nonisolated struct ClusterMember: Identifiable, Sendable {
    let clientID: UUID
    let name: String
    let size: EnterpriseSize
    /// Latest figures, nil when the client has reported nothing yet.
    let figures: ClientYearFigures?

    var id: UUID { clientID }
}

/// A metric members are ranked on.
nonisolated enum BenchmarkMetric: String, CaseIterable, Identifiable, Sendable {
    case intensityPerRevenue, intensityPerOutput, energyPerRevenue, renewableShare, scope12

    var id: String { rawValue }
    var title: String {
        switch self {
        case .intensityPerRevenue: return "Emission intensity (revenue)"
        case .intensityPerOutput: return "Emission intensity (output)"
        case .energyPerRevenue: return "Energy intensity"
        case .renewableShare: return "Renewable energy"
        case .scope12: return "Scope 1 + 2 emissions"
        }
    }
    func unit(outputUnit: String) -> String {
        switch self {
        case .intensityPerRevenue: return "tCO2e per ₹ crore"
        case .intensityPerOutput: return outputUnit.isEmpty ? "tCO2e per unit" : "tCO2e per \(outputUnit)"
        case .energyPerRevenue: return "GJ per ₹ crore"
        case .renewableShare: return "%"
        case .scope12: return "tCO2e"
        }
    }
    /// Lower values rank better for every metric except the renewable share.
    var lowerIsBetter: Bool { self != .renewableShare }

    /// The metric's value; renewable share as a percentage (0–100).
    func value(_ figures: ClientYearFigures) -> Double? {
        switch self {
        case .intensityPerRevenue: return figures.intensityPerRevenue
        case .intensityPerOutput: return figures.intensityPerOutput
        case .energyPerRevenue: return figures.energyPerRevenue
        case .renewableShare: return figures.renewableShare.map { $0 * 100 }
        case .scope12: return figures.scope12
        }
    }
}

nonisolated struct MetricStatistics: Equatable, Sendable {
    let count: Int
    let minimum: Double
    let lowerQuartile: Double
    let median: Double
    let upperQuartile: Double
    let maximum: Double
}

/// Quartile band from best to worst performers.
nonisolated enum PerformanceBand: Int, Comparable, Sendable {
    case leading = 1, aboveMedian, belowMedian, lagging

    var title: String {
        switch self {
        case .leading: return "Top quartile"
        case .aboveMedian: return "Above median"
        case .belowMedian: return "Below median"
        case .lagging: return "Bottom quartile"
        }
    }
    static func < (a: PerformanceBand, b: PerformanceBand) -> Bool { a.rawValue < b.rawValue }
}

nonisolated struct BenchmarkRow: Identifiable, Sendable {
    let member: ClusterMember
    let value: Double
    /// 1 = best.
    let rank: Int
    let band: PerformanceBand
    var id: UUID { member.id }
}

nonisolated struct ClusterGap: Hashable, Sendable {
    enum Kind: Hashable, Sendable { case noFigures, noRevenue, mixedYears, mixedOutputUnits }
    let kind: Kind
    let message: String
}

nonisolated struct ClusterSummary: Sendable {
    let name: String
    let members: [ClusterMember]

    var reporting: [ClusterMember] { members.filter { $0.figures?.hasEmissions == true } }
    /// Share of members with Scope 1 + 2 figures.
    var coverage: Double { members.isEmpty ? 0 : Double(reporting.count) / Double(members.count) }

    var totalScope1: Double { reporting.compactMap { $0.figures?.scope1 }.reduce(0, +) }
    var totalScope2: Double { reporting.compactMap { $0.figures?.scope2 }.reduce(0, +) }
    var totalScope12: Double { totalScope1 + totalScope2 }
    var totalEnergyGJ: Double { members.compactMap { $0.figures?.energyGJ }.reduce(0, +) }

    /// Cluster-wide intensity: emissions ÷ revenue of the members that report both.
    var aggregateIntensityPerRevenue: Double? {
        let pairs = members.compactMap { member -> (Double, Double)? in
            guard let figures = member.figures, let emissions = figures.scope12, let revenue = figures.revenueCrore, revenue > 0
            else { return nil }
            return (emissions, revenue)
        }
        let revenue = pairs.reduce(0) { $0 + $1.1 }
        return revenue > 0 ? pairs.reduce(0) { $0 + $1.0 } / revenue : nil
    }

    var fiscalYears: [Int] { Array(Set(members.compactMap { $0.figures?.fiscalYearStart })).sorted() }

    /// The output unit shared by every member that reports output; empty if they differ.
    var sharedOutputUnit: String {
        let units = Set(members.compactMap { $0.figures }.filter { $0.output != nil }.map { $0.outputUnit.lowercased() })
        guard units.count == 1, let only = units.first else { return "" }
        return members.compactMap { $0.figures?.outputUnit }.first { $0.lowercased() == only } ?? only
    }

    /// Output-based ranking only makes sense when everyone measures output the same way.
    func isComparable(_ metric: BenchmarkMetric) -> Bool {
        metric != .intensityPerOutput || !sharedOutputUnit.isEmpty
    }

    func values(_ metric: BenchmarkMetric) -> [(member: ClusterMember, value: Double)] {
        members.compactMap { member in
            guard let figures = member.figures, let value = metric.value(figures) else { return nil }
            return (member, value)
        }
    }

    func statistics(_ metric: BenchmarkMetric) -> MetricStatistics? {
        ClusterBenchmark.statistics(values(metric).map { $0.value })
    }

    /// Members ranked best first, with their quartile band.
    func ranking(_ metric: BenchmarkMetric) -> [BenchmarkRow] {
        guard isComparable(metric), let stats = statistics(metric) else { return [] }
        let sorted = values(metric).sorted { metric.lowerIsBetter ? $0.value < $1.value : $0.value > $1.value }
        return sorted.enumerated().map { index, item in
            BenchmarkRow(member: item.member, value: item.value, rank: index + 1,
                         band: ClusterBenchmark.band(of: item.value, in: stats, lowerIsBetter: metric.lowerIsBetter))
        }
    }

    var gaps: [ClusterGap] {
        var gaps: [ClusterGap] = []
        let silent = members.filter { $0.figures?.hasEmissions != true }.map(\.name)
        if !silent.isEmpty {
            gaps.append(ClusterGap(kind: .noFigures, message: "No Scope 1 + 2 figures: " + silent.joined(separator: ", ")))
        }
        let noRevenue = reporting.filter { $0.figures?.revenueCrore == nil }.map(\.name)
        if !noRevenue.isEmpty {
            gaps.append(ClusterGap(kind: .noRevenue, message: "No revenue, so left out of intensity: " + noRevenue.joined(separator: ", ")))
        }
        if fiscalYears.count > 1 {
            gaps.append(ClusterGap(kind: .mixedYears,
                                   message: "Figures span " + fiscalYears.map { ReportingPeriod.label($0) }.joined(separator: ", ")
                                       + "; compare with care."))
        }
        let outputs = members.compactMap { $0.figures }.filter { $0.output != nil }
        if outputs.count > 1, sharedOutputUnit.isEmpty {
            gaps.append(ClusterGap(kind: .mixedOutputUnits, message: "Members measure output in different units, so output intensity is not ranked."))
        }
        return gaps
    }
}

nonisolated enum ClusterBenchmark {
    static func summarize(name: String, members: [ClusterMember]) -> ClusterSummary {
        ClusterSummary(name: name, members: members.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending })
    }

    /// Quartiles by linear interpolation between closest ranks; nil for no values.
    static func statistics(_ values: [Double]) -> MetricStatistics? {
        let sorted = values.sorted()
        guard let first = sorted.first, let last = sorted.last else { return nil }
        return MetricStatistics(count: sorted.count, minimum: first, lowerQuartile: percentile(sorted, 0.25),
                                median: percentile(sorted, 0.5), upperQuartile: percentile(sorted, 0.75), maximum: last)
    }

    /// `sorted` must be ascending and non-empty; `fraction` in 0...1.
    static func percentile(_ sorted: [Double], _ fraction: Double) -> Double {
        guard sorted.count > 1 else { return sorted[0] }
        let position = Double(sorted.count - 1) * fraction
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }

    static func band(of value: Double, in stats: MetricStatistics, lowerIsBetter: Bool) -> PerformanceBand {
        if lowerIsBetter {
            if value <= stats.lowerQuartile { return .leading }
            if value <= stats.median { return .aboveMedian }
            if value <= stats.upperQuartile { return .belowMedian }
            return .lagging
        } else {
            if value >= stats.upperQuartile { return .leading }
            if value >= stats.median { return .aboveMedian }
            if value >= stats.lowerQuartile { return .belowMedian }
            return .lagging
        }
    }

    /// One row per member with every metric, for sharing with the cluster association.
    static func csv(_ summary: ClusterSummary) -> String {
        let unit = summary.sharedOutputUnit
        let header = ["client", "size", "financial_year", "scope1_tco2e", "scope2_tco2e", "revenue_inr_crore"]
            + BenchmarkMetric.allCases.map { "\($0.rawValue) (\($0.unit(outputUnit: unit)))" }
        let rows = summary.members.map { member -> [String] in
            let figures = member.figures
            let base = [member.name, member.size.title,
                        figures.map { ReportingPeriod.label($0.fiscalYearStart) } ?? "",
                        number(figures?.scope1), number(figures?.scope2), number(figures?.revenueCrore)]
            return base + BenchmarkMetric.allCases.map { metric in
                guard summary.isComparable(metric), let figures else { return "" }
                return number(metric.value(figures))
            }
        }
        return CSVText.write(header: header, rows: rows)
    }

    private static func number(_ value: Double?) -> String {
        guard let value else { return "" }
        if value == value.rounded(), abs(value) < 1e15 { return String(Int64(value)) }
        return String(format: "%.4f", value)
    }
}
