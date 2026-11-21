import SwiftUI
import Charts

/// Step 6: turns a scenario into a climate action plan — owner, timeline, cost per
/// tonne, funding and co-benefits for each measure, plus residual emissions and
/// credits reported the GPC way (Chapter 11, Section 4.4).
struct GPCActionPlanView: View {
    @ObservedObject var store: GPCInventoryStore
    let inventory: GPCInventory
    let accent: Color
    /// Shared with the Scenarios step.
    @Binding var selectedScenarioID: UUID?
    let openScenarios: () -> Void

    @State private var expandedMeasureID: String?
    @State private var showingMethod = false
    @State private var showingAllIssues = false

    private var scenarios: [DecarbonizationScenario] { inventory.decarbonizationScenarios }
    private var currentScenario: DecarbonizationScenario? {
        scenarios.first { $0.id == selectedScenarioID } ?? scenarios.first
    }

    var body: some View {
        if let scenario = currentScenario, !scenario.measures.isEmpty {
            content(PlanFigures(inventory: inventory, scenario: scenario))
        } else {
            GHGPanelCard(title: currentScenario == nil ? "No Scenario Yet" : "No Measures in This Scenario",
                         subtitle: "The action plan assigns owners, costs, funding and timelines to a scenario's measures. Build the pathway first.") {
                HStack(spacing: 10) {
                    Button {
                        openScenarios()
                    } label: {
                        Label("Go to Scenarios", systemImage: "chart.line.downtrend.xyaxis")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(accent)
                    if inventory.cityName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Iritty") == .orderedSame {
                        Button("Load Iritty Example Plan") {
                            let example = GPCExamplePathways.irittyPathway(for: inventory)
                            store.mutateSelected { $0.decarbonizationScenarios.append(example) }
                            selectedScenarioID = example.id
                        }
                        .help("A worked 2035 pathway with owners, timeline and funding (illustrative)")
                    }
                }
            }
        }
    }

    // MARK: Layout

