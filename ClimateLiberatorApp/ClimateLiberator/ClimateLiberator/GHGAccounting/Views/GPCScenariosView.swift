import SwiftUI
import Charts

/// Step 5: decarbonisation pathways for the selected inventory — business as usual
/// versus a scenario of measures, with each measure's share of the cut.
struct GPCScenariosView: View {
    @ObservedObject var store: GPCInventoryStore
    let inventory: GPCInventory
    let accent: Color
    /// Shared with the Action Plan step, so both show the same scenario.
    @Binding var selectedScenarioID: UUID?

    @State private var showingLibrary = false
    @State private var showingGrowth = false
    @State private var showingMethod = false
    @State private var expandedMeasureID: String?
    @State private var renameDraft: String?

    private var scenarios: [DecarbonizationScenario] { inventory.decarbonizationScenarios }
    private var isIritty: Bool { inventory.cityName.trimmingCharacters(in: .whitespaces).caseInsensitiveCompare("Iritty") == .orderedSame }
    private var currentScenario: DecarbonizationScenario? {
        scenarios.first { $0.id == selectedScenarioID } ?? scenarios.first
    }

    var body: some View {
        let summary = GPCInventorySummary.make(inventory)
        let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: summary)
        Group {
            if baseline.lines.isEmpty {
                GHGPanelCard(title: "No Emissions to Project",
                             subtitle: "Add activity data first. Scenarios start from the inventory's \(inventory.targetLevel.title) total.") { EmptyView() }
            } else if let scenario = currentScenario {
                let projection = DecarbonizationEngine.project(baseline, scenario: scenario)
                scenarioContent(scenario, baseline: baseline, projection: projection)
                    .sheet(isPresented: $showingLibrary) {
                        MeasureLibrarySheet(baseline: baseline, scenario: scenario, accent: accent) { measure, add in
                            toggle(measure, add: add, in: scenario)
                        }
                    }
            } else {
                startCard(baseline)
            }
        }
    }

    // MARK: Start

    private func startCard(_ baseline: ScenarioBaseline) -> some View {
        GHGPanelCard(title: "Plan a Decarbonisation Pathway",
                     subtitle: "Compare business as usual with a set of measures and see what each one cuts.") {
            HStack(spacing: 10) {
                Button {
                    addScenario(.starter(for: baseline))
                } label: {
                    Label("Create Starter Pathway", systemImage: "wand.and.stars")
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                Button("Start Empty") {
                    addScenario(DecarbonizationScenario(name: "Scenario \(baseline.baseYear + 10)", targetYear: baseline.baseYear + 10))
                }
                if isIritty {
                    Button("Load Iritty Example Plan") { addScenario(GPCExamplePathways.irittyPathway(for: inventory)) }
                        .help("A worked 2035 pathway with owners, timeline and funding (illustrative)")
                }
            }
            Text("The starter adds every measure that fits your sources and cuts emissions by the target year, at a typical adoption level.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    // MARK: Layout

    private func scenarioContent(_ scenario: DecarbonizationScenario, baseline: ScenarioBaseline,
                                 projection: ScenarioProjection) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                toolbar(scenario, baseline: baseline)
                metrics(scenario, projection: projection)
                // Two columns when there is room, one column on narrow windows.
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        chartsColumn(scenario, projection: projection).frame(minWidth: 560)
                        sideColumn(scenario, baseline: baseline, projection: projection).frame(width: 420)
                    }
                    VStack(spacing: 14) {
                        chartsColumn(scenario, projection: projection)
                        sideColumn(scenario, baseline: baseline, projection: projection)
                    }
                }
                notes(projection.warnings)
            }
            .padding(.bottom, 20)
        }
    }

    private func chartsColumn(_ scenario: DecarbonizationScenario, projection: ScenarioProjection) -> some View {
        VStack(spacing: 14) {
            GHGPanelCard(title: "Emissions Pathway",
                         subtitle: "tCO2e per year, \(inventory.targetLevel.title). Hover for values; the mitigation scenario is net of removals.") {
                PathwayChart(projection: projection,
                             goalTonnes: scenario.goalTonnes(baseTonnes: projection.baseTonnes,
                                                             bauTonnes: projection.target?.bauTonnes ?? projection.baseTonnes),
                             accent: accent)
            }
            GHGPanelCard(title: "What Each Measure Cuts in \(String(scenario.targetYear))",
                         subtitle: "Applied in order (use less, switch fuel, cut methane, clean power, cleaner grid), so nothing is counted twice.") {
                WedgeBreakdown(result: projection.target)
            }
        }
    }

    private func sideColumn(_ scenario: DecarbonizationScenario, baseline: ScenarioBaseline,
                            projection: ScenarioProjection) -> some View {
        VStack(spacing: 14) {
            measuresCard(scenario, projection: projection)
            suggestionsCard(scenario, baseline: baseline)
        }
    }

    @ViewBuilder
    private func notes(_ warnings: [String]) -> some View {
        if !warnings.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(warnings, id: \.self) { Text($0) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            } label: {
                Label("\(warnings.count) calculation note\(warnings.count == 1 ? "" : "s")", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: Toolbar and metrics

    private func toolbar(_ scenario: DecarbonizationScenario, baseline: ScenarioBaseline) -> some View {
        HStack(spacing: 10) {
            Picker("Scenario", selection: Binding(get: { scenario.id }, set: { selectedScenarioID = $0 })) {
                ForEach(scenarios) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            .frame(maxWidth: 260)
            Menu {
                Button("New Starter Pathway") { addScenario(.starter(for: baseline, targetYear: scenario.targetYear)) }
                if isIritty {
                    Button("Add Iritty Example Pathway") { addScenario(GPCExamplePathways.irittyPathway(for: inventory)) }
                }
                Button("Duplicate") {
                    var copy = scenario
                    copy.id = UUID()
                    copy.name = "\(scenario.name) (copy)"
                    addScenario(copy)
                }
                Button("Rename…") { renameDraft = scenario.name }
                Divider()
                Button("Delete Scenario", role: .destructive) { deleteScenario(scenario.id) }
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.button)
            .buttonStyle(.borderless)
            .fixedSize()
            Divider().frame(height: 20)
            Stepper(value: Binding(get: { scenario.targetYear },
                                   set: { year in update(scenario.id) { $0.targetYear = max(year, baseline.baseYear + 1) } }),
                    in: (baseline.baseYear + 1)...2070) {
                Text("Target Year \(String(scenario.targetYear))").font(.callout)
            }
            .fixedSize()
            Button { showingGrowth.toggle() } label: { Label("Growth & Goal", systemImage: "chart.line.uptrend.xyaxis") }
                .popover(isPresented: $showingGrowth, arrowEdge: .bottom) { growthEditor(scenario, baseline: baseline) }
                .help("Business-as-usual growth by sector and a reduction goal")
            Spacer()
            Button { showingLibrary = true } label: { Label("Add Measures", systemImage: "plus") }
                .buttonStyle(.borderedProminent)
                .tint(accent)
            Button { showingMethod.toggle() } label: { Image(systemName: "info.circle").imageScale(.large) }
                .buttonStyle(.borderless)
                .help("How scenarios are calculated")
                .popover(isPresented: $showingMethod, arrowEdge: .bottom) { methodNote }
        }
        .alert("Rename Scenario", isPresented: Binding(get: { renameDraft != nil }, set: { if !$0 { renameDraft = nil } })) {
            TextField("Name", text: Binding(get: { renameDraft ?? "" }, set: { renameDraft = $0 }))
            Button("Rename") {
                let name = (renameDraft ?? "").trimmingCharacters(in: .whitespaces)
                if !name.isEmpty { update(scenario.id) { $0.name = name } }
                renameDraft = nil
            }
            Button("Cancel", role: .cancel) { renameDraft = nil }
        }
    }

    private func metrics(_ scenario: DecarbonizationScenario, projection: ScenarioProjection) -> some View {
        let base = projection.baseTonnes
        let bau = projection.target?.bauTonnes ?? base
        let net = projection.target?.netTonnes ?? base
        let year = String(scenario.targetYear)
        return HStack(spacing: 12) {
            GHGMetricCard(title: "Base Year \(String(projection.baseYear))", value: GHGFormat.tonnes(base),
                          detail: "\(inventory.targetLevel.title) inventory")
            GHGMetricCard(title: "Business as Usual \(year)", value: GHGFormat.tonnes(bau),
                          detail: bau == base ? "No growth set" : "\(DecarbonizationFormat.signedPercent(bau / base - 1)) vs base year")
            GHGMetricCard(title: "Mitigation Scenario \(year)", value: GHGFormat.tonnes(net),
                          detail: "\(DecarbonizationFormat.signedPercent(base > 0 ? net / base - 1 : 0)) vs base year")
            GHGMetricCard(title: "Cut vs Business as Usual", value: GHGFormat.percent(bau > 0 ? max(0, 1 - net / bau) : 0),
                          detail: goalStatus(scenario, baseYear: projection.baseYear, base: base, bau: bau, net: net))
        }
    }

    private func goalStatus(_ scenario: DecarbonizationScenario, baseYear: Int, base: Double, bau: Double, net: Double) -> String {
        guard let goal = scenario.goalTonnes(baseTonnes: base, bauTonnes: bau),
              let label = scenario.goalLabel(baseYear: baseYear) else {
            return "\(GHGFormat.plain(max(0, bau - net))) t avoided"
        }
        return net <= goal + 0.5 ? "Meets goal (\(label))" : "\(GHGFormat.plain(net - goal)) t short of goal (\(label))"
    }

    // MARK: Measures

    private func measuresCard(_ scenario: DecarbonizationScenario, projection: ScenarioProjection) -> some View {
        let selections = scenario.measures.sorted {
            DecarbonizationMeasureCatalog.position(of: $0.measureID) < DecarbonizationMeasureCatalog.position(of: $1.measureID)
        }
        return GHGPanelCard(title: "Measures (\(scenario.measures.count))",
                            subtitle: "Adoption reached in \(String(scenario.targetYear)), rising evenly from each start year.") {
            if selections.isEmpty {
                Text("No measures yet. Use Add Measures.").font(.caption).foregroundStyle(.white.opacity(0.6))
            }
            VStack(spacing: 8) {
                ForEach(selections) { selection in
                    if let measure = DecarbonizationMeasureCatalog.measure(selection.measureID) {
                        measureRow(measure, selection: selection, scenario: scenario,
                                   wedge: projection.target?.wedge(selection.measureID) ?? 0)
                    }
                }
            }
        }
    }

    private func measureRow(_ measure: DecarbonizationMeasure, selection: ScenarioMeasureSelection,
                            scenario: DecarbonizationScenario, wedge: Double) -> some View {
        let isExpanded = expandedMeasureID == measure.id
        let isStretch = selection.adoption > min(1, 2 * measure.defaultAdoption) + 0.001
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: measure.category.systemImage)
                    .foregroundStyle(measure.category.tint)
                    .frame(width: 18)
                Text(measure.title).font(.callout.weight(.semibold)).lineLimit(1)
                if isStretch {
                    GHGTag(text: "Stretch", color: .orange)
                        .help("More than twice the typical adoption of \(GHGFormat.percent(measure.defaultAdoption))")
                }
                if selection.adoption <= 0 {
                    GHGTag(text: "0%: No Effect", color: .orange)
                        .help("At 0% adoption the measure cuts nothing and has no cost per tonne in the Action Plan. Typical: \(GHGFormat.percent(measure.defaultAdoption)).")
                }
                Spacer(minLength: 8)
                Text(DecarbonizationFormat.cut(wedge))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(wedge < 0 ? MeasureCategory.addsEmissionsTint : Color.secondary)
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) { expandedMeasureID = isExpanded ? nil : measure.id }
                } label: {
                    Image(systemName: "chevron.down").rotationEffect(.degrees(isExpanded ? 180 : 0))
                }
                .buttonStyle(.borderless)
                .help(isExpanded ? "Hide settings" : "Settings")
            }
            HStack(spacing: 10) {
                Slider(value: Binding(get: { selection.adoption },
                                      set: { value in updateSelection(scenario.id, measure.id) { $0.adoption = (value * 20).rounded() / 20 } }),
                       in: 0...1)
                    .help(measure.adoptionMeaning)
                Text(GHGFormat.percent(selection.adoption))
                    .font(.caption.monospacedDigit())
                    .frame(width: 40, alignment: .trailing)
            }
            if isExpanded {
                measureSettings(measure, selection: selection, scenario: scenario)
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.white.opacity(isExpanded ? 0.07 : 0.04)))
    }

    private func measureSettings(_ measure: DecarbonizationMeasure, selection: ScenarioMeasureSelection,
                                 scenario: DecarbonizationScenario) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("\(measure.adoptionMeaning). Typical: \(GHGFormat.percent(measure.defaultAdoption)).")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(spacing: 16) {
                Stepper(value: Binding(get: { selection.startYear },
                                       set: { year in updateSelection(scenario.id, measure.id) { $0.startYear = min(year, $0.fullYear) } }),
                        in: 1990...2070) {
                    Text("Start \(String(selection.startYear))").font(.caption)
                }
                Stepper(value: Binding(get: { selection.fullYear },
                                       set: { year in updateSelection(scenario.id, measure.id) { $0.fullYear = max(year, $0.startYear) } }),
                        in: 1990...2070) {
                    Text("Full \(String(selection.fullYear))").font(.caption)
                }
            }
            if !measure.parameters.isEmpty {
                VStack(spacing: 6) {
                    ForEach(measure.parameters) { parameter in
                        ParameterField(parameter: parameter,
                                       value: selection.parameterOverrides[parameter.id] ?? parameter.typical) { value in
                            updateSelection(scenario.id, measure.id) { selection in
                                if value == parameter.typical { selection.parameterOverrides[parameter.id] = nil }
                                else { selection.parameterOverrides[parameter.id] = value }
                            }
                        }
                    }
                }
            }
            if !measure.caveat.isEmpty {
                Label(measure.caveat, systemImage: "exclamationmark.circle").font(.caption2).foregroundStyle(.yellow)
            }
            HStack {
                PrimarySourceLink(measure: measure)
                Spacer()
                Button("Remove", role: .destructive) {
                    update(scenario.id) { $0.measures.removeAll { $0.measureID == measure.id } }
                }
                .controlSize(.small)
            }
        }
        .padding(.top, 2)
    }

    // MARK: Suggestions

    /// A base-year source and the catalog measures that cut it most on their own.
    private struct SourceSuggestion: Identifiable {
        let key: String
        let label: String
        let tonnes: Double
        let potentials: [MeasurePotential]
        var id: String { key }
    }

    private func suggestions(for baseline: ScenarioBaseline, year: Int, sources limit: Int = 3) -> [SourceSuggestion] {
        let largest = Dictionary(grouping: baseline.lines, by: \.sourceKey)
            .map { key, lines in (key: key, lines: lines, tonnes: lines.reduce(0) { $0 + $1.co2eTonnes(baseline.gwp) }) }
            .sorted { $0.tonnes > $1.tonnes }
            .prefix(limit)
        return largest.map { source in
            let ranked = DecarbonizationMeasureCatalog.measures
                .filter { measure in source.lines.contains(where: measure.targets.matches) }
                .map { DecarbonizationEngine.potential(of: $0, baseline: baseline, adoption: $0.defaultAdoption, year: year) }
                .filter { $0.typicalTonnes > 0 }
                .sorted { $0.typicalTonnes > $1.typicalTonnes }
            return SourceSuggestion(key: source.key, label: source.lines.first?.label ?? source.key,
                                    tonnes: source.tonnes, potentials: Array(ranked.prefix(3)))
        }
    }

    private func suggestionsCard(_ scenario: DecarbonizationScenario, baseline: ScenarioBaseline) -> some View {
        let chosen = Set(scenario.measures.map(\.measureID))
        return GHGPanelCard(title: "Best Fits for Your Largest Sources", subtitle: "Stand-alone cut at typical adoption.") {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(suggestions(for: baseline, year: scenario.targetYear)) { source in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("\(source.key) · \(source.label)").font(.caption.weight(.semibold)).lineLimit(1)
                            Spacer()
                            Text("\(GHGFormat.plain(source.tonnes)) t").font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                        }
                        if source.potentials.isEmpty {
                            Text("No catalog measure cuts this source on today's grid.").font(.caption2).foregroundStyle(.white.opacity(0.55))
                        }
                        ForEach(source.potentials) { potential in
                            suggestionRow(potential, isChosen: chosen.contains(potential.measureID), scenario: scenario)
                        }
                    }
                }
            }
        }
    }

    private func suggestionRow(_ potential: MeasurePotential, isChosen: Bool, scenario: DecarbonizationScenario) -> some View {
        let measure = DecarbonizationMeasureCatalog.measure(potential.measureID)
        return HStack(spacing: 8) {
            Image(systemName: measure?.category.systemImage ?? "circle")
                .font(.caption2)
                .foregroundStyle(measure?.category.tint ?? .gray)
                .frame(width: 14)
            Text(measure?.title ?? potential.measureID).font(.caption).lineLimit(1)
            Spacer()
            Text(DecarbonizationFormat.cut(potential.typicalTonnes)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
            if isChosen {
                Image(systemName: "checkmark").foregroundStyle(.green).frame(width: 36)
            } else if let measure {
                Button("Add") { toggle(measure, add: true, in: scenario) }.controlSize(.small).frame(width: 36)
            }
        }
    }

    // MARK: Popovers

    private func growthEditor(_ scenario: DecarbonizationScenario, baseline: ScenarioBaseline) -> some View {
        let groups = baseline.groupTitles.keys.filter { key in baseline.lines.contains { $0.groupKey == key } }.sorted()
        return VStack(alignment: .leading, spacing: 10) {
            Text("Business-as-Usual Growth").font(.headline)
            Text("Yearly growth in activity with today's technology. Use local projections: population, vehicles, electricity demand.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(groups, id: \.self) { group in
                HStack {
                    Text(baseline.groupTitles[group] ?? group).font(.callout)
                    Spacer()
                    TextField("0", value: Binding(get: { scenario.growth(for: group) * 100 },
                                                  set: { value in update(scenario.id) { $0.annualGrowth[group] = value / 100 } }),
                              format: .number.precision(.fractionLength(0...2)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("% / yr").font(.caption).foregroundStyle(.secondary)
                }
            }
            Divider()
            Text("Goal (GPC Chapter 11)").font(.headline)
            Picker("Goal type", selection: Binding(get: { scenario.goalKind },
                                                   set: { kind in update(scenario.id) { $0.goalType = kind } })) {
                ForEach(ScenarioGoalType.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            HStack {
                if scenario.goalKind == .fixedLevel {
                    Text("Emissions in \(String(scenario.targetYear)) (0 = net zero)").font(.callout)
                    Spacer()
                    TextField("None", value: Binding(get: { scenario.goalLevelTonnes },
                                                     set: { value in update(scenario.id) { $0.goalLevelTonnes = value.map { max(0, $0) } } }),
                              format: .number.precision(.fractionLength(0)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .multilineTextAlignment(.trailing)
                    Text("t").font(.caption).foregroundStyle(.secondary)
                } else {
                    Text(scenario.goalKind == .baseYear ? "Cut vs \(String(baseline.baseYear))" : "Cut vs business as usual").font(.callout)
                    Spacer()
                    TextField("None", value: Binding(get: { scenario.reductionTarget.map { $0 * 100 } },
                                                     set: { value in update(scenario.id) { $0.reductionTarget = value.map { min(max($0, 0), 100) / 100 } } }),
                              format: .number.precision(.fractionLength(0...1)))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 70)
                        .multilineTextAlignment(.trailing)
                    Text("%").font(.caption).foregroundStyle(.secondary)
                }
            }
            Text("Goals are checked against emissions net of in-boundary removals. Credits bought from outside the city are kept separate (Action Plan).")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(width: 380)
    }

    private var methodNote: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("How Scenarios Are Calculated").font(.headline)
            Text("Business as usual grows each base-year source by the rates you set; emission factors stay at base-year values.")
            Text("Measures apply in order: use less → switch fuels → cut methane → clean power → cleaner grid → removals. Measures on the same source act on what is left, so nothing is cut twice.")
            Text("Fuel switches add electricity at that year's grid factor, so their bars show the real net effect. Tree measures are removals, shown apart from emissions.")
            Text("Defaults cite a source or are marked as assumptions. Replace them with local data. Costs are not modelled.")
        }
        .font(.caption)
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 380)
    }

    // MARK: Changes

    private func addScenario(_ scenario: DecarbonizationScenario) {
        store.mutateSelected { $0.decarbonizationScenarios.append(scenario) }
        selectedScenarioID = scenario.id
    }

    private func deleteScenario(_ id: UUID) {
        store.mutateSelected { $0.decarbonizationScenarios.removeAll { $0.id == id } }
        selectedScenarioID = nil
    }

    private func update(_ id: UUID, _ change: (inout DecarbonizationScenario) -> Void) {
        store.mutateSelected { inventory in
            var list = inventory.decarbonizationScenarios
            guard let index = list.firstIndex(where: { $0.id == id }) else { return }
            change(&list[index])
            inventory.decarbonizationScenarios = list
        }
    }

    private func updateSelection(_ scenarioID: UUID, _ measureID: String, _ change: (inout ScenarioMeasureSelection) -> Void) {
        update(scenarioID) { scenario in
            guard let index = scenario.measures.firstIndex(where: { $0.measureID == measureID }) else { return }
            change(&scenario.measures[index])
        }
    }

    private func toggle(_ measure: DecarbonizationMeasure, add: Bool, in scenario: DecarbonizationScenario) {
        update(scenario.id) { scenario in
            scenario.measures.removeAll { $0.measureID == measure.id }
            if add {
                let start = min(inventory.inventoryYear + 1, scenario.targetYear)
                scenario.measures.append(ScenarioMeasureSelection(measureID: measure.id, adoption: measure.defaultAdoption,
                                                                  startYear: start, fullYear: scenario.targetYear))
            }
        }
    }
}

// MARK: - Pathway chart

/// Business as usual vs scenario, fitted to the base year–target year window.
private struct PathwayChart: View {
    let projection: ScenarioProjection
    let goalTonnes: Double?
    let accent: Color

    @State private var hoverYear: Int?

    private static let bauSeries = "Business as Usual"
    private static let scenarioSeries = "Mitigation Scenario"

    private struct Point: Identifiable {
        let year: Int
        let series: String
        let tonnes: Double
        var id: String { "\(series)-\(year)" }
    }

    var body: some View {
        let years = projection.years
        let first = years.first?.year ?? projection.baseYear
        let last = max(years.last?.year ?? first, first + 1)
        let ceiling = max(years.map(\.bauTonnes).max() ?? 0, years.map(\.netTonnes).max() ?? 0, goalTonnes ?? 0) * 1.1
        let points = years.flatMap { year in
            [Point(year: year.year, series: Self.bauSeries, tonnes: year.bauTonnes),
             Point(year: year.year, series: Self.scenarioSeries, tonnes: year.netTonnes)]
        }
        let hovered = hoverYear.flatMap { projection.year($0) }

        Chart {
            ForEach(years) { year in
                AreaMark(x: .value("Year", year.year),
                         yStart: .value("Scenario", year.netTonnes),
                         yEnd: .value("Business as Usual", year.bauTonnes))
                    .foregroundStyle(accent.opacity(0.12))
                    .interpolationMethod(.monotone)
            }
            ForEach(points) { point in
                LineMark(x: .value("Year", point.year), y: .value("tCO2e", point.tonnes))
                    .foregroundStyle(by: .value("Series", point.series))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round))
            }
            if let goalTonnes {
                RuleMark(y: .value("Goal", goalTonnes))
                    .foregroundStyle(.green.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [5, 4]))
                    .annotation(position: .top, alignment: .leading) {
                        Text("Goal").font(.caption2).foregroundStyle(.green)
                    }
            }
            if let hovered {
                RuleMark(x: .value("Year", hovered.year))
                    .foregroundStyle(.white.opacity(0.3))
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        tooltip(hovered)
                    }
            }
        }
        .chartForegroundStyleScale([Self.bauSeries: Color.orange, Self.scenarioSeries: accent])
        .chartXScale(domain: first...last)
        .chartYScale(domain: 0...max(ceiling, 1))
        .chartXAxis {
            AxisMarks(values: Array(stride(from: first, through: last, by: Self.labelStep(span: last - first)))) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisTick()
                AxisValueLabel {
                    if let year = value.as(Int.self) { Text(String(year)) }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine().foregroundStyle(.white.opacity(0.08))
                AxisValueLabel {
                    if let tonnes = value.as(Double.self) { Text(tonnes.formatted(.number.notation(.compactName))) }
                }
            }
        }
        .chartXSelection(value: $hoverYear)
        .chartLegend(position: .bottom, alignment: .leading, spacing: 10)
        .frame(height: 260)
    }

    /// One label per year for a decade, every 2 or 5 years for longer horizons.
    private static func labelStep(span: Int) -> Int {
        span <= 12 ? 1 : span <= 24 ? 2 : 5
    }

    private func tooltip(_ year: ScenarioYearResult) -> some View {
        let cut = year.bauTonnes > 0 ? max(0, 1 - year.netTonnes / year.bauTonnes) : 0
        return VStack(alignment: .leading, spacing: 3) {
            Text(String(year.year)).font(.caption.weight(.semibold))
            Text("Business as usual  \(GHGFormat.plain(year.bauTonnes)) t").foregroundStyle(.orange)
            Text("Mitigation  \(GHGFormat.plain(year.netTonnes)) t").foregroundStyle(accent)
            Text("Cut  \(GHGFormat.percent(cut))").foregroundStyle(.secondary)
        }
        .font(.caption2.monospacedDigit())
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.black.opacity(0.8)))
    }
}

