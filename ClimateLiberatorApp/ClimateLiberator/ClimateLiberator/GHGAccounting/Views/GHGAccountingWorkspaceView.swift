import SwiftUI
import MapKit

/// The inventory pipeline, in the order the GPC work is done.
enum GHGPipelineStep: String, CaseIterable, Identifiable {
    case boundary, activity, review, results, scenarios, actionPlan

    var id: String { rawValue }
    var number: Int { (Self.allCases.firstIndex(of: self) ?? 0) + 1 }
    var title: String {
        switch self {
        case .boundary: return "Boundary"
        case .activity: return "Activity Data"
        case .review: return "Review"
        case .results: return "Results"
        case .scenarios: return "Scenarios"
        case .actionPlan: return "Action Plan"
        }
    }
    var systemImage: String {
        switch self {
        case .boundary: return "map"
        case .activity: return "list.bullet.rectangle"
        case .review: return "checklist"
        case .results: return "chart.pie"
        case .scenarios: return "chart.line.downtrend.xyaxis"
        case .actionPlan: return "checklist.checked"
        }
    }
}

/// Helpers used alongside any step, shown in the side panel.
enum GHGTool: String, CaseIterable, Identifiable {
    case calculator, databases

    /// UserDefaults key other workspaces set to open a tool here on arrival.
    static let pendingRequestKey = "ghg.pendingTool"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .calculator: return "Calculator"
        case .databases: return "Factor Databases"
        }
    }
    var systemImage: String {
        switch self {
        case .calculator: return "function"
        case .databases: return "externaldrive.connected.to.line.below"
        }
    }
}

/// GHG Accounting workspace: a six-step GPC pipeline (inventory, scenarios, action plan), with the
/// emission-factor calculator and databases in a side panel that stays open
/// next to whichever step is in use.
struct GHGAccountingWorkspaceView: View {
    @ObservedObject var inventoryStore: GPCInventoryStore
    @ObservedObject var factorStore: EmissionFactorLibraryStore
    let theme: ThemeStyle

    @State private var step: GHGPipelineStep = .boundary
    /// Scenario shown in the Scenarios and Action Plan steps.
    @State private var scenarioID: UUID?
    @State private var tool: GHGTool?
    @State private var showingNewInventory = false
    @State private var confirmingDelete = false

