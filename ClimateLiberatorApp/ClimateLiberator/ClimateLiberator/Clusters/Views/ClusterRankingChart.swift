import SwiftUI
import Charts

/// Horizontal bars per member, coloured by quartile band, with the cluster median.
struct ClusterRankingChart: View {
    let rows: [BenchmarkRow]
    let median: Double?
    let unit: String
    let accent: Color

    static func color(_ band: PerformanceBand) -> Color {
        switch band {
        case .leading: return DSStyle.good
        case .aboveMedian: return Color(red: 0.55, green: 0.80, blue: 0.70)
        case .belowMedian: return DSStyle.warning
        case .lagging: return DSStyle.bad
        }
    }

    var body: some View {
        Chart {
            ForEach(rows) { row in
                BarMark(x: .value(unit, row.value), y: .value("Client", row.member.name))
                    .foregroundStyle(Self.color(row.band))
                    .annotation(position: .trailing) {
                        Text(DisplayFormat.number(row.value)).font(.caption2.monospacedDigit()).foregroundStyle(DSStyle.subtle)
                    }
            }
            if let median {
                RuleMark(x: .value("Median", median))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Median").font(.caption2).foregroundStyle(DSStyle.subtle)
                    }
            }
        }
        .chartXAxisLabel(unit)
        .chartYAxis {
            AxisMarks { _ in AxisValueLabel().foregroundStyle(DSStyle.subtle) }
        }
        .chartXAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel().foregroundStyle(DSStyle.faint)
            }
        }
        .frame(height: max(140, CGFloat(rows.count) * 34 + 40))
        .accessibilityLabel("Ranking chart, \(rows.count) members")
    }
}
