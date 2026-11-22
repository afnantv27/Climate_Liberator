import Foundation

/// Top-level workspaces, in the order work flows: who the clients are, what they
/// emit, how they reduce it, what they report — with climate risk alongside.
enum AppWorkspace: String, CaseIterable, Identifiable {
    case home
    case clients
    case ghgAccounting
    case reduce
    case disclosure
    case climateRisk

    var id: String { rawValue }

    /// Label in the toolbar.
    var shortTitle: String {
        switch self {
        case .home: return "Home"
        case .clients: return "Clients"
        case .ghgAccounting: return "Measure"
        case .reduce: return "Reduce"
        case .disclosure: return "Report"
        case .climateRisk: return "Climate Risk"
        }
    }

    var title: String {
        switch self {
        case .home: return "Home"
        case .clients: return "Clients"
        case .ghgAccounting: return "GHG Accounting"
        case .reduce: return "Reduce"
        case .disclosure: return "Disclosure (BRSR · IFRS S2)"
        case .climateRisk: return "Climate Risk"
        }
    }

    var subtitle: String {
        switch self {
        case .home: return "What needs attention across all clients."
        case .clients: return "Client companies, their sites and clusters."
        case .ghgAccounting: return "GHG inventories with emission factors from connected databases."
        case .reduce: return "Targets, reduction measures, carbon credits and action plans."
        case .disclosure: return "BRSR, BRSR Core and IFRS S2 reporting: data, review, sign-off and reports."
        case .climateRisk: return "Hazard simulation for sites: wildfire today, more hazards planned."
        }
    }
}
