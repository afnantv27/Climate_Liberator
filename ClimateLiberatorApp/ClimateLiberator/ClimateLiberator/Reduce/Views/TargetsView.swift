import SwiftUI

/// Targets with their status, reference checks and pathway.
struct TargetsView: View {
    let context: ReducePlanContext

    @State private var selectedID: UUID?
    @State private var editing: ReductionTarget?

    private var assessments: [TargetAssessment] {
        context.plan.targets.map { TargetAssessor.assess($0, history: context.history) }
    }

    private var selected: TargetAssessment? {
        assessments.first { $0.target.id == selectedID } ?? assessments.first
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 14) {
                    targetList.frame(width: 360)
                    if let selected {
                        TargetDetailCard(assessment: selected, context: context)
                            .frame(maxWidth: .infinity)
                    } else {
                        DSCard("No targets yet") {
                            Text("Add a target, e.g. 42% lower Scope 1 + 2 emissions by FY 2030-31 from FY 2023-24. Progress is read from the client's reported figures.")
                                .font(.callout).foregroundStyle(DSStyle.subtle)
                        }
                    }
                }
                ReportedFiguresCard(history: context.history)
            }
            .padding(.bottom, 16)
        }
        .sheet(item: $editing) { target in
            TargetEditorSheet(target: target, accent: context.accent) { saved in
                context.store.upsertTarget(saved, client: context.clientID, name: context.clientName)
                selectedID = saved.id
            }
        }
    }

    private var targetList: some View {
        DSCard("Targets") {
            Button {
                let base = context.history.first(where: \.hasEmissions)?.fiscalYearStart ?? context.defaultYear
                editing = ReductionTarget(baseYear: base, targetYear: base + 7)
            } label: {
                Label("Add Target", systemImage: "plus")
            }
        } content: {
            VStack(spacing: 6) {
                ForEach(assessments, id: \.target.id) { assessment in
                    row(assessment)
                }
            }
        }
    }

    private func row(_ assessment: TargetAssessment) -> some View {
        let isSelected = assessment.target.id == (selected?.target.id)
        return Button { selectedID = assessment.target.id } label: {
            HStack(spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(assessment.target.displayName).font(.callout.weight(.medium)).lineLimit(2)
                    Text("\(assessment.target.framework.title) · \(assessment.target.kind.title)")
                        .font(.caption).foregroundStyle(DSStyle.subtle)
                }
                Spacer()
                TargetStatusTag(status: assessment.status)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? DSStyle.rowSelected : DSStyle.rowFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Edit…") { editing = assessment.target }
            Button("Delete", role: .destructive) {
                context.store.removeTarget(assessment.target.id, client: context.clientID, name: context.clientName)
            }
        }
    }
}

struct TargetStatusTag: View {
    let status: TargetStatus

    var body: some View {
        DSTag(text: status.title, color: color)
    }

    private var color: Color {
        switch status {
        case .achieved, .onTrack: return DSStyle.good
        case .offTrack: return DSStyle.bad
        case .notStarted, .noBaseline: return DSStyle.warning
        }
    }
}

/// Status, numbers, reference checks and chart for one target.
struct TargetDetailCard: View {
    let assessment: TargetAssessment
    let context: ReducePlanContext

    @State private var editing: ReductionTarget?

    private var unit: String {
        switch assessment.target.kind {
        case .absolute: return "tCO2e"
        case .intensityRevenue: return "tCO2e per ₹ crore"
        case .intensityOutput: return "tCO2e per unit"
        }
    }

