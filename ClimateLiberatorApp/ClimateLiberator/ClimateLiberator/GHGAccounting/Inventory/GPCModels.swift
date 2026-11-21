import Foundation

// MARK: - GPC (Global Protocol for Community-Scale GHG Emission Inventories)
//
// Structure follows GPC v1.1 (WRI, C40, ICLEI): six sectors, scope 1/2/3 by
// where emissions occur relative to the inventory boundary, and two reporting
// levels. BASIC = stationary energy & transport scopes 1–2 plus waste
// generated in the city (scope 1 and 3). BASIC+ adds IPPU, AFOLU, T&D losses
// and transboundary transport (GPC Box 4.1). Energy generation supplied to the
// grid (I.4.4) and imported waste (III.x.3) count only in the scope 1
// (territorial) total. Reference codes follow the GPC reporting template —
// confirm against GPC Table 4.3 before formal submission.

nonisolated enum GPCSector: String, Codable, CaseIterable, Identifiable, Sendable {
    case stationaryEnergy = "I"
    case transportation = "II"
    case waste = "III"
    case ippu = "IV"
    case afolu = "V"
    case otherScope3 = "VI"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .stationaryEnergy: return "Stationary energy"
        case .transportation: return "Transportation"
        case .waste: return "Waste"
        case .ippu: return "Industrial processes and product use (IPPU)"
        case .afolu: return "Agriculture, forestry and other land use (AFOLU)"
        case .otherScope3: return "Other scope 3"
        }
    }

    var shortTitle: String {
        switch self {
        case .stationaryEnergy: return "Stationary energy"
        case .transportation: return "Transport"
        case .waste: return "Waste"
        case .ippu: return "IPPU"
        case .afolu: return "AFOLU"
        case .otherScope3: return "Other scope 3"
        }
    }
}

nonisolated enum GPCScope: Int, Codable, CaseIterable, Identifiable, Sendable {
    case one = 1, two = 2, three = 3

    var id: Int { rawValue }
    var title: String { "Scope \(rawValue)" }

    var definition: String {
        switch self {
        case .one: return "Emitted inside the city boundary."
        case .two: return "Grid-supplied electricity, heat, steam or cooling used inside the boundary."
        case .three: return "Emitted outside the boundary because of activity inside it."
        }
    }
}

nonisolated enum GPCReportingLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case basic, basicPlus

    var id: String { rawValue }
    var title: String { self == .basic ? "BASIC" : "BASIC+" }
}

/// GPC notation keys (Table 2.1) for sources without a reported number.
nonisolated enum GPCNotationKey: String, Codable, CaseIterable, Identifiable, Sendable {
    case notOccurring = "NO"
    case includedElsewhere = "IE"
    case notEstimated = "NE"
    case confidential = "C"

    var id: String { rawValue }

    var meaning: String {
        switch self {
        case .notOccurring: return "Not occurring — the activity does not happen in the city."
        case .includedElsewhere: return "Included elsewhere — say where in the explanation."
        case .notEstimated: return "Not estimated — justify; the GPC discourages this."
        case .confidential: return "Confidential — data could disclose confidential information."
        }
    }
}

