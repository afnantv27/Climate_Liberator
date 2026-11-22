import Foundation

/// Turns the KPI Data of a client's Disclosure engagements into `ClientYearFigures`,
/// one per financial year. Each engagement gives its own year (current column) and
/// the year before (prior-year column); the current column wins when both exist.
nonisolated enum DisclosurePerformanceSource {
    static let renewableTotalID = "energy.renewableTotal"

    /// Figures by year for one client, oldest first.
    static func history(for clientID: UUID, engagements: [DisclosureEngagement]) -> [ClientYearFigures] {
        let linked = engagements.filter { $0.clientID == clientID }
        var byYear: [Int: ClientYearFigures] = [:]
        let resolved = linked.map { ($0, MetricResolver($0)) }
        for (engagement, values) in resolved {
            let year = engagement.fiscalYearStart
            var figures = byYear[year] ?? ClientYearFigures(clientID: clientID, fiscalYearStart: year)
            fill(&figures, from: values, engagement: engagement, column: .current, overwrite: true)
            byYear[year] = figures
        }
        for (engagement, values) in resolved {
            let year = engagement.fiscalYearStart - 1
            var figures = byYear[year] ?? ClientYearFigures(clientID: clientID, fiscalYearStart: year)
            fill(&figures, from: values, engagement: engagement, column: .prior, overwrite: false)
            byYear[year] = figures
        }
        return byYear.values.filter(hasAnyFigure).sorted { $0.fiscalYearStart < $1.fiscalYearStart }
    }

    /// The most recent year with Scope 1 + 2 emissions, else the most recent with any data.
    static func latest(for clientID: UUID, engagements: [DisclosureEngagement]) -> ClientYearFigures? {
        let history = history(for: clientID, engagements: engagements)
        return history.last(where: \.hasEmissions) ?? history.last
    }

    // MARK: Internals

    private enum Column { case current, prior }

    private static func fill(_ figures: inout ClientYearFigures, from values: MetricResolver,
                             engagement: DisclosureEngagement, column: Column, overwrite: Bool) {
        func pick(_ id: String) -> Double? {
            column == .current ? values.current(id) : values.prior(id)
        }
        func set(_ path: WritableKeyPath<ClientYearFigures, Double?>, _ id: String) {
            guard let value = pick(id), overwrite || figures[keyPath: path] == nil else { return }
            figures[keyPath: path] = value
        }
        let before = figures
        set(\.scope1, MetricID.scope1)
        set(\.scope2, MetricID.scope2)
        set(\.scope3, MetricID.scope3)
        set(\.energyGJ, MetricID.energyTotal)
        set(\.renewableEnergyGJ, renewableTotalID)
        set(\.waterConsumptionKL, MetricID.waterConsumption)
        set(\.wasteGeneratedT, MetricID.wasteTotal)
        set(\.revenueCrore, MetricID.revenue)
        set(\.output, MetricID.output)
        let unit = engagement.metric(MetricID.outputUnit).text.trimmingCharacters(in: .whitespaces)
        if !unit.isEmpty, overwrite || figures.outputUnit.isEmpty { figures.outputUnit = unit }
        if figures != before, overwrite || figures.source.isEmpty {
            let label = ReportingPeriod.label(engagement.fiscalYearStart)
            figures.source = column == .current ? "KPI Data · \(label)" : "KPI Data · \(label), prior-year column"
        }
    }

    private static func hasAnyFigure(_ figures: ClientYearFigures) -> Bool {
        [figures.scope1, figures.scope2, figures.scope3, figures.energyGJ, figures.waterConsumptionKL,
         figures.wasteGeneratedT, figures.revenueCrore, figures.output].contains { $0 != nil }
    }
}
