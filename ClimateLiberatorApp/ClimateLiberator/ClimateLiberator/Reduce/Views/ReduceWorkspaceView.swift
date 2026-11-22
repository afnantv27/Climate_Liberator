import SwiftUI

/// The Reduce workspace: for each client, targets against reported emissions,
/// the measures that should get there, and the carbon credits bought or retired.
/// City action plans (GHG Accounting) are listed alongside.
struct ReduceWorkspaceView: View {
    @ObservedObject var store: ReductionStore
    @ObservedObject var registry: ClientRegistryStore
    @ObservedObject var disclosureStore: DisclosureStore
    @ObservedObject var ghgStore: GPCInventoryStore
    let accent: Color
    let openClients: () -> Void
    let openGHGAccounting: (UUID) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case targets, measures, credits, cityPlans
        var id: String { rawValue }
        var title: String {
            switch self {
            case .targets: return "Targets"
            case .measures: return "Measures"
            case .credits: return "Carbon Credits"
            case .cityPlans: return "City Action Plans"
            }
        }
    }

    @State private var tab: Tab = .targets

    private var client: Client? { registry.selectedClient ?? registry.clients.first }

    var body: some View {
        WorkspacePage(title: "Reduce", subtitle: "Targets, reduction measures and carbon credits for each client.",
                      status: store.statusMessage) {
            actions
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 560)
                if tab == .cityPlans {
                    CityActionPlansView(ghgStore: ghgStore, openInventory: openGHGAccounting)
                } else if let client {
                    clientContent(client)
                } else {
                    DSEmptyState(systemImage: "person.2", title: "No clients yet",
                                 message: "Reduction plans belong to clients. Add a client first; its reported emissions then drive the targets here.") {
                        Button("Open Clients", action: openClients)
                    }
                }
            }
        }
    }

    // MARK: Header

    private var actions: some View {
        HStack(spacing: 10) {
            if !registry.clients.isEmpty {
                Picker("Client", selection: Binding(get: { client?.id }, set: { registry.selectedID = $0 })) {
                    ForEach(registry.clients) { Text($0.displayName).tag(Optional($0.id)) }
                }
                .frame(width: 300)
            }
            Button {
                if let id = client?.id { store.save(clientID: id) }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!(client.map { store.isUnsaved($0.id) } ?? false))
            .help("Save this client's reduction plan (⌘S)")
            Menu {
                Button("Save All Plans") { store.saveAll() }.disabled(store.unsavedIDs.isEmpty)
                Button("Revert to Saved") { if let id = client?.id { store.revert(clientID: id) } }
                    .disabled(!(client.map { store.isUnsaved($0.id) } ?? false))
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .fixedSize()
        }
    }

    // MARK: Content

    @ViewBuilder
    private func clientContent(_ client: Client) -> some View {
        let plan = store.plan(for: client.id, clientName: client.displayName)
        let history = DisclosurePerformanceSource.history(for: client.id, engagements: disclosureStore.engagements)
        let context = ReducePlanContext(store: store, clientID: client.id, clientName: client.displayName, plan: plan,
                                        history: history, accent: accent)
        switch tab {
        case .targets: TargetsView(context: context)
        case .measures: MeasuresView(context: context)
        case .credits: CreditsView(context: context)
        case .cityPlans: EmptyView()
        }
    }
}

/// What every Reduce tab needs about the selected client, in one value.
struct ReducePlanContext {
    let store: ReductionStore
    let clientID: UUID
    let clientName: String
    let plan: ReductionPlan
    /// Reported figures by year, oldest first.
    let history: [ClientYearFigures]
    let accent: Color

    var latestYear: Int? { history.last?.fiscalYearStart }
    /// Default years for new items: last completed year and the year after.
    var defaultYear: Int { latestYear ?? NewEngagementSheet.lastCompletedYear() }
}