    private func content(_ figures: PlanFigures) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    toolbar(figures.scenario)
                    metrics(figures)
                    if !figures.issues.isEmpty {
                        checksCard(figures) { measureID in
                            withAnimation(.easeInOut(duration: 0.15)) { expandedMeasureID = measureID }
                            withAnimation { proxy.scrollTo(measureID, anchor: .top) }
                        }
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 14) {
                            overviewColumn(figures).frame(minWidth: 560)
                            measuresColumn(figures).frame(width: 440)
                        }
                        VStack(spacing: 14) {
                            overviewColumn(figures)
                            measuresColumn(figures)
                        }
                    }
                }
                .padding(.bottom, 20)
            }
        }
    }

    private func overviewColumn(_ figures: PlanFigures) -> some View {
        let scenario = figures.scenario
        return VStack(spacing: 14) {
            GHGPanelCard(title: "Cost per Tonne Cut",
                         subtitle: "Marginal abatement cost in \(String(scenario.targetYear)): bars run from cheapest to dearest; width is tonnes cut.") {
                MACCurveChart(segments: figures.macSegments,
                              notCharted: figures.summary.notCharted.map { id in
                                  MACCurveChart.Excluded(id: id, reason: figures.summary.gaps[id]?.advice(targetYear: scenario.targetYear) ?? "")
                              },
                              currency: scenario.settings.currencyCode)
            }
            GHGPanelCard(title: "Delivery Timeline", subtitle: "Start year to full adoption, coloured by status.") {
                DeliveryTimeline(scenario: scenario, baseYear: figures.projection.baseYear)
            }
            GHGPanelCard(title: "Co-Benefits", subtitle: "Measures and target-year cut behind each benefit. Edit them per measure.") {
                coBenefitGrid(figures.coverage)
            }
            residualCard(figures)
        }
    }

    private func measuresColumn(_ figures: PlanFigures) -> some View {
        let scenario = figures.scenario
        let selections = scenario.measures.sorted {
            DecarbonizationMeasureCatalog.position(of: $0.measureID) < DecarbonizationMeasureCatalog.position(of: $1.measureID)
        }
        return GHGPanelCard(title: "Measures (\(selections.count))",
                            subtitle: "Assign an owner, costs and funding. Rollout years and adoption come from the scenario.") {
            VStack(spacing: 8) {
                ForEach(selections) { selection in
                    if let measure = DecarbonizationMeasureCatalog.measure(selection.measureID) {
                        PlanRow(measure: measure, selection: selection, economics: figures.economics[measure.id],
                                gap: figures.summary.gaps[measure.id], targetYear: scenario.targetYear,
                                currency: scenario.settings.currencyCode, accent: accent,
                                isExpanded: expandedMeasureID == measure.id,
                                toggle: {
                                    withAnimation(.easeInOut(duration: 0.15)) {
                                        expandedMeasureID = expandedMeasureID == measure.id ? nil : measure.id
                                    }
                                },
                                update: { change in updatePlan(scenario.id, measure.id, change) },
                                setAdoption: { share in updateSelection(scenario.id, measure.id) { $0.adoption = share } },
                                openScenarios: openScenarios)
                            .id(measure.id)
                    }
                }
            }
        }
    }

    // MARK: Plan checks

    /// Gaps and contradictions in the plan; each row opens the measure it is about.
    private func checksCard(_ figures: PlanFigures, open: @escaping (String) -> Void) -> some View {
        let issues = figures.issues
        let shown = showingAllIssues ? issues : Array(issues.prefix(Self.issuesShown))
        let affectingFigures = issues.filter(\.affectsFigures).count
        let subtitle = affectingFigures > 0
            ? "\(affectingFigures) change the figures; fix these first."
            : "Nothing changes the figures; these are missing details."
        return GHGPanelCard(title: "Plan Checks (\(issues.count))", subtitle: subtitle) {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(shown) { issue in
                    Button { open(issue.measureID) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: issue.affectsFigures ? "exclamationmark.triangle.fill" : "circle.dashed")
                                .foregroundStyle(issue.affectsFigures ? Color.orange : Color.secondary)
                                .frame(width: 16)
                            Text(DecarbonizationMeasureCatalog.measure(issue.measureID)?.title ?? issue.measureID)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                                .frame(width: 260, alignment: .leading)
                            Text(issue.message(targetYear: figures.scenario.targetYear))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Open this measure's plan")
                }
                if issues.count > Self.issuesShown {
                    Button(showingAllIssues ? "Show fewer" : "Show all \(issues.count)") { showingAllIssues.toggle() }
                        .buttonStyle(.borderless)
                        .font(.caption)
                }
            }
        }
    }

    private static let issuesShown = 5

    // MARK: Toolbar and metrics

    private func toolbar(_ scenario: DecarbonizationScenario) -> some View {
        let settings = scenario.settings
        return HStack(spacing: 12) {
            Picker("Scenario", selection: Binding(get: { scenario.id }, set: { selectedScenarioID = $0 })) {
                ForEach(scenarios) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            Text("Target \(String(scenario.targetYear))").font(.callout).foregroundStyle(.secondary)
            Divider().frame(height: 20)
            Picker("Currency", selection: Binding(get: { settings.currencyCode },
                                                  set: { code in updateSettings(scenario.id) { $0.currencyCode = code } })) {
                ForEach(["INR", "USD", "EUR"], id: \.self) { Text($0).tag($0) }
            }
            .frame(width: 140)
            HStack(spacing: 4) {
                Text("Discount rate").font(.callout)
                TextField("8", value: Binding(get: { settings.discountRate * 100 },
                                              set: { value in updateSettings(scenario.id) { $0.discountRate = min(max(value, 0), 30) / 100 } }),
                          format: .number.precision(.fractionLength(0...1)))
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 48)
                    .multilineTextAlignment(.trailing)
                Text("%").font(.caption).foregroundStyle(.secondary)
            }
            .help("Real discount rate for annualising capital costs. 8% is an assumption — use your organisation's rate.")
            Spacer()
            Button {
                store.exportActionPlan(scenarioID: scenario.id)
            } label: {
                Label("Export CSV", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(.borderedProminent)
            .tint(accent)
            Button { showingMethod.toggle() } label: { Image(systemName: "info.circle").imageScale(.large) }
                .buttonStyle(.borderless)
                .help("How the action plan is calculated")
                .popover(isPresented: $showingMethod, arrowEdge: .bottom) { methodNote }
        }
    }

    private func metrics(_ figures: PlanFigures) -> some View {
        let scenario = figures.scenario
        let summary = figures.summary
        let currency = scenario.settings.currencyCode
        let bau = figures.projection.target?.bauTonnes ?? figures.projection.baseTonnes
        return HStack(spacing: 12) {
            GHGMetricCard(title: "Cut in \(String(scenario.targetYear))", value: GHGFormat.tonnes(summary.totalCutTonnes),
                          detail: bau > 0 ? "\(GHGFormat.percent(summary.totalCutTonnes / bau)) of business as usual" : "")
            GHGMetricCard(title: "Capital Cost",
                          value: summary.totalCapitalCost > 0 ? DecarbonizationFormat.money(summary.totalCapitalCost, currency: currency) : "—",
                          detail: "\(summary.costedCount) of \(summary.measureCount) measures costed")
            GHGMetricCard(title: "Average Cost per Tonne",
                          value: summary.averageCostPerTonne.map { DecarbonizationFormat.perTonne($0, currency: currency) } ?? "—",
                          detail: summary.costedCutTonnes > 0 ? "Covers \(GHGFormat.percent(summary.costedShare)) of the cut" : "Enter costs per measure")
            GHGMetricCard(title: "Owners Assigned", value: "\(summary.ownersAssigned) of \(summary.measureCount)",
                          detail: "Funding identified for \(summary.fundingAssigned)")
        }
    }

    // MARK: Co-benefits

    private func coBenefitGrid(_ coverage: [CoBenefitCoverage]) -> some View {
        Group {
            if coverage.isEmpty {
                Text("No co-benefits selected yet.").font(.caption).foregroundStyle(.white.opacity(0.6))
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 170), spacing: 10)], alignment: .leading, spacing: 10) {
                    ForEach(coverage) { item in
                        HStack(spacing: 8) {
                            Image(systemName: item.benefit.systemImage)
                                .foregroundStyle(accent)
                                .frame(width: 20)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.benefit.title).font(.caption.weight(.semibold))
                                Text("\(item.measures) measure\(item.measures == 1 ? "" : "s") · \(GHGFormat.plain(item.tonnes)) t")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.white.opacity(0.05)))
                    }
                }
            }
        }
    }

    // MARK: Residual emissions and credits

    private func residualCard(_ figures: PlanFigures) -> some View {
        let scenario = figures.scenario
        let projection = figures.projection
        let residual = figures.residual
        let settings = scenario.settings
        let bau = projection.target?.bauTonnes ?? projection.baseTonnes
        let goal = scenario.goalTonnes(baseTonnes: projection.baseTonnes, bauTonnes: bau)
        let year = String(scenario.targetYear)
        return GHGPanelCard(title: "Residual Emissions and Credits",
                            subtitle: "GPC: gross emissions, removals and credits are reported separately; credits are never deducted from the inventory.") {
            VStack(spacing: 8) {
                residualRow("Gross emissions \(year)", unit: "t", emphasis: true) { valueText(GHGFormat.plain(residual.grossTonnes)) }
                residualRow("Removals inside the boundary", unit: "t") { valueText("−" + GHGFormat.plain(residual.removalsTonnes)) }
                residualRow("Net of removals", unit: "t", emphasis: true) { valueText(GHGFormat.plain(residual.netOfRemovals)) }
                Divider().overlay(Color.white.opacity(0.1))
                residualRow("Credits from outside the boundary", unit: "t") {
                    TextField("0", value: Binding(get: { settings.plannedCreditsTonnes },
                                                  set: { value in updateSettings(scenario.id) { $0.plannedCreditsTonnes = value.map { max(0, $0) } } }),
                              format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                }
                residualRow("Credit ceiling (share of gross)", unit: "%") {
                    TextField("None", value: Binding(get: { settings.creditCapShare.map { $0 * 100 } },
                                                     set: { value in updateSettings(scenario.id) { $0.creditCapShare = value.map { min(max($0, 0), 100) / 100 } } }),
                              format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.trailing)
                }
                .help("Maximum credits as a share of gross emissions. The GPC asks cities to cap credits and reduce them over time.")
                residualRow("Net with credits", unit: "t", emphasis: true) { valueText(GHGFormat.plain(residual.netWithCredits)) }
                if let goal, let label = scenario.goalLabel(baseYear: projection.baseYear) {
                    let gap = residual.netOfRemovals - goal
                    Label(gap <= 0.5 ? "Measures alone meet the goal (\(label))."
                                     : "\(GHGFormat.plain(gap)) t above the goal (\(label)) before credits.",
                          systemImage: gap <= 0.5 ? "checkmark.circle" : "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(gap <= 0.5 ? Color.green : Color.yellow)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if residual.exceedsCap {
                    Label("Planned credits exceed the ceiling of \(GHGFormat.plain(residual.creditCapTonnes ?? 0)) t.",
                          systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                Text("Use only credits that are additional, third-party verified and publicly registered (GPC Chapter 11).")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    /// Title on the left; value (text or field) and unit in fixed right-hand columns.
    private func residualRow<Value: View>(_ title: String, unit: String, emphasis: Bool = false,
                                          @ViewBuilder value: () -> Value) -> some View {
        HStack(spacing: 8) {
            Text(title).font(emphasis ? .callout.weight(.semibold) : .callout)
            Spacer(minLength: 8)
            value().frame(width: 110, alignment: .trailing)
            Text(unit).font(.caption).foregroundStyle(.secondary).frame(width: 16, alignment: .leading)
        }
        .frame(minHeight: 24)
    }

    private func valueText(_ text: String) -> some View {
        Text(text).font(.callout.monospacedDigit())
    }

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How the Action Plan Is Calculated").font(.headline)
            Text("Cost per tonne = (capital cost × capital recovery factor + yearly running cost − yearly savings) ÷ tonnes the measure cuts in the target year.")
            Text("The capital recovery factor spreads the investment over its lifetime at the discount rate. A negative cost per tonne means the measure saves money.")
            Text("Enter costs for the adoption level in the scenario, as full amounts in the plan currency (not lakh or crore). Costs are your inputs; the app does not estimate them.")
            Text("A measure appears on the cost curve only when it cuts emissions in the target year: adoption above 0% and a rollout that starts by then.")
            Text("Co-benefits, city influence and schemes start as suggestions. Scheme status changes; checked \(ActionPlanCatalog.schemesCheckedOn).")
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 380)
    }

    // MARK: Changes

    private func updateScenario(_ id: UUID, _ change: (inout DecarbonizationScenario) -> Void) {
        store.mutateSelected { inventory in
            var list = inventory.decarbonizationScenarios
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            change(&list[index])
            inventory.decarbonizationScenarios = list
        }
    }

    private func updateSettings(_ id: UUID, _ change: (inout ActionPlanSettings) -> Void) {
        updateScenario(id) { scenario in
            var settings = scenario.settings
            change(&settings)
            scenario.planSettings = settings
        }
    }

    /// Rollout and adoption belong to the scenario; the plan only offers a quick fix.
    private func updateSelection(_ scenarioID: UUID, _ measureID: String, _ change: (inout ScenarioMeasureSelection) -> Void) {
        updateScenario(scenarioID) { scenario in
            guard let index = scenario.measures.firstIndex(where: { $0.measureID == measureID }) else { return }
            change(&scenario.measures[index])
        }
    }

    private func updatePlan(_ scenarioID: UUID, _ measureID: String, _ change: (inout ActionPlanItem) -> Void) {
        updateScenario(scenarioID) { scenario in
            guard let index = scenario.measures.firstIndex(where: { $0.measureID == measureID }) else { return }
            var plan = scenario.measures[index].plan ?? ActionPlanItem()
            change(&plan)
            scenario.measures[index].plan = plan.isEmpty ? nil : plan
        }
    }
}

// MARK: - Figures

/// Everything the page shows, worked out once per change. (ViewThatFits builds both
/// layouts, so computing inside the columns would run the analysis twice.)
private struct PlanFigures {
    let scenario: DecarbonizationScenario
    let projection: ScenarioProjection
    let summary: ActionPlanSummary
    let economics: [String: MeasureEconomics]
    let macSegments: [MACSegment]
    let coverage: [CoBenefitCoverage]
    let residual: ResidualEmissions
    let issues: [PlanIssue]

    init(inventory: GPCInventory, scenario: DecarbonizationScenario) {
        let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: GPCInventorySummary.make(inventory))
        let projection = DecarbonizationEngine.project(baseline, scenario: scenario)
        let summary = ActionPlanAnalysis.summary(of: scenario, result: projection.target)
        self.scenario = scenario
        self.projection = projection
        self.summary = summary
        // Keep the first entry if a saved file ever lists a measure twice, rather than trapping.
        economics = Dictionary(summary.economics.map { ($0.measureID, $0) }, uniquingKeysWith: { first, _ in first })
        macSegments = ActionPlanAnalysis.macCurve(summary.economics)
        coverage = ActionPlanAnalysis.coBenefitCoverage(of: scenario, result: projection.target)
        residual = ActionPlanAnalysis.residualEmissions(of: scenario, result: projection.target)
        issues = ActionPlanAnalysis.issues(of: scenario, summary: summary,
                                           currentYear: Calendar.current.component(.year, from: Date()))
    }
}

// MARK: - Measure row

/// One measure's plan: a summary line, and an editor when expanded.
private struct PlanRow: View {
    let measure: DecarbonizationMeasure
    let selection: ScenarioMeasureSelection
    let economics: MeasureEconomics?
    /// Why there is no cost per tonne, if there is none.
    let gap: CostGap?
    let targetYear: Int
    let currency: String
    let accent: Color
    let isExpanded: Bool
    let toggle: () -> Void
    let update: ((inout ActionPlanItem) -> Void) -> Void
    let setAdoption: (Double) -> Void
    let openScenarios: () -> Void

    private var plan: ActionPlanItem { selection.plan ?? ActionPlanItem() }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if isExpanded { editor }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(isExpanded ? 0.07 : 0.04)))
    }

    private var header: some View {
        let cut = economics?.abatementTonnes ?? 0
        let owner = plan.owner.trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: measure.category.systemImage).foregroundStyle(measure.category.tint).frame(width: 18)
                Text(measure.title).font(.callout.weight(.semibold)).lineLimit(1)
                Spacer(minLength: 6)
                statusMenu
                Button(action: toggle) {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Hide plan details" : "Edit plan details")
            }
            HStack(spacing: 10) {
                Label(owner.isEmpty ? "No owner" : owner, systemImage: "person.crop.circle")
                    .foregroundStyle(owner.isEmpty ? Color.orange : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 6)
                Text(DecarbonizationFormat.cut(cut))
                    .foregroundStyle(cut < 0 ? MeasureCategory.addsEmissionsTint : Color.secondary)
                Text(economics?.costPerTonne.map { DecarbonizationFormat.perTonne($0, currency: currency) } ?? gap?.label ?? "No cost")
                    .foregroundStyle(costLabelColor)
                    .frame(minWidth: 70, alignment: .trailing)
                    .help(gap?.advice(targetYear: targetYear) ?? "Cost per tonne cut in \(String(targetYear))")
            }
            .font(.caption.monospacedDigit())
            .padding(.leading, 26)
        }
    }

    private var costLabelColor: Color {
        if economics?.costPerTonne != nil { return .primary }
        // A measure that does nothing, or costs entered without a result: worth a look.
        if let gap, gap == .noAdoption || (gap != .noCosts && plan.hasCosts) { return .orange }
        return Color.secondary.opacity(0.7)
    }

    private var statusMenu: some View {
        Menu {
            ForEach(ActionStatus.allCases) { status in
                Button(status.title) { update { $0.status = status } }
            }
        } label: {
            Text(plan.status.title)
                .font(.caption2.weight(.semibold))
                .padding(.vertical, 3)
                .padding(.horizontal, 8)
                .background(Capsule().fill(plan.status.tint.opacity(0.25)))
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .fixedSize()
        .help("Delivery status")
    }

    // MARK: Editor

    private var editor: some View {
        let suggestion = ActionPlanCatalog.suggestion(for: measure.id)
        let schemes = suggestion.schemeIDs.compactMap(ActionPlanCatalog.scheme)
        let benefits = plan.coBenefits ?? suggestion.coBenefits
        return VStack(alignment: .leading, spacing: 14) {
            section("Responsibility") {
                formRow("Owner") {
                    HStack(spacing: 6) {
                        TextField(ActionPlanCatalog.suggestedOwner(for: measure.category),
                                  text: Binding(get: { plan.owner }, set: { text in update { $0.owner = text } }))
                            .textFieldStyle(.roundedBorder)
                        Menu {
                            ForEach(ActionPlanCatalog.commonOwners, id: \.self) { owner in
                                Button(owner) { update { $0.owner = owner } }
                            }
                        } label: {
                            Image(systemName: "person.crop.circle.badge.plus")
                        }
                        .menuStyle(.button)
                        .buttonStyle(.borderless)
                        .fixedSize()
                        .help("Common owners")
                    }
                }
                formRow("Partners") {
                    TextField("Utilities, agencies, groups",
                              text: Binding(get: { plan.partners }, set: { text in update { $0.partners = text } }))
                        .textFieldStyle(.roundedBorder)
                }
                formRow("City influence") {
                    Picker("City influence", selection: Binding(get: { plan.influence ?? suggestion.influence },
                                                                set: { value in update { $0.influence = value } })) {
                        ForEach(CityInfluence.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .help((plan.influence ?? suggestion.influence).detail)
                }
                formRow("Rollout") {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(String(selection.startYear))–\(String(selection.fullYear)) at \(GHGFormat.percent(selection.adoption)) adoption (set in Scenarios)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let gap, gap.isAboutTheCut {
                            rolloutWarning(gap)
                        }
                    }
                }
            }
            section("Costs (\(currency))") {
                formRow("Capital cost") { numberField(plan.capitalCost, money: true) { value in update { $0.capitalCost = value } } }
                formRow("Lifetime") {
                    numberField(plan.lifetimeYears, digits: 0, unit: "years") { value in update { $0.lifetimeYears = value.map { max(0, $0) } } }
                }
                formRow("Yearly running") { numberField(plan.annualOperatingCost, money: true) { value in update { $0.annualOperatingCost = value } } }
                formRow("Yearly savings") { numberField(plan.annualSavings, money: true) { value in update { $0.annualSavings = value } } }
                formRow("Cost per tonne") { costSummary }
            }
            section("Funding") {
                formRow("Main source") {
                    Picker("Main source", selection: Binding(get: { plan.funding },
                                                             set: { value in update { $0.funding = value } })) {
                        Text("Not set").tag(FundingSource?.none)
                        ForEach(FundingSource.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                formRow("Scheme or budget") {
                    TextField("Scheme, budget line or lender",
                              text: Binding(get: { plan.fundingNote }, set: { text in update { $0.fundingNote = text } }))
                        .textFieldStyle(.roundedBorder)
                }
                if !schemes.isEmpty {
                    formRow("Possible schemes") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(schemes) { scheme in
                                HStack(spacing: 6) {
                                    if let url = URL(string: scheme.url) {
                                        Link(scheme.name, destination: url).font(.caption).lineLimit(1)
                                    }
                                    Spacer(minLength: 4)
                                    Button("Use") {
                                        update {
                                            $0.funding = .centralScheme
                                            $0.fundingNote = scheme.name
                                        }
                                    }
                                    .controlSize(.small)
                                }
                                .help("\(scheme.ministry): \(scheme.covers)")
                            }
                            Text("Checked \(ActionPlanCatalog.schemesCheckedOn); confirm eligibility.")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            section("Co-Benefits") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 124), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(CoBenefit.allCases) { benefit in
                        benefitChip(benefit, isOn: benefits.contains(benefit), current: benefits)
                    }
                }
                if plan.coBenefits == nil {
                    Text("Suggested. Click to change.").font(.caption2).foregroundStyle(.secondary)
                }
            }
            section("Notes") {
                TextField("Milestones, risks, dependencies", text: Binding(get: { plan.notes }, set: { text in update { $0.notes = text } }),
                          axis: .vertical)
                    .lineLimit(2...6)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding(.top, 6)
    }

    private func benefitChip(_ benefit: CoBenefit, isOn: Bool, current: Set<CoBenefit>) -> some View {
        Button {
            var next = current
            if isOn { next.remove(benefit) } else { next.insert(benefit) }
            update { $0.coBenefits = next }
        } label: {
            Label(benefit.title, systemImage: benefit.systemImage)
                .font(.caption2)
                .lineLimit(1)
                .padding(.vertical, 4)
                .padding(.horizontal, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Capsule().fill(isOn ? accent.opacity(0.25) : Color.white.opacity(0.05)))
                .overlay(Capsule().stroke(isOn ? accent.opacity(0.7) : Color.white.opacity(0.1), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private var costSummary: some View {
        Group {
            if let perTonne = economics?.costPerTonne {
                Text("\(DecarbonizationFormat.perTonne(perTonne, currency: currency))\(perTonne < 0 ? " (saves money)" : "")")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(perTonne < 0 ? Color.green : Color.primary)
            } else if let gap {
                Text(gap.isAboutTheCut ? "None: the measure \(gap == .addsEmissions ? "adds emissions" : "cuts nothing") in \(String(targetYear)). See Rollout."
                                       : gap.advice(targetYear: targetYear))
                    .font(.caption)
                    .foregroundStyle(gap == .needsLifetime || (gap.isAboutTheCut && plan.hasCosts) ? Color.orange : Color.secondary)
            } else {
                Text("Enter costs to calculate").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Why the measure cuts nothing, with a fix.
    private func rolloutWarning(_ gap: CostGap) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(gap.advice(targetYear: targetYear), systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(gap == .addsEmissions ? Color.secondary : Color.orange)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                if gap == .noAdoption {
                    Button("Use typical \(GHGFormat.percent(measure.defaultAdoption))") { setAdoption(measure.defaultAdoption) }
                        .help(measure.adoptionMeaning)
                }
                Button("Open Scenarios", action: openScenarios)
            }
            .controlSize(.small)
        }
    }

    private static let labelWidth: CGFloat = 112

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.5))
            content()
        }
    }

    /// Label column of fixed width, control column filling the rest — every row lines up.
    private func formRow<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `money`: echoes the amount in words ("₹56.5 lakh") so the scale of a typed number is clear.
    private func numberField(_ value: Double?, digits: Int = 2, unit: String? = nil, money: Bool = false,
                             set: @escaping (Double?) -> Void) -> some View {
        HStack(spacing: 6) {
            TextField("—", value: Binding(get: { value }, set: set),
                      format: .number.precision(.fractionLength(0...digits)))
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.trailing)
                .frame(width: 140)
            if let unit {
                Text(unit).font(.caption).foregroundStyle(.secondary)
            } else if money, let value {
                Text(DecarbonizationFormat.money(value, currency: currency)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - MAC curve

/// Marginal abatement cost curve: one bar per costed measure, cheapest first.
private struct MACCurveChart: View {
    /// A measure with costs entered that cannot be drawn, and why.
    struct Excluded: Identifiable {
        let id: String
        let reason: String
    }

    let segments: [MACSegment]
    let notCharted: [Excluded]
    let currency: String

    @State private var hoverTonnes: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if segments.isEmpty {
                Label("Enter a capital cost and lifetime, or yearly costs and savings, for measures to draw the curve.",
                      systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
            } else {
                curve
            }
            if !notCharted.isEmpty { excludedNote }
        }
    }

    /// Costed measures missing from the curve, so a typed-in cost never just vanishes.
    private var excludedNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Not on the chart").font(.caption.weight(.semibold)).foregroundStyle(.orange)
            ForEach(notCharted) { item in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(.orange)
                    Text(DecarbonizationMeasureCatalog.measure(item.id)?.title ?? item.id).font(.caption.weight(.semibold))
                    Text(item.reason).font(.caption).foregroundStyle(.secondary)
                }
                .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.orange.opacity(0.08)))
    }

    private var curve: some View {
        let total = max(segments.last?.endTonnes ?? 1, 1e-9)
        let gap = total * 0.004
        let hovered = hoverTonnes.flatMap { tonnes in segments.first { tonnes >= $0.startTonnes && tonnes <= $0.endTonnes } }
        return VStack(alignment: .leading, spacing: 10) {
            Chart {
                ForEach(segments) { segment in
                    let measure = DecarbonizationMeasureCatalog.measure(segment.measureID)
                    RectangleMark(xStart: .value("From", segment.startTonnes + gap),
                                  xEnd: .value("To", max(segment.startTonnes + gap, segment.endTonnes - gap)),
                                  yStart: .value("Zero", 0.0),
                                  yEnd: .value("Cost per tonne", segment.costPerTonne))
                        .foregroundStyle((measure?.category.tint ?? .gray).opacity(hovered == nil || hovered?.id == segment.id ? 0.9 : 0.4))
                }
                RuleMark(y: .value("Zero", 0.0)).foregroundStyle(.white.opacity(0.35))
                if let hovered {
                    RuleMark(x: .value("Measure", (hovered.startTonnes + hovered.endTonnes) / 2))
                        .foregroundStyle(.clear)
                        .annotation(position: .top, spacing: 0,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .fit(to: .chart))) {
                            tooltip(hovered)
                        }
                }
            }
            .chartXScale(domain: 0...total)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 5)) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel {
                        if let tonnes = value.as(Double.self) { Text(tonnes.formatted(.number.notation(.compactName))) }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine().foregroundStyle(.white.opacity(0.08))
                    AxisValueLabel {
                        if let cost = value.as(Double.self) {
                            Text(DecarbonizationFormat.currencySymbol(currency) + cost.formatted(.number.notation(.compactName)))
                        }
                    }
                }
            }
            .chartXAxisLabel("tCO2e cut in the target year", alignment: .center)
            .chartYAxisLabel("per tCO2e", position: .trailing)
            .chartXSelection(value: $hoverTonnes)
            .frame(height: 220)
            legend
        }
    }

    /// Ranked list under the chart instead of crowded labels on it.
    private var legend: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(segments.enumerated()), id: \.element.id) { index, segment in
                let measure = DecarbonizationMeasureCatalog.measure(segment.measureID)
                HStack(spacing: 8) {
                    Text("\(index + 1)").font(.caption2.monospacedDigit()).foregroundStyle(.secondary).frame(width: 16, alignment: .trailing)
                    RoundedRectangle(cornerRadius: 2).fill(measure?.category.tint ?? .gray).frame(width: 10, height: 10)
                    Text(measure?.title ?? segment.measureID).font(.caption).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(DecarbonizationFormat.perTonne(segment.costPerTonne, currency: currency))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(segment.costPerTonne < 0 ? Color.green : Color.primary)
                        .frame(width: 100, alignment: .trailing)
                    Text("\(GHGFormat.plain(segment.widthTonnes)) t")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 80, alignment: .trailing)
                }
            }
        }
    }

    private func tooltip(_ segment: MACSegment) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(DecarbonizationMeasureCatalog.measure(segment.measureID)?.title ?? segment.measureID).font(.caption.weight(.semibold))
            Text(DecarbonizationFormat.perTonne(segment.costPerTonne, currency: currency))
            Text("\(GHGFormat.plain(segment.widthTonnes)) t cut").foregroundStyle(.secondary)
        }
        .font(.caption2.monospacedDigit())
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.8)))
    }
}

