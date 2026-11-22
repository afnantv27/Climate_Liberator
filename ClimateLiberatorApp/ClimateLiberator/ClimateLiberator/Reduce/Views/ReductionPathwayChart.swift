import SwiftUI
import Charts

/// Reported values, the straight line to the target, and the projection from
/// committed measures.
struct ReductionPathwayChart: View {
    let points: [PathwayPoint]
    let unit: String
    let accent: Color

    private struct Mark: Identifiable {
        let year: Int
        let value: Double
        let series: String
        var id: String { "\(series)-\(year)" }
    }

    private var marks: [Mark] {
        points.flatMap { point -> [Mark] in
            var marks: [Mark] = []
            if let value = point.allowed { marks.append(Mark(year: point.year, value: value, series: "Target path")) }
            if let value = point.withMeasures { marks.append(Mark(year: point.year, value: value, series: "With measures")) }
            if let value = point.actual { marks.append(Mark(year: point.year, value: value, series: "Reported")) }
            return marks
        }
    }

    var body: some View {
        if marks.isEmpty {
            Text("The chart appears once the target has a base-year value.")
                .font(.callout).foregroundStyle(DSStyle.subtle)
        } else {
            Chart(marks) { mark in
                LineMark(x: .value("Year", mark.year), y: .value(unit, mark.value))
                    .foregroundStyle(by: .value("Series", mark.series))
                    .lineStyle(StrokeStyle(lineWidth: mark.series == "Reported" ? 2.5 : 1.5,
                                           dash: mark.series == "Target path" ? [5, 4] : []))
                if mark.series == "Reported" {
                    PointMark(x: .value("Year", mark.year), y: .value(unit, mark.value))
                        .foregroundStyle(by: .value("Series", mark.series))
                }
            }
            .chartForegroundStyleScale(["Reported": accent, "Target path": Color.white.opacity(0.7), "With measures": DSStyle.warning])
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 8)) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel {
                        if let year = value.as(Int.self) { Text("FY\(String(year % 100))") }
                    }
                    .foregroundStyle(DSStyle.faint)
                }
            }
            .chartYAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel().foregroundStyle(DSStyle.faint)
                }
            }
            .chartYAxisLabel(unit)
            .chartLegend(position: .bottom)
            .frame(height: 240)
        }
    }
}
