import SwiftUI
import Charts

/// The client's reduction measures, their cost per tonne and the cost curve.
struct MeasuresView: View {
    let context: ReducePlanContext

    @State private var editing: ReductionMeasure?

    private var measures: [ReductionMeasure] {
        context.plan.measures.sorted { ($0.startYear, $0.displayName) < ($1.startYear, $1.displayName) }
    }

    var body: some View {
        let rate = context.plan.discountRate
        let curve = MeasureCosting.curve(context.plan.measures.filter { $0.status.isCommitted }, discountRate: rate)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary
                DSCard("Measures", subtitle: "Ideas are listed but not counted in the projection on the Targets tab.") {
                    Button {
                        editing = ReductionMeasure(startYear: context.defaultYear + 1)
                    } label: {
                        Label("Add Measure", systemImage: "plus")
                    }
                } content: {
                    if measures.isEmpty {
                        Text("No measures yet. Add actions such as servo-drive retrofits on moulding machines, rooftop solar or chiller upgrades, with their yearly cut and costs.")
                            .font(.callout).foregroundStyle(DSStyle.subtle)
                    }
                    VStack(spacing: 6) {
                        ForEach(measures) { measure in row(measure, rate: rate) }
                    }
                }
                if !curve.isEmpty {
                    DSCard("Cost per Tonne", subtitle: "Committed measures with costs, cheapest first. Width is the yearly cut; below zero saves money.") {
                        MeasureCostChart(segments: curve, names: Dictionary(uniqueKeysWithValues: context.plan.measures.map { ($0.id.uuidString, $0.displayName) }),
                                         accent: context.accent)
                    }
                }
            }
            .padding(.bottom, 16)
        }
        .sheet(item: $editing) { measure in
            MeasureEditorSheet(measure: measure, accent: context.accent) { saved in
                context.store.upsertMeasure(saved, client: context.clientID, name: context.clientName)
            }
        }
    }

    private var summary: some View {
        let committed = context.plan.measures.filter { $0.status.isCommitted }
        let cut = committed.reduce(0) { $0 + ($1.annualAbatement ?? 0) }
        let capital = committed.reduce(0) { $0 + ($1.capitalCost ?? 0) }
        let savings = committed.reduce(0) { $0 + ($1.annualSavings ?? 0) }
        return HStack(spacing: 12) {
            DSMetricTile(title: "Committed measures", value: "\(committed.count)",
                         detail: "\(context.plan.measures.count - committed.count) ideas", systemImage: "list.bullet")
            DSMetricTile(title: "Yearly cut", value: DisplayFormat.value(cut, unit: "tCO2e"), systemImage: "arrow.down.right")
            DSMetricTile(title: "Capital", value: "₹ " + DisplayFormat.number(capital), systemImage: "indianrupeesign")
            DSMetricTile(title: "Yearly savings", value: "₹ " + DisplayFormat.number(savings),
                         detail: "Discount rate \(DisplayFormat.percent(context.plan.discountRate)) (assumption)", systemImage: "banknote")
        }
    }

    private func row(_ measure: ReductionMeasure, rate: Double) -> some View {
        let economics = MeasureCosting.economics(of: measure, discountRate: rate)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(measure.displayName).font(.callout.weight(.medium))
                Text([measure.scope.title, "from \(ReportingPeriod.label(measure.startYear))", measure.owner]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(DSStyle.subtle)
            }
            Spacer()
            DSTag(text: measure.status.title, color: measure.status == .idea ? DSStyle.faint : measure.status == .done ? DSStyle.good : DSStyle.info)
            Text(DisplayFormat.value(measure.annualAbatement, unit: "t/yr"))
                .font(.callout.monospacedDigit()).frame(width: 100, alignment: .trailing)
            Group {
                if let cost = economics.costPerTonne {
                    Text("₹\(DisplayFormat.number(cost))/t").foregroundStyle(cost < 0 ? DSStyle.good : .white)
                } else {
                    Text(MeasureCosting.gap(of: measure, economics: economics) ?? "").foregroundStyle(DSStyle.faint)
                }
            }
            .font(.caption.monospacedDigit())
            .frame(width: 110, alignment: .trailing)
            Button { editing = measure } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            Button {
                context.store.removeMeasure(measure.id, client: context.clientID, name: context.clientName)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }
}

/// Marginal abatement cost curve: bar width = yearly cut, height = ₹ per tonne.
struct MeasureCostChart: View {
    let segments: [MACSegment]
    let names: [String: String]
    let accent: Color

    var body: some View {
        Chart(segments) { segment in
            RectangleMark(xStart: .value("Cut from", segment.startTonnes), xEnd: .value("Cut to", segment.endTonnes),
                          yStart: .value("₹/t", 0), yEnd: .value("₹/t", segment.costPerTonne))
                .foregroundStyle(segment.costPerTonne < 0 ? DSStyle.good : accent)
                .annotation(position: segment.costPerTonne < 0 ? .bottom : .top) {
                    Text(names[segment.measureID] ?? "").font(.caption2).foregroundStyle(DSStyle.subtle).lineLimit(1)
                }
        }
        .chartXAxisLabel("Yearly cut (tCO2e)")
        .chartYAxisLabel("₹ per tonne")
        .chartXAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel().foregroundStyle(DSStyle.faint) } }
        .chartYAxis { AxisMarks { _ in AxisGridLine().foregroundStyle(.white.opacity(0.08)); AxisValueLabel().foregroundStyle(DSStyle.faint) } }
        .frame(height: 240)
    }
}
