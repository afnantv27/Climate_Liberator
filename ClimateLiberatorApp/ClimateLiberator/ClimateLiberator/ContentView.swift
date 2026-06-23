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


}
