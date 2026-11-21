import Foundation

/// Inventory boundary as a single outer ring of WGS84 coordinates (no holes).
/// Vertices are stored open: the first point is not repeated at the end.
nonisolated struct BoundaryPolygon: Codable, Hashable, Sendable {
    var vertices: [GeoCoordinate] = []

    /// Mean radius, used for great-circle distances.
    static let earthRadiusMetres = 6_371_008.8
    /// Above this size the O(n²) crossing check is skipped (imported official boundaries are assumed clean).
    static let maxVerticesForCrossingCheck = 6_000

    var isEmpty: Bool { vertices.isEmpty }
    var isClosed: Bool { vertices.count >= 3 }

    /// Call once per render and reuse: the crossing check is O(n²).
    var validationIssues: [String] {
        var issues: [String] = []
        if vertices.count < 3 { issues.append("Add at least three points to close the boundary.") }
        else if selfIntersects() { issues.append("Boundary edges cross each other. Move or remove points so the outline does not overlap itself.") }
        if vertices.contains(where: { abs($0.latitude) > 90 || abs($0.longitude) > 180 }) {
            issues.append("A point has an invalid latitude or longitude.")
        }
        return issues
    }

    var isValid: Bool { validationIssues.isEmpty }

    // MARK: Measurements

    /// WGS84 ellipsoidal area: the Chamberlain & Duquette (2007) ring formula on the
    /// authalic (equal-area) sphere, with each latitude converted to authalic
    /// latitude. Matches geodesic WGS84 area to about 0.002% for city boundaries.
    func areaSquareMetres() -> Double {
        let count = vertices.count
        guard count >= 3 else { return 0 }
        let sinBeta = vertices.map { Self.sinAuthalicLatitude($0.latitude) }
        var total = 0.0
        for index in 0..<count {
            let lower = vertices[index]
            let upper = vertices[(index + 2) % count]
            total += (Self.radians(upper.longitude) - Self.radians(lower.longitude)) * sinBeta[(index + 1) % count]
        }
        return abs(total * Self.authalicRadius * Self.authalicRadius / 2)
    }

    // WGS84 ellipsoid and its authalic sphere.
    private static let semiMajorAxis = 6_378_137.0
    private static let eccentricitySquared: Double = {
        let flattening = 1 / 298.257_223_563
        return flattening * (2 - flattening)
    }()
    private static let eccentricity = eccentricitySquared.squareRoot()
    private static func authalicQ(_ sinPhi: Double) -> Double {
        let e = eccentricity, e2 = eccentricitySquared
        return (1 - e2) * (sinPhi / (1 - e2 * sinPhi * sinPhi) - (1 / (2 * e)) * log((1 - e * sinPhi) / (1 + e * sinPhi)))
    }
    private static let authalicQPole = authalicQ(1)
    static let authalicRadius = semiMajorAxis * (authalicQPole / 2).squareRoot()

    static func sinAuthalicLatitude(_ latitude: Double) -> Double {
        min(1, max(-1, authalicQ(sin(radians(latitude))) / authalicQPole))
    }

    var areaSquareKilometres: Double { areaSquareMetres() / 1_000_000 }

    func perimeterMetres() -> Double {
        guard vertices.count >= 2 else { return 0 }
        var total = 0.0
        for index in 0..<vertices.count {
            let next = vertices[(index + 1) % vertices.count]
            if vertices.count == 2 && index == 1 { break }
            total += Self.haversineMetres(vertices[index], next)
        }
        return total
    }

    var boundingBox: (minLatitude: Double, maxLatitude: Double, minLongitude: Double, maxLongitude: Double)? {
        guard let first = vertices.first else { return nil }
        var box = (minLatitude: first.latitude, maxLatitude: first.latitude, minLongitude: first.longitude, maxLongitude: first.longitude)
        for point in vertices.dropFirst() {
            box.minLatitude = min(box.minLatitude, point.latitude)
            box.maxLatitude = max(box.maxLatitude, point.latitude)
            box.minLongitude = min(box.minLongitude, point.longitude)
            box.maxLongitude = max(box.maxLongitude, point.longitude)
        }
        return box
    }

    /// Area-weighted planar centroid in degrees (fine for city-sized boundaries).
    var centroid: GeoCoordinate? {
        guard vertices.count >= 3 else {
            guard !vertices.isEmpty else { return nil }
            let lat = vertices.map(\.latitude).reduce(0, +) / Double(vertices.count)
            let lon = vertices.map(\.longitude).reduce(0, +) / Double(vertices.count)
            return GeoCoordinate(latitude: lat, longitude: lon)
        }
        var area = 0.0, cx = 0.0, cy = 0.0
        for index in 0..<vertices.count {
            let a = vertices[index], b = vertices[(index + 1) % vertices.count]
            let cross = a.longitude * b.latitude - b.longitude * a.latitude
            area += cross
            cx += (a.longitude + b.longitude) * cross
            cy += (a.latitude + b.latitude) * cross
        }
        guard abs(area) > 1e-15 else { return vertices.first }
        return GeoCoordinate(latitude: cy / (3 * area), longitude: cx / (3 * area))
    }

    /// Ray-casting point-in-polygon test in longitude/latitude space.
    func contains(_ point: GeoCoordinate) -> Bool {
        guard vertices.count >= 3 else { return false }
        var inside = false
        var j = vertices.count - 1
        for i in 0..<vertices.count {
            let a = vertices[i], b = vertices[j]
            if (a.latitude > point.latitude) != (b.latitude > point.latitude) {
                let crossing = (b.longitude - a.longitude) * (point.latitude - a.latitude) / (b.latitude - a.latitude) + a.longitude
                if point.longitude < crossing { inside.toggle() }
            }
            j = i
        }
        return inside
    }

    /// True when any two non-adjacent edges intersect. A bounding-box test rejects
    /// most edge pairs before the exact orientation test.
    func selfIntersects() -> Bool {
        let count = vertices.count
        guard count >= 4, count <= Self.maxVerticesForCrossingCheck else { return false }
        let boxes: [(minX: Double, maxX: Double, minY: Double, maxY: Double)] = (0..<count).map { index in
            let a = vertices[index], b = vertices[(index + 1) % count]
            return (min(a.longitude, b.longitude), max(a.longitude, b.longitude),
                    min(a.latitude, b.latitude), max(a.latitude, b.latitude))
        }
        for i in 0..<count {
            let boxA = boxes[i]
            for j in (i + 1)..<count {
                // Skip edges that share a vertex.
                if (i + 1) % count == j || (j + 1) % count == i { continue }
                let boxB = boxes[j]
                if boxA.maxX < boxB.minX || boxB.maxX < boxA.minX || boxA.maxY < boxB.minY || boxB.maxY < boxA.minY { continue }
                if Self.segmentsIntersect(vertices[i], vertices[(i + 1) % count], vertices[j], vertices[(j + 1) % count]) { return true }
            }
        }
        return false
    }

    /// Positive when vertices run counter-clockwise (in lon/lat).
    var signedPlanarArea: Double {
        guard vertices.count >= 3 else { return 0 }
        var sum = 0.0
        for index in 0..<vertices.count {
            let a = vertices[index], b = vertices[(index + 1) % vertices.count]
            sum += a.longitude * b.latitude - b.longitude * a.latitude
        }
        return sum / 2
    }

    // MARK: Helpers

    static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }

    static func haversineMetres(_ a: GeoCoordinate, _ b: GeoCoordinate) -> Double {
        let dLat = radians(b.latitude - a.latitude)
        let dLon = radians(b.longitude - a.longitude)
        let h = sin(dLat / 2) * sin(dLat / 2)
            + cos(radians(a.latitude)) * cos(radians(b.latitude)) * sin(dLon / 2) * sin(dLon / 2)
        return 2 * earthRadiusMetres * asin(min(1, sqrt(h)))
    }

    private static func orientation(_ p: GeoCoordinate, _ q: GeoCoordinate, _ r: GeoCoordinate) -> Double {
        (q.longitude - p.longitude) * (r.latitude - p.latitude) - (q.latitude - p.latitude) * (r.longitude - p.longitude)
    }

    private static func onSegment(_ p: GeoCoordinate, _ q: GeoCoordinate, _ r: GeoCoordinate) -> Bool {
        min(p.longitude, r.longitude) <= q.longitude && q.longitude <= max(p.longitude, r.longitude)
            && min(p.latitude, r.latitude) <= q.latitude && q.latitude <= max(p.latitude, r.latitude)
    }

    static func segmentsIntersect(_ p1: GeoCoordinate, _ p2: GeoCoordinate, _ q1: GeoCoordinate, _ q2: GeoCoordinate) -> Bool {
        let d1 = orientation(q1, q2, p1), d2 = orientation(q1, q2, p2)
        let d3 = orientation(p1, p2, q1), d4 = orientation(p1, p2, q2)
        if ((d1 > 0 && d2 < 0) || (d1 < 0 && d2 > 0)) && ((d3 > 0 && d4 < 0) || (d3 < 0 && d4 > 0)) { return true }
        if d1 == 0 && onSegment(q1, p1, q2) { return true }
        if d2 == 0 && onSegment(q1, p2, q2) { return true }
        if d3 == 0 && onSegment(p1, q1, p2) { return true }
        if d4 == 0 && onSegment(p1, q2, p2) { return true }
        return false
    }
}

