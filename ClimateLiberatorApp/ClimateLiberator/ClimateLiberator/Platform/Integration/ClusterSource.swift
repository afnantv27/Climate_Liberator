import Foundation

/// Builds a cluster benchmark from the client register and the clients' KPI Data.
nonisolated enum ClusterSource {
    static func summary(cluster name: String, clients: [Client], engagements: [DisclosureEngagement]) -> ClusterSummary {
        let members = clients
            .filter { $0.clusterName.caseInsensitiveCompare(name) == .orderedSame }
            .map { client in
                ClusterMember(clientID: client.id, name: client.displayName, size: client.size,
                              figures: DisclosurePerformanceSource.latest(for: client.id, engagements: engagements))
            }
        return ClusterBenchmark.summarize(name: name, members: members)
    }
}
