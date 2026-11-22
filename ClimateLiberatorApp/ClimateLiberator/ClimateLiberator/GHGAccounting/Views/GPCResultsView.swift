import SwiftUI
import Charts

/// Ways to look at the final inventory.
enum GPCResultChart: String, CaseIterable, Identifiable {
    case sectorScope, sectorShare, topSources, gases, dataQuality, buildUp

    var id: String { rawValue }
    var title: String {
        switch self {
        case .sectorScope: return "Sector × Scope"
        case .sectorShare: return "Share by Sector"
        case .topSources: return "Largest Sources"
        case .gases: return "By Gas"
        case .dataQuality: return "Data Quality"
        case .buildUp: return "How the Total Builds Up"
        }
    }
    var systemImage: String {
        switch self {
        case .sectorScope: return "chart.bar.fill"
        case .sectorShare: return "chart.pie.fill"
        case .topSources: return "list.number"
        case .gases: return "cloud.fill"
        case .dataQuality: return "checkmark.seal.fill"
        case .buildUp: return "chart.bar.xaxis"
        }
    }
}

/// Step 4: totals, charts, the GPC sector × scope table and export.
struct GPCResultsView: View {
    @ObservedObject var store: GPCInventoryStore
    let inventory: GPCInventory
    let accent: Color

    @AppStorage("ghg.resultChart") private var chartKind: GPCResultChart = .sectorScope

    private struct ChartPoint: Identifiable {
        let sector: String
        let scope: String
        let value: Double
        var id: String { sector + scope }
    }

    var body: some View {
        let summary = GPCInventorySummary.make(inventory)
        let breakdown = GPCResultBreakdown.make(inventory, summary: summary)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                controls
                metrics(summary)
                HStack(alignment: .top, spacing: 14) {
                    chartCard(summary: summary, breakdown: breakdown)
                    sectorTable(summary)
                }
            }
            .padding(.bottom, 20)
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Picker("Reporting level", selection: Binding(get: { inventory.targetLevel },
                                                         set: { level in store.mutateSelected { $0.targetLevel = level } })) {
                ForEach(GPCReportingLevel.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .frame(width: 220)
            Picker("GWP values", selection: Binding(get: { inventory.gwpSet },
                                                    set: { gwp in store.mutateSelected { $0.gwpSet = gwp } })) {
                ForEach(GWPSet.allCases) { Text("IPCC \($0.title)").tag($0) }
            }
            .frame(width: 200)
            Spacer()
            Button {
                store.exportReports()
            } label: {
                Label("Export GPC Tables", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }

    private func metrics(_ summary: GPCInventorySummary) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 12) {
                GHGMetricCard(title: "BASIC", value: GHGFormat.tonnes(summary.basicTotal),
                              detail: summary.perCapitaBasic.map { "\(GHGFormat.number($0, maxDigits: 3)) tCO2e per person" } ?? "Add population for per-capita")
                GHGMetricCard(title: "BASIC+", value: GHGFormat.tonnes(summary.basicPlusTotal),
                              detail: summary.perCapitaBasicPlus.map { "\(GHGFormat.number($0, maxDigits: 3)) tCO2e per person" } ?? "Includes IPPU, AFOLU, T&D, transboundary")
                GHGMetricCard(title: "Scope 1 (territorial)", value: GHGFormat.tonnes(summary.territorialTotal),
                              detail: "All in-boundary sources, incl. grid generation and imported waste")
                GHGMetricCard(title: "Biogenic CO2", value: "\(GHGFormat.number(summary.biogenicCO2Tonnes)) t",
                              detail: "Reported separately, not in totals")
            }
            if let gasLine = Self.gasLine(summary.gasesBasicPlusTonnes) {
                Text(gasLine)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
                    .textSelection(.enabled)
            }
            if !store.statusMessage.isEmpty {
                Text(store.statusMessage).font(.caption).foregroundStyle(.white.opacity(0.7)).textSelection(.enabled)
            }
        }
    }

    /// GPC reports each gas separately; CH4 and N2O are tonnes of gas, not CO2e.
    static func gasLine(_ gases: GasAmounts) -> String? {
        guard !gases.isEmpty else { return nil }
        func t(_ value: Double) -> String { GHGFormat.number(value, maxDigits: 6) }
        var line = "BASIC+ by gas (tonnes of gas): CO2 \(t(gases.co2)) · CH4 \(t(gases.ch4Total)) · N2O \(t(gases.n2o))"
        if gases.sf6 + gases.nf3 > 0 { line += " · SF6 \(t(gases.sf6)) · NF3 \(t(gases.nf3))" }
        if gases.otherCO2e > 0 { line += " · entered as CO2e \(t(gases.otherCO2e)) tCO2e" }
        return line
    }

    // MARK: Charts

