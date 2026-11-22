import XCTest
@testable import ClimateLiberator

/// Returns canned HTTP responses so connector code runs without a network.
private struct StubLoader: HTTPDataLoading {
    let status: Int
    let body: Data
    func load(_ request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
        return (body, response)
    }
}

@MainActor
final class GHGAccountingTests: XCTestCase {

    private func seed(_ externalID: String) throws -> EmissionFactor {
        try XCTUnwrap(EmissionFactorSeedLibrary.factors.first { $0.externalID == externalID })
    }

    // MARK: Units

    func testUnitResolution() {
        XCTAssertEqual(UnitRegistry.resolve("kWh")?.dimension, .energy)
        XCTAssertEqual(UnitRegistry.resolve("units")?.symbol, "kWh")       // Indian electricity bills
        XCTAssertEqual(UnitRegistry.resolve("litres")?.symbol, "L")
        XCTAssertEqual(UnitRegistry.resolve("tkm")?.symbol, "t·km")
        XCTAssertEqual(UnitRegistry.resolve("INR")?.currency, "INR")
        XCTAssertEqual(UnitRegistry.resolve("Mt")?.toBase, 1_000_000_000)
        XCTAssertNil(UnitRegistry.resolve("mt"), "MT is ambiguous (metric tonne vs megatonne)")
        XCTAssertNil(UnitRegistry.resolve("TON"))
        let mwh = UnitRegistry.resolve("MWh")!, kwh = UnitRegistry.resolve("kWh")!
        XCTAssertEqual(UnitRegistry.convert(2, from: mwh, to: kwh), 2_000)
        XCTAssertNil(UnitRegistry.convert(1, from: UnitRegistry.resolve("INR")!, to: UnitRegistry.resolve("USD")!))
    }

    func testFactorUnitExpressions() throws {
        let a = try XCTUnwrap(FactorUnitExpression.parse("kgCO2e/kWh"))
        XCTAssertEqual(a.numeratorToKg, 1); XCTAssertEqual(a.activityUnit.symbol, "kWh")
        let b = try XCTUnwrap(FactorUnitExpression.parse("tCO2/MWh"))
        XCTAssertEqual(b.numeratorToKg, 1_000); XCTAssertEqual(b.activityUnit.symbol, "MWh")
        let c = try XCTUnwrap(FactorUnitExpression.parse("kg CO2e per litre"))
        XCTAssertEqual(c.activityUnit.symbol, "L")
        let d = try XCTUnwrap(FactorUnitExpression.parse("g/km"))
        XCTAssertEqual(d.numeratorToKg, 0.001, accuracy: 1e-12)
        XCTAssertNil(FactorUnitExpression.parse("MT CO2e/MWh"))
    }

    // MARK: Calculator

    func testDieselLitresConvertThroughMassAndEnergy() throws {
        let diesel = try seed("ipcc2006-stationary-residential-diesel")
        // 10,000 L × 0.84 kg/L × 43.0 MJ/kg = 0.3612 TJ; CO2 74,100, CH4 10, N2O 0.6 kg/TJ.
        let ar6 = try EmissionCalculator.calculate(quantity: 10_000, unit: "L", factor: diesel, gwp: .ar6)
        XCTAssertEqual(ar6.quantityInFactorUnit, 0.3612, accuracy: 1e-9)
        XCTAssertEqual(ar6.gasesKg.co2, 26_764.92, accuracy: 1e-6)
        XCTAssertEqual(ar6.co2eKg, 26_921.60856, accuracy: 1e-5)
        XCTAssertEqual(try EmissionCalculator.calculate(quantity: 10_000, unit: "L", factor: diesel, gwp: .ar5).co2eKg,
                       26_923.4868, accuracy: 1e-5)
        XCTAssertEqual(try EmissionCalculator.calculate(quantity: 10_000, unit: "L", factor: diesel, gwp: .ar4).co2eKg,
                       26_919.80256, accuracy: 1e-5)
        XCTAssertFalse(ar6.steps.isEmpty)
    }

    func testGridElectricityAndBiogenicSeparation() throws {
        let grid = try seed("cea-v20-fy2024-weighted-average")
        XCTAssertEqual(try EmissionCalculator.calculate(quantity: 12.5, unit: "MWh", factor: grid, gwp: .ar6).co2eKg,
                       9_087.5, accuracy: 1e-9)

        let wood = try seed("ipcc2006-stationary-residential-wood")
        let result = try EmissionCalculator.calculate(quantity: 2, unit: "t", factor: wood, gwp: .ar6)
        XCTAssertEqual(result.co2eKg, 286.7904, accuracy: 1e-6)          // CH4 + N2O only
        XCTAssertEqual(result.biogenicCO2Kg, 3_494.4, accuracy: 1e-6)    // reported separately
    }

    func testConversionErrors() throws {
        let lpg = try seed("ipcc2006-stationary-residential-lpg")
        XCTAssertThrowsError(try EmissionCalculator.calculate(quantity: 10, unit: "L", factor: lpg, gwp: .ar6)) { error in
            XCTAssertEqual(error as? EmissionCalculationError, .missingDensity(lpg.name))
        }
        XCTAssertThrowsError(try EmissionCalculator.calculate(quantity: 10, unit: "km", factor: lpg, gwp: .ar6))
        XCTAssertThrowsError(try EmissionCalculator.calculate(quantity: 10, unit: "furlong", factor: lpg, gwp: .ar6))

        var spend = lpg
        spend.activityUnit = "USD"
        spend.gases = nil
        spend.co2ePerUnit = 0.4
        XCTAssertThrowsError(try EmissionCalculator.calculate(quantity: 10, unit: "INR", factor: spend, gwp: .ar6)) { error in
            XCTAssertEqual(error as? EmissionCalculationError, .currencyMismatch(activity: "INR", factor: "USD"))
        }
    }

    func testCO2eOnlyFactorWarnsWhenGWPDiffers() throws {
        var factor = try seed("cea-v20-fy2024-weighted-average")
        factor.gases = nil
        factor.co2ePerUnit = 0.5
        factor.co2eBasis = .ar5
        let result = try EmissionCalculator.calculate(quantity: 100, unit: "kWh", factor: factor, gwp: .ar6)
        XCTAssertEqual(result.co2eKg, 50, accuracy: 1e-9)
        XCTAssertFalse(result.warnings.isEmpty)
    }

    // MARK: Connectors

    func testCSVConnectorParsesQuotedFieldsAndScalesTonnes() throws {
        let csv = "\u{FEFF}name,unit,co2e,region,year\r\n\"Grid, southern region\",tCO2e/MWh,0.71,India,2024\r\nNo value,kg/kWh,,India,2024\r\nBad unit,kg/furlong,1,India,2024\r\n"
        let connector = EmissionFactorConnector(id: "web", name: "Web", kind: .csv, urlTemplate: "https://example.org/f.csv")
        let report = try EmissionFactorConnectorService.parseCSV(Data(csv.utf8), connector: connector, retrievedAt: Date())
        XCTAssertEqual(report.factors.count, 1)
        XCTAssertEqual(report.skipped, 2)
        let factor = try XCTUnwrap(report.factors.first)
        XCTAssertEqual(factor.name, "Grid, southern region")
        XCTAssertEqual(factor.activityUnit, "MWh")
        XCTAssertEqual(try XCTUnwrap(factor.co2ePerUnit), 710, accuracy: 1e-9)
        XCTAssertEqual(factor.year, 2024)
        XCTAssertEqual(try EmissionCalculator.calculate(quantity: 1_000, unit: "kWh", factor: factor, gwp: .ar6).co2eKg,
                       710, accuracy: 1e-9)
    }

