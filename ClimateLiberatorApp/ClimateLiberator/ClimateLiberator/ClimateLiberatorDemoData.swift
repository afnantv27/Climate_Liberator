import Foundation

struct ClimateLiberatorDemoCompany {
    let name: String
    let sector: String
    let portfolioLabel: String
    let states: [String]
    let baselineScenarioName: String
    let stressedScenarioName: String
    let sites: [ClimateLiberatorDemoSite]
    let workflow: [ClimateLiberatorDemoStep]

    static let indianUtility = ClimateLiberatorDemoCompany(
        name: "Sahyadri Grid Utilities",
        sector: "Transmission & Distribution Utility",
        portfolioLabel: "Western India substation resilience pilot",
        states: ["Maharashtra", "Karnataka"],
        baselineScenarioName: "Monsoon-normal baseline",
        stressedScenarioName: "High-wind pre-monsoon stress",
        sites: [
            ClimateLiberatorDemoSite(
                name: "Kolhapur North Substation",
                district: "Kolhapur",
                state: "Maharashtra",
                assetCount: 2,
                nearbyBuildings: 74,
                baselineBurnProbability: 0.11,
                stressedBurnProbability: 0.29,
                riskBand: "High",
                decisionSummary: "Escalate vegetation clearance and backup switching plan before the next dry season."
            ),
            ClimateLiberatorDemoSite(
                name: "Belagavi Ring Main",
                district: "Belagavi",
                state: "Karnataka",
                assetCount: 1,
                nearbyBuildings: 41,
                baselineBurnProbability: 0.06,
                stressedBurnProbability: 0.14,
                riskBand: "Medium",
                decisionSummary: "Track as watchlist site and confirm insurer assumptions in the stressed scenario."
            ),
            ClimateLiberatorDemoSite(
                name: "Satara Operations Yard",
                district: "Satara",
                state: "Maharashtra",
                assetCount: 1,
                nearbyBuildings: 23,
                baselineBurnProbability: 0.03,
                stressedBurnProbability: 0.07,
                riskBand: "Low",
                decisionSummary: "Retain current controls and monitor under quarterly review."
            )
        ],
        workflow: [
            ClimateLiberatorDemoStep(
                title: "Portfolio View",
                detail: "Risk teams start with the utility portfolio to see which substations and yards concentrate wildfire exposure across Maharashtra and Karnataka.",
                output: "High-risk asset count, concentration hotspots, and nearest-site shortlist."
            ),
            ClimateLiberatorDemoStep(
                title: "Site View",
                detail: "Operations teams screen the selected substation against nearby buildings, stored wildfire assessments, and local exposure context.",
                output: "Nearby asset mix, footprint, built-up area, and risk snapshot."
            ),
            ClimateLiberatorDemoStep(
                title: "Simulation View",
                detail: "Analysts run a baseline and a stressed wildfire scenario against the same prepared study bundle to show how conditions change.",
                output: "Burn %, ROS, breached thresholds, and comparator deltas."
            ),
            ClimateLiberatorDemoStep(
                title: "TCFD / Board Pack",
                detail: "Governance teams review the run package, assign threshold-breach actions, and export the approved board pack.",
                output: "Decision cockpit, action owner, due date, and final board-ready package."
            )
        ]
    )
}

struct ClimateLiberatorDemoSite: Identifiable {
    let id = UUID()
    let name: String
    let district: String
    let state: String
    let assetCount: Int
    let nearbyBuildings: Int
    let baselineBurnProbability: Double
    let stressedBurnProbability: Double
    let riskBand: String
    let decisionSummary: String

    var deltaBurnProbability: Double {
        stressedBurnProbability - baselineBurnProbability
    }
}

struct ClimateLiberatorDemoStep: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let output: String
}

