import Foundation

// MARK: - GHG accounting core: gases, GWP sets, units and emission factors
//
// This module is a separate track from the physical-risk core (see
// docs/product-architecture.md §9). It never imports hazard, exposure or
// financial types, so the wildfire → BRSR slice is unaffected.
//
// Conventions
// - Every emission-factor value is stored in kilograms of gas per ONE activity
//   unit (`EmissionFactor.activityUnit`). Connectors normalise tonnes/grams on
//   ingestion so the calculator never has to guess the numerator unit.
// - Biogenic CO2 is tracked but excluded from CO2e totals (GPC Box 4.2 asks for
//   it to be reported separately).

/// IPCC assessment report used for 100-year global warming potentials.
nonisolated enum GWPSet: String, Codable, CaseIterable, Identifiable, Sendable {
    case ar4, ar5, ar6

    var id: String { rawValue }
    var title: String { rawValue.uppercased() }

    /// 100-year GWPs. AR6: IPCC AR6 WGI Table 7.15 (CH4 fossil 29.8, non-fossil
    /// 27.0, N2O 273). The GHG Protocol (Aug 2024) asks for the fossil value only
    /// for fugitive/process fossil methane; combustion methane uses non-fossil.
    var ch4Fossil: Double {
        switch self { case .ar4: return 25; case .ar5: return 28; case .ar6: return 29.8 }
    }
    var ch4NonFossil: Double {
        switch self { case .ar4: return 25; case .ar5: return 28; case .ar6: return 27.0 }
    }
    var n2o: Double {
        switch self { case .ar4: return 298; case .ar5: return 265; case .ar6: return 273 }
    }
    var sf6: Double {
        switch self { case .ar4: return 22_800; case .ar5: return 23_500; case .ar6: return 25_200 }
    }
    var nf3: Double {
        switch self { case .ar4: return 17_200; case .ar5: return 16_100; case .ar6: return 17_400 }
    }
}

/// Mass of each gas, in kilograms. Used both per activity unit (inside a factor)
/// and as absolute amounts (inside a result).
nonisolated struct GasAmounts: Codable, Hashable, Sendable {
    var co2: Double = 0
    /// Reported separately; never added to CO2e totals.
    var co2Biogenic: Double = 0
    var ch4Fossil: Double = 0
    var ch4NonFossil: Double = 0
    var n2o: Double = 0
    var sf6: Double = 0
    var nf3: Double = 0
    /// HFCs, PFCs or any gas a source only publishes as CO2e.
    var otherCO2e: Double = 0

    static let zero = GasAmounts()

    var isEmpty: Bool {
        co2 == 0 && co2Biogenic == 0 && ch4Fossil == 0 && ch4NonFossil == 0
            && n2o == 0 && sf6 == 0 && nf3 == 0 && otherCO2e == 0
    }

    var ch4Total: Double { ch4Fossil + ch4NonFossil }

    func co2e(_ gwp: GWPSet) -> Double {
        co2 + ch4Fossil * gwp.ch4Fossil + ch4NonFossil * gwp.ch4NonFossil
            + n2o * gwp.n2o + sf6 * gwp.sf6 + nf3 * gwp.nf3 + otherCO2e
    }

    func scaled(by factor: Double) -> GasAmounts {
        GasAmounts(co2: co2 * factor, co2Biogenic: co2Biogenic * factor,
                   ch4Fossil: ch4Fossil * factor, ch4NonFossil: ch4NonFossil * factor,
                   n2o: n2o * factor, sf6: sf6 * factor, nf3: nf3 * factor,
                   otherCO2e: otherCO2e * factor)
    }

    static func + (lhs: GasAmounts, rhs: GasAmounts) -> GasAmounts {
        GasAmounts(co2: lhs.co2 + rhs.co2, co2Biogenic: lhs.co2Biogenic + rhs.co2Biogenic,
                   ch4Fossil: lhs.ch4Fossil + rhs.ch4Fossil, ch4NonFossil: lhs.ch4NonFossil + rhs.ch4NonFossil,
                   n2o: lhs.n2o + rhs.n2o, sf6: lhs.sf6 + rhs.sf6, nf3: lhs.nf3 + rhs.nf3,
                   otherCO2e: lhs.otherCO2e + rhs.otherCO2e)
    }
}

