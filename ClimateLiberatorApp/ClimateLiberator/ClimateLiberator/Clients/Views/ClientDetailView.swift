import SwiftUI

/// One client: profile, sites, linked reporting and latest figures.
struct ClientDetailView: View {
    @ObservedObject var store: ClientRegistryStore
    @ObservedObject var disclosureStore: DisclosureStore
    let client: Client
    let accent: Color
    let openEngagement: (UUID) -> Void
    let openReduce: (UUID) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                ClientProfileCard(store: store, client: client)
                ClientSitesCard(store: store, client: client, accent: accent)
                ClientReportingCard(store: store, disclosureStore: disclosureStore, client: client, accent: accent,
                                    openEngagement: openEngagement, openReduce: openReduce)
            }
            .padding(.bottom, 16)
        }
    }
}

/// Name, sector, size, cluster and contact.
struct ClientProfileCard: View {
    @ObservedObject var store: ClientRegistryStore
    let client: Client

    private func binding<Value>(_ path: WritableKeyPath<Client, Value>) -> Binding<Value> {
        Binding(get: { client[keyPath: path] }, set: { value in store.update(client.id) { $0[keyPath: path] = value } })
    }

    var body: some View {
        DSCard("Company") {
            if client.isExample { DSTag(text: "Example · invented figures", color: .orange) }
        } content: {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Name", width: 120) {
                    TextField("Company name", text: binding(\.name)).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Sector", width: 120) {
                    Picker("Sector", selection: binding(\.sector)) {
                        ForEach(IndustrySector.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Size", width: 120) {
                    Picker("Size", selection: binding(\.size)) {
                        ForEach(EnterpriseSize.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 300)
                }
                DSFormRow("Cluster", width: 120) {
                    HStack(spacing: 6) {
                        TextField("e.g. Tiruppur knitwear", text: binding(\.cluster)).textFieldStyle(.roundedBorder)
                        if !store.clusters.isEmpty {
                            Menu {
                                ForEach(store.clusters, id: \.self) { name in
                                    Button(name) { store.update(client.id) { $0.cluster = name } }
                                }
                            } label: {
                                Image(systemName: "chevron.down.circle")
                            }
                            .menuStyle(.borderlessButton)
                            .fixedSize()
                            .help("Use an existing cluster")
                        }
                    }
                }
                DSFormRow("CIN", width: 120) {
                    TextField("Corporate Identity Number", text: binding(\.cin)).textFieldStyle(.roundedBorder).frame(maxWidth: 300)
                }
                DSFormRow("Website", width: 120) {
                    TextField("https://", text: binding(\.website)).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Contact", width: 120) {
                    HStack(spacing: 6) {
                        TextField("Name", text: binding(\.contact.name)).textFieldStyle(.roundedBorder)
                        TextField("Role", text: binding(\.contact.role)).textFieldStyle(.roundedBorder)
                    }
                }
                DSFormRow("", width: 120) {
                    HStack(spacing: 6) {
                        TextField("Email", text: binding(\.contact.email)).textFieldStyle(.roundedBorder)
                        TextField("Phone", text: binding(\.contact.phone)).textFieldStyle(.roundedBorder)
                    }
                }
                DSFormRow("Notes", width: 120) {
                    TextField("Scope of work, history, anything the team should know", text: binding(\.notes), axis: .vertical)
                        .lineLimit(2...5).textFieldStyle(.roundedBorder)
                }
            }
        }
    }
}
