import Foundation

/// Cost per tonne for a client's measures, using the same annualisation and
/// cost-curve maths as the city action plans in GHG Accounting.
nonisolated enum MeasureCosting {
    static func economics(of measure: ReductionMeasure, discountRate: Double) -> MeasureEconomics {
        let running = (measure.annualOperatingCost ?? 0) - (measure.annualSavings ?? 0)
        let annualised: Double?
        if let capital = measure.capitalCost, capital != 0 {
            if let years = measure.lifetimeYears, years > 0 {
                annualised = capital * ActionPlanAnalysis.capitalRecoveryFactor(rate: discountRate, years: years) + running
            } else {
                annualised = nil   // a capital cost needs a lifetime to be spread
            }
        } else {
            annualised = measure.annualOperatingCost != nil || measure.annualSavings != nil ? running : nil
        }
        return MeasureEconomics(measureID: measure.id.uuidString, abatementTonnes: measure.annualAbatement ?? 0,
                                annualisedCost: annualised, capitalCost: measure.capitalCost)
    }

    /// Why a measure has no cost per tonne, in a few words; nil when it has one.
    static func gap(of measure: ReductionMeasure, economics: MeasureEconomics) -> String? {
        guard economics.costPerTonne == nil else { return nil }
        if (measure.annualAbatement ?? 0) <= 0 { return "Add the yearly cut" }
        if let capital = measure.capitalCost, capital != 0, (measure.lifetimeYears ?? 0) <= 0 { return "Add lifetime" }
        return "Add costs"
    }

    /// Cost curve segments, cheapest first.
    static func curve(_ measures: [ReductionMeasure], discountRate: Double) -> [MACSegment] {
        ActionPlanAnalysis.macCurve(measures.map { economics(of: $0, discountRate: discountRate) })
    }
}
