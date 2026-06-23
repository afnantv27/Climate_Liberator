import SwiftUI
import AppKit
import MapKit
import CoreLocation
import UniformTypeIdentifiers
import Combine

struct ContentView: View {
    @ObservedObject private var scenarioStore: ScenarioLibraryStore
    @ObservedObject private var reviewStore: TCFDReviewStore
    @ObservedObject private var forecastStore: ForecastIntelligenceStore
    @Environment(\.openWindow) private var openWindow

    @AppStorage("climateliberator.binaryPath") private var binaryPath = "/Users/afnan/Desktop/Climate-Liberator/Cell2Fire/Cell2Fire"
    @AppStorage("climateliberator.inputFolder") private var inputFolder = "/Users/afnan/Desktop/Climate-Liberator/data/ScottAndBurgan/Clinge"
    @AppStorage("climateliberator.outputFolder") private var outputFolder = ""
    @AppStorage("climateliberator.theme") private var theme: ThemeStyle = .night
    @AppStorage("climateliberator.engineMode") private var engineModeRaw = SimulationEngineMode.embeddedCell2Fire.rawValue

    @State private var showingFolderPicker = false
    @State private var showingOutputPicker = false
    @State private var showingBinaryPicker = false
    @State private var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 52.155, longitude: 5.387),
        span: MKCoordinateSpan(latitudeDelta: 3.0, longitudeDelta: 3.0)
    )
    @StateObject private var simulationState = SimulationRunState()
    @State private var activeWorkspace: AppWorkspace = .dashboard
    @State private var isPanelVisible = true
    @StateObject private var locationSearchState = LocationSearchState()
    @State private var useSatelliteView = false
    @State private var enable3DView = false
    @State private var mapHeading: CLLocationDirection = 0
    @State private var controlsExpanded = true
    @StateObject private var overlayState = SimulationOverlayState()
    @StateObject private var outputStore: SimulationOutputStore
    @State private var restoredRunID: String?
    @State private var legendOffset: CGSize = .zero
    @GestureState private var legendDragTranslation: CGSize = .zero
    @StateObject private var mapController = MapController()
    @AppStorage("climateliberator.overrideCRS.enabled") private var useOverrideCRS = false
    @AppStorage("climateliberator.overrideCRS.code") private var overrideCRSCode = "EPSG:4326"
    @State private var showCRSInfo = false
    @AppStorage("climateliberator.rosPalette") private var rosPaletteRawValue = RateOfSpreadPalette.terrain.rawValue
    @AppStorage("climateliberator.rosOpacity") private var rosOpacity = 0.85
    @AppStorage("climateliberator.ee.serviceAccount") private var earthEngineServiceAccount = "climascan@wildire-modelling.iam.gserviceaccount.com"
    @AppStorage("climateliberator.ee.keyPath") private var earthEngineKeyPath = "/Users/afnan/Library/Application Support/ClimateLiberator/earthengine-key.json"
    @AppStorage("climateliberator.ee.dataset") private var earthEngineDataset = "COPERNICUS/S2_SR"
    @AppStorage("climateliberator.ee.band") private var earthEngineBand = "B04"
    @AppStorage("climateliberator.ee.startDate") private var earthEngineStartDate = "2025-01-01"
    @AppStorage("climateliberator.ee.endDate") private var earthEngineEndDate = "2025-12-31"
    @AppStorage("climateliberator.ee.scaleMeters") private var earthEngineScaleInput = "10"
    @AppStorage("climateliberator.ee.scriptPath") private var earthEngineScriptPath = "/Users/afnan/Desktop/ClimateLiberator/ClimateLiberator/Scripts/fetch_from_earth_engine.py"
    @AppStorage("climateliberator.ee.mode") private var earthEngineModeRaw = EarthEngineTarget.overlay.rawValue
    @AppStorage("climateliberator.ee.demFilename") private var earthEngineDemFilename = "elevation.asc"
    @AppStorage("climateliberator.ee.useStudyBounds") private var useStudyAreaBounds = false
    @AppStorage("climateliberator.mapVisible") private var mapVisible = false
    @AppStorage("climateliberator.ee.expanded") private var earthEngineExpanded = true
    @StateObject private var earthEngineState = EarthEngineFetchState()
    @StateObject private var indiaRiskStore = IndiaRiskStore()
    @StateObject private var exposureIntakeStore = ExposureIntakeStore()
    @State private var reviewRefreshWorkItem: DispatchWorkItem?
    @available(macOS, introduced: 10.8, deprecated: 26)
    private let legacyFallbackGeocoder = CLGeocoder()

    private let enterprisePlatform: ClimateLiberatorEnterprisePlatform
    private let simulationEngineService: SimulationEngineServicing
    private let artifactService: SimulationArtifactServicing
    private let runConfigService: SimulationRunConfigServicing
    private let reviewDiscoveryService: SimulationReviewDiscoveryServicing
    private let simOptions: [(label: String, value: String)] = [
        ("Scott & Burgan", "S"),
        ("Kitral", "K"),
        ("FBP-Canada", "C")
    ]
    private let preferredBinaryPath = "/Users/afnan/Desktop/Climate-Liberator/Cell2Fire/Cell2Fire"
    private let legacyBinaryPaths = [
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
    private let maxCachedSearchEntries = 12
    private let maxLogCharacterCount = 40_000
    private let outputTreeLimits = OutputTreeDiscoveryLimits(maxDepth: 4, maxNodes: 300)
    private static var gdalTranslateCache: String?
    private static var gdalWarpCache: String?
    private static var gdalTransformCache: String?

    private var rosPalette: RateOfSpreadPalette {
        get { RateOfSpreadPalette(rawValue: rosPaletteRawValue) ?? .terrain }
        set { rosPaletteRawValue = newValue.rawValue }
    }

    private var simulationEngineMode: SimulationEngineMode {
        get { SimulationEngineMode(rawValue: engineModeRaw) ?? .legacyCell2Fire }
        set { engineModeRaw = newValue.rawValue }
    }

    private var rosPaletteBinding: Binding<RateOfSpreadPalette> {
        Binding(get: { RateOfSpreadPalette(rawValue: rosPaletteRawValue) ?? .terrain },
                set: { rosPaletteRawValue = $0.rawValue })
    }

    private var earthEngineMode: EarthEngineTarget {
        get { EarthEngineTarget(rawValue: earthEngineModeRaw) ?? .overlay }
        set { earthEngineModeRaw = newValue.rawValue }
    }

    private var studyAreaExtentStatus: String {
        earthEngineState.studyAreaExtentStatusMessage
    }

    private var canFetchEarthEngine: Bool {
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

    private var decoratedRootView: some View {
        rootLifecycleView
    }

    private var rootOverlayView: some View {
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

    private var rootAppearanceView: some View {
        rootOverlayView
        .tint(theme.accentColor)
        .preferredColorScheme(theme.colorScheme)
    }

    private var rootFileImportView: some View {
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

    private var rootAlertView: some View {
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

    private var rootObservedView: some View {
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

    private var rootStudyAreaObservedView: some View {
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

    private var rootLifecycleView: some View {
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

    private var mapLayer: AnyView {
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

    private var panelLayer: AnyView {
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

    private var mainCard: some View {
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

    private var dashboardWorkspaceView: some View {
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

    private var commandCenterWorkspaceView: some View {
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

    private var enterpriseReadinessSummary: EnterpriseReadinessSummary {
        enterprisePlatform
            .dashboard
            .fetchSummary(request: EnterpriseDashboardSummaryRequest(outputFolder: outputFolder))
            .readinessSummary
    }

    private var intelligenceWorkspaceView: some View {
        PortfolioIntelligenceWorkspaceView(
            indiaRiskStore: indiaRiskStore,
            exposureIntakeStore: exposureIntakeStore,
            mapRegion: $mapRegion,
            activeWorkspace: $activeWorkspace,
            theme: theme,
            openTCFDDashboard: { openWindow(id: "tcfd-dashboard") }
        )
    }

    private func executiveMetricCard(title: String, value: String, detail: String) -> some View {
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

    private func dashboardPanelCard<Content: View>(title: String,
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

    private var indiaWildfireReadinessPanel: some View {
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

    private var recentSimulationActivityPanel: some View {
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

    private var indiaWildfireReadinessChecks: [IndiaWildfireReadinessCheck] {
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

    private var indiaWildfireSimulationReadinessMessage: String {
        let checks = indiaWildfireReadinessChecks
        return checks.allSatisfy(\.isReady)
            ? "Simulation-ready for a prepared India wildfire study."
            : "Ready only when all prepared wildfire inputs are present and aligned."
    }

    private func preferredInputFile(in folder: URL, candidates: [String]) -> URL? {
        guard FileManager.default.fileExists(atPath: folder.path) else { return nil }
        return candidates
            .map { folder.appendingPathComponent($0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private var searchCard: some View {
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

    private var earthEngineCard: some View {
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

    private var mapModeControls: some View {
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

    private var environmentSection: some View {
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

    private var scenarioWorkflowSection: some View {
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

    private var indiaSiteLookupSection: some View {
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

    private var runSetupSection: some View {
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

    private var resultsSection: some View {
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

    private var crsOverrideSection: some View {
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

    private var logSection: some View {
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

    private var outputExplorer: some View {
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

    private var logView: some View {
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

    private var weatherIntervalSection: some View {
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

    private var rosVisualizationControls: some View {
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

    private var simulationSettings: some View {
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

    private func togglePanel() {
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            isPanelVisible.toggle()
        }
    }

    private func quitApplication() {
        NSApp.terminate(nil)
    }

    private func toggleControlPanel() {
        withAnimation(.spring(response: 0.45, dampingFraction: 0.85)) {
            controlsExpanded.toggle()
        }
    }

    private var scenarioSelectionBinding: Binding<ScenarioDefinition.ID?> {
        Binding(
            get: { scenarioStore.selectedScenarioID },
            set: { newValue in
                scenarioStore.selectScenario(id: newValue)
            }
        )
    }

    private var selectedScenarioApplicationAvailability: ActionAvailability {
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

    private var operationsWorkspaceAvailability: ActionAvailability {
        if simulationState.isRunning {
            return .unavailable("A wildfire simulation is currently running in the operations workspace.")
        }
        if let warning = validateEnvironment() {
            return .unavailable(warning)
        }
        return .ready
    }

    private var portfolioIntelligenceAvailability: ActionAvailability {
        if indiaRiskStore.lookupAvailability.isEnabled {
            return .ready
        }
        return .unavailable(indiaRiskStore.lookupAvailability.reason ?? "Connect a queryable India risk database before screening the portfolio.")
    }

    private var disclosureReviewAvailability: ActionAvailability {
        guard !reviewStore.bundles.isEmpty else {
            return .unavailable("Generate a disclosure package from a successful run before starting disclosure review.")
        }
        return .ready
    }

    private var runActionAvailability: ActionAvailability {
        if simulationState.isRunning {
            return .unavailable("A wildfire simulation is already running.")
        }
        if let warning = validateEnvironment() {
            return .unavailable(warning)
        }
        return .ready
    }

    private var exportActionAvailability: ActionAvailability {
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

    private var outputRefreshAvailability: ActionAvailability {
        if outputStore.isLoading {
            return .unavailable("Output discovery is already running.")
        }
        if simulationState.lastOutputDirectory != nil || !outputStore.nodes.isEmpty {
            return .ready
        }
        return .unavailable("Run a simulation or import an Earth Engine layer first.")
    }

    private var logActionAvailability: ActionAvailability {
        simulationState.log.isEmpty ? .unavailable("No simulation log entries are available yet.") : .ready
    }

    private var earthEngineActionAvailability: ActionAvailability {
        if earthEngineState.isFetching {
            return .unavailable("Earth Engine import is already running.")
        }
        if canFetchEarthEngine {
            return .ready
        }
        return .unavailable("Complete the dataset, band, dates, credentials, and helper script before fetching.")
    }

    private var latestDisclosureReportAvailability: ActionAvailability {
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

    private var latestEvidencePackageAvailability: ActionAvailability {
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

    private var openOutputFolderAvailability: ActionAvailability {
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

    private func applySelectedScenario() {
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

    private func scheduleStudyAreaExtentStatusRefresh() {
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

    private func buildStudyAreaExtentStatusMessage() -> String {
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

    private func refreshReviewDiscoveryRoots() {
        reviewRefreshWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            reviewStore.updateDiscoveryRoots(reviewDiscoveryService.discoveryRoots(for: outputFolder))
        }
        reviewRefreshWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: workItem)
    }

    private func performLocationSearch() {
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

    private func currentOperationalRunConfigDocument() -> OperationalRunConfigDocument {
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

    private func exportRunConfiguration() {
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

    private func importRunConfiguration() {
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

    private func applyImportedRunConfiguration(_ document: OperationalRunConfigDocument) {
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
    private func normalizedSpan(from region: MKCoordinateRegion?) -> MKCoordinateSpan {
        let fallback = MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        guard let region = region else { return fallback }
        let lat = region.span.latitudeDelta
        let lon = region.span.longitudeDelta
        let validLat = max(0.01, min(lat, 40))
        let validLon = max(0.01, min(lon, 40))
        if lat.isZero || lon.isZero { return fallback }
        return MKCoordinateSpan(latitudeDelta: validLat, longitudeDelta: validLon)
    }

    private func updateMapRegion(center coordinate: CLLocationCoordinate2D, span: MKCoordinateSpan) {
        var updatedRegion = mapRegion
        updatedRegion.center = coordinate
        updatedRegion.span = span
        withAnimation(.easeInOut(duration: 0.35)) {
            mapRegion = updatedRegion
        }
    }

    private func coordinateFromQuery(_ query: String) -> CLLocationCoordinate2D? {
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

    private func directionMultiplier(for char: Character) -> Double? {
        let lower = String(char).lowercased()
        if lower == "s" || lower == "w" { return -1 }
        if lower == "n" || lower == "e" { return 1 }
        return nil
    }

    private func cacheSearchResult(for key: String,
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

    private func cachedSearchResult(for key: String) -> CachedSearchResult? {
        locationSearchState.cache[key.lowercased()]
    }

    private func scheduleFallbackGeocode(for query: String,
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

    private func startFallbackGeocode(for query: String, normalizedKey: String) {
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

    private func cancelPendingSearchWork() {
        locationSearchState.fallbackWorkItem?.cancel()
        locationSearchState.fallbackWorkItem = nil
        if #available(macOS 26, *) {
            // no legacy geocoder to cancel
        } else {
            legacyFallbackGeocoder.cancelGeocode()
        }
    }

    @available(macOS 26, *)
    private func startSecondaryLocalSearch(for query: String, normalizedKey: String) {
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

    private func handleFallbackResult(coordinate: CLLocationCoordinate2D?,
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

    private func restoreOverlaySnapshotIfNeeded() {
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

    private func logSimulationSummary(_ summary: RunSummary) {
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

    private func appendOutputTailIfNeeded(from stdout: String) {
        let allLines = stdout.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
        guard !allLines.isEmpty else { return }
        let filteredLines = allLines.filter {
            !$0.contains("FuelModelSpain: spain_lookup_table.csv is empty; fm_parameters will not be populated")
        }
        let source = filteredLines.isEmpty ? allLines : filteredLines
        let tail = source.suffix(3000).joined(separator: "\n")
        appendToLog("\n------ Cell2Fire Console Tail ------\n\(tail)\n")
    }

    private func tableRow(label: String,
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

    private func fetchEarthEngineOverlay() {
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

    private func boundingBox(for region: MKCoordinateRegion) -> (west: Double, south: Double, east: Double, north: Double) {
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

    private struct ASCIIGridHeader {
        let ncols: Int
        let nrows: Int
        let xOrigin: Double
        let yOrigin: Double
        let cellSize: Double
    }

    private func locateStudyGrid() -> URL? {
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

    private func readGridHeader(from url: URL) -> ASCIIGridHeader? {
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

    private func readASCIIHeaderLines(from url: URL,
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

    private func rawBoundingBox(from header: ASCIIGridHeader) -> (west: Double, south: Double, east: Double, north: Double) {
        let west = header.xOrigin
        let south = header.yOrigin
        let east = west + header.cellSize * Double(header.ncols)
        let north = south + header.cellSize * Double(header.nrows)
        return (west, south, east, north)
    }

    private func reprojectBoundingBox(header: ASCIIGridHeader,
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

    private func studyAreaBoundingBox() -> (west: Double, south: Double, east: Double, north: Double)? {
        guard let gridURL = locateStudyGrid(),
              let header = readGridHeader(from: gridURL) else { return nil }
        return computeStudyAreaBoundingBox(gridURL: gridURL, header: header, logFailures: true)
    }

    private func computeStudyAreaBoundingBox(gridURL: URL,
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

    private func sanitizedDEMFilename(_ proposed: String) -> String {
        var name = proposed.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty { name = "elevation.asc" }
        let invalid = CharacterSet(charactersIn: "/\\:")
        name = name.components(separatedBy: invalid).joined(separator: "_")
        if !name.lowercased().hasSuffix(".asc") {
            name += ".asc"
        }
        return name
    }

    private func run() {
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

    private func handleInputFolder(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let folder = urls.first { inputFolder = folder.path }
        case .failure(let error):
            appendToLog("Input folder picker error: \(error.localizedDescription)")
        }
    }

    private func handleOutputFolder(_ result: Result<[URL], Error>) {
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

    private func handleBinarySelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let file = urls.first { binaryPath = file.path }
        case .failure(let error):
            appendToLog("Binary picker error: \(error.localizedDescription)")
        }
    }

    private func refreshOutputTree() {
        rebuildOutputTree(rateOfSpreadBase: simulationState.lastOutputDirectory)
    }

    private func loadOutputTree(from basePath: String) {
        rebuildOutputTree(rateOfSpreadBase: basePath)
    }

    private func rebuildOutputTree(rateOfSpreadBase: String?) {
        outputStore.rebuild(rateOfSpreadBase: rateOfSpreadBase,
                            earthEngineOverlaysDirectory: overlaysDirectory(),
                            limits: outputTreeLimits)
    }

    private func selectOutputNode(_ node: OutputNode, zoomAfterSelection: Bool) {
        guard node.isSelectable else { return }
        loadOverlay(from: node.url,
                    zoomAfterLoad: zoomAfterSelection,
                    successMessage: "Loaded overlay from")
    }

        private func reloadIgnitionCells() {
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

    private func refreshIgnitionMarkers(with overlay: RateOfSpreadOverlay?) {
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

    private func normalizeWeatherInterval() {
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

    private func normalizeSimulationParameters() {
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

    private func resolveBinaryPath(allowAutofix: Bool) -> BinaryResolution {
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

    private func validateEnvironment(skipBinaryCheck: Bool = false) -> String? {
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

    private func resolvedOutputDirectory(for input: String, customOutput: String?) -> String {
        if let customOutput, !customOutput.isEmpty {
            return NSString(string: customOutput).expandingTildeInPath
        }
        var normalized = input
        if !normalized.hasSuffix("/") {
            normalized += "/"
        }
        return NSString(string: normalized + "simOuts").expandingTildeInPath
    }

    private func rateOfSpreadDirectory(basePath: String) -> URL {
        let baseURL = URL(fileURLWithPath: basePath)
        if baseURL.lastPathComponent.compare("RateOfSpread", options: .caseInsensitive) == .orderedSame {
            return baseURL
        }
        return baseURL.appendingPathComponent("RateOfSpread")
    }

    private func latestROSFile(from files: [URL]) -> URL? {
        let ascFiles = files.filter { $0.pathExtension.lowercased() == "asc" }
        return ascFiles.max { lhs, rhs in
            let lDate = (try? lhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            let rDate = (try? rhs.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date.distantPast
            return lDate < rDate
        }
    }

    private func persistIndiaWildfireAssessmentsIfPossible(runID: String,
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

    private func restoreLatestPersistedRunIfNeeded() {
        guard !simulationState.hasSuccessfulRun, simulationState.runSummaries.isEmpty, restoredRunID == nil,
              let latest = reviewStore.bundles.first else {
            return
        }
        restorePersistedRunState(from: latest)
    }

    private func restorePersistedRunState(from bundle: TCFDRunArtifactBundle) {
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

    private func projectionInfo(for ascURL: URL, logFailures: Bool = true) -> ProjectionInfo? {
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

    private func heuristicallyInferProjection(for ascURL: URL, logFailures: Bool) -> ProjectionInfo? {
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

    private func asciiHeaderMetadata(for ascURL: URL) -> ASCIIHeaderMetadata? {
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

    private func isLikelyDutchRD(easting: Double, northing: Double) -> Bool {
        let eastingRange = 0.0...300_000.0
        let northingRange = 250_000.0...630_000.0
        return eastingRange.contains(easting) && northingRange.contains(northing)
    }

    private func normalizeCRSCode(_ value: String) -> String {
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

    private func exportKMZ() {
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

    private func createKMZ(from outputDirectory: String) -> Result<URL, Error> {
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

    private func runGDALTranslate(arguments: [String]) throws {
        guard let executable = locateGDALTranslate() else {
            throw ExportError(message: "gdal_translate not found. Install GDAL (e.g., `brew install gdal`).")
        }
        try runGDALProcess(executable: executable, arguments: arguments, label: "gdal_translate")
    }

    private func runGDALWarp(arguments: [String]) throws {
        guard let executable = locateGDALWarp() else {
            throw ExportError(message: "gdalwarp not found. Install GDAL (e.g., `brew install gdal`).")
        }
        try runGDALProcess(executable: executable, arguments: arguments, label: "gdalwarp")
    }

    private func runGDALProcess(executable: String, arguments: [String], label: String) throws {
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

    private func locateGDALTranslate() -> String? {
        locateGDALBinary(name: "gdal_translate", cache: &ContentView.gdalTranslateCache)
    }

    private func locateGDALWarp() -> String? {
        locateGDALBinary(name: "gdalwarp", cache: &ContentView.gdalWarpCache)
    }

    private func locateGDALTransform() -> String? {
        locateGDALBinary(name: "gdaltransform", cache: &ContentView.gdalTransformCache)
    }

    private func locateGDALBinary(name: String, cache: inout String?) -> String? {
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

    private func postProcessRateOfSpread(at outputDirectory: String, desiredFormat: OutputFormat) {
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

    private func updateMapOverlay(at outputDirectory: String, expectedVersion: Int? = nil) {
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

    private func rebuildOverlay() {
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

    private func loadOverlay(from sourceFile: URL,
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

    private func applyRenderedOverlay(_ overlay: RateOfSpreadOverlay,
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

    private func focusMap(on overlay: RateOfSpreadOverlay) {
        let latExtent = max(overlay.maxLat - overlay.minLat, 0.005)
        let lonExtent = max(overlay.maxLon - overlay.minLon, 0.005)
        let span = MKCoordinateSpan(latitudeDelta: latExtent * 1.25,
                                    longitudeDelta: lonExtent * 1.25)
        let region = MKCoordinateRegion(center: overlay.coordinate, span: span)
        withAnimation(.easeInOut(duration: 0.35)) {
            mapRegion = region
        }
    }

    private func simulationField(title: String,
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

    private func filterSeedInput(_ value: String) -> String {
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

    nonisolated private func appendToLog(_ message: String) {
        let entry = message.hasSuffix("\n") ? message : message + "\n"
        Task { @MainActor in
            simulationState.appendLog(entry, maxCharacterCount: maxLogCharacterCount)
            appendLogToFile(entry)
        }
    }

    private func prepareOverlayASCII(for source: URL) -> URL? {
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

    private func overlaysDirectory() -> URL? {
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

    private func parseRateOfSpreadGrid(from asciiURL: URL) -> RateOfSpreadGrid? {
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

    private func makeOverlay(from grid: RateOfSpreadGrid,
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

    private func heatColor(for normalized: Double,
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

    private func prepareLogFile() -> URL? {
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

    private func resetLogFile(with text: String) {
        guard let url = simulationState.logFileURL, let data = text.data(using: .utf8) else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func appendLogToFile(_ text: String) {
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

    private func simulatorLabel(for code: String) -> String {
        simOptions.first(where: { $0.value == code })?.label ?? code
    }

    private func buildRunSummary(from output: String,
                                 rosStats: (Double?, Double?),
                                 timestamp: Date) -> RunSummary? {
        let simulations = parseSimulationStats(from: output, rosStats: rosStats)
        guard !simulations.isEmpty else { return nil }
        return RunSummary(timestamp: timestamp, simulations: simulations)
    }

    private func parseSimulationStats(from output: String,
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

    private func analyzeRateOfSpread(at outputDirectory: String) -> (Double?, Double?) {
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

    private func parseCountValue(from line: String, label: String) -> Int? {
        let remainder = line.replacingOccurrences(of: label, with: "")
        return firstInteger(in: remainder)
    }

    private func firstInteger(in text: String) -> Int? {
        if let range = text.range(of: "[0-9]+", options: .regularExpression) {
            return Int(text[range])
        }
        return nil
    }

    private func firstDouble(in text: String) -> Double? {
        if let range = text.range(of: "-?[0-9]+(\\.[0-9]+)?", options: .regularExpression) {
            return Double(text[range])
        }
        return nil
    }

}

private struct SimulationStatsBuilder {
    let index: Int
    var weatherFile: String?
    var ignitionCell: Int?
    var totalCells: Int?
    var available: Int?
    var burnt: Int?
    var nonBurnable: Int?
    var firebreak: Int?
}

private struct ExportError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private struct SettingRow<Content: View>: View {
    let title: String
    let theme: ThemeStyle
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(theme.subtleTextColor)
            HStack(spacing: 8) {
                content()
            }
        }
    }
}

private struct DashboardView: View {
    let summaries: [RunSummary]
    let theme: ThemeStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                if let latest = summaries.first {
                    DashboardSummaryCard(summary: latest,
                                         theme: theme,
                                         title: "Latest Run")
                    .padding(.bottom, 24)
                } else {
                    Text("No simulations have been captured yet.")
                        .foregroundColor(theme.subtleTextColor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if summaries.count > 1 {
                    Text("Run History")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.bottom, 8)

                    VStack(spacing: 12) {
                        ForEach(Array(summaries.dropFirst())) { summary in
                            HistoryRow(summary: summary, theme: theme)
                        }
                    }
                }
            }
            .padding()
            .background(
                LinearGradient(colors: theme.gradient,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("Run Dashboard")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .frame(minWidth: 540, minHeight: 560)
    }
}

private struct LogViewer: View {
    let logText: String
    let logURL: URL?
    let theme: ThemeStyle
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                Text(logText.isEmpty ? "No simulation log entries yet." : logText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .glassBackground(material: theme.material,
                                     tint: theme.cardBackground,
                                     cornerRadius: 18,
                                     strokeColor: theme.borderColor)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .padding()
            .background(
                LinearGradient(colors: theme.gradient,
                               startPoint: .topLeading,
                               endPoint: .bottomTrailing)
                    .ignoresSafeArea()
            )
            .navigationTitle("Run Log")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                if let logURL {
                    ToolbarItem(placement: .primaryAction) {
                        ShareLink(item: logURL) {
                            Label("Share", systemImage: "square.and.arrow.up")
                        }
                    }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

private struct DashboardSummaryCard: View {
    let summary: RunSummary
    let theme: ThemeStyle
    let title: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            Text(summary.timestamp, style: .date)
                .font(.title3).bold()
            Text(summary.timestamp, style: .time)
                .font(.subheadline)
                .foregroundColor(theme.subtleTextColor)

            ForEach(summary.simulations) { stats in
                SimulationDisclosure(stats: stats, theme: theme)
            }
        }
        .padding()
        .glassBackground(material: theme.material,
                         tint: theme.cardBackground,
                         cornerRadius: 26,
                         strokeColor: theme.borderColor)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .shadow(color: theme.shadowColor, radius: 8, x: 0, y: 6)
    }
}

private struct SimulationDisclosure: View {
    let stats: SimulationStats
    let theme: ThemeStyle
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(spacing: 6) {
                StatsRow(label: "Total Cells", value: formattedCount(stats.resolvedTotal))
                StatsRow(label: "Ignition Point", value: formattedCount(stats.ignitionCell))
                StatsRow(label: "Available", value: formattedCount(stats.available))
                StatsRow(label: "Burnt", value: formattedCount(stats.burnt))
                StatsRow(label: "Non-burnable", value: formattedCount(stats.nonBurnable))
                StatsRow(label: "Firebreak", value: formattedCount(stats.firebreak))
                StatsRow(label: "Highest ROS", value: formattedROS(stats.highestROS))
                StatsRow(label: "Lowest ROS", value: formattedROS(stats.lowestROS))
            }
            .padding(.top, 6)
        } label: {
            Text("Simulation \(stats.simulationIndex) Stats")
                .font(.subheadline).bold()
        }
        .tint(theme.accentColor)
        .padding(.vertical, 6)
    }
}

private struct StatsRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .font(.system(.body, design: .monospaced))
        }
    }
}

private struct OutputTreeRow: View {
    let node: OutputNode
    let theme: ThemeStyle
    let isSelected: Bool
    let onSelect: () -> Void
    let onZoom: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: node.iconName)
                .foregroundColor(node.isDirectory ? theme.subtleTextColor : theme.accentColor)
            Text(node.name)
                .lineLimit(1)
            Spacer()
        }
        .font(.subheadline)
        .padding(.vertical, 4)
        .padding(.horizontal, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundColor(theme.textColor)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? theme.accentColor.opacity(0.28) : Color.clear)
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if node.isSelectable {
                onSelect()
            }
        }
        .contextMenu {
            if node.isSelectable {
                Button("Display Layer") { onSelect() }
                Button("Zoom In") { onZoom() }
            }
        }
    }
}

private struct ROSLegendView: View {
    let palette: RateOfSpreadPalette
    let minValue: Double
    let maxValue: Double
    let opacity: Double

    var body: some View {
        VStack(alignment: .center, spacing: 10) {
            Text("Rate of Spread")
                .font(.caption).bold()
            VStack(spacing: 4) {
                Text(String(format: "Max %.2f", maxValue))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
                HStack {
                    Spacer()
                    LinearGradient(gradient: Gradient(colors: palette.gradientColors),
                                   startPoint: .bottom,
                                   endPoint: .top)
                        .frame(width: 28, height: 140)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.white.opacity(0.35), lineWidth: 1)
                        )
                    Spacer()
                }
                Text(String(format: "Min %.2f", minValue))
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.85))
            }
            Text(String(format: "Opacity: %.0f%%", opacity * 100))
                .font(.caption2)
                .foregroundColor(.white.opacity(0.7))
        }
        .multilineTextAlignment(.center)
        .padding(12)
        .frame(maxWidth: 150)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
        .foregroundColor(.white)
        .shadow(color: Color.black.opacity(0.35), radius: 10, x: 0, y: 8)
    }
}

private struct MapModeButton: View {
    let icon: String
    let label: String
    let active: Bool
    let theme: ThemeStyle
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                Text(label)
                    .font(.caption2)
            }
            .frame(width: 52, height: 52)
            .foregroundColor(.white)
            .background(
                Circle()
                    .fill(active ? theme.accentColor : Color.black.opacity(0.45))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.25), lineWidth: 1)
                    )
            )
        }
        .buttonStyle(.plain)
    }
}

struct InspectResult: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let value: Double
}

struct IgnitionMarker: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

final class RateOfSpreadOverlay: NSObject, MKOverlay {
    let image: CGImage
    let boundingMapRect: MKMapRect
    let coordinate: CLLocationCoordinate2D
    let values: [Double?]
    let width: Int
    let height: Int
    let minValue: Double
    let maxValue: Double
    let minLon: Double
    let maxLon: Double
    let minLat: Double
    let maxLat: Double
    let cellSize: Double

    init(image: CGImage,
         boundingMapRect: MKMapRect,
         coordinate: CLLocationCoordinate2D,
         values: [Double?],
         width: Int,
         height: Int,
         minValue: Double,
         maxValue: Double,
         minLon: Double,
         maxLon: Double,
         minLat: Double,
         maxLat: Double,
         cellSize: Double) {
        self.image = image
        self.boundingMapRect = boundingMapRect
        self.coordinate = coordinate
        self.values = values
        self.width = width
        self.height = height
        self.minValue = minValue
        self.maxValue = maxValue
        self.minLon = minLon
        self.maxLon = maxLon
        self.minLat = minLat
        self.maxLat = maxLat
        self.cellSize = cellSize
        super.init()
    }

    func value(at coordinate: CLLocationCoordinate2D) -> Double? {
        return sample(at: coordinate)?.value
    }

    func sample(at coordinate: CLLocationCoordinate2D) -> (value: Double, center: CLLocationCoordinate2D)? {
        let col = Int((coordinate.longitude - minLon) / cellSize)
        let row = Int((maxLat - coordinate.latitude) / cellSize)
        guard col >= 0, col < width, row >= 0, row < height else { return nil }
        guard let value = values[row * width + col] else { return nil }
        let centerLat = maxLat - cellSize * (Double(row) + 0.5)
        let centerLon = minLon + cellSize * (Double(col) + 0.5)
        let center = CLLocationCoordinate2D(latitude: centerLat, longitude: centerLon)
        return (value, center)
    }

    func coordinate(forCellID cellID: Int) -> CLLocationCoordinate2D? {
        guard cellID >= 1, cellID <= width * height else { return nil }
        let zeroIndexed = cellID - 1
        let row = zeroIndexed / width
        let col = zeroIndexed % width
        let latitude = maxLat - cellSize * (Double(row) + 0.5)
        let longitude = minLon + cellSize * (Double(col) + 0.5)
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

final class RateOfSpreadOverlayRenderer: MKOverlayRenderer {
    override init(overlay: MKOverlay) {
        super.init(overlay: overlay)
    }

    override func draw(_ mapRect: MKMapRect, zoomScale: MKZoomScale, in context: CGContext) {
        guard let overlay = overlay as? RateOfSpreadOverlay else { return }
        let rect = self.rect(for: overlay.boundingMapRect)
        context.saveGState()
        context.setAlpha(0.75)
        context.draw(overlay.image, in: rect)
        context.restoreGState()
    }
}

private struct IdentifyHint: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Identify ROS")
                .font(.caption).bold()
            Text("Click the map to probe the rate of spread at that point.")
                .font(.caption)
                .multilineTextAlignment(.leading)
        }
        .padding(10)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .foregroundColor(.white)
    }
}

final class IgnitionAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D

    init(coordinate: CLLocationCoordinate2D) {
        self.coordinate = coordinate
        super.init()
    }
}

private struct CompassButton: View {
    let angle: CLLocationDirection
    let theme: ThemeStyle
    let action: () -> Void

    private var rotation: Angle { Angle(degrees: -angle) }

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(Color.black.opacity(0.55))
                    .overlay(
                        Circle()
                            .stroke(Color.white.opacity(0.35), lineWidth: 1)
                    )
                Image(systemName: "location.north.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color.white, Color.red)
                    .rotationEffect(rotation)
            }
            .frame(width: 52, height: 52)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Reset bearing")
    }
}

private struct HistoryRow: View {
    let summary: RunSummary
    let theme: ThemeStyle

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(summary.timestamp, style: .date)
                Text(summary.timestamp, style: .time)
                    .font(.caption)
                    .foregroundColor(theme.subtleTextColor)
            }
            Spacer()
            if let burnt = aggregatedBurnt(for: summary),
               let total = aggregatedTotal(for: summary) {
                Text("\(formattedCount(burnt)) / \(formattedCount(total)) burnt")
                    .font(.footnote)
                    .foregroundColor(theme.subtleTextColor)
            } else {
                Text("—")
                    .foregroundColor(theme.subtleTextColor)
            }
        }
        .padding()
        .glassBackground(material: theme.material,
                         tint: theme.cardBackground.opacity(0.9),
                         cornerRadius: 16,
                         strokeColor: theme.borderColor)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private func formattedCount(_ value: Int?) -> String {
    guard let value else { return "—" }
    return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
}

private func formattedROS(_ value: Double?) -> String {
    guard let value else { return "—" }
    return String(format: "%.3f", value)
}

private func aggregatedBurnt(for summary: RunSummary) -> Int? {
    let values = summary.simulations.compactMap { $0.burnt }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
}

private func aggregatedTotal(for summary: RunSummary) -> Int? {
    let values = summary.simulations.compactMap { $0.resolvedTotal }
    guard !values.isEmpty else { return nil }
    return values.reduce(0, +)
}

private extension SimulationStats {
    var resolvedTotal: Int? {
        if let totalCells { return totalCells }
        let components = [available, burnt, nonBurnable, firebreak]
        if components.contains(where: { $0 == nil }) { return nil }
        return components.compactMap { $0 }.reduce(0, +)
    }
}

#if os(macOS)
private struct ZoomableMapView: NSViewRepresentable {
    @Binding var region: MKCoordinateRegion
    @Binding var useSatellite: Bool
    @Binding var enable3D: Bool
    @Binding var heading: CLLocationDirection
    @Binding var overlay: RateOfSpreadOverlay?
    @Binding var inspectMode: Bool
    @Binding var inspectResult: InspectResult?
    @Binding var ignitionMarkers: [IgnitionMarker]
    var controller: MapController

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> ScrollZoomMKMapView {
        let mapView = ScrollZoomMKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.scrollDelegate = context.coordinator
        mapView.setRegion(region, animated: false)
        mapView.isRotateEnabled = true
        mapView.pointOfInterestFilter = .includingAll
        mapView.showsBuildings = true
        let clickRecognizer = NSClickGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleClick(_:)))
        mapView.addGestureRecognizer(clickRecognizer)
        context.coordinator.applyDisplayOptions(mapView: mapView,
                                                useSatellite: useSatellite,
                                                enable3D: enable3D)
        controller.mapView = mapView
        if let overlay {
            mapView.updateOverlay(overlay)
        }
        mapView.updateIgnitionMarkers(ignitionMarkers)
        mapView.updateIdentifyMarker(inspectResult)
        return mapView
    }

    func updateNSView(_ nsView: ScrollZoomMKMapView, context: Context) {
        context.coordinator.updateRegionIfNeeded(mapView: nsView, region: region)
        context.coordinator.applyDisplayOptions(mapView: nsView,
                                                useSatellite: useSatellite,
                                                enable3D: enable3D)
        controller.mapView = nsView
        nsView.updateOverlay(overlay)
        nsView.updateIgnitionMarkers(ignitionMarkers)
        nsView.updateIdentifyMarker(inspectResult)
        nsView.refreshScale()
    }

    final class Coordinator: NSObject, MKMapViewDelegate, ScrollZoomMapViewDelegate {
        var parent: ZoomableMapView
        private var isSyncingRegion = false

        init(_ parent: ZoomableMapView) {
            self.parent = parent
        }

        func updateRegionIfNeeded(mapView: MKMapView, region: MKCoordinateRegion) {
            guard !isSyncingRegion else { return }
            if !regionsEqual(mapView.region, region) {
                isSyncingRegion = true
                mapView.setRegion(region, animated: false)
                isSyncingRegion = false
            }
        }

        func applyDisplayOptions(mapView: MKMapView, useSatellite: Bool, enable3D: Bool) {
            let desiredType: MKMapType = useSatellite ? .hybrid : .standard
            if mapView.mapType != desiredType {
                mapView.mapType = desiredType
            }

            let camera = mapView.camera
            let targetPitch: CGFloat = enable3D ? 55 : 0
            let targetDistance: CLLocationDistance
            if enable3D {
                let minDistance: CLLocationDistance = 2200
                targetDistance = max(minDistance, camera.centerCoordinateDistance)
            } else {
                targetDistance = max(800, camera.centerCoordinateDistance)
            }

            let targetHeading: CLLocationDirection = enable3D ? camera.heading : 0
            let needsCameraUpdate =
                abs(camera.pitch - targetPitch) > 0.5 ||
                abs(camera.centerCoordinateDistance - targetDistance) > 1 ||
                abs(camera.heading - targetHeading) > 0.5 ||
                abs(camera.centerCoordinate.latitude - mapView.region.center.latitude) > 0.0001 ||
                abs(camera.centerCoordinate.longitude - mapView.region.center.longitude) > 0.0001

            if needsCameraUpdate {
                camera.pitch = targetPitch
                camera.centerCoordinate = mapView.region.center
                camera.centerCoordinateDistance = targetDistance
                camera.heading = targetHeading
                mapView.setCamera(camera, animated: false)
            }

            mapView.isPitchEnabled = true
            parent.heading = targetHeading
        }

        func mapView(_ mapView: MKMapView, regionDidChangeAnimated animated: Bool) {
            guard !isSyncingRegion else { return }
            isSyncingRegion = true
            parent.region = mapView.region
            isSyncingRegion = false
            parent.heading = mapView.camera.heading
            (mapView as? ScrollZoomMKMapView)?.refreshScale()
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if overlay is RateOfSpreadOverlay {
                return RateOfSpreadOverlayRenderer(overlay: overlay)
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if annotation is MKUserLocation {
                return nil
            }
            if annotation is IgnitionAnnotation {
                let identifier = "IgnitionAnnotation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) ??
                    MKAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                let baseConfig = NSImage.SymbolConfiguration(pointSize: 24, weight: .bold)
                let colorConfig = NSImage.SymbolConfiguration(paletteColors: [.systemOrange])
                let combinedConfig = baseConfig.applying(colorConfig)
                if let baseImage = NSImage(systemSymbolName: "flame.fill", accessibilityDescription: "Ignition"),
                   let image = baseImage.withSymbolConfiguration(combinedConfig) {
                    view.image = image
                }
                view.canShowCallout = false
                return view
            }
            return nil
        }

        func mapView(_ mapView: ScrollZoomMKMapView, scrollZoom deltaY: CGFloat) {
            var span = mapView.region.span
            let magnitude = Double(max(0.05, min(0.6, abs(deltaY) / 300)))
            let multiplier = 1 + magnitude
            if deltaY > 0 {
                span.latitudeDelta = min(span.latitudeDelta * multiplier, 80)
                span.longitudeDelta = min(span.longitudeDelta * multiplier, 80)
            } else {
                span.latitudeDelta = max(span.latitudeDelta / multiplier, 0.0005)
                span.longitudeDelta = max(span.longitudeDelta / multiplier, 0.0005)
            }
            let newRegion = MKCoordinateRegion(center: mapView.region.center, span: span)
            isSyncingRegion = true
            mapView.setRegion(newRegion, animated: false)
            parent.region = newRegion
            isSyncingRegion = false
            mapView.refreshScale()
        }

        private func regionsEqual(_ lhs: MKCoordinateRegion, _ rhs: MKCoordinateRegion) -> Bool {
            abs(lhs.center.latitude - rhs.center.latitude) < 0.0001 &&
            abs(lhs.center.longitude - rhs.center.longitude) < 0.0001 &&
            abs(lhs.span.latitudeDelta - rhs.span.latitudeDelta) < 0.0001 &&
            abs(lhs.span.longitudeDelta - rhs.span.longitudeDelta) < 0.0001
        }

        @objc func handleClick(_ gesture: NSClickGestureRecognizer) {
            guard parent.inspectMode,
                  let mapView = gesture.view as? ScrollZoomMKMapView,
                  gesture.state == .ended else { return }
            let point = gesture.location(in: mapView)
            let coordinate = mapView.convert(point, toCoordinateFrom: mapView)
            if let info = mapView.sampleInfo(at: coordinate) {
                parent.inspectResult = InspectResult(coordinate: info.coordinate, value: info.value)
            } else {
                parent.inspectResult = nil
            }
        }
    }
}

fileprivate protocol ScrollZoomMapViewDelegate: AnyObject {
    func mapView(_ mapView: ScrollZoomMKMapView, scrollZoom deltaY: CGFloat)
}

fileprivate final class ScrollZoomMKMapView: MKMapView {
    weak var scrollDelegate: ScrollZoomMapViewDelegate?
    private let scaleOverlay = MapScaleOverlay()
    private var activeOverlay: RateOfSpreadOverlay?
    private var ignitionAnnotations: [IgnitionAnnotation] = []
    private let identifyMarkerView = IdentifyMarkerView()
    private var currentIdentifyResult: InspectResult?

    override init(frame: NSRect) {
        super.init(frame: frame)
        configureAuxiliaryViews()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureAuxiliaryViews()
    }

    override func scrollWheel(with event: NSEvent) {
        if abs(event.scrollingDeltaY) > abs(event.scrollingDeltaX) {
            scrollDelegate?.mapView(self, scrollZoom: event.scrollingDeltaY)
        } else {
            super.scrollWheel(with: event)
        }
    }

    private func configureAuxiliaryViews() {
        showsCompass = false
        showsScale = false
        addSubview(scaleOverlay)
        scaleOverlay.translatesAutoresizingMaskIntoConstraints = false
        identifyMarkerView.translatesAutoresizingMaskIntoConstraints = true
        identifyMarkerView.isHidden = true
        addSubview(identifyMarkerView)

        NSLayoutConstraint.activate([
            scaleOverlay.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            scaleOverlay.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -16)
        ])
        refreshScale()
    }

    override func layout() {
        super.layout()
        scaleOverlay.update(using: self)
        repositionIdentifyMarker()
    }

    func refreshScale() {
        scaleOverlay.update(using: self)
    }

    func updateOverlay(_ overlay: RateOfSpreadOverlay?) {
        if activeOverlay === overlay {
            return
        }
        if let current = activeOverlay {
            removeOverlay(current)
        }
        activeOverlay = overlay
        if let overlay {
            addOverlay(overlay)
        }
    }

    func updateIgnitionMarkers(_ markers: [IgnitionMarker]) {
        let existingCoordinates = ignitionAnnotations.map(\.coordinate)
        let newCoordinates = markers.map(\.coordinate)
        if existingCoordinates.count == newCoordinates.count &&
            zip(existingCoordinates, newCoordinates).allSatisfy({
                abs($0.latitude - $1.latitude) < 0.000001 &&
                abs($0.longitude - $1.longitude) < 0.000001
            }) {
            return
        }
        removeAnnotations(ignitionAnnotations)
        ignitionAnnotations = markers.map { IgnitionAnnotation(coordinate: $0.coordinate) }
        addAnnotations(ignitionAnnotations)
    }

    func updateIdentifyMarker(_ result: InspectResult?) {
        currentIdentifyResult = result
        guard let result else {
            identifyMarkerView.isHidden = true
            return
        }
        identifyMarkerView.isHidden = false
        identifyMarkerView.update(text: formattedRateOfSpread(result.value))
        repositionIdentifyMarker()
    }

    private func repositionIdentifyMarker() {
        guard let result = currentIdentifyResult, !identifyMarkerView.isHidden else { return }
        let point = convert(result.coordinate, toPointTo: self)
        identifyMarkerView.layoutSubtreeIfNeeded()
        let size = identifyMarkerView.intrinsicContentSize
        let clampedX = min(max(point.x - size.width / 2, 8), bounds.width - size.width - 8)
        let clampedY = min(max(point.y - size.height - 12, 8), bounds.height - size.height - 8)
        identifyMarkerView.frame = CGRect(origin: CGPoint(x: clampedX, y: clampedY),
                                          size: size)
    }

    func sampleInfo(at coordinate: CLLocationCoordinate2D) -> (value: Double, coordinate: CLLocationCoordinate2D)? {
        guard let overlay = activeOverlay,
              let sample = overlay.sample(at: coordinate) else { return nil }
        return (sample.value, sample.center)
    }
}

private final class MapScaleOverlay: NSView {
    private let label = NSTextField(labelWithString: "—")
    private let bar = NSView()
    private var barWidthConstraint: NSLayoutConstraint!
    private let targetPixelLength: CGFloat = 110

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.backgroundColor = NSColor.black.withAlphaComponent(0.45).cgColor

        bar.translatesAutoresizingMaskIntoConstraints = false
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor.white.cgColor
        bar.layer?.cornerRadius = 1.5

        label.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .medium)
        label.alignment = .right
        label.textColor = .white
        label.translatesAutoresizingMaskIntoConstraints = false

        addSubview(bar)
        addSubview(label)

        barWidthConstraint = bar.widthAnchor.constraint(equalToConstant: targetPixelLength)

        NSLayoutConstraint.activate([
            bar.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -12),
            bar.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            bar.heightAnchor.constraint(equalToConstant: 3),
            barWidthConstraint,
            bar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
            label.topAnchor.constraint(equalTo: bar.bottomAnchor, constant: 6),
            label.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 12)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(using mapView: MKMapView) {
        guard mapView.bounds.width > 0 else { return }
        let mapRect = mapView.visibleMapRect
        guard mapRect.size.width > 0 else { return }
        let left = MKMapPoint(x: mapRect.minX, y: mapRect.midY)
        let right = MKMapPoint(x: mapRect.maxX, y: mapRect.midY)
        let totalMeters = left.distance(to: right)
        guard totalMeters.isFinite else { return }

        let metersPerPoint = totalMeters / Double(mapView.bounds.width)
        let desiredMeters = metersPerPoint * Double(targetPixelLength)
        let scaledValue = niceScaleValue(for: desiredMeters)
        let units = scaledValue >= 1000 ? "km" : "m"
        let displayValue = scaledValue >= 1000 ? scaledValue / 1000 : scaledValue
        if units == "m" {
            label.stringValue = "\(Int(displayValue)) m"
        } else {
            let shown = displayValue >= 10 ? String(format: "%.0f", displayValue) : String(format: "%.1f", displayValue)
            label.stringValue = "\(shown) km"
        }

        let width = CGFloat(scaledValue / metersPerPoint)
        barWidthConstraint.constant = max(24, min(width, mapView.bounds.width - 40))
        needsLayout = true
    }

    private func niceScaleValue(for meters: Double) -> Double {
        guard meters > 0 else { return 1 }
        let exponent = floor(log10(meters))
        let base = pow(10.0, exponent)
        let normalized = meters / base
        let candidate: Double
        if normalized < 2 { candidate = 1 }
        else if normalized < 5 { candidate = 2 }
        else { candidate = 5 }
        return candidate * base
    }
}

private final class IdentifyMarkerView: NSView {
    private let label = NSTextField(labelWithString: "")
    private let dot = NSView()
    private let container = NSView()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        translatesAutoresizingMaskIntoConstraints = false

        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.backgroundColor = NSColor(calibratedWhite: 0.05, alpha: 0.95).cgColor
        container.layer?.borderColor = NSColor.white.withAlphaComponent(0.35).cgColor
        container.layer?.borderWidth = 1.2
        container.translatesAutoresizingMaskIntoConstraints = false

        label.font = NSFont.monospacedSystemFont(ofSize: 14, weight: .semibold)
        label.textColor = .white
        label.alignment = .center
        label.usesSingleLineMode = true
        label.lineBreakMode = .byClipping
        label.translatesAutoresizingMaskIntoConstraints = false

        dot.wantsLayer = true
        dot.layer?.cornerRadius = 6
        dot.layer?.backgroundColor = NSColor.systemOrange.cgColor
        dot.translatesAutoresizingMaskIntoConstraints = false

        addSubview(container)
        container.addSubview(label)
        addSubview(dot)

        NSLayoutConstraint.activate([
            container.leadingAnchor.constraint(equalTo: leadingAnchor),
            container.trailingAnchor.constraint(equalTo: trailingAnchor),
            container.topAnchor.constraint(equalTo: topAnchor),

            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 8),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -8),

            dot.topAnchor.constraint(equalTo: container.bottomAnchor, constant: 5),
            dot.centerXAnchor.constraint(equalTo: centerXAnchor),
            dot.widthAnchor.constraint(equalToConstant: 12),
            dot.heightAnchor.constraint(equalToConstant: 12),
            dot.bottomAnchor.constraint(equalTo: bottomAnchor)
        ])
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(text: String) {
        label.stringValue = text
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    override var intrinsicContentSize: NSSize {
        let labelSize = label.intrinsicContentSize
        return NSSize(width: max(90, labelSize.width + 20), height: labelSize.height + 8 + 12 + 6)
    }
}

private let rosIdentifyFormatter: NumberFormatter = {
    let formatter = NumberFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.numberStyle = .decimal
    formatter.minimumFractionDigits = 2
    formatter.maximumFractionDigits = 2
    formatter.usesGroupingSeparator = false
    return formatter
}()

private func formattedRateOfSpread(_ value: Double) -> String {
    if let string = rosIdentifyFormatter.string(from: NSNumber(value: value)) {
        return "\(string) m/min"
    }
    return String(format: "%.2f m/min", locale: Locale(identifier: "en_US_POSIX"), value)
}

final class MapController: ObservableObject {
    let objectWillChange = ObservableObjectPublisher()
    fileprivate weak var mapView: ScrollZoomMKMapView?

    func resetHeading() {
        guard let mapView else { return }
        let camera = mapView.camera
        camera.heading = 0
        mapView.setCamera(camera, animated: true)
    }

    func clearOverlay() {
        mapView?.updateOverlay(nil)
    }
}
#endif
