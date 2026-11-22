import SwiftUI

struct TargetEditorSheet: View {
    @State var target: ReductionTarget
    let accent: Color
    let onSave: (ReductionTarget) -> Void
    @Environment(\.dismiss) private var dismiss

    private var yearsValid: Bool { target.targetYear > target.baseYear }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(target.name.isEmpty ? "Reduction Target" : target.name).font(.title2.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Name", width: 150) {
                    TextField("Optional, e.g. Near-term target 2030", text: $target.name).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Framework", width: 150) {
                    Picker("Framework", selection: $target.framework) {
                        ForEach(TargetFramework.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Covers", width: 150) {
                    Picker("Covers", selection: $target.coverage) {
                        ForEach(EmissionScopeCoverage.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 340)
                }
                DSFormRow("Type", width: 150) {
                    Picker("Type", selection: $target.kind) {
                        ForEach(TargetKind.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 420)
                }
                DSFormRow("Base year", width: 150) {
                    Stepper(value: $target.baseYear, in: 2010...2050) { Text(ReportingPeriod.label(target.baseYear)).monospacedDigit() }
                }
                DSFormRow("Target year", width: 150) {
                    Stepper(value: $target.targetYear, in: 2011...2070) { Text(ReportingPeriod.label(target.targetYear)).monospacedDigit() }
                }
                DSFormRow("Reduction", width: 150) {
                    HStack {
                        DSNumberField(placeholder: "%", value: target.reductionPercent,
                                      onCommit: { target.reductionPercent = min(100, max(0, $0 ?? 0)) }, width: 90)
                        Text("% below the base year").font(.caption).foregroundStyle(DSStyle.subtle)
                    }
                }
                DSFormRow("Base value", width: 150) {
                    HStack {
                        DSNumberField(placeholder: "From reports", value: target.baseValueOverride,
                                      onCommit: { target.baseValueOverride = $0 }, width: 140)
                        Text("Only if the baseline was recalculated; otherwise it is read from reported figures.")
                            .font(.caption).foregroundStyle(DSStyle.faint)
                    }
                }
                DSFormRow("Minimum rate", width: 150) {
                    HStack {
                        DSNumberField(placeholder: "%", value: target.minimumAnnualRate,
                                      onCommit: { target.minimumAnnualRate = max(0, $0 ?? 0) }, width: 90)
                        Text("% a year, linear (4.2% is SBTi's floor for Scope 1 + 2 at 1.5°C; check current criteria)")
                            .font(.caption).foregroundStyle(DSStyle.faint)
                    }
                }
                DSFormRow("Notes", width: 150) {
                    TextField("Board approval, boundary, exclusions", text: $target.notes, axis: .vertical)
                        .lineLimit(2...4).textFieldStyle(.roundedBorder)
                }
            }
            if !yearsValid {
                Label("The target year must be after the base year.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(DSStyle.bad)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(target)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!yearsValid)
            }
        }
        .padding(22)
        .frame(width: 720)
    }
}