// MARK: - Wedge breakdown

/// Ranked rows — measure, bar, tonnes, share of business as usual — with even spacing.
private struct WedgeBreakdown: View {
    let result: ScenarioYearResult?

    private static let titleWidth: CGFloat = 230
    private static let valueWidth: CGFloat = 86
    private static let shareWidth: CGFloat = 56

    var body: some View {
        let wedges = (result?.wedges ?? []).filter { abs($0.tonnes) >= 0.5 }.sorted { $0.tonnes > $1.tonnes }
        if wedges.isEmpty {
            Text("Add measures to see what each one cuts.").font(.caption).foregroundStyle(.white.opacity(0.6))
        } else {
            let bau = result?.bauTonnes ?? 0
            let largest = wedges.map { abs($0.tonnes) }.max() ?? 1
            let total = wedges.reduce(0) { $0 + $1.tonnes }
            VStack(alignment: .leading, spacing: 12) {
                header
                ForEach(wedges) { wedge in
                    row(wedge, largest: largest, bau: bau)
                }
                Divider().overlay(Color.white.opacity(0.1))
                HStack(spacing: 12) {
                    Text("Total").font(.callout.weight(.semibold))
                    Spacer()
                    Text(DecarbonizationFormat.cut(total))
                        .font(.callout.weight(.semibold).monospacedDigit())
                        .frame(width: Self.valueWidth, alignment: .trailing)
                    Text(bau > 0 ? GHGFormat.percent(total / bau) : "—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: Self.shareWidth, alignment: .trailing)
                }
                if wedges.contains(where: { $0.tonnes < 0 }) {
                    Text("Red rows add emissions: the electricity for a fuel switch outweighs the fuel saved at that year's grid factor.")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.55))
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Text("Measure").frame(width: Self.titleWidth + 28, alignment: .leading)
            Spacer()
            Text("tCO2e").frame(width: Self.valueWidth, alignment: .trailing)
            Text("of BAU").frame(width: Self.shareWidth, alignment: .trailing)
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(.white.opacity(0.5))
    }

    private func row(_ wedge: MeasureWedge, largest: Double, bau: Double) -> some View {
        let measure = DecarbonizationMeasureCatalog.measure(wedge.measureID)
        let color = wedge.tonnes < 0 ? MeasureCategory.addsEmissionsTint : (measure?.category.tint ?? .gray)
        let fraction = largest > 0 ? abs(wedge.tonnes) / largest : 0
        let isRemoval = measure?.category == .landUse
        return HStack(spacing: 12) {
            Image(systemName: measure?.category.systemImage ?? "circle")
                .font(.caption)
                .foregroundStyle(color)
                .frame(width: 16)
            Text(measure?.title ?? wedge.measureID)
                .font(.callout)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(width: Self.titleWidth, alignment: .leading)
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.06))
                    Capsule().fill(color.gradient).frame(width: max(4, proxy.size.width * fraction))
                }
            }
            .frame(height: 10)
            Text(DecarbonizationFormat.cut(wedge.tonnes))
                .font(.callout.monospacedDigit())
                .foregroundStyle(wedge.tonnes < 0 ? color : Color.primary)
                .frame(width: Self.valueWidth, alignment: .trailing)
            Text(bau > 0 ? GHGFormat.percent(abs(wedge.tonnes) / bau) : "—")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: Self.shareWidth, alignment: .trailing)
        }
        .frame(height: 22)
        .help("\(measure?.category.title ?? "Measure")\(isRemoval ? " — carbon removed, shown apart from emissions" : "")")
    }
}

