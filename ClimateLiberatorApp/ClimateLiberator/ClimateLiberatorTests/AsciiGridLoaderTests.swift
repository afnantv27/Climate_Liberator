import XCTest
@testable import ClimateLiberator

@MainActor
final class AsciiGridLoaderTests: XCTestCase {

    private let fixture = """
    ncols 3
    nrows 2
    xllcorner 0
    yllcorner 0
    cellsize 1
    NODATA_value -9999
    1 2 -9999
    4 5 6
    """

    func testParsesDimensionsBoundsAndNodata() throws {
        let grid = try AsciiGridLoader.parse(fixture)
        XCTAssertEqual(grid.width, 3)
        XCTAssertEqual(grid.height, 2)
        XCTAssertEqual(grid.minLon, 0, accuracy: 1e-9)
        XCTAssertEqual(grid.maxLon, 3, accuracy: 1e-9)
        XCTAssertEqual(grid.minLat, 0, accuracy: 1e-9)
        XCTAssertEqual(grid.maxLat, 2, accuracy: 1e-9)
        XCTAssertEqual(grid.maxValue, 6, accuracy: 1e-9)
        // row-major, top row first: [1, 2, nil, 4, 5, 6]
        XCTAssertEqual(grid.values.count, 6)
        XCTAssertNil(grid.values[2])               // NODATA → nil
        XCTAssertEqual(grid.values[0], 1)
        XCTAssertEqual(grid.values[5], 6)
    }

    func testSamplingThroughHazardSurface() throws {
        let surface: HazardSurface = try AsciiGridLoader.parse(fixture)
        // top-left cell center (lon 0.5, lat 1.5) → value 1
        XCTAssertEqual(surface.intensity(latitude: 1.5, longitude: 0.5), 1)
        // bottom-right cell center (lon 2.5, lat 0.5) → value 6
        XCTAssertEqual(surface.intensity(latitude: 0.5, longitude: 2.5), 6)
    }

    func testMissingHeaderThrows() {
        XCTAssertThrowsError(try AsciiGridLoader.parse("nrows 2\n1 2\n3 4")) { error in
            XCTAssertEqual(error as? AsciiGridLoader.LoaderError, .missingHeaderKey("ncols"))
        }
    }

    func testHazardModelLoadsLatestROSGridFromFolder() async throws {
        // Lay out <tmp>/RateOfSpread/ROSFile1.asc and load it through the model.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rosDir = root.appendingPathComponent("RateOfSpread")
        try FileManager.default.createDirectory(at: rosDir, withIntermediateDirectories: true)
        try fixture.write(to: rosDir.appendingPathComponent("ROSFile1.asc"), atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: root) }

        let model = WildfireHazardModel.loadingLatestROSGrid()
        let surface = try await model.makeHazardSurface(
            HazardRequest(inputFolder: "/unused", outputFolder: root.path)
        )
        XCTAssertEqual(model.peril, .wildfire)
        XCTAssertEqual(surface.intensity(latitude: 0.5, longitude: 2.5), 6)
    }
}