// MARK: - GeoJSON / KML

nonisolated enum BoundaryFileError: LocalizedError, Sendable {
    case unreadable(String)
    case noPolygon
    case invalidBoundary(String)

    var errorDescription: String? {
        switch self {
        case .unreadable(let detail): return "The boundary file could not be read: \(detail)"
        case .noPolygon: return "No polygon was found. Export the boundary as a GeoJSON Polygon/MultiPolygon or a KML polygon (EPSG:4326)."
        case .invalidBoundary(let detail): return detail
        }
    }
}

nonisolated enum BoundaryFileCodec {
    /// Reads GeoJSON (Polygon, MultiPolygon, Feature, FeatureCollection). For several
    /// polygons the largest outer ring is used; holes are ignored.
    static func polygon(fromGeoJSON data: Data) throws -> BoundaryPolygon {
        let root: Any
        do { root = try JSONSerialization.jsonObject(with: data) }
        catch { throw BoundaryFileError.unreadable(error.localizedDescription) }
        guard let best = largestPolygon(inGeoJSONObject: root).polygon else { throw BoundaryFileError.noPolygon }
        if best.vertices.contains(where: { abs($0.latitude) > 90 || abs($0.longitude) > 180 }) {
            throw BoundaryFileError.invalidBoundary("Coordinates are outside latitude/longitude ranges — the file is probably in a projected CRS. Re-export it in EPSG:4326 (WGS84).")
        }
        return best
    }

    /// Largest outer ring in any GeoJSON object, and how many polygon parts it had.
    static func largestPolygon(inGeoJSONObject object: Any) -> (polygon: BoundaryPolygon?, partCount: Int) {
        let parts = outerRings(in: object).map(Self.boundary(fromRing:)).filter { $0.vertices.count >= 3 }
        let largest = parts.map { ($0, $0.areaSquareMetres()) }.max { $0.1 < $1.1 }?.0
        return (largest, parts.count)
    }

    private static func outerRings(in object: Any) -> [[Any]] {
        guard let dictionary = object as? [String: Any], let type = dictionary["type"] as? String else { return [] }
        switch type {
        case "FeatureCollection":
            return (dictionary["features"] as? [Any] ?? []).flatMap { outerRings(in: $0) }
        case "Feature":
            return dictionary["geometry"].map { outerRings(in: $0) } ?? []
        case "GeometryCollection":
            return (dictionary["geometries"] as? [Any] ?? []).flatMap { outerRings(in: $0) }
        case "Polygon":
            guard let rings = dictionary["coordinates"] as? [Any], let outer = rings.first as? [Any] else { return [] }
            return [outer]
        case "MultiPolygon":
            guard let polygons = dictionary["coordinates"] as? [Any] else { return [] }
            return polygons.compactMap { ($0 as? [Any])?.first as? [Any] }
        default:
            return []
        }
    }

    private static func boundary(fromRing ring: [Any]) -> BoundaryPolygon {
        var points: [GeoCoordinate] = ring.compactMap { item in
            guard let pair = item as? [Any], pair.count >= 2,
                  let lon = (pair[0] as? NSNumber)?.doubleValue,
                  let lat = (pair[1] as? NSNumber)?.doubleValue else { return nil }
            return GeoCoordinate(latitude: lat, longitude: lon)
        }
        if points.count > 1, points.first == points.last { points.removeLast() }
        return BoundaryPolygon(vertices: points)
    }

    /// Reads the first polygon's outer boundary from a KML file (Google Earth / My Maps).
    static func polygon(fromKML data: Data) throws -> BoundaryPolygon {
        guard let text = String(data: data, encoding: .utf8) else { throw BoundaryFileError.unreadable("not UTF-8 text") }
        var searchRange = text.startIndex..<text.endIndex
        if let outer = text.range(of: "<outerBoundaryIs", options: .caseInsensitive) {
            searchRange = outer.upperBound..<text.endIndex
        }
        guard let open = text.range(of: "<coordinates>", options: .caseInsensitive, range: searchRange),
              let close = text.range(of: "</coordinates>", options: .caseInsensitive, range: open.upperBound..<text.endIndex) else {
            throw BoundaryFileError.noPolygon
        }
        let tuples = text[open.upperBound..<close.lowerBound]
            .split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" || $0 == "\r" || $0 == "\r\n" })
        var points: [GeoCoordinate] = tuples.compactMap { tuple in
            let parts = tuple.split(separator: ",")
            guard parts.count >= 2, let lon = Double(parts[0]), let lat = Double(parts[1]) else { return nil }
            return GeoCoordinate(latitude: lat, longitude: lon)
        }
        if points.count > 1, points.first == points.last { points.removeLast() }
        guard points.count >= 3 else { throw BoundaryFileError.noPolygon }
        return BoundaryPolygon(vertices: points)
    }

    /// RFC 7946 Feature with a closed, counter-clockwise outer ring.
    static func geoJSON(_ polygon: BoundaryPolygon, properties: [String: Any]) throws -> Data {
        guard polygon.vertices.count >= 3 else { throw BoundaryFileError.invalidBoundary("Draw or import a boundary first.") }
        var ring = polygon.vertices
        if polygon.signedPlanarArea < 0 { ring.reverse() }
        var coordinates = ring.map { [$0.longitude, $0.latitude] }
        coordinates.append(coordinates[0])
        let feature: [String: Any] = [
            "type": "Feature",
            "properties": properties,
            "geometry": ["type": "Polygon", "coordinates": [coordinates]],
        ]
        return try JSONSerialization.data(withJSONObject: feature, options: [.prettyPrinted, .sortedKeys])
    }
}
