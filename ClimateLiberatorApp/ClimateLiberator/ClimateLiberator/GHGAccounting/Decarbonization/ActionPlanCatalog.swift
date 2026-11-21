import Foundation

/// Suggestions that pre-fill an action plan: co-benefits, how much the city controls
/// a measure, a typical lead owner, and national schemes that may fund it.
///
/// These are starting points, not findings. Co-benefits and influence are
/// qualitative judgements the user can change; scheme status changes often, so
/// each scheme carries the date it was checked.
nonisolated enum ActionPlanCatalog {

    // MARK: Funding schemes (India)

    struct FundingScheme: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let ministry: String
        let covers: String
        let url: String
    }

    /// When the scheme list was last checked against official or news sources.
    static let schemesCheckedOn = "November 2026"

    static let schemes: [FundingScheme] = [
        FundingScheme(id: "pm-surya-ghar", name: "PM Surya Ghar: Muft Bijli Yojana", ministry: "MNRE",
                      covers: "Subsidy for residential rooftop solar; target 1 crore homes by FY 2026-27.",
                      url: "https://newsonair.gov.in/over-50-lakh-households-benefit-under-pm-surya-ghar-muft-bijli-yojana-pralhad-joshi/"),
        FundingScheme(id: "pm-e-drive", name: "PM E-DRIVE", ministry: "Ministry of Heavy Industries",
                      covers: "Demand incentives for e-2Ws, e-3Ws, e-trucks and e-ambulances; e-buses; charging. Extended to 2028.",
                      url: "https://www.pib.gov.in/FactsheetDetails.aspx?Id=151062"),
        FundingScheme(id: "pm-ebus-sewa", name: "PM-eBus Sewa", ministry: "MoHUA",
                      covers: "E-bus operations in cities, with a payment security mechanism for operators.",
                      url: "https://www.autocarpro.in/news/budget-2025-rs-4000-crore-for-pm-e-drive-rs-1310-crore-for-pm-ebus-sewa-in-fy26-124728"),
        FundingScheme(id: "sbm-u-2", name: "Swachh Bharat Mission-Urban 2.0", ministry: "MoHUA",
                      covers: "Solid waste processing, legacy dumpsite remediation and used-water management. Check the current phase.",
                      url: "https://pib.gov.in/PressReleasePage.aspx?PRID=1763355"),
        FundingScheme(id: "amrut-2", name: "AMRUT 2.0", ministry: "MoHUA",
                      covers: "Water supply, sewerage and septage management, green spaces and parks.",
                      url: "https://pib.gov.in/PressReleasePage.aspx?PRID=1760039"),
        FundingScheme(id: "nagar-van", name: "Nagar Van Yojana", ministry: "MoEFCC",
                      covers: "Urban forests (Nagar Van) and gardens (Nagar Vatika) with ULBs; runs to 2026-27.",
                      url: "https://eparlib.sansad.in/bitstream/123456789/2988196/1/AU936_50zNvG.pdf"),
        FundingScheme(id: "gobardhan", name: "GOBARdhan (National Circular Bioenergy Scheme)", ministry: "MoPNG",
                      covers: "Compressed biogas plants from organic waste; FY 2026-27 to 2035-36.",
                      url: "https://static.pib.gov.in/WriteReadData/specificdocs/documents/2026/aug/doc202686946301.pdf"),
    ]

    static func scheme(_ id: String) -> FundingScheme? { schemes.first { $0.id == id } }

    // MARK: Per-measure suggestions

    struct Suggestion: Sendable {
        let coBenefits: Set<CoBenefit>
        let influence: CityInfluence
        let schemeIDs: [String]
    }

    static func suggestion(for measureID: String) -> Suggestion {
        suggestions[measureID] ?? Suggestion(coBenefits: [], influence: .enable, schemeIDs: [])
    }

    private static let suggestions: [String: Suggestion] = [
        // Buildings & industry
        "lpg-to-induction": Suggestion(coBenefits: [.health, .energySecurity], influence: .enable, schemeIDs: []),
        "biogas-cooking": Suggestion(coBenefits: [.resourceRecovery, .energySecurity, .health], influence: .enable, schemeIDs: []),
        "ecbc-buildings": Suggestion(coBenefits: [.savings, .resilience], influence: .enable, schemeIDs: []),
        "efficient-fans": Suggestion(coBenefits: [.savings], influence: .enable, schemeIDs: []),
        "solar-water-heaters": Suggestion(coBenefits: [.savings], influence: .enable, schemeIDs: []),
        "led-streetlights": Suggestion(coBenefits: [.savings], influence: .direct, schemeIDs: []),
        "industrial-efficiency": Suggestion(coBenefits: [.savings], influence: .enable, schemeIDs: []),
        "industrial-gas-switch": Suggestion(coBenefits: [.airQuality, .health], influence: .enable, schemeIDs: []),
        "diesel-generators-to-solar": Suggestion(coBenefits: [.airQuality, .savings, .energySecurity], influence: .enable, schemeIDs: []),
        // Energy supply
        "rooftop-solar": Suggestion(coBenefits: [.savings, .jobs, .energySecurity], influence: .enable, schemeIDs: ["pm-surya-ghar"]),
        "green-power": Suggestion(coBenefits: [.energySecurity], influence: .enable, schemeIDs: []),
        "grid-decarbonisation": Suggestion(coBenefits: [.airQuality, .energySecurity], influence: .advocate, schemeIDs: []),
        // Transport
        "electric-two-wheelers": Suggestion(coBenefits: [.airQuality, .savings], influence: .enable, schemeIDs: ["pm-e-drive"]),
        "electric-cars": Suggestion(coBenefits: [.airQuality, .savings], influence: .enable, schemeIDs: []),
        "electric-buses": Suggestion(coBenefits: [.airQuality, .mobility, .health], influence: .enable, schemeIDs: ["pm-ebus-sewa", "pm-e-drive"]),
        "electric-waste-trucks": Suggestion(coBenefits: [.airQuality], influence: .direct, schemeIDs: ["pm-e-drive"]),
        "modal-shift": Suggestion(coBenefits: [.mobility, .airQuality, .health, .equity], influence: .enable, schemeIDs: []),
        "two-wheeler-efficiency": Suggestion(coBenefits: [.savings, .airQuality], influence: .advocate, schemeIDs: []),
        "ethanol-blending": Suggestion(coBenefits: [.energySecurity], influence: .advocate, schemeIDs: []),
        // Solid waste
        "organics-to-compost": Suggestion(coBenefits: [.resourceRecovery, .sanitation, .jobs], influence: .direct, schemeIDs: ["sbm-u-2"]),
        "organics-to-biogas": Suggestion(coBenefits: [.resourceRecovery, .energySecurity], influence: .direct, schemeIDs: ["sbm-u-2", "gobardhan"]),
        "landfill-gas-capture": Suggestion(coBenefits: [.airQuality, .energySecurity], influence: .direct, schemeIDs: ["sbm-u-2"]),
        "waste-reduction": Suggestion(coBenefits: [.resourceRecovery, .sanitation], influence: .enable, schemeIDs: ["sbm-u-2"]),
        "end-open-burning": Suggestion(coBenefits: [.airQuality, .health], influence: .direct, schemeIDs: ["sbm-u-2"]),
        // Wastewater
        "septic-to-aerobic-stp": Suggestion(coBenefits: [.sanitation, .health], influence: .direct, schemeIDs: ["amrut-2", "sbm-u-2"]),
        // Land use and removals
        "urban-trees": Suggestion(coBenefits: [.greenSpace, .resilience, .airQuality], influence: .direct, schemeIDs: ["nagar-van", "amrut-2"]),
        "urban-green-cover": Suggestion(coBenefits: [.greenSpace, .resilience], influence: .direct, schemeIDs: ["nagar-van", "amrut-2"]),
    ]

    // MARK: Owners

    /// Typical lead agency for a category in an Indian city, shown as a placeholder.
    static func suggestedOwner(for category: MeasureCategory) -> String {
        switch category {
        case .buildings: return "Municipal engineering wing"
        case .energySupply: return "Electricity distribution company (DISCOM)"
        case .transport: return "State transport undertaking"
        case .waste: return "Municipal health and sanitation wing"
        case .wastewater: return "Municipal engineering or water authority"
        case .landUse: return "Parks wing or state forest department"
        }
    }

    /// Owners offered in the picker; any text can be typed instead.
    static let commonOwners = [
        "Municipal council and mayor's office",
        "Municipal engineering wing",
        "Municipal health and sanitation wing",
        "Town planning department",
        "Parks wing",
        "Electricity distribution company (DISCOM)",
        "State renewable energy agency",
        "State transport undertaking",
        "Pollution control board",
        "State forest department",
        "Private operator (PPP)",
        "Residents' welfare associations",
    ]

    // MARK: Effective values

    static func coBenefits(of selection: ScenarioMeasureSelection) -> Set<CoBenefit> {
        selection.plan?.coBenefits ?? suggestion(for: selection.measureID).coBenefits
    }

    static func influence(of selection: ScenarioMeasureSelection) -> CityInfluence {
        selection.plan?.influence ?? suggestion(for: selection.measureID).influence
    }
}
