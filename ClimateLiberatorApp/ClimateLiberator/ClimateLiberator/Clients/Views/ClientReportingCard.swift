import SwiftUI

/// Engagements linked to the client and the latest figures they hold.
struct ClientReportingCard: View {
    @ObservedObject var store: ClientRegistryStore
    @ObservedObject var disclosureStore: DisclosureStore
    let client: Client
    let accent: Color
    let openEngagement: (UUID) -> Void
    let openReduce: (UUID) -> Void

    private var linked: [DisclosureEngagement] { disclosureStore.engagements(forClient: client.id) }

    /// Unlinked engagements, likely matches (same company name) first.
    private var linkable: [DisclosureEngagement] {
        let name = client.name.trimmingCharacters(in: .whitespaces).lowercased()
        return disclosureStore.unlinkedEngagements.sorted { a, b in
            let aMatch = !name.isEmpty && a.companyName.lowercased().contains(name)
            let bMatch = !name.isEmpty && b.companyName.lowercased().contains(name)
            if aMatch != bMatch { return aMatch }
            return a.displayName < b.displayName
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            figuresCard
            engagementsCard
        }
    }

    // MARK: Figures

    private var figuresCard: some View {
        let latest = DisclosurePerformanceSource.latest(for: client.id, engagements: disclosureStore.engagements)
        return DSCard("Latest Figures", subtitle: latest?.source ?? "From the client's KPI Data in Report. Link or start an engagement to collect them.") {
            Button { openReduce(client.id) } label: { Label("Reduction Plan", systemImage: "arrow.down.right") }
        } content: {
            if let latest {
                HStack(spacing: 12) {
                    DSMetricTile(title: "Scope 1 + 2", value: DisplayFormat.value(latest.scope12, unit: "tCO2e"),
                                 detail: ReportingPeriod.label(latest.fiscalYearStart), systemImage: "smoke")
                    DSMetricTile(title: "Intensity", value: DisplayFormat.value(latest.intensityPerRevenue, unit: ""),
                                 detail: "tCO2e per ₹ crore", systemImage: "chart.bar")
                    DSMetricTile(title: "Energy", value: DisplayFormat.value(latest.energyGJ, unit: "GJ"),
                                 detail: latest.renewableShare.map { "\(DisplayFormat.percent($0)) renewable" } ?? "",
                                 systemImage: "bolt")
                }
            } else {
                Text("No figures yet.").font(.callout).foregroundStyle(DSStyle.subtle)
            }
        }
    }

    // MARK: Engagements

    private var engagementsCard: some View {
        DSCard("Reporting & Data Collection",
               subtitle: "Engagements in Report hold the client's KPI Data. One engagement per financial year.") {
            HStack(spacing: 8) {
                if !linkable.isEmpty {
                    Menu {
                        ForEach(linkable) { engagement in
                            Button(engagement.displayName) {
                                disclosureStore.setClient(client.id, clientName: client.displayName, for: engagement.id)
                            }
                        }
                    } label: {
                        Label("Link Existing", systemImage: "link")
                    }
                    .fixedSize()
                }
                Button { startEngagement() } label: { Label("Start Data Collection", systemImage: "plus") }
                    .help("Creates an engagement for the last completed financial year, linked to this client")
            }
        } content: {
            if linked.isEmpty {
                Text("No engagements linked yet.").font(.callout).foregroundStyle(DSStyle.subtle)
            }
            VStack(spacing: 6) {
                ForEach(linked) { engagement in row(engagement) }
            }
        }
    }

    private func row(_ engagement: DisclosureEngagement) -> some View {
        let readiness = ReadinessAnalyzer.analyze(engagement)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text(engagement.periodLabel).font(.callout.weight(.medium))
                Text(engagement.frameworks.map(\.title).sorted().joined(separator: " · "))
                    .font(.caption).foregroundStyle(DSStyle.subtle)
            }
            Spacer()
            if engagement.isLocked { DSTag(text: "Signed off", color: DSStyle.good) }
            DSProgressBar(value: readiness.overallAnswered, tint: accent).frame(width: 90)
            Text(DisplayFormat.percent(readiness.overallAnswered)).font(.caption.monospacedDigit()).frame(width: 40, alignment: .trailing)
            Button("Open") { openEngagement(engagement.id) }
                .controlSize(.small)
            Button {
                disclosureStore.setClient(nil, clientName: client.displayName, for: engagement.id)
            } label: {
                Image(systemName: "xmark.circle")
            }
            .buttonStyle(.borderless)
            .help("Unlink from this client")
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }

    private func startEngagement() {
        let year = NewEngagementSheet.lastCompletedYear()
        let engagement = disclosureStore.createEngagement(companyName: client.displayName, fiscalYearStart: year,
                                                          frameworks: [.brsr], isListed: false, marketCapRank: nil,
                                                          sector: client.sector)
        disclosureStore.setClient(client.id, clientName: client.displayName, for: engagement.id)
        openEngagement(engagement.id)
    }
}
