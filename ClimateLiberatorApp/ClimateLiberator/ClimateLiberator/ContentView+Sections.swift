import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

extension ContentView {

    var mainCard: some View {
        OperationsWorkspaceView(
            style: WorkspaceSectionStyle(
                textColor: theme.textColor,
                subtleTextColor: theme.subtleTextColor,
                material: theme.material,
                cardTint: theme.cardBackground,
                panelTint: theme.editorBackground,
                borderColor: theme.borderColor,
                shadowColor: theme.shadowColor
            ),
            controlsExpanded: controlsExpanded,
            onToggleExpanded: toggleControlPanel
        ) {
            Picker("Theme", selection: $theme) {
                ForEach(ThemeStyle.allCases) { style in
                    Text(style.displayName).tag(style)
                }
            }
            .pickerStyle(.segmented)
        } siteContent: {
            VStack(alignment: .leading, spacing: 18) {
                searchCard
                earthEngineCard
                indiaSiteLookupSection
            }
        } inputsContent: {
            VStack(alignment: .leading, spacing: 18) {
                environmentSection
                scenarioWorkflowSection
                dashboardPanelCard(title: "India Preparedness Checklist",
                                   subtitle: "Prepared-instance validation for India-first wildfire studies. Keep this with simulation setup, not portfolio screening.") {
                    indiaWildfireReadinessPanel
                }
            }
        } runContent: {
            runSetupSection
        } outputsContent: {
            resultsSection
        } logsContent: {
            VStack(alignment: .leading, spacing: 18) {
                dashboardPanelCard(title: "Recent Simulation Activity",
                                   subtitle: "Latest wildfire runs captured in the current session.") {
                    recentSimulationActivityPanel
                }
                logSection
            }
        }
    }

    var dashboardWorkspaceView: some View {
        DashboardWorkspaceView(
            enterpriseReadiness: enterpriseReadinessSummary,
            openClimateSimulation: {
                activeWorkspace = .operations
            },
            openForecastIntelligence: { openWindow(id: "forecast-intelligence") },
            openTCFDDashboard: { openWindow(id: "tcfd-dashboard") },
            openCommandCenter: {
                activeWorkspace = .commandCenter
            },
            openPortfolioIntelligence: {
                activeWorkspace = .intelligence
            }
        )
    }

    var commandCenterWorkspaceView: some View {
        CommandCenterWorkspaceView(
            scenarioStore: scenarioStore,
            reviewStore: reviewStore,
            forecastStore: forecastStore,
            activeWorkspace: $activeWorkspace,
            theme: theme,
            enterpriseReadiness: enterpriseReadinessSummary,
            latestDisclosureReportAvailability: latestDisclosureReportAvailability,
            logActionAvailability: logActionAvailability,
            operationsWorkspaceAvailability: operationsWorkspaceAvailability,
            portfolioIntelligenceAvailability: portfolioIntelligenceAvailability,
            disclosureReviewAvailability: disclosureReviewAvailability,
            openTCFDDashboard: { openWindow(id: "tcfd-dashboard") },
            openForecastIntelligence: { openWindow(id: "forecast-intelligence") },
            openOperationsLog: {
                activeWorkspace = .operations
                simulationState.showLogSheet = true
            }
        )
    }

    var enterpriseReadinessSummary: EnterpriseReadinessSummary {
        enterprisePlatform
            .dashboard
            .fetchSummary(request: EnterpriseDashboardSummaryRequest(outputFolder: outputFolder))
            .readinessSummary
    }

    var intelligenceWorkspaceView: some View {
        PortfolioIntelligenceWorkspaceView(
            indiaRiskStore: indiaRiskStore,
            exposureIntakeStore: exposureIntakeStore,
            mapRegion: $mapRegion,
            activeWorkspace: $activeWorkspace,
            theme: theme,
            openTCFDDashboard: { openWindow(id: "tcfd-dashboard") }
        )
    }

