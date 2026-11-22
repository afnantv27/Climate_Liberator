import SwiftUI
import UniformTypeIdentifiers

/// Benchmark of one cluster: totals, member ranking on a chosen metric, data gaps.
struct ClusterView: View {
    @ObservedObject var registry: ClientRegistryStore
    @ObservedObject var disclosureStore: DisclosureStore
    let accent: Color
    /// Shows a member in the Clients tab.
    let openClient: (UUID) -> Void

    @State private var cluster: String?
    @State private var metric: BenchmarkMetric = .intensityPerRevenue

    var body: some View {
        if registry.clusters.isEmpty {
            DSEmptyState(systemImage: "circle.hexagongrid",
                         title: "No clusters yet",
                         message: "Type a cluster name on each client (for example the industrial cluster or programme they belong to). Clients with the same name are benchmarked together.") {
                Button("Load Example Cluster") { ExampleCluster.load(into: registry, disclosureStore: disclosureStore) }
            }
        } else {
            content(ClusterSource.summary(cluster: selectedCluster, clients: registry.clients,
                                          engagements: disclosureStore.engagements))
        }
    }

    private var selectedCluster: String {
        if let cluster, registry.clusters.contains(cluster) { return cluster }
        return registry.clusters[0]
    }

    private func content(_ summary: ClusterSummary) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toolbar(summary)
                ClusterTotalsRow(summary: summary)
                HStack(alignment: .top, spacing: 14) {
                    rankingCard(summary).frame(maxWidth: .infinity)
                    gapsCard(summary).frame(width: 320)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func toolbar(_ summary: ClusterSummary) -> some View {
        HStack(spacing: 10) {
            Picker("Cluster", selection: Binding(get: { selectedCluster }, set: { cluster = $0 })) {
                ForEach(registry.clusters, id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 320)
            Spacer()
            Button { export(summary) } label: { Label("Export CSV", systemImage: "square.and.arrow.up") }
                .help("One row per member with every benchmark metric")
        }
    }

    // MARK: Ranking

    private func rankingCard(_ summary: ClusterSummary) -> some View {
        let comparable = BenchmarkMetric.allCases.filter(summary.isComparable)
        let active = comparable.contains(metric) ? metric : .intensityPerRevenue
        let rows = summary.ranking(active)
        let unit = active.unit(outputUnit: summary.sharedOutputUnit)
        return DSCard("Ranking", subtitle: "Best first. Bands compare each member with the cluster's quartiles.") {
            Picker("Metric", selection: $metric) {
                ForEach(comparable) { Text($0.title).tag($0) }
            }
            .labelsHidden()
            .fixedSize()
        } content: {
            if rows.isEmpty {
                Text("No member reports this metric yet.").font(.callout).foregroundStyle(DSStyle.subtle)
            } else {
                ClusterRankingChart(rows: rows, median: summary.statistics(active)?.median, unit: unit, accent: accent)
                VStack(spacing: 4) {
                    ForEach(rows) { row in rankingRow(row, unit: unit) }
                }
            }
        }
    }

    private func rankingRow(_ row: BenchmarkRow, unit: String) -> some View {
        HStack(spacing: 10) {
            Text("\(row.rank)").font(.callout.monospacedDigit().weight(.semibold)).frame(width: 24)
            Button(row.member.name) { openClient(row.member.clientID) }
                .buttonStyle(.link)
                .lineLimit(1)
            Text(row.member.size.title).font(.caption).foregroundStyle(DSStyle.faint)
            Spacer()
            Text(DisplayFormat.value(row.value, unit: unit == "%" ? "%" : ""))
                .font(.callout.monospacedDigit())
            DSTag(text: row.band.title, color: ClusterRankingChart.color(row.band))
                .frame(width: 110, alignment: .trailing)
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(DSStyle.rowFill))
    }

    // MARK: Gaps

    private func gapsCard(_ summary: ClusterSummary) -> some View {
        DSCard("Data Gaps", subtitle: "What limits the comparison. Figures come from each member's KPI Data in Report.") {
            if summary.gaps.isEmpty {
                Label("Every member reports comparable figures.", systemImage: "checkmark.circle").foregroundStyle(DSStyle.good)
            }
            ForEach(summary.gaps, id: \.self) { gap in
                Label(gap.message, systemImage: gap.kind == .noFigures ? "tray" : "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(gap.kind == .noFigures ? DSStyle.subtle : DSStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    // MARK: Export

    private func export(_ summary: ClusterSummary) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = DisplayFormat.fileStem(summary.name) + "-benchmark.csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try ClusterBenchmark.csv(summary).write(to: url, atomically: true, encoding: .utf8)
            registry.statusMessage = "Exported the \(summary.name) benchmark to \(url.lastPathComponent)."
        } catch {
            registry.statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }
}

/// Headline numbers for the cluster.
struct ClusterTotalsRow: View {
    let summary: ClusterSummary

    var body: some View {
        HStack(spacing: 12) {
            DSMetricTile(title: "Members reporting", value: "\(summary.reporting.count) of \(summary.members.count)",
                         detail: DisplayFormat.percent(summary.coverage) + " coverage", systemImage: "person.3")
            DSMetricTile(title: "Scope 1 + 2", value: DisplayFormat.value(summary.totalScope12, unit: "tCO2e"),
                         detail: "Scope 1 \(DisplayFormat.number(summary.totalScope1)) · Scope 2 \(DisplayFormat.number(summary.totalScope2))",
                         systemImage: "smoke")
            DSMetricTile(title: "Cluster intensity", value: DisplayFormat.value(summary.aggregateIntensityPerRevenue, unit: ""),
                         detail: "tCO2e per ₹ crore, all members", systemImage: "chart.bar")
            DSMetricTile(title: "Energy", value: DisplayFormat.value(summary.totalEnergyGJ, unit: "GJ"),
                         detail: summary.fiscalYears.map { ReportingPeriod.label($0) }.joined(separator: ", "),
                         systemImage: "bolt")
        }
    }
}
