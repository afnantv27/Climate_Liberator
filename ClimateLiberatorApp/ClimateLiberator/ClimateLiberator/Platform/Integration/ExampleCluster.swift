import Foundation

/// An invented polymer-processing and 3D-printing cluster: five MSMEs (moulding,
/// film extrusion, additive manufacturing, recycling, tooling) with sites and one
/// year of KPI Data, so the cluster benchmark, Reduce and Home have something to
/// show. Every company and figure is fictional; place coordinates are approximate.
/// Scope 2 ≈ grid electricity × 0.727 kg CO2e/kWh; Scope 1 ≈ fuel GJ × 0.063 t/GJ.
@MainActor
enum ExampleCluster {
    static let clusterName = "Example polymer & 3D printing cluster"
    /// One unit for every member, so output intensity can be ranked.
    static let outputUnit = "tonnes of polymer processed"

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
        Member(name: "Example Precision Moulders Pvt Ltd", size: .small,
               site: ("Injection moulding shop", .plant, "Chennai", 13.0980, 80.1620),
               values: [MetricID.scope1: 260, MetricID.scope2: 2_900, MetricID.revenue: 58, MetricID.output: 2_600,
                        MetricID.electricityRenewable: 3_000, MetricID.electricityNonRenewable: 14_400,
                        "energy.nonRenewableFuel": 4_100, MetricID.waterConsumption: 9_500],
               outputUnit: outputUnit, priorFactor: 1.06),
        Member(name: "Example Flexible Films Ltd", size: .medium,
               site: ("Blown-film extrusion plant", .plant, "Kancheepuram", 12.9680, 79.9480),
               values: [MetricID.scope1: 900, MetricID.scope2: 7_600, MetricID.revenue: 165, MetricID.output: 14_500,
                        MetricID.electricityRenewable: 4_500, MetricID.electricityNonRenewable: 37_600,
                        "energy.nonRenewableFuel": 14_300, MetricID.waterConsumption: 21_000],
               outputUnit: outputUnit, priorFactor: 1.02),
        Member(name: "Example Additive Works Pvt Ltd", size: .small,
               site: ("3D printing bureau (powder-bed and FDM)", .plant, "Chennai", 13.0108, 80.2120),
               values: [MetricID.scope1: 40, MetricID.scope2: 1_150, MetricID.revenue: 36, MetricID.output: 85,
                        MetricID.electricityRenewable: 2_800, MetricID.electricityNonRenewable: 5_700,
                        "energy.nonRenewableFuel": 630, MetricID.waterConsumption: 1_200],
               outputUnit: outputUnit, priorFactor: 1.09),
        Member(name: "Example Polymer Recyclers Pvt Ltd", size: .small,
               site: ("Washing and re-pelletising line", .plant, "Krishnagiri", 12.7409, 77.8253),
               values: [MetricID.scope1: 520, MetricID.scope2: 4_300, MetricID.revenue: 48, MetricID.output: 9_800,
                        MetricID.electricityRenewable: 1_500, MetricID.electricityNonRenewable: 21_300,
                        "energy.nonRenewableFuel": 8_250, MetricID.waterConsumption: 38_000],
               outputUnit: outputUnit, priorFactor: 0.98),
        Member(name: "Example Tooling & Moulds", size: .micro,
               site: ("Tool room", .plant, "Chennai", nil, nil),
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