// MARK: - Units

nonisolated enum UnitDimension: String, Codable, CaseIterable, Sendable {
    case energy, mass, volume, distance, freightDistance, passengerDistance, area, time, count, money

    var title: String {
        switch self {
        case .energy: return "Energy"
        case .mass: return "Mass"
        case .volume: return "Volume"
        case .distance: return "Distance"
        case .freightDistance: return "Freight (mass × distance)"
        case .passengerDistance: return "Passenger distance"
        case .area: return "Area"
        case .time: return "Time"
        case .count: return "Count"
        case .money: return "Spend"
        }
    }
}

/// A resolved unit: its dimension and the multiplier to the dimension's base
/// unit (energy kWh, mass kg, volume L, distance km, freight t·km,
/// passenger p·km, area m², time h, count 1, money 1 of `currency`).
nonisolated struct UnitDefinition: Hashable, Sendable {
    let symbol: String
    let dimension: UnitDimension
    let toBase: Double
    /// ISO 4217 code for money units, otherwise nil.
    let currency: String?
}

nonisolated enum UnitRegistry {
    private static let table: [(symbol: String, dimension: UnitDimension, toBase: Double, aliases: [String])] = [
        // Energy (base kWh)
        ("Wh", .energy, 0.001, ["watthour", "watt-hour"]),
        // "units" is how Indian electricity bills express kWh.
        ("kWh", .energy, 1, ["kilowatthour", "kilowatt-hour", "kilowatthours", "units"]),
        ("MWh", .energy, 1_000, ["megawatthour", "megawatt-hour"]),
        ("GWh", .energy, 1_000_000, ["gigawatthour"]),
        ("kJ", .energy, 1.0 / 3_600, ["kilojoule"]),
        ("MJ", .energy, 1.0 / 3.6, ["megajoule", "megajoules"]),
        ("GJ", .energy, 1_000.0 / 3.6, ["gigajoule", "gigajoules"]),
        ("TJ", .energy, 1_000_000.0 / 3.6, ["terajoule", "terajoules"]),
        ("therm", .energy, 29.307_107, ["therms", "thm"]),
        ("MMBtu", .energy, 293.071_07, ["mmbtu", "million btu"]),
        // Mass (base kg)
        ("g", .mass, 0.001, ["gram", "grams"]),
        ("kg", .mass, 1, ["kilogram", "kilograms", "kgs"]),
        ("t", .mass, 1_000, ["tonne", "tonnes", "metric ton", "metric tons", "metric tonne", "ton (metric)"]),
        ("kt", .mass, 1_000_000, ["kilotonne", "kilotonnes", "gg", "gigagram"]),
        ("Mt", .mass, 1_000_000_000, ["megatonne", "megatonnes"]),
        ("lb", .mass, 0.453_592_37, ["lbs", "pound", "pounds"]),
        ("short ton", .mass, 907.184_74, ["short tons", "us ton"]),
        // Volume (base litre)
        ("mL", .volume, 0.001, ["millilitre", "milliliter", "ml"]),
        ("L", .volume, 1, ["l", "litre", "liter", "litres", "liters", "ltr"]),
        ("kL", .volume, 1_000, ["kilolitre", "kiloliter", "kl"]),
        ("m3", .volume, 1_000, ["m³", "cubic metre", "cubic meter", "cubic metres", "cubic meters", "scm", "cbm"]),
        ("US gal", .volume, 3.785_411_784, ["gal", "gallon", "gallons", "gallon_us", "us gallon"]),
        ("UK gal", .volume, 4.546_09, ["gallon_uk", "imperial gallon", "uk gallon"]),
        ("bbl", .volume, 158.987_294_928, ["barrel", "barrels"]),
        ("ft3", .volume, 28.316_846_592, ["cubic foot", "cubic feet", "cf"]),
        // Distance (base km)
        ("m", .distance, 0.001, ["metre", "meter", "metres", "meters"]),
        ("km", .distance, 1, ["kilometre", "kilometer", "kilometres", "kilometers", "vkm", "vehicle-km"]),
        ("mi", .distance, 1.609_344, ["mile", "miles", "vehicle-mile"]),
        ("nmi", .distance, 1.852, ["nautical mile", "nautical miles"]),
        // Freight (base tonne-km)
        ("t·km", .freightDistance, 1, ["tkm", "t.km", "t-km", "tonne-km", "tonne.km", "tonne km", "tonnekm", "tonne-kilometre", "tonne-kilometer"]),
        ("kg·km", .freightDistance, 0.001, ["kg.km", "kg-km", "kgkm"]),
        // Passenger distance (base passenger-km)
        ("p·km", .passengerDistance, 1, ["pkm", "p.km", "p-km", "passenger-km", "passenger.km", "passenger km", "passengerkm"]),
        ("p·mi", .passengerDistance, 1.609_344, ["passenger-mile", "passenger mile", "pmi"]),
        // Area (base m²)
        ("m2", .area, 1, ["m²", "sqm", "square metre", "square meter"]),
        ("ha", .area, 10_000, ["hectare", "hectares"]),
        ("km2", .area, 1_000_000, ["km²", "square kilometre", "square kilometer"]),
        // Time (base hour)
        ("h", .time, 1, ["hr", "hrs", "hour", "hours"]),
        ("day", .time, 24, ["days", "d"]),
        // Count (base 1)
        ("item", .count, 1, ["items", "unit-count", "number", "each", "no", "nos", "piece", "pieces",
                             "room-night", "room night", "night", "nights", "head", "heads", "vehicle", "vehicles"]),
        ("person", .count, 1, ["persons", "people", "capita", "inhabitant", "inhabitants", "person-year"]),
    ]

    private static let currencyCodes: Set<String> = [
        "INR", "USD", "EUR", "GBP", "JPY", "CNY", "AUD", "CAD", "CHF", "SGD", "AED", "NZD", "ZAR", "BRL",
        "SEK", "NOK", "DKK", "BDT", "LKR", "NPR", "IDR", "MYR", "THB", "KRW", "MXN", "SAR", "HKD"
    ]

    /// "MT" means metric tonne in much Indian reporting but megatonne in SI ("Mt").
    /// A wrong guess is a 1,000,000× error, so these spellings are rejected.
    static let ambiguousKeys: Set<String> = ["mt"]

    private static let lookup: [String: UnitDefinition] = {
        var map: [String: UnitDefinition] = [:]
        for entry in table {
            let definition = UnitDefinition(symbol: entry.symbol, dimension: entry.dimension,
                                            toBase: entry.toBase, currency: nil)
            for key in [entry.symbol] + entry.aliases where !ambiguousKeys.contains(normalizedKey(key)) {
                map[normalizedKey(key)] = definition
            }
        }
        return map
    }()

    /// All canonical symbols, grouped for pickers.
    static var symbolsByDimension: [UnitDimension: [String]] {
        var grouped: [UnitDimension: [String]] = [:]
        for entry in table { grouped[entry.dimension, default: []].append(entry.symbol) }
        grouped[.money] = currencyCodes.sorted()
        return grouped
    }

    static func normalizedKey(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "·", with: ".")
            .lowercased()
    }

    /// Resolves a unit symbol or alias. Currency codes (e.g. "INR", "usd") resolve to money.
    static func resolve(_ raw: String) -> UnitDefinition? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // Case-sensitive check first so "Mt" (megatonne) is not read as "mt".
        if let exact = table.first(where: { $0.symbol == trimmed }) {
            return UnitDefinition(symbol: exact.symbol, dimension: exact.dimension, toBase: exact.toBase, currency: nil)
        }
        if ambiguousKeys.contains(normalizedKey(trimmed)) { return nil }
        if let found = lookup[normalizedKey(trimmed)] { return found }
        // Only known ISO codes count as money, so a typo never silently becomes spend.
        let upper = trimmed.uppercased()
        if currencyCodes.contains(upper) {
            return UnitDefinition(symbol: upper, dimension: .money, toBase: 1, currency: upper)
        }
        return nil
    }

    /// Converts `value` between two units of the same dimension.
    static func convert(_ value: Double, from: UnitDefinition, to: UnitDefinition) -> Double? {
        guard from.dimension == to.dimension else { return nil }
        if from.dimension == .money, from.currency != to.currency { return nil }
        return value * from.toBase / to.toBase
    }
}

