import Foundation

/// A place found in OpenStreetMap, with its outline when OSM maps one.
nonisolated struct PlaceBoundaryResult: Identifiable, Hashable, Sendable {
    let osmType: String
    let osmID: Int64
    let name: String
    let displayName: String
    /// OSM address type or place type, e.g. "municipality", "city", "district".
    let kind: String
    let center: GeoCoordinate
    /// Largest outer ring of the OSM geometry; nil for point-only results.
    let boundary: BoundaryPolygon?
    /// Number of separate polygon parts OSM returned (islands, exclaves).
    let partCount: Int
    let isAdministrative: Bool

    var id: String { "\(osmType)/\(osmID)" }
    var hasBoundary: Bool { boundary != nil }
    var osmURL: URL? { URL(string: "https://www.openstreetmap.org/\(osmType)/\(osmID)") }

    /// Stored with the inventory so the boundary's origin and licence travel with it.
    var sourceDescription: String {
        "OpenStreetMap \(osmType) \(osmID) via Nominatim, retrieved \(Date().formatted(date: .abbreviated, time: .omitted)) — © OpenStreetMap contributors, ODbL"
    }
}

nonisolated enum BoundaryLookupError: LocalizedError, Equatable {
    case emptyQuery
    case http(Int)
    case unreadable

    var errorDescription: String? {
        switch self {
        case .emptyQuery: return "Type a place name first."
        case .http(429): return "OpenStreetMap is rate-limiting requests. Wait a minute and search again."
        case .http(let status): return "Place search failed (HTTP \(status))."
        case .unreadable: return "Place search returned data the app could not read."
        }
    }
}

/// Looks up places and their administrative outlines with the OpenStreetMap
/// Nominatim API. Usage policy: at most one request per second, an identifying
/// User-Agent, no search-as-you-type, and visible "© OpenStreetMap contributors".
nonisolated struct BoundaryLookupService: Sendable {
    static let endpoint = "https://nominatim.openstreetmap.org/search"
    static let userAgent = "ClimateLiberator/1.0 (macOS desktop app; GHG inventory boundary lookup)"
    static let attribution = "Boundaries © OpenStreetMap contributors (ODbL)"
    /// Simplification tolerance in degrees (~11 m); keeps large outlines light.
    static let polygonThresholdDegrees = 0.0001

    let loader: HTTPDataLoading

    init(loader: HTTPDataLoading = URLSessionHTTPLoader()) {
        self.loader = loader
    }

    func makeRequest(query: String, limit: Int = 8) throws -> URLRequest {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw BoundaryLookupError.emptyQuery }
        var components = URLComponents(string: Self.endpoint)!
        components.queryItems = [
            URLQueryItem(name: "q", value: trimmed),
            URLQueryItem(name: "format", value: "jsonv2"),
            URLQueryItem(name: "polygon_geojson", value: "1"),
            URLQueryItem(name: "polygon_threshold", value: String(Self.polygonThresholdDegrees)),
            URLQueryItem(name: "limit", value: String(min(max(limit, 1), 40))),
            URLQueryItem(name: "accept-language", value: "en"),
        ]
        var request = URLRequest(url: components.url!, timeoutInterval: 30)
        request.setValue(Self.userAgent, forHTTPHeaderField: "User-Agent")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func search(_ query: String) async throws -> [PlaceBoundaryResult] {
        let request = try makeRequest(query: query)
        let (data, response) = try await loader.load(request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw BoundaryLookupError.http(http.statusCode)
        }
        // Outlines can hold thousands of points: parse off the main actor.
        return try await Task.detached(priority: .userInitiated) { try Self.parse(data) }.value
    }

    /// Parses a Nominatim `format=jsonv2` response. Results with an outline come first.
    static func parse(_ data: Data) throws -> [PlaceBoundaryResult] {
        guard let items = (try? JSONSerialization.jsonObject(with: data)) as? [[String: Any]] else {
            throw BoundaryLookupError.unreadable
        }
        let results: [PlaceBoundaryResult] = items.compactMap { item in
            guard let osmType = item["osm_type"] as? String,
                  let osmID = int64(item["osm_id"]),
                  let lat = double(item["lat"]), let lon = double(item["lon"]) else { return nil }
            let displayName = item["display_name"] as? String ?? ""
            let name = (item["name"] as? String).flatMap { $0.isEmpty ? nil : $0 }
                ?? displayName.components(separatedBy: ",").first ?? displayName
            let kind = (item["addresstype"] as? String) ?? (item["type"] as? String) ?? ""
            let outline = item["geojson"].map { BoundaryFileCodec.largestPolygon(inGeoJSONObject: $0) }
            let polygon = outline?.polygon
            let parts = outline?.partCount ?? 0
            let isAdministrative = (item["category"] as? String) == "boundary" && (item["type"] as? String) == "administrative"
            return PlaceBoundaryResult(osmType: osmType, osmID: osmID, name: name, displayName: displayName,
                                       kind: kind.replacingOccurrences(of: "_", with: " "),
                                       center: GeoCoordinate(latitude: lat, longitude: lon),
                                       boundary: polygon, partCount: parts, isAdministrative: isAdministrative)
        }
        // Stable: keep Nominatim's importance order within each group.
        return results.filter(\.hasBoundary) + results.filter { !$0.hasBoundary }
    }

    private static func double(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        return (value as? String).flatMap(Double.init)
    }

    private static func int64(_ value: Any?) -> Int64? {
        if let number = value as? NSNumber { return number.int64Value }
        return (value as? String).flatMap { Int64($0) }
    }
}