nonisolated enum GPCDataQuality: String, Codable, CaseIterable, Identifiable, Sendable {
    case high = "H", medium = "M", low = "L"

    var id: String { rawValue }
    var title: String {
        switch self {
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

nonisolated struct GPCSubSector: Identifiable, Hashable, Sendable {
    let id: String
    let sector: GPCSector
    let title: String
    let examples: String
}

nonisolated struct GPCReference: Identifiable, Hashable, Sendable {
    let id: String
    let subSectorID: String
    let sector: GPCSector
    let scope: GPCScope
    let title: String
    let inBasic: Bool
    let inBasicPlus: Bool

    /// Counted only in the scope 1 (territorial) total, e.g. I.4.4 and imported waste.
    var isTerritorialOnly: Bool { scope == .one && !inBasic && !inBasicPlus }

    func isRequired(for level: GPCReportingLevel) -> Bool { level == .basic ? inBasic : inBasicPlus }

    var inclusionLabel: String {
        if sector == .otherScope3 { return "Reported separately" }
        if isTerritorialOnly { return "Territorial total only" }
        if inBasic { return "BASIC & BASIC+" }
        if inBasicPlus { return "BASIC+ only" }
        return "Not in totals"
    }
}

nonisolated enum GPCCatalog {
    static let subSectors: [GPCSubSector] = [
        GPCSubSector(id: "I.1", sector: .stationaryEnergy, title: "Residential buildings", examples: "LPG, kerosene, firewood for cooking; household electricity"),
        GPCSubSector(id: "I.2", sector: .stationaryEnergy, title: "Commercial and institutional buildings and facilities", examples: "Shops, offices, hotels, hospitals, schools, street lighting, water pumping"),
        GPCSubSector(id: "I.3", sector: .stationaryEnergy, title: "Manufacturing industries and construction", examples: "Boilers, furnaces, captive DG sets, industrial electricity"),
        GPCSubSector(id: "I.4", sector: .stationaryEnergy, title: "Energy industries", examples: "Power plant auxiliary use; generation supplied to the grid"),
        GPCSubSector(id: "I.5", sector: .stationaryEnergy, title: "Agriculture, forestry and fishing activities", examples: "Irrigation pumps (diesel or grid), farm machinery at fixed sites"),
        GPCSubSector(id: "I.6", sector: .stationaryEnergy, title: "Non-specified sources", examples: "Energy use that cannot be allocated to another sub-sector"),
        GPCSubSector(id: "I.7", sector: .stationaryEnergy, title: "Fugitive emissions from coal mining, processing, storage and transport", examples: "Coal mines and yards inside the boundary"),
        GPCSubSector(id: "I.8", sector: .stationaryEnergy, title: "Fugitive emissions from oil and natural gas systems", examples: "City gas distribution leaks, venting, flaring"),
        GPCSubSector(id: "II.1", sector: .transportation, title: "On-road", examples: "Cars, two-wheelers, auto-rickshaws, buses, trucks; electric vehicles"),
        GPCSubSector(id: "II.2", sector: .transportation, title: "Railways", examples: "Diesel and electric trains, metro"),
        GPCSubSector(id: "II.3", sector: .transportation, title: "Waterborne navigation", examples: "Ferries, fishing boats, port vessels"),
        GPCSubSector(id: "II.4", sector: .transportation, title: "Aviation", examples: "Flights departing the city's airport"),
        GPCSubSector(id: "II.5", sector: .transportation, title: "Off-road", examples: "Construction equipment, airport ground vehicles, tractors"),
        GPCSubSector(id: "III.1", sector: .waste, title: "Solid waste disposal", examples: "Landfills and open dumps"),
        GPCSubSector(id: "III.2", sector: .waste, title: "Biological treatment of waste", examples: "Composting, anaerobic digestion / biogas"),
        GPCSubSector(id: "III.3", sector: .waste, title: "Incineration and open burning", examples: "Waste-to-energy plants, open burning of waste"),
        GPCSubSector(id: "III.4", sector: .waste, title: "Wastewater treatment and discharge", examples: "STPs, septic tanks, open drains"),
        GPCSubSector(id: "IV.1", sector: .ippu, title: "Industrial processes", examples: "Cement clinker, lime, chemicals, metals"),
        GPCSubSector(id: "IV.2", sector: .ippu, title: "Product use", examples: "Refrigerant (HFC) leakage, lubricants, solvents, SF6 in switchgear"),
        GPCSubSector(id: "V.1", sector: .afolu, title: "Livestock", examples: "Enteric fermentation, manure management"),
        GPCSubSector(id: "V.2", sector: .afolu, title: "Land", examples: "Forest, cropland, settlement land-use change; carbon stock change"),
        GPCSubSector(id: "V.3", sector: .afolu, title: "Aggregate sources and non-CO2 emissions on land", examples: "Rice cultivation, fertiliser N2O, biomass burning, liming, urea"),
        GPCSubSector(id: "VI.1", sector: .otherScope3, title: "Other scope 3", examples: "Embodied emissions of goods, food, construction materials"),
    ]

    static let references: [GPCReference] = {
        var list: [GPCReference] = []
        func add(_ id: String, _ sub: String, _ sector: GPCSector, _ scope: GPCScope, _ title: String, basic: Bool, basicPlus: Bool) {
            list.append(GPCReference(id: id, subSectorID: sub, sector: sector, scope: scope, title: title,
                                     inBasic: basic, inBasicPlus: basicPlus))
        }
        // Stationary energy I.1–I.3, I.5, I.6
        for sub in ["I.1", "I.2", "I.3", "I.4", "I.5", "I.6"] {
            if sub == "I.4" {
                add("I.4.1", sub, .stationaryEnergy, .one, "Energy used in power plant auxiliary operations within the boundary", basic: true, basicPlus: true)
                add("I.4.2", sub, .stationaryEnergy, .two, "Grid-supplied energy consumed in power plant auxiliary operations within the boundary", basic: true, basicPlus: true)
                add("I.4.3", sub, .stationaryEnergy, .three, "Transmission and distribution losses from grid energy used in auxiliary operations", basic: false, basicPlus: true)
                add("I.4.4", sub, .stationaryEnergy, .one, "Energy generation supplied to the grid", basic: false, basicPlus: false)
                continue
            }
            add("\(sub).1", sub, .stationaryEnergy, .one, "Fuel combustion within the city boundary", basic: true, basicPlus: true)
            add("\(sub).2", sub, .stationaryEnergy, .two, "Grid-supplied energy consumed within the city boundary", basic: true, basicPlus: true)
            add("\(sub).3", sub, .stationaryEnergy, .three, "Transmission and distribution losses from grid-supplied energy", basic: false, basicPlus: true)
        }
        add("I.7.1", "I.7", .stationaryEnergy, .one, "Fugitive emissions from coal within the city boundary", basic: true, basicPlus: true)
        add("I.8.1", "I.8", .stationaryEnergy, .one, "Fugitive emissions from oil and natural gas systems within the city boundary", basic: true, basicPlus: true)

        // Transportation
        for sub in ["II.1", "II.2", "II.3", "II.4"] {
            add("\(sub).1", sub, .transportation, .one, "Fuel combustion for trips occurring within the city boundary", basic: true, basicPlus: true)
            add("\(sub).2", sub, .transportation, .two, "Grid-supplied energy consumed within the boundary for this mode", basic: true, basicPlus: true)
            add("\(sub).3", sub, .transportation, .three, "Out-of-boundary portion of transboundary journeys, and T&D losses", basic: false, basicPlus: true)
        }
        add("II.5.1", "II.5", .transportation, .one, "Fuel combustion for off-road vehicles within the city boundary", basic: true, basicPlus: true)
        add("II.5.2", "II.5", .transportation, .two, "Grid-supplied energy consumed by off-road vehicles within the boundary", basic: true, basicPlus: true)

        // Waste
        for sub in ["III.1", "III.2", "III.3", "III.4"] {
            add("\(sub).1", sub, .waste, .one, "Waste generated in the city and treated within the boundary", basic: true, basicPlus: true)
            add("\(sub).2", sub, .waste, .three, "Waste generated in the city but treated outside the boundary", basic: true, basicPlus: true)
            add("\(sub).3", sub, .waste, .one, "Waste generated outside the city and treated within the boundary", basic: false, basicPlus: false)
        }

        // IPPU and AFOLU (scope 1, BASIC+)
        add("IV.1", "IV.1", .ippu, .one, "Industrial process emissions within the city boundary", basic: false, basicPlus: true)
        add("IV.2", "IV.2", .ippu, .one, "Product use emissions within the city boundary", basic: false, basicPlus: true)
        add("V.1", "V.1", .afolu, .one, "Livestock emissions within the city boundary", basic: false, basicPlus: true)
        add("V.2", "V.2", .afolu, .one, "Land emissions and removals within the city boundary", basic: false, basicPlus: true)
        add("V.3", "V.3", .afolu, .one, "Aggregate and non-CO2 sources on land within the city boundary", basic: false, basicPlus: true)

        add("VI.1", "VI.1", .otherScope3, .three, "Other scope 3 emissions", basic: false, basicPlus: false)
        return list
    }()

    private static let referenceIndex: [String: GPCReference] = Dictionary(uniqueKeysWithValues: references.map { ($0.id, $0) })

    static func reference(_ id: String) -> GPCReference? { referenceIndex[id] }

    static func subSector(_ id: String) -> GPCSubSector? { subSectors.first { $0.id == id } }

    static func subSectors(in sector: GPCSector) -> [GPCSubSector] { subSectors.filter { $0.sector == sector } }

    static func references(inSubSector id: String) -> [GPCReference] { references.filter { $0.subSectorID == id } }
}

/// Helps pick the GPC reference from where a waste stream is generated and treated.
nonisolated enum GPCScopeAdvisor {
    /// Returns nil when neither generation nor treatment is in the city (outside the inventory).
    static func wasteReference(subSectorID: String, generatedInCity: Bool, treatedInsideBoundary: Bool) -> String? {
        guard subSectorID.hasPrefix("III.") else { return nil }
        switch (generatedInCity, treatedInsideBoundary) {
        case (true, true): return "\(subSectorID).1"
        case (true, false): return "\(subSectorID).2"
        case (false, true): return "\(subSectorID).3"
        case (false, false): return nil
        }
    }

    /// Plain-language reminder of the scope rule for a reference.
    static func guidance(for reference: GPCReference) -> String {
        switch (reference.sector, reference.scope) {
        case (.stationaryEnergy, .one) where reference.id == "I.4.4":
            return "Report generation supplied to the grid for the territorial total only; city consumption of that power is counted in scope 2."
        case (.stationaryEnergy, .one): return "Fuel burned inside the boundary (LPG, diesel, coal, firewood…). Use fuel sales or consumption data."
        case (.stationaryEnergy, .two): return "Grid electricity consumed inside the boundary — discom sales by consumer category × grid factor."
        case (.stationaryEnergy, .three): return "T&D losses: grid electricity consumed × T&D loss share × grid factor."
        case (.transportation, .one): return "Fuel used for trips inside the boundary (fuel sales, or VKT × fuel economy)."
        case (.transportation, .two): return "Electricity for EVs, metro or rail charged inside the boundary."
        case (.transportation, .three): return "Out-of-boundary part of trips starting or ending in the city (e.g. departing flights)."
        case (.waste, .one): return reference.isTerritorialOnly
            ? "Waste brought in from outside and treated here — territorial total only."
            : "City waste treated at facilities inside the boundary."
        case (.waste, .three): return "City waste sent to landfills or plants outside the boundary."
        case (.ippu, _): return "Non-energy industrial process and product-use emissions inside the boundary."
        case (.afolu, _): return "Livestock, land-use change and land-based non-CO2 sources inside the boundary. Removals may be negative."
        default: return "Optional; reported separately from BASIC/BASIC+."
        }
    }
}

// MARK: - Inventory

nonisolated struct GeoCoordinate: Codable, Hashable, Sendable {
    var latitude: Double
    var longitude: Double
}

nonisolated enum GPCBoundaryType: String, Codable, CaseIterable, Identifiable, Sendable {
    case administrative, planningArea, custom

    var id: String { rawValue }
    var title: String {
        switch self {
        case .administrative: return "Administrative (municipal) boundary"
        case .planningArea: return "Local planning area"
        case .custom: return "Custom boundary"
        }
    }
}

/// A point source such as a landfill, STP or power plant, used for in/out-of-boundary checks.
nonisolated struct GPCFacility: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name: String
    var coordinate: GeoCoordinate
}

nonisolated enum GPCEntryMethod: String, Codable, CaseIterable, Identifiable, Sendable {
    case activity, directCO2e, notationKey

    var id: String { rawValue }
    var title: String {
        switch self {
        case .activity: return "Activity × emission factor"
        case .directCO2e: return "Direct CO2e (t)"
        case .notationKey: return "Notation key"
        }
    }
}

/// A Climatiq estimate stored with the inputs it was computed for.
nonisolated struct GPCRemoteEstimate: Codable, Hashable, Sendable {
    var quantity: Double
    var unit: String
    var co2eKg: Double
    var retrievedAt: Date
}

nonisolated struct GPCInventoryEntry: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var referenceID: String
    var label: String
    var method: GPCEntryMethod = .activity
    var activityQuantity: Double?
    var activityUnit: String = ""
    /// A snapshot of the factor used, so later database changes never rewrite history.
    var factor: EmissionFactor?
    var remoteEstimate: GPCRemoteEstimate?
    var directCO2eTonnes: Double?
    var notationKey: GPCNotationKey?
    var notationExplanation: String = ""
    var dataQuality: GPCDataQuality = .medium
    var dataSource: String = ""
    var facilityID: UUID?
    var notes: String = ""

    var reference: GPCReference? { GPCCatalog.reference(referenceID) }
}

nonisolated struct GPCInventory: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var cityName: String
    var region: String = ""
    var country: String = "India"
    var inventoryYear: Int
    var boundaryType: GPCBoundaryType = .administrative
    var boundarySource: String = ""
    var boundary = BoundaryPolygon()
    var facilities: [GPCFacility] = []
    var population: Int?
    var gwpSet: GWPSet = .ar6
    var targetLevel: GPCReportingLevel = .basic
    var entries: [GPCInventoryEntry] = []
    /// Optional so inventories saved before scenarios existed still load.
    var scenarios: [DecarbonizationScenario]?
    var createdAt = Date()
    var updatedAt = Date()

    var displayName: String { "\(cityName.isEmpty ? "Untitled city" : cityName) \(inventoryYear)" }

    var decarbonizationScenarios: [DecarbonizationScenario] {
        get { scenarios ?? [] }
        set { scenarios = newValue.isEmpty ? nil : newValue }
    }

    func facility(_ id: UUID?) -> GPCFacility? {
        guard let id else { return nil }
        return facilities.first { $0.id == id }
    }
}

