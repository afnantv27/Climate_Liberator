import Foundation

/// Decarbonisation measures with sourced defaults.
///
/// Each default either cites a source (`sources`) or is flagged `isAssumption`
/// (shown as "replace with local data"). Measures that need a local number before
/// they do anything (counts, local rates) are flagged `requiresInput`.
/// Selectors use GPC source keys; a corporate catalog can reuse the same engine
/// with its own keys.
nonisolated enum DecarbonizationMeasureCatalog {

    // MARK: Sources

    static let sources: [MeasureSource] = [
        MeasureSource(id: "bis-lpg-stove", title: "IS 4246: domestic LPG stoves — minimum burner thermal efficiency 68%", publisher: "Bureau of Indian Standards", url: "https://services.bis.gov.in/php/BIS_2.0/BISBlog/?p=903"),
        MeasureSource(id: "bee-lpg-star", title: "Star labels for LPG stoves: 1 star ≥68% … 5 stars ≥76% thermal efficiency", publisher: "BEE notification (reported by The Tribune)", url: "https://www.tribuneindia.com/news/india/ac-type-efficiency-star-ratings-now-for-lpg-stoves"),
        MeasureSource(id: "lbnl-cooktops", title: "Cooktop efficiency: induction 84%, electric 74%, gas 40% (LBNL study for US DOE)", publisher: "Green Building Advisor, citing LBNL", url: "https://greenbuildingadvisor.com/article/going-high-tech-with-an-induction-cooktop"),
        MeasureSource(id: "icct-indore-2026", title: "Electrifying urban public fleets: Indore e-buses 0.85 kWh/km (54% less energy than diesel); e-waste trucks 91% less", publisher: "ICCT, Oct 2026", url: "https://theicct.org/?p=96462"),
        MeasureSource(id: "icct-ebus-sewa", title: "First 3,825 e-buses under PM e-Bus Sewa: e-buses ~70% more energy efficient than diesel", publisher: "ICCT, Nov 2024", url: "https://theicct.org/emissions-reduction-and-benefits-of-the-first-3825-electric-buses-under-pm-ebus-sewa-nov24"),
        MeasureSource(id: "autocar-e2w", title: "Real-world range tests of electric scooters: 28.5–34.6 km/kWh", publisher: "Autocar India, 2026", url: "https://www.autocarindia.com/auto-features/bajaj-chetak-c2501-real-world-range-tested-and-explained-441124"),
        MeasureSource(id: "ampere-ice2w", title: "Petrol scooter ~45 km/L real-world (manufacturer comparison)", publisher: "Greaves Electric Mobility press release, 2026", url: "https://ampere.greaveselectricmobility.com/press-releases/fuel-efficiency-vs-energy-efficiency-electric-scooter-2026"),
        MeasureSource(id: "icct-ev-2025", title: "ICCT Global Automaker Rating 2025: leading EVs average 131 Wh/km (best 106 Wh/km)", publisher: "ICCT, reported by Rest of World", url: "https://restofworld.org/2026/indian-evs-beat-tesla-byd-icct-efficiency-ranking/"),
        MeasureSource(id: "icct-2w-fuel", title: "Fuel consumption reduction technologies for the two-wheeler fleet in India", publisher: "ICCT, 2021", url: "https://theicct.org/publication/fuel-consumption-reduction-technologies-for-the-two-wheeler-fleet-in-india"),
        MeasureSource(id: "pib-slnp", title: "Street Lighting National Programme: guaranteed minimum energy saving of typically 50%", publisher: "PIB factsheet, 2022", url: "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2022/may/doc202253060301.pdf"),
        MeasureSource(id: "powerline-slnp", title: "SLNP: about 270 kWh saved per LED street light per year", publisher: "Power Line, 2018", url: "https://powerline.net.in/2018/04/28/street-smart/"),
        MeasureSource(id: "bee-ecbc", title: "ECBC 2017: ECBC ~25%, ECBC+ ~35%, SuperECBC ≥50% savings vs a conventional building", publisher: "Bureau of Energy Efficiency", url: "https://beeindia.gov.in/en/node/38864"),
        MeasureSource(id: "bee-ecbc-climate", title: "ECBC-compliant buildings save 20–25% across climate zones (BEE, 2017)", publisher: "GRIHA ECBC presentation", url: "https://www.grihaindia.org/sites/default/files/pdf/ECBC-Code.pdf"),
        MeasureSource(id: "mnre-swh", title: "A 100 litre/day solar water heater saves about 1,500 kWh a year (MNRE figure)", publisher: "HAREDA", url: "https://hareda.gov.in/centers/solar-water-heating-system/"),
        MeasureSource(id: "doca-bldc", title: "BLDC 5-star ceiling fans tested at 26.9–35.4 W", publisher: "Department of Consumer Affairs", url: "https://consumeraffairs.nic.in/sites/default/files/file-uploads/ctocpas/BLDC_Ceiling_Fans_Choosing_Efficiency.pdf"),
        MeasureSource(id: "orient-fans", title: "Conventional induction-motor ceiling fans use 70–75 W", publisher: "Orient Electric", url: "https://orientelectric.com/blogs/fans/bldc-fans-paving-the-way-to-energy-savings-and-a-greener-future"),
        MeasureSource(id: "cea-nep-2023", title: "National Electricity Plan 2022–32: grid factor 0.548 (2026-27) and 0.430 kg CO2/kWh (2031-32)", publisher: "CEA, via PIB, 2023", url: "https://pib.gov.in/PressReleasePage.aspx?PRID=1928750"),
        MeasureSource(id: "epa-lfg", title: "Landfill gas collection efficiency: 75% default, typical range 50–95%", publisher: "US EPA LMOP handbook, ch. 2", url: "https://www.epa.gov/system/files/documents/2021-07/pdh_chapter2.pdf"),
        MeasureSource(id: "ipcc-2006-v5", title: "IPCC 2006 Guidelines Vol. 5 (Waste): Table 4.1 biological treatment, Table 6.3 MCF", publisher: "IPCC", url: "https://www.ipcc-nggip.iges.or.jp/public/2006gl/vol5.html"),
        MeasureSource(id: "ipcc-2006-v2", title: "IPCC 2006 Guidelines Vol. 2 (Energy): Table 1.2 net calorific values", publisher: "IPCC", url: "https://www.ipcc-nggip.iges.or.jp/public/2006gl/vol2.html"),
        MeasureSource(id: "ipcc-2019-settlements", title: "2019 Refinement Vol. 4 Ch. 8 Settlements: crown cover 2.8 t C/ha crown/yr (Table 8.1); mixed city trees 0.005–0.01 t C/tree/yr (Table 8.2)", publisher: "IPCC", url: "https://www.ipcc-nggip.iges.or.jp/public/2019rf/pdf/4_Volume4/19R_V4_Ch08_Settlements.pdf"),
        MeasureSource(id: "gpc-forests-trees", title: "GPC Supplemental Guidance for Forests and Trees", publisher: "WRI / GHG Protocol", url: "https://ghgprotocol.org/gpc-supplemental-guidance-forests-and-trees"),
        MeasureSource(id: "pib-e20", title: "Ethanol blending in India: E20 achieved in 2025", publisher: "PIB, Jul 2026", url: "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2026/jul/doc202675912001.pdf"),
    ]

    static func source(_ id: String) -> MeasureSource? { sourceIndex[id] }
    private static let sourceIndex = Dictionary(uniqueKeysWithValues: sources.map { ($0.id, $0) })

    static func measure(_ id: String) -> DecarbonizationMeasure? { measureIndex[id] }
    private static let measureIndex = Dictionary(uniqueKeysWithValues: measures.map { ($0.id, $0) })

    /// Position in the catalog, for a stable display order grouped by category.
    static func position(of id: String) -> Int { positionIndex[id] ?? Int.max }
    private static let positionIndex = Dictionary(uniqueKeysWithValues: measures.enumerated().map { ($1.id, $0) })

    /// Carbon to CO2 mass ratio (44/12).
    static let co2PerCarbon = 44.0 / 12.0

    // MARK: Physical constants (library values, so results stay consistent)

    /// Petrol: 0.745 kg/L (typical) × 44.3 MJ/kg (IPCC) ÷ 3.6 = kWh per litre.
    static let petrolKWhPerLitre = 0.745 * 44.3 / 3.6
    static let petrolDensity = 0.745, petrolNCV = 44.3
    /// Ethanol: 0.789 kg/L; NCV 27.0 MJ/kg (IPCC 2006 Table 1.2, biogasoline).
    static let ethanolDensity = 0.789, ethanolNCV = 27.0

    /// Ethanol's share of the energy in a blend with `volumeShare` ethanol.
    static func ethanolEnergyShare(volumeShare x: Double) -> Double {
        let ethanol = x * ethanolDensity * ethanolNCV
        let petrol = (1 - x) * petrolDensity * petrolNCV
        return ethanol + petrol > 0 ? ethanol / (ethanol + petrol) : 0
    }

    // MARK: Measures

    private static let buildingKeys = ["I.1", "I.2", "I.3", "I.5", "I.6"]

    static let measures: [DecarbonizationMeasure] = [
        // Buildings & industry
        DecarbonizationMeasure(
            id: "lpg-to-induction", title: "Induction Cooking (LPG → Electric)", category: .buildings,
            summary: "Replace LPG stoves with induction cooktops. Electricity needed = LPG energy × stove efficiency ÷ induction efficiency.",
            bestFor: "Residential and commercial LPG (I.1.1, I.2.1); pairs well with rooftop solar.",
            adoptionMeaning: "Share of LPG cooking switched", defaultAdoption: 0.2,
            targets: SourceSelector(keyPrefixes: ["I.1", "I.2"], carriers: [.lpg]),
            parameters: [
                MeasureParameter(id: "lpgEfficiency", title: "LPG stove efficiency", unit: "%", typical: 0.68, low: 0.68, high: 0.76, sourceIDs: ["bis-lpg-stove", "bee-lpg-star"]),
                MeasureParameter(id: "inductionEfficiency", title: "Induction efficiency", unit: "%", typical: 0.84, low: 0.74, high: 0.84, sourceIDs: ["lbnl-cooktops"],
                                 note: "Low value is a conventional electric hob (74%)."),
            ],
            caveat: "Adds grid electricity; the net cut depends on the grid factor.",
            effect: { v in .switchToGridElectricity(kWhPerKWhReplaced: v["lpgEfficiency", default: 0.68] / max(v["inductionEfficiency", default: 0.84], 0.01)) }),
        DecarbonizationMeasure(
            id: "biogas-cooking", title: "Biogas Cooking (LPG → Biogas)", category: .buildings,
            summary: "Household or community biogas from kitchen and animal waste replaces LPG. Biogas CO2 is biogenic.",
            bestFor: "Residential LPG in peri-urban areas with organic waste or cattle (I.1.1).",
            adoptionMeaning: "Share of LPG cooking replaced by biogas", defaultAdoption: 0.05,
            targets: SourceSelector(keyPrefixes: ["I.1"], carriers: [.lpg]),
            parameters: [
                MeasureParameter(id: "energyRatio", title: "Biogas energy per unit of LPG energy", unit: "×", typical: 1.0, low: 1.0, high: 1.4, sourceIDs: [],
                                 isAssumption: true, note: "Assumes similar stove efficiency; biogas stoves are often less efficient."),
            ],
            effect: { v in .switchToFactor(factorExternalID: "ipcc2006-stationary-residential-biogas", kWhPerKWhReplaced: v["energyRatio", default: 1]) }),
        DecarbonizationMeasure(
            id: "ecbc-buildings", title: "Energy-Efficient Commercial Buildings (ECBC)", category: .buildings,
            summary: "New and retrofitted commercial buildings meet the Energy Conservation Building Code.",
            bestFor: "Commercial and institutional electricity (I.2.2): offices, malls, hotels, hospitals.",
            adoptionMeaning: "Share of commercial electricity in ECBC buildings", defaultAdoption: 0.2,
            targets: SourceSelector(keyPrefixes: ["I.2"], gridElectricity: true),
            parameters: [
                MeasureParameter(id: "savings", title: "Energy saving vs a conventional building", unit: "%", typical: 0.25, low: 0.20, high: 0.50, sourceIDs: ["bee-ecbc", "bee-ecbc-climate"],
                                 note: "ECBC 25%, ECBC+ 35%, SuperECBC 50%; 20–25% by climate zone."),
            ],
            effect: { v in .reduceActivity(fraction: v["savings", default: 0.25]) }),
        DecarbonizationMeasure(
            id: "efficient-fans", title: "Efficient Ceiling Fans (BLDC)", category: .buildings,
            summary: "Replace induction-motor fans with 5-star BLDC fans.",
            bestFor: "Residential electricity in warm climates (I.1.2).",
            adoptionMeaning: "Share of the planned fans installed", defaultAdoption: 1.0,
            targets: SourceSelector(keyPrefixes: ["I.1", "I.2"], gridElectricity: true),
            parameters: [
                MeasureParameter(id: "fans", title: "Fans replaced", unit: "fans", typical: 0, low: 0, high: 0, sourceIDs: [], requiresInput: true),
                MeasureParameter(id: "wattsSaved", title: "Power saved per fan", unit: "W", typical: 43, low: 35, high: 48, sourceIDs: ["orient-fans", "doca-bldc"],
                                 note: "70–75 W conventional vs 27–35 W BLDC."),
                MeasureParameter(id: "hoursPerDay", title: "Use per day", unit: "h", typical: 8, low: 4, high: 12, sourceIDs: [], isAssumption: true),
            ],
            effect: { v in .saveGridElectricity(kWhPerYear: v["fans", default: 0] * v["wattsSaved", default: 43] * v["hoursPerDay", default: 8] * 365 / 1_000) }),
        DecarbonizationMeasure(
            id: "solar-water-heaters", title: "Solar Water Heaters", category: .buildings,
            summary: "Solar water heaters replace electric geysers in homes, hotels and hospitals.",
            bestFor: "Residential and commercial electricity used for hot water (I.1.2, I.2.2).",
            adoptionMeaning: "Share of the planned systems installed", defaultAdoption: 1.0,
            targets: SourceSelector(keyPrefixes: ["I.1", "I.2"], gridElectricity: true),
            parameters: [
                MeasureParameter(id: "systems", title: "Systems (100 litres/day each)", unit: "systems", typical: 0, low: 0, high: 0, sourceIDs: [], requiresInput: true),
                MeasureParameter(id: "kWhPerSystem", title: "Electricity saved per system", unit: "kWh/yr", typical: 1_500, low: 1_000, high: 1_500, sourceIDs: ["mnre-swh"],
                                 note: "MNRE: up to ~1,500 kWh; lower where less hot water is used."),
            ],
            effect: { v in .saveGridElectricity(kWhPerYear: v["systems", default: 0] * v["kWhPerSystem", default: 1_500]) }),
        DecarbonizationMeasure(
            id: "led-streetlights", title: "LED Street Lighting", category: .buildings,
            summary: "Convert conventional street lights to LED (as under the Street Lighting National Programme).",
            bestFor: "Municipal public lighting, reported under commercial/institutional electricity (I.2.2).",
            adoptionMeaning: "Share of the planned lights converted", defaultAdoption: 1.0,
            targets: SourceSelector(keyPrefixes: ["I.2"], gridElectricity: true),
            parameters: [
                MeasureParameter(id: "lights", title: "Street lights converted", unit: "lights", typical: 0, low: 0, high: 0, sourceIDs: [], requiresInput: true),
                MeasureParameter(id: "kWhPerLight", title: "Electricity saved per light", unit: "kWh/yr", typical: 270, low: 200, high: 300, sourceIDs: ["powerline-slnp", "pib-slnp"],
                                 isAssumption: false, note: "SLNP average ~270 kWh/light/yr; contracts guarantee ≥50% saving."),
            ],
            effect: { v in .saveGridElectricity(kWhPerYear: v["lights", default: 0] * v["kWhPerLight", default: 270]) }),
        DecarbonizationMeasure(
            id: "industrial-efficiency", title: "Industrial Energy Efficiency", category: .buildings,
            summary: "Energy audits, efficient motors, pumps, compressors and heat recovery in industry.",
            bestFor: "Manufacturing fuel and electricity (I.3.1, I.3.2).",
            adoptionMeaning: "Share of industrial energy covered", defaultAdoption: 0.5,
            targets: SourceSelector(keyPrefixes: ["I.3"]),
            parameters: [
                MeasureParameter(id: "savings", title: "Energy saving where applied", unit: "%", typical: 0, low: 0, high: 0, sourceIDs: [], requiresInput: true,
                                 note: "Use audit results; savings vary widely by plant."),
            ],
            effect: { v in .reduceActivity(fraction: v["savings", default: 0]) }),
        DecarbonizationMeasure(
            id: "industrial-gas-switch", title: "Industrial Fuel Switch to Natural Gas", category: .buildings,
            summary: "Coal, furnace oil or diesel boilers and furnaces switch to piped natural gas.",
            bestFor: "Manufacturing coal, furnace oil and diesel (I.3.1). A bridge, not zero carbon.",
            adoptionMeaning: "Share of these fuels switched", defaultAdoption: 0.3,
            targets: SourceSelector(keyPrefixes: ["I.3"], carriers: [.coal, .fuelOil, .diesel]),
            parameters: [
                MeasureParameter(id: "energyRatio", title: "Gas energy per unit of fuel replaced", unit: "×", typical: 1.0, low: 0.9, high: 1.1, sourceIDs: [],
                                 isAssumption: true, note: "Assumes equal boiler efficiency."),
            ],
            effect: { v in .switchToFactor(factorExternalID: "ipcc2006-stationary-manufacturing-natural-gas", kWhPerKWhReplaced: v["energyRatio", default: 1]) }),
        DecarbonizationMeasure(
            id: "diesel-generators-to-solar", title: "Replace Diesel Generators with Solar + Storage", category: .buildings,
            summary: "Backup and off-grid diesel generators are replaced by solar PV with batteries.",
            bestFor: "Diesel used for power in homes, shops, offices and industry (I.1.1–I.3.1).",
            adoptionMeaning: "Share of generator diesel replaced", defaultAdoption: 0.5,
            targets: SourceSelector(keyPrefixes: DecarbonizationMeasureCatalog.buildingKeys, carriers: [.diesel]),
            parameters: [],
            effect: { _ in .reduceActivity(fraction: 1) }),

        // Energy supply
        DecarbonizationMeasure(
            id: "rooftop-solar", title: "Rooftop Solar PV", category: .energySupply,
            summary: "Rooftop solar on homes, businesses and public buildings supplies part of their electricity.",
            bestFor: "Grid electricity in all buildings (I.1.2, I.2.2, I.3.2), including new electricity from fuel switches.",
            adoptionMeaning: "Share of building electricity from rooftop solar", defaultAdoption: 0.15,
            targets: SourceSelector(keyPrefixes: DecarbonizationMeasureCatalog.buildingKeys, gridElectricity: true),
            parameters: [],
            caveat: "Location-based inventories count only on-site use; exported solar lowers the grid factor instead.",
            effect: { _ in .replaceGridSupply }),
        DecarbonizationMeasure(
            id: "green-power", title: "Renewable Power Procurement", category: .energySupply,
            summary: "Commercial and industrial users buy renewable power (green tariff, open access, PPAs).",
            bestFor: "Commercial and industrial grid electricity (I.2.2, I.3.2).",
            adoptionMeaning: "Share of their electricity bought as renewable", defaultAdoption: 0.2,
            targets: SourceSelector(keyPrefixes: ["I.2", "I.3"], gridElectricity: true),
            parameters: [],
            caveat: "In a location-based GPC inventory this shows as a market-based saving; report it separately.",
            effect: { _ in .replaceGridSupply }),
        DecarbonizationMeasure(
            id: "grid-decarbonisation", title: "National Grid Decarbonisation (CEA Plan)", category: .energySupply,
            summary: "The grid factor follows the National Electricity Plan as more renewables come online.",
            bestFor: "All grid electricity, including e-mobility and induction cooking.",
            adoptionMeaning: "Share of the planned grid improvement achieved", defaultAdoption: 1.0,
            targets: SourceSelector(gridElectricity: true),
            parameters: [
                MeasureParameter(id: "factor2027", title: "Grid factor 2026-27", unit: "kg CO2/kWh", typical: 0.548, low: 0.548, high: 0.548, sourceIDs: ["cea-nep-2023"]),
                MeasureParameter(id: "factor2032", title: "Grid factor 2031-32", unit: "kg CO2/kWh", typical: 0.430, low: 0.430, high: 0.430, sourceIDs: ["cea-nep-2023"],
                                 note: "Held flat after 2031-32 unless you change it. Actual coal share has stayed above plan."),
            ],
            caveat: "Outside the city's control; shown as its own wedge.",
            effect: { v in .gridEmissionFactorPath([YearValue(year: 2027, value: v["factor2027", default: 0.548]),
                                                    YearValue(year: 2032, value: v["factor2032", default: 0.430])]) }),

        // Transport
        DecarbonizationMeasure(
            id: "electric-two-wheelers", title: "Electric Two-Wheelers", category: .transport,
            summary: "Petrol scooters and motorcycles are replaced by electric ones.",
            bestFor: "On-road petrol (II.1.1): two-wheelers use most of the petrol in Indian cities.",
            adoptionMeaning: "Share of on-road petrol used by two-wheelers that go electric", defaultAdoption: 0.3,
            targets: SourceSelector(keyPrefixes: ["II.1"], carriers: [.petrol]),
            parameters: [
                MeasureParameter(id: "evKWhPerKm", title: "Electric two-wheeler energy use", unit: "kWh/km", typical: 0.035, low: 0.029, high: 0.040, sourceIDs: ["autocar-e2w"],
                                 note: "28.5–34.6 km/kWh in real-world tests; high value adds ~10% charging loss."),
                MeasureParameter(id: "iceKmPerLitre", title: "Petrol two-wheeler fuel economy", unit: "km/L", typical: 45, low: 40, high: 55, sourceIDs: ["ampere-ice2w"],
                                 isAssumption: true, note: "Manufacturer comparison; use local fleet data if you have it."),
            ],
            effect: { v in .switchToGridElectricity(kWhPerKWhReplaced: v["evKWhPerKm", default: 0.035] * v["iceKmPerLitre", default: 45] / DecarbonizationMeasureCatalog.petrolKWhPerLitre) }),
        DecarbonizationMeasure(
            id: "electric-cars", title: "Electric Cars and Taxis", category: .transport,
            summary: "Petrol cars, taxis and ride-hailing fleets switch to battery-electric.",
            bestFor: "On-road petrol used by cars (II.1.1); fleets first.",
            adoptionMeaning: "Share of on-road petrol used by cars that go electric", defaultAdoption: 0.1,
            targets: SourceSelector(keyPrefixes: ["II.1"], carriers: [.petrol]),
            parameters: [
                MeasureParameter(id: "evKWhPerKm", title: "Electric car energy use", unit: "kWh/km", typical: 0.131, low: 0.106, high: 0.160, sourceIDs: ["icct-ev-2025"],
                                 note: "Test-cycle average 131 Wh/km; high value allows for real-world use (assumption)."),
                MeasureParameter(id: "iceKmPerLitre", title: "Petrol car fuel economy", unit: "km/L", typical: 15, low: 12, high: 20, sourceIDs: [],
                                 isAssumption: true, note: "Replace with local fleet data."),
            ],
            effect: { v in .switchToGridElectricity(kWhPerKWhReplaced: v["evKWhPerKm", default: 0.131] * v["iceKmPerLitre", default: 15] / DecarbonizationMeasureCatalog.petrolKWhPerLitre) }),
        DecarbonizationMeasure(
            id: "electric-buses", title: "Electric Buses", category: .transport,
            summary: "Diesel city and intercity buses are replaced by electric buses (e.g. PM e-Bus Sewa).",
            bestFor: "On-road diesel used by buses (II.1.1).",
            adoptionMeaning: "Share of on-road diesel used by buses that go electric", defaultAdoption: 0.3,
            targets: SourceSelector(keyPrefixes: ["II.1"], carriers: [.diesel]),
            parameters: [
                MeasureParameter(id: "energyRatio", title: "E-bus energy use vs diesel bus", unit: "×", typical: 0.46, low: 0.30, high: 0.46, sourceIDs: ["icct-indore-2026", "icct-ebus-sewa"],
                                 note: "Indore real-world: 54% less energy; ICCT tender analysis: ~70% less."),
            ],
            effect: { v in .switchToGridElectricity(kWhPerKWhReplaced: v["energyRatio", default: 0.46]) }),
        DecarbonizationMeasure(
            id: "electric-waste-trucks", title: "Electric Waste-Collection Vehicles", category: .transport,
            summary: "Diesel door-to-door waste collection vehicles are replaced by small electric trucks.",
            bestFor: "Municipal fleet diesel (II.1.1).",
            adoptionMeaning: "Share of on-road diesel used by waste collection that goes electric", defaultAdoption: 0.05,
            targets: SourceSelector(keyPrefixes: ["II.1"], carriers: [.diesel]),
            parameters: [
                MeasureParameter(id: "energyRatio", title: "E-truck energy use vs diesel truck", unit: "×", typical: 0.09, low: 0.09, high: 0.11, sourceIDs: ["icct-indore-2026"],
                                 note: "Indore: 91% less energy than diesel, 89% less than CNG."),
            ],
            effect: { v in .switchToGridElectricity(kWhPerKWhReplaced: v["energyRatio", default: 0.09]) }),
        DecarbonizationMeasure(
            id: "modal-shift", title: "Public Transport, Walking and Cycling", category: .transport,
            summary: "Better buses, footpaths, cycle lanes and parking policy move trips out of private vehicles.",
            bestFor: "On-road petrol from private cars and two-wheelers (II.1.1).",
            adoptionMeaning: "Net cut in private-vehicle petrol (after added bus trips)", defaultAdoption: 0.1,
            targets: SourceSelector(keyPrefixes: ["II.1"], carriers: [.petrol]),
            parameters: [],
            effect: { _ in .reduceActivity(fraction: 1) }),
        DecarbonizationMeasure(
            id: "two-wheeler-efficiency", title: "Fuel-Efficient Two-Wheelers", category: .transport,
            summary: "Newer petrol two-wheelers with fuel-saving technology (as studied for fuel consumption standards).",
            bestFor: "On-road petrol (II.1.1) where electric uptake is slow.",
            adoptionMeaning: "Share of petrol two-wheeler use by efficient models", defaultAdoption: 0.3,
            targets: SourceSelector(keyPrefixes: ["II.1"], carriers: [.petrol]),
            parameters: [
                MeasureParameter(id: "savings", title: "Fuel saving", unit: "%", typical: 0.23, low: 0.09, high: 0.42, sourceIDs: ["icct-2w-fuel"],
                                 note: "23%: limit of cost-effective ICE gains; up to 42% for small motorcycles."),
            ],
            effect: { v in .reduceActivity(fraction: v["savings", default: 0.23]) }),
        DecarbonizationMeasure(
            id: "ethanol-blending", title: "Higher Ethanol Blending", category: .transport,
            summary: "Raise ethanol in petrol beyond the current blend; ethanol CO2 is biogenic.",
            bestFor: "On-road petrol (II.1.1). Only the increase above today's blend counts.",
            adoptionMeaning: "Share of petrol sold at the higher blend", defaultAdoption: 1.0,
            targets: SourceSelector(keyPrefixes: ["II"], carriers: [.petrol]),
            parameters: [
                MeasureParameter(id: "currentBlend", title: "Current ethanol share (by volume)", unit: "%", typical: 0.20, low: 0.20, high: 0.20, sourceIDs: ["pib-e20"]),
                MeasureParameter(id: "newBlend", title: "Future ethanol share (by volume)", unit: "%", typical: 0.27, low: 0.25, high: 0.30, sourceIDs: [],
                                 isAssumption: true, note: "No national plan beyond E20 as of 2026; a policy assumption."),
            ],
            extraSourceIDs: ["ipcc-2006-v2"],
            caveat: "If your petrol factor ignores today's ethanol, the baseline already overstates fossil CO2.",
            effect: { v in
                let now = DecarbonizationMeasureCatalog.ethanolEnergyShare(volumeShare: v["currentBlend", default: 0.2])
                let future = DecarbonizationMeasureCatalog.ethanolEnergyShare(volumeShare: v["newBlend", default: 0.27])
                return .reduceFossilCO2(fraction: max(0, 1 - (1 - future) / max(1 - now, 0.01)))
            }),

        // Solid waste
        DecarbonizationMeasure(
            id: "organics-to-compost", title: "Divert Organic Waste to Composting", category: .waste,
            summary: "Source-segregated wet waste goes to composting instead of a dumpsite or landfill.",
            bestFor: "Solid waste disposal (III.1); the largest methane source in most Indian cities.",
            adoptionMeaning: "Share of disposed waste diverted", defaultAdoption: 0.5,
            targets: SourceSelector(keyPrefixes: ["III.1"]),
            parameters: [],
            extraSourceIDs: ["ipcc-2006-v5"],
            caveat: "Adds composting emissions (IPCC Table 4.1); dumpsite methane avoided is from your inventory.",
            effect: { _ in .divertWaste(treatmentExternalID: "ipcc2006-composting-wet") }),
        DecarbonizationMeasure(
            id: "organics-to-biogas", title: "Divert Organic Waste to Biomethanation", category: .waste,
            summary: "Wet waste goes to biogas plants; the biogas can replace LPG or diesel.",
            bestFor: "Solid waste disposal (III.1) in cities with markets, hotels and bulk generators.",
            adoptionMeaning: "Share of disposed waste diverted", defaultAdoption: 0.2,
            targets: SourceSelector(keyPrefixes: ["III.1"]),
            parameters: [],
            extraSourceIDs: ["ipcc-2006-v5"],
            caveat: "Fuel displaced by the biogas is not credited here.",
            effect: { _ in .divertWaste(treatmentExternalID: "ipcc2006-anaerobic-digestion-wet") }),
        DecarbonizationMeasure(
            id: "landfill-gas-capture", title: "Landfill Gas Capture", category: .waste,
            summary: "Cover the landfill and collect methane for flaring or power.",
            bestFor: "Large managed landfills (III.1). Not suited to open dumpsites.",
            adoptionMeaning: "Share of disposed waste at sites with gas collection", defaultAdoption: 0.5,
            targets: SourceSelector(keyPrefixes: ["III.1"]),
            parameters: [
                MeasureParameter(id: "collection", title: "Gas collection efficiency", unit: "%", typical: 0.75, low: 0.50, high: 0.95, sourceIDs: ["epa-lfg"]),
            ],
            effect: { v in .reduceMethane(fraction: v["collection", default: 0.75]) }),
        DecarbonizationMeasure(
            id: "waste-reduction", title: "Waste Prevention and Recycling", category: .waste,
            summary: "Less waste generated and more dry waste recycled, so less reaches treatment.",
            bestFor: "All solid waste (III.1–III.3).",
            adoptionMeaning: "Cut in waste treated or disposed", defaultAdoption: 0.1,
            targets: SourceSelector(keyPrefixes: ["III.1", "III.2", "III.3"]),
            parameters: [],
            effect: { _ in .reduceActivity(fraction: 1) }),
        DecarbonizationMeasure(
            id: "end-open-burning", title: "End Open Burning of Waste", category: .waste,
            summary: "Enforced collection stops waste being burnt in the open.",
            bestFor: "Open burning (III.3).",
            adoptionMeaning: "Share of open burning stopped", defaultAdoption: 0.5,
            targets: SourceSelector(keyPrefixes: ["III.3"]),
            parameters: [],
            caveat: "Add the collected waste to its new treatment in the inventory.",
            effect: { _ in .reduceActivity(fraction: 1) }),

        // Wastewater
        DecarbonizationMeasure(
            id: "septic-to-aerobic-stp", title: "Connect Septic Tanks to Aerobic Treatment", category: .wastewater,
            summary: "Households on septic tanks or pit latrines connect to sewers and a well-run aerobic STP.",
            bestFor: "Domestic wastewater on septic tanks and latrines (III.4).",
            adoptionMeaning: "Share of those people connected", defaultAdoption: 0.3,
            targets: SourceSelector(keyPrefixes: ["III.4"]),
            parameters: [
                MeasureParameter(id: "currentMCF", title: "Current methane correction factor", unit: "MCF", typical: 0.5, low: 0.5, high: 0.5, sourceIDs: ["ipcc-2006-v5"],
                                 note: "Septic tank 0.5 (IPCC Table 6.3)."),
                MeasureParameter(id: "newMCF", title: "Methane correction factor after", unit: "MCF", typical: 0, low: 0.3, high: 0, sourceIDs: ["ipcc-2006-v5"],
                                 note: "Aerobic, well managed 0; overloaded or poorly run 0.3."),
            ],
            caveat: "STP electricity and effluent N2O are not added.",
            effect: { v in
                let current = max(v["currentMCF", default: 0.5], 0.01)
                return .reduceMethane(fraction: min(1, max(0, 1 - v["newMCF", default: 0] / current)))
            }),

        // Land use and removals — inside the boundary, GPC AFOLU (BASIC+). Shown apart from emissions.
        DecarbonizationMeasure(
            id: "urban-trees", title: "Urban Tree Planting", category: .landUse,
            summary: "Street, park and campus trees remove CO2 as they grow. Shown as removals, apart from emissions.",
            bestFor: "Any city with planting space; counted under AFOLU (BASIC+). Shade also lowers cooling demand (not counted).",
            adoptionMeaning: "Share of planned trees planted and surviving", defaultAdoption: 0.8,
            targets: SourceSelector(),
            parameters: [
                MeasureParameter(id: "trees", title: "Trees planned", unit: "trees", typical: 0, low: 0, high: 0, sourceIDs: [], requiresInput: true),
                MeasureParameter(id: "tonnesPerTree", title: "CO2 removed per tree", unit: "t/yr",
                                 typical: 0.0075 * DecarbonizationMeasureCatalog.co2PerCarbon,
                                 low: 0.005 * DecarbonizationMeasureCatalog.co2PerCarbon,
                                 high: 0.01 * DecarbonizationMeasureCatalog.co2PerCarbon, sourceIDs: ["ipcc-2019-settlements"],
                                 note: "IPCC mixed city trees 0.005–0.01 t C per tree per year; young trees remove less."),
            ],
            extraSourceIDs: ["gpc-forests-trees"],
            caveat: "Removals can reverse (felling, fire, die-off). They are not offsets and are not netted from GPC totals.",
            effect: { v in .removeCarbon(tonnesPerYear: v["trees", default: 0] * v["tonnesPerTree", default: 0]) }),
        DecarbonizationMeasure(
            id: "urban-green-cover", title: "Urban Forests and Green Cover", category: .landUse,
            summary: "New canopy in parks, mini forests, riverbanks and campuses, counted by crown area.",
            bestFor: "Open public land and institutional campuses, when you know the canopy area rather than the tree count.",
            adoptionMeaning: "Share of the planned canopy established", defaultAdoption: 0.8,
            targets: SourceSelector(),
            parameters: [
                MeasureParameter(id: "hectares", title: "New tree crown cover", unit: "ha", typical: 0, low: 0, high: 0, sourceIDs: [], requiresInput: true),
                MeasureParameter(id: "tonnesPerHectare", title: "CO2 removed per ha of crown", unit: "t/ha/yr",
                                 typical: 2.8 * DecarbonizationMeasureCatalog.co2PerCarbon,
                                 low: 2.35 * DecarbonizationMeasureCatalog.co2PerCarbon,
                                 high: 3.25 * DecarbonizationMeasureCatalog.co2PerCarbon, sourceIDs: ["ipcc-2019-settlements"],
                                 note: "IPCC global default 2.8 ± 0.45 t C per ha of crown per year."),
            ],
            extraSourceIDs: ["gpc-forests-trees"],
            caveat: "Removals can reverse. Count canopy, not land area.",
            effect: { v in .removeCarbon(tonnesPerYear: v["hectares", default: 0] * v["tonnesPerHectare", default: 0]) }),
    ]
}