// MARK: - Shared pieces

/// Editable parameter: title, value and unit on one line; range and note on hover.
private struct ParameterField: View {
    let parameter: MeasureParameter
    let value: Double
    let onChange: (Double) -> Void

    private var scale: Double { parameter.unit == "%" ? 100 : 1 }

    private var hint: String {
        let range = parameter.low != parameter.high
            ? "Range \(GHGFormat.plain(parameter.low * scale))–\(GHGFormat.plain(parameter.high * scale)) \(parameter.unit). " : ""
        return range + parameter.note
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(parameter.title).font(.caption).lineLimit(1)
            if parameter.isAssumption { GHGTag(text: "Assumption", color: .orange) }
            if parameter.requiresInput && value == 0 { GHGTag(text: "Needs Input", color: .yellow) }
            Spacer(minLength: 4)
            TextField("", value: Binding(get: { value * scale }, set: { onChange($0 / scale) }),
                      format: .number.precision(.significantDigits(1...6)))
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
                .multilineTextAlignment(.trailing)
            Text(parameter.unit).font(.caption2).foregroundStyle(.secondary).frame(width: 54, alignment: .leading)
        }
        .help(hint)
    }
}

/// The measure's main source as a single link; the full list stays in the catalog.
private struct PrimarySourceLink: View {
    let measure: DecarbonizationMeasure

