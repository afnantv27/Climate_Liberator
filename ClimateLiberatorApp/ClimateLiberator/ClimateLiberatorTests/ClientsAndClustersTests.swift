import XCTest
@testable import ClimateLiberator

/// Client register, figures from KPI Data, and cluster benchmarking.
@MainActor
final class ClientsAndClustersTests: XCTestCase {

    private func engagement(client: UUID, year: Int, current: [String: Double], prior: [String: Double] = [:]) -> DisclosureEngagement {
        var engagement = DisclosureEngagement(fiscalYearStart: year)
        engagement.clientID = client
        for (id, value) in current {
            var entry = engagement.metric(id)
            entry.current = value
            engagement.metrics[id] = entry
        }
        for (id, value) in prior {
            var entry = engagement.metric(id)
            entry.prior = value
            engagement.metrics[id] = entry
        }
        return engagement
    }

    private func figures(_ year: Int = 2025, scope1: Double?, scope2: Double?, revenue: Double?,
                         output: Double? = nil, unit: String = "") -> ClientYearFigures {
        var figures = ClientYearFigures(clientID: UUID(), fiscalYearStart: year)
        figures.scope1 = scope1
        figures.scope2 = scope2
        figures.revenueCrore = revenue
        figures.output = output
        figures.outputUnit = unit
        return figures
    }

    // MARK: Register

    func testRegisterIgnoresNoOpEditsAndTracksUnsaved() {
        let store = ClientRegistryStore(loadFromDisk: false)
        let client = store.createClient(name: "Moulding Co")
        store.save(id: client.id)
        XCTAssertFalse(store.isUnsaved(client.id))
        store.update(client.id) { $0.name = "Moulding Co" }
        XCTAssertFalse(store.isUnsaved(client.id), "Writing back the same value is not an edit")
        store.addSite(to: client.id, name: "Plant")
        XCTAssertTrue(store.isUnsaved(client.id))
        XCTAssertEqual(store.client(client.id)?.sites.count, 1)
    }

    func testClustersMergeCaseAndSpacing() {
        let store = ClientRegistryStore(loadFromDisk: false)
        store.createClient(name: "A", cluster: "Chennai Polymer")
        store.createClient(name: "B", cluster: " chennai polymer ")
        store.createClient(name: "C", cluster: "")
        XCTAssertEqual(store.clusters, ["Chennai Polymer"])
        XCTAssertEqual(store.clients(inCluster: "CHENNAI POLYMER").count, 2)
    }

    func testRevertRemovesNeverSavedClient() {
        let store = ClientRegistryStore(loadFromDisk: false)
        let client = store.createClient(name: "Temp")
        store.revert(id: client.id)
        XCTAssertNil(store.client(client.id))
    }

    // MARK: Figures from KPI Data

    func testHistoryPrefersCurrentColumnOverPriorColumn() throws {
        let client = UUID()
        let fy25 = engagement(client: client, year: 2025, current: [MetricID.scope1: 100, MetricID.scope2: 50],
                              prior: [MetricID.scope1: 120, MetricID.scope2: 60])
        let fy24 = engagement(client: client, year: 2024, current: [MetricID.scope1: 118, MetricID.scope2: 61])
        let other = engagement(client: UUID(), year: 2025, current: [MetricID.scope1: 999])
        let history = DisclosurePerformanceSource.history(for: client, engagements: [fy25, fy24, other])
        XCTAssertEqual(history.map(\.fiscalYearStart), [2024, 2025])
        let first = try XCTUnwrap(history.first)
        XCTAssertEqual(first.scope1, 118, "FY 2024-25's own engagement wins over the prior-year column")
        XCTAssertEqual(history.last?.scope12, 150)
    }

    func testPriorColumnFillsAYearWithoutItsOwnEngagement() {
        let client = UUID()
        let fy25 = engagement(client: client, year: 2025, current: [MetricID.scope1: 100], prior: [MetricID.scope1: 120])
        let history = DisclosurePerformanceSource.history(for: client, engagements: [fy25])
        XCTAssertEqual(history.first?.fiscalYearStart, 2024)
        XCTAssertEqual(history.first?.scope1, 120)
        XCTAssertTrue(history.first?.source.contains("prior-year") ?? false)
    }

    // MARK: Benchmark