// MARK: - Timeline

/// Gantt-style rollout: a fixed title column, bars on a shared year grid, the
/// rollout years at the right, and a line for today.
private struct DeliveryTimeline: View {
    let scenario: DecarbonizationScenario
    let baseYear: Int

    private static let iconWidth: CGFloat = 16
    private static let titleWidth: CGFloat = 220
    private static let yearsWidth: CGFloat = 78
    private static let spacing: CGFloat = 12
    private static let rowHeight: CGFloat = 22
    private static let rowSpacing: CGFloat = 10
    private static let barHeight: CGFloat = 12

    private struct Row: Identifiable {
        let id: String
        let title: String
        let category: MeasureCategory?
        let start: Int
        let full: Int
        let status: ActionStatus
    }

    private var sortedRows: [Row] {
        scenario.measures
            .sorted { ($0.startYear, $0.fullYear, DecarbonizationMeasureCatalog.position(of: $0.measureID))
                < ($1.startYear, $1.fullYear, DecarbonizationMeasureCatalog.position(of: $1.measureID)) }
            .map { selection in
                let measure = DecarbonizationMeasureCatalog.measure(selection.measureID)
                return Row(id: selection.measureID, title: measure?.title ?? selection.measureID, category: measure?.category,
                           start: selection.startYear, full: max(selection.fullYear, selection.startYear),
                           status: selection.plan?.status ?? .proposed)
            }
    }

