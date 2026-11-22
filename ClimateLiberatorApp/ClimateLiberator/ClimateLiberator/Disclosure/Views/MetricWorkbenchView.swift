import SwiftUI
import UniformTypeIdentifiers

/// KPI data collection: every metric in scope with values, status and evidence, an
/// editor for the selected one, and the data-request round trip.
struct MetricWorkbenchView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let ghgTotals: [GHGInventoryTotals]
    let accent: Color
    let openGHGAccounting: () -> Void

    @EnvironmentObject private var router: DisclosureRouter
    @State private var group: MetricGroup?
    @State private var selectedID: String?
    @State private var search = ""
    @State private var filter: Filter = .inScope
    @State private var importMessage: String?

    enum Filter: String, CaseIterable, Identifiable {
        case inScope, required, core, missing, noEvidence, review
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inScope: return "All in scope"
            case .required: return "Required"
            case .core: return "BRSR Core"
            case .missing: return "Missing"
            case .noEvidence: return "No evidence"
            case .review: return "In review"
            }
        }
    }

    var body: some View {
        let values = MetricResolver(engagement)
        let groups = visibleGroups
        let rows = filteredDefinitions(groups: groups)
        VStack(alignment: .leading, spacing: 12) {
            toolbar
            groupChips(groups)
            HStack(alignment: .top, spacing: 14) {
                list(rows, values: values)
                    .frame(minWidth: 400, maxWidth: .infinity)
                editorPanel(values: values)
                    .frame(width: 390)
            }
        }
        .onAppear(perform: applyFocus)
        .onChange(of: router.focusMetricID) { _, _ in applyFocus() }
        .alert("Data Request Imported", isPresented: Binding(get: { importMessage != nil }, set: { if !$0 { importMessage = nil } })) {
            Button("OK") { importMessage = nil }
        } message: {
            Text(importMessage ?? "")
        }
    }

    private func applyFocus() {
        if let focus = router.focusMetricID {
            selectedID = focus
            group = MetricCatalog.metric(focus)?.group
            search = ""
            router.focusMetricID = nil
        } else if let focusGroup = router.focusGroup {
            group = focusGroup
            router.focusGroup = nil
        }
        if group == nil { group = visibleGroups.first }
        if selectedID == nil, let group {
            selectedID = MetricCatalog.metrics(in: group).first { !$0.isCalculated }?.id
        }
    }

    // MARK: Filtering

    private var visibleGroups: [MetricGroup] {
        let scope = engagement.frameworks
        return MetricGroup.allCases.filter { group in
            MetricCatalog.metrics(in: group).contains { scope.isEmpty || $0.isUsed(in: scope) }
        }
    }

    private func filteredDefinitions(groups: [MetricGroup]) -> [MetricDefinition] {
        let scope = engagement.frameworks
        let required = Set(MetricCatalog.requiredInputs(for: scope).map(\.id))
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return MetricCatalog.all.filter { definition in
            guard scope.isEmpty || definition.isUsed(in: scope) || required.contains(definition.id) else { return false }
            if query.isEmpty {
                guard definition.group == group else { return false }
            } else {
                let haystack = (definition.title + " " + definition.id + " " + definition.referenceLine).lowercased()
                guard haystack.contains(query) else { return false }
            }
            let entry = engagement.metric(definition.id)
            switch filter {
            case .inScope: return true
            case .required: return definition.isRequired(in: scope) || required.contains(definition.id)
            case .core: return definition.core != nil
            case .missing: return !definition.isCalculated && required.contains(definition.id) && !entry.isAnswered
            case .noEvidence: return !definition.isCalculated && definition.core != nil && entry.hasValue && entry.evidenceIDs.isEmpty
            case .review: return entry.status == .readyForReview || entry.status == .changesRequested
            }
        }
    }

    // MARK: Toolbar

    private var toolbar: some View {
        HStack(spacing: 10) {
            DSSearchField(text: $search, prompt: "Search all KPIs, e.g. scope 2, LTIFR, P6")
                .frame(maxWidth: 340)
            Picker("Show", selection: $filter) {
                ForEach(Filter.allCases) { Text($0.title).tag($0) }
            }
            .frame(width: 210)
            Spacer()
            Menu {
                Button("Export Data Request Template…") {
                    if let url = store.exportDataRequest(id: engagement.id) {
                        NSWorkspace.shared.activateFileViewerSelecting([url])
                    }
                }
                Button("Import Filled Data Request…") { importDataRequest() }
                    .disabled(engagement.isLocked)
            } label: {
                Label("Data Request", systemImage: "arrow.up.arrow.down.square")
            }
            .fixedSize()
            .help("Send a CSV of the KPIs to plant, HR and finance teams, then import their answers")
        }
    }

    private func importDataRequest() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.commaSeparatedText, .plainText]
        panel.message = "Choose the filled data-request CSV."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            let text = try String(contentsOf: url, encoding: .utf8)
            let result = DataRequest.parse(text)
            let summary = store.applyDataRequest(result, to: engagement.id, fileName: url.lastPathComponent)
            let skipped = result.skipped.prefix(8).joined(separator: "\n")
            importMessage = summary + (skipped.isEmpty ? "" : "\n\n" + skipped + (result.skipped.count > 8 ? "\n…" : ""))
        } catch {
            importMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    private func groupChips(_ groups: [MetricGroup]) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(groups) { item in
                    let progress = ReadinessAnalyzer.groupProgress(item, in: engagement)
                    let isSelected = item == group && search.isEmpty
                    Button {
                        group = item
                        search = ""
                        selectedID = MetricCatalog.metrics(in: item).first { !$0.isCalculated }?.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: item.systemImage)
                            Text(item.title)
                            if progress.total > 0 {
                                Text("\(progress.answered)/\(progress.total)")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(progress.answered == progress.total ? WorkflowStatus.approved.tint : DSStyle.subtle)
                            }
                        }
                        .font(.caption.weight(.medium))
                        .padding(.vertical, 6)
                        .padding(.horizontal, 10)
                        .background(Capsule().fill(isSelected ? accent.opacity(0.35) : DSStyle.panel))
                        .overlay(Capsule().stroke(isSelected ? accent.opacity(0.8) : DSStyle.panelStroke, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: List

    private func list(_ rows: [MetricDefinition], values: MetricResolver) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("KPI").frame(maxWidth: .infinity, alignment: .leading)
                Text(engagement.periodLabel).frame(width: 110, alignment: .trailing)
                Text(engagement.priorPeriodLabel).frame(width: 100, alignment: .trailing)
                Text("Change").frame(width: 56, alignment: .trailing)
                Text("").frame(width: 46)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(DSStyle.faint)
            .padding(.horizontal, 10)
            .padding(.bottom, 6)
            if rows.isEmpty {
                Text(search.isEmpty ? "Nothing matches this filter." : "No KPI matches “\(search)”.")
                    .font(.callout)
                    .foregroundStyle(DSStyle.subtle)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(30)
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(rows) { definition in
                        row(definition, values: values)
                    }
                }
                .padding(.bottom, 10)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DSStyle.panel))
    }

    private func row(_ definition: MetricDefinition, values: MetricResolver) -> some View {
        let entry = engagement.metric(definition.id)
        let resolved = values[definition.id]
        let isSelected = selectedID == definition.id
        let unit = definition.unit == "count" ? "" : definition.unit
        return Button {
            selectedID = definition.id
        } label: {
            HStack(spacing: 8) {
                if definition.isCalculated {
                    Image(systemName: "function").foregroundStyle(DSStyle.faint).frame(width: 16)
                } else {
                    Image(systemName: entry.status.systemImage).foregroundStyle(entry.status.tint).frame(width: 16)
                }
                VStack(alignment: .leading, spacing: 2) {
                    Text(definition.title).font(.callout).lineLimit(1)
                    HStack(spacing: 4) {
                        if let core = definition.core { DSTag(text: "Core \(core.rawValue)", color: DisclosureFramework.brsrCore.tint) }
                        if let brsr = definition.brsr { DSTag(text: brsr.reference, color: DisclosureFramework.brsr.tint) }
                        if let ifrs = definition.ifrs { DSTag(text: "S2 \(ifrs.paragraph)", color: DisclosureFramework.ifrsS2.tint) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(Self.currentText(definition, entry: entry, value: resolved.current, unit: unit))
                    .font(.callout.monospacedDigit())
                    .lineLimit(1)
                    .frame(width: 110, alignment: .trailing)
                Text(definition.isText ? "" : DisclosureFormat.value(resolved.prior, unit: unit))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DSStyle.subtle)
                    .lineLimit(1)
                    .frame(width: 100, alignment: .trailing)
                Text(DisclosureFormat.change(current: resolved.current, prior: resolved.prior) ?? "")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DSStyle.subtle)
                    .frame(width: 56, alignment: .trailing)
                HStack(spacing: 3) {
                    if !entry.evidenceIDs.isEmpty {
                        Image(systemName: "paperclip").help("\(entry.evidenceIDs.count) evidence item(s)")
                    }
                    if !entry.comments.isEmpty {
                        Image(systemName: "text.bubble").help("\(entry.comments.count) comment(s)")
                    }
                    if resolved.isPartial {
                        Image(systemName: "circle.dotted").foregroundStyle(IssueSeverity.warning.tint).help("Some inputs are missing")
                    }
                }
                .font(.caption)
                .foregroundStyle(DSStyle.subtle)
                .frame(width: 46, alignment: .trailing)
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 8)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? DSStyle.rowSelected : DSStyle.rowFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private static func currentText(_ definition: MetricDefinition, entry: MetricEntry, value: Double?, unit: String) -> String {
        if definition.isText { return entry.text.isEmpty ? "—" : entry.text }
        if entry.notApplicable && !definition.isCalculated { return "N/A" }
        return DisclosureFormat.value(value, unit: unit)
    }

    // MARK: Editor

    @ViewBuilder
    private func editorPanel(values: MetricResolver) -> some View {
        if let selectedID, let definition = MetricCatalog.metric(selectedID) {
            MetricEditorView(store: store, engagement: engagement, definition: definition, values: values,
                             ghgTotals: ghgTotals, accent: accent, openGHGAccounting: openGHGAccounting,
                             select: { self.selectedID = $0 })
                .id(selectedID)
        } else {
            DSCard("Select a KPI") {
                Text("Choose a KPI on the left to enter its value, source, method and evidence.")
                    .font(.callout)
                    .foregroundStyle(DSStyle.subtle)
            }
        }
    }
}
