import SwiftUI

/// Carbon credits bought, held and retired for the client, with integrity checks.
/// Shown beside emissions, never subtracted from them.
struct CreditsView: View {
    let context: ReducePlanContext

    @State private var editing: CarbonCredit?
    @State private var claimYear: Int?

    private var ledger: CreditLedger { CreditLedger(credits: context.plan.credits) }

    private var years: [Int] {
        let claimed = context.plan.credits.compactMap(\.retiredForYear)
        let reported = context.history.map(\.fiscalYearStart)
        return Array(Set(claimed + reported)).sorted(by: >)
    }

    private var year: Int { claimYear ?? years.first ?? context.defaultYear }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                claimCard
                registerCard
                if !ledger.issues.isEmpty { issuesCard }
            }
            .padding(.bottom, 16)
        }
        .sheet(item: $editing) { credit in
            CreditEditorSheet(credit: credit, accent: context.accent) { saved in
                context.store.upsertCredit(saved, client: context.clientID, name: context.clientName)
            }
        }
    }

    // MARK: Claim

    private var claimCard: some View {
        let figures = context.history.first { $0.fiscalYearStart == year }
        let emissions = figures?.scope12
        let retired = ledger.retiredQuantity(forYear: year)
        return DSCard("Retirements Against Emissions",
                      subtitle: "Report gross emissions and credits separately. Any neutrality claim should rest on a reduction plan first, with credits only for what remains.") {
            if !years.isEmpty {
                Picker("Year", selection: Binding(get: { year }, set: { claimYear = $0 })) {
                    ForEach(years, id: \.self) { Text(ReportingPeriod.label($0)).tag($0) }
                }
                .labelsHidden()
                .fixedSize()
            }
        } content: {
            HStack(spacing: 12) {
                DSMetricTile(title: "Scope 1 + 2 emissions", value: DisplayFormat.value(emissions, unit: "tCO2e"),
                             detail: figures?.source ?? "Not reported", systemImage: "smoke")
                DSMetricTile(title: "Credits retired", value: DisplayFormat.value(retired, unit: "tCO2e"),
                             detail: ledger.removalShare(forYear: year).map { "\(DisplayFormat.percent($0)) removals" } ?? "",
                             systemImage: "checkmark.seal")
                DSMetricTile(title: "Coverage", value: ledger.coverage(ofEmissions: emissions, forYear: year).map(DisplayFormat.percent) ?? "—",
                             detail: "of Scope 1 + 2", systemImage: "chart.pie")
                DSMetricTile(title: "Held, not retired", value: DisplayFormat.value(ledger.held, unit: "tCO2e"),
                             detail: ledger.spend > 0 ? "₹ \(DisplayFormat.number(ledger.spend)) spent in total" : "",
                             systemImage: "tray.full")
            }
        }
    }

    // MARK: Register

    private var registerCard: some View {
        DSCard("Credit Register") {
            Button {
                editing = CarbonCredit(vintageYear: context.defaultYear)
            } label: {
                Label("Add Credits", systemImage: "plus")
            }
        } content: {
            if context.plan.credits.isEmpty {
                Text("No credits recorded. Add each purchase with registry, project, vintage, quantity and serial numbers.")
                    .font(.callout).foregroundStyle(DSStyle.subtle)
            }
            VStack(spacing: 6) {
                ForEach(context.plan.credits.sorted { $0.vintageYear > $1.vintageYear }) { credit in row(credit) }
            }
        }
    }

    private func row(_ credit: CarbonCredit) -> some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(credit.displayName).font(.callout.weight(.medium))
                    if credit.projectType.isRemoval { DSTag(text: "Removal", color: DSStyle.good) }
                }
                Text([credit.registry.title, credit.projectType.title, "vintage \(credit.vintageYear)",
                      credit.retiredForYear.map { "claimed for \(ReportingPeriod.label($0))" } ?? ""]
                        .filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption).foregroundStyle(DSStyle.subtle)
            }
            Spacer()
            DSTag(text: credit.status.title, color: credit.status == .retired ? DSStyle.good : credit.status == .held ? DSStyle.info : DSStyle.faint)
            Text(DisplayFormat.value(credit.quantity, unit: "t")).font(.callout.monospacedDigit()).frame(width: 90, alignment: .trailing)
            Button { editing = credit } label: { Image(systemName: "pencil") }.buttonStyle(.borderless)
            Button {
                context.store.removeCredit(credit.id, client: context.clientID, name: context.clientName)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(DSStyle.rowFill))
    }

    private var issuesCard: some View {
        DSCard("Check Before Any Claim") {
            ForEach(ledger.issues, id: \.self) { issue in
                Label(issue.message, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(DSStyle.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
