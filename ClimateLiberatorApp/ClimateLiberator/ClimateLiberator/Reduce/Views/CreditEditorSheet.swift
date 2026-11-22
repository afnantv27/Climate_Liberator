import SwiftUI

struct CreditEditorSheet: View {
    @State var credit: CarbonCredit
    let accent: Color
    let onSave: (CarbonCredit) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(credit.projectName.isEmpty ? "Carbon Credits" : credit.projectName).font(.title2.weight(.semibold))
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Project", width: 140) {
                    HStack {
                        TextField("Project name", text: $credit.projectName).textFieldStyle(.roundedBorder)
                        TextField("Registry ID", text: $credit.projectID).textFieldStyle(.roundedBorder).frame(width: 140)
                    }
                }
                DSFormRow("Registry", width: 140) {
                    Picker("Registry", selection: $credit.registry) {
                        ForEach(CreditRegistry.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Type", width: 140) {
                    HStack {
                        Picker("Type", selection: $credit.projectType) {
                            ForEach(CreditProjectType.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                        DSTag(text: credit.projectType.isRemoval ? "Removal" : "Avoidance / reduction",
                              color: credit.projectType.isRemoval ? DSStyle.good : DSStyle.info)
                    }
                }
                DSFormRow("Country", width: 140) {
                    TextField("Country", text: $credit.country).textFieldStyle(.roundedBorder).frame(width: 200)
                }
                DSFormRow("Vintage", width: 140) {
                    Stepper(value: $credit.vintageYear, in: 2000...2060) { Text(String(credit.vintageYear)).monospacedDigit() }
                }
                DSFormRow("Quantity", width: 140) {
                    HStack {
                        DSNumberField(placeholder: "tCO2e", value: credit.quantity, onCommit: { credit.quantity = max(0, $0 ?? 0) }, width: 140)
                        Text("tCO2e").font(.caption).foregroundStyle(DSStyle.subtle)
                        DSNumberField(placeholder: "₹ per t", value: credit.unitPrice, onCommit: { credit.unitPrice = $0 }, width: 110)
                        Text("₹ per tonne").font(.caption).foregroundStyle(DSStyle.subtle)
                    }
                }
                DSFormRow("Status", width: 140) {
                    Picker("Status", selection: $credit.status) {
                        ForEach(CreditStatus.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 300)
                }
                if credit.status == .retired {
                    DSFormRow("Retired on", width: 140) {
                        DatePicker("Retired on", selection: Binding(get: { credit.retirementDate ?? Date() },
                                                                   set: { credit.retirementDate = $0 }),
                                   displayedComponents: .date)
                            .labelsHidden()
                    }
                    DSFormRow("Claimed for", width: 140) {
                        Picker("Year", selection: Binding(get: { credit.retiredForYear ?? credit.vintageYear },
                                                          set: { credit.retiredForYear = $0 })) {
                            ForEach((2015...2060).reversed(), id: \.self) { Text(ReportingPeriod.label($0)).tag($0) }
                        }
                        .labelsHidden().fixedSize()
                    }
                }
                DSFormRow("Serial numbers", width: 140) {
                    TextField("Range or list from the registry", text: $credit.serialNumbers, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Evidence", width: 140) {
                    TextField("Registry retirement link or invoice path", text: $credit.evidence).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Notes", width: 140) {
                    TextField("Co-benefits, ratings, purchase terms", text: $credit.notes, axis: .vertical)
                        .lineLimit(1...3).textFieldStyle(.roundedBorder)
                }
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    var saved = credit
                    if saved.status == .retired {
                        saved.retirementDate = saved.retirementDate ?? Date()
                        saved.retiredForYear = saved.retiredForYear ?? saved.vintageYear
                    }
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(credit.quantity <= 0)
            }
        }
        .padding(22)
        .frame(width: 680)
    }
}
