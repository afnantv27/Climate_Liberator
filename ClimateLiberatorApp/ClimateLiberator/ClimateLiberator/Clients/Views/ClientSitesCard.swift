import SwiftUI
import MapKit

/// The client's sites with a map. Coordinates are what Climate Risk will assess.
struct ClientSitesCard: View {
    @ObservedObject var store: ClientRegistryStore
    let client: Client
    let accent: Color

    @State private var editing: Site?

    private var mapped: [Site] { client.sites.filter(\.hasCoordinates) }

    var body: some View {
        DSCard("Sites", subtitle: "Plants, offices and warehouses. Add coordinates so climate risks can be checked for each site.") {
            Button {
                editing = Site(name: client.sites.isEmpty ? "Main plant" : "")
            } label: {
                Label("Add Site", systemImage: "plus")
            }
        } content: {
            if client.sites.isEmpty {
                Text("No sites yet.").font(.callout).foregroundStyle(DSStyle.subtle)
            } else {
                if !mapped.isEmpty { map }
                VStack(spacing: 6) {
                    ForEach(client.sites) { site in row(site) }
                }
                if mapped.count < client.sites.count {
                    Label("\(client.sites.count - mapped.count) site(s) without coordinates.", systemImage: "mappin.slash")
                        .font(.caption)
                        .foregroundStyle(DSStyle.warning)
                }
            }
        }
        .sheet(item: $editing) { site in
            SiteEditorSheet(site: site, accent: accent) { saved in
                if client.site(saved.id) == nil {
                    store.update(client.id) { $0.sites.append(saved) }
                } else {
                    store.updateSite(saved.id, of: client.id) { $0 = saved }
                }
            }
        }
    }

    private var map: some View {
        Map(initialPosition: .automatic) {
            // `mapped` only holds sites with both coordinates.
            ForEach(mapped) { site in
                Marker(site.displayName, systemImage: site.kind.systemImage,
                       coordinate: CLLocationCoordinate2D(latitude: site.latitude ?? 0, longitude: site.longitude ?? 0))
                    .tint(accent)
            }
        }
        .mapStyle(.standard(pointsOfInterest: .excludingAll))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func row(_ site: Site) -> some View {
        HStack(spacing: 10) {
            Image(systemName: site.kind.systemImage).foregroundStyle(DSStyle.subtle).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(site.displayName).font(.callout.weight(.medium))
                Text([site.kind.title, site.placeLabel].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(DSStyle.subtle)
            }
            Spacer()
            if let latitude = site.latitude, let longitude = site.longitude {
                Text(CoordinateText.format(latitude: latitude, longitude: longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DSStyle.faint)
                    .textSelection(.enabled)
            } else {
                DSTag(text: "No coordinates", color: DSStyle.warning)
            }
            Button { editing = site } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Edit")
            Button { store.removeSite(site.id, from: client.id) } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Remove")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }
}
