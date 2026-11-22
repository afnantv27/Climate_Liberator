import Foundation
import Combine
import MapKit
import SwiftUI

enum ForecastHorizon: String, CaseIterable, Identifiable {
    case shortTerm
    case subseasonal
    case seasonal

    var id: String { rawValue }

    var title: String {
        switch self {
        case .shortTerm:
            return "Short Term"
        case .subseasonal:
            return "Subseasonal"
        case .seasonal:
            return "Seasonal"
        }
    }

    var providerStatus: String {
        switch self {
        case .shortTerm:
            return "Processed feeds preferred. Live weather and air-quality fallback available."
        case .subseasonal:
            return "Processed feeds preferred. Live seasonal-weather fallback available; air quality needs a managed feed."
        case .seasonal:
            return "Processed feeds preferred. Live seasonal-weather fallback available; air quality needs a managed feed."
        }
    }
}

enum ForecastBusinessVariable: String, CaseIterable, Identifiable {
    case meanTemperature
    case maxTemperature
    case minimumTemperature
    case precipitation
    case soilTemperature
    case relativeHumidity
    case evapotranspiration
    case solarRadiation
    case soilMoisture
    case windSpeed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .meanTemperature: return "Mean Temperature"
        case .maxTemperature: return "Max Temperature"
        case .minimumTemperature: return "Minimum Temperature"
        case .precipitation: return "Precipitation"
        case .soilTemperature: return "Soil Temperature"
        case .relativeHumidity: return "Relative Humidity"
        case .evapotranspiration: return "Evapotranspiration"
        case .solarRadiation: return "Solar Radiation"
        case .soilMoisture: return "Soil Moisture"
        case .windSpeed: return "Wind Speed"
        }
    }

    var queryValue: String {
        switch self {
        case .meanTemperature: return "temp_mean"
        case .maxTemperature: return "temp_max"
        case .minimumTemperature: return "temp_min"
        case .precipitation: return "precipitation"
        case .soilTemperature: return "soil_temperature"
        case .relativeHumidity: return "humidity"
        case .evapotranspiration: return "evapotranspiration"
        case .solarRadiation: return "solar_radiation"
        case .soilMoisture: return "soil_moisture"
        case .windSpeed: return "wind_speed"
        }
    }

    var supportsSeasonal: Bool { true }
    var supportsSubseasonal: Bool { true }
    var supportsShortTerm: Bool { true }
}

struct ForecastMetricCard: Identifiable, Hashable {
    let id: String
    let title: String
    let value: String
    let detail: String
}

struct ForecastTrustSummary: Hashable {
    let sourceLabel: String
    let sourceMode: String
    let officialStatus: String
    let confidenceLabel: String
    let freshnessLabel: String
    let updatedLabel: String
    let validWindowLabel: String
    let note: String
}

enum ForecastSourceState: Hashable {
    case processedFeedActive
    case liveProviderFallback
    case staleData
    case forecastUnavailable

    var title: String {
        switch self {
        case .processedFeedActive:
            return "Processed Forecast Feed"
        case .liveProviderFallback:
            return "Live Provider Fallback"
        case .staleData:
            return "Stale Data"
        case .forecastUnavailable:
            return "Forecast Unavailable"
        }
    }

    var shortLabel: String {
        switch self {
        case .processedFeedActive:
            return "Build-fed"
        case .liveProviderFallback:
            return "Fallback"
        case .staleData:
            return "Stale"
        case .forecastUnavailable:
            return "Unavailable"
        }
    }

    var detail: String {
        switch self {
        case .processedFeedActive:
            return "Standardized and quality-checked forecast data prepared for operational and business use."
        case .liveProviderFallback:
            return "Using live provider data while the processed forecast feed is unavailable or still refreshing."
        case .staleData:
            return "Data is older than the expected refresh window and should be used with caution."
        case .forecastUnavailable:
            return "No approved forecast source is available for this selection."
        }
    }

    var accentColor: Color {
        switch self {
        case .processedFeedActive:
            return .teal
        case .liveProviderFallback:
            return .orange
        case .staleData:
            return .yellow
        case .forecastUnavailable:
            return .red
        }
    }
}

struct ForecastLocationPin: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let tint: Color
}

nonisolated enum ForecastSourceMode: String, Codable, Hashable, Sendable {
    case liveFallback
    case processedFeed
    case curatedScenarioInput
}