    var body: some View {
        if let source = measure.sourceIDs.lazy.compactMap(DecarbonizationMeasureCatalog.source).first,
           let url = URL(string: source.url) {
            Link(destination: url) {
                Label("Source: \(source.publisher)", systemImage: "arrow.up.right.square")
                    .lineLimit(1)
            }
            .font(.caption2)
            .help(source.title)
        }
    }
}

// MARK: - Measure library

/// All measures with their stand-alone potential for this inventory.
private struct MeasureLibrarySheet: View {
    let baseline: ScenarioBaseline
    let scenario: DecarbonizationScenario
    let accent: Color
    let onToggle: (DecarbonizationMeasure, Bool) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var category: MeasureCategory?
    @State private var selectedID: String?

    var body: some View {
        let potentials = Dictionary(uniqueKeysWithValues: DecarbonizationMeasureCatalog.measures.map { measure in
            (measure.id, DecarbonizationEngine.potential(of: measure, baseline: baseline,
                                                         adoption: measure.defaultAdoption, year: scenario.targetYear))
        })
        let chosen = Set(scenario.measures.map(\.measureID))
        let visible = filteredMeasures
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Measure Library").font(.appSectionTitle)
                Text("\(DecarbonizationMeasureCatalog.measures.count) measures").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            HStack {
                TextField("Search measures", text: $query).textFieldStyle(.roundedBorder).frame(maxWidth: 260)
                Picker("Category", selection: $category) {
                    Text("All Categories").tag(MeasureCategory?.none)
                    ForEach(MeasureCategory.allCases) { Label($0.title, systemImage: $0.systemImage).tag(Optional($0)) }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                Spacer()
                Text("Potential: stand-alone cut at typical adoption, base-year activity.").font(.caption2).foregroundStyle(.secondary)
            }
            HStack(alignment: .top, spacing: 14) {
                List(visible, selection: $selectedID) { measure in
                    libraryRow(measure, potential: potentials[measure.id], isChosen: chosen.contains(measure.id))
                        .tag(measure.id)
                }
                .frame(width: 430)
                if let measure = visible.first(where: { $0.id == selectedID }) ?? visible.first {
                    ScrollView {
                        detail(measure, potential: potentials[measure.id], isChosen: chosen.contains(measure.id))
                    }
                } else {
                    Text("No measures match.").foregroundStyle(.secondary)
                    Spacer()
                }
            }
        }
        .padding(20)
        .frame(width: 1_000, height: 660)
    }

