import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

extension ContentView {

    func togglePanel() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isPanelVisible.toggle()
        }
    }

    func quitApplication() {
        NSApp.terminate(nil)
    }

    func toggleControlPanel() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            controlsExpanded.toggle()
        }
    }

    var scenarioSelectionBinding: Binding<ScenarioDefinition.ID?> {
        Binding(
            get: { scenarioStore.selectedScenarioID },
            set: { newValue in
                scenarioStore.selectScenario(id: newValue)
            }
        )
    }

    var selectedScenarioApplicationAvailability: ActionAvailability {
        guard let scenario = scenarioStore.selectedScenario else {
            return .unavailable("Select a saved disclosure scenario first.")
        }

        let binaryAvailability = AppActionSupport.pathAvailability(
            path: scenario.binaryPath,
            expectation: .file,
            emptyReason: "Complete the scenario binary path in the TCFD dashboard before applying it.",
            missingReason: "The scenario binary path cannot be found on disk."
        )
        guard binaryAvailability.isEnabled else {
            return binaryAvailability
        }

        let inputAvailability = AppActionSupport.pathAvailability(
            path: scenario.inputFolder,
            expectation: .directory,
            emptyReason: "Complete the scenario input folder in the TCFD dashboard before applying it.",
            missingReason: "The scenario input folder cannot be found on disk."
        )
        guard inputAvailability.isEnabled else {
            return inputAvailability
        }

        guard OutputFormat(rawValue: scenario.outputFormat) != nil else {
            return .unavailable("The selected scenario uses an unsupported ROS output format.")
        }

        return .ready
    }

    var operationsWorkspaceAvailability: ActionAvailability {
        if simulationState.isRunning {
            return .unavailable("A wildfire simulation is currently running in the operations workspace.")
        }
        if let warning = validateEnvironment() {
            return .unavailable(warning)
        }
        return .ready
    }

    var portfolioIntelligenceAvailability: ActionAvailability {
        if indiaRiskStore.lookupAvailability.isEnabled {
            return .ready
        }
        return .unavailable(indiaRiskStore.lookupAvailability.reason ?? "Connect a queryable India risk database before screening the portfolio.")
    }

    var disclosureReviewAvailability: ActionAvailability {
        guard !reviewStore.bundles.isEmpty else {
            return .unavailable("Generate a disclosure package from a successful run before starting disclosure review.")
        }
        return .ready
    }

    var runActionAvailability: ActionAvailability {
        if simulationState.isRunning {
            return .unavailable("A wildfire simulation is already running.")
        }
        if let warning = validateEnvironment() {
            return .unavailable(warning)
        }
        return .ready
    }

    var exportActionAvailability: ActionAvailability {
        if simulationState.isRunning {
            return .unavailable("Wait for the current simulation to finish before exporting.")
        }
        if simulationState.isExportingKMZ {
            return .unavailable("KMZ export is already in progress.")
        }
        guard simulationState.hasSuccessfulRun else {
            return .unavailable("Run a wildfire simulation first to generate exportable outputs.")
        }
        guard let outputDir = simulationState.lastOutputDirectory else {
            return .unavailable("No output directory is available yet.")
        }

        let rosDir = rateOfSpreadDirectory(basePath: outputDir)
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rosDir.path, isDirectory: &isDir), isDir.boolValue else {
            return .unavailable("The RateOfSpread output folder has not been generated yet.")
        }

        if let contents = try? FileManager.default.contentsOfDirectory(at: rosDir,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: .skipsHiddenFiles),
           latestROSFile(from: contents) != nil {
            return .ready
        }

        return .unavailable("No ROS ASCII outputs are available for KMZ export yet.")
    }

    var outputRefreshAvailability: ActionAvailability {
        if outputStore.isLoading {
            return .unavailable("Output discovery is already running.")
        }
        if simulationState.lastOutputDirectory != nil || !outputStore.nodes.isEmpty {
            return .ready
        }
        return .unavailable("Run a simulation or import an Earth Engine layer first.")
    }

    var logActionAvailability: ActionAvailability {
        simulationState.log.isEmpty ? .unavailable("No simulation log entries are available yet.") : .ready
    }

    var earthEngineActionAvailability: ActionAvailability {
        if earthEngineState.isFetching {
            return .unavailable("Earth Engine import is already running.")
        }
        if canFetchEarthEngine {
            return .ready
        }
        return .unavailable("Complete the dataset, band, dates, credentials, and helper script before fetching.")
    }

    var latestDisclosureReportAvailability: ActionAvailability {
        guard let latest = reviewStore.bundles.first else {
            return .unavailable("Generate a disclosure package before opening a report.")
        }
        return AppActionSupport.pathAvailability(
            path: latest.reportURL,
            expectation: .file,
            emptyReason: "The latest disclosure package does not include a report file.",
            missingReason: "The latest disclosure report cannot be found on disk."
        )
    }

    var latestEvidencePackageAvailability: ActionAvailability {
        guard let latest = reviewStore.bundles.first else {
            return .unavailable("Generate a disclosure package before opening the latest evidence package.")
        }
        return AppActionSupport.pathAvailability(
            path: latest.bundleURL,
            expectation: .directory,
            emptyReason: "The latest evidence package is not available.",
            missingReason: "The latest evidence package cannot be found on disk."
        )
    }

    var openOutputFolderAvailability: ActionAvailability {
        guard let outputDirectory = simulationState.lastOutputDirectory else {
            return .unavailable("Run a simulation first to generate an output folder.")
        }
        return AppActionSupport.pathAvailability(
            path: outputDirectory,
            expectation: .directory,
            emptyReason: "No output folder is configured.",
            missingReason: "The current output folder cannot be found on disk."
        )
    }

    func applySelectedScenario() {
        guard selectedScenarioApplicationAvailability.isEnabled else {
            appendToLog(selectedScenarioApplicationAvailability.reason ?? "Selected scenario is not ready to apply.")
            return
        }
        guard let scenario = scenarioStore.selectedScenario else { return }
        if scenario.binaryPath.isEmpty && scenario.inputFolder.isEmpty && scenario.outputFolder.isEmpty {
            appendToLog("Selected scenario is a template. Edit its paths in the governance dashboard before applying it.")
            return
        }
        binaryPath = scenario.binaryPath
        inputFolder = scenario.inputFolder
        if !scenario.outputFolder.isEmpty {
            outputFolder = scenario.outputFolder
        }
        simulationState.selectedSim = scenario.simulatorCode
        simulationState.includeRos = scenario.includeROS
        simulationState.weatherPeriodMinutes = max(1, scenario.weatherPeriodMinutes)
        simulationState.weatherPeriodInput = "\(simulationState.weatherPeriodMinutes)"
        if let format = OutputFormat(rawValue: scenario.outputFormat) {
            simulationState.outputFormat = format
        }
        simulationState.numberOfSimulations = max(1, scenario.numberOfSimulations)
        simulationState.numberOfSimulationsInput = "\(simulationState.numberOfSimulations)"
        simulationState.numberOfThreads = max(1, scenario.numberOfThreads)
        simulationState.numberOfThreadsInput = "\(simulationState.numberOfThreads)"
        simulationState.seedValue = scenario.seed
        simulationState.seedInput = "\(simulationState.seedValue)"
        refreshReviewDiscoveryRoots()
        scheduleStudyAreaExtentStatusRefresh()
    }

    func scheduleStudyAreaExtentStatusRefresh() {
        earthEngineState.studyAreaExtentRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            let message = buildStudyAreaExtentStatusMessage()
            DispatchQueue.main.async {
                earthEngineState.studyAreaExtentStatusMessage = message
            }
        }
        earthEngineState.studyAreaExtentRefreshWorkItem = workItem
        DispatchQueue.global(qos: .utility).async(execute: workItem)
    }

    func buildStudyAreaExtentStatusMessage() -> String {
        guard let gridURL = locateStudyGrid() else {
            return "fuels.asc not found in the current input folder; map extent will be used."
        }
        guard let header = readGridHeader(from: gridURL) else {
            return "Unable to read \(gridURL.lastPathComponent); map extent will be used."
        }
        if let bbox = computeStudyAreaBoundingBox(gridURL: gridURL, header: header, logFailures: false) {
            return String(format: "%@ extent: Lat %.4f..%.4f, Lon %.4f..%.4f",
                          gridURL.lastPathComponent,
                          bbox.south, bbox.north, bbox.west, bbox.east)
        }
        return "Cannot reproject \(gridURL.lastPathComponent) into WGS84 automatically; map extent will be used (install GDAL and set a CRS override if needed)."
    }

    func refreshReviewDiscoveryRoots() {
        reviewRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            reviewStore.updateDiscoveryRoots(reviewDiscoveryService.discoveryRoots(for: outputFolder))
        }
        reviewRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    func performLocationSearch() {
        let trimmed = locationSearchState.query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            locationSearchState.statusMessage = "Enter a place name or coordinate."
            return
        }

        locationSearchState.activeSearch?.cancel()
        cancelPendingSearchWork()
        locationSearchState.activeSearch = nil
        let normalizedKey = trimmed.lowercased()

        if let coordinate = coordinateFromQuery(trimmed) {
            let span = normalizedSpan(from: mapRegion)
            cacheSearchResult(for: normalizedKey, coordinate: coordinate, span: span)
            updateMapRegion(center: coordinate, span: span)
            locationSearchState.statusMessage = String(format: "Centered on %.4f, %.4f.", coordinate.latitude, coordinate.longitude)
            return
        }

        if let cached = cachedSearchResult(for: normalizedKey) {
            let span = cached.span ?? normalizedSpan(from: mapRegion)
            updateMapRegion(center: cached.coordinate, span: span)
            locationSearchState.statusMessage = "Loaded recent result for \"\(trimmed)\"."
            return
        }

        locationSearchState.isSearching = true
        locationSearchState.statusMessage = "Searching…"
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = trimmed
        request.region = mapRegion
        request.resultTypes = [.pointOfInterest, .address]
        let search = MKLocalSearch(request: request)
        locationSearchState.activeSearch = search
        scheduleFallbackGeocode(for: trimmed, normalizedKey: normalizedKey, referenceSearch: search)
        search.start { response, error in
            DispatchQueue.main.async {
                guard self.locationSearchState.activeSearch === search else { return }
                self.cancelPendingSearchWork()
                self.locationSearchState.activeSearch = nil
                self.locationSearchState.isSearching = false
                let coordinate: CLLocationCoordinate2D?
                if #available(macOS 26, *) {
                    coordinate = response?.mapItems.first?.location.coordinate
                } else {
                    coordinate = response?.mapItems.first?.placemark.coordinate
                }
                if let coordinate {
                    let span = self.normalizedSpan(from: response?.boundingRegion)
                    self.cacheSearchResult(for: normalizedKey, coordinate: coordinate, span: span)
                    self.updateMapRegion(center: coordinate, span: span)
                    if let name = response?.mapItems.first?.name, !name.isEmpty {
                        self.locationSearchState.statusMessage = "Centered on \(name)."
                    } else {
                        self.locationSearchState.statusMessage = "Centered on \(trimmed)."
                    }
                } else if let error {
                    if let mkError = error as? MKError, mkError.code == .loadingThrottled {
                        self.locationSearchState.statusMessage = "Search throttled. Please try again in a moment."
                    } else {
                        self.locationSearchState.statusMessage = "Search failed: \(error.localizedDescription)"
                    }
                } else {
                    self.locationSearchState.statusMessage = "No results for \"\(trimmed)\"."
                }
            }
        }
    }

    func currentOperationalRunConfigDocument() -> OperationalRunConfigDocument {
        let selectedScenario = scenarioStore.selectedScenario
        return OperationalRunConfigDocument(
            schemaVersion: 1,
            hazardType: "wildfire",
            exportedAt: Date(),
            binaryPath: binaryPath,
            inputFolder: inputFolder,
            outputFolder: outputFolder,
            simulatorCode: simulationState.selectedSim,
            includeROS: simulationState.includeRos,
            weatherPeriodMinutes: simulationState.weatherPeriodMinutes,
            outputFormat: simulationState.outputFormat.rawValue,
            numberOfSimulations: simulationState.numberOfSimulations,
            numberOfThreads: simulationState.numberOfThreads,
            seed: simulationState.seedValue,
            selectedScenarioID: selectedScenario?.id,
            scenarioName: selectedScenario?.name,
            tcfdScenarioLabel: selectedScenario?.tcfdScenarioLabel,
            scenarioPathway: selectedScenario?.pathwayLabel,
            scenarioHorizon: selectedScenario?.horizonLabel
        )
    }

    func exportRunConfiguration() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = runConfigService.exportFileName(at: Date())
        panel.directoryURL = URL(fileURLWithPath: outputFolder.isEmpty ? NSString(string: "~/Desktop").expandingTildeInPath : outputFolder)

        guard panel.runModal() == .OK, let destinationURL = panel.url else { return }

        do {
            let data = try runConfigService.exportData(for: currentOperationalRunConfigDocument())
            try data.write(to: destinationURL, options: .atomic)
            appendToLog("[Run Config] Exported consolidated run config to \(destinationURL.path).")
        } catch {
            appendToLog("[Run Config] Failed to export run config: \(error.localizedDescription)")
        }
    }

    func importRunConfiguration() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: NSString(string: "~/Desktop").expandingTildeInPath)

        guard panel.runModal() == .OK, let sourceURL = panel.url else { return }

        do {
            let document = try runConfigService.importDocument(from: sourceURL)
            applyImportedRunConfiguration(document)
            appendToLog("[Run Config] Imported consolidated run config from \(sourceURL.path).")
        } catch {
            appendToLog("[Run Config] Failed to import run config: \(error.localizedDescription)")
        }
    }

    func applyImportedRunConfiguration(_ document: OperationalRunConfigDocument) {
        binaryPath = document.binaryPath
        inputFolder = document.inputFolder
        outputFolder = document.outputFolder
        simulationState.selectedSim = document.simulatorCode
        simulationState.includeRos = document.includeROS
        simulationState.weatherPeriodMinutes = document.weatherPeriodMinutes
        simulationState.weatherPeriodInput = "\(document.weatherPeriodMinutes)"
        if let format = OutputFormat(rawValue: document.outputFormat) {
            simulationState.outputFormat = format
        }
        simulationState.numberOfSimulations = document.numberOfSimulations
        simulationState.numberOfSimulationsInput = "\(document.numberOfSimulations)"
        simulationState.numberOfThreads = document.numberOfThreads
        simulationState.numberOfThreadsInput = "\(document.numberOfThreads)"
        simulationState.seedValue = document.seed
        simulationState.seedInput = "\(document.seed)"

        if let scenarioID = document.selectedScenarioID,
           scenarioStore.scenarios.contains(where: { $0.id == scenarioID }) {
            scenarioStore.selectScenario(id: scenarioID)
        } else {
            scenarioStore.selectScenario(id: nil)
        }

        scheduleStudyAreaExtentStatusRefresh()
        refreshReviewDiscoveryRoots()
    }
    func normalizedSpan(from region: MKCoordinateRegion?) -> MKCoordinateSpan {
        let fallback = MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        guard let region = region else { return fallback }
        let lat = region.span.latitudeDelta
        let lon = region.span.longitudeDelta
        let validLat = max(0.01, min(lat, 40))
        let validLon = max(0.01, min(lon, 40))
        if lat.isZero || lon.isZero { return fallback }
        return MKCoordinateSpan(latitudeDelta: validLat, longitudeDelta: validLon)
    }

    func updateMapRegion(center coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        var updatedRegion = mapRegion
        updatedRegion.center = coordinate
        updatedRegion.span = span
        withAnimation(.easeInOut(duration: 0.35)) {
            mapRegion = updatedRegion
        }
    }

    func coordinateFromQuery(_ query: String) -> CLLocationCoordinate2D? {
        let allowed = CharacterSet(charactersIn: "0123456789NnSsEeWw.+-°,; \t")
        let sanitized = query.replacingOccurrences(of: "\n", with: " ")
        if sanitized.unicodeScalars.contains(where: { !allowed.contains($0) }) {
            return nil
        }

        guard let regex = try? NSRegularExpression(pattern: "([NnSsEeWw]?)\\s*(-?\\d+(?:\\.\\d+)?)(?:\\s*°)?\\s*([NnSsEeWw]?)") else {
            return nil
        }

        let fullRange = NSRange(sanitized.startIndex..<sanitized.endIndex, in: sanitized)
        let matches = regex.matches(in: sanitized, range: fullRange)
        var values: [Double] = []

        for match in matches {
            guard match.range(at: 2).location != NSNotFound,
                  let valueRange = Range(match.range(at: 2), in: sanitized) else { continue }
            let rawValue = String(sanitized[valueRange])
            guard let numeric = Double(rawValue) else { continue }

            var multiplier = 1.0
            if match.range(at: 3).location != NSNotFound,
               let trailingRange = Range(match.range(at: 3), in: sanitized),
               let char = sanitized[trailingRange].first,
               let direction = directionMultiplier(for: char) {
                multiplier = direction
            } else if match.range(at: 1).location != NSNotFound,
                      let leadingRange = Range(match.range(at: 1), in: sanitized),
                      let char = sanitized[leadingRange].first,
                      let direction = directionMultiplier(for: char) {
                multiplier = direction
            }

            values.append(numeric * multiplier)
            if values.count == 2 { break }
        }

        guard values.count == 2 else { return nil }
        let latitude = values[0]
        let longitude = values[1]
        guard (-90...90).contains(latitude), (-180...180).contains(longitude) else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func directionMultiplier(for char: Character) -> Double? {
        let lower = String(char).lowercased()
        if lower == "s" || lower == "w" { return -1 }
        if lower == "n" || lower == "e" { return 1 }
        return nil
    }

    func cacheSearchResult(for key: String,
                                   coordinate: CLLocationCoordinate2D,
                                   span: MKCoordinateSpan?) {
        let normalizedKey = key.lowercased()
        locationSearchState.cache[normalizedKey] = CachedSearchResult(coordinate: coordinate, span: span)
        locationSearchState.cacheOrder.removeAll { $0 == normalizedKey }
        locationSearchState.cacheOrder.append(normalizedKey)
        if locationSearchState.cacheOrder.count > maxCachedSearchEntries, let oldest = locationSearchState.cacheOrder.first {
            locationSearchState.cacheOrder.removeFirst()
            locationSearchState.cache.removeValue(forKey: oldest)
        }
    }

    func cachedSearchResult(for key: String) -> CachedSearchResult? {
        locationSearchState.cache[key.lowercased()]
    }

    func scheduleFallbackGeocode(for query: String,
                                         normalizedKey: String,
                                         referenceSearch: MKLocalSearch) {
        locationSearchState.fallbackWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            guard locationSearchState.isSearching, locationSearchState.activeSearch === referenceSearch else { return }
            startFallbackGeocode(for: query, normalizedKey: normalizedKey)
        }
        locationSearchState.fallbackWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: workItem)
    }

    func startFallbackGeocode(for query: String, normalizedKey: String) {
        if #available(macOS 26, *) {
            startSecondaryLocalSearch(for: query, normalizedKey: normalizedKey)
        } else {
            legacyFallbackGeocoder.cancelGeocode()
            legacyFallbackGeocoder.geocodeAddressString(query) { placemarks, error in
                DispatchQueue.main.async {
                    guard self.locationSearchState.isSearching else { return }
                    self.handleFallbackResult(coordinate: placemarks?.first?.location?.coordinate,
                                              name: placemarks?.first?.locality ?? placemarks?.first?.name ?? query,
                                              query: query,
                                              normalizedKey: normalizedKey,
                                              error: error)
                }
            }
        }
    }

    func cancelPendingSearchWork() {
        locationSearchState.fallbackWorkItem?.cancel()
        locationSearchState.fallbackWorkItem = nil
        if #available(macOS 26, *) {
            // no legacy geocoder to cancel
        } else {
            legacyFallbackGeocoder.cancelGeocode()
        }
    }

    @available(macOS 26, *)
    func startSecondaryLocalSearch(for query: String, normalizedKey: String) {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = query
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(center: mapRegion.center,
                                            span: MKCoordinateSpan(latitudeDelta: 120, longitudeDelta: 360))
        let backupSearch = MKLocalSearch(request: request)
        backupSearch.start { response, error in
            DispatchQueue.main.async {
                guard self.locationSearchState.isSearching else { return }
                let coordinate = response?.mapItems.first?.location.coordinate
                let name = response?.mapItems.first?.name ?? query
                self.handleFallbackResult(coordinate: coordinate,
                                          name: name,
                                          query: query,
                                          normalizedKey: normalizedKey,
                                          error: error)
            }
        }
    }

    func handleFallbackResult(coordinate: CLLocationCoordinate2D?,
                                      name: String?,
                                      query: String,
                                      normalizedKey: String,
                                      error: Error?) {
        cancelPendingSearchWork()
        locationSearchState.activeSearch = nil
        locationSearchState.isSearching = false
        if let coordinate {
            let span = normalizedSpan(from: nil)
            cacheSearchResult(for: normalizedKey, coordinate: coordinate, span: span)
            updateMapRegion(center: coordinate, span: span)
            let label = name ?? query
            locationSearchState.statusMessage = "Centered on \(label) (backup lookup)."
        } else if let error {
            locationSearchState.statusMessage = "Search failed (backup geocoder): \(error.localizedDescription)"
        } else {
            locationSearchState.statusMessage = "No results for \"\(query)\"."
        }
    }

    func restoreOverlaySnapshotIfNeeded() {
        guard let snapshot = overlayState.overlaySnapshotBeforeRun else {
            outputStore.clearLoadingState()
            return
        }
        outputStore.clearLoadingState()
        overlayState.overlaySnapshotBeforeRun = nil
        overlayState.lastOverlayASCIIURL = snapshot.asciiURL
        overlayState.lastOverlaySourceURL = snapshot.sourceURL
        overlayState.lastOverlayGrid = snapshot.grid
        if let overlay = snapshot.overlay {
            overlayState.rosOverlay = overlay
            refreshIgnitionMarkers(with: overlay)
        } else {
            refreshIgnitionMarkers(with: nil)
        }
    }

    func logSimulationSummary(_ summary: RunSummary) {
        var lines: [String] = []
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        lines.append("")
        lines.append("------ Simulation Summary (\(formatter.string(from: summary.timestamp))) ------")
        for stats in summary.simulations {
            lines.append("Simulation \(stats.simulationIndex) Results:")
            lines.append("Cell Status        Count      Percent")
            lines.append("---------------------------------------")
            let total = stats.resolvedTotal ?? [stats.available, stats.burnt, stats.nonBurnable, stats.firebreak].compactMap { $0 }.reduce(0, +)
            lines.append(tableRow(label: "Available",
                                  count: stats.available,
                                  total: total))
            lines.append(tableRow(label: "Burnt",
                                  count: stats.burnt,
                                  total: total))
            lines.append(tableRow(label: "Non-Burnable",
                                  count: stats.nonBurnable,
                                  total: total))
            lines.append(tableRow(label: "Firebreak",
                                  count: stats.firebreak,
                                  total: total))
            lines.append(tableRow(label: "Total",
                                  count: stats.resolvedTotal ?? total,
                                  total: total,
                                  forceHundred: true))
            lines.append("")
            if let weatherFile = stats.weatherFile, !weatherFile.isEmpty {
                lines.append("Weather File: \(weatherFile)")
            }
            if let ignitionCell = stats.ignitionCell {
                lines.append("Ignition Cell: \(ignitionCell)")
            }
            if let highest = stats.highestROS {
                lines.append(String(format: "Highest ROS: %.3f m/min", highest))
            }
            if let lowest = stats.lowestROS {
                lines.append(String(format: "Lowest ROS: %.3f m/min", lowest))
            }
            lines.append("")
        }
        appendToLog(lines.joined(separator: "\n"))
    }

    func appendOutputTailIfNeeded(from stdout: String) {
        let allLines = stdout.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard !allLines.isEmpty else { return }
        let filteredLines = allLines.filter {
            !$0.contains("FuelModelSpain: spain_lookup_table.csv is empty; fm_parameters will not be populated")
        }
        let source = filteredLines.isEmpty ? allLines : filteredLines
        let tail = source.suffix(3000).joined(separator: "\n")
        appendToLog("\n------ Cell2Fire Console Tail ------\n\(tail)\n")
    }

    func tableRow(label: String,
                          count: Int?,
                          total: Int,
                          forceHundred: Bool = false) -> String {
        let countString = formattedCount(count)
        let percentString: String
        if forceHundred {
            percentString = total > 0 ? "100.00%" : "—"
        } else if let count, total > 0 {
            let percent = (Double(count) / Double(total)) * 100
            percentString = String(format: "%6.2f%%", percent)
        } else {
            percentString = "   —"
        }
        let paddedLabel = (label as NSString).padding(toLength: 16, withPad: " ", startingAt: 0)
        let paddedCount = countString.padding(toLength: 8, withPad: " ", startingAt: 0)
        return "\(paddedLabel) \(paddedCount)    \(percentString)"
    }

    func fetchEarthEngineOverlay() {
        guard !earthEngineState.isFetching else { return }
        guard canFetchEarthEngine else {
            earthEngineState.statusMessage = "Fill in the dataset, band, dates, key, and script path."
            return
        }

        let scriptPath = NSString(string: earthEngineScriptPath).expandingTildeInPath
        let keyPath = NSString(string: earthEngineKeyPath).expandingTildeInPath
        let fm = FileManager.default
        guard fm.fileExists(atPath: scriptPath) else {
            earthEngineState.statusMessage = "Helper script not found at \(scriptPath)."
            return
        }
        guard fm.isExecutableFile(atPath: scriptPath) else {
            earthEngineState.statusMessage = "Make the helper executable (chmod +x \(scriptPath))."
            return
        }
        guard fm.fileExists(atPath: keyPath) else {
            earthEngineState.statusMessage = "Key file missing at \(keyPath)."
            return
        }
        guard let overlaysDir = overlaysDirectory() else {
            earthEngineState.statusMessage = "Unable to prepare the overlays directory."
            return
        }

        var demDestination: URL?
        if earthEngineMode == .dem {
            let trimmedInput = inputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedInput.isEmpty else {
                earthEngineState.statusMessage = "Set the Cell2Fire input folder before importing a DEM."
                return
            }
            let expandedInput = NSString(string: trimmedInput).expandingTildeInPath
            var isDir: ObjCBool = false
            if !fm.fileExists(atPath: expandedInput, isDirectory: &isDir) || !isDir.boolValue {
                earthEngineState.statusMessage = "Input folder not found for DEM copy."
                return
            }
            let demName = sanitizedDEMFilename(earthEngineDemFilename)
            demDestination = URL(fileURLWithPath: expandedInput).appendingPathComponent(demName)
        }

        let trimmedAccount = earthEngineServiceAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDataset = earthEngineDataset.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBand = earthEngineBand.trimmingCharacters(in: .whitespacesAndNewlines)
        let startDate = earthEngineStartDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let endDate = earthEngineEndDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let scaleMeters = max(1.0, min(Double(earthEngineScaleInput) ?? 10.0, 5000))
        earthEngineScaleInput = String(format: "%.2f", scaleMeters)

        let bbox: (west: Double, south: Double, east: Double, north: Double)
        if useStudyAreaBounds {
            guard let derived = studyAreaBoundingBox() else {
                earthEngineState.statusMessage = "Cannot derive study area extent; verify fuels.asc exists in WGS84."
                return
            }
            bbox = derived
        } else {
            bbox = boundingBox(for: mapRegion)
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withTime, .withColonSeparatorInTime, .withTimeZone]
        let filename = "earthengine-\(formatter.string(from: Date())).asc"
        let outputURL = overlaysDir.appendingPathComponent(filename)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        let arguments = [
            "python3",
            scriptPath,
            "--service-account", trimmedAccount,
            "--key", keyPath,
            "--dataset", trimmedDataset,
            "--band", trimmedBand,
            "--start-date", startDate,
            "--end-date", endDate,
            "--scale", String(scaleMeters),
            "--bbox",
            String(bbox.west),
            String(bbox.south),
            String(bbox.east),
            String(bbox.north),
            "--output", outputURL.path,
            "--format", "asc"
        ]
        process.arguments = arguments
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe

        earthEngineState.statusMessage = "Requesting imagery…"
        earthEngineState.isFetching = true
        appendToLog("[Earth Engine] Fetching \(trimmedDataset) / \(trimmedBand) at \(scaleMeters)m.")

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                try process.run()
            } catch {
                let message = "Failed to launch helper: \(error.localizedDescription)"
                DispatchQueue.main.async {
                    earthEngineState.isFetching = false
                    earthEngineState.statusMessage = message
                    appendToLog("[Earth Engine] \(message)")
                }
                return
            }

            process.waitUntilExit()
            let stdout = String(data: stdoutPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let stderr = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

            DispatchQueue.main.async {
                earthEngineState.isFetching = false
                guard process.terminationStatus == 0 else {
                    let message = stderr.isEmpty ? "Helper exited with code \(process.terminationStatus)." : stderr
                    earthEngineState.statusMessage = message
                    appendToLog("[Earth Engine] \(message)")
                    return
                }

                if !stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    appendToLog("[Earth Engine] \(stdout)")
                }

                var overlayToDisplay = outputURL
                if let destination = demDestination {
                    do {
                        if fm.fileExists(atPath: destination.path) {
                            try fm.removeItem(at: destination)
                        }
                        try fm.copyItem(at: outputURL, to: destination)
                        overlayToDisplay = destination
                        appendToLog("[Earth Engine] DEM saved to \(destination.path).")
                        earthEngineState.statusMessage = "DEM saved to \(destination.lastPathComponent)."
                    } catch {
                        let message = "Failed to copy DEM into input folder: \(error.localizedDescription)"
                        earthEngineState.statusMessage = message
                        appendToLog("[Earth Engine] \(message)")
                    }
                } else {
                    earthEngineState.statusMessage = "Loaded \(outputURL.lastPathComponent)."
                }

                loadOverlay(from: overlayToDisplay,
                            zoomAfterLoad: true,
                            successMessage: "Loaded Earth Engine layer from")
                refreshOutputTree()
            }
        }
    }

    func boundingBox(for region: MKCoordinateRegion) -> (west: Double, south: Double, east: Double, north: Double) {
        let halfLat = max(min(region.span.latitudeDelta / 2, 90), 0.0005)
        let halfLon = max(min(region.span.longitudeDelta / 2, 180), 0.0005)
        var north = region.center.latitude + halfLat
        var south = region.center.latitude - halfLat
        var east = region.center.longitude + halfLon
        var west = region.center.longitude - halfLon
        north = min(90, max(-90, north))
        south = min(90, max(-90, south))
        east = min(180, max(-180, east))
        west = min(180, max(-180, west))
        return (west, south, east, north)
    }

    struct ASCIIGridHeader {
        let ncols: Int
        let nrows: Int
        let xOrigin: Double
        let yOrigin: Double
        let cellSize: Double
    }

    func locateStudyGrid() -> URL? {
        let trimmed = inputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDir), isDir.boolValue else {
            return nil
        }
        let baseURL = URL(fileURLWithPath: expanded, isDirectory: true)
        let preferredNames = ["fuels.asc", "fuel.asc", "Fuels.asc", "Fuel.asc"]
        for name in preferredNames {
            let candidate = baseURL.appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return candidate
            }
        }
        if let contents = try? FileManager.default.contentsOfDirectory(at: baseURL,
                                                                       includingPropertiesForKeys: nil,
                                                                       options: [.skipsHiddenFiles]) {
            return contents.first {
                $0.pathExtension.lowercased() == "asc" &&
                $0.deletingPathExtension().lastPathComponent.lowercased().contains("fuel")
            }
        }
        return nil
    }

    func readGridHeader(from url: URL) -> ASCIIGridHeader? {
        guard let lines = readASCIIHeaderLines(from: url, maxBytes: 16_384, maxLines: 16) else {
            return nil
        }
        var header: [String: Double] = [:]
        let keys: Set<String> = ["ncols", "nrows", "xllcorner", "yllcorner", "xllcenter", "yllcenter", "cellsize", "nodata_value"]
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            let parts = trimmed.split { $0 == " " || $0 == "\t" }
            guard parts.count >= 2 else { break }
            let key = parts[0].lowercased()
            if keys.contains(key), let value = Double(parts[1]) {
                header[key] = value
            } else {
                break
            }
        }

        guard let ncolsValue = header["ncols"],
              let nrowsValue = header["nrows"],
              let cellSize = header["cellsize"],
              let xll = header["xllcorner"] ?? header["xllcenter"],
              let yll = header["yllcorner"] ?? header["yllcenter"] else {
            return nil
        }
        let ncols = Int(ncolsValue)
        let nrows = Int(nrowsValue)
        guard ncols > 0, nrows > 0, cellSize > 0 else { return nil }
        return ASCIIGridHeader(ncols: ncols, nrows: nrows, xOrigin: xll, yOrigin: yll, cellSize: cellSize)
    }

    func readASCIIHeaderLines(from url: URL,
                                      maxBytes: Int,
                                      maxLines: Int) -> [Substring]? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        let data = handle.readData(ofLength: maxBytes)
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }

        return Array(text.split(whereSeparator: \.isNewline).prefix(maxLines))
    }

    func rawBoundingBox(from header: ASCIIGridHeader) -> (west: Double, south: Double, east: Double, north: Double) {
        let west = header.xOrigin
        let south = header.yOrigin
        let east = west + header.cellSize * Double(header.ncols)
        let north = south + header.cellSize * Double(header.nrows)
        return (west, south, east, north)
    }

    func reprojectBoundingBox(header: ASCIIGridHeader,
                                      projection: ProjectionInfo,
                                      fileName: String,
                                      logFailures: Bool) -> (west: Double, south: Double, east: Double, north: Double)? {
        guard let executable = locateGDALTransform() else {
            if logFailures {
                appendToLog("[Earth Engine] gdaltransform is required to convert \(fileName) bounds into WGS84. Install GDAL (e.g., `brew install gdal`).")
            }
            return nil
        }
        let raw = rawBoundingBox(from: header)
        let points = [
            "\(raw.west) \(raw.south) 0",
            "\(raw.west) \(raw.north) 0",
            "\(raw.east) \(raw.south) 0",
            "\(raw.east) \(raw.north) 0"
        ].joined(separator: "\n") + "\n"

        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["-s_srs", projection.srs, "-t_srs", "EPSG:4326"]
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
        } catch {
            if logFailures {
                appendToLog("[Earth Engine] Unable to run gdaltransform: \(error.localizedDescription)")
            }
            return nil
        }

        if let data = points.data(using: .utf8) {
            inputPipe.fileHandleForWriting.write(data)
        }
        try? inputPipe.fileHandleForWriting.close()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            if logFailures {
                let stderr = String(data: errorPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                appendToLog("[Earth Engine] gdaltransform failed for \(fileName): \(stderr)")
            }
            return nil
        }

        let output = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let lines = output.split(whereSeparator: \.isNewline).prefix(4)
        guard !lines.isEmpty else { return nil }
        var minLon = Double.infinity
        var maxLon = -Double.infinity
        var minLat = Double.infinity
        var maxLat = -Double.infinity

        for line in lines {
            let components = line.split { $0 == " " || $0 == "\t" }
            guard components.count >= 2,
                  let lon = Double(components[0]),
                  let lat = Double(components[1]) else { continue }
            minLon = min(minLon, lon)
            maxLon = max(maxLon, lon)
            minLat = min(minLat, lat)
            maxLat = max(maxLat, lat)
        }

        guard minLon.isFinite, maxLon.isFinite, minLat.isFinite, maxLat.isFinite else {
            return nil
        }
        return (minLon, minLat, maxLon, maxLat)
    }

    func studyAreaBoundingBox() -> (west: Double, south: Double, east: Double, north: Double)? {
        guard let gridURL = locateStudyGrid(),
              let header = readGridHeader(from: gridURL) else { return nil }
        return computeStudyAreaBoundingBox(gridURL: gridURL, header: header, logFailures: true)
    }

    func computeStudyAreaBoundingBox(gridURL: URL,
                                             header: ASCIIGridHeader,
                                             logFailures: Bool) -> (west: Double, south: Double, east: Double, north: Double)? {
        let raw = rawBoundingBox(from: header)
        if let projection = projectionInfo(for: gridURL, logFailures: logFailures) {
            if projection.isWGS84 {
                return raw
            }
            return reprojectBoundingBox(header: header,
                                        projection: projection,
                                        fileName: gridURL.lastPathComponent,
                                        logFailures: logFailures)
        } else {
            let lonRange = -180.0...180.0
            let latRange = -90.0...90.0
            guard lonRange.contains(raw.west),
                  lonRange.contains(raw.east),
                  latRange.contains(raw.south),
                  latRange.contains(raw.north) else {
                if logFailures {
                    appendToLog("[Earth Engine] \(gridURL.lastPathComponent) appears to be projected. Include a .prj file or set a CRS override so Climate Liberator can convert it to WGS84.")
                }
                return nil
            }
            return raw
        }
    }

    func sanitizedDEMFilename(_ proposed: String) -> String {
        var name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "elevation.asc" }
        let invalid = CharacterSet(charactersIn: "/\\:")
        name = name.components(separatedBy: invalid).joined(separator: "_")
        if !name.lowercased().hasSuffix(".asc") {
            name += ".asc"
        }
        return name
    }
}
