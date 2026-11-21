import Foundation

/// A metric's current and prior values after calculation.
nonisolated struct ResolvedMetric: Sendable {
    let current: Double?
    let prior: Double?
    /// Some inputs of a total were missing, so the total is incomplete.
    let isPartial: Bool

    static let empty = ResolvedMetric(current: nil, prior: nil, isPartial: false)
}

/// Turns an engagement's inputs into values for every metric, calculating totals,
/// shares and intensities from their inputs. Pure and cheap: recompute freely.
nonisolated struct MetricResolver: Sendable {
    let values: [String: ResolvedMetric]

    init(_ engagement: DisclosureEngagement) {
        var memo: [String: ResolvedMetric] = [:]
        for definition in MetricCatalog.all {
            _ = Self.resolve(definition.id, engagement: engagement, memo: &memo, depth: 0)
        }
        values = memo
    }

    subscript(_ id: String) -> ResolvedMetric { values[id] ?? .empty }
    func current(_ id: String) -> Double? { values[id]?.current }
    func prior(_ id: String) -> Double? { values[id]?.prior }

    // MARK: Calculation

    private static func resolve(_ id: String, engagement: DisclosureEngagement,
                                memo: inout [String: ResolvedMetric], depth: Int) -> ResolvedMetric {
        if let known = memo[id] { return known }
        guard depth < 16, let definition = MetricCatalog.metric(id) else { return .empty }

        let result: ResolvedMetric
        if let derivation = definition.derivation {
            func value(_ input: String) -> ResolvedMetric {
                resolve(input, engagement: engagement, memo: &memo, depth: depth + 1)
            }
            result = calculate(derivation, value: value)
        } else {
            let entry = engagement.metric(id)
            // Not applicable counts as zero in totals; an unanswered input stays missing.
            if entry.notApplicable {
                result = ResolvedMetric(current: 0, prior: entry.prior ?? 0, isPartial: false)
            } else {
                result = ResolvedMetric(current: entry.current, prior: entry.prior, isPartial: false)
            }
        }
        memo[id] = result
        return result
    }

    private static func calculate(_ derivation: Derivation, value: (String) -> ResolvedMetric) -> ResolvedMetric {
        switch derivation {
        case .sum(let ids):
            return sum(ids, value: value)
        case .ratio(let numerator, let denominator, let scale):
            let top = sum(numerator, value: value)
            let bottom = sum(denominator, value: value)
            return ResolvedMetric(current: divide(top.current, bottom.current, scale: scale),
                                  prior: divide(top.prior, bottom.prior, scale: scale),
                                  isPartial: top.isPartial || bottom.isPartial)
        case .perRevenue(let ids):
            let top = sum(ids, value: value)
            let revenue = value(MetricID.revenue)
            return ResolvedMetric(current: divide(top.current, revenue.current, scale: 1),
                                  prior: divide(top.prior, revenue.prior, scale: 1),
                                  isPartial: top.isPartial)
        case .perPPPRevenue(let ids):
            let top = sum(ids, value: value)
            let revenue = value(MetricID.revenue)
            let ppp = value(MetricID.pppRate)
            // The PPP rate is a single input; the prior year falls back to it when no prior rate is given.
            return ResolvedMetric(current: perPPP(top.current, revenueCrore: revenue.current, rate: ppp.current),
                                  prior: perPPP(top.prior, revenueCrore: revenue.prior, rate: ppp.prior ?? ppp.current),
                                  isPartial: top.isPartial)
        case .perOutput(let ids):
            let top = sum(ids, value: value)
            let output = value(MetricID.output)
            return ResolvedMetric(current: divide(top.current, output.current, scale: 1),
                                  prior: divide(top.prior, output.prior, scale: 1),
                                  isPartial: top.isPartial)
        }
    }

    private static func sum(_ ids: [String], value: (String) -> ResolvedMetric) -> ResolvedMetric {
        let parts = ids.map(value)
        func total(_ pick: (ResolvedMetric) -> Double?) -> (Double?, Bool) {
            let present = parts.compactMap(pick)
            guard !present.isEmpty else { return (nil, false) }
            return (present.reduce(0, +), present.count < parts.count)
        }
        let (current, currentPartial) = total { $0.current }
        let (prior, _) = total { $0.prior }
        return ResolvedMetric(current: current, prior: prior,
                              isPartial: currentPartial || parts.contains { $0.isPartial })
    }

    private static func divide(_ numerator: Double?, _ denominator: Double?, scale: Double) -> Double? {
        guard let numerator, let denominator, denominator != 0 else { return nil }
        return numerator / denominator * scale
    }

    /// Value per million international dollars: revenue (₹ crore × 10⁷) ÷ PPP rate (₹ per $) gives $.
    static func perPPP(_ value: Double?, revenueCrore: Double?, rate: Double?) -> Double? {
        guard let value, let revenueCrore, let rate, revenueCrore > 0, rate > 0 else { return nil }
        let millionDollars = revenueCrore * 10_000_000 / rate / 1_000_000
        return value / millionDollars
    }

    /// Plain-language formula for a calculated metric.
    static func describe(_ derivation: Derivation) -> String {
        func names(_ ids: [String]) -> String {
            ids.map { MetricCatalog.metric($0)?.title ?? $0 }.joined(separator: " + ")
        }
        switch derivation {
        case .sum(let ids):
            return names(ids)
        case .ratio(let numerator, let denominator, let scale):
            let factor = scale == 1 ? "" : scale == 100 ? " × 100" : " × \(DisclosureFormat.number(scale))"
            return "(\(names(numerator))) ÷ (\(names(denominator)))\(factor)"
        case .perRevenue(let ids):
            return "(\(names(ids))) ÷ revenue from operations (₹ crore)"
        case .perPPPRevenue(let ids):
            return "(\(names(ids))) ÷ revenue adjusted for PPP (million international $)"
        case .perOutput(let ids):
            return "(\(names(ids))) ÷ physical output"
        }
    }
}
