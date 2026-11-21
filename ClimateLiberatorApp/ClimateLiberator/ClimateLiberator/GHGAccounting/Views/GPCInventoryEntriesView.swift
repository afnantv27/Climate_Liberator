import SwiftUI

/// Step 2: activity data per GPC sector and sub-sector.
struct GPCInventoryEntriesView: View {
    @ObservedObject var store: GPCInventoryStore
    @ObservedObject var factorStore: EmissionFactorLibraryStore
    let inventory: GPCInventory
    let accent: Color

    @State private var editingEntry: GPCInventoryEntry?
    @State private var deletingEntry: GPCInventoryEntry?
    @State private var expanded: Set<GPCSector> = [.stationaryEnergy]
    @State private var showingTagGuide = false

    var body: some View {
        let summary = GPCInventorySummary.make(inventory)
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 12) {
                    GHGMetricCard(title: "BASIC", value: GHGFormat.tonnes(summary.basicTotal), detail: "Energy, transport, waste")
                    GHGMetricCard(title: "BASIC+", value: GHGFormat.tonnes(summary.basicPlusTotal), detail: "Adds IPPU, AFOLU, T&D, transboundary")
                    GHGMetricCard(title: "Entries", value: "\(inventory.entries.count)", detail: "GWP: IPCC \(inventory.gwpSet.title)")
                    GHGMetricCard(title: "Gaps for \(inventory.targetLevel.title)", value: "\(summary.missingCount)",
                                  detail: "Sources without a number or notation key")
                }
                tagGuide
                if !inventory.boundary.isClosed {
                    Label("Define the boundary first — scopes depend on what is inside it.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                ForEach(GPCSector.allCases) { sector in
                    sectorCard(sector, summary: summary)
                }
            }
            .padding(.bottom, 20)
        }
        .sheet(item: $editingEntry) { entry in
            GPCEntryEditorView(entry: entry, inventory: inventory, factorStore: factorStore, accent: accent) { saved in
                store.upsertEntry(saved)
            }
        }
        .confirmationDialog("Delete this entry?",
                            isPresented: Binding(get: { deletingEntry != nil }, set: { if !$0 { deletingEntry = nil } }),
                            presenting: deletingEntry) { entry in
            Button("Delete", role: .destructive) { store.removeEntry(id: entry.id) }
        } message: { entry in
            Text("\(entry.referenceID) \(entry.label.isEmpty ? (entry.reference?.title ?? "Entry") : entry.label) will be removed from the inventory.")
        }
    }

    // MARK: Tag guide

    /// One line explaining the tags on each entry, with the full guide behind (i).
    private var tagGuide: some View {
        HStack(spacing: 10) {
            Text("Tags:").foregroundStyle(.white.opacity(0.6))
            GHGTag(text: "Scope 1–3")
            GHGTag(text: "High / Medium / Low DQ", color: .yellow)
            GHGTag(text: "NO · IE · NE · C", color: .teal)
            Button { showingTagGuide.toggle() } label: { Image(systemName: "info.circle") }
                .buttonStyle(.borderless)
                .help("What the tags mean")
                .popover(isPresented: $showingTagGuide, arrowEdge: .bottom) { tagGuidePopover }
            Spacer()
        }
        .font(.caption)
    }

    private var tagGuidePopover: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Entry Tags").font(.headline)
            Text("Scope").font(.subheadline.weight(.semibold))
            Text("1 = emitted inside the boundary · 2 = grid electricity used inside it · 3 = outside the boundary but caused by the city (e.g. waste treated elsewhere, T&D losses).")
                .font(.caption)
            Text("Data quality (DQ)").font(.subheadline.weight(.semibold))
            ForEach(GPCDataQuality.allCases) { quality in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    GHGTag(text: quality.title, color: Self.qualityColor(quality))
                    Text(Self.qualityMeaning(quality)).font(.caption)
                }
            }
            Text("Notation keys (used instead of a number)").font(.subheadline.weight(.semibold))
            ForEach(GPCNotationKey.allCases) { key in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    GHGTag(text: key.rawValue, color: .teal)
                    Text(key.meaning).font(.caption)
                }
            }
            Text("IE and NE need a written explanation in the GPC report.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .padding(16)
        .frame(width: 380)
    }

    static func qualityColor(_ quality: GPCDataQuality) -> Color {
        switch quality {
        case .high: return .green
        case .medium: return .yellow
        case .low: return .orange
        }
    }

    /// GPC data-quality ratings for activity data and emission factors.
    static func qualityMeaning(_ quality: GPCDataQuality) -> String {
        switch quality {
        case .high: return "detailed local activity data and source-specific emission factors."
        case .medium: return "activity data modelled from robust assumptions, or more general factors."
        case .low: return "highly modelled or uncertain activity data, or default factors (e.g. IPCC Tier 1)."
        }
    }

    private func sectorCard(_ sector: GPCSector, summary: GPCInventorySummary) -> some View {
        let total = GPCScope.allCases.map { summary.total(sector, $0) }.reduce(0, +)
        let isOpen = expanded.contains(sector)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                if isOpen { expanded.remove(sector) } else { expanded.insert(sector) }
            } label: {
                HStack {
                    Image(systemName: isOpen ? "chevron.down" : "chevron.right")
                    Text("\(sector.rawValue). \(sector.title)").font(.appSectionTitle)
                    Spacer()
                    Text(GHGFormat.tonnes(total)).font(.headline.monospacedDigit())
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isOpen {
                ForEach(GPCCatalog.subSectors(in: sector)) { subSector in
                    subSectorBlock(subSector, summary: summary)
                }
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    private func subSectorBlock(_ subSector: GPCSubSector, summary: GPCInventorySummary) -> some View {
        let entries = inventory.entries.filter { $0.reference?.subSectorID == subSector.id }
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(subSector.id).font(.caption.monospacedDigit()).foregroundStyle(.white.opacity(0.6))
                VStack(alignment: .leading, spacing: 2) {
                    Text(subSector.title).font(.callout.weight(.semibold))
                    Text(subSector.examples).font(.caption).foregroundStyle(.white.opacity(0.6))
                }
                Spacer()
                Button {
                    let first = GPCCatalog.references(inSubSector: subSector.id).first?.id ?? subSector.id
                    editingEntry = GPCInventoryEntry(referenceID: first, label: "")
                } label: {
                    Label("Add", systemImage: "plus.circle")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
            ForEach(entries) { entry in
                entryRow(entry, outcome: summary.outcomes[entry.id])
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.04)))
    }

    private func entryRow(_ entry: GPCInventoryEntry, outcome: GPCEntryOutcome?) -> some View {
        HStack(spacing: 8) {
            GHGTag(text: entry.referenceID, color: accent)
            if let reference = entry.reference { GHGTag(text: reference.scope.title) }
            Text(entry.label.isEmpty ? (entry.reference?.title ?? "Entry") : entry.label)
                .font(.callout)
                .lineLimit(1)
            Spacer()
            if let error = outcome?.error {
                Label(error, systemImage: "xmark.octagon.fill")
                    .font(.caption)
                    .foregroundStyle(.red)
                    .lineLimit(1)
                    .help(error)
            } else if entry.method == .notationKey, let key = entry.notationKey {
                GHGTag(text: key.rawValue, color: .teal)
                    .help("\(key.rawValue): \(key.meaning)")
            } else {
                Text(GHGFormat.tonnes(outcome?.co2eTonnes ?? 0)).font(.callout.monospacedDigit())
            }
            GHGTag(text: "\(entry.dataQuality.title) DQ", color: Self.qualityColor(entry.dataQuality))
                .help("Data quality: \(Self.qualityMeaning(entry.dataQuality))")
            Button { editingEntry = entry } label: { Image(systemName: "pencil") }
                .buttonStyle(.borderless)
                .help("Edit entry")
            Button { deletingEntry = entry } label: { Image(systemName: "trash") }
                .buttonStyle(.borderless)
                .help("Delete entry")
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Entry editor

struct GPCEntryEditorView: View {
    let inventory: GPCInventory
    @ObservedObject var factorStore: EmissionFactorLibraryStore
    let accent: Color
    let onSave: (GPCInventoryEntry) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var entry: GPCInventoryEntry
    @State private var sector: GPCSector
    @State private var subSectorID: String
    @State private var quantityText: String
    @State private var directText: String
    @State private var factorQuery = ""
    @State private var wasteGeneratedInCity = true
    @State private var estimating = false
    @State private var estimateMessage = ""
    /// The source the entry had when the editor opened, restored if the user returns to its sub-sector.
    private let originalReferenceID: String

    private static let labelWidth: CGFloat = 86

    init(entry: GPCInventoryEntry, inventory: GPCInventory, factorStore: EmissionFactorLibraryStore,
         accent: Color, onSave: @escaping (GPCInventoryEntry) -> Void) {
        self.inventory = inventory
        _factorStore = ObservedObject(wrappedValue: factorStore)
        self.accent = accent
        self.onSave = onSave
        let reference = GPCCatalog.reference(entry.referenceID)
        _entry = State(initialValue: entry)
        _sector = State(initialValue: reference?.sector ?? .stationaryEnergy)
        _subSectorID = State(initialValue: reference?.subSectorID ?? "I.1")
        _quantityText = State(initialValue: entry.activityQuantity.map(Self.editableNumber) ?? "")
        _directText = State(initialValue: entry.directCO2eTonnes.map(Self.editableNumber) ?? "")
        originalReferenceID = entry.referenceID
    }

    /// "8821" rather than "8821.0"; no grouping, so the text parses back unchanged.
    nonisolated private static func editableNumber(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }

    /// Label column of fixed width and a control column — every row lines up.
    private func formRow<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        GridRow {
            Text(label)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .frame(width: Self.labelWidth, alignment: .leading)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// A row with no label, for notes under the control above.
    private func noteRow<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        GridRow {
            Color.clear.frame(width: Self.labelWidth, height: 0)
            content()
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var reference: GPCReference? { GPCCatalog.reference(entry.referenceID) }
    private var outcome: GPCEntryOutcome { GPCInventorySummary.evaluate(entry, gwp: inventory.gwpSet) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(entry.label.isEmpty ? "GPC entry" : entry.label).font(.title2.weight(.semibold))
            HStack(alignment: .top, spacing: 18) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        classificationSection
                        methodSection
                        qualitySection
                    }
                }
                .frame(width: 460)
                VStack(alignment: .leading, spacing: 12) {
                    if entry.method == .activity { factorPicker }
                    previewSection
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save Entry") {
                    var saved = entry
                    if saved.label.trimmingCharacters(in: .whitespaces).isEmpty {
                        saved.label = reference?.title ?? "Entry"
                    }
                    onSave(saved)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 1000, height: 700)
        .onChange(of: quantityText) { _, value in
            entry.activityQuantity = EmissionFactorConnectorService.parseNumber(value)
        }
        .onChange(of: directText) { _, value in
            entry.directCO2eTonnes = EmissionFactorConnectorService.parseNumber(value)
        }
    }

    // MARK: Classification

    private var classificationSection: some View {
        GroupBox("GPC Classification") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                formRow("Sector") {
                    Picker("Sector", selection: $sector) {
                        ForEach(GPCSector.allCases) { Text("\($0.rawValue). \($0.shortTitle)").tag($0) }
                    }
                    .labelsHidden()
                }
                formRow("Sub-sector") {
                    Picker("Sub-sector", selection: $subSectorID) {
                        ForEach(GPCCatalog.subSectors(in: sector)) { Text("\($0.id) \($0.title)").tag($0.id) }
                    }
                    .labelsHidden()
                }
                formRow("Source") {
                    Picker("Source", selection: $entry.referenceID) {
                        ForEach(GPCCatalog.references(inSubSector: subSectorID)) { reference in
                            Text("\(reference.id) \(reference.title)").tag(reference.id)
                        }
                    }
                    .labelsHidden()
                }
                if let reference {
                    noteRow {
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 6) {
                                GHGTag(text: reference.scope.title, color: accent)
                                GHGTag(text: reference.inclusionLabel)
                            }
                            Text(GPCScopeAdvisor.guidance(for: reference))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if entry.referenceID != originalReferenceID, GPCCatalog.reference(originalReferenceID) != nil {
                                Label("Source changed from \(originalReferenceID). Check the scope and factor still fit.",
                                      systemImage: "arrow.triangle.swap")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
                formRow("Facility") { facilityPicker.labelsHidden() }
                if sector == .waste {
                    noteRow { wasteAdvisor }
                }
                formRow("Name") {
                    TextField("e.g. Household LPG, discom residential sales", text: $entry.label)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(6)
        }
        .onChange(of: sector) { _, newSector in
            guard GPCCatalog.subSector(subSectorID)?.sector != newSector else { return }
            // Back to the entry's own sector: restore its sub-sector rather than the first one.
            if let original = GPCCatalog.reference(originalReferenceID), original.sector == newSector {
                subSectorID = original.subSectorID
            } else {
                subSectorID = GPCCatalog.subSectors(in: newSector).first?.id ?? subSectorID
            }
        }
        .onChange(of: subSectorID) { _, newID in
            guard reference?.subSectorID != newID else { return }
            if GPCCatalog.reference(originalReferenceID)?.subSectorID == newID {
                entry.referenceID = originalReferenceID
            } else {
                entry.referenceID = GPCCatalog.references(inSubSector: newID).first?.id ?? entry.referenceID
            }
        }
    }

    private var facilityPicker: some View {
        Picker("Facility", selection: $entry.facilityID) {
            Text("None").tag(UUID?.none)
            ForEach(inventory.facilities) { facility in
                let inside = inventory.boundary.contains(facility.coordinate)
                Text("\(facility.name) (\(inside ? "inside" : "outside") boundary)").tag(Optional(facility.id))
            }
        }
    }

    private var wasteAdvisor: some View {
        let facility = inventory.facility(entry.facilityID)
        let treatedInside = facility.map { inventory.boundary.contains($0.coordinate) }
        let suggestion = treatedInside.flatMap {
            GPCScopeAdvisor.wasteReference(subSectorID: subSectorID, generatedInCity: wasteGeneratedInCity, treatedInsideBoundary: $0)
        }
        return VStack(alignment: .leading, spacing: 6) {
            Toggle("Waste generated in the city", isOn: $wasteGeneratedInCity)
            if facility == nil {
                Text("Pick the treatment facility to get the scope from its location.").font(.caption).foregroundStyle(.secondary)
            } else if let suggestion, suggestion != entry.referenceID {
                Button("Use \(suggestion) (treatment \(treatedInside == true ? "inside" : "outside") boundary)") {
                    entry.referenceID = suggestion
                }
            } else if suggestion == nil {
                Text("Waste generated and treated outside the city is not part of this inventory.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    // MARK: Method

    private var methodSection: some View {
        GroupBox("Quantification") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                formRow("Method") {
                    Picker("Method", selection: $entry.method) {
                        ForEach(GPCEntryMethod.allCases) { Text(Self.shortTitle($0)).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                switch entry.method {
                case .activity:
                    formRow("Quantity") {
                        HStack(spacing: 6) {
                            TextField("Amount", text: $quantityText)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                            unitField
                        }
                    }
                    if !entry.activityUnit.isEmpty, UnitRegistry.resolve(entry.activityUnit) == nil {
                        noteRow {
                            Text("Unit not recognised. Pick one from the list.").font(.caption).foregroundStyle(.orange)
                        }
                    }
                case .directCO2e:
                    formRow("Emissions") {
                        HStack(spacing: 6) {
                            TextField("From an external model or report", text: $directText)
                                .textFieldStyle(.roundedBorder)
                                .multilineTextAlignment(.trailing)
                            Text("tCO2e").foregroundStyle(.secondary)
                        }
                    }
                case .notationKey:
                    formRow("Key") {
                        Picker("Notation key", selection: notationBinding) {
                            ForEach(GPCNotationKey.allCases) { Text("\($0.rawValue) — \($0.meaning)").tag($0) }
                        }
                        .labelsHidden()
                    }
                    formRow("Explanation") {
                        TextField("Required for IE and NE", text: $entry.notationExplanation, axis: .vertical)
                            .lineLimit(1...4)
                            .textFieldStyle(.roundedBorder)
                    }
                }
            }
            .padding(6)
        }
    }

    /// Segment titles short enough to fit beside the label column.
    private static func shortTitle(_ method: GPCEntryMethod) -> String {
        switch method {
        case .activity: return "Activity × Factor"
        case .directCO2e: return "Direct tCO2e"
        case .notationKey: return "Notation Key"
        }
    }

    /// Unit text with a list of units that fit the chosen factor.
    private var unitField: some View {
        HStack(spacing: 2) {
            TextField("Unit", text: $entry.activityUnit)
                .textFieldStyle(.roundedBorder)
                .frame(width: 76)
            Menu {
                ForEach(unitSuggestions, id: \.self) { unit in
                    Button(unit) { entry.activityUnit = unit }
                }
            } label: {
                Image(systemName: "chevron.down")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("Units that fit the selected factor")
        }
    }

    private var notationBinding: Binding<GPCNotationKey> {
        Binding(get: { entry.notationKey ?? .notOccurring }, set: { entry.notationKey = $0 })
    }

    private var unitSuggestions: [String] {
        guard let dimension = entry.factor?.unitDefinition?.dimension else {
            return ["kWh", "MWh", "L", "kL", "kg", "t", "m3", "TJ", "km", "t·km", "INR"]
        }
        var units = UnitRegistry.symbolsByDimension[dimension] ?? []
        if let factor = entry.factor {
            for extra in [UnitDimension.volume, .mass, .energy] where extra != dimension {
                if EmissionFactorLibraryStore.isCompatible(factor, with: extra) {
                    units += UnitRegistry.symbolsByDimension[extra] ?? []
                }
            }
        }
        return units
    }

    private var qualitySection: some View {
        GroupBox("Data Quality and Source") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 10) {
                formRow("Quality") {
                    Picker("Data quality", selection: $entry.dataQuality) {
                        ForEach(GPCDataQuality.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .pickerStyle(.segmented)
                }
                formRow("Data source") {
                    TextField("e.g. KSEB sales FY2024-25", text: $entry.dataSource, axis: .vertical)
                        .lineLimit(1...3)
                        .textFieldStyle(.roundedBorder)
                }
                formRow("Notes") {
                    TextField("Assumptions, gaps, next steps", text: $entry.notes, axis: .vertical)
                        .lineLimit(2...5)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(6)
        }
    }

    // MARK: Factor picker and preview

    private var factorPicker: some View {
        let dimension = UnitRegistry.resolve(entry.activityUnit)?.dimension
        let results = factorResults(dimension: dimension)
        return GroupBox("Emission Factor") {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    TextField("Search factors (e.g. diesel residential, grid India)", text: $factorQuery)
                        .textFieldStyle(.roundedBorder)
                    Button("Search Online") { Task { await factorStore.searchRemote(factorQuery) } }
                        .disabled(factorQuery.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let dimension {
                    Text("Factors usable with \(dimension.title.lowercased()) units\(isBlankQuery && entry.factor != nil ? "; the selected one is first" : "").")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                List(results, id: \.id) { factor in
                    factorRow(factor)
                }
                .frame(minHeight: 200)
                if !factorStore.statusMessage.isEmpty {
                    Text(factorStore.statusMessage).font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                }
            }
            .padding(6)
        }
    }

    private var isBlankQuery: Bool { factorQuery.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Search results; with no search text, the selected factor comes first and, for
    /// grid-electricity sources, electricity factors before fuels.
    private func factorResults(dimension: UnitDimension?) -> [EmissionFactor] {
        var results = factorStore.search(factorQuery, dimension: dimension, limit: 400)
        guard isBlankQuery else { return Array(results.prefix(80)) }
        if reference?.scope == .two {
            let isElectricity = { (factor: EmissionFactor) in factor.name.localizedCaseInsensitiveContains("electricity") }
            results = results.filter(isElectricity) + results.filter { !isElectricity($0) }
        }
        if let selected = entry.factor {
            results.removeAll { $0.id == selected.id }
            results.insert(selected, at: 0)
        }
        return Array(results.prefix(80))
    }

    private func factorRow(_ factor: EmissionFactor) -> some View {
        let isSelected = entry.factor?.id == factor.id
        return Button {
            entry.factor = factor
            entry.remoteEstimate = nil
            if entry.activityUnit.isEmpty { entry.activityUnit = factor.activityUnit }
        } label: {
            HStack(alignment: .top) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(factor.name).font(.callout)
                    Text(GHGFormat.factorDetail(factor, gwp: inventory.gwpSet))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Full calculation for activity entries whose factor has a value; nil otherwise.
    private var calculation: (result: EmissionCalculationResult, factor: EmissionFactor)? {
        guard entry.method == .activity, let factor = entry.factor, factor.hasValue,
              let quantity = entry.activityQuantity,
              let result = try? EmissionCalculator.calculate(quantity: quantity, unit: entry.activityUnit,
                                                             factor: factor, gwp: inventory.gwpSet) else { return nil }
        return (result, factor)
    }

    private var previewSection: some View {
        let result = outcome
        return GroupBox("Result") {
            VStack(alignment: .leading, spacing: 6) {
                if let error = result.error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                } else if entry.method == .notationKey {
                    Text("Reported as \(entry.notationKey?.rawValue ?? "—"); no emissions added.")
                } else if let calculation {
                    EmissionResultView(result: calculation.result, factor: calculation.factor)
                } else {
                    Text(GHGFormat.tonnes(result.co2eTonnes)).font(.title2.weight(.semibold).monospacedDigit())
                    ForEach(result.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.yellow)
                    }
                }
                if let factor = entry.factor, entry.method == .activity, !factor.hasValue, factor.metadata["unit_type"] != nil {
                    climatiqEstimateButton(factor)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(6)
        }
    }

    private func climatiqEstimateButton(_ factor: EmissionFactor) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(estimating ? "Estimating…" : "Estimate with Climatiq") {
                guard let quantity = entry.activityQuantity else {
                    estimateMessage = "Enter a quantity first."
                    return
                }
                let unit = entry.activityUnit
                estimating = true
                Task {
                    defer { estimating = false }
                    do {
                        let kg = try await factorStore.estimateWithClimatiq(factor, quantity: quantity, unit: unit)
                        entry.remoteEstimate = GPCRemoteEstimate(quantity: quantity, unit: unit, co2eKg: kg, retrievedAt: Date())
                        estimateMessage = "Climatiq returned \(GHGFormat.number(kg)) kg CO2e."
                    } catch {
                        estimateMessage = error.localizedDescription
                    }
                }
            }
            .disabled(estimating)
            if !estimateMessage.isEmpty { Text(estimateMessage).font(.caption2).foregroundStyle(.secondary) }
        }
    }
}