nonisolated enum ForecastConfidence: String, Codable, Hashable, Sendable {
    case low
    case medium
    case high
    case watch
    case unknown
}

nonisolated enum ForecastPromotionLevel: String, Codable, Hashable, Sendable {
    case operationsOnly
    case executiveEligible
    case disclosureEligible
}

nonisolated struct ForecastObservedMetric: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var title: String
    var value: String
    var detail: String
}

nonisolated struct ForecastEvidenceSnapshot: Identifiable, Codable, Hashable, Sendable {
    var id: String
    var capturedAt: Date
    var providerID: String
    var providerLabel: String
    var sourceMode: ForecastSourceMode
    var horizon: String
    var confidence: ForecastConfidence
    var generatedAt: Date?
    var validFrom: Date?
    var validTo: Date?
    var locationLabel: String
    var latitude: Double
    var longitude: Double
    var statusSummary: String
    var weatherMetrics: [ForecastObservedMetric]
    var airQualityMetrics: [ForecastObservedMetric]
    var promotionLevel: ForecastPromotionLevel
    var analystInterpretation: String?
    var linkedScenarioID: UUID?
    var linkedPackageRunID: String?
    var sourceHash: String?
}

struct ForecastOverviewSummary: Decodable, Hashable {
    let asOf: Date
    let locationCount: Int
    let processedBuildLocationCount: Int
    let fallbackLocationCount: Int
    let mixedSourceLocationCount: Int
    let subseasonalLocationCount: Int
    let seasonalLocationCount: Int
    let warningReadyLocationCount: Int
    let providerCount: Int

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case locationCount = "location_count"
        case processedBuildLocationCount = "processed_build_location_count"
        case fallbackLocationCount = "fallback_location_count"
        case mixedSourceLocationCount = "mixed_source_location_count"
        case subseasonalLocationCount = "subseasonal_location_count"
        case seasonalLocationCount = "seasonal_location_count"
        case warningReadyLocationCount = "warning_ready_location_count"
        case providerCount = "provider_count"
    }
}

struct ForecastProviderTrustFeed: Decodable, Hashable {
    let asOf: Date
    let providers: [ForecastProviderTrustEntry]

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case providers
    }
}

struct ForecastProviderTrustEntry: Decodable, Hashable, Identifiable {
    let providerID: String
    let providerName: String
    let supportedHorizons: [String]
    let preferredForHorizons: [String]
    let fallbackOnlyForHorizons: [String]
    let status: String
    let trustLevel: String
    let lastSuccessAt: Date
    let latestValidWindowStart: Date
    let latestValidWindowEnd: Date
    let freshSnapshotCount: Int
    let staleSnapshotCount: Int
    let warningOverlayReady: Bool

    var id: String { providerID }

    enum CodingKeys: String, CodingKey {
        case providerID = "provider_id"
        case providerName = "provider_name"
        case supportedHorizons = "supported_horizons"
        case preferredForHorizons = "preferred_for_horizons"
        case fallbackOnlyForHorizons = "fallback_only_for_horizons"
        case status
        case trustLevel = "trust_level"
        case lastSuccessAt = "last_success_at"
        case latestValidWindowStart = "latest_valid_window_start"
        case latestValidWindowEnd = "latest_valid_window_end"
        case freshSnapshotCount = "fresh_snapshot_count"
        case staleSnapshotCount = "stale_snapshot_count"
        case warningOverlayReady = "warning_overlay_ready"
    }
}

struct ForecastWarningSummary: Decodable, Hashable {
    let asOf: Date
    let warningReadyLocationCount: Int
    let subseasonalWatchCount: Int
    let seasonalWatchCount: Int
    let overlayReadyLocationCount: Int
    let warningCandidatesByKind: [String: Int]
    let activeOverlayIDs: [String]

    enum CodingKeys: String, CodingKey {
        case asOf = "as_of"
        case warningReadyLocationCount = "warning_ready_location_count"
        case subseasonalWatchCount = "subseasonal_watch_count"
        case seasonalWatchCount = "seasonal_watch_count"
        case overlayReadyLocationCount = "overlay_ready_location_count"
        case warningCandidatesByKind = "warning_candidates_by_kind"
        case activeOverlayIDs = "active_overlay_ids"
    }
}