    func executiveMetricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.72))
            Text(value)
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text(detail)
                .font(.footnote)
                .foregroundColor(Color.white.opacity(0.68))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    func dashboardPanelCard<Content: View>(title: String,
                                                   subtitle: String,
                                                   @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.title3.bold())
                .foregroundColor(.white)
            Text(subtitle)
                .font(.footnote)
                .foregroundColor(Color.white.opacity(0.72))
            content()
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    var indiaWildfireReadinessPanel: some View {
        let checks = indiaWildfireReadinessChecks
        let readyCount = checks.filter(\.isReady).count

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                executiveMetricCard(title: "Checklist",
                                    value: "\(readyCount)/\(checks.count)",
                                    detail: indiaWildfireSimulationReadinessMessage)
                executiveMetricCard(title: "Current Input",
                                    value: inputFolder.isEmpty ? "Not set" : URL(fileURLWithPath: inputFolder).lastPathComponent,
                                    detail: "Prepared wildfire study folder")
            }

            ForEach(checks) { check in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: check.isReady ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                        .foregroundColor(check.isReady ? .green : .orange)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(check.title)
                            .font(.headline)
                            .foregroundColor(.white)
                        Text(check.detail)
                            .font(.footnote)
                            .foregroundColor(Color.white.opacity(0.72))
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color.white.opacity(0.05))
                )
            }

            Text("Accepted India wildfire bundle: fuels, terrain/elevation context, weather source, ignition source, CRS metadata, and study boundary. Climate Liberator does not yet auto-generate nationwide wildfire-ready inputs for India.")
                .font(.footnote)
                .foregroundColor(Color.white.opacity(0.72))
        }
    }

    var recentSimulationActivityPanel: some View {
        Group {
            if simulationState.runSummaries.isEmpty {
                Text("No simulation has been completed in this session yet.")
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.72))
            } else {
                ForEach(simulationState.runSummaries.prefix(3)) { summary in
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(summary.timestamp.formatted(date: .abbreviated, time: .shortened))
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("\(summary.simulations.count) simulation result(s)")
                                .font(.footnote)
                                .foregroundColor(Color.white.opacity(0.72))
                        }
                        Spacer()
                        Text(aggregatedBurnt(for: summary).map { formattedCount($0) } ?? "—")
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.white)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                    )
                }
            }
        }
    }

    var indiaWildfireReadinessChecks: [IndiaWildfireReadinessCheck] {
        let normalizedInput = NSString(string: inputFolder.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        let inputURL = URL(fileURLWithPath: normalizedInput)
        let fm = FileManager.default
        let inputFolderExists = !normalizedInput.isEmpty && fm.fileExists(atPath: inputURL.path)

        let fuelsURL = preferredInputFile(in: inputURL, candidates: ["fuels.asc", "fuels.tif", "fuel.asc", "fuel.tif"])
        let weatherReady = preferredInputFile(in: inputURL, candidates: ["Weather.csv", "weather.csv"]) != nil ||
            fm.fileExists(atPath: inputURL.appendingPathComponent("Weathers", isDirectory: true).path)
        let ignitionReady = fm.fileExists(atPath: inputURL.appendingPathComponent("Ignitions.csv").path) ||
            !overlayState.ignitionMarkers.isEmpty ||
            overlayState.currentIgnitionCell != nil
        let terrainFiles = [
            preferredInputFile(in: inputURL, candidates: ["elevation.asc", "elevation.tif", "dem.asc", "dem.tif"]),
            preferredInputFile(in: inputURL, candidates: ["slope.asc", "slope.tif"]),
            preferredInputFile(in: inputURL, candidates: ["aspect.asc", "aspect.tif"])
        ]
        let terrainReady = terrainFiles.contains { $0 != nil }
        let crsReady = fuelsURL.flatMap { projectionInfo(for: $0, logFailures: false) } != nil

        return [
            IndiaWildfireReadinessCheck(title: "Study area selected",
                                        isReady: inputFolderExists,
                                        detail: inputFolderExists ? "Prepared study folder found at \(inputURL.lastPathComponent)." : "Choose a valid prepared study folder before running a wildfire scenario."),
            IndiaWildfireReadinessCheck(title: "Fuel layer present",
                                        isReady: fuelsURL != nil,
                                        detail: fuelsURL != nil ? "Fuel grid detected in the prepared instance." : "Expected `fuels.asc` or `fuels.tif` in the prepared study folder."),
            IndiaWildfireReadinessCheck(title: "Terrain context present",
                                        isReady: terrainReady,
                                        detail: terrainReady ? "Elevation or terrain-derived context was found." : "Add elevation, DEM, slope, or aspect layers for India study preparation."),
            IndiaWildfireReadinessCheck(title: "Weather source present",
                                        isReady: weatherReady,
                                        detail: weatherReady ? "Weather rows are available for the current study." : "Add `Weather.csv`, `weather.csv`, or a `Weathers/` folder."),
            IndiaWildfireReadinessCheck(title: "Ignition source chosen",
                                        isReady: ignitionReady,
                                        detail: ignitionReady ? "Ignition CSV or manual ignition context is available." : "Add `Ignitions.csv` or choose ignition points before running."),
            IndiaWildfireReadinessCheck(title: "CRS valid",
                                        isReady: crsReady,
                                        detail: crsReady ? "Climate Liberator can resolve the current study CRS." : "Provide a `.prj` file or use the CRS override so the study can be aligned correctly.")
        ]
    }

    var indiaWildfireSimulationReadinessMessage: String {
        let checks = indiaWildfireReadinessChecks
        return checks.allSatisfy(\.isReady)
            ? "Simulation-ready for a prepared India wildfire study."
            : "Ready only when all prepared wildfire inputs are present and aligned."
    }

    func preferredInputFile(in folder: URL, candidates: [String]) -> URL? {
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        return candidates
            .map { folder.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    var searchCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Map Search")
                .font(.headline)
            HStack(spacing: 8) {
                TextField("Find a place or coordinates", text: $locationSearchState.query)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                    .onSubmit { performLocationSearch() }
                    .onChange(of: locationSearchState.query) { _, newValue in
                        if newValue.isEmpty {
                            DispatchQueue.main.async {
                                locationSearchState.statusMessage = nil
                            }
                        }
                    }
                Button(action: performLocationSearch) {
                    if locationSearchState.isSearching {
                        ProgressView()
                            .controlSize(.small)
                            .frame(minWidth: 50)
                    } else {
                        Label("Search", systemImage: "magnifyingglass")
                            .labelStyle(.titleAndIcon)
                            .frame(minWidth: 80)
                    }
                }
                .disabled(locationSearchState.isSearching || locationSearchState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
            if let status = locationSearchState.statusMessage {
                Text(status)
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            }
        }
        .foregroundColor(theme.textColor)
        .padding(18)
        .glassBackground(material: theme.material,
                         tint: theme.cardBackground,
                         cornerRadius: 24,
                         strokeColor: theme.borderColor)
    }

    var earthEngineCard: some View {
        DisclosureGroup(isExpanded: $earthEngineExpanded) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Import Sentinel, Landsat, DEM or other rasters directly from your non-commercial Earth Engine account. The helper writes into the private overlays folder so nothing lands in Git.")
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
                TextField("Dataset ID (e.g., COPERNICUS/S2_SR)", text: $earthEngineDataset)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                HStack(spacing: 10) {
                    TextField("Band (e.g., B04)", text: $earthEngineBand)
                        .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                    TextField("Scale (m)", text: $earthEngineScaleInput)
                        .frame(width: 100)
                        .multilineTextAlignment(.trailing)
                        .onChange(of: earthEngineScaleInput) { _, newValue in
                            let filtered = newValue.filter { "0123456789.".contains($0) }
                            if filtered != newValue {
                                earthEngineScaleInput = filtered
                            }
                        }
                        .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                }
                HStack(spacing: 10) {
                    TextField("Start date (YYYY-MM-DD)", text: $earthEngineStartDate)
                        .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                    TextField("End date (YYYY-MM-DD)", text: $earthEngineEndDate)
                        .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                }
                TextField("Service account email", text: $earthEngineServiceAccount)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                TextField("Key path (outside Git)", text: $earthEngineKeyPath)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                TextField("Helper script path", text: $earthEngineScriptPath)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                Picker("Target", selection: $earthEngineModeRaw) {
                    ForEach(EarthEngineTarget.allCases) { mode in
                        Text(mode.label).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                HStack {
                    Toggle(isOn: $useStudyAreaBounds) {
                        Text("Use study area extent (fuels.asc)")
                    }
                    .toggleStyle(SwitchToggleStyle(tint: theme.accentColor))
                    Button {
                        earthEngineState.showExtentInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundColor(theme.subtleTextColor)
                }
                Text(studyAreaExtentStatus)
                    .font(.caption2)
                    .foregroundColor(theme.subtleTextColor)
                if earthEngineMode == .dem {
                    Text("DEM outputs are copied into your Cell2Fire input folder so future runs stop filling elevation with NaN.")
                        .font(.footnote)
                        .foregroundColor(theme.subtleTextColor)
                    TextField("DEM file name (e.g., elevation.asc)", text: $earthEngineDemFilename)
                        .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                }
                Button(earthEngineState.isFetching ? "Fetching…" : "Fetch from Earth Engine") {
                    fetchEarthEngineOverlay()
                }
                .disabled(!earthEngineActionAvailability.isEnabled)
                .buttonStyle(.borderedProminent)
                if let status = earthEngineState.statusMessage {
                    Text(status)
                        .font(.footnote)
                        .foregroundColor(theme.subtleTextColor)
                } else if let reason = earthEngineActionAvailability.reason, !earthEngineActionAvailability.isEnabled {
                    Text(reason)
                        .font(.footnote)
                        .foregroundColor(theme.subtleTextColor)
                }
            }
        } label: {
            HStack {
                Text("Google Earth Engine")
                    .font(.headline)
                Spacer()
                if earthEngineState.isFetching {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .foregroundColor(theme.textColor)
        .padding(18)
        .glassBackground(material: theme.material,
                         tint: theme.cardBackground,
                         cornerRadius: 24,
                         strokeColor: theme.borderColor)
    }

    var mapModeControls: some View {
        VStack(spacing: 12) {
            MapModeButton(icon: mapVisible ? "map.fill" : "map",
                          label: mapVisible ? "Hide" : "Map",
                          active: mapVisible,
                          theme: theme) {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    mapVisible.toggle()
                }
            }

            if mapVisible {
                CompassButton(angle: mapHeading,
                              theme: theme) {
                    mapController.resetHeading()
                }

                MapModeButton(icon: useSatelliteView ? "globe.europe.africa.fill" : "globe.europe.africa",
                              label: "Satellite",
                              active: useSatelliteView,
                              theme: theme) {
                    useSatelliteView.toggle()
                }
                MapModeButton(icon: enable3DView ? "cube.fill" : "cube",
                              label: "3D",
                              active: enable3DView,
                              theme: theme) {
                    enable3DView.toggle()
                }
                MapModeButton(icon: overlayState.inspectMode ? "viewfinder.circle.fill" : "viewfinder.circle",
                              label: "Identify",
                              active: overlayState.inspectMode,
                              theme: theme) {
                    overlayState.inspectMode.toggle()
                    if !overlayState.inspectMode {
                        overlayState.inspectResult = nil
                    }
                }
            }
        }
    }

    var environmentSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SettingRow(title: "Cell2Fire Binary", theme: theme) {
                TextField("/path/to/Cell2Fire", text: $binaryPath)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                Button("Choose…") { showingBinaryPicker = true }
            }

            SettingRow(title: "Input Folder", theme: theme) {
                TextField("Input instance folder", text: $inputFolder)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                Button("Choose…") { showingFolderPicker = true }
            }

            SettingRow(title: "Output Folder", theme: theme) {
                TextField("Choose a writable directory", text: $outputFolder)
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
                Button("Choose…") { showingOutputPicker = true }
            }
            Text("Choose the directory where Cell2Fire should write RateOfSpread outputs.")
                .font(.footnote)
                .foregroundColor(theme.subtleTextColor)

            Picker("Fuel Model", selection: $simulationState.selectedSim) {
                ForEach(simOptions, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.segmented)

            Toggle("Generate ROS output", isOn: $simulationState.includeRos)

            Picker("ROS output format", selection: $simulationState.outputFormat) {
                ForEach(OutputFormat.allCases) { format in
                    Text(format.label).tag(format)
                }
            }
            .pickerStyle(.segmented)

            weatherIntervalSection

            if let warning = validateEnvironment() {
                Text("⚠️ \(warning)")
                    .font(.footnote)
                    .foregroundColor(.yellow)
            }
        }
    }

    var scenarioWorkflowSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                if scenarioStore.scenarios.isEmpty {
                    Text("No saved scenarios yet. Open the governance dashboard to create one.")
                        .font(.footnote)
                        .foregroundColor(theme.subtleTextColor)
                } else {
                    Picker("Saved Scenario", selection: scenarioSelectionBinding) {
                        Text("None").tag(nil as ScenarioDefinition.ID?)
                        ForEach(scenarioStore.scenarios) { scenario in
                            Text(scenario.name).tag(Optional(scenario.id))
                        }
                    }
                    .pickerStyle(.menu)

                    if let selected = scenarioStore.selectedScenario {
                        Text(selected.tcfdScenarioLabel)
                            .font(.caption)
                            .foregroundColor(theme.subtleTextColor)
                    }
                }

                HStack {
                    Button("Apply Selected Scenario") {
                        applySelectedScenario()
                    }
                    .disabled(!selectedScenarioApplicationAvailability.isEnabled)

                    Button("Open TCFD Dashboard") {
                        openWindow(id: "tcfd-dashboard")
                    }
                    .buttonStyle(.bordered)
                }

                if let reason = selectedScenarioApplicationAvailability.reason, !selectedScenarioApplicationAvailability.isEnabled {
                    Text(reason)
                        .font(.footnote)
                        .foregroundColor(theme.subtleTextColor)
                }
            }
        }
    }

    var indiaSiteLookupSection: some View {
        IndiaSiteLookupView(
            store: indiaRiskStore,
            currentCoordinate: mapRegion.center,
            onRefreshNearby: {
                indiaRiskStore.lookupNearbyBuildings(
                    latitude: mapRegion.center.latitude,
                    longitude: mapRegion.center.longitude
                )
            }
        )
    }

    var runSetupSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button("Import Run Config") {
                    importRunConfiguration()
                }
                .buttonStyle(.bordered)

                Button("Export Run Config") {
                    exportRunConfiguration()
                }
                .buttonStyle(.bordered)
            }

            simulationSettings

            HStack(spacing: 12) {
                Button(simulationState.isRunning ? "Running…" : "Run Simulation") {
                    run()
                }
                .disabled(!runActionAvailability.isEnabled)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                if simulationState.isRunning {
                    Button("Stop Run") {
                        simulationEngineService.cancel()
                        appendToLog("[Run] Stop requested. Waiting for the active simulation engine to terminate.")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
            }

            if let reason = runActionAvailability.reason, !runActionAvailability.isEnabled {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            }
        }
    }

    var resultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Button(simulationState.isExportingKMZ ? "Exporting GIS Footprint…" : "Export GIS Footprint (KMZ)") {
                    exportKMZ()
                }
                .disabled(!exportActionAvailability.isEnabled)
                .buttonStyle(.borderedProminent)

                Button("Open Output Folder") {
                    if let path = simulationState.lastOutputDirectory {
                        _ = AppActionSupport.openExistingPath(path, expectation: .directory)
                    }
                }
                .disabled(!openOutputFolderAvailability.isEnabled)
                .buttonStyle(.bordered)

                Button("Open Latest Evidence Package") {
                    if let path = reviewStore.bundles.first?.bundleURL {
                        _ = AppActionSupport.openExistingPath(path, expectation: .directory)
                    }
                }
                .disabled(!latestEvidencePackageAvailability.isEnabled)
                .buttonStyle(.bordered)
            }

            if let reason = exportActionAvailability.reason, !exportActionAvailability.isEnabled {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            }
            if let reason = openOutputFolderAvailability.reason, !openOutputFolderAvailability.isEnabled {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            }
            if let reason = latestEvidencePackageAvailability.reason, !latestEvidencePackageAvailability.isEnabled {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            }

            crsOverrideSection
            outputExplorer
        }
    }

    var crsOverrideSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $useOverrideCRS) {
                HStack(spacing: 4) {
                    Text("Override ROS CRS (EPSG)")
                    Button {
                        showCRSInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                }
            }
            .toggleStyle(SwitchToggleStyle(tint: theme.accentColor))

            TextField("e.g., 28998 or EPSG:28992", text: $overrideCRSCode)
                .textFieldStyle(.roundedBorder)
                .disabled(!useOverrideCRS)
                .opacity(useOverrideCRS ? 1 : 0.35)
                .font(.system(.body, design: .monospaced))
        }
    }

    var logSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Run Log")
                    .font(.headline)
                Spacer()
                Button("View Log") {
                    simulationState.showLogSheet = true
                }
                .disabled(!logActionAvailability.isEnabled)
            }
            if let reason = logActionAvailability.reason, !logActionAvailability.isEnabled {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            }
            logView
        }
    }

    var outputExplorer: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Text("Output Explorer")
                    .font(.headline)
                if outputStore.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
                Spacer()
                Button("Refresh") {
                    refreshOutputTree()
                }
                .disabled(!outputRefreshAvailability.isEnabled)
            }

            if let reason = outputRefreshAvailability.reason, !outputRefreshAvailability.isEnabled {
                Text(reason)
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            }

            if outputStore.nodes.isEmpty {
                Text("Run a simulation to populate RateOfSpread outputs.")
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                OutlineGroup(outputStore.nodes, children: \.children) { node in
                    OutputTreeRow(node: node,
                                  theme: theme,
                                  isSelected: node.isSelectable && overlayState.lastOverlaySourceURL?.standardizedFileURL == node.url.standardizedFileURL,
                                  onSelect: { selectOutputNode(node, zoomAfterSelection: false) },
                                  onZoom: { selectOutputNode(node, zoomAfterSelection: true) })
                }
                .padding(10)
                .glassBackground(material: theme.material,
                                 tint: theme.cardBackground,
                                 cornerRadius: 20,
                                 strokeColor: theme.borderColor)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            }

            rosVisualizationControls
        }
    }

    var logView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                Text(simulationState.log.isEmpty ? "No simulation log entries yet." : simulationState.log)
                    .font(.system(.footnote, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .foregroundColor(theme.textColor)
                    .textSelection(.enabled)
                    .padding(.vertical, 8)
                    .padding(.horizontal, 6)
                    .id("logBottom")
            }
            .onChange(of: simulationState.log) { _, _ in
                withAnimation(.easeOut(duration: 0.15)) {
                    proxy.scrollTo("logBottom", anchor: .bottom)
                }
            }
        }
        .frame(minHeight: 220)
        .glassBackground(material: theme.material,
                         tint: theme.editorBackground,
                         cornerRadius: 18,
                         strokeColor: theme.borderColor.opacity(0.8))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.accentColor.opacity(0.35), lineWidth: 1.5)
        )
    }

    var weatherIntervalSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                HStack(spacing: 4) {
                    Text("Weather Interval")
                    Button {
                        simulationState.showWeatherInfo = true
                    } label: {
                        Image(systemName: "info.circle")
                    }
                    .buttonStyle(.plain)
                    .help("Enter the weather data interval in minutes. Minimum 10 and must be a multiple of 10.")
                }
                Spacer()
                TextField("Minutes", text: $simulationState.weatherPeriodInput)
                    .frame(width: 90)
                    .multilineTextAlignment(.trailing)
                    .onChange(of: simulationState.weatherPeriodInput) { _, newValue in
                        let digitsOnly = newValue.filter { $0.isNumber }
                        if digitsOnly != newValue {
                            DispatchQueue.main.async {
                                simulationState.weatherPeriodInput = digitsOnly
                            }
                        }
                    }
                    .themedField(background: theme.fieldBackground, textColor: theme.textColor)
            }
            Text("Current interval: \(simulationState.weatherPeriodMinutes) minutes")
                .font(.footnote)
                .foregroundColor(theme.subtleTextColor)
        }
    }

    var rosVisualizationControls: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("ROS Visualization")
                .font(.headline)
            Picker("Color Ramp", selection: rosPaletteBinding) {
                ForEach(RateOfSpreadPalette.allCases) { palette in
                    Text(palette.displayName).tag(palette)
                }
            }
            .pickerStyle(.menu)

            VStack(alignment: .leading, spacing: 4) {
                Text(String(format: "Overlay Opacity: %.0f%%", rosOpacity * 100))
                    .font(.caption)
                    .foregroundColor(theme.subtleTextColor)
                Slider(value: $rosOpacity, in: 0.2...1.0, step: 0.05)
            }

            if let overlayURL = overlayState.lastOverlaySourceURL {
                Text("Active layer: \(overlayURL.lastPathComponent)")
                    .font(.caption)
                    .foregroundColor(theme.subtleTextColor)
            }
        }
    }

    var simulationSettings: some View {
        VStack(alignment: .leading, spacing: 8) {
            simulationField(title: "Simulations", binding: $simulationState.numberOfSimulationsInput, placeholder: "1") { newValue in
                let digits = newValue.filter { $0.isNumber }
                if digits != newValue {
                    simulationState.numberOfSimulationsInput = digits
                }
                if let value = Int(digits), value >= 1 {
                    simulationState.numberOfSimulations = value
                }
            } infoAction: {
                simulationState.showSimInfo = true
            }

            simulationField(title: "Threads", binding: $simulationState.numberOfThreadsInput, placeholder: "7") { newValue in
                let digits = newValue.filter { $0.isNumber }
                if digits != newValue {
                    simulationState.numberOfThreadsInput = digits
                }
                if let value = Int(digits), value >= 1 {
                    simulationState.numberOfThreads = value
                }
            } infoAction: {
                simulationState.showThreadInfo = true
            }

            simulationField(title: "Seed", binding: $simulationState.seedInput, placeholder: "123") { newValue in
                let filtered = filterSeedInput(newValue)
                if filtered != newValue {
                    simulationState.seedInput = filtered
                }
                if let value = Int(filtered) {
                    simulationState.seedValue = value
                }
            } infoAction: {
                simulationState.showSeedInfo = true
            }
        }
    }
}
