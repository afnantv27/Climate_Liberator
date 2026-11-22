import Foundation

/// An invented knitwear cluster: five MSMEs with sites and one year of KPI Data,
/// so the cluster benchmark, Reduce and Home have something to show. Every
/// company and figure is fictional; place coordinates are approximate.
@MainActor
enum ExampleCluster {
    static let clusterName = "Example knitwear cluster"

    private struct Member {
        let name: String
        let size: EnterpriseSize
        let site: (name: String, kind: SiteKind, district: String, latitude: Double?, longitude: Double?)
        /// Current-year KPI values by metric id; prior year is derived from `priorFactor`.
        let values: [String: Double]
        let outputUnit: String
        let priorFactor: Double
    }

    private static let members: [Member] = [
        Member(name: "Example Knit Fabrics Pvt Ltd", size: .small,
               site: ("Knitting and compacting unit", .plant, "Tiruppur", 11.1085, 77.3411),
               values: [MetricID.scope1: 820, MetricID.scope2: 2_450, MetricID.revenue: 64, MetricID.output: 3_100,
                        MetricID.electricityRenewable: 4_000, MetricID.electricityNonRenewable: 11_000,
                        "energy.nonRenewableFuel": 9_000, MetricID.waterConsumption: 48_000],
               outputUnit: "tonnes of fabric", priorFactor: 1.06),
        Member(name: "Example Dyeing & Processing Ltd", size: .medium,
               site: ("Dyeing house with effluent treatment", .plant, "Tiruppur", 11.0790, 77.3820),
               values: [MetricID.scope1: 5_600, MetricID.scope2: 3_900, MetricID.revenue: 120, MetricID.output: 5_200,
                        MetricID.electricityRenewable: 2_000, MetricID.electricityNonRenewable: 17_500,
                        "energy.nonRenewableFuel": 70_000, MetricID.waterConsumption: 310_000],
               outputUnit: "tonnes of fabric", priorFactor: 1.02),
        Member(name: "Example Garment Exports Pvt Ltd", size: .medium,
               site: ("Stitching and finishing unit", .plant, "Tiruppur", 11.1270, 77.3050),
               values: [MetricID.scope1: 300, MetricID.scope2: 2_100, MetricID.revenue: 210, MetricID.output: 2_400,
                        MetricID.electricityRenewable: 6_500, MetricID.electricityNonRenewable: 8_700,
                        "energy.nonRenewableFuel": 3_500, MetricID.waterConsumption: 22_000],
               outputUnit: "tonnes of fabric", priorFactor: 1.09),
        Member(name: "Example Yarn Spinners Pvt Ltd", size: .small,
               site: ("Open-end spinning mill", .plant, "Coimbatore", 11.0168, 76.9558),
               values: [MetricID.scope1: 450, MetricID.scope2: 6_800, MetricID.revenue: 95, MetricID.output: 4_800,
                        MetricID.electricityRenewable: 9_000, MetricID.electricityNonRenewable: 31_000,
                        "energy.nonRenewableFuel": 4_500, MetricID.waterConsumption: 15_000],
               outputUnit: "tonnes of fabric", priorFactor: 0.98),
        Member(name: "Example Trims & Labels", size: .micro,
               site: ("Workshop", .plant, "Tiruppur", nil, nil),
               values: [:], outputUnit: "", priorFactor: 1),
    ]

    /// Adds the example clients (unsaved) and their example engagements (unsaved).
    static func load(into registry: ClientRegistryStore, disclosureStore: DisclosureStore, fiscalYearStart: Int? = nil) {
        let year = fiscalYearStart ?? NewEngagementSheet.lastCompletedYear()
        var firstID: UUID?
        for member in members {
            var client = Client(name: member.name)
            client.sector = .manufacturing
            client.size = member.size
            client.cluster = clusterName
            client.isExample = true
            var site = Site(name: member.site.name, kind: member.site.kind)
            site.district = member.site.district
            site.state = "Tamil Nadu"
            site.latitude = member.site.latitude
            site.longitude = member.site.longitude
            client.sites = [site]
            registry.insert(client)
            firstID = firstID ?? client.id
            guard !member.values.isEmpty else { continue }
            addEngagement(for: client, member: member, year: year, store: disclosureStore)
        }
        registry.selectedID = firstID
        registry.statusMessage = "Loaded an example cluster of five invented companies (not saved)."
    }

    private static func addEngagement(for client: Client, member: Member, year: Int, store: DisclosureStore) {
        let engagement = store.createEngagement(companyName: client.name, fiscalYearStart: year, frameworks: [.brsr],
                                                isListed: false, marketCapRank: nil, sector: client.sector)
        for (id, value) in member.values {
            store.updateMetric(id, in: engagement.id) { entry in
                entry.current = value
                // Business grew about 5%; emissions and resources moved by the member's factor.
                let isActivity = id == MetricID.revenue || id == MetricID.output
                entry.prior = (value * (isActivity ? 0.95 : member.priorFactor)).rounded()
                entry.source = "Example figure (invented)"
            }
        }
        store.updateMetric(MetricID.outputUnit, in: engagement.id) { $0.text = member.outputUnit }
        store.mutate(engagement.id) { $0.isExample = true }
        store.setClient(client.id, clientName: client.name, for: engagement.id)
    }
}
