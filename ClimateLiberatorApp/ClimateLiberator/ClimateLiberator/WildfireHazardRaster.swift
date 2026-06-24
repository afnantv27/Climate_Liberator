import Foundation

/// Loads an ESRI ASCII grid (`.asc`) — the format Cell2Fire writes for ROS and
/// other outputs — into an `IndiaWildfireRiskGrid`, which is a `HazardSurface`.
///
/// Coordinates are read from the `.asc` header as-is. This is exact for rasters
/// already in lon/lat; Cell2Fire output in a projected CRS must be reprojected to
/// lon/lat first (the app's overlay pipeline does this). Keeping the parsing here,
/// isolated from `ContentView`, makes it reusable and unit-testable.
enum AsciiGridLoader {
    enum LoaderError: Error, Equatable {
        case unreadable
        case missingHeaderKey(String)
        case malformedRow(Int)
        case sizeMismatch(expected: Int, found: Int)
    }

    static func loadGrid(at url: URL) throws -> IndiaWildfireRiskGrid {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw LoaderError.unreadable
        }
        return try parse(text)
    }

    static func parse(_ text: String) throws -> IndiaWildfireRiskGrid {
        var ncols = 0, nrows = 0
        var xll = 0.0, yll = 0.0
        var xCenter = false, yCenter = false
        var cellsize = 1.0
        var nodata = -9999.0
        var haveNcols = false, haveNrows = false, haveCellsize = false
        var dataRows: [[Double?]] = []

        for rawLine in text.split(whereSeparator: \.isNewline) {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split { $0 == " " || $0 == "\t" }.map(String.init)
            let key = parts[0].lowercased()

            switch key {
            case "ncols" where parts.count >= 2:    ncols = Int(Double(parts[1]) ?? 0); haveNcols = true
            case "nrows" where parts.count >= 2:    nrows = Int(Double(parts[1]) ?? 0); haveNrows = true
            case "xllcorner" where parts.count >= 2: xll = Double(parts[1]) ?? 0; xCenter = false
            case "xllcenter" where parts.count >= 2: xll = Double(parts[1]) ?? 0; xCenter = true
            case "yllcorner" where parts.count >= 2: yll = Double(parts[1]) ?? 0; yCenter = false
            case "yllcenter" where parts.count >= 2: yll = Double(parts[1]) ?? 0; yCenter = true
            case "cellsize" where parts.count >= 2: cellsize = Double(parts[1]) ?? 1; haveCellsize = true
            case "nodata_value" where parts.count >= 2: nodata = Double(parts[1]) ?? nodata
            default:
                // data row
                let vals: [Double?] = parts.map { token in
                    guard let v = Double(token) else { return nil }
                    return v == nodata ? nil : v
                }
                dataRows.append(vals)
            }
        }

        guard haveNcols else { throw LoaderError.missingHeaderKey("ncols") }
        guard haveNrows else { throw LoaderError.missingHeaderKey("nrows") }
        guard haveCellsize else { throw LoaderError.missingHeaderKey("cellsize") }

        var values: [Double?] = []
        values.reserveCapacity(ncols * nrows)
        for (index, row) in dataRows.enumerated() {
            guard row.count == ncols else { throw LoaderError.malformedRow(index) }
            values.append(contentsOf: row)
        }
        guard values.count == ncols * nrows else {
            throw LoaderError.sizeMismatch(expected: ncols * nrows, found: values.count)
        }

        // .asc origin is the lower-left corner; convert center references if used.
        let originX = xCenter ? xll - cellsize / 2 : xll
        let originY = yCenter ? yll - cellsize / 2 : yll
        let maxValue = values.compactMap { $0 }.max() ?? 0

        return IndiaWildfireRiskGrid(
            width: ncols,
            height: nrows,
            minLon: originX,
            maxLon: originX + Double(ncols) * cellsize,
            minLat: originY,
            maxLat: originY + Double(nrows) * cellsize,
            maxValue: maxValue,
            values: values
        )
    }
}

extension WildfireHazardModel {
    /// A wildfire hazard model that loads the most recent ROS raster (`.asc`)
    /// written by Cell2Fire under `<outputFolder>/<subdirectory>/`. Assumes the
    /// raster is in lon/lat (see `AsciiGridLoader`); projected output should be
    /// reprojected first.
    static func loadingLatestROSGrid(subdirectory: String = "RateOfSpread") -> WildfireHazardModel {
        WildfireHazardModel { request in
            let directory = URL(fileURLWithPath: request.outputFolder)
                .appendingPathComponent(subdirectory)
            let files = (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: .skipsHiddenFiles)) ?? []
            let ascFiles = files.filter { $0.pathExtension.lowercased() == "asc" }

            func modificationDate(_ url: URL) -> Date {
                (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            }

            guard let latest = ascFiles.max(by: { modificationDate($0) < modificationDate($1) }) else {
                throw AsciiGridLoader.LoaderError.unreadable
            }
            return try AsciiGridLoader.loadGrid(at: latest)
        }
    }
}
