import SwiftUI

/// One card per module, in the order work flows: clients → measure → reduce →
/// report, with climate risk alongside.
struct HomeModulesColumn: View {
    let summary: HomeSummary
    @ObservedObject var forecastStore: ForecastIntelligenceStore
    let accent: Color
    let navigation: HomeNavigation

    var body: some View {
        VStack(spacing: 10) {
            module("Clients", "person.2", "Companies, sites and clusters. Start here.",
                   "\(summary.clientCount) clients", button: "Open Clients") { navigation.open(.clients) }
            module("Measure", "function", "GHG inventories with emission factors from connected databases.",
                   "\(summary.inventoryCount) inventories", button: "Open GHG Accounting") { navigation.open(.ghgAccounting) }
            module("Reduce", "arrow.down.right", "Targets, reduction measures, carbon credits and action plans.",
                   "\(summary.targetCount) targets", button: "Open Reduce") { navigation.open(.reduce) }
            module("Report", "doc.text", "BRSR, BRSR Core and IFRS S2: KPI data, review, sign-off and reports.",
                   "\(summary.activeEngagements) in progress", button: "Open Disclosure") { navigation.open(.disclosure) }
            climateRiskCard
        }
    }

    private func module(_ title: String, _ icon: String, _ detail: String, _ count: String,
                        button: String, action: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon).font(.title3).foregroundStyle(accent).frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(title).font(.headline)
                    Spacer()
                    Text(count).font(.caption.monospacedDigit()).foregroundStyle(DSStyle.faint)
                }
                Text(detail).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
                Button(button, action: action).controlSize(.small).padding(.top, 2)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DSStyle.panel))
    }

    private var climateRiskCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "flame").font(.title3).foregroundStyle(.orange).frame(width: 28)
            VStack(alignment: .leading, spacing: 6) {
                Text("Climate Risk").font(.headline)
                Text("Wildfire simulation today; more hazards for client sites are planned.")
                    .font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
                if let snapshot = forecastStore.latestExecutiveSnapshot {
                    Text("Latest promoted forecast: \(snapshot.locationLabel) · \(snapshot.horizon.capitalized)")
                        .font(.caption).foregroundStyle(DSStyle.faint)
                }
                HStack(spacing: 8) {
                    Button("Open Climate Simulation") { navigation.open(.climateRisk) }
                    Button("Open Forecast Intelligence", action: navigation.openForecastIntelligence)
                }
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DSStyle.panel))
    }
}
