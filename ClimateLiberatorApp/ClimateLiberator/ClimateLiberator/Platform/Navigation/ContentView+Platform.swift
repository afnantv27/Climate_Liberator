import SwiftUI

/// Home, Clients and Reduce workspaces, and the cross-workspace navigation they use.
/// Kept apart from ContentView's simulation code.
extension ContentView {
    var homeWorkspaceView: some View {
        HomeView(registry: clientRegistry, disclosureStore: disclosureStore, reductionStore: reductionStore,
                 ghgStore: ghgInventoryStore, forecastStore: forecastStore, accent: theme.accentColor,
                 navigation: HomeNavigation(open: { activeWorkspace = $0 },
                                            openEngagement: openEngagement,
                                            openClient: openClient,
                                            openReductionPlan: openReductionPlan,
                                            openForecastIntelligence: { openWindow(id: "forecast-intelligence") }))
    }

    var clientsWorkspaceView: some View {
        ClientsWorkspaceView(store: clientRegistry, disclosureStore: disclosureStore, accent: theme.accentColor,
                             openEngagement: openEngagement, openReduce: openReductionPlan)
    }

    var reduceWorkspaceView: some View {
        ReduceWorkspaceView(store: reductionStore, registry: clientRegistry, disclosureStore: disclosureStore,
                            ghgStore: ghgInventoryStore, accent: theme.accentColor,
                            openClients: { activeWorkspace = .clients },
                            openGHGAccounting: openInventory)
    }

    // MARK: Navigation

    func openEngagement(_ id: UUID) {
        disclosureStore.selectedID = id
        activeWorkspace = .disclosure
    }

    func openClient(_ id: UUID) {
        clientRegistry.selectedID = id
        activeWorkspace = .clients
    }

    func openReductionPlan(_ clientID: UUID) {
        clientRegistry.selectedID = clientID
        activeWorkspace = .reduce
    }

    func openInventory(_ id: UUID) {
        ghgInventoryStore.selectedID = id
        activeWorkspace = .ghgAccounting
    }
}