/// Parsed emission-factor unit such as "kg/kWh", "tCO2e per MWh" or "kg CO2e / litre".
nonisolated struct FactorUnitExpression: Hashable, Sendable {
    /// Multiplier that turns the published numerator into kilograms.
    let numeratorToKg: Double
    let activityUnit: UnitDefinition

    static func parse(_ raw: String) -> FactorUnitExpression? {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        let parts: [String]
        if let range = text.range(of: " per ", options: .caseInsensitive) {
            parts = [String(text[..<range.lowerBound]), String(text[range.upperBound...])]
        } else {
            parts = text.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        }
        guard parts.count == 2 else { return nil }
        guard let activity = UnitRegistry.resolve(parts[1]) else { return nil }
        let numerator = parseMassNumerator(parts[0])
        guard let numerator else { return nil }
        return FactorUnitExpression(numeratorToKg: numerator, activityUnit: activity)
    }

    /// Strips gas labels ("CO2e", "CO2", "CO2-eq") and returns the mass multiplier to kg.
    static func parseMassNumerator(_ raw: String) -> Double? {
        var token = raw.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for label in ["co2-eq", "co2-e", "co2eq", "co2e", "co₂e", "co2", "co₂", "ch4", "n2o", "ghg"] where token.hasSuffix(label) {
            token = String(token.dropLast(label.count))
            break
        }
        token = token.trimmingCharacters(in: CharacterSet(charactersIn: " -_"))
        if token.isEmpty { return 1 } // bare "CO2e/kWh" — assume kg, the common default
        guard let definition = UnitRegistry.resolve(token), definition.dimension == .mass else { return nil }
        return definition.toBase
    }
}

