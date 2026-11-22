import SwiftUI

/// Material issues register (BRSR Section A, IFRS S2 Strategy), heat map, and
/// physical-risk assessments for IFRS S2 29(c).
struct RisksView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let candidates: [SimulationEvidenceCandidate]
    let accent: Color

    @State private var editingIssue: MaterialIssue?
    @State private var editingRisk: PhysicalRiskAssessment?
    @State private var topicFilter: TopicFilter = .all

    enum TopicFilter: String, CaseIterable, Identifiable {
        case all, climate, other
        var id: String { rawValue }
        var title: String {
            switch self {
            case .all: return "All issues"
            case .climate: return "Climate only"
            case .other: return "Other ESG"
            }
        }
    }

    private var locked: Bool { engagement.isLocked }

    private var issues: [MaterialIssue] {
        let sorted = ReportBuilder.sortedIssues(engagement.issues)
        switch topicFilter {
        case .all: return sorted
        case .climate: return sorted.filter { $0.topic.isClimate }
        case .other: return sorted.filter { !$0.topic.isClimate }
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        registerCard.frame(minWidth: 520)
                        heatMapCard.frame(width: 330)
                    }
                    VStack(spacing: 14) {
                        registerCard
                        heatMapCard
                    }
                }
                physicalCard
            }
            .padding(.bottom, 16)
        }
        .sheet(item: $editingIssue) { issue in
            IssueEditorSheet(issue: issue, accent: accent) { saved in store.upsertIssue(saved, in: engagement.id) }
        }
        .sheet(item: $editingRisk) { risk in
            PhysicalRiskEditorSheet(risk: risk, evidence: engagement.evidence, accent: accent) { saved in
                store.upsertPhysicalRisk(saved, in: engagement.id)
            }
        }
    }

    // MARK: Register

    private var registerCard: some View {
        DSCard("Material Issues Register",
               subtitle: "One register feeds BRSR Section A (material responsible business conduct issues) and, for climate topics, IFRS S2 Strategy.") {
            HStack(spacing: 8) {
                Picker("Show", selection: $topicFilter) {
                    ForEach(TopicFilter.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                Button { editingIssue = MaterialIssue() } label: { Label("Add Issue", systemImage: "plus") }
                    .disabled(locked)
            }
        } content: {
            if issues.isEmpty {
                Text("No issues yet. Add each material risk and opportunity, with why it matters and how the company responds.")
                    .font(.callout)
                    .foregroundStyle(DSStyle.subtle)
            } else {
                VStack(spacing: 6) {
                    ForEach(issues) { issue in issueRow(issue) }
                }
            }
        }
    }

    private func issueRow(_ issue: MaterialIssue) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("\(issue.score)")
                .font(.callout.weight(.bold).monospacedDigit())
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Self.scoreColor(issue.score).opacity(0.8)))
                .help("Likelihood \(issue.likelihood) × impact \(issue.impact)")
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(issue.title.isEmpty ? "Untitled issue" : issue.title).font(.callout.weight(.semibold))
                    DSTag(text: issue.type.title, color: issue.type == .risk ? IssueSeverity.blocker.tint : WorkflowStatus.approved.tint)
                    DSTag(text: issue.horizon.title)
                }
                Text(issue.topic.title).font(.caption).foregroundStyle(DSStyle.subtle)
                if !issue.rationale.isEmpty {
                    Text(issue.rationale).font(.caption).foregroundStyle(DSStyle.subtle).lineLimit(2)
                }
            }
            Spacer(minLength: 6)
            Button { editingIssue = issue } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .disabled(locked)
                .help("Edit")
            Button { store.removeIssue(issue.id, in: engagement.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .disabled(locked)
                .help("Remove")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }

    static func scoreColor(_ score: Int) -> Color {
        switch score {
        case 15...: return Color(red: 0.86, green: 0.30, blue: 0.30)
        case 8..<15: return Color(red: 0.90, green: 0.60, blue: 0.22)
        case 4..<8: return Color(red: 0.78, green: 0.72, blue: 0.25)
        default: return Color(red: 0.35, green: 0.62, blue: 0.42)
        }
    }

    // MARK: Heat map

    private var heatMapCard: some View {
        DSCard("Heat Map", subtitle: "Likelihood against impact. Hover a cell to see its issues.") {
            VStack(alignment: .leading, spacing: 4) {
                ForEach((1...5).reversed(), id: \.self) { likelihood in
                    HStack(spacing: 4) {
                        Text("\(likelihood)").font(.caption2.monospacedDigit()).foregroundStyle(DSStyle.faint).frame(width: 14)
                        ForEach(1...5, id: \.self) { impact in
                            heatCell(likelihood: likelihood, impact: impact)
                        }
                    }
                }
                HStack(spacing: 4) {
                    Text("").frame(width: 14)
                    ForEach(1...5, id: \.self) { impact in
                        Text("\(impact)").font(.caption2.monospacedDigit()).foregroundStyle(DSStyle.faint).frame(width: 50)
                    }
                }
                HStack {
                    Text("↑ Likelihood").font(.caption2).foregroundStyle(DSStyle.faint)
                    Spacer()
                    Text("Impact →").font(.caption2).foregroundStyle(DSStyle.faint)
                }
                .frame(width: 290)
            }
        }
    }

    private func heatCell(likelihood: Int, impact: Int) -> some View {
        let matching = engagement.issues.filter { $0.likelihood == likelihood && $0.impact == impact }
        return ZStack {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(Self.scoreColor(likelihood * impact).opacity(matching.isEmpty ? 0.22 : 0.85))
            if !matching.isEmpty {
                Text("\(matching.count)").font(.callout.weight(.bold).monospacedDigit())
            }
        }
        .frame(width: 50, height: 34)
        .help(matching.isEmpty ? "Likelihood \(likelihood), impact \(impact)" : matching.map(\.title).joined(separator: "\n"))
    }

    // MARK: Physical risk

    private var physicalCard: some View {
        let paragraphs = PhysicalRiskDrafting.paragraphs(for: engagement)
        return DSCard("Physical-Risk Assessments",
                      subtitle: "Modelled exposure of the company's assets to climate hazards. Feeds IFRS S2 29(c) and the resilience narrative. Wildfire runs from the Simulation workspace can be used directly.") {
            HStack(spacing: 8) {
                if !candidates.isEmpty {
                    Menu {
                        ForEach(candidates) { candidate in
                            Button("\(candidate.scenario) · \(DisclosureFormat.date(candidate.generatedAt))") {
                                store.addPhysicalRisk(from: candidate, in: engagement.id)
                            }
                        }
                    } label: {
                        Label("From Simulation", systemImage: "flame")
                    }
                    .fixedSize()
                    .help("Adds a wildfire simulation package as evidence and starts an assessment from it")
                }
                Button { editingRisk = PhysicalRiskAssessment() } label: { Label("Add Assessment", systemImage: "plus") }
            }
            .disabled(locked)
        } content: {
            VStack(alignment: .leading, spacing: 10) {
                if engagement.physicalRisks.isEmpty {
                    Text("No assessments yet. Add one per hazard (flood, cyclone, heat, wildfire…) with the value of assets assessed and found vulnerable.")
                        .font(.callout)
                        .foregroundStyle(DSStyle.subtle)
                } else {
                    physicalHeader
                    ForEach(engagement.physicalRisks) { risk in physicalRow(risk) }
                    HStack {
                        Button("Fill IFRS S2 29(c) from These") { store.applyPhysicalRisksToMetrics(in: engagement.id) }
                            .disabled(locked)
                            .help("Sets the amount and share of assets vulnerable to physical risks in KPI Data")
                        Spacer()
                    }
                    if !paragraphs.isEmpty {
                        Text("DRAFT TEXT FOR THE IFRS S2 REPORT").font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint)
                        ForEach(paragraphs, id: \.self) { paragraph in
                            Text(paragraph).font(.caption).foregroundStyle(DSStyle.subtle).textSelection(.enabled)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    private var physicalHeader: some View {
        HStack(spacing: 8) {
            Text("Hazard").frame(width: 110, alignment: .leading)
            Text("Scenario").frame(maxWidth: .infinity, alignment: .leading)
            Text("Assessed").frame(width: 110, alignment: .trailing)
            Text("Vulnerable").frame(width: 110, alignment: .trailing)
            Text("Gross loss").frame(width: 100, alignment: .trailing)
            Text("").frame(width: 60)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(DSStyle.faint)
    }

    private func physicalRow(_ risk: PhysicalRiskAssessment) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Text(risk.hazard.title)
                if risk.evidenceID != nil { Image(systemName: "paperclip").font(.caption).foregroundStyle(DSStyle.subtle) }
            }
            .frame(width: 110, alignment: .leading)
            Text([risk.scenario, risk.horizon].filter { !$0.isEmpty }.joined(separator: " · "))
                .font(.caption).foregroundStyle(DSStyle.subtle).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(DisclosureFormat.value(risk.valueAssessedCrore, unit: "₹ cr")).frame(width: 110, alignment: .trailing)
            Text(DisclosureFormat.value(risk.valueVulnerableCrore, unit: "₹ cr")
                 + (risk.vulnerableShare.map { " (\(DisclosureFormat.percent($0)))" } ?? ""))
                .frame(width: 110, alignment: .trailing)
            Text(DisclosureFormat.value(risk.grossLossCrore, unit: "₹ cr")).frame(width: 100, alignment: .trailing)
            HStack(spacing: 6) {
                Button { editingRisk = risk } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
                Button { store.removePhysicalRisk(risk.id, in: engagement.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless)
            }
            .disabled(locked)
            .frame(width: 60)
        }
        .font(.callout.monospacedDigit())
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DSStyle.rowFill))
    }
}

// MARK: - Editors

private struct IssueEditorSheet: View {
    @State var issue: MaterialIssue
    let accent: Color
    let onSave: (MaterialIssue) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(issue.title.isEmpty ? "New Material Issue" : issue.title).font(.title2.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Issue", width: 130) {
                    TextField("e.g. Water stress at the Pune plant", text: $issue.title).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Type", width: 130) {
                    Picker("Type", selection: $issue.type) {
                        ForEach(IssueType.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 220)
                }
                DSFormRow("Topic", width: 130) {
                    Picker("Topic", selection: $issue.topic) {
                        ForEach(IssueTopic.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Time horizon", width: 130) {
                    Picker("Horizon", selection: $issue.horizon) {
                        ForEach(TimeHorizon.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 320)
                }
                DSFormRow("Likelihood", width: 130) {
                    Stepper(value: $issue.likelihood, in: 1...5) { Text("\(issue.likelihood) of 5").monospacedDigit() }
                }
                DSFormRow("Impact", width: 130) {
                    Stepper(value: $issue.impact, in: 1...5) { Text("\(issue.impact) of 5").monospacedDigit() }
                }
                DSFormRow("Why it is material", width: 130) {
                    TextField("Rationale", text: $issue.rationale, axis: .vertical).lineLimit(2...4).textFieldStyle(.roundedBorder)
                }
                DSFormRow(issue.type == .risk ? "Response" : "How it is pursued", width: 130) {
                    TextField("Approach to adapt, mitigate or capture", text: $issue.approach, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Financial effect", width: 130) {
                    HStack {
                        Picker("Implication", selection: $issue.implication) {
                            ForEach(FinancialImplication.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        TextField("Size or description, e.g. ₹12 crore a year", text: $issue.financialNote).textFieldStyle(.roundedBorder)
                    }
                }
                DSFormRow("Owner", width: 130) {
                    TextField("Person or team", text: $issue.owner).textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(issue)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(issue.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 640)
    }
}

private struct PhysicalRiskEditorSheet: View {
    @State var risk: PhysicalRiskAssessment
    let evidence: [EvidenceItem]
    let accent: Color
    let onSave: (PhysicalRiskAssessment) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Physical-Risk Assessment").font(.title2.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Hazard", width: 150) {
                    Picker("Hazard", selection: $risk.hazard) {
                        ForEach(PhysicalHazard.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Scenario", width: 150) {
                    TextField("e.g. SSP2-4.5, 1-in-100-year flood", text: $risk.scenario).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Time horizon", width: 150) {
                    TextField("e.g. 2030, 2050", text: $risk.horizon).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Assets assessed", width: 150) {
                    DSNumberField(placeholder: "Number", value: risk.assetsAssessed.map { Double($0) },
                                  onCommit: { risk.assetsAssessed = $0.map { Int($0) } }, width: 120)
                }
                DSFormRow("Value assessed", width: 150) { croreField(\.valueAssessedCrore) }
                DSFormRow("Value vulnerable", width: 150) { croreField(\.valueVulnerableCrore) }
                DSFormRow("Modelled gross loss", width: 150) { croreField(\.grossLossCrore) }
                DSFormRow("Net insured loss", width: 150) { croreField(\.insuredLossCrore) }
                DSFormRow("Evidence", width: 150) {
                    Picker("Evidence", selection: $risk.evidenceID) {
                        Text("None").tag(UUID?.none)
                        ForEach(evidence) { Text($0.title).tag(Optional($0.id)) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Notes", width: 150) {
                    TextField("Model, data sources, limitations", text: $risk.notes, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                }
            }
            if let share = risk.vulnerableShare {
                Text("\(DisclosureFormat.percent(share)) of the value assessed is vulnerable.").font(.callout).foregroundStyle(DSStyle.subtle)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(risk)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 600)
    }

    private func croreField(_ path: WritableKeyPath<PhysicalRiskAssessment, Double?>) -> some View {
        HStack {
            DSNumberField(placeholder: "—", value: risk[keyPath: path], onCommit: { risk[keyPath: path] = $0 }, width: 140)
            Text("₹ crore").font(.caption).foregroundStyle(DSStyle.subtle)
        }
    }
}
