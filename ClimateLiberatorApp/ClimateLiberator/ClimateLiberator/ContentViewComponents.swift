import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

struct SimulationStatsBuilder {
    let index: Int
    var weatherFile: String?
    var ignitionCell: Int?
    var totalCells: Int?
    var available: Int?
    var burnt: Int?
    var nonBurnable: Int?
    var firebreak: Int?
}

struct ExportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

struct SettingRow<Content: View>: View {
    let title: String
    let theme: ThemeStyle
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(theme.subtleTextColor)
            HStack(spacing: 8) {
                content()
            }
        }
    }
}

struct DashboardView: View {
    let summaries: [RunSummary]
    let theme: ThemeStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let latest = summaries.first {
                    DashboardSummaryCard(summary: latest,
                                         theme: theme,
                                         title: "Latest Run")
                    .padding(.bottom, 24)
                } else {
                    Text("No simulations have been captured yet.")
                        .foregroundColor(theme.subtleTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if summaries.count > 1 {
                    Text("Run History")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    VStack(spacing: 12) {
                        ForEach(Array(summaries.dropFirst())) { summary in
                            HistoryRow(summary: summary, theme: theme)
                        }
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(colors: theme.gradient,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("Run Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 560)
    }
}

struct LogViewer: View {
    let logText: String
    let logURL: URL?
    let theme: ThemeStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(logText.isEmpty ? "No simulation log entries yet." : logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassBackground(material: theme.material,
                                     tint: theme.cardBackground,
                                     cornerRadius: 18,
                                     strokeColor: theme.borderColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding()
            .background(
                LinearGradient(colors: theme.gradient,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("Run Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let logURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: logURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

struct DashboardSummaryCard: View {
    let summary: RunSummary
    let theme: ThemeStyle
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(summary.timestamp, style: .date)
                .font(.title3).bold()
            Text(summary.timestamp, style: .time)
                .font(.subheadline)
                .foregroundColor(theme.subtleTextColor)

            ForEach(summary.simulations) { stats in
                SimulationDisclosure(stats: stats, theme: theme)
            }
        }
        .padding()
        .glassBackground(material: theme.material,
                         tint: theme.cardBackground,
                         cornerRadius: 26,
                         strokeColor: theme.borderColor)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: theme.shadowColor, radius: 8, x: 0, y: 6)
    }
}

struct SimulationDisclosure: View {
    let stats: SimulationStats
    let theme: ThemeStyle
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 6) {
                StatsRow(label: "Total Cells", value: formattedCount(stats.resolvedTotal))
                StatsRow(label: "Ignition Point", value: formattedCount(stats.ignitionCell))
                StatsRow(label: "Available", value: formattedCount(stats.available))
                StatsRow(label: "Burnt", value: formattedCount(stats.burnt))
                StatsRow(label: "Non-burnable", value: formattedCount(stats.nonBurnable))
                StatsRow(label: "Firebreak", value: formattedCount(stats.firebreak))
                StatsRow(label: "Highest ROS", value: formattedROS(stats.highestROS))
                StatsRow(label: "Lowest ROS", value: formattedROS(stats.lowestROS))
            }
            .padding(.top, 6)
        } label: {
            Text("Simulation \(stats.simulationIndex) Stats")
                .font(.subheadline).bold()
        }
        .tint(theme.accentColor)
        .padding(.vertical, 6)
    }
}

struct StatsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

struct OutputTreeRow: View {
    let node: OutputNode
    let theme: ThemeStyle
    let isSelected: Bool
    let onSelect: () -> Void
    let onZoom: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.iconName)
                .foregroundColor(node.isDirectory ? theme.subtleTextColor : theme.accentColor)
            Text(node.name)
                .lineLimit(1)
            Spacer()
        }
        .font(.subheadline)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(theme.textColor)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? theme.accentColor.opacity(0.28) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isSelectable {
                onSelect()
            }
        }
        .contextMenu {
            if node.isSelectable {
                Button("Display Layer") { onSelect() }
                Button("Zoom In") { onZoom() }
            }
        }
    }
}

struct ROSLegendView: View {
    let palette: RateOfSpreadPalette
    let minValue: Double
    let maxValue: Double
    let opacity: Double

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Rate of Spread")
                .font(.caption).bold()
            VStack(spacing: 4) {
                Text(String(format: "Max %.2f", maxValue))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Spacer()
                    LinearGradient(gradient: Gradient(colors: palette.gradientColors),
                                   startPoint: .bottom,
                                   endPoint: .top)
                        .frame(width: 28, height: 140)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                    Spacer()
                }
                Text(String(format: "Min %.2f", minValue))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
            }
            Text(String(format: "Opacity: %.0f%%", opacity * 100))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .multilineTextAlignment(.center)
        .padding(12)
        .frame(maxWidth: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .foregroundColor(.white)
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 8)
    }
}

struct MapModeButton: View {
    let icon: String
    let label: String
    let active: Bool
    let theme: ThemeStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 52, height: 52)
            .foregroundColor(.white)
            .background(
                Circle()
                    .fill(active ? theme.accentColor : Color.black.opacity(0.45))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct InspectResult: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let value: Double
}

struct IgnitionMarker: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