@MainActor
final class ForecastIntelligenceStore: ObservableObject {
    @Published var searchQuery = "Bengaluru, India"
    @Published var selectedHorizon: ForecastHorizon = .shortTerm
    @Published var selectedLocationName = "Bengaluru, India"
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946),
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )
    @Published private(set) var weatherCards: [ForecastMetricCard] = []
    @Published private(set) var airQualityCards: [ForecastMetricCard] = []
    @Published private(set) var statusMessage = "Search for an Indian site or business location to pull live forecast and air-quality outlooks."
    @Published private(set) var providerLabel = "Open-Meteo"
    @Published private(set) var isLoading = false
    @Published private(set) var forecastOverview: ForecastOverviewSummary?
    @Published private(set) var providerTrustFeed: ForecastProviderTrustFeed?
    @Published private(set) var warningSummary: ForecastWarningSummary?
    @Published private(set) var executiveEligibleSnapshots: [ForecastEvidenceSnapshot] = []
    @Published private(set) var disclosureEligibleSnapshots: [ForecastEvidenceSnapshot] = []
    @Published private(set) var lastSnapshotMessage: String?
    @Published private(set) var trustSummary = ForecastTrustSummary(
        sourceLabel: "Build Feed Pending",
        sourceMode: "Managed feed preferred",
        officialStatus: "Derived source",
        confidenceLabel: "Pending",
        freshnessLabel: "Unknown",
        updatedLabel: "No forecast loaded",
        validWindowLabel: "No valid window yet",
        note: "Forecast Intelligence prefers processed Build feeds first, then uses live provider fallback only when needed."
    )

    private let feedRepository: ForecastFeedRepository
    private let liveDataClient: ForecastLiveDataClient
    private let metricBuilder: ForecastMetricCardBuilding
    private let evidenceManager: ForecastEvidencePromotionManaging
    private let evidenceQueue = DispatchQueue(label: "com.climateliberator.forecast-evidence", qos: .utility)
    private var resolvedCoordinate = CLLocationCoordinate2D(latitude: 12.9716, longitude: 77.5946)
    private var currentGeneratedAt: Date?
    private var currentValidFrom: Date?
    private var currentValidTo: Date?
    private var activeProviderID = ""
    private var activeSourceMode: ForecastSourceMode = .processedFeed
    private var evidenceLocation: ForecastResolvedLocation?
    private var requestGeneration = 0

    convenience init() {
        let snapshotStore = FileSystemForecastEvidenceSnapshotStore()
        self.init(feedRepository: BuildForecastFeedRepository(),
                  liveDataClient: OpenMeteoForecastLiveClient(),
                  metricBuilder: ForecastMetricCardBuilder(),
                  evidenceManager: ForecastEvidencePromotionManager(snapshotStore: snapshotStore))
    }

    init(feedRepository: ForecastFeedRepository,
         liveDataClient: ForecastLiveDataClient,
         metricBuilder: ForecastMetricCardBuilding,
         evidenceManager: ForecastEvidencePromotionManaging) {
        self.feedRepository = feedRepository
        self.liveDataClient = liveDataClient
        self.metricBuilder = metricBuilder
        self.evidenceManager = evidenceManager
        loadBuildSupportFeeds()
        loadPersistedForecastEvidence()
    }

    var capabilityVariables: [ForecastBusinessVariable] {
        ForecastBusinessVariable.allCases
    }

    var locationPins: [ForecastLocationPin] {
        [ForecastLocationPin(coordinate: resolvedCoordinate, tint: airQualityTint)]
    }

    var providerNote: String {
        "Imported processed feeds in this user's Application Support folder work offline for nearby locations. Location search and live Open-Meteo fallback require a network connection. No national forecast is generated from missing local data."
    }

    var sourceState: ForecastSourceState {
        let freshness = trustSummary.freshnessLabel.lowercased()
        if weatherCards.isEmpty && airQualityCards.isEmpty {
            return .forecastUnavailable
        }
        if freshness.contains("stale") {
            return .staleData
        }
        if activeSourceMode == .liveFallback {
            return .liveProviderFallback
        }
        return .processedFeedActive
    }

    var sourceStateTitle: String { sourceState.title }
    var sourceStateDetail: String { sourceState.detail }
    var sourceStateShortLabel: String { sourceState.shortLabel }
    var sourceStateColor: Color { sourceState.accentColor }

    var forecastVariablesSubtitle: String {
        switch sourceState {
        case .processedFeedActive:
            return "Source: processed forecast feed"
        case .liveProviderFallback:
            return "Source: live provider fallback"
        case .staleData:
            return "Source: processed forecast feed requiring freshness review"
        case .forecastUnavailable:
            return "No approved forecast source is available for this selection."
        }
    }

    var airQualitySubtitle: String {
        if !airQualityCards.isEmpty {
            return selectedHorizon == .shortTerm
                ? "Air-quality outlook is active for the current short-term window."
                : "Air-quality outlook is supplied by a processed feed for this horizon."
        }
        if selectedHorizon == .shortTerm {
            return "Air quality is currently unavailable for this selection."
        }
        return "Air Quality Not Available For This Horizon"
    }

    var latestExecutiveSnapshot: ForecastEvidenceSnapshot? {
        executiveEligibleSnapshots.first
    }

    var latestDisclosureSnapshot: ForecastEvidenceSnapshot? {
        disclosureEligibleSnapshots.first
    }

    var providerTrustEntries: [ForecastProviderTrustEntry] {
        providerTrustFeed?.providers ?? []
    }

    func searchAndLoad() async {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            statusMessage = "Enter a location to pull forecast data."
            return
        }

        isLoading = true
        requestGeneration += 1
        let generation = requestGeneration
        defer { if generation == requestGeneration { isLoading = false } }

        do {
            let match = try await liveDataClient.resolveLocation(query: query)
            guard generation == requestGeneration, !Task.isCancelled else { return }
            guard CLLocationCoordinate2DIsValid(match.coordinate) else { throw URLError(.badServerResponse) }
            selectedLocationName = match.name
            resolvedCoordinate = match.coordinate
            mapRegion = MKCoordinateRegion(
                center: match.coordinate,
                span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
            )
        } catch {
            guard generation == requestGeneration else { return }
            statusMessage = "Could not resolve the searched location. Location search requires a network connection; the selected location has not changed."
            return
        }
        do {
            try await refreshForecast()
        } catch {
            // refreshForecast already distinguishes a data failure from a location-search failure.
        }
    }

    func refreshForecast() async throws {
        isLoading = true
        requestGeneration += 1
        let generation = requestGeneration
        let horizon = selectedHorizon
        let coordinate = resolvedCoordinate
        defer { if generation == requestGeneration { isLoading = false } }
        clearCurrentForecast()
        loadBuildSupportFeeds()

        if let processedFeed = feedRepository.loadProcessedFeed(near: coordinate, horizon: horizon),
           !processedFeed.isSynthetic {
            applyProcessedFeed(processedFeed)
            persistCurrentSnapshot()
            return
        }

        do {
        if horizon == .shortTerm {
            async let weatherResponse = liveDataClient.fetchWeatherForecast(for: coordinate, horizon: horizon)
            async let airQualityResponse = try? liveDataClient.fetchAirQualityForecast(for: coordinate)

            let weather = try await weatherResponse
            let airQuality = await airQualityResponse
            guard generation == requestGeneration, horizon == selectedHorizon, !Task.isCancelled else { return }

            weatherCards = metricBuilder.buildWeatherCards(from: weather)
            guard !weatherCards.isEmpty else { throw URLError(.cannotParseResponse) }
            airQualityCards = airQuality.map { metricBuilder.buildAirQualityCards(from: $0) } ?? []
            activeProviderID = "open_meteo"
            activeSourceMode = .liveFallback
            providerLabel = "Open-Meteo"
            trustSummary = ForecastTrustSummary(
                sourceLabel: "Open-Meteo",
                sourceMode: "Live provider fallback",
                officialStatus: "Derived provider data",
                confidenceLabel: "Medium",
                freshnessLabel: "Retrieved just now; model freshness unknown",
                updatedLabel: "Provider issue time unavailable",
                validWindowLabel: "Requested 7 days; validity not verified",
                note: "Network fallback, not an observed risk measurement. Retrieval time is not the model issue time. No eligible nearby processed feed was available."
            )
            statusMessage = "\(horizon.title) outlook retrieved for \(selectedLocationName)." + (airQualityCards.isEmpty ? " Air quality is unavailable." : "")
            persistCurrentSnapshot()
            return
        }

        let seasonalForecast = try await liveDataClient.fetchSeasonalForecast(for: coordinate, horizon: horizon)
        guard generation == requestGeneration, horizon == selectedHorizon, !Task.isCancelled else { return }
        weatherCards = metricBuilder.buildWeatherCards(from: seasonalForecast)
        guard !weatherCards.isEmpty else { throw URLError(.cannotParseResponse) }
        airQualityCards = []
        activeProviderID = "open_meteo_seasonal"
        activeSourceMode = .liveFallback
        providerLabel = "Open-Meteo Seasonal"
        trustSummary = ForecastTrustSummary(
            sourceLabel: "Open-Meteo Seasonal",
            sourceMode: "Live provider fallback",
            officialStatus: "Derived provider data",
            confidenceLabel: selectedHorizon == .subseasonal ? "Medium" : "Watch",
            freshnessLabel: "Retrieved just now; model freshness unknown",
            updatedLabel: "Provider issue time unavailable",
            validWindowLabel: horizon == .subseasonal ? "Requested 46 days; validity not verified" : "Requested 183 days; validity not verified",
            note: "Network seasonal guidance, not an observed risk measurement. Provider issue time and validity are not verified. Air quality requires a managed feed on this horizon."
        )
        statusMessage = "\(selectedHorizon.title) weather outlook refreshed for \(selectedLocationName). Air-quality guidance requires a processed feed on this horizon."
        persistCurrentSnapshot()
        } catch {
            guard generation == requestGeneration, horizon == selectedHorizon else { return }
            setRefreshFailureMessage()
            throw error
        }
    }

    func updateHorizon(_ horizon: ForecastHorizon) async {
        selectedHorizon = horizon
        do {
            try await refreshForecast()
        } catch {
            // The active refresh owns its failure state; an older request must not overwrite it.
        }
    }

    func setRefreshFailureMessage() {
        clearCurrentForecast()
        trustSummary = ForecastTrustSummary(
            sourceLabel: "Forecast unavailable",
            sourceMode: "Refresh failed",
            officialStatus: "No current source",
            confidenceLabel: "Unknown",
            freshnessLabel: "Unknown",
            updatedLabel: "No forecast loaded",
            validWindowLabel: "No valid window",
            note: "No eligible nearby imported feed was available and the network refresh failed. Previous selection data is not used as a substitute."
        )
        statusMessage = "Forecast refresh failed for \(selectedLocationName)."
    }

    func promoteLatestSnapshotToExecutive() {
        updateLatestSnapshotPromotionLevel(.executiveEligible, message: "Snapshot promoted to Home.")
    }

    func promoteLatestSnapshotToDisclosure() {
        updateLatestSnapshotPromotionLevel(.disclosureEligible, message: "Snapshot promoted to disclosure support.")
    }

    func refreshBuildSupportFeeds() {
        loadBuildSupportFeeds()
    }

    private func applyProcessedFeed(_ feed: ProcessedForecastFeed) {
        evidenceLocation = ForecastResolvedLocation(name: feed.locationLabel, coordinate: feed.coordinate)
        activeProviderID = feed.providerID
        activeSourceMode = feed.sourceMode
        providerLabel = feed.providerLabel
        weatherCards = feed.weatherMetrics.map(\.card)
        airQualityCards = feed.airQualityMetrics.map(\.card)
        currentGeneratedAt = feed.generatedAt
        currentValidFrom = feed.validFrom
        currentValidTo = feed.validTo
        trustSummary = feed.trustSummary.summary(
            providerLabel: feed.providerLabel,
            generatedAt: feed.generatedAt,
            validFrom: feed.validFrom,
            validTo: feed.validTo
        )
        let distance = CLLocation(latitude: resolvedCoordinate.latitude, longitude: resolvedCoordinate.longitude)
            .distance(from: CLLocation(latitude: feed.latitude, longitude: feed.longitude)) / 1000
        statusMessage = (feed.statusSummary ?? "\(selectedHorizon.title) outlook loaded from an imported feed.")
            + " Feed location: \(feed.locationLabel) (\(String(format: "%.1f", distance)) km from selection). Not national coverage."
    }

    private func clearCurrentForecast() {
        weatherCards = []
        airQualityCards = []
        currentGeneratedAt = nil
        currentValidFrom = nil
        currentValidTo = nil
        activeProviderID = ""
        evidenceLocation = nil
        providerLabel = "No current provider"
        lastSnapshotMessage = nil
    }

    private func loadBuildSupportFeeds() {
        let feeds = feedRepository.loadBuildSupportFeeds()
        forecastOverview = feeds.overview
        providerTrustFeed = feeds.providerTrust
        warningSummary = feeds.warningSummary
    }

    private func persistCurrentSnapshot() {
        let context = currentSnapshotContext()
        performEvidenceOperation(message: "Snapshot stored for operational use.") { manager in
            try manager.persistOperationalSnapshot(from: context)
        }
    }

    private func loadPersistedForecastEvidence() {
        performEvidenceOperation { $0.loadSnapshotCollections() }
    }

    private func updateLatestSnapshotPromotionLevel(_ promotionLevel: ForecastPromotionLevel, message: String) {
        guard !weatherCards.isEmpty || !airQualityCards.isEmpty else {
            lastSnapshotMessage = "No current forecast snapshot is available to promote."
            return
        }
        let context = currentSnapshotContext()
        performEvidenceOperation(message: message) { manager in
            try manager.promoteSnapshot(from: context, to: promotionLevel)
        }
    }

    private func performEvidenceOperation(message: String? = nil,
        _ operation: @escaping @Sendable (ForecastEvidencePromotionManaging) throws -> ForecastSnapshotCollections) {
        let manager = evidenceManager
        // Documents can be cloud-backed. Serialize evidence I/O without blocking
        // launch or allowing reads and promotions to race one another.
        evidenceQueue.async { [weak self] in
            let result = Result { try operation(manager) }
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                switch result {
                case .success(let collections):
                    self.applySnapshotCollections(collections)
                    if let message { self.lastSnapshotMessage = message }
                case .failure:
                    self.lastSnapshotMessage = "Forecast evidence could not be read or written."
                }
            }
        }
    }

    private var airQualityTint: Color {
        guard let aqiCard = airQualityCards.first,
              let value = Double(aqiCard.value.components(separatedBy: " ").first ?? "") else {
            return .blue
        }
        switch value {
        case ..<50: return .green
        case ..<100: return .yellow
        case ..<150: return .orange
        default: return .red
        }
    }

    private func currentSnapshotContext() -> ForecastSnapshotContext {
        ForecastSnapshotContext(
            providerID: activeProviderID,
            providerLabel: providerLabel,
            sourceMode: activeSourceMode,
            horizon: selectedHorizon,
            confidence: currentConfidence,
            generatedAt: currentGeneratedAt,
            validFrom: currentValidFrom,
            validTo: currentValidTo,
            locationLabel: evidenceLocation?.name ?? selectedLocationName,
            coordinate: evidenceLocation?.coordinate ?? resolvedCoordinate,
            statusSummary: statusMessage,
            weatherCards: weatherCards,
            airQualityCards: airQualityCards
        )
    }

    private var currentConfidence: ForecastConfidence {
        switch trustSummary.confidenceLabel.lowercased() {
        case let value where value.contains("high"):
            return .high
        case let value where value.contains("medium"):
            return .medium
        case let value where value.contains("watch"):
            return .watch
        case let value where value.contains("low"):
            return .low
        default:
            return .unknown
        }
    }

    private func applySnapshotCollections(_ collections: ForecastSnapshotCollections) {
        executiveEligibleSnapshots = collections.executiveEligibleSnapshots
        disclosureEligibleSnapshots = collections.disclosureEligibleSnapshots
    }
}

