import Foundation

/// Every KPI the platform collects, with its BRSR, BRSR Core and IFRS S2 links.
///
/// Sources: SEBI BRSR Core format (Annexure I, July 2023) and BRSR format, as amended
/// by the SEBI circular of 28 March 2025; IFRS S2 (June 2023, amended December 2025).
/// References are for navigation; check them against the official texts.
nonisolated enum MetricCatalog {

    static let all: [MetricDefinition] = denominators + ghg + energy + water + waste + air
        + safety + workforce + gender + inclusion + fairness + openness + climateRisk

    private static let index: [String: MetricDefinition] =
        Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    private static let positions: [String: Int] =
        Dictionary(all.enumerated().map { ($1.id, $0) }, uniquingKeysWith: { first, _ in first })

    static func metric(_ id: String) -> MetricDefinition? { index[id] }
    static func position(of id: String) -> Int { positions[id] ?? Int.max }
    static func metrics(in group: MetricGroup) -> [MetricDefinition] { all.filter { $0.group == group } }
    static func metrics(in attribute: BRSRCoreAttribute) -> [MetricDefinition] { all.filter { $0.core == attribute } }

    /// Input metrics needed to answer every required metric of `scope`, including the
    /// inputs of required calculated metrics (e.g. revenue for intensities).
    static func requiredInputs(for scope: Set<DisclosureFramework>) -> [MetricDefinition] {
        var needed = Set<String>()
        func collect(_ definition: MetricDefinition) {
            guard needed.insert(definition.id).inserted else { return }
            for input in definition.derivation?.inputs ?? [] {
                if let child = metric(input) { collect(child) }
            }
        }
        for definition in all where definition.isRequired(in: scope) { collect(definition) }
        return all.filter { needed.contains($0.id) && !$0.isCalculated }
    }

    /// Input metrics required for one framework only.
    static func requiredInputs(for framework: DisclosureFramework) -> [MetricDefinition] {
        requiredInputs(for: [framework])
    }

    // MARK: Builder

    private static func m(_ id: String, _ title: String, _ unit: String, _ kind: MetricKind = .quantity,
                          group: MetricGroup, brsr: BRSRLink? = nil, core: BRSRCoreAttribute? = nil,
                          ifrs: IFRSLink? = nil, derive: Derivation? = nil, _ guidance: String) -> MetricDefinition {
        MetricDefinition(id: id, title: title, unit: unit, kind: kind, group: group, brsr: brsr, core: core,
                         ifrs: ifrs, guidance: guidance, derivation: derive)
    }

    // MARK: Financials and denominators

    private static let denominators: [MetricDefinition] = [
        m(MetricID.revenue, "Revenue from operations", "₹ crore", .money, group: .denominators,
          "From the audited statement of profit and loss, on the same boundary as the report (standalone or consolidated). Denominator for all revenue intensities."),
        m(MetricID.pppRate, "PPP conversion factor", "₹ per international $", .ratio, group: .denominators,
          "Purchasing power parity rate for India (rupees per international dollar). The Industry Standards on BRSR Core point to the latest IMF rate. Revenue ÷ this rate gives PPP-adjusted revenue."),
        m(MetricID.output, "Physical output", "units", .quantity, group: .denominators,
          "Output for output-based intensity: tonnes of product, vehicles, room-nights, etc. Service companies may use full-time employees. Name the unit below."),
        m(MetricID.outputUnit, "Unit of output", "", .text, group: .denominators,
          "The unit used for physical output, e.g. 'tonnes of finished steel' or 'FTE'."),
        m(MetricID.totalWages, "Total wages paid", "₹ crore", .money, group: .denominators,
          "Gross wages to all employees and workers, permanent and other than permanent. Denominator for wages paid to women and in smaller towns."),
        m("fin.accountsPayable", "Accounts payable", "₹ crore", .money, group: .denominators,
          "Trade payables at year end, from the audited balance sheet."),
        m("fin.purchaseCost", "Cost of goods and services procured", "₹ crore", .money, group: .denominators,
          "Total cost of goods and services procured in the year, from the financial statements."),
    ]

    // MARK: GHG (Core attribute 1, P6 EI 7)

    private static let scopes12 = [MetricID.scope1, MetricID.scope2]

    private static let ghg: [MetricDefinition] = [
        m(MetricID.scope1, "Scope 1 emissions", "tCO2e", group: .ghg, brsr: .essential(.p6, "7"), core: .ghg,
          ifrs: .required("29(a)(i)(1)"),
          "Direct emissions from owned or controlled sources: fuel combustion, process and fugitive emissions, per the GHG Protocol. Factors from IPCC or accredited lab tests. Not calculated yet? Use Calculate in GHG Accounting."),
        m(MetricID.scope2, "Scope 2 emissions (location-based)", "tCO2e", group: .ghg, brsr: .essential(.p6, "7"), core: .ghg,
          ifrs: .required("29(a)(i)(2)"),
          "Purchased electricity, steam, heating and cooling × emission factor (CEA grid factor, or the supplier's audited certificate). IFRS S2 asks for location-based Scope 2."),
        m("ghg.scope2Market", "Scope 2 emissions (market-based)", "tCO2e", group: .ghg, ifrs: .supporting("29(a)(v)"),
          "Optional. Reflects contractual instruments such as green tariffs, RECs and PPAs; IFRS S2 asks for information on contractual instruments."),
        m(MetricID.scope12, "Total Scope 1 + 2 emissions", "tCO2e", group: .ghg, brsr: .essential(.p6, "7"), core: .ghg,
          derive: .sum(scopes12), "Scope 1 + Scope 2."),
        m(MetricID.ghgIntensityPPP, "GHG intensity per PPP-adjusted revenue", "tCO2e per million $ PPP", .ratio, group: .ghg,
          brsr: .essential(.p6, "7"), core: .ghg, derive: .perPPPRevenue(scopes12),
          "Scope 1 + 2 ÷ revenue from operations adjusted for PPP."),
        m("ghg.intensityRevenue", "GHG intensity per revenue", "tCO2e per ₹ crore", .ratio, group: .ghg,
          brsr: .essential(.p6, "7"), derive: .perRevenue(scopes12), "Scope 1 + 2 ÷ revenue from operations."),
        m("ghg.intensityOutput", "GHG intensity per unit of output", "tCO2e per unit", .ratio, group: .ghg,
          brsr: .essential(.p6, "7"), core: .ghg, derive: .perOutput(scopes12), "Scope 1 + 2 ÷ physical output."),
        m(MetricID.scope3, "Scope 3 emissions", "tCO2e", group: .ghg, brsr: .leadership(.p6, "2"), ifrs: .required("29(a)(i)(3)"),
          "Value-chain emissions across the GHG Protocol's 15 categories. Voluntary in BRSR (leadership indicator). Required by IFRS S2, which allows omitting it in the first reporting year."),
        m("ghg.scope3Categories", "Scope 3 categories included", "", .text, group: .ghg, ifrs: .required("29(a)(vi)"),
          "Categories measured (e.g. 1 Purchased goods and services, 4 Upstream transport) and why others are left out."),
    ]

    // MARK: Energy (Core attribute 3, P6 EI 1)

    private static let renewables = ["energy.renewableElectricity", "energy.renewableFuel", "energy.renewableOther"]
    private static let nonRenewables = ["energy.nonRenewableElectricity", "energy.nonRenewableFuel", "energy.nonRenewableOther"]

    private static let energy: [MetricDefinition] = [
        m(MetricID.electricityRenewable, "Renewable electricity consumed", "GJ", group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          "Grid, captive or contracted electricity from solar, wind, hydro or other renewables. 1 MWh = 3.6 GJ."),
        m("energy.renewableFuel", "Renewable fuel consumed", "GJ", group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          "Biomass, biogas, biofuels and other renewable fuels, by calorific value."),
        m("energy.renewableOther", "Other renewable energy consumed", "GJ", group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          "Renewable heating, cooling or steam."),
        m("energy.renewableTotal", "Total renewable energy", "GJ", group: .energy, brsr: .essential(.p6, "1"), derive: .sum(renewables),
          "Sum of renewable sources."),
        m(MetricID.electricityNonRenewable, "Non-renewable electricity consumed", "GJ", group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          "Grid and captive electricity from fossil sources. 1 MWh = 3.6 GJ."),
        m("energy.nonRenewableFuel", "Non-renewable fuel consumed", "GJ", group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          "Coal, diesel, fuel oil, natural gas, LPG and other fossil fuels, by calorific value."),
        m("energy.nonRenewableOther", "Other non-renewable energy consumed", "GJ", group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          "Purchased heating, cooling or steam from fossil sources."),
        m("energy.nonRenewableTotal", "Total non-renewable energy", "GJ", group: .energy, brsr: .essential(.p6, "1"), derive: .sum(nonRenewables),
          "Sum of non-renewable sources."),
        m(MetricID.energyTotal, "Total energy consumed", "GJ", group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          derive: .sum(renewables + nonRenewables), "All sources, each counted once."),
        m(MetricID.renewableShare, "Energy from renewable sources", "%", .percent, group: .energy, brsr: .essential(.p6, "1"), core: .energy,
          derive: .ratio(numerator: renewables, denominator: renewables + nonRenewables, scale: 100), "Renewable ÷ total energy."),
        m("energy.intensityPPP", "Energy intensity per PPP-adjusted revenue", "GJ per million $ PPP", .ratio, group: .energy,
          brsr: .essential(.p6, "1"), core: .energy, derive: .perPPPRevenue(renewables + nonRenewables),
          "Total energy ÷ revenue adjusted for PPP."),
        m("energy.intensityOutput", "Energy intensity per unit of output", "GJ per unit", .ratio, group: .energy,
          brsr: .essential(.p6, "1"), core: .energy, derive: .perOutput(renewables + nonRenewables), "Total energy ÷ physical output."),
    ]

    // MARK: Water (Core attribute 2, P6 EI 3–4)

    private static let withdrawals = ["water.surface", "water.ground", "water.thirdParty", "water.seawater", "water.other"]
    private static let discharges = ["water.dischargeUntreated", "water.dischargePrimary", "water.dischargeSecondary", "water.dischargeTertiary"]

    private static let water: [MetricDefinition] = [
        m("water.surface", "Withdrawal: surface water", "kL", group: .water, brsr: .essential(.p6, "3"), "Rivers, lakes, canals and reservoirs."),
        m("water.ground", "Withdrawal: groundwater", "kL", group: .water, brsr: .essential(.p6, "3"), "Borewells and open wells."),
        m("water.thirdParty", "Withdrawal: third-party water", "kL", group: .water, brsr: .essential(.p6, "3"), "Municipal supply and tankers."),
        m("water.seawater", "Withdrawal: seawater / desalinated", "kL", group: .water, brsr: .essential(.p6, "3"), "Seawater and desalinated water."),
        m("water.other", "Withdrawal: other sources", "kL", group: .water, brsr: .essential(.p6, "3"), "Rainwater harvesting and other sources."),
        m(MetricID.waterWithdrawal, "Total water withdrawal", "kL", group: .water, brsr: .essential(.p6, "3"), derive: .sum(withdrawals),
          "Sum of sources."),
        m(MetricID.waterConsumption, "Total water consumption", "kL", group: .water, brsr: .essential(.p6, "3"), core: .water,
          "Water not returned: input minus output from calibrated flow meters, where consumption is not measured directly."),
        m("water.intensityPPP", "Water intensity per PPP-adjusted revenue", "kL per million $ PPP", .ratio, group: .water,
          brsr: .essential(.p6, "3"), core: .water, derive: .perPPPRevenue([MetricID.waterConsumption]),
          "Water consumption ÷ revenue adjusted for PPP."),
        m("water.intensityOutput", "Water intensity per unit of output", "kL per unit", .ratio, group: .water,
          brsr: .essential(.p6, "3"), core: .water, derive: .perOutput([MetricID.waterConsumption]), "Water consumption ÷ physical output."),
        m("water.dischargeUntreated", "Discharge: no treatment", "kL", group: .water, brsr: .essential(.p6, "4"), core: .water,
          "Water discharged without treatment. Give the destination (surface, ground, sea, third party) in the method."),
        m("water.dischargePrimary", "Discharge: primary treatment", "kL", group: .water, brsr: .essential(.p6, "4"), core: .water,
          "Discharged after primary treatment, with destination in the method."),
        m("water.dischargeSecondary", "Discharge: secondary treatment", "kL", group: .water, brsr: .essential(.p6, "4"), core: .water,
          "Discharged after secondary treatment, with destination in the method."),
        m("water.dischargeTertiary", "Discharge: tertiary treatment", "kL", group: .water, brsr: .essential(.p6, "4"), core: .water,
          "Discharged after tertiary treatment, with destination in the method."),
        m("water.dischargeTotal", "Total water discharged", "kL", group: .water, brsr: .essential(.p6, "4"), core: .water,
          derive: .sum(discharges), "Sum of discharge by treatment level."),
    ]

    // MARK: Waste (Core attribute 4, P6 EI 9)

    private static let wasteStreams = ["waste.plastic", "waste.eWaste", "waste.bioMedical", "waste.constructionDemolition",
                                       "waste.battery", "waste.radioactive", "waste.otherHazardous", "waste.otherNonHazardous"]
    private static let recovered = ["waste.recycled", "waste.reused", "waste.otherRecovery"]
    private static let disposed = ["waste.incinerated", "waste.landfilled", "waste.otherDisposal"]

    private static let waste: [MetricDefinition] = [
        m("waste.plastic", "Plastic waste (A)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Including packaging, under the Plastic Waste Management Rules 2016 and amendments."),
        m("waste.eWaste", "E-waste (B)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Items under the E-Waste Rules and amendments."),
        m("waste.bioMedical", "Bio-medical waste (C)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Under the Bio-Medical Waste Management Rules 2016 and amendments."),
        m("waste.constructionDemolition", "Construction and demolition waste (D)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Under the Construction and Demolition Waste Rules 2016 and amendments."),
        m("waste.battery", "Battery waste (E)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Li-ion, lead-acid, alkaline and other batteries."),
        m("waste.radioactive", "Radioactive waste (F)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Material exposed to radiation (power plants, hospitals, laboratories, industry)."),
        m("waste.otherHazardous", "Other hazardous waste (G)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Hazardous waste under CPCB rules; name the types in the method."),
        m("waste.otherNonHazardous", "Other non-hazardous waste (H)", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Give the composition by material in the method."),
        m(MetricID.wasteTotal, "Total waste generated", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          derive: .sum(wasteStreams), "Sum of A to H."),
        m("waste.intensityPPP", "Waste intensity per PPP-adjusted revenue", "t per million $ PPP", .ratio, group: .waste,
          brsr: .essential(.p6, "9"), core: .circularity, derive: .perPPPRevenue(wasteStreams), "Total waste ÷ revenue adjusted for PPP."),
        m("waste.intensityOutput", "Waste intensity per unit of output", "t per unit", .ratio, group: .waste,
          brsr: .essential(.p6, "9"), core: .circularity, derive: .perOutput(wasteStreams), "Total waste ÷ physical output."),
        m("waste.recycled", "Recovered: recycled", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Vendor certificates may support assurance; say so if relied on."),
        m("waste.reused", "Recovered: re-used", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity, "Waste re-used."),
        m("waste.otherRecovery", "Recovered: other recovery", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Other recovery operations, e.g. co-processing."),
        m(MetricID.wasteRecovered, "Total waste recovered", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          derive: .sum(recovered), "Recycled + re-used + other recovery."),
        m("waste.incinerated", "Disposed: incineration", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity, "Incinerated."),
        m("waste.landfilled", "Disposed: landfilling", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity, "Sent to landfill."),
        m("waste.otherDisposal", "Disposed: other methods", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          "Other disposal operations."),
        m(MetricID.wasteDisposed, "Total waste disposed", "t", group: .waste, brsr: .essential(.p6, "9"), core: .circularity,
          derive: .sum(disposed), "Incineration + landfill + other disposal."),
    ]

    // MARK: Air emissions and green credits (P6)

    private static let air: [MetricDefinition] = [
        m("air.nox", "NOx emissions", "t", group: .air, brsr: .essential(.p6, "6"), "As reported to the State Pollution Control Board."),
        m("air.sox", "SOx emissions", "t", group: .air, brsr: .essential(.p6, "6"), "As reported to the State Pollution Control Board."),
        m("air.pm", "Particulate matter", "t", group: .air, brsr: .essential(.p6, "6"), "As reported to the State Pollution Control Board."),
        m("air.greenCredits", "Green credits generated or procured", "count", .count, group: .air, brsr: .leadership(.p6, "8"),
          "Under the Green Credit Programme, for the company and its top 10 value-chain partners (added by SEBI in March 2025)."),
    ]

    // MARK: Well-being and safety (Core attribute 5, P3)

    private static let safety: [MetricDefinition] = [
        m("safety.wellbeingSpend", "Spending on employee and worker well-being", "₹ crore", .money, group: .safety,
          brsr: .essential(.p3, "1(c)"), core: .wellbeing,
          "Health and accident insurance, maternity and paternity benefits, day care, health and safety including mental health. Checked against insurance policies and invoices."),
        m("safety.wellbeingShare", "Well-being spending as share of revenue", "%", .percent, group: .safety,
          brsr: .essential(.p3, "1(c)"), core: .wellbeing,
          derive: .ratio(numerator: ["safety.wellbeingSpend"], denominator: [MetricID.revenue], scale: 100),
          "Well-being spending ÷ revenue from operations."),
        m("safety.lostTimeInjuries", "Lost-time injuries", "count", .count, group: .safety, brsr: .essential(.p3, "11"), core: .wellbeing,
          "Employees and workers, including the contract workforce."),
        m("safety.hoursWorked", "Total hours worked", "hours", group: .safety, brsr: .essential(.p3, "11"), core: .wellbeing,
          "Person-hours worked by employees and workers, including contract workforce."),
        m(MetricID.ltifr, "Lost Time Injury Frequency Rate (LTIFR)", "per million hours", .ratio, group: .safety,
          brsr: .essential(.p3, "11"), core: .wellbeing,
          derive: .ratio(numerator: ["safety.lostTimeInjuries"], denominator: ["safety.hoursWorked"], scale: 1_000_000),
          "Lost-time injuries × 1,000,000 ÷ hours worked."),
        m("safety.fatalities", "Fatalities", "count", .count, group: .safety, brsr: .essential(.p3, "11"), core: .wellbeing,
          "Checked against claims reported to the Factory Inspector."),
        m("safety.permanentDisabilities", "Permanent disabilities", "count", .count, group: .safety, brsr: .essential(.p3, "11"), core: .wellbeing,
          "Verified against claims; includes contract workforce."),
    ]

    // MARK: Workforce (Section A)

    private static let workforce: [MetricDefinition] = [
        m("workforce.employeesMale", "Employees: male", "count", .count, group: .workforce, brsr: .sectionA("IV Employees"),
          "Permanent and other-than-permanent employees at year end."),
        m("workforce.employeesFemale", "Employees: female", "count", .count, group: .workforce, brsr: .sectionA("IV Employees"),
          "Permanent and other-than-permanent employees at year end."),
        m("workforce.workersMale", "Workers: male", "count", .count, group: .workforce, brsr: .sectionA("IV Employees"),
          "Permanent and other-than-permanent workers at year end."),
        m("workforce.workersFemale", "Workers: female", "count", .count, group: .workforce, brsr: .sectionA("IV Employees"),
          "Permanent and other-than-permanent workers at year end."),
        m("workforce.boardSize", "Board of Directors: members", "count", .count, group: .workforce, brsr: .sectionA("IV Women"),
          "Total directors at year end."),
        m("workforce.womenOnBoard", "Board of Directors: women", "count", .count, group: .workforce, brsr: .sectionA("IV Women"),
          "Women directors at year end."),
        m("workforce.womenOnBoardShare", "Women on the Board", "%", .percent, group: .workforce, brsr: .sectionA("IV Women"),
          derive: .ratio(numerator: ["workforce.womenOnBoard"], denominator: ["workforce.boardSize"], scale: 100),
          "Women directors ÷ all directors."),
        m("workforce.employeeTurnover", "Turnover rate, permanent employees", "%", .percent, group: .workforce, brsr: .sectionA("IV Turnover"),
          "Leavers ÷ average permanent employees in the year."),
    ]

    // MARK: Gender diversity (Core attribute 6, P5)

    private static let gender: [MetricDefinition] = [
        m("gender.femaleWages", "Gross wages paid to women", "₹ crore", .money, group: .gender, brsr: .essential(.p5, "3(b)"), core: .gender,
          "From the employee master or wage register."),
        m(MetricID.femaleWageShare, "Wages paid to women, share of total", "%", .percent, group: .gender, brsr: .essential(.p5, "3(b)"), core: .gender,
          derive: .ratio(numerator: ["gender.femaleWages"], denominator: [MetricID.totalWages], scale: 100),
          "Gross wages paid to women ÷ total wages paid."),
        m("gender.poshComplaints", "Sexual harassment (POSH) complaints reported", "count", .count, group: .gender,
          brsr: .essential(.p5, "7"), core: .gender, "Complaints under the POSH Act in the year."),
        m("gender.femaleHeadcount", "Women employees and workers", "count", .count, group: .gender, brsr: .essential(.p5, "7"), core: .gender,
          "Denominator for the POSH complaint rate."),
        m("gender.poshRate", "POSH complaints as share of women employees and workers", "%", .percent, group: .gender,
          brsr: .essential(.p5, "7"), core: .gender,
          derive: .ratio(numerator: ["gender.poshComplaints"], denominator: ["gender.femaleHeadcount"], scale: 100),
          "Complaints ÷ women employees and workers."),
        m("gender.poshUpheld", "POSH complaints upheld", "count", .count, group: .gender, brsr: .essential(.p5, "7"), core: .gender,
          "Complaints upheld after inquiry."),
    ]

    // MARK: Inclusive development (Core attribute 7, P8)

    private static let inclusion: [MetricDefinition] = [
        m("inclusion.msmeSourcing", "Input material sourced from MSMEs and small producers", "%", .percent, group: .inclusion,
          brsr: .essential(.p8, "4"), core: .inclusion,
          "Raw materials, spares, services and capital items sourced directly from MSMEs and small producers, % of total purchases by value."),
        m("inclusion.indiaSourcing", "Input material sourced from within India", "%", .percent, group: .inclusion,
          brsr: .essential(.p8, "4"), "Directly sourced from within India, % of total purchases by value."),
        m("inclusion.smallerTownWages", "Wages paid in smaller towns", "%", .percent, group: .inclusion,
          brsr: .essential(.p8, "5"), core: .inclusion,
          "Wages to people employed in rural, semi-urban, urban and metropolitan locations (RBI classification), % of total wage cost. Give the split in the method."),
    ]

    // MARK: Customers and suppliers (Core attribute 8)

    private static let fairness: [MetricDefinition] = [
        m("fairness.dataBreachShare", "Customer data breaches", "%", .percent, group: .fairness, brsr: .essential(.p9, "7"), core: .fairness,
          "Customer-data loss or breach events as % of all data breaches or cyber-security events."),
        m("fairness.payableDays", "Days of accounts payable", "days", .ratio, group: .fairness, brsr: .essential(.p1, "8"), core: .fairness,
          derive: .ratio(numerator: ["fin.accountsPayable"], denominator: ["fin.purchaseCost"], scale: 365),
          "Accounts payable × 365 ÷ cost of goods and services procured."),
    ]

    // MARK: Openness of business (Core attribute 9, P1 EI 9)

    private static let openness: [MetricDefinition] = [
        m("openness.tradingHousePurchases", "Purchases from trading houses", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "% of total purchases."),
        m("openness.tradingHouseCount", "Trading houses purchased from", "count", .count, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "Number of trading houses."),
        m("openness.top10TradingHouses", "Purchases from top 10 trading houses", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "% of total purchases from trading houses."),
        m("openness.dealerSales", "Sales to dealers and distributors", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "% of total sales."),
        m("openness.dealerCount", "Dealers and distributors sold to", "count", .count, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "Number of dealers and distributors."),
        m("openness.top10Dealers", "Sales to top 10 dealers and distributors", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "% of total sales to dealers and distributors."),
        m("openness.rptPurchases", "Related-party share of purchases", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "From audited related-party transaction disclosures."),
        m("openness.rptSales", "Related-party share of sales", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "From audited related-party transaction disclosures."),
        m("openness.rptLoans", "Related-party share of loans and advances", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "From audited related-party transaction disclosures."),
        m("openness.rptInvestments", "Related-party share of investments", "%", .percent, group: .openness,
          brsr: .essential(.p1, "9"), core: .openness, "From audited related-party transaction disclosures."),
    ]

    // MARK: Climate risk (IFRS S2 cross-industry metrics 29(b)–(g))

    private static let climateRisk: [MetricDefinition] = [
        m("s2.transitionVulnerableAmount", "Assets or activities vulnerable to transition risks", "₹ crore", .money, group: .climateRisk,
          ifrs: .required("29(b)"), "Amount of assets or business activities vulnerable to transition risks."),
        m("s2.transitionVulnerableShare", "Share vulnerable to transition risks", "%", .percent, group: .climateRisk,
          ifrs: .required("29(b)"), "Percentage of assets or business activities vulnerable to transition risks."),
        m(MetricID.physicalVulnerableAmount, "Assets or activities vulnerable to physical risks", "₹ crore", .money, group: .climateRisk,
          ifrs: .required("29(c)"), "Can be filled from Risks & Opportunities → physical-risk assessments."),
        m(MetricID.physicalVulnerableShare, "Share vulnerable to physical risks", "%", .percent, group: .climateRisk,
          ifrs: .required("29(c)"), "Can be filled from Risks & Opportunities → physical-risk assessments."),
        m("s2.opportunityAlignedAmount", "Assets or activities aligned with climate opportunities", "₹ crore", .money, group: .climateRisk,
          ifrs: .required("29(d)"), "Amount of assets or business activities aligned with climate-related opportunities."),
        m("s2.opportunityAlignedShare", "Share aligned with climate opportunities", "%", .percent, group: .climateRisk,
          ifrs: .required("29(d)"), "Percentage aligned with climate-related opportunities."),
        m("s2.capitalDeployed", "Capital deployed to climate risks and opportunities", "₹ crore", .money, group: .climateRisk,
          ifrs: .required("29(e)"), "Capital expenditure, financing or investment deployed towards climate-related risks and opportunities."),
        m("s2.internalCarbonPrice", "Internal carbon price", "₹ per tCO2e", .ratio, group: .climateRisk, ifrs: .required("29(f)"),
          "Price per tonne used internally. Explain how it is applied in the Metrics narrative. Mark not applicable if none is used."),
        m("s2.remunerationLinkedShare", "Executive remuneration linked to climate", "%", .percent, group: .climateRisk,
          ifrs: .required("29(g)"), "Share of executive remuneration recognised in the period that is linked to climate-related considerations."),
    ]
}
