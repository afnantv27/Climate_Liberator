import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

extension ContentView {

    func run() {
        normalizeWeatherInterval()
        normalizeSimulationParameters()

        let binaryResolution = resolveBinaryPath(allowAutofix: true)
        guard case let .resolved(normalizedBinary) = binaryResolution else {
            appendToLog("Cannot run: \(binaryResolution.failureMessage)")
            return
        }

        if let error = validateEnvironment(skipBinaryCheck: true) {
            appendToLog("Cannot run: \(error)")
            return
        }

        overlayState.overlayLoadVersion &+= 1
        let currentOverlayVersion = overlayState.overlayLoadVersion
        overlayState.overlaySnapshotBeforeRun = OverlaySnapshot(overlay: overlayState.rosOverlay,
                                                   asciiURL: overlayState.lastOverlayASCIIURL,
                                                   sourceURL: overlayState.lastOverlaySourceURL,
                                                   grid: overlayState.lastOverlayGrid)
        overlayState.rosOverlay = nil
        overlayState.lastOverlayASCIIURL = nil
        overlayState.lastOverlaySourceURL = nil
        overlayState.lastOverlayGrid = nil
        refreshIgnitionMarkers(with: nil)
        DispatchQueue.main.async {
            mapController.clearOverlay()
        }

        simulationState.logFileURL = prepareLogFile()
        simulationState.log = "Starting \(simulationEngineMode.label)…\n"
        resetLogFile(with: simulationState.log)

        let trimmedOutput = outputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedOutput.isEmpty else {
            appendToLog("Choose an output folder before running.")
            DispatchQueue.main.async { showingOutputPicker = true }
            return
        }

        let outputArgument = NSString(string: trimmedOutput).expandingTildeInPath
        do {
            try FileManager.default.createDirectory(atPath: outputArgument, withIntermediateDirectories: true)
        } catch {
            appendToLog("Failed to prepare output folder: \(error.localizedDescription)")
            return
        }

        simulationState.isRunning = true
        let runStartedAt = Date()
        let riskLinkCoordinate = mapRegion.center
        let riskLinkRadiusMeters = indiaRiskStore.radiusMeters
        let logFilePath = simulationState.logFileURL?.path

        let normalizedInput = NSString(string: inputFolder).expandingTildeInPath
        let resolvedOutputDir = resolvedOutputDirectory(for: normalizedInput, customOutput: outputArgument)
        let runConfiguration = RunConfigurationSnapshot(
            binaryPath: normalizedBinary,
            inputFolder: normalizedInput,
            outputDirectory: resolvedOutputDir,
            simulatorCode: simulationState.selectedSim,
            simulatorLabel: simulatorLabel(for: simulationState.selectedSim),
            scenarioName: scenarioStore.selectedScenario?.name,
            scenarioLabel: scenarioStore.selectedScenario?.tcfdScenarioLabel ?? "Ad hoc wildfire run",
            scenarioPathway: scenarioStore.selectedScenario?.pathwayLabel,
            scenarioHorizon: scenarioStore.selectedScenario?.horizonLabel,
            includeROS: simulationState.includeRos,
            weatherPeriodMinutes: simulationState.weatherPeriodMinutes,
            outputFormat: simulationState.outputFormat.rawValue,
            numberOfSimulations: simulationState.numberOfSimulations,
            numberOfThreads: simulationState.numberOfThreads,
            seed: simulationState.seedValue
        )

        let request = SimulationEngineRequest(
            mode: simulationEngineMode,
            legacyBinaryPath: normalizedBinary,
            simulatorCode: simulationState.selectedSim,
            inputFolder: normalizedInput,
            outputFolder: outputArgument,
            includeROS: simulationState.includeRos,
            weatherPeriodMinutes: simulationState.weatherPeriodMinutes,
            firePeriodLength: 1.0,
            outputFormat: simulationState.outputFormat,
            numberOfSimulations: simulationState.numberOfSimulations,
            numberOfThreads: simulationState.numberOfThreads,
            seed: simulationState.seedValue
        )

        simulationEngineService.run(request: request,
                                    onStandardOutput: { chunk in
                                        appendToLog(chunk)
                                    },
                                    onStandardError: { chunk in
                                        appendToLog("[stderr] \(chunk)")
                                    }) { result in
            simulationState.isRunning = false
            switch result {
            case .success(let output):
                appendToLog("[Engine] Completed with \(output.engineLabel).\n")
                appendToLog("Exit code: \(output.terminationStatus)\n")
                if let runArtifactURL = output.runArtifactURL {
                    appendToLog("[Artifact] Run artifact: \(runArtifactURL.path)\n")
                }
                appendOutputTailIfNeeded(from: output.stdout)
                simulationState.hasSuccessfulRun = true
                simulationState.lastOutputDirectory = resolvedOutputDir
                loadOutputTree(from: resolvedOutputDir)
                overlayState.overlaySnapshotBeforeRun = nil
                DispatchQueue.global(qos: .userInitiated).async {
                    let completedAt = Date()
                    let rosStats = analyzeRateOfSpread(at: resolvedOutputDir)
                    let summary = buildRunSummary(from: output.stdout,
                                                  rosStats: rosStats,
                                                  timestamp: completedAt)
                    let persistenceResult: Result<PersistedTCFDBundleResult, Error>? = summary.map { parsedSummary in
                        Result {
                            try artifactService.persistTCFDBundle(summary: parsedSummary,
                                                                   stdout: output.stdout,
                                                                   stderr: output.stderr,
                                                                   startedAt: runStartedAt,
                                                                   completedAt: completedAt,
                                                                   configuration: runConfiguration,
                                                                   logFilePath: logFilePath)
                        }
                    }
                    let indiaRiskPersistenceResult: Result<IndiaWildfireRiskLinkResult?, Error>?
                    if case let .success(bundle)? = persistenceResult {
                        indiaRiskPersistenceResult = Result {
                            try persistIndiaWildfireAssessmentsIfPossible(
                                runID: bundle.runID,
                                configuration: runConfiguration,
                                siteCoordinate: riskLinkCoordinate,
                                radiusMeters: riskLinkRadiusMeters,
                                ignitionCell: summary?.simulations.first?.ignitionCell
                            )
                        }
                    } else {
                        indiaRiskPersistenceResult = nil
                    }
                DispatchQueue.main.async {
                        if let summary {
                            simulationState.runSummaries.insert(summary, at: 0)
                            if simulationState.runSummaries.count > 12 {
                                simulationState.runSummaries.removeLast(simulationState.runSummaries.count - 12)
                            }
                            if let ignition = summary.simulations.first?.ignitionCell {
                                overlayState.currentIgnitionCell = ignition
                            }
                            logSimulationSummary(summary)
                        }
                        if let persistenceResult {
                            switch persistenceResult {
                            case .success(let bundle):
                                reviewStore.updateDiscoveryRoots([URL(fileURLWithPath: resolvedOutputDir)])
                                appendToLog("[TCFD] Persisted run package to \(bundle.bundleDirectory.path).")
                                appendToLog("[TCFD] Run evidence report saved to \(bundle.reportURL.path).")
                            case .failure(let error):
                                appendToLog("[TCFD] Failed to write run evidence package: \(error.localizedDescription)")
                            }
                        } else {
                            appendToLog("[TCFD] Run completed, but the summary could not be parsed for packaging.")
                        }
                        if let indiaRiskPersistenceResult {
                            switch indiaRiskPersistenceResult {
                            case .success(.some(let linkResult)):
                                appendToLog("[India Risk] Stored \(linkResult.storedCount) wildfire assessments for nearby buildings (\(linkResult.highRiskCount) high, \(linkResult.mediumRiskCount) medium, \(linkResult.lowRiskCount) low).")
                                indiaRiskStore.refreshDatabaseStatus()
                                indiaRiskStore.lookupNearbyBuildings(latitude: riskLinkCoordinate.latitude,
                                                                     longitude: riskLinkCoordinate.longitude)
                            case .success(.none):
                                break
                            case .failure(let error):
                                appendToLog("[India Risk] Failed to store wildfire linkages: \(error.localizedDescription)")
                            }
                        }
                    }
                }
                postProcessRateOfSpread(at: resolvedOutputDir, desiredFormat: simulationState.outputFormat)
                updateMapOverlay(at: resolvedOutputDir, expectedVersion: currentOverlayVersion)
            case .failure(let error):
                appendToLog("Error: \(error.localizedDescription)")
                restoreOverlaySnapshotIfNeeded()
            }
        }
    }