struct ProcessedForecastFeed: Decodable {
    let snapshotID: String
    let providerID: String
    let providerLabel: String
    let locationLabel: String
    let latitude: Double
    let longitude: Double
    let forecastHorizon: String
    let generatedAt: Date?
    let validFrom: Date?
    let validTo: Date?
    let statusSummary: String?
    let trustSummary: ProcessedForecastTrustSummary
    let weatherMetrics: [ProcessedForecastMetric]
    let airQualityMetrics: [ProcessedForecastMetric]
    let synthetic: Bool?

    var isSynthetic: Bool {
        synthetic == true || [providerID, providerLabel, trustSummary.sourceMode, trustSummary.note]
            .contains { $0.localizedCaseInsensitiveContains("synthetic") || $0.localizedCaseInsensitiveContains("demo") }
    }

    var sourceMode: ForecastSourceMode {
        let mode = trustSummary.sourceMode.lowercased()
        if mode.contains("fallback") { return .liveFallback }
        if mode.contains("curated") || mode.contains("scenario") { return .curatedScenarioInput }
        return .processedFeed
    }

    enum CodingKeys: String, CodingKey {
        case snapshotID = "snapshot_id"
        case providerID = "provider_id"
        case providerLabel = "provider_label"
        case locationLabel = "location_label"
        case latitude
        case longitude
        case forecastHorizon = "forecast_horizon"
        case generatedAt = "generated_at"
        case validFrom = "valid_from"
        case validTo = "valid_to"
        case statusSummary = "status_summary"
        case trustSummary = "trust_summary"
        case weatherMetrics = "weather_metrics"
        case airQualityMetrics = "air_quality_metrics"
        case synthetic
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

struct ProcessedForecastTrustSummary: Decodable {
    let sourceMode: String
    let officialStatus: String
    let confidenceLabel: String
    let freshnessLabel: String?
    let note: String

