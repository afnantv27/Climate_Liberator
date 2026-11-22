import Foundation

/// Worked example inventories for demonstrations.
///
/// Iritty Municipality (Kannur, Kerala), GPC BASIC, IPCC AR6 GWPs.
/// ILLUSTRATIVE: most activity data is top-down — a Kerala state total multiplied
/// by Iritty's share of Kerala's population. Replace each line with local data
/// (KSEB section-office sales, fuel-station sales, municipal waste records)
/// before using the numbers for decisions.
nonisolated enum GPCExampleInventories {

    /// Inputs, each from a public source (see docs/ghg-accounting.md).
    nonisolated enum Iritty {
        /// AMRUT City Water Balance Plan (Iritty): projected 2025 population and households.
        static let population2025 = 52_318.0
        static let households2025 = 12_918.0
        /// Census 2011.
        static let population2011 = 40_369.0
        /// Municipal area reported officially, km² (the OSM outline measures ≈50.7 km²).
        static let areaKm2 = 45.84
        /// Technical Group on Population Projections: Kerala, 1 July 2025.
        static let keralaPopulation2025 = 36_111_000.0
        static var populationShare: Double { population2025 / keralaPopulation2025 }

        /// KSEBL total electricity sales FY2023-24: 27,675 MU, with category shares.
        static let ksebSalesMWh = 27_675_000.0
        static let shareDomestic = 0.50
        static let shareCommercialAndOther = 0.22   // commercial LT 17% + other categories 5%
        static let shareIndustrialLT = 0.05
        static let shareAgricultureLT = 0.01

        /// Kerala average daily LPG use reported for 26 Feb 2026 (tonnes/day).
        static let lpgDomesticTonnesPerDay = 2_985.0
        static let lpgNonDomesticTonnesPerDay = 753.0
        /// PPAC: Kerala petrol consumption FY2024-25 (1,851.3 TMT).
        static let petrolTonnes = 1_851_300.0
        /// Kerala monthly diesel sales (litres): March 2023, April 2023, April 2022.
        static let dieselMonthlyLitres: [Double] = [266_600_000, 202_800_000, 237_800_000]

        /// Kerala Solid Waste Management Project C-EMP: Iritty generates 14.12 TPD.
        static let wasteTonnesPerDay = 14.12
        /// Low end of the 70–80% biodegradable share reported for Kerala MSW.
        static let biodegradableShare = 0.70

        static func round1(_ value: Double) -> Double { (value * 10).rounded() / 10 }
    }

    /// Iritty Municipality (LSGI code M13083) outline from the OpenStreetMap Kerala
    /// community's local-body dataset (github.com/opendatakerala/lsg-kerala-data,
    /// 2021 snapshot). © OpenStreetMap contributors, ODbL. 192 points, [longitude, latitude].
    /// Its area (≈50.7 km²) is larger than the 45.84 km² reported officially —
    /// confirm against the municipality's ward map before formal reporting.
    static let irittyBoundary = BoundaryPolygon(vertices: irittyOutlineLonLat.map {
        GeoCoordinate(latitude: $0[1], longitude: $0[0])
    })

    /// Inventories saved from earlier app versions carry an 8-point placeholder outline.
    /// Returns true when it was replaced with the real municipal outline.
    static func upgradeLegacyIrittyBoundary(_ inventory: inout GPCInventory) -> Bool {
        guard inventory.boundarySource.hasPrefix("APPROXIMATE demonstration outline"),
              inventory.boundary.vertices.count == 8 else { return false }
        inventory.boundary = irittyBoundary
        inventory.boundarySource = irittyBoundarySource
        inventory.boundaryType = .administrative
        return true
    }

    static let irittyBoundarySource = "OpenStreetMap Kerala local-body boundaries (opendatakerala/lsg-kerala-data, LSGI M13083, 2021) — © OpenStreetMap contributors, ODbL. OSM area ≈50.7 km² vs 45.84 km² reported officially; check against the municipal ward map."

    private static let irittyOutlineLonLat: [[Double]] = [
        [75.679600, 11.943882], [75.678012, 11.942706], [75.675137, 11.942286], [75.674441, 11.942447],
        [75.673141, 11.942748], [75.671468, 11.943483], [75.669107, 11.944532], [75.666897, 11.945015],
        [75.665441, 11.945316], [75.664966, 11.945414], [75.664473, 11.945960], [75.664344, 11.947828],
        [75.663958, 11.949319], [75.663228, 11.950893], [75.662155, 11.952111], [75.661039, 11.953140],
        [75.660262, 11.953418], [75.659044, 11.953853], [75.656941, 11.954525], [75.655546, 11.954651],
        [75.654817, 11.954126], [75.653615, 11.953937], [75.652821, 11.954546], [75.651705, 11.954987],
        [75.650825, 11.955323], [75.649667, 11.955281], [75.649224, 11.955252], [75.646105, 11.955050],
        [75.644925, 11.953895], [75.643637, 11.952426], [75.642371, 11.951523], [75.641170, 11.951418],
        [75.640011, 11.951208], [75.639174, 11.950411], [75.638273, 11.949382], [75.637543, 11.948059],
        [75.636342, 11.947786], [75.635827, 11.947199], [75.635376, 11.946023], [75.635466, 11.944851],
        [75.635633, 11.942664], [75.635612, 11.938843], [75.635569, 11.937434], [75.635505, 11.935295],
        [75.634689, 11.933091], [75.633316, 11.931306], [75.631063, 11.930257], [75.629573, 11.930223],
        [75.629218, 11.930215], [75.628016, 11.930320], [75.627158, 11.930446], [75.622534, 11.928199],
        [75.619229, 11.931370], [75.614691, 11.933805], [75.613572, 11.935393], [75.613242, 11.935862],
        [75.611504, 11.937458], [75.606653, 11.937310], [75.605968, 11.937290], [75.604935, 11.937040],
        [75.602932, 11.936555], [75.601237, 11.937468], [75.600132, 11.936660], [75.597321, 11.935348],
        [75.594606, 11.935967], [75.594213, 11.936115], [75.589907, 11.937741], [75.588546, 11.937948],
        [75.587131, 11.938164], [75.585841, 11.938360], [75.584596, 11.940712], [75.583845, 11.943032],
        [75.583464, 11.945388], [75.583363, 11.946013], [75.583710, 11.948092], [75.583942, 11.949476],
        [75.584575, 11.951565], [75.586377, 11.952489], [75.587096, 11.953339], [75.587369, 11.954346],
        [75.587482, 11.954766], [75.587611, 11.956971], [75.587987, 11.959427], [75.589188, 11.960539],
        [75.588791, 11.962397], [75.589703, 11.962911], [75.591785, 11.963069], [75.593501, 11.963457],
        [75.593448, 11.964801], [75.593909, 11.965493], [75.596366, 11.965986], [75.596226, 11.967393],
        [75.596409, 11.969377], [75.596226, 11.971938], [75.597417, 11.973218], [75.598384, 11.973798],
        [75.598984, 11.974168], [75.602417, 11.974299], [75.603812, 11.974719], [75.605657, 11.975537],
        [75.607953, 11.976986], [75.608854, 11.978560], [75.609906, 11.979988], [75.611730, 11.980869],
        [75.614390, 11.981415], [75.616257, 11.981205], [75.617974, 11.980911], [75.620828, 11.981625],
        [75.621664, 11.983241], [75.621772, 11.984710], [75.621021, 11.986012], [75.620205, 11.986998],
        [75.619197, 11.988048], [75.618360, 11.989349], [75.618660, 11.990503], [75.619819, 11.991448],
        [75.621493, 11.991595], [75.623145, 11.991007], [75.624282, 11.989811], [75.626128, 11.987691],
        [75.627544, 11.986431], [75.629261, 11.985529], [75.631277, 11.985466], [75.634260, 11.985907],
        [75.636277, 11.987229], [75.637672, 11.988887], [75.638638, 11.989874], [75.639453, 11.989685],
        [75.640740, 11.988614], [75.643938, 11.984836], [75.644796, 11.984227], [75.646105, 11.983829],
        [75.646856, 11.984101], [75.647821, 11.984941], [75.648894, 11.985907], [75.650117, 11.986704],
        [75.651813, 11.986725], [75.654559, 11.986641], [75.655739, 11.987397], [75.656598, 11.988530],
        [75.658786, 11.988887], [75.660052, 11.988048], [75.661404, 11.987901], [75.662413, 11.988027],
        [75.663829, 11.988824], [75.665760, 11.990923], [75.667627, 11.992791], [75.669622, 11.993232],
        [75.672090, 11.993526], [75.674772, 11.993400], [75.676789, 11.993148], [75.678592, 11.992644],
        [75.679600, 11.991700], [75.679922, 11.990671], [75.679772, 11.988027], [75.679257, 11.984626],
        [75.680480, 11.981530], [75.681928, 11.979074], [75.683001, 11.977574], [75.683387, 11.976891],
        [75.683924, 11.976367], [75.684943, 11.976272], [75.686402, 11.976755], [75.688806, 11.978020],
        [75.689551, 11.978345], [75.690372, 11.978460], [75.691289, 11.978376], [75.691896, 11.978140],
        [75.692046, 11.977091], [75.691852, 11.976314], [75.691745, 11.974950], [75.692174, 11.973963],
        [75.693333, 11.973061], [75.694985, 11.972788], [75.695541, 11.972826], [75.695461, 11.972240],
        [75.695136, 11.969849], [75.694739, 11.968086], [75.694492, 11.966532], [75.692389, 11.964580],
        [75.689900, 11.961872], [75.688355, 11.960235], [75.687604, 11.958954], [75.687351, 11.957831],
        [75.687089, 11.956666], [75.686247, 11.955192], [75.685759, 11.954336], [75.685432, 11.953985],
        [75.682669, 11.951019], [75.681510, 11.948185], [75.681103, 11.947085], [75.680416, 11.945225],
    ]

    static func iritty() -> GPCInventory {
        var inventory = GPCInventory(cityName: "Iritty", inventoryYear: 2025)
        inventory.region = "Kerala (Kannur district)"
        inventory.country = "India"
        inventory.boundaryType = .administrative
        inventory.boundarySource = irittyBoundarySource
        inventory.boundary = irittyBoundary
        inventory.population = Int(Iritty.population2025)
        inventory.gwpSet = .ar6
        inventory.targetLevel = .basic
        inventory.entries = irittyEntries()
        return inventory
    }

    private static func seed(_ externalID: String) -> EmissionFactor? {
        EmissionFactorSeedLibrary.factors.first { $0.externalID == externalID }
    }

    private static func activity(_ reference: String, _ label: String, quantity: Double, unit: String,
                                 factor: EmissionFactor?, quality: GPCDataQuality, source: String,
                                 notes: String) -> GPCInventoryEntry {
        var entry = GPCInventoryEntry(referenceID: reference, label: label)
        entry.method = .activity
        entry.activityQuantity = quantity
        entry.activityUnit = unit
        entry.factor = factor
        entry.dataQuality = quality
        entry.dataSource = source
        entry.notes = notes
        return entry
    }

    private static func notation(_ reference: String, _ key: GPCNotationKey, _ explanation: String) -> GPCInventoryEntry {
        var entry = GPCInventoryEntry(referenceID: reference, label: GPCCatalog.reference(reference)?.title ?? reference)
        entry.method = .notationKey
        entry.notationKey = key
        entry.notationExplanation = explanation
        return entry
    }

    private static func irittyEntries() -> [GPCInventoryEntry] {
        let share = Iritty.populationShare
        let shareText = String(format: "Iritty share of Kerala population %.4f%% (52,318 / 36,111,000)", share * 100)
        let grid = seed("cea-v20-fy2024-weighted-average")
        let electricity = { (fraction: Double) in (Iritty.ksebSalesMWh * fraction * share).rounded() }
        let dieselLitres = (Iritty.dieselMonthlyLitres.reduce(0, +) / Double(Iritty.dieselMonthlyLitres.count) * 12 * share).rounded()
        let wasteTonnes = Iritty.round1(Iritty.wasteTonnesPerDay * 365)
        let compostTonnes = Iritty.round1(wasteTonnes * Iritty.biodegradableShare)

        return [
            // I. Stationary energy
            activity("I.1.1", "Household LPG", quantity: Iritty.round1(Iritty.lpgDomesticTonnesPerDay * 365 * share), unit: "t",
                     factor: seed("ipcc2006-stationary-residential-lpg"), quality: .low,
                     source: "Kerala domestic LPG 2,985 t/day (26 Feb 2026) × 365 × population share",
                     notes: "\(shareText). Firewood use not estimated (biogenic CO2 would be reported separately)."),
            activity("I.1.2", "Household electricity (KSEB LT domestic)", quantity: electricity(Iritty.shareDomestic), unit: "MWh",
                     factor: grid, quality: .low,
                     source: "KSEBL FY2023-24 sales 27,675 MU × LT domestic 50% × population share",
                     notes: "\(shareText). Replace with KSEB section-office sales for Iritty."),
            activity("I.2.1", "Commercial LPG (non-domestic)", quantity: Iritty.round1(Iritty.lpgNonDomesticTonnesPerDay * 365 * share), unit: "t",
                     factor: seed("ipcc2006-stationary-commercial-lpg"), quality: .low,
                     source: "Kerala non-domestic LPG 753 t/day (26 Feb 2026) × 365 × population share",
                     notes: shareText),
            activity("I.2.2", "Commercial & other electricity (KSEB LT commercial + others)", quantity: electricity(Iritty.shareCommercialAndOther), unit: "MWh",
                     factor: grid, quality: .low,
                     source: "KSEBL FY2023-24 sales × (commercial LT 17% + others 5%) × population share",
                     notes: "\(shareText). 'Others' includes public lighting and water works."),
            notation("I.3.1", .notEstimated, "Fuel use of Iritty's 28 listed industries is not available; collect from KSPCB consents or industry surveys."),
            activity("I.3.2", "Industrial electricity (KSEB LT industrial)", quantity: electricity(Iritty.shareIndustrialLT), unit: "MWh",
                     factor: grid, quality: .low,
                     source: "KSEBL FY2023-24 sales × LT industrial 5% × population share",
                     notes: "\(shareText). HT/EHT sales (22% statewide) excluded: no large HT consumers assumed — confirm with KSEB."),
            notation("I.4.1", .notOccurring, "No power plant assumed inside the municipal boundary — confirm."),
            notation("I.4.2", .notOccurring, "No power plant assumed inside the municipal boundary — confirm."),
            notation("I.5.1", .notEstimated, "Diesel use in irrigation pumps and farm equipment not available."),
            activity("I.5.2", "Agricultural electricity (KSEB LT agriculture)", quantity: electricity(Iritty.shareAgricultureLT), unit: "MWh",
                     factor: grid, quality: .low,
                     source: "KSEBL FY2023-24 sales × LT agriculture 1% × population share",
                     notes: shareText),
            notation("I.6.1", .includedElsewhere, "All fuel allocated to residential and commercial lines."),
            notation("I.6.2", .includedElsewhere, "KSEB 'other' categories included in I.2.2."),
            notation("I.7.1", .notOccurring, "No coal mining or handling in Iritty."),
            notation("I.8.1", .notEstimated, "City gas distribution leakage not estimated."),

            // II. Transportation
            activity("II.1.1", "Petrol sold for road transport", quantity: Iritty.round1(Iritty.petrolTonnes * share), unit: "t",
                     factor: seed("ipcc2006-road-petrol"), quality: .low,
                     source: "PPAC: Kerala petrol FY2024-25 1,851.3 TMT × population share",
                     notes: "\(shareText). Fuel-sales method; replace with sales from fuel stations inside the boundary."),
            activity("II.1.1", "Diesel sold for road transport", quantity: dieselLitres, unit: "L",
                     factor: seed("ipcc2006-road-diesel"), quality: .low,
                     source: "Kerala diesel sales (Mar 2023 26.66, Apr 2023 20.28, Apr 2022 23.78 crore L): monthly mean × 12 × population share",
                     notes: "\(shareText). Annualised from three months — weakest input; uses 0.84 kg/L density."),
            notation("II.1.2", .includedElsewhere, "EV charging is billed within KSEB domestic/commercial sales (I.1.2, I.2.2)."),
            notation("II.2.1", .notOccurring, "No railway in Iritty."),
            notation("II.2.2", .notOccurring, "No railway in Iritty."),
            notation("II.3.1", .notOccurring, "No waterborne transport service assumed."),
            notation("II.3.2", .notOccurring, "No waterborne transport service assumed."),
            notation("II.4.1", .notOccurring, "No airport inside the boundary (Kannur airport is in Mattannur)."),
            notation("II.4.2", .notOccurring, "No airport inside the boundary."),
            notation("II.5.1", .notEstimated, "Construction and farm machinery fuel not available."),
            notation("II.5.2", .notOccurring, "No electric off-road machinery assumed."),

            // III. Waste
            notation("III.1.1", .notOccurring, "KSWMP reports no current dumping at the Athithattu dumpsite (Ward 12)."),
            notation("III.1.2", .notEstimated, "Residual waste sent outside for landfill is not quantified."),
            activity("III.2.1", "Composting of biodegradable waste", quantity: compostTonnes, unit: "t",
                     factor: seed("ipcc2006-composting-wet"), quality: .medium,
                     source: "14.12 TPD (KSWMP C-EMP Iritty) × 365 × 70% biodegradable",
                     notes: "Assumes all biodegradable waste is composted inside the boundary (Kerala source-level composting policy). Biogas share not separated."),
            notation("III.2.2", .notEstimated, "Organic waste taken outside (e.g. to farms) not quantified."),
            notation("III.3.1", .notEstimated, "Open burning of waste not quantified."),
            notation("III.3.2", .notEstimated, "Non-recyclable dry waste goes via Clean Kerala Company to co-processing outside; not estimated."),
            activity("III.4.1", "Domestic wastewater in septic tanks", quantity: Iritty.population2025, unit: "person",
                     factor: seed("ipcc2006-wastewater-india-septic"), quality: .low,
                     source: "AMRUT projected 2025 population × IPCC Tier 1 septic-system defaults",
                     notes: "Assumes all households use septic systems with no sludge removal; this overstates CH4 if septage is treated."),
            notation("III.4.2", .includedElsewhere, "Septage handling included in III.4.1 (on-site systems)."),
        ]
    }
}
