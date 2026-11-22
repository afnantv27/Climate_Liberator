import SwiftUI

/// Searchable list of clients, optionally narrowed to one cluster.
struct ClientListView: View {
    @ObservedObject var store: ClientRegistryStore
    let accent: Color

    @State private var search = ""
    @State private var cluster: String?

    private var rows: [Client] {
        let query = search.trimmingCharacters(in: .whitespaces).lowercased()
        return store.clients.filter { client in
            if let cluster, client.clusterName.caseInsensitiveCompare(cluster) != .orderedSame { return false }
            guard !query.isEmpty else { return true }
            let haystack = ([client.name, client.clusterName, client.sector.title] + client.sites.map(\.placeLabel))
                .joined(separator: " ").lowercased()
            return haystack.contains(query)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            DSSearchField(text: $search, prompt: "Search clients, places, sectors")
            if !store.clusters.isEmpty {
                Picker("Cluster", selection: $cluster) {
                    Text("All clusters").tag(String?.none)
                    ForEach(store.clusters, id: \.self) { Text($0).tag(Optional($0)) }
                }
                .labelsHidden()
            }
            ScrollView {
                LazyVStack(spacing: 4) {
                    ForEach(rows) { client in row(client) }
                    if rows.isEmpty {
                        Text("No client matches.").font(.callout).foregroundStyle(DSStyle.subtle).padding(.top, 20)
                    }
                }
            }
            Text("\(store.clients.count) clients · \(store.siteCount) sites · \(store.clusters.count) clusters")
                .font(.caption)
                .foregroundStyle(DSStyle.faint)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(DSStyle.panel))
    }

    private func row(_ client: Client) -> some View {
        let isSelected = store.selectedID == client.id
        return Button {
            store.selectedID = client.id
        } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(client.displayName).font(.callout.weight(.medium)).lineLimit(1)
                        if store.isUnsaved(client.id) {
                            Circle().fill(DSStyle.warning).frame(width: 6, height: 6).help("Unsaved changes")
                        }
                    }
                    Text([client.size.title, client.sector.title, client.clusterName].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(DSStyle.subtle)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                if client.isExample { DSTag(text: "Example", color: .orange) }
                Text("\(client.sites.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DSStyle.faint)
                    .help("\(client.sites.count) site(s)")
            }
            .padding(.vertical, 7)
            .padding(.horizontal, 9)
            .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(isSelected ? DSStyle.rowSelected : DSStyle.rowFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