    enum CodingKeys: String, CodingKey {
        case sourceMode = "source_mode"
        case officialStatus = "official_status"
        case confidenceLabel = "confidence_label"
        case freshnessLabel = "freshness_label"
        case note
    }

    func summary(providerLabel: String,
                 generatedAt: Date?,
                 validFrom: Date?,
                 validTo: Date?) -> ForecastTrustSummary {
        ForecastTrustSummary(
            sourceLabel: providerLabel,
            sourceMode: sourceMode,
            officialStatus: officialStatus,
            confidenceLabel: confidenceLabel,
            freshnessLabel: freshnessLabel ?? derivedFreshnessLabel(generatedAt: generatedAt),
            updatedLabel: generatedAt.map(Self.relativeTimestamp) ?? "Updated time unavailable",
            validWindowLabel: validWindowLabel(validFrom: validFrom, validTo: validTo),
            note: note
        )
    }

    private func derivedFreshnessLabel(generatedAt: Date?) -> String {
        guard let generatedAt else { return "Freshness unknown" }
        let ageHours = Date().timeIntervalSince(generatedAt) / 3600
        switch ageHours {
        case ..<6:
            return "Fresh"
        case ..<24:
            return "Watch"
        default:
            return "Stale"
        }
    }

    private func validWindowLabel(validFrom: Date?, validTo: Date?) -> String {
        guard let validFrom, let validTo else { return "Valid window unavailable" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return "Valid \(formatter.string(from: validFrom)) to \(formatter.string(from: validTo))"
    }

    nonisolated private static func relativeTimestamp(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return "Updated \(formatter.localizedString(for: date, relativeTo: Date()))"
    }
}

struct ProcessedForecastMetric: Decodable {
    let id: String
    let title: String
    let value: String
    let detail: String

