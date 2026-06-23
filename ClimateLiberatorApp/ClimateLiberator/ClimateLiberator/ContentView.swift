import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @ObservedObject var scenarioStore: ScenarioLibraryStore
    @ObservedObject var reviewStore: TCFDReviewStore
    @ObservedObject var forecastStore: ForecastIntelligenceStore
    @Environment(\.openWindow) var openWindow

    @AppStorage("climateliberator.binaryPath") var binaryPath = "/Users/afnan/Desktop/Climate-Liberator/Cell2Fire/Cell2Fire"
    @AppStorage("climateliberator.inputFolder") var inputFolder = "/Users/afnan/Desktop/Climate-Liberator/data/ScottAndBurgan/Clinge"
    @AppStorage("climateliberator.outputFolder") var outputFolder = ""
    @AppStorage("climateliberator.theme") var theme: ThemeStyle = .night
    // Default to the legacy subprocess engine: it is the verified ground truth.
    // The embedded engine builds but is not yet at output parity with the CLI
    // (see docs/embedded-engine-parity.md), so it is opt-in until those bugs land.
    @AppStorage("climateliberator.engineMode") var engineModeRaw = SimulationEngineMode.legacyCell2Fire.rawValue

    @State var showingFolderPicker = false
    @State var showingOutputPicker = false
    @State var showingBinaryPicker = false
    @State var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.155, longitude: 5.387),
        span: MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0)
    )
    @StateObject var simulationState = SimulationRunState()
    @State var activeWorkspace: AppWorkspace = .dashboard
    @State var isPanelVisible = true
    @StateObject var locationSearchState = LocationSearchState()
    @State var useSatelliteView = false
    @State var enable3DView = false
    @State var mapHeading: CLLocationDirection = 0
    @State var controlsExpanded = true
    @StateObject var overlayState = SimulationOverlayState()
    @StateObject var outputStore: SimulationOutputStore
    @State var restoredRunID: String?
    @State var legendOffset: CGSize = .zero
    @GestureState var legendDragTranslation: CGSize = .zero
    @StateObject var mapController = MapController()
    @AppStorage("climateliberator.overrideCRS.enabled") var useOverrideCRS = false
    @AppStorage("climateliberator.overrideCRS.code") var overrideCRSCode = "EPSG:4326"
    @State var showCRSInfo = false
    @AppStorage("climateliberator.rosPalette") var rosPaletteRawValue = RateOfSpreadPalette.terrain.rawValue
    @AppStorage("climateliberator.rosOpacity") var rosOpacity = 0.85
    @AppStorage("climateliberator.ee.serviceAccount") var earthEngineServiceAccount = "climascan@wildire-modelling.iam.gserviceaccount.com"
    @AppStorage("climateliberator.ee.keyPath") var earthEngineKeyPath = "/Users/afnan/Library/Application Support/ClimateLiberator/earthengine-key.json"
    @AppStorage("climateliberator.ee.dataset") var earthEngineDataset = "COPERNICUS/S2_SR"
    @AppStorage("climateliberator.ee.band") var earthEngineBand = "B04"
    @AppStorage("climateliberator.ee.startDate") var earthEngineStartDate = "2025-01-01"
    @AppStorage("climateliberator.ee.endDate") var earthEngineEndDate = "2025-12-31"
    @AppStorage("climateliberator.ee.scaleMeters") var earthEngineScaleInput = "10"
    @AppStorage("climateliberator.ee.scriptPath") var earthEngineScriptPath = "/Users/afnan/Desktop/ClimateLiberator/ClimateLiberator/Scripts/fetch_from_earth_engine.py"
    @AppStorage("climateliberator.ee.mode") var earthEngineModeRaw = EarthEngineTarget.overlay.rawValue
    @AppStorage("climateliberator.ee.demFilename") var earthEngineDemFilename = "elevation.asc"
    @AppStorage("climateliberator.ee.useStudyBounds") var useStudyAreaBounds = false
    @AppStorage("climateliberator.mapVisible") var mapVisible = false
    @AppStorage("climateliberator.ee.expanded") var earthEngineExpanded = true
    @StateObject var earthEngineState = EarthEngineFetchState()
    @StateObject var indiaRiskStore = IndiaRiskStore()
    @StateObject var exposureIntakeStore = ExposureIntakeStore()
    @State var reviewRefreshWorkItem: DispatchWorkItem?
    @available(macOS, introduced: 10.8, deprecated: 26)
    let legacyFallbackGeocoder = CLGeocoder()

    let enterprisePlatform: ClimateLiberatorEnterprisePlatform
    let simulationEngineService: SimulationEngineServicing
    let artifactService: SimulationArtifactServicing
    let runConfigService: SimulationRunConfigServicing
    let reviewDiscoveryService: SimulationReviewDiscoveryServicing
    let simOptions: [(label: String, value: String)] = [
        ("Scott & Burgan", "S"),
        ("Kitral", "K"),
        ("FBP-Canada", "C")
    ]
    let preferredBinaryPath = "/Users/afnan/Desktop/Climate-Liberator/Cell2Fire/Cell2Fire"
    let legacyBinaryPaths = [
        "/Users/afnan/Desktop/C2F-W/Cell2Fire/Cell2Fire",
        "/Users/afnan/Desktop/Wildfire Model/Cell2Fire/C2F-W/Cell2Fire/Cell2Fire"
    ]

    init(scenarioStore: ScenarioLibraryStore,
         reviewStore: TCFDReviewStore,
         forecastStore: ForecastIntelligenceStore,
         enterprisePlatform: ClimateLiberatorEnterprisePlatform = .localDefault(),
         simulationEngineService: SimulationEngineServicing? = nil,
         artifactService: SimulationArtifactServicing = SimulationArtifactService(),
         runConfigService: SimulationRunConfigServicing = SimulationRunConfigService(),
         reviewDiscoveryService: SimulationReviewDiscoveryServicing = SimulationReviewDiscoveryService(),
         outputTreeService: SimulationOutputTreeServicing = SimulationOutputTreeService()) {
        _scenarioStore = ObservedObject(wrappedValue: scenarioStore)
        _reviewStore = ObservedObject(wrappedValue: reviewStore)
        _forecastStore = ObservedObject(wrappedValue: forecastStore)
        _outputStore = StateObject(wrappedValue: SimulationOutputStore(treeService: outputTreeService))
        self.enterprisePlatform = enterprisePlatform
        self.simulationEngineService = simulationEngineService ?? enterprisePlatform.simulationEngine
        self.artifactService = artifactService
        self.runConfigService = runConfigService
        self.reviewDiscoveryService = reviewDiscoveryService
    }
    let maxCachedSearchEntries = 12
    let maxLogCharacterCount = 40_000
    let outputTreeLimits = OutputTreeDiscoveryLimits(maxDepth: 4, maxNodes: 300)
    static var gdalTranslateCache: String?
    static var gdalWarpCache: String?
    static var gdalTransformCache: String?

    var rosPalette: RateOfSpreadPalette {
        get { RateOfSpreadPalette(rawValue: rosPaletteRawValue) ?? .terrain }
        set { rosPaletteRawValue = newValue.rawValue }
    }

    var simulationEngineMode: SimulationEngineMode {
        get { SimulationEngineMode(rawValue: engineModeRaw) ?? .legacyCell2Fire }
        set { engineModeRaw = newValue.rawValue }
    }

    var rosPaletteBinding: Binding<RateOfSpreadPalette> {
        Binding(get: { RateOfSpreadPalette(rawValue: rosPaletteRawValue) ?? .terrain },
                set: { rosPaletteRawValue = $0.rawValue })
    }

    var earthEngineMode: EarthEngineTarget {
        get { EarthEngineTarget(rawValue: earthEngineModeRaw) ?? .overlay }
        set { earthEngineModeRaw = newValue.rawValue }
    }

    var studyAreaExtentStatus: String {
        earthEngineState.studyAreaExtentStatusMessage
    }

    var canFetchEarthEngine: Bool {
        let account = earthEngineServiceAccount.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = earthEngineKeyPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let dataset = earthEngineDataset.trimmingCharacters(in: .whitespacesAndNewlines)
        let band = earthEngineBand.trimmingCharacters(in: .whitespacesAndNewlines)
        let script = earthEngineScriptPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let start = earthEngineStartDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let end = earthEngineEndDate.trimmingCharacters(in: .whitespacesAndNewlines)
        let scale = earthEngineScaleInput.trimmingCharacters(in: .whitespacesAndNewlines)
        if earthEngineMode == .dem {
            let demName = earthEngineDemFilename.trimmingCharacters(in: .whitespacesAndNewlines)
            let inputPath = inputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
            return !account.isEmpty && !key.isEmpty && !dataset.isEmpty && !band.isEmpty &&
                   !script.isEmpty && !start.isEmpty && !end.isEmpty && !scale.isEmpty &&
                   !demName.isEmpty && !inputPath.isEmpty
        }
        return !account.isEmpty && !key.isEmpty && !dataset.isEmpty && !band.isEmpty &&
               !script.isEmpty && !start.isEmpty && !end.isEmpty && !scale.isEmpty
    }

    var body: some View {
        decoratedRootView
    }

    var decoratedRootView: some View {
        rootLifecycleView
    }

    var rootOverlayView: some View {
        ClimateLiberatorWorkspaceShellView(
            activeWorkspace: $activeWorkspace,
            theme: theme,
            dashboardView: AnyView(dashboardWorkspaceView),
            executiveOverviewView: AnyView(commandCenterWorkspaceView),
            portfolioIntelligenceView: AnyView(intelligenceWorkspaceView),
            operationsView: AnyView(
                ClimateSimulationWorkspaceView(
                    theme: theme,
                    isPanelVisible: isPanelVisible,
                    controlsExpanded: controlsExpanded,
                    mapLayer: AnyView(mapLayer),
                    searchCard: AnyView(searchCard),
                    earthEngineCard: AnyView(earthEngineCard),
                    themePicker: AnyView(
                        Picker("Theme", selection: $theme) {
                            ForEach(ThemeStyle.allCases) { style in
                                Text(style.displayName).tag(style)
                            }
                        }
                        .pickerStyle(.segmented)
                    ),
                    siteContent: AnyView(
                        VStack(alignment: .leading, spacing: 18) {
                            searchCard
                            earthEngineCard
                            indiaSiteLookupSection
                        }
                    ),
                    inputsContent: AnyView(
                        VStack(alignment: .leading, spacing: 18) {
                            environmentSection
                            scenarioWorkflowSection
                            dashboardPanelCard(title: "India Preparedness Checklist",
                                               subtitle: "Prepared-instance validation for India-first wildfire studies. Keep this with simulation setup, not portfolio screening.") {
                                indiaWildfireReadinessPanel
                            }
                        }
                    ),
                    runContent: AnyView(runSetupSection),
                    outputsContent: AnyView(resultsSection),
                    logsContent: AnyView(
                        VStack(alignment: .leading, spacing: 18) {
                            dashboardPanelCard(title: "Recent Simulation Activity",
                                               subtitle: "Latest wildfire runs captured in the current session.") {
                                recentSimulationActivityPanel
                            }
                            logSection
                        }
                    ),
                    onTogglePanel: togglePanel,
                    onToggleExpanded: toggleControlPanel
                )
            ),
            operationsOverlayControls: AnyView(mapModeControls),
            openTCFDDashboard: { openWindow(id: "tcfd-dashboard") },
            quitApplication: quitApplication
        )
    }

    var rootAppearanceView: some View {
        rootOverlayView
        .tint(theme.accentColor)
        .preferredColorScheme(theme.colorScheme)
    }

    var rootFileImportView: some View {
        rootAppearanceView
        .fileImporter(isPresented: $showingFolderPicker,
                       allowedContentTypes: [.folder],
                       allowsMultipleSelection: false, onCompletion: handleInputFolder)
        .fileImporter(isPresented: $showingOutputPicker,
                       allowedContentTypes: [.folder],
                       allowsMultipleSelection: false, onCompletion: handleOutputFolder)
        .fileImporter(isPresented: $showingBinaryPicker,
                       allowedContentTypes: [.item],
                       allowsMultipleSelection: false, onCompletion: handleBinarySelection)
    }

    var rootAlertView: some View {
        rootFileImportView
        .alert("Weather Interval", isPresented: $simulationState.showWeatherInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Enter the weather sampling interval in minutes. Values must be multiples of 10, starting at 10 minutes.")
        }
        .alert("Simulations", isPresented: $simulationState.showSimInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Number of independent Cell2Fire runs to execute. Each simulation uses a different random seed sequence.")
        }
        .alert("Threads", isPresented: $simulationState.showThreadInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("OpenMP thread count. Increase to speed up runs if your CPU has available cores.")
        }
        .alert("Seed", isPresented: $simulationState.showSeedInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Base random seed for reproducibility. Use the same value to reproduce identical results.")
        }
        .alert("Study Area Extent", isPresented: $earthEngineState.showExtentInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("When enabled, Climate Liberator reads fuels.asc (or another fuel grid) to derive the map extent. If the grid is projected (e.g., EPSG:28992), the corners are reprojected to WGS84 using gdaltransform so Google Earth Engine receives latitude/longitude bounds. Install GDAL so gdaltransform is available.")
        }
        .sheet(isPresented: $simulationState.showLogSheet) {
            LogViewer(logText: simulationState.log, logURL: simulationState.logFileURL, theme: theme)
        }
        .alert("CRS Override", isPresented: $showCRSInfo) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("If your RateOfSpread outputs are in a projected CRS (e.g., EPSG:28998 for Amersfoort), enable the override and enter the EPSG code. The exporter will reproject to WGS84 so the KMZ aligns in Google Earth.")
        }
    }

    var rootObservedView: some View {
        rootAlertView
        .onChange(of: mapVisible) { _, visible in
            if !visible {
                overlayState.inspectMode = false
                overlayState.inspectResult = nil
                mapController.mapView = nil
            }
        }
        .onChange(of: theme) { _, _ in
            DispatchQueue.main.async {
                rebuildOverlay()
            }
        }
        .onChange(of: rosPaletteRawValue) { _, _ in
            DispatchQueue.main.async {
                rebuildOverlay()
            }
        }
        .onChange(of: rosOpacity) { _, _ in
            DispatchQueue.main.async {
                rebuildOverlay()
            }
        }
        .onChange(of: inputFolder) { _, _ in
            reloadIgnitionCells()
            scheduleStudyAreaExtentStatusRefresh()
        }
        .onChange(of: outputFolder) { _, _ in
            refreshReviewDiscoveryRoots()
        }
        .onChange(of: overlayState.currentIgnitionCell) { _, _ in
            refreshIgnitionMarkers(with: overlayState.rosOverlay)
        }
    }

    var rootStudyAreaObservedView: some View {
        rootObservedView
        .onChange(of: useStudyAreaBounds) { _, _ in
            scheduleStudyAreaExtentStatusRefresh()
        }
        .onChange(of: useOverrideCRS) { _, _ in
            scheduleStudyAreaExtentStatusRefresh()
        }
        .onChange(of: overrideCRSCode) { _, _ in
            scheduleStudyAreaExtentStatusRefresh()
        }
        .onChange(of: earthEngineExpanded) { _, expanded in
            if expanded {
                scheduleStudyAreaExtentStatusRefresh()
            }
        }
    }

    var rootLifecycleView: some View {
        rootStudyAreaObservedView
        .onAppear {
            activeWorkspace = .dashboard
            reloadIgnitionCells()
            refreshOutputTree()
            refreshReviewDiscoveryRoots()
            scheduleStudyAreaExtentStatusRefresh()
            indiaRiskStore.refreshDatabaseStatus()
            restoreLatestPersistedRunIfNeeded()
        }
        .onChange(of: reviewStore.bundles.first?.runID) { _, _ in
            restoreLatestPersistedRunIfNeeded()
        }
    }

    var mapLayer: AnyView {
        if mapVisible {
            return AnyView(
                ZoomableMapView(region: $mapRegion,
                                useSatellite: $useSatelliteView,
                                enable3D: $enable3DView,
                                heading: $mapHeading,
                                overlay: $overlayState.rosOverlay,
                                inspectMode: $overlayState.inspectMode,
                                inspectResult: $overlayState.inspectResult,
                                ignitionMarkers: $overlayState.ignitionMarkers,
                                controller: mapController)
                    .ignoresSafeArea()
                    .overlay(alignment: .topTrailing) {
                        if let overlay = overlayState.rosOverlay {
                            VStack(alignment: .trailing, spacing: 8) {
                                if let coordinate = overlayState.inspectResult?.coordinate {
                                    Text(String(format: "Lat %.4f°  Lon %.4f°",
                                                coordinate.latitude,
                                                coordinate.longitude))
                                        .font(.caption2)
                                        .padding(.vertical, 4)
                                        .padding(.horizontal, 10)
                                        .background(
                                            Capsule()
                                                .fill(Color.black.opacity(0.55))
                                                .overlay(
                                                    Capsule().stroke(Color.white.opacity(0.25), lineWidth: 1)
                                                )
                                        )
                                }
                                ROSLegendView(palette: rosPalette,
                                              minValue: overlay.minValue,
                                              maxValue: overlay.maxValue,
                                              opacity: rosOpacity)
                                    .frame(width: 130)
                            }
                            .padding(.top, 24)
                            .padding(.trailing, 24)
                            .offset(x: legendOffset.width + legendDragTranslation.width,
                                    y: legendOffset.height + legendDragTranslation.height)
                            .gesture(
                                DragGesture()
                                    .updating($legendDragTranslation) { value, state, _ in
                                        state = value.translation
                                    }
                                    .onEnded { value in
                                        legendOffset.width += value.translation.width
                                        legendOffset.height += value.translation.height
                                    }
                            )
                        }
                    }
                    .overlay(alignment: .topTrailing) {
                        if overlayState.inspectMode && overlayState.inspectResult == nil {
                            IdentifyHint()
                                .padding(.top, 26)
                                .padding(.trailing, 20)
                        }
                    }
            )
        } else {
            return AnyView(
                Color.black.opacity(0.9)
                    .ignoresSafeArea()
                    .overlay {
                        VStack(spacing: 10) {
                            Image(systemName: "map")
                                .font(.system(size: 42, weight: .regular))
                                .foregroundColor(.white.opacity(0.8))
                            Text("Map is hidden")
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Tap the Map button to display Apple Maps when you need it. Keeping it hidden reduces memory usage.")
                                .font(.footnote)
                                .multilineTextAlignment(.center)
                                .foregroundColor(.white.opacity(0.7))
                                .frame(maxWidth: 240)
                        }
                    }
            )
        }
    }

    var panelLayer: AnyView {
        if isPanelVisible {
            return AnyView(
                VStack(alignment: .leading, spacing: 18) {
                    HStack {
                        Button(action: togglePanel) {
                            Label("Hide Panel", systemImage: "sidebar.leading")
                                .labelStyle(.titleAndIcon)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        Spacer()
                    }
                    searchCard
                    earthEngineCard
                    ScrollView {
                        mainCard
                    }
                }
                .frame(maxWidth: 420)
                .padding(.top, 84)
                .padding(.bottom, 32)
                .padding(.leading, 20)
                .padding(.trailing, 12)
                .transition(.move(edge: .leading).combined(with: .opacity))
            )
        } else {
            return AnyView(
                VStack {
                    HStack {
                        Button(action: togglePanel) {
                            Label("Show Panel", systemImage: "sidebar.trailing")
                                .labelStyle(.titleAndIcon)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.leading, 20)
                        .padding(.top, 84)
                        Spacer()
                    }
                    Spacer()
                }
            )
        }
    }

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
