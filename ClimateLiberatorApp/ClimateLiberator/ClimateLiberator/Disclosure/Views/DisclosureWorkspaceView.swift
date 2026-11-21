import SwiftUI
import Combine
import UniformTypeIdentifiers

/// Sections of the Disclosure workspace, in the order the work is done.
enum DisclosureSection: String, CaseIterable, Identifiable {
    case portfolio, overview, setup, data, narratives, risks, policies, evidence, review, reports

    var id: String { rawValue }
    var title: String {
        switch self {
        case .portfolio: return "All Clients"
        case .overview: return "Overview"
        case .setup: return "Company & Scope"
        case .data: return "KPI Data"
        case .narratives: return "Narratives"
        case .risks: return "Risks & Opportunities"
        case .policies: return "Policies & Governance"
        case .evidence: return "Evidence"
        case .review: return "Review & Approval"
        case .reports: return "Reports"
        }
    }
    var systemImage: String {
        switch self {
        case .portfolio: return "square.grid.2x2"
        case .overview: return "gauge.with.dots.needle.50percent"
        case .setup: return "building.2"
        case .data: return "tablecells"
        case .narratives: return "text.alignleft"
        case .risks: return "exclamationmark.triangle"
        case .policies: return "building.columns"
        case .evidence: return "paperclip"
        case .review: return "checkmark.seal"
        case .reports: return "doc.richtext"
        }
    }
    var group: String {
        switch self {
        case .portfolio: return "Clients"
        case .overview, .setup: return "Engagement"
        case .data, .narratives, .risks, .policies, .evidence: return "Collect"
        case .review, .reports: return "Finalise"
        }
    }
    /// Sections that need a selected engagement.
    var needsEngagement: Bool { self != .portfolio }
}

/// Shared navigation state, so any panel can send the user to the right place.
@MainActor
final class DisclosureRouter: ObservableObject {
    @Published var section: DisclosureSection = .overview
    @Published var focusMetricID: String?
    @Published var focusGroup: MetricGroup?
    @Published var focusNarrativeID: String?

    func open(_ section: DisclosureSection) {
        self.section = section
    }

    func openMetric(_ id: String) {
        focusMetricID = id
        focusGroup = MetricCatalog.metric(id)?.group
        section = .data
    }

    func openGroup(_ group: MetricGroup) {
        focusGroup = group
        focusMetricID = MetricCatalog.metrics(in: group).first { !$0.isCalculated }?.id
        section = .data
    }

    func openNarrative(_ id: String) {
        focusNarrativeID = id
        section = .narratives
    }

    /// Where a data-quality issue is fixed.
    func open(_ issue: QualityIssue) {
        switch issue.area {
        case .setup: open(.setup)
        case .data:
            if let target = issue.target {
                if let group = MetricGroup(rawValue: target) { openGroup(group) } else { openMetric(target) }
            } else {
                open(.data)
            }
        case .narratives:
            if let target = issue.target { openNarrative(target) } else { open(.narratives) }
        case .risks: open(.risks)
        case .policies: open(.policies)
        case .evidence: open(.evidence)
        case .review: open(.review)
        }
    }
}

/// The Disclosure workspace: BRSR, BRSR Core and IFRS S2 for one or many clients.
struct DisclosureWorkspaceView: View {
    @ObservedObject var store: DisclosureStore
    @ObservedObject var ghgStore: GPCInventoryStore
    @ObservedObject var evidenceStore: TCFDReviewStore
    let theme: ThemeStyle
    /// Switches the app to the GHG Accounting workspace.
    let openGHGAccounting: () -> Void

    @StateObject private var router = DisclosureRouter()
    @State private var showingNewEngagement = false
    @State private var confirmingDelete = false

    private var accent: Color { theme.accentColor }