    var card: ForecastMetricCard {
        ForecastMetricCard(id: id, title: title, value: value, detail: detail)
    }
}

struct OpenMeteoWeatherResponse: Decodable {
    let daily: Daily
    let dailyUnits: DailyUnits

    enum CodingKeys: String, CodingKey {
        case daily
        case dailyUnits = "daily_units"
    }

    struct Daily: Decodable {
        let temperature2MMean: [Double]?
        let temperature2MMax: [Double]?
        let temperature2MMin: [Double]?
        let precipitationSum: [Double]?
        let soilTemperature0cmMean: [Double]?
        let relativeHumidity2MMean: [Double]?
        let et0FaoEvapotranspiration: [Double]?
        let shortwaveRadiationSum: [Double]?
        let soilMoisture0To1cmMean: [Double]?
        let windSpeed10MMean: [Double]?

        enum CodingKeys: String, CodingKey {
            case temperature2MMean = "temperature_2m_mean"
            case temperature2MMax = "temperature_2m_max"
            case temperature2MMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
            case soilTemperature0cmMean = "soil_temperature_0cm_mean"
            case relativeHumidity2MMean = "relative_humidity_2m_mean"
            case et0FaoEvapotranspiration = "et0_fao_evapotranspiration"
            case shortwaveRadiationSum = "shortwave_radiation_sum"
            case soilMoisture0To1cmMean = "soil_moisture_0_to_1cm_mean"
            case windSpeed10MMean = "wind_speed_10m_mean"
        }
    }

