import SwiftUI

/// IFRS S2 core content and BRSR qualitative disclosures, each with a checklist of
/// what it must cover and the KPIs a reader expects beside it.
struct NarrativesView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let accent: Color

    @EnvironmentObject private var router: DisclosureRouter
    @State private var selectedID: String?

    private var requirements: [NarrativeRequirement] {
        NarrativeCatalog.inScope(engagement.frameworks)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            list.frame(width: 320)
            editor.frame(maxWidth: .infinity)
        }
        .onAppear(perform: applyFocus)
        .onChange(of: router.focusNarrativeID) { _, _ in applyFocus() }
    }

    private func applyFocus() {
        if let focus = router.focusNarrativeID {
            selectedID = focus
            router.focusNarrativeID = nil
        }
        if selectedID == nil { selectedID = requirements.first?.id }
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if requirements.isEmpty {
                    Text("Add BRSR or IFRS S2 to the scope to see its narratives.").font(.callout).foregroundStyle(DSStyle.subtle)
                }
                ForEach(NarrativePillar.allCases) { pillar in
                    let items = requirements.filter { $0.pillar == pillar }
                    if !items.isEmpty {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(items.first?.framework.title ?? "") · \(pillar.title)".uppercased())
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(DSStyle.faint)
                                .padding(.leading, 6)
                            ForEach(items) { requirement in listRow(requirement) }
                        }
                    }
                }
            }
            .padding(12)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DSStyle.panel))
    }

    private func listRow(_ requirement: NarrativeRequirement) -> some View {
        let entry = engagement.narrative(requirement.id)
        let isSelected = selectedID == requirement.id
        return Button {
            selectedID = requirement.id
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: entry.status.systemImage).foregroundStyle(entry.status.tint).frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text(requirement.title).font(.callout).lineLimit(2).multilineTextAlignment(.leading)
                    HStack(spacing: 6) {
                        Text(requirement.reference).font(.caption2).foregroundStyle(DSStyle.faint)
                        if !requirement.required { Text("optional").font(.caption2).foregroundStyle(DSStyle.faint) }
                        if entry.hasText { Text("\(entry.wordCount) words").font(.caption2).foregroundStyle(DSStyle.faint) }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? DSStyle.rowSelected : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: Editor

    @ViewBuilder
    private var editor: some View {
        if let selectedID, let requirement = NarrativeCatalog.requirement(selectedID) {
            NarrativeEditor(store: store, engagement: engagement, requirement: requirement, accent: accent)
                .id(selectedID)
        } else {
            DSCard("Select a narrative") {
                Text("Choose a disclosure on the left.").foregroundStyle(DSStyle.subtle)
            }
        }
    }
}

private struct NarrativeEditor: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let requirement: NarrativeRequirement
    let accent: Color

    @EnvironmentObject private var router: DisclosureRouter
    @State private var reviewComment = ""
    @State private var newComment = ""

    private var entry: NarrativeEntry { engagement.narrative(requirement.id) }
    private var locked: Bool { engagement.isLocked }

    private func update(_ change: (inout NarrativeEntry) -> Void) {
        store.updateNarrative(requirement.id, in: engagement.id, change)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(requirement.title).font(.title3.weight(.semibold))
                        Spacer()
                        DSStatusPill(status: entry.status)
                    }
                    HStack(spacing: 6) {
                        DSTag(text: requirement.reference, color: requirement.framework.tint)
                        if !requirement.required { DSTag(text: "Optional") }
                    }
                    Text(requirement.guidance).font(.callout).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
                }
                HStack(alignment: .top, spacing: 14) {
                    textArea.frame(maxWidth: .infinity)
                    checklist.frame(width: 280)
                }
                reviewBar
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DSStyle.panel))
    }

    private var textArea: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: Binding(get: { entry.text }, set: { value in update { $0.text = value } }))
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .frame(minHeight: 260)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.black.opacity(0.25)))
                .disabled(locked || entry.notApplicable)
            HStack(spacing: 10) {
                Text("\(entry.wordCount) words").font(.caption.monospacedDigit()).foregroundStyle(DSStyle.subtle)
                Spacer()
                if requirement.id == "s2.str.risks" && !engagement.issues.isEmpty {
                    Button("Draft from Register") { appendText(Self.registerDraft(engagement)) }
                        .help("Adds a description of each climate-related risk and opportunity in the register")
                }
                if !requirement.linkedMetrics.isEmpty {
                    Button("Insert Figures") { appendText(figuresSentence) }
                        .help("Adds the linked KPI values as a sentence")
                }
            }
            .controlSize(.small)
            .disabled(locked)
            Toggle("Not applicable", isOn: Binding(get: { entry.notApplicable }, set: { value in update { $0.notApplicable = value } }))
                .disabled(locked)
            if entry.notApplicable {
                TextField("Reason (required)", text: Binding(get: { entry.notApplicableReason },
                                                             set: { value in update { $0.notApplicableReason = value } }))
                    .textFieldStyle(.roundedBorder)
                    .disabled(locked)
            }
            TextField("Owner", text: Binding(get: { entry.owner }, set: { value in update { $0.owner = value } }))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 280)
                .disabled(locked)
        }
    }

    private func appendText(_ text: String) {
        guard !text.isEmpty else { return }
        update { entry in
            entry.text = entry.text.isEmpty ? text : entry.text + "\n\n" + text
        }
    }

    private var figuresSentence: String {
        let values = MetricResolver(engagement)
        let parts = requirement.linkedMetrics.compactMap { id -> String? in
            guard let definition = MetricCatalog.metric(id) else { return nil }
            let unit = definition.unit == "count" ? "" : definition.unit
            if definition.isText {
                let text = engagement.metric(id).text
                return text.isEmpty ? nil : "\(definition.title): \(text)"
            }
            guard let current = values[id].current else { return nil }
            var part = "\(definition.title): \(DisclosureFormat.value(current, unit: unit))"
            if let prior = values[id].prior {
                part += " (\(engagement.priorPeriodLabel): \(DisclosureFormat.value(prior, unit: unit)))"
            }
            return part
        }
        return parts.isEmpty ? "" : "In \(engagement.periodLabel): " + parts.joined(separator: "; ") + "."
    }

    static func registerDraft(_ engagement: DisclosureEngagement) -> String {
        ReportBuilder.sortedIssues(engagement.issues.filter { $0.topic.isClimate }).map { issue in
            var text = "\(issue.title) (\(issue.type.title.lowercased()), \(issue.topic.title.lowercased()), \(issue.horizon.title.lowercased())). \(issue.rationale)"
            if !issue.approach.isEmpty { text += " Response: \(issue.approach)" }
            return text
        }.joined(separator: "\n\n")
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("SHOULD COVER").font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint)
            ForEach(Array(requirement.elements.enumerated()), id: \.offset) { index, element in
                Toggle(isOn: Binding(get: { entry.coveredElements.contains(index) },
                                     set: { value in update { entry in
                                         if value { _ = entry.coveredElements.insert(index) } else { _ = entry.coveredElements.remove(index) }
                                     } })) {
                    Text(element).font(.caption).fixedSize(horizontal: false, vertical: true)
                }
                .toggleStyle(.checkbox)
                .disabled(locked)
            }
            Text("\(entry.coveredElements.count) of \(requirement.elements.count) covered")
                .font(.caption.monospacedDigit())
                .foregroundStyle(entry.coveredElements.count == requirement.elements.count ? WorkflowStatus.approved.tint : DSStyle.subtle)
            if !requirement.linkedMetrics.isEmpty {
                Divider()
                Text("RELATED KPIs").font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint)
                ForEach(requirement.linkedMetrics, id: \.self) { id in
                    if let definition = MetricCatalog.metric(id) {
                        Button { router.openMetric(id) } label: {
                            HStack {
                                Text(definition.title).font(.caption).lineLimit(1)
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(DSStyle.faint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(DSStyle.rowFill))
    }

    private var reviewBar: some View {
        let actions = WorkflowEngine.actions(from: entry.status)
        return VStack(alignment: .leading, spacing: 8) {
            if actions.contains(.approve) || actions.contains(.requestChanges) {
                TextField("Comment for the author (needed to request changes)", text: $reviewComment, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
            }
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    Button {
                        if store.review(action, narrative: requirement.id, in: engagement.id, comment: reviewComment) { reviewComment = "" }
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .disabled(locked || !WorkflowEngine.canApply(action, status: entry.status, isAnswered: entry.isAnswered)
                              || (action == .requestChanges && reviewComment.trimmingCharacters(in: .whitespaces).isEmpty))
                }
                Spacer()
                if entry.status == .approved, !entry.approvedBy.isEmpty {
                    Text("Approved by \(entry.approvedBy)").font(.caption).foregroundStyle(DSStyle.subtle)
                }
            }
            .controlSize(.small)
            ForEach(Array(entry.comments.reversed())) { comment in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(comment.author).font(.caption.weight(.semibold))
                    Text(comment.text).font(.caption).foregroundStyle(DSStyle.subtle)
                    Spacer()
                    Text(DisclosureFormat.dateTime(comment.date)).font(.caption2).foregroundStyle(DSStyle.faint)
                }
            }
            HStack {
                TextField("Add a comment", text: $newComment).textFieldStyle(.roundedBorder)
                Button("Post") {
                    store.addComment(newComment, narrative: requirement.id, in: engagement.id)
                    newComment = ""
                }
                .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(locked)
        }
    }
}
