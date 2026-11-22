import SwiftUI

/// Where Home's buttons go; provided by the app shell.
struct HomeNavigation {
    let open: (AppWorkspace) -> Void
    let openEngagement: (UUID) -> Void
    let openClient: (UUID) -> Void
    let openReductionPlan: (UUID) -> Void
    let openForecastIntelligence: () -> Void
}

/// Start page: what needs attention across all clients, and the way into each module.
struct HomeView: View {
    @ObservedObject var registry: ClientRegistryStore
    @ObservedObject var disclosureStore: DisclosureStore
    @ObservedObject var reductionStore: ReductionStore
    @ObservedObject var ghgStore: GPCInventoryStore
    @ObservedObject var forecastStore: ForecastIntelligenceStore
    let accent: Color
    let navigation: HomeNavigation

    var body: some View {
        let summary = HomeSummary.build(clients: registry.clients, engagements: disclosureStore.engagements,
                                        plans: Array(reductionStore.plans.values), inventoryCount: ghgStore.inventories.count)
        WorkspacePage(title: "Home", subtitle: Date().formatted(date: .complete, time: .omitted)) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tiles(summary)
                    HStack(alignment: .top, spacing: 16) {
                        AttentionCard(items: summary.attention, navigate: navigate)
                            .frame(maxWidth: .infinity)
                        HomeModulesColumn(summary: summary, forecastStore: forecastStore, accent: accent, navigation: navigation)
                            .frame(width: 430)
                    }
                }
                .padding(.bottom, 16)
            }
            .accessibilityIdentifier("home.scroll")
        }
    }

    private func tiles(_ summary: HomeSummary) -> some View {
        HStack(spacing: 12) {
            DSMetricTile(title: "Clients", value: "\(summary.clientCount)",
                         detail: "\(summary.clusterCount) cluster(s)", systemImage: "person.2")
            DSMetricTile(title: "Sites", value: "\(summary.siteCount)",
                         detail: summary.sitesWithoutCoordinates > 0 ? "\(summary.sitesWithoutCoordinates) without coordinates" : "All mapped",
                         systemImage: "mappin.and.ellipse")
            DSMetricTile(title: "Engagements in progress", value: "\(summary.activeEngagements)",
                         detail: "\(summary.signedOffEngagements) signed off", systemImage: "doc.text")
            DSMetricTile(title: "Waiting for review", value: "\(summary.itemsAwaitingReview)",
                         detail: "KPIs and narratives", systemImage: "checkmark.seal")
            DSMetricTile(title: "Targets", value: "\(summary.targetCount)",
                         detail: summary.targetsOffTrack > 0 ? "\(summary.targetsOffTrack) off track" : "None off track",
                         systemImage: "scope")
        }
    }

    private func navigate(_ destination: HomeDestination) {
        switch destination {
        case .engagement(let id): navigation.openEngagement(id)
        case .client(let id): navigation.openClient(id)
        case .reductionPlan(let id): navigation.openReductionPlan(id)
        }
    }
}

/// The attention list, most urgent first.
struct AttentionCard: View {
    let items: [AttentionItem]
    let navigate: (HomeDestination) -> Void

    @State private var showAll = false

    var body: some View {
        DSCard("Needs Attention", subtitle: "Deadlines, blockers, reviews and targets across all clients.") {
            if items.isEmpty {
                Label("Nothing needs attention.", systemImage: "checkmark.circle").foregroundStyle(DSStyle.good)
            }
            VStack(spacing: 6) {
                ForEach(showAll ? items : Array(items.prefix(8))) { item in row(item) }
            }
            if items.count > 8 {
                Button(showAll ? "Show fewer" : "Show all \(items.count)") { showAll.toggle() }
                    .buttonStyle(.link)
            }
        }
    }

    private func row(_ item: AttentionItem) -> some View {
        Button { navigate(item.destination) } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: icon(item.severity)).foregroundStyle(color(item.severity)).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title).font(.callout.weight(.medium)).multilineTextAlignment(.leading)
                    if !item.detail.isEmpty {
                        Text(item.detail).font(.caption).foregroundStyle(DSStyle.subtle)
                    }
                }
                Spacer()
                Image(systemName: "chevron.right").font(.caption).foregroundStyle(DSStyle.faint)
            }
            .padding(9)
            .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func icon(_ severity: AttentionItem.Severity) -> String {
        switch severity {
        case .urgent: return "exclamationmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private func color(_ severity: AttentionItem.Severity) -> Color {
        switch severity {
        case .urgent: return DSStyle.bad
        case .warning: return DSStyle.warning
        case .info: return DSStyle.info
        }
    }
}