    struct DailyUnits: Decodable {
        let temperature2MMean: String?
        let temperature2MMax: String?
        let temperature2MMin: String?
        let precipitationSum: String?
        let soilTemperature0cmMean: String?
        let relativeHumidity2MMean: String?
        let et0FaoEvapotranspiration: String?
        let shortwaveRadiationSum: String?
        let soilMoisture0To1cmMean: String?
        let windSpeed10MMean: String?

        enum CodingKeys: String, CodingKey {
            case temperature2MMean = "temperature_2m_mean"
            case temperature2MMax = "temperature_2m_max"
            case temperature2MMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
            case soilTemperature0cmMean = "soil_temperature_0cm_mean"
            case relativeHumidity2MMean = "relative_humidity_2m_mean"
            case et0FaoEvapotranspiration = "et0_fao_evapotranspiration"
            case shortwaveRadiationSum = "shortwave_radiation_sum"
            case soilMoisture0To1cmMean = "soil_moisture_0_to_1cm_mean"
            case windSpeed10MMean = "wind_speed_10m_mean"
        }
    }
}

struct OpenMeteoAirQualityResponse: Decodable {
    let hourly: Hourly
    let hourlyUnits: HourlyUnits

    enum CodingKeys: String, CodingKey {
        case hourly
        case hourlyUnits = "hourly_units"
    }