    func testJSONConnectorWithAirtableMapping() throws {
        let json = #"{"records":[{"id":"rec1","fields":{"Name":"Grid","Unit":"kg/kWh","CO2e":0.7,"Region":"IN","Year":2024}},{"id":"rec2","fields":{"Name":"Empty"}}]}"#
        let connector = EmissionFactorConnector.make(.airtable)
        let report = try EmissionFactorConnectorService.parseJSON(Data(json.utf8), connector: connector, retrievedAt: Date())
        XCTAssertEqual(report.factors.map(\.externalID), ["rec1"])
        XCTAssertEqual(report.factors.first?.co2ePerUnit, 0.7)
        XCTAssertEqual(report.skipped, 1)
    }

    func testClimatiqParsingAndGWPRecalculation() throws {
        let json = #"""
        {"current_page":1,"last_page":1,"total_results":2,"results":[
         {"id":"abc","activity_id":"electricity-supply_grid","name":"Grid electricity","category":"Electricity","source":"CEA",
          "source_link":"https://cea.nic.in","year":2023,"region":"IN","region_name":"India","unit_type":"Energy","unit":"kg/kWh",
          "factor":0.71,"factor_calculation_method":"ar5",
          "constituent_gases":{"co2e_total":0.71,"co2e_other":null,"co2":0.7,"ch4":0.0001,"ch4_fossil":null,"ch4_biogenic":null,"n2o":0.00001}},
         {"id":"def","name":"Hidden value","unit":"kg/kWh","unit_type":"Energy","factor":null,
          "constituent_gases":{"co2e_total":null,"co2":null,"ch4":null,"n2o":null}}]}
        """#
        var connector = EmissionFactorConnector.make(.climatiq)
        connector.id = "cq"
        let report = try EmissionFactorConnectorService.parseClimatiq(Data(json.utf8), connector: connector, retrievedAt: Date())
        XCTAssertEqual(report.factors.count, 2)
        let grid = try XCTUnwrap(report.factors.first { $0.externalID == "abc" })
        XCTAssertEqual(grid.co2eBasis, .ar5)
        XCTAssertEqual(grid.metadata["unit_type"], "Energy")
        // AR5 matches the source total; AR6 is recomputed from gases: 0.7 + 0.0001×27 + 0.00001×273.
        XCTAssertEqual(try EmissionCalculator.calculate(quantity: 1, unit: "kWh", factor: grid, gwp: .ar5).co2eKg, 0.71, accuracy: 1e-12)
        XCTAssertEqual(try EmissionCalculator.calculate(quantity: 1, unit: "kWh", factor: grid, gwp: .ar6).co2eKg, 0.70543, accuracy: 1e-12)
        let hidden = try XCTUnwrap(report.factors.first { $0.externalID == "def" })
        XCTAssertFalse(hidden.hasValue)
        XCTAssertFalse(report.warnings.isEmpty)
        XCTAssertEqual(try EmissionFactorConnectorService.climatiqParameters(unitType: "Energy", quantity: 5,
                                                                             unit: UnitRegistry.resolve("MWh")!)["energy_unit"] as? String, "MWh")
    }

    func testRequestBuildingAndSecurityRules() throws {
        let service = EmissionFactorConnectorService(loader: StubLoader(status: 200, body: Data()))
        let climatiq = EmissionFactorConnector.make(.climatiq)
        XCTAssertThrowsError(try service.makeRequest(climatiq, secret: nil, query: "grid")) { error in
            XCTAssertEqual(error as? ConnectorError, .missingSecret)
        }
        let request = try service.makeRequest(climatiq, secret: "key", query: "grid India")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer key")
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        XCTAssertTrue(items.contains(URLQueryItem(name: "query", value: "grid India")))
        XCTAssertTrue(items.contains(URLQueryItem(name: "region", value: "IN")))

        var supabase = EmissionFactorConnector.make(.supabase)
        supabase.urlTemplate = "https://demo.supabase.co/rest/v1/factors?name=ilike.*{query}*"
        let supabaseRequest = try service.makeRequest(supabase, secret: "anon", query: "LPG & kerosene")
        XCTAssertEqual(supabaseRequest.value(forHTTPHeaderField: "apikey"), "anon")
        XCTAssertTrue(supabaseRequest.url!.absoluteString.contains("LPG%20%26%20kerosene"))

        var insecure = EmissionFactorConnector.make(.csv)
        insecure.urlTemplate = "http://example.org/f.csv"
        XCTAssertThrowsError(try service.makeRequest(insecure, secret: nil, query: "")) { error in
            XCTAssertEqual(error as? ConnectorError, .insecureURL)
        }
    }

    func testFetchUsesLoaderAndReportsHTTPErrors() async throws {
        var connector = EmissionFactorConnector.make(.csv)
        connector.urlTemplate = "https://example.org/f.csv"
        let ok = EmissionFactorConnectorService(loader: StubLoader(status: 200, body: Data("name,unit,co2e\nGrid,kg/kWh,0.7\n".utf8)))
        let report = try await ok.fetch(connector, secret: nil, query: "")
        XCTAssertEqual(report.factors.count, 1)

        let denied = EmissionFactorConnectorService(loader: StubLoader(status: 401, body: Data("unauthorised".utf8)))
        do {
            _ = try await denied.fetch(connector, secret: nil, query: "")
            XCTFail("Expected HTTP error")
        } catch let error as ConnectorError {
            XCTAssertEqual(error, .http(status: 401, detail: "unauthorised"))
        }
    }

    func testLibraryStoreSearchAndCompatibility() throws {
        let store = EmissionFactorLibraryStore(secrets: InMemorySecretStore(), loadFromDisk: false)
        let results = store.search("diesel residential")
        XCTAssertTrue(results.contains { $0.externalID == "ipcc2006-stationary-residential-diesel" })
        let diesel = try seed("ipcc2006-stationary-residential-diesel")
        let lpg = try seed("ipcc2006-stationary-residential-lpg")
        XCTAssertTrue(EmissionFactorLibraryStore.isCompatible(diesel, with: .volume))
        XCTAssertFalse(EmissionFactorLibraryStore.isCompatible(lpg, with: .volume))
        XCTAssertTrue(EmissionFactorLibraryStore.isCompatible(lpg, with: .mass))
        XCTAssertFalse(store.search("", dimension: .distance).contains { $0.externalID == "cea-v20-fy2024-weighted-average" })
    }

    // MARK: GPC

    private func direct(_ ref: String, _ tonnes: Double) -> GPCInventoryEntry {
        var entry = GPCInventoryEntry(referenceID: ref, label: ref)
        entry.method = .directCO2e
        entry.directCO2eTonnes = tonnes
        return entry
    }

    func testCatalogCoversEverySubSector() {
        XCTAssertEqual(Set(GPCCatalog.references.map(\.subSectorID)), Set(GPCCatalog.subSectors.map(\.id)))
        XCTAssertEqual(GPCCatalog.reference("I.4.4")?.isTerritorialOnly, true)
        XCTAssertEqual(GPCCatalog.reference("III.2.3")?.isTerritorialOnly, true)
        XCTAssertEqual(GPCCatalog.reference("III.1.2")?.scope, .three)
        XCTAssertEqual(GPCCatalog.reference("III.1.2")?.inBasic, true)
        XCTAssertEqual(GPCCatalog.reference("II.4.3")?.inBasic, false)
        XCTAssertEqual(GPCCatalog.reference("II.4.3")?.inBasicPlus, true)
        XCTAssertNil(GPCCatalog.reference("II.5.3"))
    }

    func testBasicBasicPlusAndTerritorialTotals() {
        var inventory = GPCInventory(cityName: "Testpur", inventoryYear: 2024)
        inventory.population = 105
        inventory.entries = [
            direct("I.1.2", 1_000),   // scope 2, BASIC
            direct("I.1.3", 100),     // T&D, BASIC+ only
            direct("I.4.4", 500),     // territorial only
            direct("III.1.2", 50),    // exported waste, scope 3, BASIC
            direct("III.1.3", 30),    // imported waste, territorial only
            direct("IV.1", 200),      // IPPU, BASIC+
            direct("VI.1", 10),       // other scope 3, separate
        ]
        var notation = GPCInventoryEntry(referenceID: "II.1.1", label: "On-road")
        notation.method = .notationKey
        notation.notationKey = .notEstimated
        inventory.entries.append(notation)

        let summary = GPCInventorySummary.make(inventory)
        XCTAssertEqual(summary.basicTotal, 1_050, accuracy: 1e-9)
        XCTAssertEqual(summary.basicPlusTotal, 1_350, accuracy: 1e-9)
        XCTAssertEqual(summary.territorialTotal, 730, accuracy: 1e-9)
        XCTAssertEqual(summary.scope2Total, 1_000, accuracy: 1e-9)
        XCTAssertEqual(summary.scope3Total, 150, accuracy: 1e-9)
        XCTAssertEqual(summary.otherScope3Total, 10, accuracy: 1e-9)
        XCTAssertEqual(summary.total(.waste, .one), 30, accuracy: 1e-9)
        XCTAssertEqual(try XCTUnwrap(summary.perCapitaBasic), 10, accuracy: 1e-9)

        let status = Dictionary(uniqueKeysWithValues: summary.completeness.map { ($0.id, $0.status) })
        XCTAssertEqual(status["II.1.1"], .notation(.notEstimated))
        XCTAssertEqual(status["I.1.2"], .reported)
        XCTAssertEqual(status["I.1.1"], .missing)
        XCTAssertNil(status["IV.1"], "IPPU is not required for BASIC")

        let csv = GPCReportExporter.summaryCSV(inventory, summary: summary)
        XCTAssertTrue(csv.contains("BASIC total (tCO2e),1050.000"))
        XCTAssertTrue(csv.contains("BASIC+ total (tCO2e),1350.000"))
    }

    func testEntryErrorsAreExcludedAndFlagged() {
        var inventory = GPCInventory(cityName: "Testpur", inventoryYear: 2024)
        inventory.entries = [GPCInventoryEntry(referenceID: "I.1.1", label: "No factor yet", activityQuantity: 10, activityUnit: "kg")]
        let summary = GPCInventorySummary.make(inventory)
        XCTAssertEqual(summary.basicTotal, 0)
        XCTAssertNotNil(summary.outcomes[inventory.entries[0].id]?.error)
        if case .error = summary.completeness.first(where: { $0.id == "I.1.1" })?.status {} else { XCTFail("Expected error status") }
    }

    func testWasteScopeAdvisor() {
        XCTAssertEqual(GPCScopeAdvisor.wasteReference(subSectorID: "III.1", generatedInCity: true, treatedInsideBoundary: true), "III.1.1")
        XCTAssertEqual(GPCScopeAdvisor.wasteReference(subSectorID: "III.1", generatedInCity: true, treatedInsideBoundary: false), "III.1.2")
        XCTAssertEqual(GPCScopeAdvisor.wasteReference(subSectorID: "III.4", generatedInCity: false, treatedInsideBoundary: true), "III.4.3")
        XCTAssertNil(GPCScopeAdvisor.wasteReference(subSectorID: "III.4", generatedInCity: false, treatedInsideBoundary: false))
    }

    func testIrittyExampleIsCompleteForBASIC() throws {
        let inventory = GPCExampleInventories.iritty()
        let summary = GPCInventorySummary.make(inventory)
        XCTAssertTrue(summary.outcomes.values.allSatisfy { $0.error == nil }, "Every example entry must calculate")
        XCTAssertEqual(summary.missingCount, 0, "Every BASIC source has a number or a notation key")
        // Cross-checked with an independent Python calculation of the same inputs.
        XCTAssertEqual(summary.basicTotal, 54_123.4, accuracy: 2)
        XCTAssertEqual(summary.total(.stationaryEnergy, .two), 22_736.9, accuracy: 1)
        XCTAssertEqual(try XCTUnwrap(summary.perCapitaBasic), 1.0345, accuracy: 0.001)
        // OSM Kerala outline (LSGI M13083): 192 points, ≈50.72 km² WGS84.
        XCTAssertEqual(inventory.boundary.vertices.count, 192)
        XCTAssertEqual(inventory.boundary.areaSquareKilometres, 50.72, accuracy: 0.05)
        XCTAssertEqual(inventory.boundaryType, .administrative)
        XCTAssertTrue(inventory.boundary.isValid)
        XCTAssertEqual(UnitRegistry.resolve("persons")?.dimension, .count)
    }

    func testLoadingExampleTwiceCreatesIndependentCopies() {
        let store = GPCInventoryStore(loadFromDisk: false)
        store.loadExample(GPCExampleInventories.iritty())
        store.loadExample(GPCExampleInventories.iritty())
        XCTAssertEqual(store.inventories.count, 2)
        XCTAssertNotEqual(store.inventories[0].id, store.inventories[1].id)
        XCTAssertNotEqual(store.inventories[0].entries.first?.id, store.inventories[1].entries.first?.id)
    }

    // MARK: Boundary

    private let square = BoundaryPolygon(vertices: [
        GeoCoordinate(latitude: 9.45, longitude: 77.55), GeoCoordinate(latitude: 9.45, longitude: 77.56),
        GeoCoordinate(latitude: 9.46, longitude: 77.56), GeoCoordinate(latitude: 9.46, longitude: 77.55),
    ])

    func testBoundaryMeasurementsAndContainment() {
        // WGS84 geodesic area from pyproj Geod.polygon_area_perimeter: 1.214624 km².
        XCTAssertEqual(square.areaSquareKilometres, 1.214624, accuracy: 0.00002)
        XCTAssertTrue(square.isValid)
        XCTAssertTrue(square.contains(GeoCoordinate(latitude: 9.455, longitude: 77.555)))
        XCTAssertFalse(square.contains(GeoCoordinate(latitude: 9.47, longitude: 77.555)))
        let equator = BoundaryPolygon(vertices: [
            GeoCoordinate(latitude: 0, longitude: 0), GeoCoordinate(latitude: 0, longitude: 0.1),
            GeoCoordinate(latitude: 0.1, longitude: 0.1), GeoCoordinate(latitude: 0.1, longitude: 0),
        ])
        XCTAssertEqual(equator.perimeterMetres(), 44_478.0, accuracy: 1)

        let bowTie = BoundaryPolygon(vertices: [
            GeoCoordinate(latitude: 0, longitude: 0), GeoCoordinate(latitude: 1, longitude: 1),
            GeoCoordinate(latitude: 0, longitude: 1), GeoCoordinate(latitude: 1, longitude: 0),
        ])
        XCTAssertTrue(bowTie.selfIntersects())
        XCTAssertFalse(bowTie.isValid)
    }

    func testGeoJSONRoundTripAndKML() throws {
        let clockwise = BoundaryPolygon(vertices: square.vertices.reversed())
        let data = try BoundaryFileCodec.geoJSON(clockwise, properties: ["name": "Test"])
        let object = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        let ring = try XCTUnwrap(((object["geometry"] as? [String: Any])?["coordinates"] as? [[[Double]]])?.first)
        XCTAssertEqual(ring.count, 5)
        XCTAssertEqual(ring.first, ring.last)
        XCTAssertGreaterThan(BoundaryPolygon(vertices: ring.dropLast().map { GeoCoordinate(latitude: $0[1], longitude: $0[0]) }).signedPlanarArea, 0)

        let parsed = try BoundaryFileCodec.polygon(fromGeoJSON: data)
        XCTAssertEqual(parsed.vertices.count, 4)
        XCTAssertEqual(parsed.areaSquareMetres(), square.areaSquareMetres(), accuracy: 1)

        let kml = """
        <kml><Placemark><Polygon><outerBoundaryIs><LinearRing><coordinates>
        77.55,9.45,0 77.56,9.45,0 77.56,9.46,0 77.55,9.46,0 77.55,9.45,0
        </coordinates></LinearRing></outerBoundaryIs></Polygon></Placemark></kml>
        """
        XCTAssertEqual(try BoundaryFileCodec.polygon(fromKML: Data(kml.utf8)).vertices.count, 4)

        let projected = #"{"type":"Polygon","coordinates":[[[500000,1000000],[501000,1000000],[501000,1001000],[500000,1000000]]]}"#
        XCTAssertThrowsError(try BoundaryFileCodec.polygon(fromGeoJSON: Data(projected.utf8)))
    }

    func testLargeBoundaryValidationAndArea() {
        // 2,000-point circle of radius ~5 km: valid, and the crossing check stays fast.
        let center = GeoCoordinate(latitude: 11.98, longitude: 75.65)
        let radiusDegrees = 0.045
        let circle = BoundaryPolygon(vertices: (0..<2_000).map { index in
            let angle = Double(index) / 2_000 * 2 * .pi
            return GeoCoordinate(latitude: center.latitude + radiusDegrees * sin(angle),
                                 longitude: center.longitude + radiusDegrees * cos(angle) / cos(center.latitude * .pi / 180))
        })
        XCTAssertFalse(circle.selfIntersects())
        XCTAssertTrue(circle.isValid)
        XCTAssertEqual(circle.areaSquareKilometres, 78.5, accuracy: 1.5)
        XCTAssertTrue(circle.contains(center))
    }

    // MARK: OpenStreetMap boundary lookup

    private let nominatimSample = """
    [
      {"place_id": 1, "osm_type": "node", "osm_id": 42, "lat": "11.98", "lon": "75.67",
       "category": "place", "type": "town", "addresstype": "town", "name": "Iritty",
       "display_name": "Iritty, Kannur, Kerala, India",
       "geojson": {"type": "Point", "coordinates": [75.67, 11.98]}},
      {"place_id": 2, "osm_type": "relation", "osm_id": 7, "lat": "9.455", "lon": "77.555",
       "category": "boundary", "type": "administrative", "addresstype": "municipality", "name": "Testpur",
       "display_name": "Testpur Municipality, Kerala, India",
       "geojson": {"type": "MultiPolygon", "coordinates": [
         [[[77.55, 9.45], [77.56, 9.45], [77.56, 9.46], [77.55, 9.46], [77.55, 9.45]]],
         [[[77.60, 9.45], [77.601, 9.45], [77.601, 9.451], [77.60, 9.45]]]
       ]}}
    ]
    """

    func testNominatimRequestFollowsUsagePolicy() throws {
        let request = try BoundaryLookupService().makeRequest(query: "  Iritty, Kerala ")
        let components = try XCTUnwrap(request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) })
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(components.host, "nominatim.openstreetmap.org")
        XCTAssertEqual(items["q"], "Iritty, Kerala")
        XCTAssertEqual(items["format"], "jsonv2")
        XCTAssertEqual(items["polygon_geojson"], "1")
        XCTAssertNotNil(items["polygon_threshold"])
        XCTAssertTrue(request.value(forHTTPHeaderField: "User-Agent")?.hasPrefix("ClimateLiberator") ?? false)
        XCTAssertThrowsError(try BoundaryLookupService().makeRequest(query: "   "))
    }

    func testNominatimParsingPrefersOutlinesAndLargestPart() throws {
        let results = try BoundaryLookupService.parse(Data(nominatimSample.utf8))
        XCTAssertEqual(results.count, 2)
        let municipality = results[0]
        XCTAssertEqual(municipality.id, "relation/7")
        XCTAssertEqual(municipality.kind, "municipality")
        XCTAssertTrue(municipality.isAdministrative)
        XCTAssertEqual(municipality.partCount, 2)
        XCTAssertEqual(municipality.boundary?.vertices.count, 4)
        XCTAssertEqual(try XCTUnwrap(municipality.boundary).areaSquareKilometres, 1.2146, accuracy: 0.001)
        XCTAssertTrue(municipality.sourceDescription.contains("OpenStreetMap contributors"))
        XCTAssertFalse(results[1].hasBoundary)
        XCTAssertEqual(results[1].center.latitude, 11.98, accuracy: 1e-9)
        XCTAssertThrowsError(try BoundaryLookupService.parse(Data("{}".utf8)))
    }

    func testNominatimSearchReportsRateLimit() async throws {
        let limited = BoundaryLookupService(loader: StubLoader(status: 429, body: Data()))
        do {
            _ = try await limited.search("Iritty")
            XCTFail("Expected HTTP 429")
        } catch let error as BoundaryLookupError {
            XCTAssertEqual(error, .http(429))
        }
        let ok = BoundaryLookupService(loader: StubLoader(status: 200, body: Data(nominatimSample.utf8)))
        let results = try await ok.search("Testpur")
        XCTAssertEqual(results.first?.osmID, 7)
    }

    func testApplyingPlaceBoundaryRecordsSourceAndType() throws {
        let store = GPCInventoryStore(loadFromDisk: false)
        store.createInventory(cityName: "", year: 2025)
        let place = try XCTUnwrap(try BoundaryLookupService.parse(Data(nominatimSample.utf8)).first)
        store.applyPlaceBoundary(place)
        let inventory = try XCTUnwrap(store.selected)
        XCTAssertEqual(inventory.boundary, place.boundary)
        XCTAssertEqual(inventory.boundaryType, .administrative)
        XCTAssertEqual(inventory.cityName, "Testpur")
        XCTAssertTrue(inventory.boundarySource.hasPrefix("OpenStreetMap relation 7"))
    }

    func testNothingIsSavedUntilTheUserSaves() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ghg-tests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let locations = GHGDataLocations(root: root)
        let store = GPCInventoryStore(locations: locations)
        let created = store.createInventory(cityName: "Iritty", year: 2025)
        store.loadExample(GPCExampleInventories.iritty())
        XCTAssertEqual(store.unsavedIDs.count, 2)
        XCTAssertTrue(GPCInventoryStore(locations: locations).inventories.isEmpty, "Nothing written before Save")

        store.selectedID = created.id
        store.mutateSelected { $0.region = "Kerala" }
        XCTAssertTrue(store.saveSelected())
        XCTAssertFalse(store.isUnsaved(created.id))
        XCTAssertTrue(store.hasUnsavedChanges, "The example is still unsaved")
        let reloaded = GPCInventoryStore(locations: locations)
        XCTAssertEqual(reloaded.inventories.map(\.id), [created.id])
        XCTAssertEqual(reloaded.selected?.region, "Kerala")

        // Editing marks it unsaved again; revert restores the saved copy.
        store.mutateSelected { $0.region = "Changed" }
        XCTAssertTrue(store.isUnsaved(created.id))
        store.revert(id: created.id)
        XCTAssertEqual(store.selected?.region, "Kerala")

        // A never-saved inventory is discarded, not trashed.
        let example = try XCTUnwrap(store.unsavedInventories.first)
        store.deleteInventory(id: example.id)
        XCTAssertFalse(store.hasUnsavedChanges)
    }

    // MARK: Reference library

    func testExpandedReferenceLibrary() throws {
        let factors = EmissionFactorSeedLibrary.factors
        XCTAssertEqual(factors.count, 120)
        XCTAssertEqual(Set(factors.map(\.id)).count, factors.count, "IDs must be unique")
        XCTAssertTrue(factors.allSatisfy { $0.hasValue && $0.unitDefinition != nil })

        let charcoal = try seed("ipcc2006-stationary-residential-charcoal")
        XCTAssertEqual(charcoal.gases?.co2Biogenic, 112_000)
        XCTAssertEqual(charcoal.gases?.ch4NonFossil, 200)
        XCTAssertEqual(charcoal.gases?.n2o, 1)
        XCTAssertEqual(try seed("ipcc2006-stationary-energyIndustries-coal-sub-bituminous").gases?.ch4NonFossil, 1)
        XCTAssertEqual(try seed("ipcc2006-stationary-agriculture-diesel").gases, try seed("ipcc2006-stationary-residential-diesel").gases)
        XCTAssertEqual(try seed("ipcc2006-offroad-diesel").gases?.n2o, 28.6)
        XCTAssertEqual(try seed("ipcc2006-aviation-jet-kerosene").gases?.co2, 71_500)
        XCTAssertEqual(try seed("ipcc2006-road-petrol").gases?.ch4NonFossil, 33)
        XCTAssertEqual(try XCTUnwrap(try seed("ipcc2006-wastewater-india-septic").gases?.ch4NonFossil), 3.723, accuracy: 1e-9)
        XCTAssertEqual(try seed("cea-v21-fy2025-weighted-average").gases?.co2, 0.710)

        // 1,000 L of off-road diesel: 0.84 t × 43 GJ/t = 36.12 GJ; CO2 = 36.12 × 74.1 kg/GJ.
        let result = try EmissionCalculator.calculate(quantity: 1_000, unit: "L", factor: try seed("ipcc2006-offroad-diesel"), gwp: .ar6)
        XCTAssertEqual(result.gasesKg.co2, 2_676.492, accuracy: 0.01)
    }

    func testFactorSearchIndexRefreshesWhenSourcesChange() throws {
        let store = EmissionFactorLibraryStore(secrets: InMemorySecretStore(), loadFromDisk: false)
        XCTAssertEqual(store.factorCount, EmissionFactorSeedLibrary.factors.count)
        XCTAssertNotNil(store.factor(id: "bundled:ipcc2006-offroad-diesel"))
        XCTAssertTrue(store.search("charcoal residential").contains { $0.externalID == "ipcc2006-stationary-residential-charcoal" })
        store.setEnabled(false, connectorID: EmissionFactorSeedLibrary.connectorID)
        XCTAssertEqual(store.factorCount, 0)
        XCTAssertTrue(store.search("diesel").isEmpty)
    }

    // MARK: Result presentation

    func testCalculationTrailIsReadable() throws {
        // 398.2 t LPG, commercial: 398,200 kg × 47.3 MJ/kg = 18.83486 TJ; 63,100 + 5 × 27 + 0.1 × 273 = 63,262.3 kg CO2e/TJ.
        let lpg = try seed("ipcc2006-stationary-commercial-lpg")
        let result = try EmissionCalculator.calculate(quantity: 398.2, unit: "t", factor: lpg, gwp: .ar6)
        XCTAssertEqual(result.trail.map(\.label), ["Activity", "Energy", "Emissions"])
        XCTAssertEqual(result.trail[1].value, 18.83486, accuracy: 1e-9)
        XCTAssertEqual(result.trail[1].unit, "TJ")
        XCTAssertEqual(result.perUnitCO2eKg, 63_262.3, accuracy: 1e-6)
        XCTAssertEqual(result.co2eKg, 1_191_536.563778, accuracy: 1e-3)
        XCTAssertEqual(result.gasesKg.ch4NonFossil, 94.1743, accuracy: 1e-6)
        XCTAssertFalse(result.steps.joined().contains("e+"), "No scientific notation in the trail")
        XCTAssertFalse(EmissionCalculator.format(18_834_860).contains("e"))
        XCTAssertEqual(GHGFormat.mass(94.1743), "94.17 kg")
        XCTAssertEqual(GHGFormat.mass(0.5), "500 g")

        let diesel = try seed("ipcc2006-stationary-residential-diesel")
        let litres = try EmissionCalculator.calculate(quantity: 10_000, unit: "L", factor: diesel, gwp: .ar6)
        XCTAssertEqual(litres.trail.map(\.label), ["Activity", "Mass", "Energy", "Emissions"])
        XCTAssertEqual(litres.trail[1].value, 8_400, accuracy: 1e-9)
        XCTAssertEqual(litres.trail[1].unit, "kg")
    }

    func testResultBreakdownsAddUpToTheTotal() throws {
        let inventory = GPCExampleInventories.iritty()
        let summary = GPCInventorySummary.make(inventory)
        let breakdown = GPCResultBreakdown.make(inventory, summary: summary, topCount: 100)
        XCTAssertEqual(breakdown.total, summary.basicTotal, accuracy: 1e-6)
        for slices in [breakdown.bySector, breakdown.byGas, breakdown.byQuality, breakdown.topSources] {
            XCTAssertEqual(slices.reduce(0) { $0 + $1.value }, summary.basicTotal, accuracy: 1e-6)
        }
        XCTAssertEqual(breakdown.waterfall.last?.isTotal, true)
        XCTAssertEqual(breakdown.waterfall.last?.end ?? 0, summary.basicTotal, accuracy: 1e-6)
        XCTAssertEqual(Set(breakdown.topSources.map(\.label)).count, breakdown.topSources.count, "Labels must be unique")
        XCTAssertEqual(breakdown.topSources.map(\.value), breakdown.topSources.map(\.value).sorted(by: >))
        XCTAssertGreaterThan(breakdown.lowQualityShare, 0)
        XCTAssertLessThanOrEqual(breakdown.lowQualityShare, 1)
    }

    func testLegacyIrittyBoundaryIsUpgraded() {
        var legacy = GPCExampleInventories.iritty()
        legacy.boundary = BoundaryPolygon(vertices: Array(GPCExampleInventories.irittyBoundary.vertices.prefix(8)))
        legacy.boundarySource = "APPROXIMATE demonstration outline (area matched to the official 45.84 km²). Replace with Iritty Municipality's ward map before use."
        XCTAssertTrue(GPCExampleInventories.upgradeLegacyIrittyBoundary(&legacy))
        XCTAssertEqual(legacy.boundary.vertices.count, 192)
        XCTAssertFalse(GPCExampleInventories.upgradeLegacyIrittyBoundary(&legacy), "Runs only once")
    }

    // MARK: Decarbonisation scenarios

    private func syntheticBaseline() -> ScenarioBaseline {
        ScenarioBaseline(
            baseYear: 2025, gwp: .ar6,
            lines: [
                ScenarioLine(id: "petrol", label: "Petrol", sourceKey: "II.1.1", groupKey: "II", carriers: [.petrol],
                             isGridElectricity: false, gases: GasAmounts(co2: 100), energyKWh: 400_000, massTonnes: nil),
                ScenarioLine(id: "grid", label: "Homes", sourceKey: "I.1.2", groupKey: "I", carriers: [.gridElectricity],
                             isGridElectricity: true, gases: GasAmounts(co2: 70), energyKWh: 100_000, massTonnes: nil),
                ScenarioLine(id: "lpg", label: "LPG", sourceKey: "I.1.1", groupKey: "I", carriers: [.lpg],
                             isGridElectricity: false, gases: GasAmounts(co2: 50), energyKWh: 200_000, massTonnes: nil),
                ScenarioLine(id: "septic", label: "Septic", sourceKey: "III.4.1", groupKey: "III", carriers: [],
                             isGridElectricity: false, gases: GasAmounts(ch4NonFossil: 2), energyKWh: nil, massTonnes: nil),
            ],
            gridFactorKgPerKWh: 0.7, groupTitles: [:],
            electricitySourceKey: { GPCScenarioBaselineAdapter.electricityKey($0) })
    }

    private func testMeasure(_ id: String, _ targets: SourceSelector, _ effect: MeasureEffect) -> DecarbonizationMeasure {
        DecarbonizationMeasure(id: id, title: id, category: .buildings, summary: "", bestFor: "", adoptionMeaning: "",
                               defaultAdoption: 1, targets: targets, parameters: [], effect: { _ in effect })
    }

    func testScenarioEngineOrdersAndCompoundsMeasures() throws {
        let baseline = syntheticBaseline()
        XCTAssertEqual(baseline.totalTonnes, 274, accuracy: 1e-9) // 100 + 70 + 50 + 2 × 27
        let petrol = SourceSelector(keyPrefixes: ["II.1"], carriers: [.petrol])
        let measures: [DecarbonizationMeasure] = [
            // Listed out of order on purpose: the engine sorts by stage.
            testMeasure("grid", SourceSelector(gridElectricity: true), .gridEmissionFactorPath([YearValue(year: 2030, value: 0.35)])),
            testMeasure("solar", SourceSelector(keyPrefixes: ["I.1"], gridElectricity: true), .replaceGridSupply),
            testMeasure("ev", petrol, .switchToGridElectricity(kWhPerKWhReplaced: 0.2)),
            testMeasure("efficiency", petrol, .reduceActivity(fraction: 0.2)),
            testMeasure("methane", SourceSelector(keyPrefixes: ["III.4"]), .reduceMethane(fraction: 1)),
        ]
        let adoption = ["grid": 1.0, "solar": 0.5, "ev": 0.5, "efficiency": 1.0, "methane": 0.5]
        let catalog = Dictionary(uniqueKeysWithValues: measures.map { ($0.id, $0) })
        let scenario = DecarbonizationScenario(name: "Test", targetYear: 2030, measures: measures.map {
            ScenarioMeasureSelection(measureID: $0.id, adoption: adoption[$0.id] ?? 0, startYear: 2030, fullYear: 2030)
        })
        let projection = DecarbonizationEngine.project(baseline, scenario: scenario, catalog: { catalog[$0] })
        let target = try XCTUnwrap(projection.target)
        XCTAssertEqual(target.year, 2030)
        XCTAssertEqual(target.bauTonnes, 274, accuracy: 1e-9)
        // Efficiency 100 → 80; EV switches half (40 t, 160,000 kWh → 32,000 kWh of new load at
        // the 2030 grid factor 0.35 = 11.2 t); methane 54 → 27; solar halves homes 70 → 35;
        // grid 0.7 → 0.35 halves the existing grid line 35 → 17.5 (new load is already priced at 0.35).
        XCTAssertEqual(target.wedge("efficiency"), 20, accuracy: 1e-9)
        XCTAssertEqual(target.wedge("ev"), 28.8, accuracy: 1e-9)
        XCTAssertEqual(target.wedge("methane"), 27, accuracy: 1e-9)
        XCTAssertEqual(target.wedge("solar"), 35, accuracy: 1e-9)
        XCTAssertEqual(target.wedge("grid"), 17.5, accuracy: 1e-9)
        XCTAssertEqual(target.scenarioTonnes, 145.7, accuracy: 1e-9)
        XCTAssertEqual(target.wedges.map(\.measureID), ["efficiency", "ev", "methane", "solar", "grid"])
        XCTAssertEqual(target.bauTonnes - target.scenarioTonnes, target.wedges.reduce(0) { $0 + $1.tonnes }, accuracy: 1e-9)
        // Nothing happens before the start year.
        XCTAssertEqual(projection.year(2029)?.scenarioTonnes ?? 0, 274, accuracy: 1e-9)
    }

    func testRolloutAndGridPathInterpolate() {
        let selection = ScenarioMeasureSelection(measureID: "x", adoption: 0.5, startYear: 2026, fullYear: 2030)
        XCTAssertEqual(selection.adoption(in: 2025), 0)
        XCTAssertEqual(selection.adoption(in: 2026), 0.1, accuracy: 1e-12)
        XCTAssertEqual(selection.adoption(in: 2028), 0.3, accuracy: 1e-12)
        XCTAssertEqual(selection.adoption(in: 2035), 0.5)
        let base = YearValue(year: 2025, value: 0.7)
        let path = [YearValue(year: 2030, value: 0.35)]
        XCTAssertEqual(DecarbonizationEngine.gridFactor(in: 2027, base: base, path: path), 0.56, accuracy: 1e-12)
        XCTAssertEqual(DecarbonizationEngine.gridFactor(in: 2040, base: base, path: path), 0.35, accuracy: 1e-12)
    }

    func testMeasureCatalogIsConsistent() {
        let measures = DecarbonizationMeasureCatalog.measures
        XCTAssertGreaterThanOrEqual(measures.count, 25)
        XCTAssertEqual(Set(measures.map(\.id)).count, measures.count)
        for measure in measures {
            for id in measure.sourceIDs { XCTAssertNotNil(DecarbonizationMeasureCatalog.source(id), "\(measure.id): \(id)") }
            for parameter in measure.parameters where !parameter.requiresInput {
                XCTAssertGreaterThanOrEqual(parameter.typical, min(parameter.low, parameter.high), "\(measure.id).\(parameter.id)")
                XCTAssertLessThanOrEqual(parameter.typical, max(parameter.low, parameter.high), "\(measure.id).\(parameter.id)")
                XCTAssertTrue(parameter.isAssumption || parameter.requiresInput || !parameter.sourceIDs.isEmpty,
                              "\(measure.id).\(parameter.id) needs a source or an assumption flag")
            }
            XCTAssertTrue((0...1).contains(measure.defaultAdoption))
        }
        // Library factors used by fuel switches and waste diversion exist.
        for id in ["ipcc2006-composting-wet", "ipcc2006-anaerobic-digestion-wet",
                   "ipcc2006-stationary-residential-biogas", "ipcc2006-stationary-manufacturing-natural-gas"] {
            XCTAssertNotNil(DecarbonizationEngine.libraryFactors(id), id)
        }
        // E20 → E27: ethanol energy share 13.9% → 19.3%, so fossil CO2 falls 6.2%.
        XCTAssertEqual(DecarbonizationMeasureCatalog.ethanolEnergyShare(volumeShare: 0.2), 0.138947, accuracy: 1e-5)
        if case .reduceFossilCO2(let fraction) = DecarbonizationMeasureCatalog.measure("ethanol-blending")!.effect(DecarbonizationMeasureCatalog.measure("ethanol-blending")!.values()) {
            XCTAssertEqual(fraction, 0.062458, accuracy: 1e-5)
        } else { XCTFail("Unexpected effect") }
    }

    func testIrittyStarterPathway() throws {
        let inventory = GPCExampleInventories.iritty()
        let summary = GPCInventorySummary.make(inventory)
        let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: summary)
        XCTAssertEqual(baseline.totalTonnes, summary.basicTotal, accuracy: 1e-6)
        XCTAssertEqual(baseline.gridFactorKgPerKWh, 0.727, accuracy: 1e-6)
        XCTAssertTrue(baseline.lines.contains { $0.carriers.contains(.lpg) && ($0.energyKWh ?? 0) > 0 })

        // LPG → induction at 100%: LPG emissions minus electricity for 68/84 of the LPG energy.
        let induction = try XCTUnwrap(DecarbonizationMeasureCatalog.measure("lpg-to-induction"))
        let lpg = baseline.lines.filter(induction.targets.matches)
        XCTAssertEqual(lpg.count, 2) // household and commercial LPG
        let grid = baseline.gridFactorKgPerKWh
        let expected = lpg.reduce(0) { $0 + $1.co2eTonnes(.ar6) - ($1.energyKWh ?? 0) * 0.68 / 0.84 * grid / 1_000 }
        let potential = DecarbonizationEngine.potential(of: induction, baseline: baseline, adoption: 1, year: 2035)
        XCTAssertEqual(potential.typicalTonnes, expected, accuracy: 1e-6)
        // LPG emits ~0.23 kg CO2/kWh; replacing it needs 0.81 kWh × 0.727 ≈ 0.59 kg — a net increase today.
        XCTAssertLessThan(potential.typicalTonnes, 0)

        let scenario = DecarbonizationScenario.starter(for: baseline)
        XCTAssertTrue(scenario.measures.contains { $0.measureID == "grid-decarbonisation" })
        XCTAssertFalse(scenario.measures.contains { $0.measureID == "solar-water-heaters" }, "Needs local input")
        // At 0.43 kg/kWh (2032) induction still needs 0.81 × 0.43 ≈ 0.35 kg per kWh of LPG (0.23 kg) — left out;
        // e-buses need 0.46 × 0.43 ≈ 0.20 kg per kWh of diesel (0.27 kg) — included.
        XCTAssertFalse(scenario.measures.contains { $0.measureID == "lpg-to-induction" }, "Adds emissions even on the 2035 grid")
        XCTAssertTrue(scenario.measures.contains { $0.measureID == "electric-buses" }, "Cuts emissions on the 2035 grid")
        let projection = DecarbonizationEngine.project(baseline, scenario: scenario)
        let target = try XCTUnwrap(projection.target)
        XCTAssertEqual(target.year, inventory.inventoryYear + 10)
        XCTAssertLessThan(target.scenarioTonnes, target.bauTonnes)
        let emissionWedges = target.wedges.reduce(0) { $0 + $1.tonnes } - target.removalsTonnes
        XCTAssertEqual(target.bauTonnes - target.scenarioTonnes, emissionWedges, accuracy: 1e-6)
    }

    func testScenariosSurviveSaveAndOldFilesStillLoad() throws {
        var inventory = GPCExampleInventories.iritty()
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()
        let old = try encoder.encode(inventory)
        XCTAssertFalse(String(decoding: old, as: UTF8.self).contains("\"scenarios\""))
        XCTAssertTrue(try decoder.decode(GPCInventory.self, from: old).decarbonizationScenarios.isEmpty)

        inventory.decarbonizationScenarios = [DecarbonizationScenario(name: "A", targetYear: 2035, measures: [
            ScenarioMeasureSelection(measureID: "rooftop-solar", adoption: 0.2, startYear: 2026, fullYear: 2035,
                                     parameterOverrides: ["x": 1]),
        ])]
        let reloaded = try decoder.decode(GPCInventory.self, from: encoder.encode(inventory))
        XCTAssertEqual(reloaded.decarbonizationScenarios, inventory.decarbonizationScenarios)
    }

    // MARK: Action plan

    func testCostPerTonneAnnualisesCapital() throws {
        XCTAssertEqual(ActionPlanAnalysis.capitalRecoveryFactor(rate: 0.08, years: 10), 0.1490295, accuracy: 1e-6)
        XCTAssertEqual(ActionPlanAnalysis.capitalRecoveryFactor(rate: 0, years: 20), 0.05, accuracy: 1e-12)

        var plan = ActionPlanItem()
        plan.capitalCost = 1_000_000
        plan.lifetimeYears = 10
        plan.annualOperatingCost = 20_000
        plan.annualSavings = 50_000
        var selection = ScenarioMeasureSelection(measureID: "rooftop-solar", adoption: 0.2, startYear: 2026, fullYear: 2035)
        selection.plan = plan
        let economics = ActionPlanAnalysis.economics(of: selection, abatementTonnes: 100, discountRate: 0.08)
        // 1,000,000 × 0.1490295 + 20,000 − 50,000 = 119,029.5 a year → 1,190.3 per tonne.
        XCTAssertEqual(try XCTUnwrap(economics.costPerTonne), 1_190.295, accuracy: 0.01)

        plan.lifetimeYears = nil
        selection.plan = plan
        XCTAssertNil(ActionPlanAnalysis.economics(of: selection, abatementTonnes: 100, discountRate: 0.08).costPerTonne,
                     "A capital cost needs a lifetime")
        var savingsOnly = ActionPlanItem()
        savingsOnly.annualSavings = 10_000
        selection.plan = savingsOnly
        XCTAssertEqual(try XCTUnwrap(ActionPlanAnalysis.economics(of: selection, abatementTonnes: 50, discountRate: 0.08).costPerTonne),
                       -200, accuracy: 1e-9)
        XCTAssertNil(ActionPlanAnalysis.economics(of: selection, abatementTonnes: -5, discountRate: 0.08).costPerTonne,
                     "No cost per tonne when a measure adds emissions")
    }

    func testMACCurveOrdersCheapestFirst() {
        let curve = ActionPlanAnalysis.macCurve([
            MeasureEconomics(measureID: "a", abatementTonnes: 100, annualisedCost: 50_000, capitalCost: nil),
            MeasureEconomics(measureID: "b", abatementTonnes: 40, annualisedCost: -8_000, capitalCost: nil),
            MeasureEconomics(measureID: "c", abatementTonnes: 10, annualisedCost: nil, capitalCost: nil),
        ])
        XCTAssertEqual(curve.map(\.measureID), ["b", "a"])
        XCTAssertEqual(curve[0].costPerTonne, -200, accuracy: 1e-9)
        XCTAssertEqual(curve[1].startTonnes, 40, accuracy: 1e-9)
        XCTAssertEqual(curve[1].endTonnes, 140, accuracy: 1e-9)
    }

    func testGoalTypesAndResidualEmissions() {
        var scenario = DecarbonizationScenario(name: "Goal", targetYear: 2035)
        scenario.reductionTarget = 0.3
        XCTAssertEqual(scenario.goalTonnes(baseTonnes: 100, bauTonnes: 120) ?? 0, 70, accuracy: 1e-9, "nil type = base year")
        scenario.goalType = .baselineScenario
        XCTAssertEqual(scenario.goalTonnes(baseTonnes: 100, bauTonnes: 120) ?? 0, 84, accuracy: 1e-9)
        scenario.goalType = .fixedLevel
        XCTAssertNil(scenario.goalTonnes(baseTonnes: 100, bauTonnes: 120))
        scenario.goalLevelTonnes = 0
        XCTAssertEqual(scenario.goalLabel(baseYear: 2025), "Net zero")

        var settings = ActionPlanSettings()
        settings.plannedCreditsTonnes = 30
        settings.creditCapShare = 0.1
        scenario.planSettings = settings
        let result = ScenarioYearResult(year: 2035, bauTonnes: 120, scenarioTonnes: 200, removalsTonnes: 20, wedges: [])
        let residual = ActionPlanAnalysis.residualEmissions(of: scenario, result: result)
        XCTAssertEqual(residual.netOfRemovals, 180, accuracy: 1e-9)
        XCTAssertEqual(residual.netWithCredits, 150, accuracy: 1e-9)
        XCTAssertTrue(residual.exceedsCap, "30 t of credits is above 10% of 200 t")
    }

    func testActionPlanSurvivesSaveAndOldScenariosStillLoad() throws {
        // A scenario saved before goal types and action plans existed.
        let old = """
        {"id":"\(UUID().uuidString)","name":"Old","targetYear":2035,"annualGrowth":{},"reductionTarget":0.45,
         "measures":[{"measureID":"rooftop-solar","adoption":0.15,"startYear":2026,"fullYear":2035,"parameterOverrides":{}}]}
        """
        let decoded = try JSONDecoder().decode(DecarbonizationScenario.self, from: Data(old.utf8))
        XCTAssertNil(decoded.measures.first?.plan)
        XCTAssertEqual(decoded.goalKind, .baseYear)
        XCTAssertEqual(decoded.settings.discountRate, 0.08, accuracy: 1e-12)
        XCTAssertEqual(try JSONDecoder().decode(ActionPlanItem.self, from: Data("{}".utf8)), ActionPlanItem())

        var scenario = decoded
        var plan = ActionPlanItem()
        plan.owner = "Municipal engineering wing"
        plan.status = .approved
        plan.coBenefits = [.jobs, .savings]
        plan.funding = .centralScheme
        plan.fundingNote = "PM Surya Ghar"
        scenario.measures[0].plan = plan
        scenario.goalType = .fixedLevel
        scenario.goalLevelTonnes = 0
        let reloaded = try JSONDecoder().decode(DecarbonizationScenario.self, from: JSONEncoder().encode(scenario))
        XCTAssertEqual(reloaded, scenario)
    }

    func testActionPlanSuggestionsCoverTheCatalog() {
        for measure in DecarbonizationMeasureCatalog.measures {
            let suggestion = ActionPlanCatalog.suggestion(for: measure.id)
            XCTAssertFalse(suggestion.coBenefits.isEmpty, "\(measure.id) has no suggested co-benefits")
            for id in suggestion.schemeIDs { XCTAssertNotNil(ActionPlanCatalog.scheme(id), "\(measure.id): \(id)") }
        }
    }

    func testIrittyExamplePlan() throws {
        let inventory = GPCExamplePathways.irittyWithPathway()
        let scenario = try XCTUnwrap(inventory.decarbonizationScenarios.first)
        XCTAssertEqual(scenario.measures.count, 15)
        XCTAssertTrue(scenario.measures.allSatisfy { !($0.plan?.owner ?? "").isEmpty }, "Every example measure has an owner")

        let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: GPCInventorySummary.make(inventory))
        let projection = DecarbonizationEngine.project(baseline, scenario: scenario)
        let target = try XCTUnwrap(projection.target)
        XCTAssertGreaterThan(target.bauTonnes, projection.baseTonnes, "Activity grows with population")
        XCTAssertLessThan(target.netTonnes, projection.baseTonnes)
        XCTAssertEqual(target.removalsTonnes, 10_000 * 0.8 * 0.0075 * 44 / 12, accuracy: 1e-6)

        let summary = ActionPlanAnalysis.summary(of: scenario, result: target)
        let solar = try XCTUnwrap(summary.economics.first { $0.measureID == "rooftop-solar" })
        XCTAssertLessThan(try XCTUnwrap(solar.costPerTonne), 0, "Solar saves more than it costs at ₹7.17/kWh")
        XCTAssertEqual(summary.ownersAssigned, scenario.measures.count)
        XCTAssertEqual(ActionPlanAnalysis.macCurve(summary.economics).count, 1, "Only rooftop solar is costed")
    }

    func testMeasuresOffTheCostCurveSayWhy() throws {
        let inventory = GPCExamplePathways.irittyWithPathway()
        var scenario = try XCTUnwrap(inventory.decarbonizationScenarios.first)
        let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: GPCInventorySummary.make(inventory))
        func summary() -> ActionPlanSummary {
            ActionPlanAnalysis.summary(of: scenario, result: DecarbonizationEngine.project(baseline, scenario: scenario).target)
        }
        let index = try XCTUnwrap(scenario.measures.firstIndex { $0.measureID == "ecbc-buildings" })
        let original = scenario.measures[index]
        var plan = original.plan ?? ActionPlanItem()
        plan.capitalCost = 5_000_000
        plan.lifetimeYears = 20
        plan.annualSavings = 300_000
        scenario.measures[index].plan = plan

        // Costed, but 0% adoption: no cut, so no cost per tonne, and the plan says why.
        scenario.measures[index].adoption = 0
        let off = summary()
        XCTAssertEqual(off.gaps["ecbc-buildings"], .noAdoption)
        XCTAssertEqual(off.notCharted, ["ecbc-buildings"])
        XCTAssertFalse(ActionPlanAnalysis.macCurve(off.economics).contains { $0.measureID == "ecbc-buildings" })
        XCTAssertEqual(off.gaps["waste-reduction"], .noCosts)
        XCTAssertFalse(off.notCharted.contains("waste-reduction"), "Uncosted measures are not reported as missing")

        scenario.measures[index].adoption = original.adoption
        let on = summary()
        XCTAssertNil(on.gaps["ecbc-buildings"])
        XCTAssertTrue(on.notCharted.isEmpty)
        XCTAssertEqual(Set(ActionPlanAnalysis.macCurve(on.economics).map(\.measureID)), ["ecbc-buildings", "rooftop-solar"])

        scenario.measures[index].startYear = scenario.targetYear + 1
        scenario.measures[index].fullYear = scenario.targetYear + 1
        XCTAssertEqual(summary().gaps["ecbc-buildings"], .startsAfterTarget)

        scenario.measures[index].startYear = original.startYear
        scenario.measures[index].fullYear = original.fullYear
        plan.lifetimeYears = nil
        scenario.measures[index].plan = plan
        XCTAssertEqual(summary().gaps["ecbc-buildings"], .needsLifetime)
    }

    func testPlanChecksFlagGapsAndStatusClashes() throws {
        let inventory = GPCExamplePathways.irittyWithPathway()
        var scenario = try XCTUnwrap(inventory.decarbonizationScenarios.first)
        let baseline = GPCScenarioBaselineAdapter.baseline(for: inventory, summary: GPCInventorySummary.make(inventory))
        let thisYear = inventory.inventoryYear + 1
        func issues() -> [PlanIssue] {
            let summary = ActionPlanAnalysis.summary(of: scenario, result: DecarbonizationEngine.project(baseline, scenario: scenario).target)
            return ActionPlanAnalysis.issues(of: scenario, summary: summary, currentYear: thisYear)
        }
        XCTAssertTrue(issues().filter { !$0.affectsFigures }.isEmpty, "Every example measure has an owner, funding and a consistent status")
        XCTAssertFalse(issues().contains { $0.kind == .cost(.noAdoption) })

        let index = try XCTUnwrap(scenario.measures.firstIndex { $0.measureID == "ecbc-buildings" })
        scenario.measures[index].adoption = 0
        scenario.measures[index].plan?.status = .underway
        scenario.measures[index].plan?.owner = " "
        let start = scenario.measures[index].startYear
        XCTAssertGreaterThan(start, thisYear)
        XCTAssertEqual(issues().filter { $0.measureID == "ecbc-buildings" }.map(\.kind),
                       [.cost(.noAdoption), .noOwner, .startedBeforeRollout(startYear: start)])
        XCTAssertTrue(try XCTUnwrap(issues().first).affectsFigures, "Issues that change the figures come first")

        scenario.measures[index].adoption = 0.2
        scenario.measures[index].startYear = inventory.inventoryYear
        scenario.measures[index].plan?.status = .completed
        XCTAssertTrue(issues().contains { $0.kind == .completedBeforeRollout(fullYear: scenario.measures[index].fullYear) })
    }

    func testCutFormatHasNoNegativeZero() {
        XCTAssertEqual(DecarbonizationFormat.cut(0), "0 t")
        XCTAssertEqual(DecarbonizationFormat.cut(12), "−12 t")
        XCTAssertEqual(DecarbonizationFormat.cut(-4.5), "+4.5 t")
    }
}