    func testQuartilesInterpolate() throws {
        let stats = try XCTUnwrap(ClusterBenchmark.statistics([10, 20, 30, 40]))
        XCTAssertEqual(stats.median, 25, accuracy: 1e-9)
        XCTAssertEqual(stats.lowerQuartile, 17.5, accuracy: 1e-9)
        XCTAssertEqual(stats.upperQuartile, 32.5, accuracy: 1e-9)
        XCTAssertNil(ClusterBenchmark.statistics([]))
    }

    func testRankingBandsAndAggregateIntensity() throws {
        let members = [
            ClusterMember(clientID: UUID(), name: "Low", size: .small, figures: figures(scope1: 10, scope2: 10, revenue: 10)),   // 2.0
            ClusterMember(clientID: UUID(), name: "High", size: .small, figures: figures(scope1: 60, scope2: 40, revenue: 10)),  // 10.0
            ClusterMember(clientID: UUID(), name: "Mid", size: .medium, figures: figures(scope1: 30, scope2: 20, revenue: 10)),  // 5.0
            ClusterMember(clientID: UUID(), name: "Silent", size: .micro, figures: nil),
        ]
        let summary = ClusterBenchmark.summarize(name: "Test", members: members)
        let ranking = summary.ranking(.intensityPerRevenue)
        XCTAssertEqual(ranking.map(\.member.name), ["Low", "Mid", "High"])
        XCTAssertEqual(ranking.first?.band, .leading)
        XCTAssertEqual(ranking.last?.band, .lagging)
        XCTAssertEqual(summary.reporting.count, 3)
        XCTAssertEqual(summary.coverage, 0.75, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.aggregateIntensityPerRevenue), 170.0 / 30.0, accuracy: 1e-9)
        XCTAssertTrue(summary.gaps.contains { $0.kind == .noFigures })
    }

    func testOutputIntensityNeedsOneUnit() {
        let members = [
            ClusterMember(clientID: UUID(), name: "A", size: .small, figures: figures(scope1: 1, scope2: 1, revenue: 1, output: 10, unit: "tonnes")),
            ClusterMember(clientID: UUID(), name: "B", size: .small, figures: figures(scope1: 1, scope2: 1, revenue: 1, output: 10, unit: "pieces")),
        ]
        let summary = ClusterBenchmark.summarize(name: "Mixed", members: members)
        XCTAssertFalse(summary.isComparable(.intensityPerOutput))
        XCTAssertTrue(summary.ranking(.intensityPerOutput).isEmpty)
        XCTAssertTrue(summary.gaps.contains { $0.kind == .mixedOutputUnits })
    }

    func testRenewableShareRanksHigherFirst() {
        var green = figures(scope1: 1, scope2: 1, revenue: 1)
        green.energyGJ = 100
        green.renewableEnergyGJ = 80
        var grey = figures(scope1: 1, scope2: 1, revenue: 1)
        grey.energyGJ = 100
        grey.renewableEnergyGJ = 10
        let summary = ClusterBenchmark.summarize(name: "RE", members: [
            ClusterMember(clientID: UUID(), name: "Grey", size: .small, figures: grey),
            ClusterMember(clientID: UUID(), name: "Green", size: .small, figures: green),
        ])
        XCTAssertEqual(summary.ranking(.renewableShare).first?.member.name, "Green")
    }

    func testClusterCSVHasOneRowPerMember() {
        let summary = ClusterBenchmark.summarize(name: "CSV", members: [
            ClusterMember(clientID: UUID(), name: "A, Ltd", size: .small, figures: figures(scope1: 44_200, scope2: 0, revenue: 2_450)),
            ClusterMember(clientID: UUID(), name: "B", size: .small, figures: nil),
        ])
        let rows = CSVText.parse(ClusterBenchmark.csv(summary))
        XCTAssertEqual(rows.count, 3)
        XCTAssertEqual(rows[1][0], "A, Ltd", "Commas in names are quoted")
        XCTAssertEqual(rows[1][3], "44200", "No scientific notation")
    }

    func testClusterSourceUsesLinkedEngagements() {
        var client = Client(name: "Linked")
        client.cluster = "X"
        let fy = engagement(client: client.id, year: 2025, current: [MetricID.scope1: 5, MetricID.scope2: 5, MetricID.revenue: 2])
        let summary = ClusterSource.summary(cluster: "x", clients: [client, Client(name: "Elsewhere")], engagements: [fy])
        XCTAssertEqual(summary.members.count, 1)
        XCTAssertEqual(summary.members.first?.figures?.intensityPerRevenue, 5)
    }
}
