import SwiftUI
import UniformTypeIdentifiers

/// Editor for one KPI: value, comparatives, source, method, evidence, review.
struct MetricEditorView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let definition: MetricDefinition
    let values: MetricResolver
    let ghgTotals: [GHGInventoryTotals]
    let accent: Color
    let openGHGAccounting: () -> Void
    let select: (String) -> Void

    @State private var reviewComment = ""
    @State private var newComment = ""

    private var entry: MetricEntry { engagement.metric(definition.id) }
    private var locked: Bool { engagement.isLocked }
    private var unitLabel: String { definition.unit == "count" ? "" : definition.unit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                header
                if definition.isCalculated {
                    calculatedSection
                } else {
                    valueSection
                    if isEmissionMetric { ghgSection }
                    provenanceSection
                    evidenceSection
                    reviewSection
                }
            }
            .padding(16)
        }
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DSStyle.panel))
    }

    private func update(_ change: (inout MetricEntry) -> Void) {
        store.updateMetric(definition.id, in: engagement.id, change)
    }

    private var isEmissionMetric: Bool {
        [MetricID.scope1, MetricID.scope2, MetricID.scope3].contains(definition.id)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(definition.title).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 4) {
                if let core = definition.core { DSTag(text: "Core \(core.rawValue) · \(core.title)", color: DisclosureFramework.brsrCore.tint) }
                if let brsr = definition.brsr {
                    DSTag(text: brsr.reference + (brsr.level == .leadership ? " (voluntary)" : ""), color: DisclosureFramework.brsr.tint)
                }
                if let ifrs = definition.ifrs { DSTag(text: ifrs.reference, color: DisclosureFramework.ifrsS2.tint) }
            }
            Text(definition.guidance).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
            if entry.origin != .manual && !entry.originNote.isEmpty {
                Label("\(entry.origin.title): \(entry.originNote)", systemImage: "arrow.down.doc")
                    .font(.caption)
                    .foregroundStyle(accent)
            }
        }
    }

    // MARK: Calculated

    private var calculatedSection: some View {
        let resolved = values[definition.id]
        return VStack(alignment: .leading, spacing: 12) {
            Label("Calculated by the app", systemImage: "function").font(.callout.weight(.semibold))
            if let derivation = definition.derivation {
                Text(MetricResolver.describe(derivation)).font(.caption).foregroundStyle(DSStyle.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                DSMetricTile(title: engagement.periodLabel, value: DisclosureFormat.value(resolved.current, unit: ""), detail: unitLabel)
                DSMetricTile(title: engagement.priorPeriodLabel, value: DisclosureFormat.value(resolved.prior, unit: ""), detail: unitLabel)
            }
            if resolved.isPartial {
                Label("Some inputs are missing, so this total is incomplete.", systemImage: "circle.dotted")
                    .font(.caption).foregroundStyle(IssueSeverity.warning.tint)
            }
            if let derivation = definition.derivation {
                Text("Inputs").font(.caption.weight(.semibold)).foregroundStyle(DSStyle.faint)
                ForEach(derivation.inputs, id: \.self) { id in
                    if let input = MetricCatalog.metric(id) {
                        Button {
                            select(id)
                        } label: {
                            HStack {
                                Text(input.title).font(.caption)
                                Spacer()
                                Text(DisclosureFormat.value(values[id].current, unit: input.unit == "count" ? "" : input.unit))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(values[id].current == nil ? IssueSeverity.warning.tint : DSStyle.subtle)
                                Image(systemName: "chevron.right").font(.caption2).foregroundStyle(DSStyle.faint)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    // MARK: Value

    private var valueSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Value")
            if definition.isText {
                TextField("Answer", text: Binding(get: { entry.text }, set: { value in update { $0.text = value } }), axis: .vertical)
                    .lineLimit(1...4)
                    .textFieldStyle(.roundedBorder)
                    .disabled(locked)
            } else {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                    DSFormRow(engagement.periodLabel, width: 92) {
                        HStack(spacing: 6) {
                            DSNumberField(placeholder: "Value", value: entry.current,
                                          onCommit: { value in update { $0.current = value } }, width: 150,
                                          isDisabled: locked || entry.notApplicable)
                            Text(unitLabel).font(.caption).foregroundStyle(DSStyle.subtle)
                        }
                    }
                    DSFormRow(engagement.priorPeriodLabel, width: 92) {
                        HStack(spacing: 6) {
                            DSNumberField(placeholder: "Prior year", value: entry.prior,
                                          onCommit: { value in update { $0.prior = value } }, width: 150,
                                          isDisabled: locked || entry.notApplicable)
                            if let change = DisclosureFormat.change(current: entry.current, prior: entry.prior) {
                                Text(change).font(.caption.monospacedDigit()).foregroundStyle(DSStyle.subtle)
                            }
                        }
                    }
                }
            }
            Toggle("Not applicable", isOn: Binding(get: { entry.notApplicable }, set: { value in update { $0.notApplicable = value } }))
                .disabled(locked)
            if entry.notApplicable {
                TextField("Reason (required)", text: Binding(get: { entry.notApplicableReason },
                                                             set: { value in update { $0.notApplicableReason = value } }))
                    .textFieldStyle(.roundedBorder)
                    .disabled(locked)
            }
            if let ratio = DisclosureFormat.changeRatio(current: entry.current, prior: entry.prior),
               abs(ratio) > DataQualityChecks.varianceThreshold {
                VStack(alignment: .leading, spacing: 4) {
                    Label("Moved more than \(DisclosureFormat.percent(DataQualityChecks.varianceThreshold)) from last year: explain why.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(entry.varianceExplanation.isEmpty ? IssueSeverity.warning.tint : DSStyle.subtle)
                    TextField("Reason for the change", text: Binding(get: { entry.varianceExplanation },
                                                                    set: { value in update { $0.varianceExplanation = value } }),
                              axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                        .disabled(locked)
                }
            }
        }
    }

    // MARK: GHG

    private var scopeNumber: Int {
        switch definition.id {
        case MetricID.scope1: return 1
        case MetricID.scope2: return 2
        default: return 3
        }
    }

    private var ghgSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Emissions Calculation")
            Text("Already have the figure? Enter it above. Need to calculate it? Use the GHG Accounting tools, then import the total here.")
                .font(.caption)
                .foregroundStyle(DSStyle.subtle)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                Button {
                    openGHGAccounting()
                } label: {
                    Label("Calculate in GHG Accounting", systemImage: "function")
                }
                .help("Opens the GHG Accounting workspace with the emission-factor calculator")
                Menu {
                    if ghgTotals.isEmpty {
                        Text("No GHG inventories yet")
                    }
                    ForEach(ghgTotals) { totals in
                        let value = scopeNumber == 1 ? totals.scope1 : scopeNumber == 2 ? totals.scope2 : totals.scope3
                        Button("\(totals.name): \(DisclosureFormat.value(value, unit: "tCO2e"))\(totals.isUnsaved ? " (not saved)" : "")") {
                            store.importGHG(totals, scopes: [scopeNumber], into: engagement.id)
                        }
                    }
                    if !ghgTotals.isEmpty {
                        Divider()
                        Menu("Import Scope 1, 2 and 3 Together") {
                            ForEach(ghgTotals) { totals in
                                Button(totals.name) { store.importGHG(totals, scopes: [1, 2, 3], into: engagement.id) }
                            }
                        }
                    }
                } label: {
                    Label("Import from Inventory", systemImage: "square.and.arrow.down")
                }
                .fixedSize()
                .disabled(locked)
            }
        }
    }

    // MARK: Provenance

    private var provenanceSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Source and Method")
            TextField("Source: system or document (e.g. DISCOM bills, payroll register)",
                      text: Binding(get: { entry.source }, set: { value in update { $0.source = value } }))
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
            TextField("Method: calculation, emission factors, assumptions", text: Binding(get: { entry.method }, set: { value in update { $0.method = value } }),
                      axis: .vertical)
                .lineLimit(2...5)
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
            TextField("Owner: person or team responsible", text: Binding(get: { entry.owner }, set: { value in update { $0.owner = value } }))
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
        }
    }

    // MARK: Evidence

    private var evidenceSection: some View {
        let linked = entry.evidenceIDs.compactMap(engagement.evidenceItem)
        let available = engagement.evidence.filter { !entry.evidenceIDs.contains($0.id) }
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Evidence")
                Spacer()
                Menu {
                    Button("Add File…") { addFile() }
                    if !available.isEmpty {
                        Divider()
                        ForEach(available) { item in
                            Button(item.title) {
                                store.linkEvidence(item.id, metric: definition.id, linked: true, in: engagement.id)
                            }
                        }
                    }
                } label: {
                    Label("Link", systemImage: "paperclip")
                }
                .fixedSize()
                .disabled(locked)
            }
            if linked.isEmpty {
                Text(definition.core != nil ? "No evidence yet. Assurers ask for source documents for every BRSR Core value."
                                            : "No evidence linked.")
                    .font(.caption)
                    .foregroundStyle(definition.core != nil && entry.hasValue ? IssueSeverity.warning.tint : DSStyle.subtle)
            }
            ForEach(linked) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.kind.systemImage).foregroundStyle(DSStyle.subtle)
                    Text(item.title).font(.caption).lineLimit(1)
                    if item.verified { Image(systemName: "checkmark.seal.fill").font(.caption).foregroundStyle(WorkflowStatus.approved.tint) }
                    Spacer()
                    if !item.location.isEmpty {
                        Button { EvidenceView.open(item) } label: { Image(systemName: "arrow.up.forward.square") }
                            .buttonStyle(.borderless)
                            .help("Open")
                    }
                    Button { store.linkEvidence(item.id, metric: definition.id, linked: false, in: engagement.id) } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .disabled(locked)
                    .help("Unlink")
                }
            }
        }
    }

    private func addFile() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.message = "Choose the source document for \(definition.title)."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        var item = EvidenceItem(title: url.lastPathComponent, kind: .other, location: url.path)
        item.period = engagement.periodLabel
        store.addEvidence(item, linkTo: [definition.id], in: engagement.id)
    }

    // MARK: Review

    private var reviewSection: some View {
        let actions = WorkflowEngine.actions(from: entry.status)
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                sectionTitle("Review")
                Spacer()
                DSStatusPill(status: entry.status)
            }
            if entry.status == .approved, !entry.approvedBy.isEmpty {
                Text("Approved by \(entry.approvedBy)\(entry.approvedAt.map { ", \(DisclosureFormat.dateTime($0))" } ?? "")")
                    .font(.caption).foregroundStyle(DSStyle.subtle)
            }
            if actions.contains(.approve) || actions.contains(.requestChanges) {
                TextField("Comment for the preparer (needed to request changes)", text: $reviewComment, axis: .vertical)
                    .lineLimit(1...3)
                    .textFieldStyle(.roundedBorder)
                if entry.updatedBy.caseInsensitiveCompare(store.userName) == .orderedSame {
                    Label("You last edited this value; assurers prefer a different reviewer.", systemImage: "person.2.slash")
                        .font(.caption)
                        .foregroundStyle(IssueSeverity.info.tint)
                }
            }
            HStack(spacing: 8) {
                ForEach(actions, id: \.self) { action in
                    Button {
                        if store.review(action, metric: definition.id, in: engagement.id, comment: reviewComment) {
                            reviewComment = ""
                        }
                    } label: {
                        Label(action.title, systemImage: action.systemImage)
                    }
                    .disabled(locked || !WorkflowEngine.canApply(action, status: entry.status, isAnswered: entry.isAnswered)
                              || (action == .requestChanges && reviewComment.trimmingCharacters(in: .whitespaces).isEmpty))
                    .help(action == .submit && !entry.isAnswered ? "Enter a value, or mark not applicable with a reason, first" : action.title)
                }
            }
            .controlSize(.small)
            commentsList
        }
    }

    private var commentsList: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(entry.comments.reversed())) { comment in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text(comment.author).font(.caption.weight(.semibold))
                        Text(DisclosureFormat.dateTime(comment.date)).font(.caption2).foregroundStyle(DSStyle.faint)
                        if comment.kind == .changeRequest { DSTag(text: "Changes requested", color: WorkflowStatus.changesRequested.tint) }
                        if comment.kind == .approval { DSTag(text: "Approved", color: WorkflowStatus.approved.tint) }
                    }
                    Text(comment.text).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DSStyle.rowFill))
            }
            HStack {
                TextField("Add a comment", text: $newComment)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(postComment)
                Button("Post", action: postComment)
                    .disabled(newComment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .disabled(locked)
        }
    }

    private func postComment() {
        store.addComment(newComment, metric: definition.id, in: engagement.id)
        newComment = ""
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint)
    }
}