    func handleInputFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let folder = urls.first { inputFolder = folder.path }
        case .failure(let error):
            appendToLog("Input folder picker error: \(error.localizedDescription)")
        }
    }

    func handleOutputFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let folder = urls.first {
                let path = folder.path
                outputFolder = path
                simulationState.lastOutputDirectory = path
                refreshOutputTree()
            }
        case .failure(let error):
            appendToLog("Output folder picker error: \(error.localizedDescription)")
        }
    }

    func handleBinarySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let file = urls.first { binaryPath = file.path }
        case .failure(let error):
            appendToLog("Binary picker error: \(error.localizedDescription)")
        }
    }

    func refreshOutputTree() {
        rebuildOutputTree(rateOfSpreadBase: simulationState.lastOutputDirectory)
    }

    func loadOutputTree(from basePath: String) {
        rebuildOutputTree(rateOfSpreadBase: basePath)
    }

    func rebuildOutputTree(rateOfSpreadBase: String?) {
        outputStore.rebuild(rateOfSpreadBase: rateOfSpreadBase,
                            earthEngineOverlaysDirectory: overlaysDirectory(),
                            limits: outputTreeLimits)
    }

    func selectOutputNode(_ node: OutputNode, zoomAfterSelection: Bool) {
        guard node.isSelectable else { return }
        loadOverlay(from: node.url,
                    zoomAfterLoad: zoomAfterSelection,
                    successMessage: "Loaded overlay from")
    }

        func reloadIgnitionCells() {
        let trimmed = inputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            overlayState.defaultIgnitionCells = []
            if overlayState.currentIgnitionCell == nil {
                refreshIgnitionMarkers(with: overlayState.rosOverlay)
            }
            return
        }

        let normalizedFolder = NSString(string: trimmed).expandingTildeInPath
        let ignitionURL = URL(fileURLWithPath: normalizedFolder).appendingPathComponent("Ignitions.csv")
        guard FileManager.default.fileExists(atPath: ignitionURL.path) else {
            overlayState.defaultIgnitionCells = []
            if overlayState.currentIgnitionCell == nil {
                refreshIgnitionMarkers(with: overlayState.rosOverlay)
            }
            return
        }

        do {
            let contents = try String(contentsOf: ignitionURL, encoding: .utf8)
            let lines = contents.split(whereSeparator: \.isNewline)
            let dataRows = lines.dropFirst()
            var cells: [Int] = []
            for row in dataRows {
                let columns = row.split(separator: ",").map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
                for column in columns.reversed() {
                    if let value = Int(column) {
                        cells.append(value)
                        break
                    }
                }
            }
            overlayState.defaultIgnitionCells = cells
            if overlayState.currentIgnitionCell == nil {
                overlayState.currentIgnitionCell = cells.first
            } else {
                refreshIgnitionMarkers(with: overlayState.rosOverlay)
            }
        } catch {
            overlayState.defaultIgnitionCells = []
        }
    }

    func refreshIgnitionMarkers(with overlay: RateOfSpreadOverlay?) {
        guard let overlay = overlay else {
            overlayState.ignitionMarkers = []
            return
        }
        guard let cellID = overlayState.activeIgnitionCell,
              let coordinate = overlay.coordinate(forCellID: cellID) else {
            overlayState.ignitionMarkers = []
            return
        }
        overlayState.ignitionMarkers = [IgnitionMarker(coordinate: coordinate)]
    }

    func normalizeWeatherInterval() {
        let digitsOnly = simulationState.weatherPeriodInput.filter { $0.isNumber }
        guard let value = Int(digitsOnly), value >= 10 else {
            simulationState.weatherPeriodMinutes = 10
            simulationState.weatherPeriodInput = "10"
            return
        }

        if value % 10 != 0 {
            simulationState.weatherPeriodMinutes = 10
            simulationState.weatherPeriodInput = "10"
        } else {
            simulationState.weatherPeriodMinutes = value
            simulationState.weatherPeriodInput = "\(value)"
        }
    }

    func normalizeSimulationParameters() {
        if let sims = Int(simulationState.numberOfSimulationsInput), sims >= 1 {
            simulationState.numberOfSimulations = sims
        } else {
            simulationState.numberOfSimulations = 1
            simulationState.numberOfSimulationsInput = "1"
        }

        if let threads = Int(simulationState.numberOfThreadsInput), threads >= 1 {
            simulationState.numberOfThreads = threads
        } else {
            simulationState.numberOfThreads = 7
            simulationState.numberOfThreadsInput = "7"
        }

        if let seed = Int(filterSeedInput(simulationState.seedInput)) {
            simulationState.seedValue = seed
            simulationState.seedInput = "\(seed)"
        } else {
            simulationState.seedValue = 123
            simulationState.seedInput = "123"
        }
    }

    func resolveBinaryPath(allowAutofix: Bool) -> BinaryResolution {
        let fm = FileManager.default
        let trimmed = binaryPath.trimmingCharacters(in: .whitespacesAndNewlines)
        var seen = Set<String>()
        var candidates: [String] = []

        if trimmed.isEmpty {
            candidates.append(preferredBinaryPath)
            candidates.append(contentsOf: legacyBinaryPaths)
        } else {
            if legacyBinaryPaths.contains(trimmed) {
                candidates.append(preferredBinaryPath)
            }
            candidates.append(trimmed)
        }

        for candidate in candidates where !candidate.isEmpty && !seen.contains(candidate) {
            seen.insert(candidate)
            let expanded = NSString(string: candidate).expandingTildeInPath
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: expanded, isDirectory: &isDir),
               !isDir.boolValue,
               fm.isExecutableFile(atPath: expanded) {
                if allowAutofix, candidate != binaryPath {
                    binaryPath = candidate
                }
                return .resolved(expanded)
            }
        }

        return trimmed.isEmpty ? .needsPath : .invalid
    }

    func validateEnvironment(skipBinaryCheck: Bool = false) -> String? {
        if !skipBinaryCheck {
            let binaryStatus = resolveBinaryPath(allowAutofix: false)
            switch binaryStatus {
            case .resolved:
                break
            case .needsPath, .invalid:
                return binaryStatus.failureMessage
            }
        }

        let fm = FileManager.default
        var isDir: ObjCBool = false
        let inputFullPath = NSString(string: inputFolder).expandingTildeInPath
        guard fm.fileExists(atPath: inputFullPath, isDirectory: &isDir), isDir.boolValue else {
            return "Input folder not found."
        }
        let trimmedOutput = outputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedOutput.isEmpty {
            return "Select an output folder."
        }
        let parent = (trimmedOutput as NSString).expandingTildeInPath
        let parentURL = URL(fileURLWithPath: parent).deletingLastPathComponent()
        if !fm.isWritableFile(atPath: parentURL.path) {
            return "Output folder location is not writable."
        }
        return nil
    }

    func resolvedOutputDirectory(for input: String, customOutput: String?) -> String {
        if let customOutput, !customOutput.isEmpty {
            return NSString(string: customOutput).expandingTildeInPath
        }
        var normalized = input
        if !normalized.hasSuffix("/") {
            normalized += "/"
        }
        return NSString(string: normalized + "simOuts").expandingTildeInPath
    }

    func rateOfSpreadDirectory(basePath: String) -> URL {
        let baseURL = URL(fileURLWithPath: basePath)
        if baseURL.lastPathComponent.compare("RateOfSpread", options: .caseInsensitive) == .orderedSame {
            return baseURL
        }
        return baseURL.appendingPathComponent("RateOfSpread")
    }

    func latestROSFile(from files: [URL]) -> URL? {
        let ascFiles = files.filter { $0.pathExtension.lowercased() == "asc" }
        return ascFiles.max { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return lDate < rDate
        }
    }

    func persistIndiaWildfireAssessmentsIfPossible(runID: String,
                                                           configuration: RunConfigurationSnapshot,
                                                           siteCoordinate: CLLocationCoordinate2D,
                                                           radiusMeters: Double,
                                                           ignitionCell: Int?) throws -> IndiaWildfireRiskLinkResult? {
        let rosDir = rateOfSpreadDirectory(basePath: configuration.outputDirectory)
        guard let contents = try? FileManager.default.contentsOfDirectory(at: rosDir,
                                                                          includingPropertiesForKeys: [.contentModificationDateKey],
                                                                          options: .skipsHiddenFiles),
              let latest = latestROSFile(from: contents),
              let normalizedASCII = prepareOverlayASCII(for: latest),
              let grid = parseRateOfSpreadGrid(from: normalizedASCII) else {
            return nil
        }

        let request = IndiaWildfireRiskLinkRequest(
            runID: runID,
            scenarioLabel: configuration.scenarioLabel,
            simulatorLabel: configuration.simulatorLabel,
            siteLatitude: siteCoordinate.latitude,
            siteLongitude: siteCoordinate.longitude,
            searchRadiusMeters: radiusMeters,
            outputDirectory: configuration.outputDirectory,
            sourceRasterPath: normalizedASCII.path,
            ignitionCell: ignitionCell
        )
        let linker = IndiaWildfireRiskLinker(store: indiaRiskStore)
        return try linker.persistLatestWildfireAssessments(
            request: request,
            grid: IndiaWildfireRiskGrid(
                width: grid.width,
                height: grid.height,
                minLon: grid.minLon,
                maxLon: grid.maxLon,
                minLat: grid.minLat,
                maxLat: grid.maxLat,
                maxValue: grid.maxValue,
                values: grid.values
            )
        )
    }

    func restoreLatestPersistedRunIfNeeded() {
        guard !simulationState.hasSuccessfulRun, simulationState.runSummaries.isEmpty, restoredRunID == nil,
              let latest = reviewStore.bundles.first else {
            return
        }
        restorePersistedRunState(from: latest)
    }

    func restorePersistedRunState(from bundle: TCFDRunArtifactBundle) {
        guard restoredRunID != bundle.runID else { return }
        let summaryURL = URL(fileURLWithPath: bundle.summaryJSONURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let data = try? Data(contentsOf: summaryURL),
              let persisted = try? decoder.decode(PersistedRunSummaryDocument.self, from: data) else {
            return
        }

        let restoredSummary = RunSummary(
            timestamp: persisted.timestamp,
            simulations: persisted.simulations.map { simulation in
                SimulationStats(
                    simulationIndex: simulation.simulationIndex,
                    weatherFile: simulation.weatherFile,
                    ignitionCell: simulation.ignitionCell,
                    totalCells: simulation.totalCells,
                    available: simulation.available,
                    burnt: simulation.burnt,
                    nonBurnable: simulation.nonBurnable,
                    firebreak: simulation.firebreak,
                    highestROS: simulation.highestROS,
                    lowestROS: simulation.lowestROS
                )
            }
        )

        restoredRunID = bundle.runID
        simulationState.hasSuccessfulRun = true
        simulationState.lastOutputDirectory = bundle.outputDirectory
        simulationState.runSummaries = [restoredSummary]
        overlayState.currentIgnitionCell = restoredSummary.simulations.first?.ignitionCell
        loadOutputTree(from: bundle.outputDirectory)
    }

    func projectionInfo(for ascURL: URL, logFailures: Bool = true) -> ProjectionInfo? {
        let prjURL = ascURL.deletingPathExtension().appendingPathExtension("prj")
        if let data = try? Data(contentsOf: prjURL),
           let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            let upper = text.uppercased()
            let isWGS = upper.contains("WGS_1984") || upper.contains("WGS84") || upper.contains("4326")
            return ProjectionInfo(srs: text, isWGS84: isWGS)
        }
        if useOverrideCRS {
            let normalized = normalizeCRSCode(overrideCRSCode)
            let isWGS = normalized.caseInsensitiveCompare("EPSG:4326") == .orderedSame
            return ProjectionInfo(srs: normalized, isWGS84: isWGS)
        }
        if let inferred = heuristicallyInferProjection(for: ascURL, logFailures: logFailures) {
            return inferred
        }
        return nil
    }

    func heuristicallyInferProjection(for ascURL: URL, logFailures: Bool) -> ProjectionInfo? {
        guard let header = asciiHeaderMetadata(for: ascURL),
              let xOrigin = header.xOrigin,
              let yOrigin = header.yOrigin else {
            return nil
        }

        if (-180.0...180.0).contains(xOrigin) && (-90.0...90.0).contains(yOrigin) {
            return ProjectionInfo(srs: "EPSG:4326", isWGS84: true)
        }

        if isLikelyDutchRD(easting: xOrigin, northing: yOrigin) {
            if logFailures {
            appendToLog("[CRS] No PRJ for \(ascURL.lastPathComponent); assuming Dutch RD New (EPSG:28992). Use the CRS override if this assumption is incorrect.")
            }
            return ProjectionInfo(srs: "EPSG:28992", isWGS84: false)
        }

        return nil
    }

    func asciiHeaderMetadata(for ascURL: URL) -> ASCIIHeaderMetadata? {
        guard let lines = readASCIIHeaderLines(from: ascURL, maxBytes: 16_384, maxLines: 12) else {
            return nil
        }
        var xOrigin: Double?
        var yOrigin: Double?
        var cellSize: Double?
        var inspected = 0

        for rawLine in lines {
            let trimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let lower = trimmed.lowercased()
            if xOrigin == nil && (lower.hasPrefix("xllcorner") || lower.hasPrefix("xllcenter")) {
                xOrigin = firstDouble(in: trimmed)
            } else if yOrigin == nil && (lower.hasPrefix("yllcorner") || lower.hasPrefix("yllcenter")) {
                yOrigin = firstDouble(in: trimmed)
            } else if cellSize == nil && lower.hasPrefix("cellsize") {
                cellSize = firstDouble(in: trimmed)
            }

            inspected += 1
            if (xOrigin != nil && yOrigin != nil && cellSize != nil) || inspected >= 12 {
                break
            }
        }

        if xOrigin == nil && yOrigin == nil && cellSize == nil {
            return nil
        }
        return ASCIIHeaderMetadata(xOrigin: xOrigin, yOrigin: yOrigin, cellSize: cellSize)
    }

    func isLikelyDutchRD(easting: Double, northing: Double) -> Bool {
        let eastingRange = 0.0...300_000.0
        let northingRange = 250_000.0...630_000.0
        return eastingRange.contains(easting) && northingRange.contains(northing)
    }

    func normalizeCRSCode(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "EPSG:4326" }
        if trimmed.uppercased().hasPrefix("EPSG:") {
            return trimmed.uppercased()
        }
        if Int(trimmed) != nil {
            return "EPSG:\(trimmed)"
        }
        return trimmed
    }

    func exportKMZ() {
        guard let outputDir = simulationState.lastOutputDirectory else {
            appendToLog("[KMZ] Run Cell2Fire first so there is a RateOfSpread output to export.")
            return
        }
        if simulationState.isExportingKMZ { return }
        simulationState.isExportingKMZ = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = createKMZ(from: outputDir)
            DispatchQueue.main.async {
                simulationState.isExportingKMZ = false
                switch result {
                case .success(let url):
                    appendToLog("[KMZ] Saved overlay to \(url.path).")
                case .failure(let error):
                    appendToLog("[KMZ] Export failed: \(error.localizedDescription)")
                }
            }
        }
    }

    func createKMZ(from outputDirectory: String) -> Result<URL, Error> {
        let rosDir = rateOfSpreadDirectory(basePath: outputDirectory)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: rosDir,
                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: .skipsHiddenFiles) else {
            return .failure(ExportError(message: "RateOfSpread folder not found at \(rosDir.path)."))
        }
        guard let latestASC = latestROSFile(from: contents) else {
            return .failure(ExportError(message: "No ROS *.asc files found under \(rosDir.path)."))
        }

        let tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
        let assignedTIF = tempDir.appendingPathComponent("ros-\(UUID().uuidString)-assigned.tif")
        guard let projection = projectionInfo(for: latestASC) else {
            return .failure(ExportError(message: "Unable to determine the CRS for \(latestASC.lastPathComponent). Enable the CRS override in Output Explorer."))
        }
        do {
            try runGDALTranslate(arguments: ["-a_srs", projection.srs, latestASC.path, assignedTIF.path])
        } catch {
            return .failure(error)
        }

        let wgs84TIF: URL
        if projection.isWGS84 {
            wgs84TIF = assignedTIF
        } else {
            let reprojected = tempDir.appendingPathComponent("ros-\(UUID().uuidString)-wgs84.tif")
            do {
                try runGDALWarp(arguments: ["-s_srs", projection.srs, "-t_srs", "EPSG:4326", assignedTIF.path, reprojected.path])
            } catch {
                try? fm.removeItem(at: assignedTIF)
                return .failure(error)
            }
            try? fm.removeItem(at: assignedTIF)
            wgs84TIF = reprojected
        }

        let kmzURL = latestASC.deletingPathExtension().appendingPathExtension("kmz")

        do {
            try runGDALTranslate(arguments: ["-of", "KMLSUPEROVERLAY", wgs84TIF.path, kmzURL.path])
            try? fm.removeItem(at: wgs84TIF)
            return .success(kmzURL)
        } catch {
            try? fm.removeItem(at: wgs84TIF)
            return .failure(error)
        }
    }

    func runGDALTranslate(arguments: [String]) throws {
        guard let executable = locateGDALTranslate() else {
            throw ExportError(message: "gdal_translate not found. Install GDAL (e.g., `brew install gdal`).")
        }
        try runGDALProcess(executable: executable, arguments: arguments, label: "gdal_translate")
    }

    func runGDALWarp(arguments: [String]) throws {
        guard let executable = locateGDALWarp() else {
            throw ExportError(message: "gdalwarp not found. Install GDAL (e.g., `brew install gdal`).")
        }
        try runGDALProcess(executable: executable, arguments: arguments, label: "gdalwarp")
    }

    func runGDALProcess(executable: String, arguments: [String], label: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let errPipe = Pipe()
        process.standardError = errPipe
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let errorOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw ExportError(message: errorOutput.isEmpty ? "\(label) exited with \(process.terminationStatus)" : errorOutput)
        }
    }

    func locateGDALTranslate() -> String? {
        locateGDALBinary(name: "gdal_translate", cache: &ContentView.gdalTranslateCache)
    }

    func locateGDALWarp() -> String? {
        locateGDALBinary(name: "gdalwarp", cache: &ContentView.gdalWarpCache)
    }

    func locateGDALTransform() -> String? {
        locateGDALBinary(name: "gdaltransform", cache: &ContentView.gdalTransformCache)
    }

    func locateGDALBinary(name: String, cache: inout String?) -> String? {
        if let cached = cache {
            return cached
        }
        let fm = FileManager.default
        var candidates = [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/usr/bin/\(name)"
        ]
        if let pathEnv = ProcessInfo.processInfo.environment["PATH"] {
            for dir in pathEnv.split(separator: ":") {
                let full = String(dir) + "/\(name)"
                candidates.append(full)
            }
        }
        for path in candidates {
            if fm.isExecutableFile(atPath: path) {
                cache = path
                return path
            }
        }
        return nil
    }

    func postProcessRateOfSpread(at outputDirectory: String, desiredFormat: OutputFormat) {
        guard desiredFormat == .tif else { return }

        DispatchQueue.global(qos: .utility).async {
            let rosDir = rateOfSpreadDirectory(basePath: outputDirectory)
            let fm = FileManager.default

            guard let contents = try? fm.contentsOfDirectory(at: rosDir,
                                                             includingPropertiesForKeys: [.contentModificationDateKey],
                                                             options: .skipsHiddenFiles) else {
                DispatchQueue.main.async {
                    appendToLog("[ROS conversion] RateOfSpread folder not found at \(rosDir.path).")
                }
                return
            }

            guard let latest = latestROSFile(from: contents) else {
                DispatchQueue.main.async {
                    appendToLog("[ROS conversion] No ROSFile*.asc outputs found in \(rosDir.path).")
                }
                return
            }

            let tifURL = latest.deletingPathExtension().appendingPathExtension("tif")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["gdal_translate", "-of", "GTiff", latest.path, tifURL.path]
            let errPipe = Pipe()
            process.standardError = errPipe

            do {
                try process.run()
                process.waitUntilExit()
                let errorOutput = String(data: errPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                DispatchQueue.main.async {
                    if process.terminationStatus == 0 {
                        appendToLog("[ROS conversion] GeoTIFF saved to \(tifURL.path).")
                    } else {
                        appendToLog("[ROS conversion] gdal_translate failed (\(process.terminationStatus)). \(errorOutput)")
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    appendToLog("[ROS conversion] Failed to run gdal_translate: \(error.localizedDescription)")
                }
            }
        }
    }

    func updateMapOverlay(at outputDirectory: String, expectedVersion: Int? = nil) {
        DispatchQueue.global(qos: .userInitiated).async {
            let rosDir = rateOfSpreadDirectory(basePath: outputDirectory)
            let fm = FileManager.default

            guard let contents = try? fm.contentsOfDirectory(at: rosDir,
                                                             includingPropertiesForKeys: [.contentModificationDateKey],
                                                             options: .skipsHiddenFiles),
                  let latest = latestROSFile(from: contents) else {
                DispatchQueue.main.async {
                    appendToLog("[Map] RateOfSpread outputs not found; overlay skipped.")
                }
                return
            }

            DispatchQueue.main.async {
                loadOverlay(from: latest,
                            zoomAfterLoad: true,
                            successMessage: "Updated overlay from",
                            expectedVersion: expectedVersion)
            }
        }
    }

    func rebuildOverlay() {
        let palette = rosPalette.colorStops
        let alphaScale = rosOpacity

        if let cachedGrid = overlayState.lastOverlayGrid {
            DispatchQueue.global(qos: .userInitiated).async {
                guard let overlay = makeOverlay(from: cachedGrid,
                                                colorStops: palette,
                                                alphaScale: alphaScale) else {
                    DispatchQueue.main.async {
                        appendToLog("[Map] Unable to refresh the ROS overlay for the selected theme.")
                    }
                    return
                }

                DispatchQueue.main.async {
                    applyRenderedOverlay(overlay,
                                         zoomAfterLoad: false,
                                         successMessage: nil,
                                         sourceFile: nil,
                                         animated: true)
                }
            }
            return
        }

        guard let asciiURL = overlayState.lastOverlayASCIIURL else { return }
        DispatchQueue.global(qos: .userInitiated).async {
            guard let grid = parseRateOfSpreadGrid(from: asciiURL),
                  let overlay = makeOverlay(from: grid,
                                            colorStops: palette,
                                            alphaScale: alphaScale) else {
                DispatchQueue.main.async {
                    appendToLog("[Map] Unable to refresh the ROS overlay for the selected theme.")
                }
                return
            }

            DispatchQueue.main.async {
                overlayState.lastOverlayGrid = grid
                applyRenderedOverlay(overlay,
                                     zoomAfterLoad: false,
                                     successMessage: nil,
                                     sourceFile: nil,
                                     animated: true)
            }
        }
    }

    func loadOverlay(from sourceFile: URL,
                             zoomAfterLoad: Bool,
                             successMessage: String,
                             expectedVersion: Int? = nil) {
        let palette = rosPalette.colorStops
        let alphaScale = rosOpacity
        DispatchQueue.global(qos: .userInitiated).async {
            guard let normalizedASCII = prepareOverlayASCII(for: sourceFile) else {
                return
            }

            guard let grid = parseRateOfSpreadGrid(from: normalizedASCII) else {
                DispatchQueue.main.async {
                    appendToLog("[Map] Failed to parse \(sourceFile.lastPathComponent).")
                }
                return
            }

            guard let overlay = makeOverlay(from: grid,
                                            colorStops: palette,
                                            alphaScale: alphaScale) else {
                DispatchQueue.main.async {
                    appendToLog("[Map] Failed to build overlay for \(sourceFile.lastPathComponent).")
                }
                return
            }

            DispatchQueue.main.async {
                if let expectedVersion, expectedVersion != overlayState.overlayLoadVersion {
                    return
                }
                overlayState.lastOverlayASCIIURL = normalizedASCII
                overlayState.lastOverlaySourceURL = sourceFile
                overlayState.lastOverlayGrid = grid
                applyRenderedOverlay(overlay,
                                     zoomAfterLoad: zoomAfterLoad,
                                     successMessage: successMessage,
                                     sourceFile: sourceFile,
                                     animated: false)
                if expectedVersion != nil {
                    refreshOutputTree()
                }
            }
        }
    }

    func applyRenderedOverlay(_ overlay: RateOfSpreadOverlay,
                                      zoomAfterLoad: Bool,
                                      successMessage: String?,
                                      sourceFile: URL?,
                                      animated: Bool) {
        let update = {
            overlayState.rosOverlay = overlay
        }

        if animated {
            withAnimation(.easeInOut(duration: 0.2)) {
                update()
            }
        } else {
            update()
        }

        refreshIgnitionMarkers(with: overlay)
        if zoomAfterLoad {
            focusMap(on: overlay)
        }
        if let message = successMessage, let source = sourceFile {
            appendToLog("[Map] \(message) \(source.lastPathComponent).")
        }
    }

    func focusMap(on overlay: RateOfSpreadOverlay) {
        let latExtent = max(overlay.maxLat - overlay.minLat, 0.005)
        let lonExtent = max(overlay.maxLon - overlay.minLon, 0.005)
        let span = MKCoordinateSpan(latitudeDelta: latExtent * 1.25,
                                    longitudeDelta: lonExtent * 1.25)
        let region = MKCoordinateRegion(center: overlay.coordinate, span: span)
        withAnimation(.easeInOut(duration: 0.35)) {
            mapRegion = region
        }
    }

    func simulationField(title: String,
                                 binding: Binding<String>,
                                 placeholder: String,
                                 onValueChange: @escaping (String) -> Void,
                                 infoAction: @escaping () -> Void) -> some View {
        HStack {
            HStack(spacing: 4) {
                Text(title)
                Button {
                    infoAction()
                } label: {
                    Image(systemName: "info.circle")
                }
                .buttonStyle(.plain)
            }
            Spacer()
            TextField(placeholder, text: binding)
                .frame(width: 100)
                .multilineTextAlignment(.trailing)
                .onChange(of: binding.wrappedValue) { _, newValue in
                    DispatchQueue.main.async {
                        onValueChange(newValue)
                    }
                }
                .themedField(background: theme.fieldBackground, textColor: theme.textColor)
        }
    }

    func filterSeedInput(_ value: String) -> String {
        var filtered = ""
        for (index, character) in value.enumerated() {
            if character.isNumber {
                filtered.append(character)
            } else if character == "-" && index == 0 {
                filtered.append(character)
            }
        }
        return filtered
    }

    nonisolated func appendToLog(_ message: String) {
        let entry = message.hasSuffix("\n") ? message : message + "\n"
        Task { @MainActor in
            simulationState.appendLog(entry, maxCharacterCount: maxLogCharacterCount)
            appendLogToFile(entry)
        }
    }

    func prepareOverlayASCII(for source: URL) -> URL? {
        guard let projection = projectionInfo(for: source) else {
            appendToLog("[Map] Unknown CRS for \(source.lastPathComponent); set a CRS override or include a .prj file before displaying the layer.")
            return nil
        }
        if projection.isWGS84 { return source }

        guard let gdalWarpPath = locateGDALWarp() else {
            appendToLog("[Map] gdalwarp is required to display \(source.lastPathComponent). Install GDAL (e.g., `brew install gdal`) or set a CRS override if the data is already in WGS84.")
            return nil
        }

        guard let targetDir = overlaysDirectory() else {
            appendToLog("[Map] Unable to prepare overlay directory.")
            return nil
        }

        let target = targetDir.appendingPathComponent("ros_overlay_wgs.asc")
        try? FileManager.default.removeItem(at: target)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: gdalWarpPath)
        process.arguments = ["-of", "AAIGrid", "-s_srs", projection.srs, "-t_srs", "EPSG:4326", source.path, target.path]
        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()
            if process.terminationStatus == 0 {
                return target
            } else {
                let errorOutput = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                appendToLog("[Map] gdalwarp failed (\(process.terminationStatus)). \(errorOutput)")
                return nil
            }
        } catch {
            appendToLog("[Map] Failed to run gdalwarp: \(error.localizedDescription)")
            return nil
        }
    }

    func overlaysDirectory() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        let dir = base.appendingPathComponent("ClimateLiberator/Overlays", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            return dir
        } catch {
            return nil
        }
    }

    func parseRateOfSpreadGrid(from asciiURL: URL) -> RateOfSpreadGrid? {
        guard let data = try? String(contentsOf: asciiURL, encoding: .utf8) else { return nil }
        let lines = data.split(whereSeparator: \.isNewline).map(String.init)
        if lines.isEmpty { return nil }

        var header: [String: Double] = [:]
        var dataStartIndex = 0
        let headerKeys: Set<String> = ["ncols", "nrows", "xllcorner", "yllcorner", "xllcenter", "yllcenter", "cellsize", "nodata_value"]

        for (index, line) in lines.enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split(whereSeparator: { $0 == " " || $0 == "\t" })
            guard parts.count >= 2 else {
                dataStartIndex = index
                break
            }
            let key = parts[0].lowercased()
            if headerKeys.contains(key), let value = Double(parts[1]) {
                header[key] = value
                continue
            } else {
                dataStartIndex = index
                break
            }
        }

        guard let ncols = header["ncols"].flatMap(Int.init),
              let nrows = header["nrows"].flatMap(Int.init),
              let cellSize = header["cellsize"],
              let xll = header["xllcorner"] ?? header["xllcenter"],
              let yll = header["yllcorner"] ?? header["yllcenter"] else {
            return nil
        }
        let nodataValue = header["nodata_value"]
        let valuesCount = ncols * nrows
        if valuesCount == 0 { return nil }

        var values = [Double?](repeating: nil, count: valuesCount)
        var minValue = Double.infinity
        var maxValue = -Double.infinity
        var hasRenderableSamples = false
        var currentRow = 0

        for line in lines[dataStartIndex...] {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let tokens = trimmed.split { $0 == " " || $0 == "\t" }
            guard tokens.count == ncols else { continue }
            if currentRow >= nrows { break }

            for (col, token) in tokens.enumerated() {
                let index = currentRow * ncols + col
                if let value = Double(token) {
                    if let nodata = nodataValue, value == nodata {
                        values[index] = nil
                    } else if abs(value) <= 1e-9 {
                        // treat zeros (and tiny numerical noise) as transparent
                        values[index] = nil
                    } else {
                        values[index] = value
                        minValue = min(minValue, value)
                        maxValue = max(maxValue, value)
                        hasRenderableSamples = true
                    }
                }
            }
            currentRow += 1
        }

        guard hasRenderableSamples else {
            return nil
        }

        if maxValue <= minValue {
            maxValue = minValue + 1
        }

        let minLon = xll
        let minLat = yll
        let maxLon = xll + cellSize * Double(ncols)
        let maxLat = yll + cellSize * Double(nrows)

        return RateOfSpreadGrid(sourceURL: asciiURL,
                                width: ncols,
                                height: nrows,
                                cellSize: cellSize,
                                minValue: minValue,
                                maxValue: maxValue,
                                minLon: minLon,
                                maxLon: maxLon,
                                minLat: minLat,
                                maxLat: maxLat,
                                values: values)
    }

    func makeOverlay(from grid: RateOfSpreadGrid,
                             colorStops: [ROSColorStop],
                             alphaScale: Double) -> RateOfSpreadOverlay? {
        let width = grid.width
        let height = grid.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let denominator = max(grid.maxValue - grid.minValue, 0.0001)

        for row in 0..<height {
            for col in 0..<width {
                let sourceIndex = row * width + col
                let pixelIndex = ((height - 1 - row) * width + col) * 4
                guard let value = grid.values[sourceIndex] else {
                    pixels[pixelIndex + 3] = 0
                    continue
                }
                let normalized = (value - grid.minValue) / denominator
                let color = heatColor(for: normalized, palette: colorStops, alphaScale: alphaScale)
                pixels[pixelIndex] = color.r
                pixels[pixelIndex + 1] = color.g
                pixels[pixelIndex + 2] = color.b
                pixels[pixelIndex + 3] = color.a
            }
        }

        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let image = CGImage(width: width,
                                  height: height,
                                  bitsPerComponent: 8,
                                  bitsPerPixel: 32,
                                  bytesPerRow: width * 4,
                                  space: CGColorSpaceCreateDeviceRGB(),
                                  bitmapInfo: CGBitmapInfo.byteOrder32Big.union(CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)),
                                  provider: provider,
                                  decode: nil,
                                  shouldInterpolate: true,
                                  intent: .defaultIntent) else {
            return nil
        }

        let topLeft = MKMapPoint(CLLocationCoordinate2D(latitude: grid.maxLat, longitude: grid.minLon))
        let bottomRight = MKMapPoint(CLLocationCoordinate2D(latitude: grid.minLat, longitude: grid.maxLon))
        let rect = MKMapRect(x: min(topLeft.x, bottomRight.x),
                             y: min(bottomRight.y, topLeft.y),
                             width: abs(bottomRight.x - topLeft.x),
                             height: abs(topLeft.y - bottomRight.y))
        let center = CLLocationCoordinate2D(latitude: (grid.minLat + grid.maxLat) / 2,
                                            longitude: (grid.minLon + grid.maxLon) / 2)
        return RateOfSpreadOverlay(image: image,
                                   boundingMapRect: rect,
                                   coordinate: center,
                                   values: grid.values,
                                   width: width,
                                   height: height,
                                   minValue: grid.minValue,
                                   maxValue: grid.maxValue,
                                   minLon: grid.minLon,
                                   maxLon: grid.maxLon,
                                   minLat: grid.minLat,
                                   maxLat: grid.maxLat,
                                   cellSize: grid.cellSize)
    }

    func heatColor(for normalized: Double,
                           palette: [ROSColorStop],
                           alphaScale: Double) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8) {
        let clamped = max(0, min(1, normalized))
        let orderedStops = palette.count >= 2 ? palette.sorted { $0.location < $1.location } : RateOfSpreadPalette.terrain.colorStops
        guard var lower = orderedStops.first, var upper = orderedStops.last else {
            let fallback: UInt8 = 0
            return (fallback, fallback, fallback, fallback)
        }

        for stop in orderedStops {
            if stop.location <= clamped { lower = stop }
            if stop.location >= clamped {
                upper = stop
                break
            }
        }

        let denominator = max(upper.location - lower.location, 0.0001)
        let t = (clamped - lower.location) / denominator
        let r = lower.red + (upper.red - lower.red) * t
        let g = lower.green + (upper.green - lower.green) * t
        let b = lower.blue + (upper.blue - lower.blue) * t
        let a = (lower.alpha + (upper.alpha - lower.alpha) * t) * max(0.05, min(1.0, alphaScale))

        let red = UInt8(max(0, min(255, r * 255)))
        let green = UInt8(max(0, min(255, g * 255)))
        let blue = UInt8(max(0, min(255, b * 255)))
        let alpha = UInt8(max(0, min(255, a * 255)))
        return (red, green, blue, alpha)
    }

    func prepareLogFile() -> URL? {
        let fm = FileManager.default
        guard let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else {
            return nil
        }
        let dir = base.appendingPathComponent("ClimateLiberator/Logs", isDirectory: true)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        } catch {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let filename = "simulation-log-\(formatter.string(from: Date())).txt"
        let url = dir.appendingPathComponent(filename, isDirectory: false)
        fm.createFile(atPath: url.path, contents: nil)
        return url
    }

    func resetLogFile(with text: String) {
        guard let url = simulationState.logFileURL, let data = text.data(using: .utf8) else { return }
        try? data.write(to: url, options: .atomic)
    }

    func appendLogToFile(_ text: String) {
        guard let url = simulationState.logFileURL, let data = text.data(using: .utf8) else { return }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // swallow silently to avoid recursive logging
        }
    }

    func simulatorLabel(for code: String) -> String {
        simOptions.first(where: { $0.value == code })?.label ?? code
    }

    func buildRunSummary(from output: String,
                                 rosStats: (Double?, Double?),
                                 timestamp: Date) -> RunSummary? {
        let simulations = parseSimulationStats(from: output, rosStats: rosStats)
        guard !simulations.isEmpty else { return nil }
        return RunSummary(timestamp: timestamp, simulations: simulations)
    }

    func parseSimulationStats(from output: String,
                                      rosStats: (Double?, Double?)) -> [SimulationStats] {
        var builders: [Int: SimulationStatsBuilder] = [:]
        var currentIndex: Int?
        var globalTotalCells: Int?

        let lines = output.components(separatedBy: .newlines)
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("Number of cells") {
                globalTotalCells = firstInteger(in: line)
                continue
            }

            if line.hasPrefix("Simulation ") {
                let tokens = line.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
                if tokens.count >= 2, let idx = Int(tokens[1]) {
                    currentIndex = idx
                    if builders[idx] == nil {
                        builders[idx] = SimulationStatsBuilder(index: idx)
                    }
                }
                continue
            }

            if line.lowercased().contains("ignition cell") {
                guard let idx = currentIndex else { continue }
                var builder = builders[idx] ?? SimulationStatsBuilder(index: idx)
                builder.ignitionCell = firstInteger(in: line)
                builders[idx] = builder
                continue
            }

            if line.lowercased().contains("weather file") {
                guard let idx = currentIndex else { continue }
                var builder = builders[idx] ?? SimulationStatsBuilder(index: idx)
                if let range = line.range(of: ":", options: .backwards) {
                    builder.weatherFile = String(line[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                } else {
                    builder.weatherFile = line
                }
                builders[idx] = builder
                continue
            }

            for label in ["Available", "Burnt", "Non-Burnable", "Firebreak", "Total"] {
                if line.hasPrefix(label) {
                    guard let idx = currentIndex else { continue }
                    var builder = builders[idx] ?? SimulationStatsBuilder(index: idx)
                    if let value = parseCountValue(from: line, label: label) {
                        switch label {
                        case "Available": builder.available = value
                        case "Burnt": builder.burnt = value
                        case "Non-Burnable": builder.nonBurnable = value
                        case "Firebreak": builder.firebreak = value
                        case "Total": builder.totalCells = value
                        default: break
                        }
                        builders[idx] = builder
                    }
                }
            }
        }

        let highest = rosStats.0
        let lowest = rosStats.1
        let sortedBuilders = builders.values.sorted { $0.index < $1.index }
        return sortedBuilders.map { builder in
            SimulationStats(simulationIndex: builder.index,
                            weatherFile: builder.weatherFile,
                            ignitionCell: builder.ignitionCell,
                            totalCells: builder.totalCells ?? globalTotalCells,
                            available: builder.available,
                            burnt: builder.burnt,
                            nonBurnable: builder.nonBurnable,
                            firebreak: builder.firebreak,
                            highestROS: highest,
                            lowestROS: lowest)
        }
    }

    func analyzeRateOfSpread(at outputDirectory: String) -> (Double?, Double?) {
        let rosDir = rateOfSpreadDirectory(basePath: outputDirectory)
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: rosDir,
                                                         includingPropertiesForKeys: [.contentModificationDateKey],
                                                         options: .skipsHiddenFiles) else {
            return (nil, nil)
        }
        let ascFiles = contents.filter { $0.pathExtension.lowercased() == "asc" }
        guard !ascFiles.isEmpty else { return (nil, nil) }

        var minValue: Double?
        var maxValue: Double?

        for file in ascFiles {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            var nodataValue: Double?
            for rawLine in text.split(whereSeparator: \.isNewline) {
                let line = rawLine.trimmingCharacters(in: .whitespaces)
                if line.isEmpty { continue }
                let lower = line.lowercased()
                if lower.hasPrefix("nodata_value") {
                    nodataValue = firstDouble(in: String(line))
                    continue
                }
                if lower.hasPrefix("ncols") || lower.hasPrefix("nrows") ||
                    lower.hasPrefix("xllcorner") || lower.hasPrefix("yllcorner") ||
                    lower.hasPrefix("cellsize") {
                    continue
                }

                let numbers = line.split { $0 == " " || $0 == "\t" }
                for token in numbers {
                    if let value = Double(token),
                       nodataValue == nil || value != nodataValue {
                        minValue = min(value, minValue ?? value)
                        maxValue = max(value, maxValue ?? value)
                    }
                }
            }
        }

        return (maxValue, minValue)
    }

    func parseCountValue(from line: String, label: String) -> Int? {
        let remainder = line.replacingOccurrences(of: label, with: "")
        return firstInteger(in: remainder)
    }

    func firstInteger(in text: String) -> Int? {
        if let range = text.range(of: "[0-9]+", options: .regularExpression) {
            return Int(text[range])
        }
        return nil
    }

    func firstDouble(in text: String) -> Double? {
        if let range = text.range(of: "-?[0-9]+(\\.[0-9]+)?", options: .regularExpression) {
            return Double(text[range])
        }
        return nil
    }
}
