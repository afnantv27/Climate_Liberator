import XCTest
@testable import ClimateLiberator

/// Shared building blocks: quit prompt text, coordinates, document folders, periods.
@MainActor
final class PlatformFoundationTests: XCTestCase {

    func testQuitPromptNamesASingleItem() {
        let prompt = UnsavedWorkPrompt(groups: [(kind: "Clients", names: ["Acme Knit"]), (kind: "GHG inventories", names: [])])
        XCTAssertEqual(prompt.title, "Do you want to save “Acme Knit”?")
        XCTAssertEqual(prompt.saveButton, "Save")
    }

    func testQuitPromptGroupsSeveralItems() {
        let prompt = UnsavedWorkPrompt(groups: [(kind: "Clients", names: ["A", "B"]), (kind: "Reduction plans", names: ["A"])])
        XCTAssertEqual(prompt.saveButton, "Save All")
        XCTAssertTrue(prompt.detail.contains("Clients: A, B"))
        XCTAssertTrue(prompt.detail.contains("Reduction plans: A"))
    }

    func testCoordinateParsing() throws {
        let plain = try XCTUnwrap(CoordinateText.parse("11.1085, 77.3411"))
        XCTAssertEqual(plain.latitude, 11.1085, accuracy: 1e-9)
        XCTAssertEqual(plain.longitude, 77.3411, accuracy: 1e-9)
        let hemispheres = try XCTUnwrap(CoordinateText.parse("33.87°S 151.21°E"))
        XCTAssertEqual(hemispheres.latitude, -33.87, accuracy: 1e-9)
        XCTAssertNil(CoordinateText.parse("95, 10"), "Latitude out of range")
        XCTAssertNil(CoordinateText.parse("Tiruppur"))
        XCTAssertNil(CoordinateText.parse("11.1"))
    }

    func testDocumentFolderRoundTripAndTrash() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("DocFolder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let folder = JSONDocumentFolder<Client>(directory: directory)
        var client = Client(name: "Round Trip Knit")
        client.createdAt = Date(timeIntervalSince1970: 1_750_000_000)
        client.updatedAt = client.createdAt
        client.sites = [Site(name: "Plant")]
        try folder.write(client)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("broken.json"))
        let loaded = folder.loadAll()
        XCTAssertEqual(loaded.documents, [client])
        XCTAssertEqual(loaded.unreadable, ["broken.json"])
        try folder.trash(client.id)
        XCTAssertFalse(folder.exists(client.id))
    }

    func testOldClientFilesDecodeWithDefaults() throws {
        let json = Data(#"{"id": "2F1B7D3E-6E1A-4B8E-9B1C-6E0F3C2A1D11", "name": "Old Co"}"#.utf8)
        let client = try AppJSON.decoder().decode(Client.self, from: json)
        XCTAssertEqual(client.name, "Old Co")
        XCTAssertEqual(client.size, .small)
        XCTAssertTrue(client.sites.isEmpty)
    }

    func testFinancialYearOfADate() {
        let calendar = Calendar(identifier: .gregorian)
        XCTAssertEqual(ReportingPeriod.startYear(containing: calendar.date(from: DateComponents(year: 2026, month: 3, day: 31))!), 2025)
        XCTAssertEqual(ReportingPeriod.startYear(containing: calendar.date(from: DateComponents(year: 2026, month: 4, day: 1))!), 2026)
        XCTAssertEqual(ReportingPeriod.label(2025), "FY 2025-26")
    }
}
