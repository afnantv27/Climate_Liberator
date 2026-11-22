import Foundation

/// Broad sector of a client company; used by Clients, Disclosure and benchmarks.
nonisolated enum IndustrySector: String, Codable, CaseIterable, Identifiable, Sendable {
    case manufacturing, energyUtilities, materialsMining, chemicals, financialServices, itServices
    case consumerGoods, healthcare, realEstateConstruction, transportLogistics, agriculture, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .manufacturing: return "Manufacturing"
        case .energyUtilities: return "Energy & Utilities"
        case .materialsMining: return "Materials & Mining"
        case .chemicals: return "Chemicals"
        case .financialServices: return "Financial Services"
        case .itServices: return "IT & Services"
        case .consumerGoods: return "Consumer Goods & Retail"
        case .healthcare: return "Healthcare & Pharma"
        case .realEstateConstruction: return "Real Estate & Construction"
        case .transportLogistics: return "Transport & Logistics"
        case .agriculture: return "Agriculture & Food"
        case .other: return "Other"
        }
    }
    /// Services report intensity per employee or FTE rather than per tonne of product.
    var isServices: Bool { self == .financialServices || self == .itServices }
}