// MARK: - Evaluation

nonisolated struct GPCEntryOutcome: Hashable, Sendable {
    /// Gas masses in tonnes.
    var gasesTonnes: GasAmounts
    var co2eTonnes: Double
    var warnings: [String]
    var error: String?

    static func failure(_ message: String) -> GPCEntryOutcome {
        GPCEntryOutcome(gasesTonnes: .zero, co2eTonnes: 0, warnings: [], error: message)
    }
}

nonisolated enum GPCCompletenessStatus: Hashable, Sendable {
    case reported
    case notation(GPCNotationKey)
    case missing
    case error(String)
}

nonisolated struct GPCCompletenessItem: Identifiable, Hashable, Sendable {
    let reference: GPCReference
    let status: GPCCompletenessStatus
    var id: String { reference.id }
}

nonisolated struct GPCInventorySummary: Sendable {
    var bySectorScope: [GPCSector: [GPCScope: Double]] = [:]
    var basicTotal = 0.0
    var basicPlusTotal = 0.0
    /// All scope 1 sources, including I.4.4 and imported waste.
    var territorialTotal = 0.0
    var scope2Total = 0.0
    /// Scope 3 within sectors I–V (other scope 3 is separate).
    var scope3Total = 0.0
    var otherScope3Total = 0.0
    var biogenicCO2Tonnes = 0.0
    var gasesBasicPlusTonnes = GasAmounts()
    var perCapitaBasic: Double?
    var perCapitaBasicPlus: Double?
    var outcomes: [UUID: GPCEntryOutcome] = [:]
    var completeness: [GPCCompletenessItem] = []

    func total(_ sector: GPCSector, _ scope: GPCScope) -> Double { bySectorScope[sector]?[scope] ?? 0 }

    var missingCount: Int {
        completeness.filter { if case .missing = $0.status { return true }; if case .error = $0.status { return true }; return false }.count
    }

    static func evaluate(_ entry: GPCInventoryEntry, gwp: GWPSet) -> GPCEntryOutcome {
        switch entry.method {
        case .notationKey:
            guard entry.notationKey != nil else { return .failure("Choose a notation key.") }
            return GPCEntryOutcome(gasesTonnes: .zero, co2eTonnes: 0, warnings: [], error: nil)
        case .directCO2e:
            guard let tonnes = entry.directCO2eTonnes, tonnes.isFinite else { return .failure("Enter tonnes CO2e.") }
            return GPCEntryOutcome(gasesTonnes: GasAmounts(otherCO2e: tonnes), co2eTonnes: tonnes,
                                   warnings: [], error: nil)
        case .activity:
            guard let quantity = entry.activityQuantity else { return .failure("Enter the activity quantity.") }
            guard let factor = entry.factor else { return .failure("Choose an emission factor.") }
            if !factor.hasValue {
                guard let estimate = entry.remoteEstimate,
                      estimate.quantity == quantity, estimate.unit == entry.activityUnit else {
                    return .failure("This factor has no value in the database. Run the Climatiq estimate for the current quantity.")
                }
                let tonnes = estimate.co2eKg / 1_000
                return GPCEntryOutcome(gasesTonnes: GasAmounts(otherCO2e: tonnes), co2eTonnes: tonnes,
                                       warnings: ["CO2e from Climatiq estimate (\(factor.co2eBasis?.title ?? "source GWP set"))."], error: nil)
            }
            do {
                let result = try EmissionCalculator.calculate(quantity: quantity, unit: entry.activityUnit, factor: factor, gwp: gwp)
                return GPCEntryOutcome(gasesTonnes: result.gasesKg.scaled(by: 0.001), co2eTonnes: result.co2eTonnes,
                                       warnings: result.warnings, error: nil)
            } catch {
                return .failure(error.localizedDescription)
            }
        }
    }

    static func make(_ inventory: GPCInventory) -> GPCInventorySummary {
        var summary = GPCInventorySummary()
        var referenceState: [String: (reported: Bool, notation: GPCNotationKey?, error: String?)] = [:]

        for entry in inventory.entries {
            guard let reference = entry.reference else {
                summary.outcomes[entry.id] = .failure("Unknown GPC reference \(entry.referenceID).")
                continue
            }
            let outcome = evaluate(entry, gwp: inventory.gwpSet)
            summary.outcomes[entry.id] = outcome
            var state = referenceState[reference.id] ?? (reported: false, notation: nil, error: nil)
            if let error = outcome.error {
                state.error = state.error ?? error
                referenceState[reference.id] = state
                continue
            }
            if entry.method == .notationKey {
                state.notation = state.notation ?? entry.notationKey
                referenceState[reference.id] = state
                continue
            }
            state.reported = true
            referenceState[reference.id] = state

            let value = outcome.co2eTonnes
            summary.bySectorScope[reference.sector, default: [:]][reference.scope, default: 0] += value
            summary.biogenicCO2Tonnes += outcome.gasesTonnes.co2Biogenic
            if reference.sector == .otherScope3 {
                summary.otherScope3Total += value
                continue
            }
            switch reference.scope {
            case .one: summary.territorialTotal += value
            case .two: summary.scope2Total += value
            case .three: summary.scope3Total += value
            }
            if reference.inBasic { summary.basicTotal += value }
            if reference.inBasicPlus {
                summary.basicPlusTotal += value
                summary.gasesBasicPlusTonnes = summary.gasesBasicPlusTonnes + outcome.gasesTonnes
            }
        }

        if let population = inventory.population, population > 0 {
            summary.perCapitaBasic = summary.basicTotal / Double(population)
            summary.perCapitaBasicPlus = summary.basicPlusTotal / Double(population)
        }

        summary.completeness = GPCCatalog.references
            .filter { $0.isRequired(for: inventory.targetLevel) }
            .map { reference in
                let state = referenceState[reference.id]
                let status: GPCCompletenessStatus
                if state?.reported == true { status = .reported }
                else if let key = state?.notation { status = .notation(key) }
                else if let error = state?.error { status = .error(error) }
                else { status = .missing }
                return GPCCompletenessItem(reference: reference, status: status)
            }
        return summary
    }
}
