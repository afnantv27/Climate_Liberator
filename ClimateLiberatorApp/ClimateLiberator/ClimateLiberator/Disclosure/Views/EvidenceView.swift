import SwiftUI
import UniformTypeIdentifiers

/// Evidence register: source documents behind each value, which KPIs they support,
/// and who verified them. Assurers sample from this list.
struct EvidenceView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let candidates: [SimulationEvidenceCandidate]
    let accent: Color

    @State private var search = ""
    @State private var kindFilter: EvidenceKind?
    @State private var editing: EvidenceItem?

    private var locked: Bool { engagement.isLocked }

    /// KPIs each evidence item supports.
    private var linkedMetrics: [UUID: [MetricDefinition]] {
        var map: [UUID: [MetricDefinition]] = [:]
        for (metricID, entry) in engagement.metrics {
            guard let definition = MetricCatalog.metric(metricID) else { continue }
            for evidenceID in entry.evidenceIDs { map[evidenceID, default: []].append(definition) }
        }
        return map.mapValues { $0.sorted { MetricCatalog.position(of: $0.id) < MetricCatalog.position(of: $1.id) } }
    }

    private var items: [EvidenceItem] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return engagement.evidence
            .filter { kindFilter == nil || $0.kind == kindFilter }
            .filter { query.isEmpty || ($0.title + " " + $0.notes + " " + $0.location).lowercased().contains(query) }
            .sorted { $0.addedAt > $1.addedAt }
    }

    var body: some View {
        let links = linkedMetrics
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                summary(links)
                registerCard(links)
                if !candidates.isEmpty { simulationCard }
            }
            .padding(.bottom, 16)
        }
        .sheet(item: $editing) { item in
            EvidenceEditorSheet(item: item, accent: accent) { saved in
                if engagement.evidenceItem(saved.id) == nil {
                    store.addEvidence(saved, in: engagement.id)
                } else {
                    store.updateEvidence(saved, in: engagement.id)
                }
            }
        }
    }

    // MARK: Summary

    private func summary(_ links: [UUID: [MetricDefinition]]) -> some View {
        let coreWithValue = MetricCatalog.all.filter { $0.core != nil && !$0.isCalculated && engagement.metric($0.id).hasValue }
        let coreBacked = coreWithValue.filter { !engagement.metric($0.id).evidenceIDs.isEmpty }
        let verified = engagement.evidence.filter(\.verified).count
        let unused = engagement.evidence.filter { (links[$0.id] ?? []).isEmpty }.count
        return HStack(spacing: 12) {
            DSMetricTile(title: "Evidence items", value: "\(engagement.evidence.count)", systemImage: "paperclip")
            DSMetricTile(title: "Verified", value: "\(verified)",
                         detail: engagement.evidence.isEmpty ? "" : DisclosureFormat.percent(Double(verified) / Double(engagement.evidence.count)),
                         systemImage: "checkmark.seal")
            DSMetricTile(title: "BRSR Core values with evidence", value: "\(coreBacked.count) of \(coreWithValue.count)",
                         detail: "Assessors ask for every one", systemImage: "checkmark.shield")
            DSMetricTile(title: "Not linked to a KPI", value: "\(unused)", systemImage: "link.badge.plus")
        }
    }

    // MARK: Register

    private func registerCard(_ links: [UUID: [MetricDefinition]]) -> some View {
        DSCard("Evidence Register", subtitle: "Add the bill, register, certificate or workbook behind each value, then link it from KPI Data or here.") {
            HStack(spacing: 8) {
                Button { addFiles() } label: { Label("Add Files", systemImage: "doc.badge.plus") }
                Button { editing = EvidenceItem(title: "", kind: .other) } label: { Label("Add Link or Note", systemImage: "link") }
            }
            .disabled(locked)
        } content: {
            HStack(spacing: 8) {
                DSSearchField(text: $search, prompt: "Search evidence").frame(maxWidth: 280)
                Picker("Type", selection: $kindFilter) {
                    Text("All types").tag(EvidenceKind?.none)
                    ForEach(EvidenceKind.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .labelsHidden()
                .fixedSize()
                Spacer()
            }
            if items.isEmpty {
                Text(engagement.evidence.isEmpty ? "No evidence yet." : "Nothing matches.")
                    .font(.callout).foregroundStyle(DSStyle.subtle).padding(.vertical, 8)
            }
            VStack(spacing: 6) {
                ForEach(items) { item in row(item, metrics: links[item.id] ?? []) }
            }
        }
    }

    private func row(_ item: EvidenceItem, metrics: [MetricDefinition]) -> some View {
        let missingFile = !item.location.isEmpty && !item.isWebLink && !FileManager.default.fileExists(atPath: item.location)
        return HStack(alignment: .top, spacing: 10) {
            Image(systemName: item.kind.systemImage).foregroundStyle(DSStyle.subtle).frame(width: 20)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.title).font(.callout.weight(.medium)).lineLimit(1)
                    if item.verified {
                        DSTag(text: "Verified\(item.verifiedBy.isEmpty ? "" : " by \(item.verifiedBy)")", color: WorkflowStatus.approved.tint)
                    }
                    if missingFile { DSTag(text: "File not found", color: IssueSeverity.blocker.tint) }
                }
                Text([item.kind.title, item.period, item.addedBy.isEmpty ? "" : "added by \(item.addedBy)", DisclosureFormat.date(item.addedAt)]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(DSStyle.faint)
                if !item.notes.isEmpty {
                    Text(item.notes).font(.caption).foregroundStyle(DSStyle.subtle).lineLimit(2)
                }
                if metrics.isEmpty {
                    Text("Not linked to any KPI").font(.caption).foregroundStyle(IssueSeverity.info.tint)
                } else {
                    Text("Supports: " + metrics.map(\.title).joined(separator: ", "))
                        .font(.caption).foregroundStyle(DSStyle.subtle).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            linkMenu(item, linked: metrics)
            if !item.location.isEmpty {
                Button { Self.open(item) } label: { Image(systemName: "arrow.up.forward.square") }
                    .buttonStyle(.borderless).help("Open")
                    .disabled(missingFile)
            }
            Toggle("Verified", isOn: Binding(get: { item.verified }, set: { store.setEvidenceVerified(item.id, verified: $0, in: engagement.id) }))
                .toggleStyle(.checkbox)
                .disabled(locked)
                .help("Tick after checking the document matches the reported value")
            Button { editing = item } label: { Image(systemName: "pencil") }.buttonStyle(.borderless).disabled(locked)
            Button { store.removeEvidence(item.id, in: engagement.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless).disabled(locked).help("Remove from the register (the file itself is not deleted)")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }

    private func linkMenu(_ item: EvidenceItem, linked: [MetricDefinition]) -> some View {
        let scope = engagement.frameworks
        let linkedIDs = Set(linked.map(\.id))
        let groups = MetricGroup.allCases.filter { group in
            MetricCatalog.metrics(in: group).contains { !$0.isCalculated && (scope.isEmpty || $0.isUsed(in: scope)) }
        }
        return Menu {
            ForEach(groups) { group in
                Menu(group.title) {
                    ForEach(MetricCatalog.metrics(in: group).filter { !$0.isCalculated && (scope.isEmpty || $0.isUsed(in: scope)) }) { definition in
                        Toggle(definition.title, isOn: Binding(get: { linkedIDs.contains(definition.id) }, set: { value in
                            store.linkEvidence(item.id, metric: definition.id, linked: value, in: engagement.id)
                        }))
                    }
                }
            }
        } label: {
            Image(systemName: "link")
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .disabled(locked)
        .help("Link to KPIs")
    }

    private func addFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Choose source documents: bills, registers, certificates, workbooks."
        guard panel.runModal() == .OK else { return }
        for url in panel.urls {
            var item = EvidenceItem(title: url.lastPathComponent, kind: Self.guessKind(url), location: url.path)
            item.period = engagement.periodLabel
            store.addEvidence(item, in: engagement.id)
        }
    }

    static func guessKind(_ url: URL) -> EvidenceKind {
        let name = url.lastPathComponent.lowercased()
        if ["xlsx", "xls", "csv", "numbers"].contains(url.pathExtension.lowercased()) { return .calculation }
        if name.contains("invoice") || name.contains("bill") { return .invoice }
        if name.contains("certificate") || name.contains("iso") { return .certificate }
        if name.contains("policy") || name.contains("minutes") { return .policy }
        if name.contains("meter") || name.contains("log") { return .meterLog }
        if name.contains("register") || name.contains("payroll") || name.contains("hr") { return .register }
        return .other
    }

    /// Opens a file in its default app or a link in the browser.
    static func open(_ item: EvidenceItem) {
        if item.isWebLink, let url = URL(string: item.location) {
            NSWorkspace.shared.open(url)
        } else if !item.location.isEmpty {
            let url = URL(fileURLWithPath: item.location)
            if FileManager.default.fileExists(atPath: url.path) { NSWorkspace.shared.open(url) }
        }
    }

    // MARK: Simulation packages

    private var simulationCard: some View {
        let added = Set(engagement.evidence.map(\.externalReference))
        return DSCard("Wildfire Simulation Packages", subtitle: "Runs exported from the Simulation workspace. Add one as evidence for a physical-risk assessment.") {
            VStack(spacing: 6) {
                ForEach(candidates) { candidate in
                    HStack(spacing: 10) {
                        Image(systemName: "flame").foregroundStyle(.orange)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(candidate.title).font(.callout).lineLimit(1)
                            Text("\(candidate.scenario) · \(DisclosureFormat.date(candidate.generatedAt))")
                                .font(.caption).foregroundStyle(DSStyle.faint)
                        }
                        Spacer()
                        if added.contains(candidate.id) {
                            DSTag(text: "Added", color: WorkflowStatus.approved.tint)
                        } else {
                            Button("Add as Assessment") { store.addPhysicalRisk(from: candidate, in: engagement.id) }
                                .controlSize(.small)
                                .disabled(locked)
                        }
                    }
                    .padding(8)
                    .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
                }
            }
        }
    }
}

private struct EvidenceEditorSheet: View {
    @State var item: EvidenceItem
    let accent: Color
    let onSave: (EvidenceItem) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(item.title.isEmpty ? "New Evidence" : item.title).font(.title2.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Title", width: 110) {
                    TextField("e.g. MSEDCL electricity bills Apr–Mar", text: $item.title).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Type", width: 110) {
                    Picker("Type", selection: $item.kind) {
                        ForEach(EvidenceKind.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("File or link", width: 110) {
                    HStack {
                        TextField("Path or https:// address", text: $item.location).textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            let panel = NSOpenPanel()
                            panel.allowsMultipleSelection = false
                            if panel.runModal() == .OK, let url = panel.url {
                                item.location = url.path
                                if item.title.isEmpty { item.title = url.lastPathComponent }
                            }
                        }
                    }
                }
                DSFormRow("Period", width: 110) {
                    TextField("e.g. FY 2025-26", text: $item.period).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                DSFormRow("Notes", width: 110) {
                    TextField("What it shows, who provided it", text: $item.notes, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(item)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 600)
    }
}