    var body: some View {
        ZStack {
            DSStyle.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                header
                HStack(alignment: .top, spacing: 16) {
                    sidebar.frame(width: 214)
                    content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
                if !store.statusMessage.isEmpty {
                    Text(store.statusMessage)
                        .font(.caption)
                        .foregroundStyle(DSStyle.subtle)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 84)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
        .environmentObject(router)
        .onAppear {
            if store.selected == nil { router.section = .portfolio }
        }
        .sheet(isPresented: $showingNewEngagement) {
            NewEngagementSheet(accent: accent) { name, year, frameworks, isListed, rank, sector in
                store.createEngagement(companyName: name, fiscalYearStart: year, frameworks: frameworks,
                                       isListed: isListed, marketCapRank: rank, sector: sector)
                router.open(.setup)
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete) {
            Button(selectedIsOnDisk ? "Move to Trash" : "Discard Engagement", role: .destructive) {
                if let id = store.selectedID { store.deleteEngagement(id: id) }
                if store.selected == nil { router.open(.portfolio) }
            }
        } message: {
            Text(selectedIsOnDisk ? "The saved file goes to the Trash, so you can restore it from there."
                                  : "This engagement was never saved, so it cannot be recovered.")
        }
    }

    private var selectedIsOnDisk: Bool { store.selectedID.map(store.isOnDisk) ?? false }
    private var selectedIsUnsaved: Bool { store.selectedID.map(store.isUnsaved) ?? false }
    private var deleteTitle: String {
        let name = store.selected?.displayName ?? "this engagement"
        return selectedIsOnDisk ? "Move “\(name)” to the Trash?" : "Discard “\(name)”?"
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Disclosure").font(.appPageTitle).accessibilityAddTraits(.isHeader)
                Text("BRSR, BRSR Core and IFRS S2 reporting for client companies.")
                    .font(.callout)
                    .foregroundStyle(DSStyle.subtle)
            }
            Spacer(minLength: 12)
            if !store.engagements.isEmpty {
                Picker("Client", selection: $store.selectedID) {
                    ForEach(store.engagements) { engagement in
                        Text(store.isUnsaved(engagement.id) ? "\(engagement.displayName) — Not Saved" : engagement.displayName)
                            .tag(Optional(engagement.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
            }
            if store.selected != nil {
                Button { store.saveSelected() } label: {
                    Label(selectedIsUnsaved ? "Save" : "Saved", systemImage: selectedIsUnsaved ? "square.and.arrow.down" : "checkmark")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!selectedIsUnsaved)
                .help(selectedIsUnsaved ? "Save this engagement (⌘S). Nothing is saved until you do." : "All changes are saved")
            }
            moreMenu
            Button { showingNewEngagement = true } label: { Label("New Client", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
    }

    private var moreMenu: some View {
        Menu {
            Button("Load Example Company") {
                store.loadExample()
                router.open(.overview)
            }
            .help("An invented company with realistic data, for demonstrations and training")
            Button("Import Engagement File…") { importEngagement() }
            if let selected = store.selected {
                Divider()
                Button("Start \(ReportingPeriod.label(selected.fiscalYearStart + 1)) from This Year") {
                    store.rollForward(id: selected.id)
                    router.open(.overview)
                }
                .help("Copies the company, scope, policies and narratives; this year's values become prior-year figures")
                Button("Export Engagement File…") { exportEngagement(selected) }
                if selectedIsUnsaved && selectedIsOnDisk {
                    Button("Revert to Saved") { store.revert(id: selected.id) }
                }
                Divider()
                Button(selectedIsOnDisk ? "Move to Trash…" : "Discard Engagement…", role: .destructive) { confirmingDelete = true }
            }
        } label: {
            Image(systemName: "ellipsis.circle")
        }
        .menuStyle(.button)
        .buttonStyle(.borderless)
        .fixedSize()
        .help("More actions")
    }

    private func importEngagement() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.message = "Choose a disclosure engagement file (.json) exported from Climate Liberator."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.importEngagementFile(from: url)
        router.open(.overview)
    }

    private func exportEngagement(_ engagement: DisclosureEngagement) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "\(DisclosureFormat.fileStem(engagement.companyName))-\(DisclosureFormat.fileStem(engagement.periodLabel)).json"
        panel.message = "Share this file with your client or consultant; they open it with Import Engagement File."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.exportEngagementFile(id: engagement.id, to: url)
    }

    // MARK: Sidebar

    private var sidebar: some View {
        let engagement = store.selected
        let readiness = engagement.map(ReadinessAnalyzer.analyze)
        let issues = engagement.map { DataQualityChecks.run($0) } ?? []
        return ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let engagement, let readiness {
                    clientCard(engagement, readiness: readiness)
                }
                let groups = ["Clients", "Engagement", "Collect", "Finalise"]
                ForEach(groups, id: \.self) { group in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(group.uppercased())
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(DSStyle.faint)
                            .padding(.leading, 10)
                            .padding(.bottom, 2)
                        ForEach(DisclosureSection.allCases.filter { $0.group == group }) { section in
                            sidebarRow(section, badge: badge(for: section, engagement: engagement, issues: issues))
                        }
                    }
                }
            }
            .padding(.bottom, 12)
        }
    }

    private func clientCard(_ engagement: DisclosureEngagement, readiness: EngagementReadiness) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(engagement.companyName).font(.callout.weight(.semibold)).lineLimit(2)
            HStack(spacing: 6) {
                DSTag(text: engagement.periodLabel, color: accent)
                if engagement.isLocked { DSTag(text: "Signed off", color: WorkflowStatus.approved.tint) }
                if engagement.isExample { DSTag(text: "Example", color: .orange) }
            }
            HStack(spacing: 4) {
                ForEach(DisclosureFramework.allCases.filter(engagement.frameworks.contains)) { framework in
                    DSTag(text: framework.title, color: framework.tint)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Complete").font(.caption2).foregroundStyle(DSStyle.subtle)
                    Spacer()
                    Text(DisclosureFormat.percent(readiness.overallAnswered)).font(.caption2.monospacedDigit())
                }
                DSProgressBar(value: readiness.overallAnswered, tint: accent)
                HStack {
                    Text("Approved").font(.caption2).foregroundStyle(DSStyle.subtle)
                    Spacer()
                    Text(DisclosureFormat.percent(readiness.overallApproved)).font(.caption2.monospacedDigit())
                }
                DSProgressBar(value: readiness.overallApproved, tint: WorkflowStatus.approved.tint)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DSStyle.panel))
    }

    private func sidebarRow(_ section: DisclosureSection, badge: (text: String, color: Color)?) -> some View {
        let isSelected = router.section == section
        let isDisabled = section.needsEngagement && store.selected == nil
        return Button {
            router.open(section)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: section.systemImage).frame(width: 18)
                Text(section.title).lineLimit(1)
                Spacer(minLength: 4)
                if let badge {
                    Text(badge.text)
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(badge.color.opacity(0.25)))
                }
            }
            .font(.callout)
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? DSStyle.rowSelected : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.4 : 1)
    }

    private func badge(for section: DisclosureSection, engagement: DisclosureEngagement?,
                       issues: [QualityIssue]) -> (text: String, color: Color)? {
        switch section {
        case .portfolio:
            return store.engagements.isEmpty ? nil : ("\(store.engagements.count)", Color.white)
        case .review:
            guard let engagement else { return nil }
            let waiting = engagement.metrics.values.filter { $0.status == .readyForReview }.count
                + engagement.narratives.values.filter { $0.status == .readyForReview }.count
            return waiting == 0 ? nil : ("\(waiting)", WorkflowStatus.readyForReview.tint)
        case .overview:
            let blockers = issues.filter { $0.severity == .blocker }.count
            return blockers == 0 ? nil : ("\(blockers)", IssueSeverity.blocker.tint)
        case .evidence:
            guard let engagement, !engagement.evidence.isEmpty else { return nil }
            return ("\(engagement.evidence.count)", Color.white)
        case .risks:
            guard let engagement, !engagement.issues.isEmpty else { return nil }
            return ("\(engagement.issues.count)", Color.white)
        default:
            return nil
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if router.section == .portfolio || store.selected == nil {
            PortfolioView(store: store, accent: accent, newEngagement: { showingNewEngagement = true })
        } else if let engagement = store.selected {
            switch router.section {
            case .portfolio:
                EmptyView()
            case .overview:
                OverviewView(store: store, engagement: engagement, accent: accent)
            case .setup:
                SetupView(store: store, engagement: engagement, accent: accent)
            case .data:
                MetricWorkbenchView(store: store, engagement: engagement, ghgTotals: GHGInventoryBridge.totals(from: ghgStore),
                                    accent: accent, openGHGAccounting: {
                                        GHGInventoryBridge.requestCalculator()
                                        openGHGAccounting()
                                    })
            case .narratives:
                NarrativesView(store: store, engagement: engagement, accent: accent)
            case .risks:
                RisksView(store: store, engagement: engagement, candidates: WildfireEvidenceBridge.candidates(from: evidenceStore),
                          accent: accent)
            case .policies:
                PoliciesView(store: store, engagement: engagement, accent: accent)
            case .evidence:
                EvidenceView(store: store, engagement: engagement, candidates: WildfireEvidenceBridge.candidates(from: evidenceStore),
                             accent: accent)
            case .review:
                ReviewView(store: store, engagement: engagement, accent: accent)
            case .reports:
                ReportsView(store: store, engagement: engagement, accent: accent)
            }
        }
    }
}
