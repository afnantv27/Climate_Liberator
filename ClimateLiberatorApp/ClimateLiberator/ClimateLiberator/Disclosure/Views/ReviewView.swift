import SwiftUI

/// Reviewer's desk: items waiting for review, data checks, sign-off and audit trail.
struct ReviewView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let accent: Color

    @EnvironmentObject private var router: DisclosureRouter
    @State private var tab: Tab = .queue
    @State private var statement = ""
    @State private var reopenReason = ""
    @State private var confirmingApproveAll = false
    @State private var auditSearch = ""

    enum Tab: String, CaseIterable, Identifiable {
        case queue, checks, signOff, audit
        var id: String { rawValue }
        var title: String {
            switch self {
            case .queue: return "Review Queue"
            case .checks: return "Data Checks"
            case .signOff: return "Sign-off"
            case .audit: return "Audit Trail"
            }
        }
    }

    /// One item awaiting review: a KPI or a narrative.
    struct QueueItem: Identifiable {
        enum Kind { case metric, narrative }
        let kind: Kind
        let id: String
        let title: String
        let reference: String
        let summary: String
        let updatedBy: String
        let status: WorkflowStatus
    }

    private var locked: Bool { engagement.isLocked }

    private var queue: [QueueItem] {
        let values = MetricResolver(engagement)
        var items: [QueueItem] = []
        for definition in MetricCatalog.all where !definition.isCalculated {
            let entry = engagement.metric(definition.id)
            guard entry.status == .readyForReview || entry.status == .changesRequested else { continue }
            let unit = definition.unit == "count" ? "" : definition.unit
            let value = entry.notApplicable ? "Not applicable: \(entry.notApplicableReason)"
                : definition.isText ? entry.text
                : "\(DisclosureFormat.value(values[definition.id].current, unit: unit)) (prior \(DisclosureFormat.value(values[definition.id].prior, unit: unit)))"
            items.append(QueueItem(kind: .metric, id: definition.id, title: definition.title, reference: definition.referenceLine,
                                   summary: value, updatedBy: entry.updatedBy, status: entry.status))
        }
        for requirement in NarrativeCatalog.inScope(engagement.frameworks) {
            let entry = engagement.narrative(requirement.id)
            guard entry.status == .readyForReview || entry.status == .changesRequested else { continue }
            let preview = entry.notApplicable ? "Not applicable: \(entry.notApplicableReason)" : String(entry.text.prefix(220))
            items.append(QueueItem(kind: .narrative, id: requirement.id, title: requirement.title, reference: requirement.reference,
                                   summary: preview, updatedBy: entry.updatedBy, status: entry.status))
        }
        return items
    }

    var body: some View {
        let issues = DataQualityChecks.run(engagement)
        let items = queue
        VStack(alignment: .leading, spacing: 12) {
            Picker("", selection: $tab) {
                ForEach(Tab.allCases) { tab in
                    Text(label(for: tab, items: items, issues: issues)).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .frame(maxWidth: 620)
            ScrollView {
                switch tab {
                case .queue: queueCard(items)
                case .checks: checksCard(issues)
                case .signOff: signOffCard(issues)
                case .audit: auditCard
                }
            }
        }
    }

    private func label(for tab: Tab, items: [QueueItem], issues: [QualityIssue]) -> String {
        switch tab {
        case .queue:
            let waiting = items.filter { $0.status == .readyForReview }.count
            return waiting == 0 ? tab.title : "\(tab.title) (\(waiting))"
        case .checks:
            return issues.isEmpty ? tab.title : "\(tab.title) (\(issues.count))"
        default:
            return tab.title
        }
    }

    // MARK: Queue

    private func queueCard(_ items: [QueueItem]) -> some View {
        let waiting = items.filter { $0.status == .readyForReview }
        let returned = items.filter { $0.status == .changesRequested }
        return DSCard("Waiting for Review",
                      subtitle: "Submitted KPIs and narratives. Approve, or send back with a comment. Edits after approval withdraw it automatically.") {
            if waiting.count > 1 {
                Button("Approve All \(waiting.count)…") { confirmingApproveAll = true }
                    .disabled(locked)
            }
        } content: {
            if items.isEmpty {
                DSEmptyState(systemImage: "tray", title: "Nothing to review",
                             message: "Preparers submit KPIs and narratives for review from KPI Data and Narratives.") {
                    Button("Open KPI Data") { router.open(.data) }
                }
            }
            VStack(spacing: 6) {
                ForEach(waiting) { item in QueueRow(store: store, engagement: engagement, item: item) }
            }
            if !returned.isEmpty {
                Text("SENT BACK TO THE PREPARER").font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint).padding(.top, 8)
                VStack(spacing: 6) {
                    ForEach(returned) { item in QueueRow(store: store, engagement: engagement, item: item) }
                }
            }
        }
        .confirmationDialog("Approve \(waiting.count) items?", isPresented: $confirmingApproveAll) {
            Button("Approve All") {
                for item in waiting {
                    switch item.kind {
                    case .metric: store.review(.approve, metric: item.id, in: engagement.id)
                    case .narrative: store.review(.approve, narrative: item.id, in: engagement.id)
                    }
                }
            }
        } message: {
            Text("Each approval is recorded in the audit trail under your name (\(store.userName)). Only approve values you have checked.")
        }
    }

    // MARK: Checks

    private func checksCard(_ issues: [QualityIssue]) -> some View {
        DSCard("Data Checks", subtitle: "Blockers stop sign-off. Warnings are what an assessor would query. Select Fix to go to the field.") {
            if issues.isEmpty {
                Label("No issues found.", systemImage: "checkmark.circle").foregroundStyle(WorkflowStatus.approved.tint)
            }
            ForEach(IssueSeverity.allCases, id: \.self) { severity in
                let group = issues.filter { $0.severity == severity }
                if !group.isEmpty {
                    Text("\(severity.title.uppercased()) · \(group.count)").font(.caption2.weight(.semibold)).foregroundStyle(severity.tint)
                        .padding(.top, 4)
                    ForEach(group) { issue in
                        DSIssueRow(issue: issue) { router.open(issue) }
                    }
                }
            }
        }
    }

    // MARK: Sign-off

    @ViewBuilder
    private func signOffCard(_ issues: [QualityIssue]) -> some View {
        if let signOff = engagement.signOff {
            DSCard("Signed Off", subtitle: "The engagement is read-only. Reopen it to make changes; the reopening is recorded.") {
                Label("Approved by \(signOff.approvedBy) on \(DisclosureFormat.dateTime(signOff.approvedAt))", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(WorkflowStatus.approved.tint)
                if !signOff.statement.isEmpty {
                    Text(signOff.statement).font(.callout).foregroundStyle(DSStyle.subtle)
                }
                Divider()
                TextField("Reason for reopening (required)", text: $reopenReason).textFieldStyle(.roundedBorder).frame(maxWidth: 480)
                Button { store.reopen(id: engagement.id, reason: reopenReason); reopenReason = "" } label: {
                    Label("Reopen Engagement", systemImage: "lock.open")
                }
                .disabled(reopenReason.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } else {
            let blockers = WorkflowEngine.signOffBlockers(engagement, issues: issues)
            DSCard("Sign-off", subtitle: "Final approval of the whole engagement by the named approver. After sign-off nothing can be edited until it is reopened.") {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    DSFormRow("Preparer", width: 120) { Text(engagement.team.preparer.isEmpty ? "—" : engagement.team.preparer) }
                    DSFormRow("Reviewer", width: 120) { Text(engagement.team.reviewer.isEmpty ? "—" : engagement.team.reviewer) }
                    DSFormRow("Approver", width: 120) { Text(engagement.team.approver.isEmpty ? "—" : engagement.team.approver) }
                    DSFormRow("Signing as", width: 120) { Text(store.userName).foregroundStyle(accent) }
                }
                if !engagement.team.approver.isEmpty,
                   engagement.team.approver.caseInsensitiveCompare(store.userName) != .orderedSame {
                    Label("You are not the named approver (\(engagement.team.approver)).", systemImage: "person.crop.circle.badge.exclamationmark")
                        .font(.caption).foregroundStyle(IssueSeverity.warning.tint)
                }
                if blockers.isEmpty {
                    Label("Ready to sign off.", systemImage: "checkmark.circle").foregroundStyle(WorkflowStatus.approved.tint)
                } else {
                    Text("BEFORE SIGN-OFF").font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint)
                    ForEach(blockers, id: \.self) { reason in
                        Label(reason, systemImage: "xmark.octagon").font(.callout).foregroundStyle(IssueSeverity.blocker.tint)
                    }
                }
                TextField("Sign-off statement, e.g. Approved for filing with the annual report", text: $statement, axis: .vertical)
                    .lineLimit(2...3).textFieldStyle(.roundedBorder).frame(maxWidth: 560)
                Button {
                    store.signOff(id: engagement.id, statement: statement)
                    statement = ""
                } label: {
                    Label("Sign Off Engagement", systemImage: "signature")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(!blockers.isEmpty)
            }
        }
    }

    // MARK: Audit

    private var auditCard: some View {
        let query = auditSearch.trimmingCharacters(in: .whitespaces).lowercased()
        let events = engagement.activity.reversed().filter { event in
            query.isEmpty || (event.user + " " + event.action + " " + event.target + " " + event.detail).lowercased().contains(query)
        }
        return DSCard("Audit Trail",
                      subtitle: "Every edit, submission, approval and sign-off, newest first. Repeated edits of one field within two minutes are merged.") {
            DSSearchField(text: $auditSearch, prompt: "Search by person, action or KPI").frame(width: 260)
        } content: {
            if events.isEmpty {
                Text("No activity matches.").font(.callout).foregroundStyle(DSStyle.subtle)
            }
            LazyVStack(spacing: 2) {
                ForEach(Array(events.prefix(400))) { event in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(DisclosureFormat.dateTime(event.date)).font(.caption.monospacedDigit()).foregroundStyle(DSStyle.faint)
                            .frame(width: 130, alignment: .leading)
                        Text(event.user).font(.caption.weight(.semibold)).frame(width: 120, alignment: .leading).lineLimit(1)
                        Text(event.action).font(.caption).frame(width: 170, alignment: .leading).lineLimit(1)
                        Text([event.target, event.detail].filter { !$0.isEmpty }.joined(separator: " · "))
                            .font(.caption).foregroundStyle(DSStyle.subtle).lineLimit(2)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 3)
                }
            }
            if events.count > 400 {
                Text("Showing the latest 400 of \(events.count). Export the full trail from Reports.").font(.caption).foregroundStyle(DSStyle.faint)
            }
        }
    }
}

private struct QueueRow: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let item: ReviewView.QueueItem

    @EnvironmentObject private var router: DisclosureRouter
    @State private var comment = ""

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind == .metric ? "number" : "text.alignleft").foregroundStyle(DSStyle.subtle).frame(width: 18)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Button(item.title) {
                        if item.kind == .metric { router.openMetric(item.id) } else { router.openNarrative(item.id) }
                    }
                    .buttonStyle(.link)
                    DSStatusPill(status: item.status)
                }
                Text(item.reference).font(.caption2).foregroundStyle(DSStyle.faint)
                Text(item.summary).font(.caption).foregroundStyle(DSStyle.subtle).lineLimit(3)
                if !item.updatedBy.isEmpty {
                    Text("Prepared by \(item.updatedBy)").font(.caption2).foregroundStyle(DSStyle.faint)
                }
            }
            Spacer(minLength: 8)
            if item.status == .readyForReview {
                VStack(alignment: .trailing, spacing: 6) {
                    TextField("Comment", text: $comment).textFieldStyle(.roundedBorder).frame(width: 220)
                    HStack(spacing: 6) {
                        Button("Request Changes") { apply(.requestChanges) }
                            .disabled(comment.trimmingCharacters(in: .whitespaces).isEmpty)
                        Button("Approve") { apply(.approve) }
                            .buttonStyle(.borderedProminent)
                    }
                    .controlSize(.small)
                }
                .disabled(engagement.isLocked)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }

    private func apply(_ action: ReviewAction) {
        let done: Bool
        switch item.kind {
        case .metric: done = store.review(action, metric: item.id, in: engagement.id, comment: comment)
        case .narrative: done = store.review(action, narrative: item.id, in: engagement.id, comment: comment)
        }
        if done { comment = "" }
    }
}
