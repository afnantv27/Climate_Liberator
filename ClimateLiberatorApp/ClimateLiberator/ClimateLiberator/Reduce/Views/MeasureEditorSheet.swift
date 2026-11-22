import SwiftUI

struct MeasureEditorSheet: View {
    @State var measure: ReductionMeasure
    let accent: Color
    let onSave: (ReductionMeasure) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(measure.title.isEmpty ? "Reduction Measure" : measure.title).font(.title2.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Measure", width: 150) {
                    TextField("e.g. Rooftop solar 500 kWp", text: $measure.title).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Cuts", width: 150) {
                    Picker("Scope", selection: $measure.scope) {
                        ForEach(MeasureScope.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 300)
                }
                DSFormRow("Status", width: 150) {
                    Picker("Status", selection: $measure.status) {
                        ForEach(MeasureStatus.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 380)
                }
                DSFormRow("Starts cutting in", width: 150) {
                    Stepper(value: $measure.startYear, in: 2015...2060) { Text(ReportingPeriod.label(measure.startYear)).monospacedDigit() }
                }
                DSFormRow("Yearly cut", width: 150) {
                    numberRow(\.annualAbatement, unit: "tCO2e a year once running")
                }
                DSFormRow("Capital cost", width: 150) { numberRow(\.capitalCost, unit: "₹") }
                DSFormRow("Lifetime", width: 150) { numberRow(\.lifetimeYears, unit: "years (needed to spread capital cost)") }
                DSFormRow("Running cost", width: 150) { numberRow(\.annualOperatingCost, unit: "₹ a year") }
                DSFormRow("Savings", width: 150) { numberRow(\.annualSavings, unit: "₹ a year (energy, fuel, maintenance)") }
                DSFormRow("Owner", width: 150) {
                    TextField("Person or team", text: $measure.owner).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Notes", width: 150) {
                    TextField("Assumptions, vendor quotes, subsidies", text: $measure.notes, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(measure)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(measure.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(22)
        .frame(width: 640)
    }

    private func numberRow(_ path: WritableKeyPath<ReductionMeasure, Double?>, unit: String) -> some View {
        HStack {
            DSNumberField(placeholder: "—", value: measure[keyPath: path], onCommit: { measure[keyPath: path] = $0 }, width: 140)
            Text(unit).font(.caption).foregroundStyle(DSStyle.subtle)
        }
    }
}