    private func chartCard(summary: GPCInventorySummary, breakdown: GPCResultBreakdown) -> some View {
        GHGPanelCard(title: chartKind.title, subtitle: caption(breakdown)) {
            Picker("View", selection: $chartKind) {
                ForEach(GPCResultChart.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        } content: {
            if chartKind != .sectorScope && breakdown.total == 0 {
                Text("No emissions in the \(breakdown.level.title) total yet.").foregroundStyle(.white.opacity(0.6))
            } else {
                switch chartKind {
                case .sectorScope: sectorScopeChart(summary)
                case .sectorShare: sectorShareChart(breakdown)
                case .topSources: topSourcesChart(breakdown)
                case .gases: gasChart(breakdown)
                case .dataQuality: dataQualityChart(breakdown)
                case .buildUp: buildUpChart(breakdown)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func caption(_ breakdown: GPCResultBreakdown) -> String {
        let level = breakdown.level.title
        let total = "\(GHGFormat.plain(breakdown.total)) tCO2e"
        switch chartKind {
        case .sectorScope:
            return "tCO2e, IPCC \(inventory.gwpSet.title) GWPs. Scope 1 includes territorial-only sources."
        case .sectorShare:
            return "Each sector's part of the \(level) total (\(total))."
        case .topSources:
            return "The ten largest lines in the \(level) total — where reductions matter most."
        case .gases:
            return "\(level) total split by gas, in CO2e (\(inventory.gwpSet.title) GWPs). Lines entered as tCO2e cannot be split."
        case .dataQuality:
            return "\(GHGFormat.percent(breakdown.lowQualityShare)) of the \(level) total rests on low-quality data — improve those lines first."
        case .buildUp:
            return "Sector by sector, adding up to the \(level) total (\(total))."
        }
    }

    private var sectorDomain: [String] { GPCSector.allCases.map(\.shortTitle) }
    private var sectorRange: [Color] { [accent, .orange, .green, .purple, .yellow, .gray] }

    private func sectorColor(_ name: String) -> Color {
        guard let index = sectorDomain.firstIndex(of: name), index < sectorRange.count else { return .gray }
        return sectorRange[index]
    }

    private func sectorScopeChart(_ summary: GPCInventorySummary) -> some View {
        let points: [ChartPoint] = GPCSector.allCases.flatMap { sector in
            GPCScope.allCases.compactMap { scope -> ChartPoint? in
                let value = summary.total(sector, scope)
                return value == 0 ? nil : ChartPoint(sector: sector.shortTitle, scope: scope.title, value: value)
            }
        }
        return Group {
            if points.isEmpty {
                Text("No emissions entered yet.").foregroundStyle(.white.opacity(0.6))
            } else {
                Chart(points) { point in
                    BarMark(x: .value("tCO2e", point.value), y: .value("Sector", point.sector))
                        .foregroundStyle(by: .value("Scope", point.scope))
                }
                .chartForegroundStyleScale(["Scope 1": accent, "Scope 2": Color.orange, "Scope 3": Color.purple])
                .frame(height: 260)
            }
        }
    }

    private func sectorShareChart(_ breakdown: GPCResultBreakdown) -> some View {
        HStack(alignment: .center, spacing: 18) {
            Chart(breakdown.bySector) { slice in
                SectorMark(angle: .value("tCO2e", slice.value), innerRadius: .ratio(0.62), angularInset: 1.5)
                    .cornerRadius(3)
                    .foregroundStyle(by: .value("Sector", slice.label))
            }
            .chartForegroundStyleScale(domain: sectorDomain, range: sectorRange)
            .chartLegend(.hidden)
            .chartBackground { proxy in
                GeometryReader { geometry in
                    if let plotFrame = proxy.plotFrame {
                        let frame = geometry[plotFrame]
                        VStack(spacing: 2) {
                            Text(GHGFormat.plain(breakdown.total)).font(.appSectionTitle.monospacedDigit())
                            Text("tCO2e \(breakdown.level.title)").font(.caption2).foregroundStyle(.secondary)
                        }
                        .position(x: frame.midX, y: frame.midY)
                    }
                }
            }
            .frame(width: 230, height: 230)
            legend(breakdown.bySector, total: breakdown.total) { sectorColor($0.label) }
        }
        .frame(minHeight: 260)
    }

    private func legend(_ slices: [GPCResultBreakdown.Slice], total: Double,
                        color: @escaping (GPCResultBreakdown.Slice) -> Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(slices) { slice in
                HStack(spacing: 8) {
                    Circle().fill(color(slice)).frame(width: 9, height: 9)
                    Text(slice.label).font(.callout)
                    Spacer(minLength: 8)
                    Text(GHGFormat.percent(slice.value / total)).font(.callout.weight(.semibold).monospacedDigit())
                    Text("\(GHGFormat.plain(slice.value)) t")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 84, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Ranked rows rather than a bar chart: long source names stay on one readable line,
    /// every bar starts at the same baseline, and tonnes and share sit in fixed columns.
    private func topSourcesChart(_ breakdown: GPCResultBreakdown) -> some View {
        let rows = breakdown.topSources
        let largest = max(rows.map(\.value).max() ?? 0, 1e-9)
        let covered = rows.reduce(0) { $0 + $1.value }
        let sectors = sectorDomain.filter { name in rows.contains { $0.group == name } }
        return VStack(alignment: .leading, spacing: 12) {
            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 9) {
                // Modifiers stay on cells: a modified GridRow is no longer laid out as a row.
                GridRow {
                    columnTitle("#").gridColumnAlignment(.trailing)
                    columnTitle("GPC ref")
                    columnTitle("Source")
                    columnTitle("")
                    columnTitle("tCO2e").gridColumnAlignment(.trailing)
                    columnTitle("Share").gridColumnAlignment(.trailing)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(Array(rows.enumerated()), id: \.element.id) { index, slice in
                    GridRow {
                        Text("\(index + 1)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(slice.code)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Text(slice.name)
                            .font(.callout)
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 340, alignment: .leading)
                            .help(slice.label)
                        sourceBar(fraction: slice.value / largest, color: sectorColor(slice.group))
                        Text(GHGFormat.plain(slice.value))
                            .font(.callout.monospacedDigit())
                        Text(GHGFormat.percent(breakdown.total > 0 ? slice.value / breakdown.total : 0))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            HStack(spacing: 14) {
                ForEach(sectors, id: \.self) { name in
                    HStack(spacing: 6) {
                        Circle().fill(sectorColor(name)).frame(width: 8, height: 8)
                        Text(name)
                    }
                }
                Spacer(minLength: 8)
                if breakdown.total > 0 {
                    Text("These \(rows.count) lines are \(GHGFormat.percent(covered / breakdown.total)) of the \(breakdown.level.title) total.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    private func columnTitle(_ text: String) -> some View {
        Text(text).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
    }

    /// A bar on a faint full-width track, so lengths compare at a glance.
    private func sourceBar(fraction: Double, color: Color) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.06))
                Capsule()
                    .fill(color.gradient)
                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(minWidth: 140, maxWidth: .infinity)
        .frame(height: 10)
    }

    private func gasChart(_ breakdown: GPCResultBreakdown) -> some View {
        Chart(breakdown.byGas) { slice in
            BarMark(x: .value("tCO2e", slice.value), y: .value("Gas", slice.label))
                .foregroundStyle(by: .value("Gas", slice.label))
                .annotation(position: .trailing) {
                    Text("\(GHGFormat.percent(slice.value / breakdown.total)) · \(GHGFormat.plain(slice.value)) t")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
        }
        .chartForegroundStyleScale(domain: ["CO2", "CH4", "N2O", "F-gases", "Entered as CO2e"],
                                   range: [Color.cyan, .orange, .pink, .purple, .gray])
        .chartLegend(.hidden)
        .frame(height: max(160, CGFloat(breakdown.byGas.count) * 44))
    }

    private func dataQualityChart(_ breakdown: GPCResultBreakdown) -> some View {
        Chart(breakdown.byQuality) { slice in
            BarMark(x: .value("tCO2e", slice.value), y: .value("Sector", slice.label))
                .foregroundStyle(by: .value("Data quality", slice.group))
        }
        .chartForegroundStyleScale(domain: GPCDataQuality.allCases.map(\.title), range: [Color.green, .yellow, .orange])
        .chartLegend(position: .bottom)
        .frame(height: 240)
    }

    private func buildUpChart(_ breakdown: GPCResultBreakdown) -> some View {
        Chart(breakdown.waterfall) { step in
            BarMark(xStart: .value("From", step.start), xEnd: .value("To", step.end), y: .value("Step", step.label))
                .foregroundStyle(step.isTotal ? accent : sectorColor(step.label).opacity(0.8))
                .annotation(position: .trailing) {
                    Text(step.isTotal ? GHGFormat.plain(step.end) : "+\(GHGFormat.plain(step.value))")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
        }
        .frame(height: max(200, CGFloat(breakdown.waterfall.count) * 40))
    }

    // MARK: Table

    private func sectorTable(_ summary: GPCInventorySummary) -> some View {
        GHGPanelCard(title: "GPC Summary", subtitle: "Sector × scope (tCO2e)") {
            // Modifiers stay on cells: a modified GridRow is no longer laid out as a row.
            Grid(alignment: .trailing, horizontalSpacing: 14, verticalSpacing: 6) {
                GridRow {
                    Text("Sector").fontWeight(.semibold).gridColumnAlignment(.leading)
                    Text("Scope 1").fontWeight(.semibold)
                    Text("Scope 2").fontWeight(.semibold)
                    Text("Scope 3").fontWeight(.semibold)
                    Text("Total").fontWeight(.semibold)
                }
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(GPCSector.allCases) { sector in
                    let values = GPCScope.allCases.map { summary.total(sector, $0) }
                    GridRow {
                        Text(sector.shortTitle).gridColumnAlignment(.leading)
                        Text(GHGFormat.number(values[0], maxDigits: 6))
                        Text(GHGFormat.number(values[1], maxDigits: 6))
                        Text(GHGFormat.number(values[2], maxDigits: 6))
                        Text(GHGFormat.number(values.reduce(0, +), maxDigits: 6)).fontWeight(.semibold)
                    }
                }
            }
            .font(.caption.monospacedDigit())
            Text("Scope 1 includes territorial-only items (I.4.4, III.x.3); BASIC/BASIC+ exclude them. Gaps and fixes are in step 3 Review.")
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
        }
        .frame(width: 460)
    }
}
