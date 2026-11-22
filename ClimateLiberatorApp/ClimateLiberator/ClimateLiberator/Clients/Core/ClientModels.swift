import Foundation

// The client register: every company the user works with, its sites and cluster.
// Other modules refer to clients by `Client.id` and never copy client details.

/// Enterprise size as companies describe themselves (India's MSME categories plus
/// large). The legal thresholds change over time, so the app does not compute it.
nonisolated enum EnterpriseSize: String, Codable, CaseIterable, Identifiable, Sendable {
    case micro, small, medium, large

    var id: String { rawValue }
    var title: String {
        switch self {
        case .micro: return "Micro"
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }
    var isMSME: Bool { self != .large }
}

nonisolated enum SiteKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case plant, office, warehouse, retail, farm, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .plant: return "Plant"
        case .office: return "Office"
        case .warehouse: return "Warehouse"
        case .retail: return "Retail"
        case .farm: return "Farm"
        case .other: return "Other"
        }
    }
    var systemImage: String {
        switch self {
        case .plant: return "building.2"
        case .office: return "building"
        case .warehouse: return "shippingbox"
        case .retail: return "cart"
        case .farm: return "leaf"
        case .other: return "mappin"
        }
    }
}

/// A physical location of a client. Coordinates let Climate Risk assess it later.
nonisolated struct Site: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var kind: SiteKind = .plant
    var address = ""
    var district = ""
    var state = ""
    var pinCode = ""
    var latitude: Double?
    var longitude: Double?
    var notes = ""

    init(name: String = "", kind: SiteKind = .plant) {
        self.name = name
        self.kind = kind
    }

    var hasCoordinates: Bool { latitude != nil && longitude != nil }

    /// "Chennai, Tamil Nadu"; empty when neither is known.
    var placeLabel: String {
        [district, state].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled site" : trimmed
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, address, district, state, pinCode, latitude, longitude, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        name = try c.value(.name, default: "")
        kind = try c.value(.kind, default: .plant)
        address = try c.value(.address, default: "")
        district = try c.value(.district, default: "")
        state = try c.value(.state, default: "")
        pinCode = try c.value(.pinCode, default: "")
        latitude = try c.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try c.decodeIfPresent(Double.self, forKey: .longitude)
        notes = try c.value(.notes, default: "")
    }
}

nonisolated struct ClientContact: Codable, Hashable, Sendable {
    var name = ""
    var role = ""
    var email = ""
    var phone = ""

    init() {}

    private enum CodingKeys: String, CodingKey { case name, role, email, phone }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.value(.name, default: "")
        role = try c.value(.role, default: "")
        email = try c.value(.email, default: "")
        phone = try c.value(.phone, default: "")
    }
}

/// One client company. Saved as its own file, like engagements and inventories.
nonisolated struct Client: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var name = ""
    var sector: IndustrySector = .manufacturing
    var size: EnterpriseSize = .small
    /// Industrial cluster or programme the client belongs to, e.g. "Chennai polymer cluster".
    /// Free text so consultants can use their own grouping; matched case-insensitively.
    var cluster = ""
    var cin = ""
    var website = ""
    var contact = ClientContact()
    var sites: [Site] = []
    var notes = ""
    /// Illustrative data, never a real company.
    var isExample = false
    var createdAt = Date()
    var updatedAt = Date()

    init(name: String = "") {
        self.name = name
    }

    var displayName: String {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "Untitled client" : trimmed
    }

    var clusterName: String { cluster.trimmingCharacters(in: .whitespaces) }

    func site(_ id: UUID) -> Site? { sites.first { $0.id == id } }

    private enum CodingKeys: String, CodingKey {
        case id, name, sector, size, cluster, cin, website, contact, sites, notes, isExample, createdAt, updatedAt
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        name = try c.value(.name, default: "")
        sector = try c.value(.sector, default: .manufacturing)
        size = try c.value(.size, default: .small)
        cluster = try c.value(.cluster, default: "")
        cin = try c.value(.cin, default: "")
        website = try c.value(.website, default: "")
        contact = try c.value(.contact, default: ClientContact())
        sites = try c.value(.sites, default: [])
        notes = try c.value(.notes, default: "")
        isExample = try c.value(.isExample, default: false)
        createdAt = try c.value(.createdAt, default: Date())
        updatedAt = try c.value(.updatedAt, default: Date())
    }
}
