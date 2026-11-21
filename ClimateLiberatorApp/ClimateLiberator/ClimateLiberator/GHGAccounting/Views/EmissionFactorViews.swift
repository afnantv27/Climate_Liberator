import SwiftUI
import UniformTypeIdentifiers

// MARK: - Calculator

/// Activity × factor calculator across every connected database. Laid out as one
/// column so it fits the Tools side panel next to any pipeline step.
struct EmissionFactorCalculatorView: View {
    @ObservedObject var factorStore: EmissionFactorLibraryStore
    @ObservedObject var inventoryStore: GPCInventoryStore
    let accent: Color
    let onAddedToInventory: () -> Void

    @State private var query = ""
    @State private var dimensionFilter: UnitDimension?
    @State private var selectedFactorID: String?
    @State private var quantityText = "1000"
    @State private var unit = ""
    @State private var gwp: GWPSet = .ar6
    @State private var targetReferenceID = "I.1.1"
    @State private var remoteCO2eKg: Double?
    @State private var remoteMessage = ""
    @State private var estimating = false
    @State private var addedMessage = ""

    private var selectedFactor: EmissionFactor? { selectedFactorID.flatMap { factorStore.factor(id: $0) } }
    private var quantity: Double? { EmissionFactorConnectorService.parseNumber(quantityText) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                searchSection
                if let factor = selectedFactor {
                    calculationSection(factor)
                    addToInventorySection(factor)
                } else {
                    Text("Pick a factor above, then enter your activity. Units convert automatically (e.g. litres of diesel → kg → TJ).")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                }
            }
            .padding(.bottom, 12)
        }
    }

    private var searchSection: some View {
        let results = factorStore.search(query, dimension: dimensionFilter, limit: 150)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                TextField("Search, e.g. LPG commercial", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { Task { await factorStore.searchRemote(query) } }
                Button { Task { await factorStore.searchRemote(query) } } label: { Image(systemName: "globe") }
                    .help("Search connected online databases")
                    .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty || !factorStore.syncingConnectorIDs.isEmpty)
            }
            HStack {
                Picker("Unit type", selection: $dimensionFilter) {
                    Text("Any unit").tag(UnitDimension?.none)
                    ForEach(UnitDimension.allCases, id: \.self) { Text($0.title).tag(Optional($0)) }
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                Spacer()
                if !factorStore.syncingConnectorIDs.isEmpty { ProgressView().controlSize(.small) }
                Text("\(results.count) of \(factorStore.factorCount)").font(.caption2).foregroundStyle(.white.opacity(0.55))
            }
            List(results, id: \.id, selection: $selectedFactorID) { factor in
                VStack(alignment: .leading, spacing: 2) {
                    Text(factor.name).font(.callout).lineLimit(2)
                    Text(GHGFormat.factorDetail(factor, gwp: gwp)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                .tag(factor.id)
            }
            .frame(height: 220)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .onChange(of: selectedFactorID) { _, _ in
                remoteCO2eKg = nil
                remoteMessage = ""
                addedMessage = ""
                if let factor = selectedFactor, UnitRegistry.resolve(unit) == nil || !EmissionFactorLibraryStore.isCompatible(factor, with: UnitRegistry.resolve(unit)?.dimension) {
                    unit = factor.activityUnit
                }
            }
        }
    }

    private func calculationSection(_ factor: EmissionFactor) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                TextField("Quantity", text: $quantityText).textFieldStyle(.roundedBorder)
                TextField("Unit", text: $unit).textFieldStyle(.roundedBorder).frame(width: 70)
                Menu {
                    ForEach(compatibleUnits(factor), id: \.self) { symbol in Button(symbol) { unit = symbol } }
                } label: { Image(systemName: "ruler") }
                .menuStyle(.button)
                .buttonStyle(.borderless)
                .frame(width: 34)
                .help("Units this factor accepts")
                Picker("GWP", selection: $gwp) {
                    ForEach(GWPSet.allCases) { Text($0.title).tag($0) }
                }
                .labelsHidden()
                .frame(width: 76)
                .help("IPCC assessment report used for global warming potentials")
            }
            resultView(factor)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }

    @ViewBuilder
    private func resultView(_ factor: EmissionFactor) -> some View {
        if !factor.hasValue {
            VStack(alignment: .leading, spacing: 6) {
                Text("This database returned no numeric value for the factor (often a plan restriction).").font(.caption)
                if factor.metadata["unit_type"] != nil {
                    Button(estimating ? "Estimating…" : "Estimate with Climatiq") { runEstimate(factor) }
                        .disabled(estimating || quantity == nil)
                }
                if let kg = remoteCO2eKg {
                    Text("\(GHGFormat.mass(kg)) CO2e").font(.title2.weight(.semibold).monospacedDigit())
                }
                if !remoteMessage.isEmpty { Text(remoteMessage).font(.caption).foregroundStyle(.white.opacity(0.7)) }
            }
        } else if let quantity {
            switch Result(catching: { try EmissionCalculator.calculate(quantity: quantity, unit: unit, factor: factor, gwp: gwp) }) {
            case .success(let result):
                EmissionResultView(result: result, factor: factor)
            case .failure(let error):
                Label(error.localizedDescription, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        } else {
            Text("Enter a numeric quantity.").font(.caption).foregroundStyle(.orange)
        }
    }

    private func compatibleUnits(_ factor: EmissionFactor) -> [String] {
        UnitDimension.allCases
            .filter { EmissionFactorLibraryStore.isCompatible(factor, with: $0) }
            .flatMap { UnitRegistry.symbolsByDimension[$0] ?? [] }
    }

    private func runEstimate(_ factor: EmissionFactor) {
        guard let quantity else { return }
        estimating = true
        let unitSymbol = unit.isEmpty ? factor.activityUnit : unit
        Task {
            defer { estimating = false }
            do {
                remoteCO2eKg = try await factorStore.estimateWithClimatiq(factor, quantity: quantity, unit: unitSymbol)
                remoteMessage = "Calculated by Climatiq for \(GHGFormat.plain(quantity)) \(unitSymbol)."
            } catch {
                remoteMessage = error.localizedDescription
            }
        }
    }

    private func addToInventorySection(_ factor: EmissionFactor) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(inventoryStore.selected.map { "Add to \($0.displayName)" } ?? "Create an inventory to add this line")
                .font(.callout.weight(.semibold))
            Picker("GPC source", selection: $targetReferenceID) {
                ForEach(GPCCatalog.references) { reference in
                    Text("\(reference.id) · \(GPCCatalog.subSector(reference.subSectorID)?.title ?? "") (\(reference.scope.title))").tag(reference.id)
                }
            }
            .labelsHidden()
            HStack {
                Button("Add Entry") {
                    var entry = GPCInventoryEntry(referenceID: targetReferenceID, label: factor.name)
                    entry.activityQuantity = quantity
                    entry.activityUnit = unit.isEmpty ? factor.activityUnit : unit
                    entry.factor = factor
                    if let kg = remoteCO2eKg, let quantity {
                        entry.remoteEstimate = GPCRemoteEstimate(quantity: quantity, unit: entry.activityUnit, co2eKg: kg, retrievedAt: Date())
                    }
                    inventoryStore.upsertEntry(entry)
                    addedMessage = "Added under \(targetReferenceID). Edit it in Activity data."
                    onAddedToInventory()
                }
                .buttonStyle(.borderedProminent)
                .tint(accent)
                .disabled(inventoryStore.selected == nil || quantity == nil)
                if !addedMessage.isEmpty {
                    Label(addedMessage, systemImage: "checkmark.circle.fill").font(.caption2).foregroundStyle(.green)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

// MARK: - Databases

struct EmissionFactorDatabasesView: View {
    @ObservedObject var store: EmissionFactorLibraryStore
    let accent: Color

    @State private var editing: EmissionFactorConnector?
    @State private var queries: [String: String] = [:]
    @State private var showingCustomFactor = false
    @State private var importingCSV = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                GHGPanelCard(title: "Databases",
                             subtitle: "Connect Climatiq, a CSV on the web, or a JSON/REST API (Supabase, Airtable, in-house). API keys stay in your macOS Keychain.") {
                    HStack {
                        Menu {
                            ForEach(EmissionFactorConnector.Preset.allCases) { preset in
                                Button(preset.title) { editing = store.addConnector(preset) }
                            }
                        } label: {
                            Label("Add Database", systemImage: "plus")
                        }
                        .fixedSize()
                        Spacer()
                    }
                    Text(store.statusMessage).font(.caption).foregroundStyle(.white.opacity(0.7))
                    ForEach(store.lastWarnings, id: \.self) { warning in
                        Label(warning, systemImage: "info.circle").font(.caption).foregroundStyle(.yellow)
                    }
                }
                ForEach(store.connectors) { connector in
                    connectorCard(connector)
                }
                customFactorsCard
            }
            .padding(.bottom, 20)
        }
        .sheet(item: $editing) { connector in
            ConnectorEditorView(store: store, connector: connector)
        }
        .sheet(isPresented: $showingCustomFactor) {
            CustomFactorSheet { store.saveCustomFactor($0) }
        }
        .fileImporter(isPresented: $importingCSV, allowedContentTypes: [.commaSeparatedText, .plainText], allowsMultipleSelection: false) { result in
            if case .success(let urls) = result, let url = urls.first {
                store.importCustomCSV(from: url, mapping: .standardCSV)
            }
        }
    }

    private func connectorCard(_ connector: EmissionFactorConnector) -> some View {
        let syncing = store.syncingConnectorIDs.contains(connector.id)
        let missingKey = connector.needsSecret && !store.hasSecret(for: connector.id)
        return GHGPanelCard(title: connector.name, subtitle: connector.kind.title) {
            HStack(spacing: 10) {
                Toggle("Enabled", isOn: Binding(get: { connector.isEnabled },
                                                set: { store.setEnabled($0, connectorID: connector.id) }))
                    .toggleStyle(.switch)
                    .controlSize(.small)
                    .labelsHidden()
                Text(connector.kind == .bundled ? "\(EmissionFactorSeedLibrary.factors.count) built-in factors"
                                                : "\(connector.factorCount) cached")
                    .font(.caption)
                Spacer()
                if connector.kind != .bundled {
                    Button { editing = connector } label: { Image(systemName: "pencil") }
                        .help("Edit connection")
                    Button(role: .destructive) { store.removeConnector(id: connector.id) } label: { Image(systemName: "trash") }
                        .help("Remove database")
                }
            }
            if let date = connector.lastSyncedAt {
                Text("Synced \(date.formatted(date: .abbreviated, time: .shortened))").font(.caption2).foregroundStyle(.white.opacity(0.6))
            }
            if missingKey {
                Label("API key missing — open Edit to add it.", systemImage: "key.fill").font(.caption).foregroundStyle(.orange)
            }
            if let status = connector.lastStatus {
                Text(status).font(.caption).foregroundStyle(.white.opacity(0.7))
            }
            if connector.kind != .bundled {
                HStack {
                    if connector.supportsRemoteSearch {
                        TextField("Search term to fetch (e.g. electricity India)", text: Binding(
                            get: { queries[connector.id] ?? "" }, set: { queries[connector.id] = $0 }))
                            .textFieldStyle(.roundedBorder)
                    }
                    Button(syncing ? "Fetching…" : (connector.supportsRemoteSearch ? "Fetch & cache" : "Download all")) {
                        Task { await store.sync(connectorID: connector.id, query: queries[connector.id] ?? "") }
                    }
                    .disabled(syncing || missingKey || !connector.isEnabled)
                    if syncing { ProgressView().controlSize(.small) }
                }
            }
        }
    }

    private var customFactorsCard: some View {
        GHGPanelCard(title: "Your Own Factors",
                     subtitle: "Supplier-specific or local factors. CSV import expects columns: name, unit (e.g. kg/kWh), co2e — optional co2, ch4, n2o, region, year, source, category, gwp.") {
            HStack {
                Button("Add Factor") { showingCustomFactor = true }
                Button("Import CSV file…") { importingCSV = true }
            }
            ForEach(store.customFactors) { factor in
                HStack {
                    VStack(alignment: .leading) {
                        Text(factor.name).font(.callout)
                        Text(GHGFormat.factorDetail(factor, gwp: .ar6)).font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    Button { store.removeCustomFactor(id: factor.id) } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                }
            }
        }
    }
}

// MARK: - Connector editor

struct ConnectorEditorView: View {
    @ObservedObject var store: EmissionFactorLibraryStore
    @State private var connector: EmissionFactorConnector
    @State private var secret = ""
    @State private var testQuery = "electricity"
    @State private var testing = false
    @State private var preview: [EmissionFactor] = []
    @State private var previewMessages: [String] = []
    @Environment(\.dismiss) private var dismiss

    init(store: EmissionFactorLibraryStore, connector: EmissionFactorConnector) {
        _store = ObservedObject(wrappedValue: store)
        _connector = State(initialValue: connector)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Database: \(connector.name)").font(.title2.weight(.semibold))
            Form {
                Section("Connection") {
                    TextField("Name", text: $connector.name)
                    TextField(connector.kind == .climatiq ? "Search endpoint" : "URL (use {query} for live search)", text: $connector.urlTemplate)
                    if connector.kind == .csv {
                        TextField("Delimiter (\",\", \";\" or tab)", text: $connector.csvDelimiter)
                    }
                    Picker("Published CO2e uses", selection: $connector.defaultGWPBasis) {
                        Text("Not stated").tag(GWPSet?.none)
                        ForEach(GWPSet.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                }
                Section("Authentication") {
                    if connector.kind != .climatiq {
                        Picker("Method", selection: $connector.authStyle) {
                            ForEach(ConnectorAuthStyle.allCases) { Text($0.title).tag($0) }
                        }
                        if connector.authStyle == .header || connector.authStyle == .query {
                            TextField("Header / parameter name (e.g. apikey, x-api-key)", text: $connector.authName)
                        }
                    }
                    if connector.needsSecret {
                        SecureField(store.hasSecret(for: connector.id) ? "Saved — type to replace" : "API key", text: $secret)
                        if store.hasSecret(for: connector.id) {
                            Button("Remove Saved Key", role: .destructive) { store.setSecret("", for: connector.id) }
                        }
                    }
                }
                if connector.kind == .climatiq {
                    Section("Climatiq") {
                        TextField("Data version (e.g. ^37)", text: $connector.climatiqDataVersion)
                        TextField("Region filter (ISO code, e.g. IN; blank = all)", text: $connector.climatiqRegion)
                    }
                } else {
                    mappingSection
                }
                Section("Test") {
                    HStack {
                        TextField("Test search term", text: $testQuery)
                        Button(testing ? "Testing…" : "Test connection") { runTest() }.disabled(testing)
                    }
                    ForEach(previewMessages, id: \.self) { Text($0).font(.caption) }
                    ForEach(preview.prefix(8), id: \.id) { factor in
                        Text("\(factor.name) — \(GHGFormat.factorValue(factor, gwp: .ar6))").font(.caption)
                    }
                }
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    store.updateConnector(connector)
                    if !secret.isEmpty { store.setSecret(secret, for: connector.id) }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 640, height: 720)
    }

    private var mappingSection: some View {
        Section("Field mapping (\(connector.kind == .csv ? "CSV column headers" : "JSON dot paths, e.g. fields.Name"))") {
            if connector.kind == .json {
                TextField("Records array path (blank = top-level array)", text: $connector.mapping.resultsPath)
            }
            TextField("Name", text: $connector.mapping.name)
            TextField("Unit, e.g. kg/kWh", text: $connector.mapping.unit)
            TextField("…or activity unit only (e.g. kWh)", text: $connector.mapping.activityUnit)
            TextField("Mass unit of values when only activity unit is given", text: $connector.mapping.numeratorUnit)
            TextField("CO2e value", text: $connector.mapping.co2e)
            TextField("CO2 value", text: $connector.mapping.co2)
            TextField("CH4 value", text: $connector.mapping.ch4)
            TextField("N2O value", text: $connector.mapping.n2o)
            TextField("GWP basis (AR5/AR6)", text: $connector.mapping.gwpBasis)
            TextField("Region", text: $connector.mapping.region)
            TextField("Year", text: $connector.mapping.year)
            TextField("Category", text: $connector.mapping.category)
            TextField("Source", text: $connector.mapping.source)
            TextField("Unique ID", text: $connector.mapping.id)
        }
    }

    private func runTest() {
        testing = true
        preview = []
        previewMessages = []
        let candidate = connector
        let key = secret.isEmpty ? store.secrets.secret(for: connector.id) : secret
        Task {
            defer { testing = false }
            switch await store.test(candidate, secret: key, query: testQuery) {
            case .success(let report):
                preview = report.factors
                previewMessages = ["\(report.factors.count) factor(s) read, \(report.skipped) skipped."] + report.warnings
            case .failure(let error):
                previewMessages = [error.localizedDescription]
            }
        }
    }
}

// MARK: - Custom factor

struct CustomFactorSheet: View {
    let onSave: (EmissionFactor) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var unit = "kWh"
    @State private var useGases = false
    @State private var co2eText = ""
    @State private var co2Text = ""
    @State private var ch4Text = ""
    @State private var n2oText = ""
    @State private var basis: GWPSet? = .ar6
    @State private var source = ""
    @State private var region = "India"
    @State private var yearText = ""
    @State private var notes = ""

    private func number(_ text: String) -> Double? { EmissionFactorConnectorService.parseNumber(text) }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && UnitRegistry.resolve(unit) != nil
            && (useGases ? [co2Text, ch4Text, n2oText].contains { number($0) != nil } : number(co2eText) != nil)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add Custom Factor").font(.title2.weight(.semibold))
            Form {
                TextField("Name", text: $name)
                TextField("Per activity unit (e.g. kWh, L, kg, km, INR)", text: $unit)
                if !unit.isEmpty, UnitRegistry.resolve(unit) == nil {
                    Text("Unit not recognised.").font(.caption).foregroundStyle(.orange)
                }
                Toggle("Enter individual gases (lets the app re-weight with any GWP set)", isOn: $useGases)
                if useGases {
                    TextField("kg CO2 per unit", text: $co2Text)
                    TextField("kg CH4 per unit", text: $ch4Text)
                    TextField("kg N2O per unit", text: $n2oText)
                } else {
                    TextField("kg CO2e per unit", text: $co2eText)
                    Picker("CO2e uses", selection: $basis) {
                        Text("Not stated").tag(GWPSet?.none)
                        ForEach(GWPSet.allCases) { Text($0.title).tag(Optional($0)) }
                    }
                }
                TextField("Source (publication, supplier)", text: $source)
                TextField("Region", text: $region)
                TextField("Year", text: $yearText)
                TextField("Notes", text: $notes)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Save") {
                    onSave(makeFactor())
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
        }
        .padding(20)
        .frame(width: 520, height: 600)
    }

    private func makeFactor() -> EmissionFactor {
        let externalID = UUID().uuidString
        var gases: GasAmounts?
        if useGases {
            gases = GasAmounts(co2: number(co2Text) ?? 0, ch4NonFossil: number(ch4Text) ?? 0, n2o: number(n2oText) ?? 0)
        }
        return EmissionFactor(
            id: "\(EmissionFactorLibraryStore.customConnectorID):\(externalID)",
            externalID: externalID,
            name: name.trimmingCharacters(in: .whitespaces),
            category: "Custom",
            region: region,
            year: Int(yearText.trimmingCharacters(in: .whitespaces)),
            activityUnit: UnitRegistry.resolve(unit)?.symbol ?? unit,
            gases: gases,
            co2ePerUnit: useGases ? nil : number(co2eText),
            co2eBasis: useGases ? nil : basis,
            source: source.isEmpty ? "User defined" : source,
            sourceURL: nil,
            connectorID: EmissionFactorLibraryStore.customConnectorID,
            notes: notes.isEmpty ? nil : notes,
            retrievedAt: Date(),
            uncertaintyPercent: nil,
            densityKgPerLitre: nil,
            netCalorificValueMJPerKg: nil
        )
    }
}
