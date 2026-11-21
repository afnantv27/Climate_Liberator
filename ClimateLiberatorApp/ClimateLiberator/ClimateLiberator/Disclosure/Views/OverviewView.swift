import SwiftUI

/// Engagement dashboard: readiness, headline KPIs, workflow, checks and activity.
struct OverviewView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let accent: Color

    @EnvironmentObject private var router: DisclosureRouter

    var body: some View {
        let values = MetricResolver(engagement)
        let readiness = ReadinessAnalyzer.analyze(engagement)
        let issues = DataQualityChecks.run(engagement, resolved: values)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                banner(readiness: readiness, issues: issues)
                readinessRow(readiness)
                kpiGrid(values)
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 14) {
                            checksCard(issues)
                            workflowCard(readiness)
                        }
                        .frame(minWidth: 420)
                        VStack(spacing: 14) {
                            coreCard(readiness)
                            activityCard
                        }
                        .frame(minWidth: 360)
                    }
                    VStack(spacing: 14) {
                        checksCard(issues)
                        workflowCard(readiness)
                        coreCard(readiness)
                        activityCard
                    }
                }
            }
            .padding(.bottom, 16)
        }
    }

    // MARK: Banner

    private func banner(readiness: EngagementReadiness, issues: [QualityIssue]) -> some View {
        let blockers = issues.filter { $0.severity == .blocker }.count
        return HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(engagement.companyName).font(.title2.weight(.semibold))
                Text("\(engagement.periodLabel) · \(engagement.boundary.title) · \(engagement.profile.sector.title)"
                     + (engagement.team.consultingFirm.isEmpty ? "" : " · \(engagement.team.consultingFirm)"))
                    .font(.callout)
                    .foregroundStyle(DSStyle.subtle)
                if engagement.isExample {
                    Label("Illustrative example: the company and every figure are invented.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 6) {
                if let signOff = engagement.signOff {
                    Label("Signed off by \(signOff.approvedBy), \(DisclosureFormat.date(signOff.approvedAt))", systemImage: "checkmark.seal.fill")
                        .foregroundStyle(WorkflowStatus.approved.tint)
                } else if let deadline = engagement.filingDeadline {
                    let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()),
                                                               to: Calendar.current.startOfDay(for: deadline)).day ?? 0
                    Label(days >= 0 ? "\(days) days to filing (\(DisclosureFormat.date(deadline)))"
                                    : "Filing date passed \(DisclosureFormat.date(deadline))",
                          systemImage: "calendar")
                        .foregroundStyle(days < 0 ? IssueSeverity.blocker.tint : days <= 30 ? IssueSeverity.warning.tint : DSStyle.subtle)
                } else {
                    Button("Set filing date") { router.open(.setup) }.controlSize(.small)
                }
                if blockers > 0 {
                    Label("\(blockers) blocker\(blockers == 1 ? "" : "s") before sign-off", systemImage: IssueSeverity.blocker.systemImage)
                        .foregroundStyle(IssueSeverity.blocker.tint)
                }
            }
            .font(.callout)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(DSStyle.panel))
    }

    // MARK: Readiness

    private func readinessRow(_ readiness: EngagementReadiness) -> some View {
        HStack(spacing: 12) {
            ForEach(readiness.frameworks) { item in
                HStack(spacing: 14) {
                    DSProgressRing(value: item.answeredShare, label: "complete", tint: item.framework.tint)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.framework.title).font(.headline)
                        Text("\(item.dataPointsAnswered) of \(item.dataPoints) data points")
                            .font(.caption).foregroundStyle(DSStyle.subtle)
                        if item.narratives > 0 {
                            Text("\(item.narrativesAnswered) of \(item.narratives) narratives").font(.caption).foregroundStyle(DSStyle.subtle)
                        }
                        Text("\(DisclosureFormat.percent(item.approvedShare)) approved")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(WorkflowStatus.approved.tint)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DSStyle.panel))
            }
            if readiness.frameworks.isEmpty {
                DSCard("No frameworks in scope") {
                    Button("Choose frameworks") { router.open(.setup) }
                }
            }
        }
    }

    // MARK: KPIs

    private func kpiGrid(_ values: MetricResolver) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            tile("Scope 1 + 2", MetricID.scope12, values, lowerIsBetter: true, image: "smoke")
            tile("GHG intensity (PPP)", MetricID.ghgIntensityPPP, values, lowerIsBetter: true, image: "chart.line.downtrend.xyaxis")
            tile("Energy consumed", MetricID.energyTotal, values, lowerIsBetter: true, image: "bolt")
            tile("Renewable energy", MetricID.renewableShare, values, lowerIsBetter: false, image: "sun.max")
            tile("Water consumed", MetricID.waterConsumption, values, lowerIsBetter: true, image: "drop")
            tile("Waste generated", MetricID.wasteTotal, values, lowerIsBetter: true, image: "trash")
            tile("LTIFR", MetricID.ltifr, values, lowerIsBetter: true, image: "cross.case")
            tile("Wages paid to women", MetricID.femaleWageShare, values, lowerIsBetter: false, image: "person.2")
        }
    }

    private func tile(_ title: String, _ id: String, _ values: MetricResolver, lowerIsBetter: Bool, image: String) -> some View {
        let definition = MetricCatalog.metric(id)
        let resolved = values[id]
        let ratio = DisclosureFormat.changeRatio(current: resolved.current, prior: resolved.prior)
        let unit = definition?.unit ?? ""
        return Button {
            router.openMetric(id)
        } label: {
            DSMetricTile(title: title,
                         value: DisclosureFormat.value(resolved.current, unit: unit == "%" ? "%" : ""),
                         detail: unit == "%" ? "vs \(engagement.priorPeriodLabel)" : unit,
                         trend: DisclosureFormat.change(current: resolved.current, prior: resolved.prior),
                         trendIsGood: Self.isGood(ratio, lowerIsBetter: lowerIsBetter),
                         systemImage: image)
        }
        .buttonStyle(.plain)
        .help("\(definition?.title ?? title): open in KPI Data")
    }

    /// nil when there is no change to judge.
    private static func isGood(_ ratio: Double?, lowerIsBetter: Bool) -> Bool? {
        guard let ratio, abs(ratio) >= 0.0005 else { return nil }
        return lowerIsBetter ? ratio < 0 : ratio > 0
    }

    // MARK: Checks and workflow

    private func checksCard(_ issues: [QualityIssue]) -> some View {
        DSCard("Data Checks", subtitle: issues.isEmpty ? "Nothing to fix." : "What a reviewer or assurer would query, most serious first.") {
            Button("See all") { router.open(.review) }.controlSize(.small)
        } content: {
            if issues.isEmpty {
                Label("All checks pass.", systemImage: "checkmark.circle").foregroundStyle(WorkflowStatus.approved.tint)
            } else {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(issues.prefix(6)) { issue in
                        DSIssueRow(issue: issue) { router.open(issue) }
                    }
                    if issues.count > 6 {
                        Text("\(issues.count - 6) more in Review & Approval").font(.caption).foregroundStyle(DSStyle.faint)
                    }
                }
            }
        }
    }

    private func workflowCard(_ readiness: EngagementReadiness) -> some View {
        let total = max(readiness.totalItems, 1)
        return DSCard("Workflow", subtitle: "Required data points and narratives by review status.") {
            VStack(alignment: .leading, spacing: 10) {
                GeometryReader { proxy in
                    HStack(spacing: 2) {
                        ForEach(WorkflowStatus.allCases) { status in
                            let count = readiness.statusCounts[status] ?? 0
                            if count > 0 {
                                Rectangle()
                                    .fill(status.tint)
                                    .frame(width: max(3, proxy.size.width * CGFloat(count) / CGFloat(total) - 2))
                            }
                        }
                    }
                }
                .frame(height: 12)
                .clipShape(Capsule())
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 6) {
                    ForEach(WorkflowStatus.allCases) { status in
                        HStack(spacing: 6) {
                            Circle().fill(status.tint).frame(width: 8, height: 8)
                            Text(status.title).font(.caption)
                            Text("\(readiness.statusCounts[status] ?? 0)").font(.caption.monospacedDigit()).foregroundStyle(DSStyle.subtle)
                        }
                    }
                }
            }
        }
    }

    // MARK: BRSR Core

    private func coreCard(_ readiness: EngagementReadiness) -> some View {
        DSCard("BRSR Core Assurance Readiness",
               subtitle: engagement.frameworks.contains(.brsrCore)
                   ? "Value, prior year, source or method, evidence and approval for each Core input."
                   : "BRSR Core is not in scope for this engagement.") {
            if engagement.frameworks.contains(.brsrCore) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Checks passed").font(.caption).foregroundStyle(DSStyle.subtle)
                        Spacer()
                        Text(DisclosureFormat.percent(readiness.coreAssuranceScore)).font(.callout.weight(.semibold).monospacedDigit())
                    }
                    DSProgressBar(value: readiness.coreAssuranceScore, tint: DisclosureFramework.brsrCore.tint)
                    ForEach(BRSRCoreAttribute.allCases) { attribute in
                        let rows = readiness.coreRows.filter { MetricCatalog.metric($0.metricID)?.core == attribute }
                        let passed = rows.reduce(0) { $0 + $1.checksPassed }
                        let possible = max(rows.count * CoreAssuranceRow.checkCount, 1)
                        Button {
                            if let first = rows.first { router.openMetric(first.metricID) }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: attribute.systemImage).frame(width: 16).foregroundStyle(DSStyle.subtle)
                                Text(attribute.title).font(.caption).lineLimit(1)
                                Spacer(minLength: 6)
                                DSProgressBar(value: Double(passed) / Double(possible), tint: DisclosureFramework.brsrCore.tint, height: 5)
                                    .frame(width: 90)
                                Text(DisclosureFormat.percent(Double(passed) / Double(possible)))
                                    .font(.caption.monospacedDigit())
                                    .frame(width: 40, alignment: .trailing)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Activity

    private var activityCard: some View {
        DSCard("Recent Activity") {
            Button("Audit trail") { router.open(.review) }.controlSize(.small)
        } content: {
            if engagement.activity.isEmpty {
                Text("No activity yet.").font(.caption).foregroundStyle(DSStyle.subtle)
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(engagement.activity.suffix(7).reversed())) { event in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(DisclosureFormat.dateTime(event.date)).font(.caption2.monospacedDigit()).foregroundStyle(DSStyle.faint)
                                .frame(width: 118, alignment: .leading)
                            VStack(alignment: .leading, spacing: 1) {
                                Text("\(event.user): \(event.action)").font(.caption.weight(.medium))
                                if !event.target.isEmpty {
                                    Text(event.target + (event.detail.isEmpty ? "" : " — \(event.detail)"))
                                        .font(.caption).foregroundStyle(DSStyle.subtle).lineLimit(2)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
