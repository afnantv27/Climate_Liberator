import XCTest
import CoreLocation
@testable import ClimateLiberator

@MainActor
final class ForecastPortabilityTests: XCTestCase {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testDirectoryCacheAvoidsRepeatDecodeAndSeesAtomicReplacement() throws {
        let directory = try folder()
        let file = directory.appendingPathComponent("one.json")
        try Data("{\"value\":1}".utf8).write(to: file, options: .atomic)
        var reads = 0
        let cache = ForecastJSONDirectoryCache<Int>(directory: directory, readData: {
            reads += 1
            return try Data(contentsOf: $0)
        }, decode: { _, data in try JSONDecoder().decode([String: Int].self, from: data)["value"] ?? 0 })
        XCTAssertEqual(cache.load(), [1])
        XCTAssertEqual(cache.load(), [1])
        XCTAssertEqual(reads, 1)
        try Data("{\"value\":2}".utf8).write(to: file, options: .atomic)
        cache.invalidate()
        XCTAssertEqual(cache.load(), [2])
        XCTAssertEqual(reads, 2)
        try FileManager.default.removeItem(at: file)
        cache.invalidate()
        XCTAssertEqual(cache.load(), [])
    }

    func testOnlyNearbyCurrentNonsyntheticFeedIsEligible() throws {
        let directory = try folder()
        let now = ISO8601DateFormatter().date(from: "2026-09-08T12:00:00Z")!
        func write(_ id: String, latitude: Double, synthetic: Bool, validTo: String) throws {
            let data: [String: Any] = [
                "snapshot_id": id, "provider_id": "test", "provider_label": "Test provider",
                "location_label": "Bengaluru", "latitude": latitude, "longitude": 77.5946,
                "forecast_horizon": ForecastHorizon.shortTerm.rawValue, "synthetic": synthetic,
                "generated_at": "2026-09-08T00:00:00Z", "valid_from": "2026-09-08T00:00:00Z", "valid_to": validTo,
                "trust_summary": ["source_mode": "processedFeed", "official_status": "Derived", "confidence_label": "Medium", "note": "Test fixture"],
                "weather_metrics": [["id": "t", "title": "Temperature", "value": "25", "detail": "test"]], "air_quality_metrics": []
            ]
            try JSONSerialization.data(withJSONObject: data).write(to: directory.appendingPathComponent(id + ".json"), options: .atomic)
        }
        try write("far", latitude: 28.6, synthetic: false, validTo: "2026-09-09T00:00:00Z")
        try write("expired", latitude: 12.9716, synthetic: false, validTo: "2026-09-08T06:00:00Z")
        try write("sample", latitude: 12.9716, synthetic: true, validTo: "2026-09-09T00:00:00Z")
        let repository = BuildForecastFeedRepository(processedFeedsDirectory: directory, manifestsDirectory: directory.appendingPathComponent("manifests"), now: { now })
        let selected = CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)
        XCTAssertNil(repository.loadProcessedFeed(near: selected, horizon: .shortTerm))
        try write("current", latitude: 12.9717, synthetic: false, validTo: "2026-09-09T00:00:00Z")
        let refreshed = BuildForecastFeedRepository(processedFeedsDirectory: directory, manifestsDirectory: directory, now: { now })
        XCTAssertEqual(refreshed.loadProcessedFeed(near: selected, horizon: .shortTerm)?.snapshotID, "current")
        XCTAssertNil(refreshed.loadProcessedFeed(near: CLLocationCoordinate2D(latitude: 0, longitude: 0), horizon: .shortTerm))
    }
}