    private var filteredMeasures: [DecarbonizationMeasure] {
        let words = query.lowercased().split(separator: " ").map(String.init)
        return DecarbonizationMeasureCatalog.measures.filter { measure in
            (category == nil || measure.category == category)
                && words.allSatisfy { "\(measure.title) \(measure.summary) \(measure.bestFor)".lowercased().contains($0) }
        }
    }

    private func potentialText(_ potential: MeasurePotential?) -> String {
        guard let potential else { return "" }
        if !potential.isApplicable { return "No matching sources" }
        if potential.needsInput { return "Needs local input" }
        if potential.typicalTonnes < 0 { return "Adds \(GHGFormat.plain(-potential.typicalTonnes)) t on today's grid" }
        return "−\(GHGFormat.plain(potential.typicalTonnes)) t (\(GHGFormat.percent(potential.shareOfBase)))"
    }

    private func potentialColor(_ potential: MeasurePotential?) -> Color {
        guard let potential, potential.isApplicable, !potential.needsInput else { return .secondary }
        return potential.typicalTonnes > 0 ? .green : MeasureCategory.addsEmissionsTint
    }

    private func libraryRow(_ measure: DecarbonizationMeasure, potential: MeasurePotential?, isChosen: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: measure.category.systemImage).foregroundStyle(measure.category.tint).frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                Text(measure.title).font(.callout.weight(.semibold))
                Text(measure.bestFor).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Text(potentialText(potential))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(potentialColor(potential))
            }
            Spacer(minLength: 4)
            Button(isChosen ? "Remove" : "Add") { onToggle(measure, !isChosen) }
                .controlSize(.small)
                .disabled(!isChosen && potential?.isApplicable == false)
        }
        .padding(.vertical, 2)
    }

    private func detail(_ measure: DecarbonizationMeasure, potential: MeasurePotential?, isChosen: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(measure.category.title, systemImage: measure.category.systemImage).font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(isChosen ? "Remove from Scenario" : "Add to Scenario") { onToggle(measure, !isChosen) }
                    .buttonStyle(.borderedProminent)
                    .tint(isChosen ? .gray : accent)
                    .disabled(!isChosen && potential?.isApplicable == false)
            }
            Text(measure.title).font(.title3.weight(.semibold))
            Text(measure.summary).font(.callout)
            LabeledContent("Best for") { Text(measure.bestFor).multilineTextAlignment(.trailing) }.font(.caption)
            LabeledContent("Adoption means") {
                Text("\(measure.adoptionMeaning) (typical \(GHGFormat.percent(measure.defaultAdoption)))").multilineTextAlignment(.trailing)
            }
            .font(.caption)
            if let potential, potential.isApplicable {
                GroupBox("Potential for This Inventory") {
                    VStack(alignment: .leading, spacing: 4) {
                        if potential.needsInput {
                            Text("Enter the local input (a count or an area) after adding the measure.").font(.caption)
                        } else {
                            Text("At \(GHGFormat.percent(potential.adoption)) adoption it cuts \(GHGFormat.plain(potential.typicalTonnes)) tCO2e a year (range \(GHGFormat.plain(potential.lowTonnes)) to \(GHGFormat.plain(potential.highTonnes))), \(GHGFormat.percent(potential.shareOfBase)) of the base total.")
                                .font(.caption)
                            if potential.typicalTonnes < 0 {
                                Text("A negative cut means the switch adds emissions at the base-year grid factor. Pair it with rooftop solar, green power or the grid pathway.")
                                    .font(.caption)
                                    .foregroundStyle(MeasureCategory.addsEmissionsTint)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                Text("No source in this inventory matches this measure.").font(.caption).foregroundStyle(.secondary)
            }
            if !measure.parameters.isEmpty {
                GroupBox("Inputs and Defaults") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(measure.parameters) { parameter in
                            let scale = parameter.unit == "%" ? 100.0 : 1.0
                            HStack(alignment: .firstTextBaseline) {
                                Text(parameter.title).font(.caption)
                                if parameter.isAssumption { GHGTag(text: "Assumption", color: .orange) }
                                if parameter.requiresInput { GHGTag(text: "Local Input", color: .yellow) }
                                Spacer()
                                Text(parameter.requiresInput ? "—" : "\(GHGFormat.plain(parameter.typical * scale)) \(parameter.unit)")
                                    .font(.caption.monospacedDigit())
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if !measure.caveat.isEmpty {
                Label(measure.caveat, systemImage: "exclamationmark.circle").font(.caption).foregroundStyle(.yellow)
            }
            PrimarySourceLink(measure: measure)
        }
        .padding(.trailing, 6)
    }
}