// MARK: - Emission factor

nonisolated struct EmissionFactor: Codable, Hashable, Identifiable, Sendable {
    /// Stable across syncs: "<connectorID>:<externalID>".
    var id: String
    var externalID: String
    var name: String
    var category: String
    var region: String
    var year: Int?
    /// Canonical symbol of ONE activity unit, e.g. "kWh", "L", "TJ", "INR".
    var activityUnit: String
    /// Kilograms of each gas per activity unit, when the source publishes gases.
    var gases: GasAmounts?
    /// Kilograms CO2e per activity unit, when the source publishes a total.
    var co2ePerUnit: Double?
    /// GWP set used by the source for `co2ePerUnit`, if stated.
    var co2eBasis: GWPSet?
    var source: String
    var sourceURL: String?
    var connectorID: String
    var notes: String?
    var retrievedAt: Date?
    var uncertaintyPercent: Double?
    /// Optional fuel properties so the calculator can convert litres → kg → TJ.
    var densityKgPerLitre: Double?
    var netCalorificValueMJPerKg: Double?
    /// Connector-specific keys (e.g. Climatiq `unit_type`, `data_version`).
    var metadata: [String: String] = [:]

    var unitDefinition: UnitDefinition? { UnitRegistry.resolve(activityUnit) }

    var hasValue: Bool { co2ePerUnit != nil || !(gases?.isEmpty ?? true) }

    /// kg CO2e per activity unit for display; nil when the value must be fetched remotely.
    func displayCO2ePerUnit(_ gwp: GWPSet) -> Double? {
        if let co2ePerUnit, co2eBasis == gwp || gases == nil { return co2ePerUnit }
        if let gases, !gases.isEmpty { return gases.co2e(gwp) }
        return co2ePerUnit
    }
}