    var body: some View {
        let rows = sortedRows
        // Year columns from the base year (or earliest start) to the target year, inclusive.
        let first = min(baseYear, rows.map(\.start).min() ?? baseYear)
        let last = max(scenario.targetYear, rows.map(\.full).max() ?? scenario.targetYear)
        let columns = last - first + 1
        let labelStep = columns <= 12 ? 1 : columns <= 24 ? 2 : 5
        let now = Self.fractionalYear(Date())

        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: Self.rowSpacing) {
                ForEach(rows) { row in
                    rowView(row, first: first, columns: columns)
                }
            }
            .background {
                // Year grid and today's line, drawn once behind every row.
                GeometryReader { proxy in
                    let track = Self.trackRange(width: proxy.size.width)
                    let yearWidth = (track.upperBound - track.lowerBound) / CGFloat(columns)
                    Path { path in
                        for index in 0...columns {
                            let x = track.lowerBound + CGFloat(index) * yearWidth
                            path.move(to: CGPoint(x: x, y: 0))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height))
                        }
                    }
                    .stroke(Color.white.opacity(0.07), lineWidth: 1)
                    if now >= Double(first), now <= Double(last + 1) {
                        let x = track.lowerBound + CGFloat(now - Double(first)) * yearWidth
                        Path { path in
                            path.move(to: CGPoint(x: x, y: -4))
                            path.addLine(to: CGPoint(x: x, y: proxy.size.height + 4))
                        }
                        .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    }
                }
            }
            axis(first: first, columns: columns, step: labelStep)
            legend
        }
    }

    private func rowView(_ row: Row, first: Int, columns: Int) -> some View {
        HStack(spacing: Self.spacing) {
            Image(systemName: row.category?.systemImage ?? "circle")
                .font(.caption)
                .foregroundStyle(row.category?.tint ?? .gray)
                .frame(width: Self.iconWidth)
            Text(row.title)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.titleWidth, alignment: .leading)
            GeometryReader { proxy in
                let yearWidth = proxy.size.width / CGFloat(columns)
                let x = CGFloat(row.start - first) * yearWidth
                let width = CGFloat(row.full - row.start + 1) * yearWidth
                Capsule()
                    .fill(row.status.tint.gradient)
                    .frame(width: max(width - 4, 6), height: Self.barHeight)
                    .offset(x: x + 2, y: (proxy.size.height - Self.barHeight) / 2)
            }
            .frame(height: Self.rowHeight)
            Text(row.start == row.full ? String(row.start) : "\(String(row.start))–\(String(row.full).suffix(2))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Self.yearsWidth, alignment: .trailing)
        }
        .frame(height: Self.rowHeight)
        .help("\(row.title): \(row.status.title), \(String(row.start))–\(String(row.full))")
    }

    /// Year labels centred under each column of the track.
    private func axis(first: Int, columns: Int, step: Int) -> some View {
        GeometryReader { proxy in
            let track = Self.trackRange(width: proxy.size.width)
            let yearWidth = (track.upperBound - track.lowerBound) / CGFloat(columns)
            ForEach(Array(stride(from: 0, to: columns, by: step)), id: \.self) { index in
                Text(String(first + index))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .fixedSize()
                    .position(x: track.lowerBound + (CGFloat(index) + 0.5) * yearWidth, y: 8)
            }
        }
        .frame(height: 16)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(ActionStatus.allCases) { status in
                HStack(spacing: 6) {
                    Capsule().fill(status.tint).frame(width: 14, height: 8)
                    Text(status.title)
                }
            }
            HStack(spacing: 6) {
                Rectangle()
                    .stroke(Color.white.opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [3, 2]))
                    .frame(width: 1, height: 10)
                Text("Today")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    /// Horizontal extent of the bar track inside a row of the given width.
    private static func trackRange(width: CGFloat) -> ClosedRange<CGFloat> {
        let leading = iconWidth + spacing + titleWidth + spacing
        let trailing = spacing + yearsWidth
        return leading...max(leading + 1, width - trailing)
    }

    /// The year with a fraction for the day, e.g. 2026.89 on 21 November 2026.
    private static func fractionalYear(_ date: Date) -> Double {
        let calendar = Calendar.current
        let year = calendar.component(.year, from: date)
        let day = Double(calendar.ordinality(of: .day, in: .year, for: date) ?? 1)
        let days = Double(calendar.range(of: .day, in: .year, for: date)?.count ?? 365)
        return Double(year) + (day - 1) / days
    }
}