    struct Hourly: Decodable {
        let usAQI: [Double]?
        let pm10: [Double]?
        let pm25: [Double]?
        let ozone: [Double]?
        let nitrogenDioxide: [Double]?
        let sulphurDioxide: [Double]?
        let carbonMonoxide: [Double]?

        enum CodingKeys: String, CodingKey {
            case usAQI = "us_aqi"
            case pm10
            case pm25 = "pm2_5"
            case ozone
            case nitrogenDioxide = "nitrogen_dioxide"
            case sulphurDioxide = "sulphur_dioxide"
            case carbonMonoxide = "carbon_monoxide"
        }
    }

    struct HourlyUnits: Decodable {
        let usAQI: String?
        let pm10: String?
        let pm25: String?
        let ozone: String?

        enum CodingKeys: String, CodingKey {
            case usAQI = "us_aqi"
            case pm10
            case pm25 = "pm2_5"
            case ozone
        }
    }
}

struct OpenMeteoSeasonalResponse: Decodable {
    let daily: Daily
    let dailyUnits: DailyUnits

    enum CodingKeys: String, CodingKey {
        case daily
        case dailyUnits = "daily_units"
    }

    struct Daily: Decodable {
        let temperature2MMean: [Double]?
        let temperature2MMax: [Double]?
        let temperature2MMin: [Double]?
        let precipitationSum: [Double]?
        let soilTemperature0To7cmMean: [Double]?
        let relativeHumidity2MMean: [Double]?
        let et0FaoEvapotranspiration: [Double]?
        let shortwaveRadiationSum: [Double]?
        let soilMoisture0To7cmMean: [Double]?
        let windSpeed10MMean: [Double]?

        enum CodingKeys: String, CodingKey {
            case temperature2MMean = "temperature_2m_mean"
            case temperature2MMax = "temperature_2m_max"
            case temperature2MMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
            case soilTemperature0To7cmMean = "soil_temperature_0_to_7cm_mean"
            case relativeHumidity2MMean = "relative_humidity_2m_mean"
            case et0FaoEvapotranspiration = "et0_fao_evapotranspiration"
            case shortwaveRadiationSum = "shortwave_radiation_sum"
            case soilMoisture0To7cmMean = "soil_moisture_0_to_7cm_mean"
            case windSpeed10MMean = "wind_speed_10m_mean"
        }
    }

    struct DailyUnits: Decodable {
        let temperature2MMean: String?
        let temperature2MMax: String?
        let temperature2MMin: String?
        let precipitationSum: String?
        let soilTemperature0To7cmMean: String?
        let relativeHumidity2MMean: String?
        let et0FaoEvapotranspiration: String?
        let shortwaveRadiationSum: String?
        let soilMoisture0To7cmMean: String?
        let windSpeed10MMean: String?

        enum CodingKeys: String, CodingKey {
            case temperature2MMean = "temperature_2m_mean"
            case temperature2MMax = "temperature_2m_max"
            case temperature2MMin = "temperature_2m_min"
            case precipitationSum = "precipitation_sum"
            case soilTemperature0To7cmMean = "soil_temperature_0_to_7cm_mean"
            case relativeHumidity2MMean = "relative_humidity_2m_mean"
            case et0FaoEvapotranspiration = "et0_fao_evapotranspiration"
            case shortwaveRadiationSum = "shortwave_radiation_sum"
            case soilMoisture0To7cmMean = "soil_moisture_0_to_7cm_mean"
            case windSpeed10MMean = "wind_speed_10m_mean"
        }
    }
}
