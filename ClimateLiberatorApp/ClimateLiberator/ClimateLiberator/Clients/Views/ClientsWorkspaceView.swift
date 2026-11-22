import SwiftUI

/// The Clients workspace: the register of client companies and their sites, and
/// cluster benchmarks built from the clients' reported figures.
struct ClientsWorkspaceView: View {
    @ObservedObject var store: ClientRegistryStore
    @ObservedObject var disclosureStore: DisclosureStore
    let accent: Color
    /// Opens an engagement in the Report (Disclosure) workspace.
    let openEngagement: (UUID) -> Void
    /// Opens the client's plan in the Reduce workspace.
    let openReduce: (UUID) -> Void

    enum Tab: String, CaseIterable, Identifiable {
        case clients, clusters
        var id: String { rawValue }
        var title: String { self == .clients ? "Clients" : "Clusters" }
    }

    @State private var tab: Tab = .clients
    @State private var confirmingDelete = false

    var body: some View {
        WorkspacePage(title: "Clients", subtitle: "Client companies, their sites and the clusters they belong to.",
                      status: store.statusMessage) {
            actions
        } content: {
            VStack(alignment: .leading, spacing: 12) {
                Picker("View", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 260)
                switch tab {
                case .clients: clientsTab
                case .clusters:
                    ClusterView(registry: store, disclosureStore: disclosureStore, accent: accent) { clientID in
                        store.selectedID = clientID
                        tab = .clients
                    }
                }
            }
        }
        .confirmationDialog(deleteTitle, isPresented: $confirmingDelete) {
            Button(selectedIsOnDisk ? "Move to Trash" : "Discard Client", role: .destructive) {
                if let id = store.selectedID { store.delete(id: id) }
            }
        } message: {
            Text("Linked engagements and reduction plans keep their data and show as unlinked.")
        }
    }

    // MARK: Header actions

    private var selectedIsOnDisk: Bool { store.selectedID.map(store.folder.exists) ?? false }
    private var deleteTitle: String {
        let name = store.selectedClient?.displayName ?? "this client"
        return selectedIsOnDisk ? "Move “\(name)” to the Trash?" : "Discard “\(name)”?"
    }

    private var actions: some View {
        HStack(spacing: 10) {
            Button {
                if let id = store.selectedID { store.save(id: id) }
            } label: {
                Label("Save", systemImage: "square.and.arrow.down")
            }
            .keyboardShortcut("s", modifiers: .command)
            .disabled(!(store.selectedID.map(store.isUnsaved) ?? false))
            .help("Save the selected client (⌘S)")

            Menu {
                Button("Save All") { store.saveAll() }
                    .disabled(store.unsavedIDs.isEmpty)
                Button("Load Example Cluster") {
                    ExampleCluster.load(into: store, disclosureStore: disclosureStore)
                    tab = .clusters
                }
                Divider()
                Button("Revert to Saved") { if let id = store.selectedID { store.revert(id: id) } }
                    .disabled(!(store.selectedID.map(store.isUnsaved) ?? false))
                Button("Delete Client…", role: .destructive) { confirmingDelete = true }
                    .disabled(store.selectedID == nil)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .fixedSize()

            Button {
                store.createClient()
                tab = .clients
            } label: {
                Label("New Client", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
        }
    }

    // MARK: Clients tab

    @ViewBuilder
    private var clientsTab: some View {
        if store.clients.isEmpty {
            DSEmptyState(systemImage: "person.2.crop.square.stack",
                         title: "No clients yet",
                         message: "Add the companies you work with and their sites. Engagements, reduction plans and climate-risk checks then link to them.") {
                Button("New Client") { store.createClient() }
                    .buttonStyle(.borderedProminent).tint(accent)
                Button("Load Example Cluster") {
                    ExampleCluster.load(into: store, disclosureStore: disclosureStore)
                }
            }
        } else {
            HStack(alignment: .top, spacing: 16) {
                ClientListView(store: store, accent: accent)
                    .frame(width: 300)
                if let client = store.selectedClient {
                    ClientDetailView(store: store, disclosureStore: disclosureStore, client: client, accent: accent,
                                     openEngagement: openEngagement, openReduce: openReduce)
                        .id(client.id)
                } else {
                    DSCard("Select a client") {
                        Text("Choose a client on the left.").foregroundStyle(DSStyle.subtle)
                    }
                }
            }
        }
    }
}