    private static let toolsPanelWidth: CGFloat = 420

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.03, green: 0.08, blue: 0.08),
                         Color(red: 0.05, green: 0.12, blue: 0.13),
                         Color(red: 0.08, green: 0.15, blue: 0.17)],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                header
                pipelineBar
                HStack(alignment: .top, spacing: 16) {
                    content
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    if let tool {
                        toolsPanel(tool)
                            .frame(width: Self.toolsPanelWidth)
                            .frame(maxHeight: .infinity, alignment: .top)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                    }
                }
            }
            .padding(.top, 84)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .foregroundStyle(.white)
        .animation(.easeInOut(duration: 0.2), value: tool)
        .onAppear(perform: openPendingTool)
        .sheet(isPresented: $showingNewInventory) {
            NewInventorySheet { name, year in
                inventoryStore.createInventory(cityName: name, year: year)
                step = .boundary
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete) {
            Button(selectedIsOnDisk ? "Move to Trash" : "Discard Inventory", role: .destructive) {
                if let id = inventoryStore.selectedID { inventoryStore.deleteInventory(id: id) }
            }
        } message: {
            Text(selectedIsOnDisk ? "The saved file goes to the Trash, so you can restore it from there."
                                  : "This inventory was never saved, so it cannot be recovered.")
        }
    }

    private var selectedIsOnDisk: Bool { inventoryStore.selectedID.map(inventoryStore.isOnDisk) ?? false }
    private var selectedIsUnsaved: Bool { inventoryStore.selectedID.map(inventoryStore.isUnsaved) ?? false }
    private var deleteTitle: String {
        let name = inventoryStore.selected?.displayName ?? "this inventory"
        return selectedIsOnDisk ? "Move “\(name)” to the Trash?" : "Discard “\(name)”?"
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("GHG Accounting")
                    .font(.appPageTitle)
                    .accessibilityAddTraits(.isHeader)
                Text("City inventories under the GPC (BASIC / BASIC+) with factors from connected databases.")
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 12)
            if !inventoryStore.inventories.isEmpty {
                Picker("Inventory", selection: $inventoryStore.selectedID) {
                    ForEach(inventoryStore.inventories) { inventory in
                        Text(inventoryStore.isUnsaved(inventory.id) ? "\(inventory.displayName) — Not Saved" : inventory.displayName)
                            .tag(Optional(inventory.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 280)
            }
            if inventoryStore.selected != nil {
                Button { inventoryStore.saveSelected() } label: {
                    Label(selectedIsUnsaved ? "Save" : "Saved", systemImage: selectedIsUnsaved ? "square.and.arrow.down" : "checkmark")
                }
                .keyboardShortcut("s", modifiers: .command)
                .disabled(!selectedIsUnsaved)
                .help(selectedIsUnsaved ? "Save this inventory (⌘S). Nothing is saved until you do." : "All changes are saved")
            }
            Menu {
                Button("Load Iritty Example") {
                    inventoryStore.loadExample(GPCExamplePathways.irittyWithPathway())
                    step = .results
                }
                .help("Illustrative GPC BASIC inventory for Iritty Municipality, Kerala, built from public data")
                if inventoryStore.selected != nil {
                    Divider()
                    if selectedIsUnsaved && selectedIsOnDisk {
                        Button("Revert to Saved") {
                            if let id = inventoryStore.selectedID { inventoryStore.revert(id: id) }
                        }
                    }
                    Button(selectedIsOnDisk ? "Move to Trash…" : "Discard Inventory…", role: .destructive) {
                        confirmingDelete = true
                    }
                }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            .help("More actions")
            Button {
                showingNewInventory = true
            } label: {
                Label("New Inventory", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(theme.accentColor)
        }
    }

    // MARK: Pipeline bar

    private var pipelineBar: some View {
        let inventory = inventoryStore.selected
        let summary = inventory.map(GPCInventorySummary.make)
        let statuses = GHGPipelineStep.allCases.map { status(of: $0, inventory: inventory, summary: summary) }
        // Full chips when there is room; compact chips and icon-only tools when the window is narrow.
        return ViewThatFits(in: .horizontal) {
            pipelineRow(statuses, compact: false)
            pipelineRow(statuses, compact: true)
        }
        .accessibilityIdentifier("ghg.sectionPicker")
    }

    private func pipelineRow(_ statuses: [StepStatus], compact: Bool) -> some View {
        HStack(spacing: 6) {
            ForEach(Array(GHGPipelineStep.allCases.enumerated()), id: \.element) { index, item in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.3))
                }
                stepChip(item, status: statuses[index], compact: compact)
            }
            Spacer(minLength: 16)
            if !compact {
                Text("Tools").font(.caption.weight(.semibold)).foregroundStyle(.white.opacity(0.55))
            }
            ForEach(GHGTool.allCases) { item in
                toolButton(item, compact: compact)
            }
        }
    }

    private struct StepStatus {
        var detail: String
        var isDone: Bool
    }

    private func status(of item: GHGPipelineStep, inventory: GPCInventory?, summary: GPCInventorySummary?) -> StepStatus {
        guard let inventory, let summary else { return StepStatus(detail: "No inventory", isDone: false) }
        switch item {
        case .boundary:
            return inventory.boundary.isClosed
                ? StepStatus(detail: String(format: "%.1f km²", inventory.boundary.areaSquareKilometres), isDone: true)
                : StepStatus(detail: "Not set", isDone: false)
        case .activity:
            return StepStatus(detail: "\(inventory.entries.count) entries", isDone: !inventory.entries.isEmpty)
        case .review:
            return summary.missingCount == 0
                ? StepStatus(detail: "Complete", isDone: !inventory.entries.isEmpty)
                : StepStatus(detail: "\(summary.missingCount) gaps", isDone: false)
        case .results:
            let total = inventory.targetLevel == .basic ? summary.basicTotal : summary.basicPlusTotal
            return StepStatus(detail: "\(GHGFormat.plain(total)) t", isDone: total > 0)
        case .scenarios:
            let count = inventory.decarbonizationScenarios.count
            return StepStatus(detail: count == 0 ? "Not started" : "\(count) pathway\(count == 1 ? "" : "s")", isDone: count > 0)
        case .actionPlan:
            let scenarios = inventory.decarbonizationScenarios
            let scenario = scenarios.first { $0.id == scenarioID } ?? scenarios.first
            guard let scenario, !scenario.measures.isEmpty else { return StepStatus(detail: "Not started", isDone: false) }
            let owned = scenario.measures.filter { !($0.plan?.owner ?? "").trimmingCharacters(in: .whitespaces).isEmpty }.count
            return StepStatus(detail: "\(owned)/\(scenario.measures.count) owned", isDone: owned == scenario.measures.count)
        }
    }

    private func stepChip(_ item: GHGPipelineStep, status: StepStatus, compact: Bool) -> some View {
        let isSelected = step == item
        return Button { step = item } label: {
            HStack(spacing: 8) {
                ZStack {
                    Circle().fill(isSelected ? theme.accentColor : Color.white.opacity(0.12))
                    if status.isDone && !isSelected {
                        Image(systemName: "checkmark").font(.caption2.weight(.semibold)).foregroundStyle(.green)
                    } else {
                        Text("\(item.number)").font(.caption.weight(.semibold))
                            .foregroundStyle(isSelected ? Color.black : Color.white)
                    }
                }
                .frame(width: 22, height: 22)
                VStack(alignment: .leading, spacing: 0) {
                    Text(item.title).font(.callout.weight(isSelected ? .semibold : .regular)).lineLimit(1)
                    if !compact {
                        Text(status.detail).font(.caption2.monospacedDigit()).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
                    }
                }
            }
            .padding(.vertical, 6)
            .padding(.leading, 6)
            .padding(.trailing, 12)
            .background(Capsule().fill(isSelected ? theme.accentColor.opacity(0.18) : Color.white.opacity(0.05)))
            .overlay(Capsule().stroke(isSelected ? theme.accentColor.opacity(0.7) : Color.white.opacity(0.08), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help("Step \(item.number): \(item.title) — \(status.detail)")
    }

    /// Opens a tool another workspace asked for (Disclosure → "Calculate in GHG Accounting").
    private func openPendingTool() {
        let defaults = UserDefaults.standard
        guard let raw = defaults.string(forKey: GHGTool.pendingRequestKey) else { return }
        defaults.removeObject(forKey: GHGTool.pendingRequestKey)
        if let requested = GHGTool(rawValue: raw) { tool = requested }
    }

    private func toolButton(_ item: GHGTool, compact: Bool) -> some View {
        let isOpen = tool == item
        return Button {
            tool = isOpen ? nil : item
        } label: {
            Label(item.title, systemImage: item.systemImage)
                .labelStyle(GHGToolLabelStyle(iconOnly: compact))
                .font(.callout)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(Capsule().fill(isOpen ? theme.accentColor.opacity(0.25) : Color.white.opacity(0.06)))
                .overlay(Capsule().stroke(isOpen ? theme.accentColor.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
                .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .help(isOpen ? "Close \(item.title)" : "Open \(item.title) beside the current step")
    }

    // MARK: Tools panel

    private func toolsPanel(_ current: GHGTool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Picker("Tool", selection: Binding(get: { current }, set: { tool = $0 })) {
                    ForEach(GHGTool.allCases) { Label($0.title, systemImage: $0.systemImage).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Button { tool = nil } label: { Image(systemName: "xmark.circle.fill").imageScale(.large) }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.white.opacity(0.6))
                    .help("Close tools")
            }
            switch current {
            case .calculator:
                EmissionFactorCalculatorView(factorStore: factorStore, inventoryStore: inventoryStore,
                                             accent: theme.accentColor) {
                    if step != .activity { step = .activity }
                }
            case .databases:
                EmissionFactorDatabasesView(store: factorStore, accent: theme.accentColor)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.12), lineWidth: 1))
        )
    }

    // MARK: Step content

    @ViewBuilder
    private var content: some View {
        if let inventory = inventoryStore.selected {
            switch step {
            case .boundary:
                GPCBoundaryEditorView(store: inventoryStore, inventory: inventory, accent: theme.accentColor)
            case .activity:
                GPCInventoryEntriesView(store: inventoryStore, factorStore: factorStore, inventory: inventory, accent: theme.accentColor)
            case .review:
                GPCReviewView(store: inventoryStore, inventory: inventory, accent: theme.accentColor)
            case .results:
                GPCResultsView(store: inventoryStore, inventory: inventory, accent: theme.accentColor)
            case .scenarios:
                GPCScenariosView(store: inventoryStore, inventory: inventory, accent: theme.accentColor,
                                 selectedScenarioID: $scenarioID)
            case .actionPlan:
                GPCActionPlanView(store: inventoryStore, inventory: inventory, accent: theme.accentColor,
                                  selectedScenarioID: $scenarioID, openScenarios: { step = .scenarios })
            }
        } else {
            VStack(alignment: .leading, spacing: 14) {
                newInventoryCard
                Button("Load the Iritty example instead") {
                    inventoryStore.loadExample(GPCExamplePathways.irittyWithPathway())
                    step = .results
                }
                .buttonStyle(.link)
                .font(.callout)
                Spacer()
            }
        }
    }

    /// Empty state: one large, clickable card that starts a new inventory.
    private var newInventoryCard: some View {
        Button { showingNewInventory = true } label: {
            HStack(spacing: 22) {
                ZStack {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(theme.accentColor.opacity(0.18))
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(theme.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    Image(systemName: "plus")
                        .font(.system(size: 38, weight: .semibold))
                        .foregroundStyle(theme.accentColor)
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 6) {
                    Text("New City Inventory").font(.appSectionTitle)
                    Text("One city, one year: boundary → activity data → review → results → scenarios → action plan.")
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                    Text("Nothing is saved until you choose Save.")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer(minLength: 0)
            }
            .padding(22)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1))
            )
            .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
        .buttonStyle(.plain)
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .help("Create a new city inventory (⇧⌘N)")
        .accessibilityLabel("New city inventory")
    }
}

private struct NewInventorySheet: View {
    let onCreate: (String, Int) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var cityName = ""
    @State private var year = Calendar.current.component(.year, from: Date()) - 1

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("New GPC Inventory").font(.appSectionTitle)
            Form {
                TextField("City or town", text: $cityName)
                Stepper(value: $year, in: 1990...2100) {
                    Text("Inventory year: \(String(year))")
                }
            }
            .formStyle(.grouped)
            Text("Use the latest complete year with data (state whether financial or calendar). The inventory stays unsaved until you choose Save.")
                .font(.footnote)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(cityName.trimmingCharacters(in: .whitespacesAndNewlines), year)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(cityName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

/// Title and icon, or icon only when the pipeline bar is short of room.
private struct GHGToolLabelStyle: LabelStyle {
    let iconOnly: Bool

    @ViewBuilder
    func makeBody(configuration: Configuration) -> some View {
        if iconOnly {
            configuration.icon
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
}
