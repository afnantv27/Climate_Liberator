import SwiftUI

/// All client engagements at a glance: readiness, open issues, deadlines.
struct PortfolioView: View {
    @ObservedObject var store: DisclosureStore
    let accent: Color
    let newEngagement: () -> Void

    @EnvironmentObject private var router: DisclosureRouter
    @State private var search = ""
    @State private var sort: SortOrder = .deadline

    enum SortOrder: String, CaseIterable, Identifiable {
        case deadline, readiness, name
        var id: String { rawValue }
        var title: String {
            switch self {
            case .deadline: return "Filing date"
            case .readiness: return "Least complete"
            case .name: return "Name"
            }
        }
    }

    private struct Row: Identifiable {
        let engagement: DisclosureEngagement
        let readiness: EngagementReadiness
        let blockers: Int
        let warnings: Int
        let awaitingReview: Int
        var id: UUID { engagement.id }
    }

    var body: some View {
        if store.engagements.isEmpty {
            DSCard("No Client Engagements Yet") {
                DSEmptyState(systemImage: "building.2.crop.circle",
                             title: "Start your first disclosure",
                             message: "An engagement is one company's report for one financial year. Create one, or load the example company to see a complete BRSR, BRSR Core and IFRS S2 workflow.") {
                    Button { newEngagement() } label: { Label("New Client", systemImage: "plus") }
                        .buttonStyle(.borderedProminent)
                        .tint(accent)
                    Button("Load Example Company") {
                        store.loadExample()
                        router.open(.overview)
                    }
                }
            }
        } else {
            let rows = sortedRows
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary(rows)
                    DSCard("Clients", subtitle: "One row per company and financial year. Open one to work on it.") {
                        HStack(spacing: 10) {
                            DSSearchField(text: $search, prompt: "Search clients")
                            Picker("Sort", selection: $sort) {
                                ForEach(SortOrder.allCases) { Text($0.title).tag($0) }
                            }
                            .frame(width: 200)
                        }
                    } content: {
                        VStack(spacing: 6) {
                            headerRow
                            ForEach(rows) { row in clientRow(row) }
                        }
                    }
                }
                .padding(.bottom, 16)
            }
        }
    }

    private var sortedRows: [Row] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        let rows = store.engagements
            .filter { query.isEmpty || $0.displayName.lowercased().contains(query) || $0.team.consultingFirm.lowercased().contains(query) }
            .map { engagement -> Row in
                let issues = DataQualityChecks.run(engagement)
                let waiting = engagement.metrics.values.filter { $0.status == .readyForReview }.count
                    + engagement.narratives.values.filter { $0.status == .readyForReview }.count
                return Row(engagement: engagement, readiness: ReadinessAnalyzer.analyze(engagement),
                           blockers: issues.filter { $0.severity == .blocker }.count,
                           warnings: issues.filter { $0.severity == .warning }.count,
                           awaitingReview: waiting)
            }
        switch sort {
        case .deadline:
            return rows.sorted { ($0.engagement.filingDeadline ?? .distantFuture) < ($1.engagement.filingDeadline ?? .distantFuture) }
        case .readiness:
            return rows.sorted { $0.readiness.overallAnswered < $1.readiness.overallAnswered }
        case .name:
            return rows.sorted { $0.engagement.displayName.localizedCaseInsensitiveCompare($1.engagement.displayName) == .orderedAscending }
        }
    }

    private func summary(_ rows: [Row]) -> some View {
        let signedOff = rows.filter { $0.engagement.isLocked }.count
        let dueSoon = rows.filter { row in
            guard let deadline = row.engagement.filingDeadline, !row.engagement.isLocked else { return false }
            return deadline.timeIntervalSinceNow < 30 * 86_400
        }.count
        let average = rows.isEmpty ? 0 : rows.reduce(0) { $0 + $1.readiness.overallAnswered } / Double(rows.count)
        return HStack(spacing: 12) {
            DSMetricTile(title: "Engagements", value: "\(rows.count)", detail: "\(signedOff) signed off", systemImage: "building.2")
            DSMetricTile(title: "Average completion", value: DisclosureFormat.percent(average), detail: "Required items answered",
                         systemImage: "chart.bar")
            DSMetricTile(title: "Due within 30 days", value: "\(dueSoon)", detail: "Not yet signed off", systemImage: "calendar.badge.exclamationmark")
            DSMetricTile(title: "Awaiting review", value: "\(rows.reduce(0) { $0 + $1.awaitingReview })",
                         detail: "Items submitted", systemImage: "paperplane")
        }
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("Client").frame(maxWidth: .infinity, alignment: .leading)
            Text("Frameworks").frame(width: 190, alignment: .leading)
            Text("Complete").frame(width: 120, alignment: .leading)
            Text("Issues").frame(width: 90, alignment: .leading)
            Text("Filing date").frame(width: 110, alignment: .leading)
            Text("").frame(width: 60)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(DSStyle.faint)
        .padding(.horizontal, 10)
    }

    private func clientRow(_ row: Row) -> some View {
        let engagement = row.engagement
        let isSelected = store.selectedID == engagement.id
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(engagement.companyName).font(.callout.weight(.semibold)).lineLimit(1)
                    if store.isUnsaved(engagement.id) { DSTag(text: "Not saved", color: .orange) }
                    if engagement.isLocked { DSTag(text: "Signed off", color: WorkflowStatus.approved.tint) }
                }
                Text([engagement.periodLabel, engagement.team.consultingFirm].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption)
                    .foregroundStyle(DSStyle.subtle)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: 4) {
                ForEach(DisclosureFramework.allCases.filter(engagement.frameworks.contains)) { framework in
                    DSTag(text: framework.title, color: framework.tint)
                }
            }
            .frame(width: 190, alignment: .leading)
            VStack(alignment: .leading, spacing: 3) {
                Text(DisclosureFormat.percent(row.readiness.overallAnswered)).font(.caption.monospacedDigit())
                DSProgressBar(value: row.readiness.overallAnswered, tint: accent, height: 5)
            }
            .frame(width: 120)
            HStack(spacing: 6) {
                if row.blockers > 0 {
                    Label("\(row.blockers)", systemImage: IssueSeverity.blocker.systemImage).foregroundStyle(IssueSeverity.blocker.tint)
                }
                if row.warnings > 0 {
                    Label("\(row.warnings)", systemImage: IssueSeverity.warning.systemImage).foregroundStyle(IssueSeverity.warning.tint)
                }
                if row.blockers == 0 && row.warnings == 0 {
                    Image(systemName: "checkmark.circle").foregroundStyle(WorkflowStatus.approved.tint)
                }
            }
            .font(.caption.monospacedDigit())
            .frame(width: 90, alignment: .leading)
            Text(engagement.filingDeadline.map(DisclosureFormat.date) ?? "Not set")
                .font(.caption)
                .foregroundStyle(deadlineColor(engagement))
                .frame(width: 110, alignment: .leading)
            Button("Open") {
                store.selectedID = engagement.id
                router.open(.overview)
            }
            .controlSize(.small)
            .frame(width: 60)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(isSelected ? DSStyle.rowSelected : DSStyle.rowFill))
    }

    private func deadlineColor(_ engagement: DisclosureEngagement) -> Color {
        guard let deadline = engagement.filingDeadline, !engagement.isLocked else { return DSStyle.subtle }
        let days = deadline.timeIntervalSinceNow / 86_400
        if days < 0 { return IssueSeverity.blocker.tint }
        if days < 30 { return IssueSeverity.warning.tint }
        return DSStyle.subtle
    }
}
