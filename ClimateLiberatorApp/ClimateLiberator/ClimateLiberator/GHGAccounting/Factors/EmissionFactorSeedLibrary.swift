import Foundation

/// Offline reference library so the calculator works without a network.
///
/// Values are IPCC 2006 Guidelines defaults (Vol. 2 energy, Vol. 5 waste) and
/// India CEA grid factors. They are Tier 1 starting points, not local or supplier
/// data: confirm against the IPCC EFDB / latest CEA release before formal
/// reporting. Fuel densities are typical values (not IPCC defaults) and say so
/// in each factor's notes.
///
/// Combustion CH4 is stored as non-fossil CH4: IPCC 2006 already counts all fuel
/// carbon as CO2 (oxidation factor 1), so the AR6 fossil-CH4 GWP would count the
/// CH4 carbon twice.
nonisolated enum EmissionFactorSeedLibrary {
    static let connectorID = "bundled"

    private static let ipccEnergyURL = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/vol2.html"
    private static let ipccWasteURL = "https://www.ipcc-nggip.iges.or.jp/public/2006gl/vol5.html"
    private static let ceaURL = "https://cea.nic.in/cdm-co2-baseline-database/"

    // MARK: Fuels

    fileprivate nonisolated enum FuelFamily {
        case oil, gas, coal, wood, charcoal, solidBiomass, biogas, liquidBiofuel
    }

    fileprivate nonisolated struct Fuel {
        let key: String
        let name: String
        let family: FuelFamily
        let co2KgPerTJ: Double
        let ncvMJPerKg: Double
        var densityKgPerLitre: Double? = nil

        var isBiogenic: Bool {
            switch family {
            case .wood, .charcoal, .solidBiomass, .biogas, .liquidBiofuel: return true
            case .oil, .gas, .coal: return false
            }
        }
    }

    // IPCC 2006 Vol. 2 Ch. 1 Table 1.2 (NCV, TJ/Gg = MJ/kg) and Ch. 2 Tables 2.2–2.5 (CO2, kg/TJ).
    // Existing keys are kept stable so saved inventories keep matching.
    private static let stationaryFuels: [Fuel] = [
        Fuel(key: "petrol", name: "Petrol (motor gasoline)", family: .oil, co2KgPerTJ: 69_300, ncvMJPerKg: 44.3, densityKgPerLitre: 0.745),
        Fuel(key: "kerosene", name: "Kerosene (other kerosene)", family: .oil, co2KgPerTJ: 71_900, ncvMJPerKg: 43.8, densityKgPerLitre: 0.80),
        Fuel(key: "diesel", name: "Diesel (gas/diesel oil)", family: .oil, co2KgPerTJ: 74_100, ncvMJPerKg: 43.0, densityKgPerLitre: 0.84),
        Fuel(key: "furnace-oil", name: "Furnace oil (residual fuel oil)", family: .oil, co2KgPerTJ: 77_400, ncvMJPerKg: 40.4),
        Fuel(key: "naphtha", name: "Naphtha", family: .oil, co2KgPerTJ: 73_300, ncvMJPerKg: 44.5),
        Fuel(key: "petcoke", name: "Petroleum coke", family: .oil, co2KgPerTJ: 97_500, ncvMJPerKg: 32.5),
        Fuel(key: "lpg", name: "LPG", family: .gas, co2KgPerTJ: 63_100, ncvMJPerKg: 47.3),
        Fuel(key: "natural-gas", name: "Natural gas", family: .gas, co2KgPerTJ: 56_100, ncvMJPerKg: 48.0),
        Fuel(key: "anthracite", name: "Coal (anthracite)", family: .coal, co2KgPerTJ: 98_300, ncvMJPerKg: 26.7),
        Fuel(key: "coking-coal", name: "Coal (coking coal)", family: .coal, co2KgPerTJ: 94_600, ncvMJPerKg: 28.2),
        Fuel(key: "coal-bituminous", name: "Coal (other bituminous)", family: .coal, co2KgPerTJ: 94_600, ncvMJPerKg: 25.8),
        Fuel(key: "coal-sub-bituminous", name: "Coal (sub-bituminous)", family: .coal, co2KgPerTJ: 96_100, ncvMJPerKg: 18.9),
        Fuel(key: "lignite", name: "Lignite", family: .coal, co2KgPerTJ: 101_000, ncvMJPerKg: 11.9),
        Fuel(key: "wood", name: "Wood / wood waste", family: .wood, co2KgPerTJ: 112_000, ncvMJPerKg: 15.6),
        Fuel(key: "charcoal", name: "Charcoal", family: .charcoal, co2KgPerTJ: 112_000, ncvMJPerKg: 29.5),
        Fuel(key: "solid-biomass", name: "Other solid biomass (crop residues, dung)", family: .solidBiomass, co2KgPerTJ: 100_000, ncvMJPerKg: 11.6),
        Fuel(key: "biogas", name: "Biogas (other biogas)", family: .biogas, co2KgPerTJ: 54_600, ncvMJPerKg: 50.4),
        Fuel(key: "biodiesel", name: "Biodiesel", family: .liquidBiofuel, co2KgPerTJ: 70_800, ncvMJPerKg: 27.0),
    ]

    fileprivate nonisolated enum StationarySector: String, CaseIterable {
        case residential, commercial, manufacturing, energyIndustries, agriculture

        var title: String {
            switch self {
            case .residential: return "Residential"
            case .commercial: return "Commercial / institutional"
            case .manufacturing: return "Manufacturing & construction"
            case .energyIndustries: return "Energy industries"
            case .agriculture: return "Agriculture, forestry & fishing"
            }
        }

        var table: String {
            switch self {
            case .energyIndustries: return "Table 2.2"
            case .manufacturing: return "Table 2.3"
            case .commercial: return "Table 2.4"
            case .residential, .agriculture: return "Table 2.5"
            }
        }

        private var isSmallScale: Bool { self == .residential || self == .commercial || self == .agriculture }

        /// (CH4, N2O) in kg/TJ.
        func nonCO2(for family: FuelFamily) -> (ch4: Double, n2o: Double) {
            switch family {
            case .oil, .liquidBiofuel:
                return isSmallScale ? (10, 0.6) : (3, 0.6)
            case .gas, .biogas:
                return isSmallScale ? (5, 0.1) : (1, 0.1)
            case .coal:
                switch self {
                case .residential, .agriculture: return (300, 1.5)
                case .commercial, .manufacturing: return (10, 1.5)
                case .energyIndustries: return (1, 1.5)
                }
            case .wood, .solidBiomass:
                return isSmallScale ? (300, 4) : (30, 4)
            case .charcoal:
                return isSmallScale ? (200, 1) : (200, 4)
            }
        }
    }

    // MARK: Mobile combustion

    fileprivate nonisolated struct MobileFactor {
        let key: String
        let name: String
        let fuel: Fuel
        let ch4: Double, n2o: Double
        let table: String
    }

    private static func fuel(_ key: String) -> Fuel {
        stationaryFuels.first { $0.key == key }!
    }

    private static let jetKerosene = Fuel(key: "jet-kerosene", name: "Jet kerosene", family: .oil, co2KgPerTJ: 71_500, ncvMJPerKg: 44.1)
    private static let aviationGasoline = Fuel(key: "aviation-gasoline", name: "Aviation gasoline", family: .oil, co2KgPerTJ: 70_000, ncvMJPerKg: 44.3)

    // IPCC 2006 Vol. 2 Ch. 3. CO2 from Table 3.2.1 (same per-TJ values as Ch. 1); CH4/N2O kg/TJ per table cited.
    private static let mobileFactors: [MobileFactor] = {
        let petrol = fuel("petrol"), diesel = fuel("diesel")
        return [
            // Road — Table 3.2.2. Keys "petrol", "diesel", "lpg", "cng" are the original IDs.
            MobileFactor(key: "road-petrol", name: "Petrol — road transport (uncontrolled)", fuel: petrol, ch4: 33, n2o: 3.2, table: "Table 3.2.2"),
            MobileFactor(key: "road-petrol-oxidation-catalyst", name: "Petrol — road transport, oxidation catalyst", fuel: petrol, ch4: 25, n2o: 8.0, table: "Table 3.2.2"),
            MobileFactor(key: "road-petrol-low-mileage", name: "Petrol — road transport, low-mileage light-duty (1995+)", fuel: petrol, ch4: 3.8, n2o: 5.7, table: "Table 3.2.2"),
            MobileFactor(key: "road-diesel", name: "Diesel — road transport", fuel: diesel, ch4: 3.9, n2o: 3.9, table: "Table 3.2.2"),
            MobileFactor(key: "road-lpg", name: "Auto LPG — road transport", fuel: fuel("lpg"), ch4: 62, n2o: 0.2, table: "Table 3.2.2"),
            MobileFactor(key: "road-cng", name: "CNG — road transport", fuel: fuel("natural-gas"), ch4: 92, n2o: 3, table: "Table 3.2.2"),
            // Off-road — Table 3.3.1.
            MobileFactor(key: "offroad-diesel", name: "Diesel — off-road machinery (agriculture, construction, industry)", fuel: diesel, ch4: 4.15, n2o: 28.6, table: "Table 3.3.1"),
            MobileFactor(key: "offroad-petrol-4stroke-agriculture", name: "Petrol 4-stroke — off-road, agriculture", fuel: petrol, ch4: 80, n2o: 2, table: "Table 3.3.1"),
            MobileFactor(key: "offroad-petrol-4stroke-industry", name: "Petrol 4-stroke — off-road, industry", fuel: petrol, ch4: 50, n2o: 2, table: "Table 3.3.1"),
            MobileFactor(key: "offroad-petrol-4stroke-household", name: "Petrol 4-stroke — off-road, household (mowers, gensets)", fuel: petrol, ch4: 120, n2o: 2, table: "Table 3.3.1"),
            MobileFactor(key: "offroad-petrol-2stroke-agriculture", name: "Petrol 2-stroke — off-road, agriculture", fuel: petrol, ch4: 140, n2o: 0.4, table: "Table 3.3.1"),
            MobileFactor(key: "offroad-petrol-2stroke-forestry", name: "Petrol 2-stroke — off-road, forestry (chainsaws)", fuel: petrol, ch4: 170, n2o: 0.4, table: "Table 3.3.1"),
            MobileFactor(key: "offroad-petrol-2stroke-industry", name: "Petrol 2-stroke — off-road, industry", fuel: petrol, ch4: 130, n2o: 0.4, table: "Table 3.3.1"),
            MobileFactor(key: "offroad-petrol-2stroke-household", name: "Petrol 2-stroke — off-road, household", fuel: petrol, ch4: 180, n2o: 0.4, table: "Table 3.3.1"),
            // Rail — Table 3.4.1.
            MobileFactor(key: "rail-diesel", name: "Diesel — railway locomotives", fuel: diesel, ch4: 4.15, n2o: 28.6, table: "Table 3.4.1"),
            // Water-borne navigation — ocean-going ship defaults, Tables 3.5.2–3.5.3.
            MobileFactor(key: "navigation-diesel", name: "Marine diesel — water-borne navigation", fuel: diesel, ch4: 7, n2o: 2, table: "Tables 3.5.2–3.5.3"),
            MobileFactor(key: "navigation-residual-fuel-oil", name: "Residual fuel oil — water-borne navigation", fuel: fuel("furnace-oil"), ch4: 7, n2o: 2, table: "Tables 3.5.2–3.5.3"),
            // Civil aviation — Tables 3.6.4–3.6.5.
            MobileFactor(key: "aviation-jet-kerosene", name: "Jet kerosene — civil aviation", fuel: jetKerosene, ch4: 0.5, n2o: 2, table: "Tables 3.6.4–3.6.5"),
            MobileFactor(key: "aviation-gasoline", name: "Aviation gasoline — civil aviation", fuel: aviationGasoline, ch4: 0.5, n2o: 2, table: "Tables 3.6.4–3.6.5"),
        ]
    }()

    /// Original road IDs ("ipcc2006-road-petrol", …) are kept for saved inventories.
    private static func mobileExternalID(_ key: String) -> String {
        key.hasPrefix("road-") ? "ipcc2006-road-\(key.dropFirst(5))" : "ipcc2006-\(key)"
    }

    // MARK: Waste

    /// India BOD 34 g/person/day (Table 6.4) × 365 = 12.41 kg BOD/person-year; Bo 0.6 kg CH4/kg BOD (Table 6.2).
    private static let indiaBODKgPerPersonYear = 0.034 * 365
    private static let maximumCH4ProducingCapacity = 0.6

    /// Methane correction factors for domestic wastewater (IPCC 2006 Vol. 5 Ch. 6 Table 6.3).
    private static let wastewaterSystems: [(key: String, name: String, mcf: Double)] = [
        ("septic", "septic tank", 0.5),
        ("latrine-dry-family", "dry pit latrine (family, groundwater below latrine)", 0.1),
        ("latrine-dry-communal", "dry pit latrine (communal, many users)", 0.5),
        ("latrine-wet", "wet pit latrine (groundwater higher than latrine)", 0.7),
        ("sewer-stagnant", "stagnant open sewer", 0.5),
        ("discharge-river", "untreated discharge to river, lake or sea", 0.1),
    ]

    // MARK: Library

    static let factors: [EmissionFactor] = {
        var list: [EmissionFactor] = []

        for sector in StationarySector.allCases {
            for fuel in stationaryFuels {
                let (ch4, n2o) = sector.nonCO2(for: fuel.family)
                var notes = "IPCC 2006 Vol. 2 Ch. 2 \(sector.table) defaults; NCV \(fuel.ncvMJPerKg) MJ/kg (Table 1.2)."
                if fuel.isBiogenic { notes += " CO2 is biogenic and reported separately." }
                list.append(combustionFactor(
                    externalID: "ipcc2006-stationary-\(sector.rawValue)-\(fuel.key)",
                    name: "\(fuel.name) — stationary combustion, \(sector.title.lowercased())",
                    category: "Stationary combustion", fuel: fuel, ch4: ch4, n2o: n2o, notes: notes))
            }
        }

        for factor in mobileFactors {
            let notes = "IPCC 2006 Vol. 2 Ch. 3 \(factor.table) CH4/N2O defaults; CO2 \(Int(factor.fuel.co2KgPerTJ)) kg/TJ; NCV \(factor.fuel.ncvMJPerKg) MJ/kg."
            list.append(combustionFactor(
                externalID: mobileExternalID(factor.key), name: factor.name,
                category: "Mobile combustion", fuel: factor.fuel, ch4: factor.ch4, n2o: factor.n2o, notes: notes))
        }

        // Biological treatment of solid waste — Vol. 5 Ch. 4 Table 4.1 (per tonne of wet waste).
        list.append(simpleFactor(
            externalID: "ipcc2006-composting-wet", name: "Composting — biological treatment of solid waste (wet weight)",
            category: "Solid waste", unit: "t", gases: GasAmounts(ch4NonFossil: 4, n2o: 0.24),
            source: "IPCC 2006 Guidelines", url: ipccWasteURL, year: 2006,
            notes: "IPCC 2006 Vol. 5 Ch. 4 Table 4.1: 4 g CH4 and 0.24 g N2O per kg wet waste. Ranges are wide (0.03–8 g CH4)."))
        list.append(simpleFactor(
            externalID: "ipcc2006-anaerobic-digestion-wet", name: "Anaerobic digestion at biogas plants (wet weight)",
            category: "Solid waste", unit: "t", gases: GasAmounts(ch4NonFossil: 0.8),
            source: "IPCC 2006 Guidelines", url: ipccWasteURL, year: 2006,
            notes: "IPCC 2006 Vol. 5 Ch. 4 Table 4.1: 0.8 g CH4 per kg wet waste (unintentional leakage); N2O assumed negligible. Biogas burned for energy goes under stationary energy."))

        // Domestic wastewater, uncollected systems (industrial-BOD correction I = 1).
        for system in wastewaterSystems {
            let ch4 = indiaBODKgPerPersonYear * maximumCH4ProducingCapacity * system.mcf
            list.append(simpleFactor(
                externalID: "ipcc2006-wastewater-india-\(system.key)",
                name: "Domestic wastewater — \(system.name) (India, per person-year)",
                category: "Wastewater", unit: "person", gases: GasAmounts(ch4NonFossil: ch4),
                source: "IPCC 2006 Guidelines", url: ipccWasteURL, year: 2006,
                notes: String(format: "Tier 1: BOD 34 g/person/day (India, Table 6.4), Bo 0.6 kg CH4/kg BOD (Table 6.2), MCF %.1f (Table 6.3) = %.3f kg CH4 per person-year. Multiply by people using this system. No sludge removal or CH4 recovery; effluent N2O not included.", system.mcf, ch4)))
        }

        // India grid — CEA CO2 Baseline Database. CO2 only; use the version matching the year of consumption.
        list.append(simpleFactor(
            externalID: "cea-v21-fy2025-weighted-average", name: "India grid electricity — weighted average FY2024-25 (CEA v21)",
            category: "Grid electricity", unit: "kWh", gases: GasAmounts(co2: 0.710),
            source: "Central Electricity Authority (CEA)", url: ceaURL, year: 2025, region: "India",
            notes: "CEA CO2 Baseline Database v21.0 (2025), FY2024-25: 1,234.19 Mt CO2 / 1,739.06 BU ≈ 0.710 t/MWh. CO2 only. Location-based scope 2 for inventories. CEA v22.0 (Aug 2026) adds FY2025-26 — check it for newer years."))
        list.append(simpleFactor(
            externalID: "cea-v20-fy2024-weighted-average", name: "India grid electricity — weighted average FY2023-24 (CEA v20)",
            category: "Grid electricity", unit: "kWh", gases: GasAmounts(co2: 0.727),
            source: "Central Electricity Authority (CEA)", url: ceaURL, year: 2024, region: "India",
            notes: "CEA CO2 Baseline Database v20.0 (Dec 2024), FY2023-24. CO2 only. Location-based scope 2 for FY2023-24 consumption."))
        list.append(simpleFactor(
            externalID: "cea-v20-fy2024-combined-margin", name: "India grid electricity — combined margin FY2023-24 (CEA v20)",
            category: "Grid electricity", unit: "kWh", gases: GasAmounts(co2: 0.757),
            source: "Central Electricity Authority (CEA)", url: ceaURL, year: 2024, region: "India",
            notes: "CEA CO2 Baseline Database v20.0 (Dec 2024), FY2023-24. CO2 only. Combined margin is for project baselines (e.g. offsets), not city inventories."))
        return list
    }()

    // MARK: Builders

    private static func combustionFactor(externalID: String, name: String, category: String,
                                         fuel: Fuel, ch4: Double, n2o: Double, notes: String) -> EmissionFactor {
        var gases = GasAmounts(ch4NonFossil: ch4, n2o: n2o)
        if fuel.isBiogenic { gases.co2Biogenic = fuel.co2KgPerTJ } else { gases.co2 = fuel.co2KgPerTJ }
        var notes = notes
        if let density = fuel.densityKgPerLitre {
            notes += " Density \(density) kg/L is a typical value, not an IPCC default — replace with supplier data."
        }
        return EmissionFactor(
            id: "\(connectorID):\(externalID)", externalID: externalID, name: name, category: category,
            region: "Global default", year: 2006, activityUnit: "TJ", gases: gases,
            co2ePerUnit: nil, co2eBasis: nil, source: "IPCC 2006 Guidelines", sourceURL: ipccEnergyURL,
            connectorID: connectorID, notes: notes, retrievedAt: nil, uncertaintyPercent: nil,
            densityKgPerLitre: fuel.densityKgPerLitre, netCalorificValueMJPerKg: fuel.ncvMJPerKg)
    }

    private static func simpleFactor(externalID: String, name: String, category: String, unit: String,
                                     gases: GasAmounts, source: String, url: String, year: Int,
                                     region: String = "Global default", notes: String) -> EmissionFactor {
        EmissionFactor(
            id: "\(connectorID):\(externalID)", externalID: externalID, name: name, category: category,
            region: region, year: year, activityUnit: unit, gases: gases,
            co2ePerUnit: nil, co2eBasis: nil, source: source, sourceURL: url,
            connectorID: connectorID, notes: notes, retrievedAt: nil, uncertaintyPercent: nil,
            densityKgPerLitre: nil, netCalorificValueMJPerKg: nil)
    }
}