    var body: some View {
        let target = assessment.target
        let shortfall = ReductionPathway.shortfall(assessment: assessment, measures: context.plan.measures)
        DSCard(target.displayName, subtitle: target.notes) {
            HStack(spacing: 8) {
                TargetStatusTag(status: assessment.status)
                Button("Edit") { editing = target }.controlSize(.small)
            }
        } content: {
            HStack(spacing: 12) {
                DSMetricTile(title: "Base · \(ReportingPeriod.label(target.baseYear))",
                             value: DisplayFormat.value(assessment.baseValue, unit: ""), detail: unit)
                DSMetricTile(title: "Target · \(ReportingPeriod.label(target.targetYear))",
                             value: DisplayFormat.value(assessment.targetValue, unit: ""),
                             detail: "−\(DisplayFormat.number(target.reductionPercent))%")
                DSMetricTile(title: assessment.latestYear.map { "Latest · \(ReportingPeriod.label($0))" } ?? "Latest",
                             value: DisplayFormat.value(assessment.latestValue, unit: ""),
                             detail: assessment.gapAtLatest == nil ? "No report after the base year" : "",
                             trend: assessment.gapAtLatest.map { gapText($0) },
                             trendIsGood: assessment.gapAtLatest.map { $0 <= 0 })
            }
            ReductionPathwayChart(points: ReductionPathway.points(for: assessment, history: context.history,
                                                                 measures: context.plan.measures),
                                  unit: unit, accent: context.accent)
            if let shortfall {
                Label(shortfall > 0
                      ? "Committed measures leave \(DisplayFormat.number(shortfall)) tCO2e to find by \(ReportingPeriod.label(target.targetYear))."
                      : "Committed measures reach the target with \(DisplayFormat.number(-shortfall)) tCO2e to spare.",
                      systemImage: shortfall > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                    .font(.callout)
                    .foregroundStyle(shortfall > 0 ? DSStyle.warning : DSStyle.good)
            }
            checks
        }
        .sheet(item: $editing) { target in
            TargetEditorSheet(target: target, accent: context.accent) { saved in
                context.store.upsertTarget(saved, client: context.clientID, name: context.clientName)
            }
        }
    }

    private static func icon(_ passed: Bool?) -> String {
        switch passed {
        case .none: return "minus.circle"
        case .some(true): return "checkmark.circle.fill"
        case .some(false): return "xmark.circle.fill"
        }
    }

    private static func color(_ passed: Bool?) -> Color {
        switch passed {
        case .none: return DSStyle.faint
        case .some(true): return DSStyle.good
        case .some(false): return DSStyle.bad
        }
    }

    private func gapText(_ gap: Double) -> String {
        gap <= 0 ? "\(DisplayFormat.number(-gap)) below the line" : "\(DisplayFormat.number(gap)) above the line"
    }

    @ViewBuilder
    private var checks: some View {
        let checks = assessment.checks()
        if !checks.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("CHECKS").font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint)
                ForEach(checks, id: \.self) { check in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: Self.icon(check.passed))
                            .foregroundStyle(Self.color(check.passed))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(check.title).font(.callout)
                            Text(check.detail).font(.caption).foregroundStyle(DSStyle.subtle)
                        }
                    }
                }
                if assessment.target.framework == .sbtiNearTerm {
                    Text("Reference checks from SBTi's near-term criteria. Required rates now depend on base year and Scope 1/2 mix; confirm with SBTi's current criteria and target-setting tool before submitting.")
                        .font(.caption2).foregroundStyle(DSStyle.faint).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// The reported figures the targets are measured against.
struct ReportedFiguresCard: View {
    let history: [ClientYearFigures]

    var body: some View {
        DSCard("Reported Figures", subtitle: "From the client's KPI Data in Report. Edit them there.") {
            if history.isEmpty {
                Text("No figures reported yet.").font(.callout).foregroundStyle(DSStyle.subtle)
            } else {
                Grid(alignment: .trailing, horizontalSpacing: 18, verticalSpacing: 6) {
                    GridRow {
                        Text("Year").gridColumnAlignment(.leading)
                        Text("Scope 1"); Text("Scope 2"); Text("Scope 3"); Text("Revenue (₹ cr)"); Text("Output")
                    }
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(DSStyle.faint)
                    ForEach(history, id: \.fiscalYearStart) { figures in
                        GridRow {
                            Text(ReportingPeriod.label(figures.fiscalYearStart))
                            Text(DisplayFormat.value(figures.scope1, unit: ""))
                            Text(DisplayFormat.value(figures.scope2, unit: ""))
                            Text(DisplayFormat.value(figures.scope3, unit: ""))
                            Text(DisplayFormat.value(figures.revenueCrore, unit: ""))
                            Text(DisplayFormat.value(figures.output, unit: figures.outputUnit))
                        }
                        .font(.callout.monospacedDigit())
                    }
                }
            }
        }
    }
}
