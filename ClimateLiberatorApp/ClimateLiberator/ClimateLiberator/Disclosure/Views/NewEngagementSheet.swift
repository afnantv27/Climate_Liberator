import SwiftUI

/// Starts an engagement: client, financial year and frameworks, with the
/// applicability rules suggesting the scope.
struct NewEngagementSheet: View {
    let accent: Color
    let onCreate: (String, Int, Set<DisclosureFramework>, Bool, Int?, IndustrySector) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var year = NewEngagementSheet.lastCompletedYear()
    @State private var isListed = true
    @State private var rankText = ""
    @State private var sector: IndustrySector = .manufacturing
    @State private var frameworks: Set<DisclosureFramework> = [.brsr]
    @State private var userChoseFrameworks = false

    /// First year of the latest financial year that has ended (Indian April–March year).
    static func lastCompletedYear(today: Date = Date()) -> Int {
        let parts = Calendar(identifier: .gregorian).dateComponents([.year, .month], from: today)
        let year = parts.year ?? 2025
        return (parts.month ?? 1) >= 4 ? year - 1 : year - 2
    }

    private var rank: Int? { Int(rankText.trimmingCharacters(in: .whitespaces)) }

    private var findings: [ApplicabilityRules.Finding] {
        var profile = CompanyProfile()
        profile.isListed = isListed
        profile.marketCapRank = rank
        profile.sector = sector
        return ApplicabilityRules.assess(profile, fiscalYearStart: year)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("New Client Engagement").font(.title2.weight(.semibold))
                Text("One engagement is one company and one financial year.").font(.callout).foregroundStyle(DSStyle.subtle)
            }
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Company", width: 130) {
                    TextField("Legal name", text: $name).textFieldStyle(.roundedBorder)
                }
                DSFormRow("Financial year", width: 130) {
                    Stepper(value: $year, in: 2021...2040) { Text(ReportingPeriod.label(year)).monospacedDigit() }
                }
                DSFormRow("Sector", width: 130) {
                    Picker("Sector", selection: $sector) {
                        ForEach(IndustrySector.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().fixedSize()
                }
                DSFormRow("Listed in India", width: 130) {
                    Toggle("", isOn: $isListed).labelsHidden()
                }
                if isListed {
                    DSFormRow("Market-cap rank", width: 130) {
                        HStack {
                            TextField("e.g. 420", text: $rankText).textFieldStyle(.roundedBorder).frame(width: 90)
                            Text("from the exchange list at 31 March").font(.caption).foregroundStyle(DSStyle.faint)
                        }
                    }
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("SCOPE").font(.caption2.weight(.semibold)).foregroundStyle(DSStyle.faint)
                ForEach(findings) { finding in
                    Toggle(isOn: Binding(get: { frameworks.contains(finding.framework) }, set: { value in
                        userChoseFrameworks = true
                        if value { _ = frameworks.insert(finding.framework) } else { _ = frameworks.remove(finding.framework) }
                        if value && finding.framework == .brsrCore { _ = frameworks.insert(.brsr) }
                    })) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(finding.framework.title).font(.callout.weight(.medium))
                                DSTag(text: finding.requirement.title,
                                      color: finding.requirement == .mandatory ? IssueSeverity.blocker.tint : DSStyle.subtle)
                            }
                            Text(finding.reason).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .toggleStyle(.checkbox)
                }
                Text("Rules checked \(ApplicabilityRules.rulesCheckedOn). SEBI and ISSB requirements change; confirm before relying on them.")
                    .font(.caption2).foregroundStyle(DSStyle.faint)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Create") {
                    onCreate(name, year, frameworks, isListed, isListed ? rank : nil, sector)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || frameworks.isEmpty)
            }
        }
        .padding(24)
        .frame(width: 600)
        .onAppear(perform: suggestScope)
        .onChange(of: year) { _, _ in suggestScope() }
        .onChange(of: isListed) { _, _ in suggestScope() }
        .onChange(of: rankText) { _, _ in suggestScope() }
    }

    /// Ticks the mandatory frameworks until the user picks their own.
    private func suggestScope() {
        guard !userChoseFrameworks else { return }
        let mandatory = Set(findings.filter { $0.requirement == .mandatory }.map(\.framework))
        frameworks = mandatory.isEmpty ? [.brsr] : mandatory
    }
}
