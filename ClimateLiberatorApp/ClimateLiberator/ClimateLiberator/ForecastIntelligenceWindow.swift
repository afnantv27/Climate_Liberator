import SwiftUI
import MapKit

struct ForecastIntelligenceWindow: View {
    @ObservedObject var store: ForecastIntelligenceStore
    @State private var mapCameraPosition: MapCameraPosition = .automatic

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.05, blue: 0.09),
                    Color(red: 0.05, green: 0.09, blue: 0.15),
                    Color(red: 0.09, green: 0.13, blue: 0.18)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            HStack(alignment: .top, spacing: 20) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        headerCard
                        sourceStateBanner
                        controlCard
                        trustCard
                        capabilityMatrixCard
                        buildOverviewCard
                        providerTrustCard
                        warningSummaryCard
                        providerCard
                    }
                    .padding(24)
                }
                .frame(width: 360)

                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        mapCard
                        metricsGrid
                        airQualityGrid
                    }
                    .padding(.vertical, 24)
                    .padding(.trailing, 24)
                }
            }
        }
        .task {
            mapCameraPosition = .region(store.mapRegion)
            if store.weatherCards.isEmpty && store.airQualityCards.isEmpty {
                do {
                    try await store.refreshForecast()
                } catch {
                    store.setRefreshFailureMessage()
                }
            }
        }
        .onChange(of: store.selectedLocationName) { _, _ in
            mapCameraPosition = .region(store.mapRegion)
        }
    }

    private var headerCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Forecast Intelligence")
                    .font(.appPageTitle)
                    .foregroundColor(.white)
                Text("A dedicated weather, climate-variable, and air-quality outlook window for business planning. Keep it separate from hazard execution and disclosure review.")
                    .font(.body)
                    .foregroundColor(Color.white.opacity(0.78))
            }
        }
    }

    private var controlCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Location Search")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)

                TextField("Search city, district, facility, or asset location", text: $store.searchQuery)
                    .textFieldStyle(.roundedBorder)

                Picker("Forecast Horizon", selection: $store.selectedHorizon) {
                    ForEach(ForecastHorizon.allCases) { horizon in
                        Text(horizon.title).tag(horizon)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.selectedHorizon) { _, newValue in
                    Task { await store.updateHorizon(newValue) }
                }

                Text("Source state: \(store.sourceStateTitle)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(store.sourceStateColor.opacity(0.95))

                HStack(spacing: 12) {
                    Button("Search And Load") {
                        Task { await store.searchAndLoad() }
                    }
                    .buttonStyle(.borderedProminent)

                    Button("Refresh Forecast") {
                        Task {
                            do {
                                try await store.refreshForecast()
                            } catch {
                                store.setRefreshFailureMessage()
                            }
                        }
                    }
                    .buttonStyle(.bordered)
                }

                HStack(spacing: 12) {
                    Button("Promote To Executive") {
                        store.promoteLatestSnapshotToExecutive()
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.weatherCards.isEmpty)

                    Button("Promote To Disclosure") {
                        store.promoteLatestSnapshotToDisclosure()
                    }
                    .buttonStyle(.bordered)
                    .disabled(store.weatherCards.isEmpty)
                }

                Text(store.statusMessage)
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.7))

                if let message = store.lastSnapshotMessage {
                    Text(message)
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.62))
                }
            }
        }
    }

    private var sourceStateBanner: some View {
        dashboardCard {
            HStack(alignment: .top, spacing: 14) {
                Circle()
                    .fill(store.sourceStateColor.opacity(0.9))
                    .frame(width: 12, height: 12)
                    .padding(.top, 6)

                VStack(alignment: .leading, spacing: 8) {
                    Text(store.sourceStateTitle)
                        .font(.headline)
                        .foregroundColor(.white)
                    Text(store.sourceStateDetail)
                        .font(.footnote)
                        .foregroundColor(Color.white.opacity(0.74))
                    Text("\(store.trustSummary.updatedLabel) • \(store.trustSummary.validWindowLabel)")
                        .font(.caption)
                        .foregroundColor(Color.white.opacity(0.62))
                }

                Spacer()
            }
        }
    }

    private var capabilityMatrixCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Variable Support Matrix")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)

                Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 10) {
                    GridRow {
                        matrixHeader("Variable")
                        matrixHeader("Query Value")
                        matrixHeader("Seasonal")
                        matrixHeader("Subseasonal")
                        matrixHeader("Short Term")
                    }
                    ForEach(store.capabilityVariables) { variable in
                        GridRow {
                            matrixValue(variable.title)
                            matrixValue(variable.queryValue)
                            supportMark(variable.supportsSeasonal)
                            supportMark(variable.supportsSubseasonal)
                            supportMark(variable.supportsShortTerm)
                        }
                    }
                }
            }
        }
    }

    private var providerCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Provider Strategy")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)
                Text(store.providerNote)
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.74))
                Text("Current source: \(store.providerLabel)")
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color.white.opacity(0.82))
                Text("Recommended path for India: processed Build feeds first, Open-Meteo fallback for short-term and longer-horizon weather, then managed overlays for official warnings, air quality, and SLA-backed operations.")
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.68))
            }
        }
    }

    private var buildOverviewCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Build Coverage")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)

                if let overview = store.forecastOverview {
                    summaryRow(title: "Locations", value: "\(overview.locationCount)")
                    summaryRow(title: "Providers", value: "\(overview.providerCount)")
                    summaryRow(title: "Subseasonal", value: "\(overview.subseasonalLocationCount)")
                    summaryRow(title: "Seasonal", value: "\(overview.seasonalLocationCount)")
                    summaryRow(title: "Warning-ready", value: "\(overview.warningReadyLocationCount)")
                } else {
                    Text("No Build forecast overview feed is available yet.")
                        .font(.footnote)
                        .foregroundColor(Color.white.opacity(0.68))
                }
            }
        }
    }

    private var providerTrustCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Provider Trust")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)

                if store.providerTrustEntries.isEmpty {
                    Text("No provider trust feed is available yet.")
                        .font(.footnote)
                        .foregroundColor(Color.white.opacity(0.68))
                } else {
                    ForEach(store.providerTrustEntries.prefix(2)) { provider in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(provider.providerName)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("Trust: \(provider.trustLevel.capitalized) • Fresh snapshots: \(provider.freshSnapshotCount)")
                                .font(.footnote)
                                .foregroundColor(Color.white.opacity(0.72))
                        }
                    }
                }
            }
        }
    }

    private var warningSummaryCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Warning Readiness")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)

                if let warningSummary = store.warningSummary {
                    summaryRow(title: "Warning-ready locations", value: "\(warningSummary.warningReadyLocationCount)")
                    summaryRow(title: "Subseasonal watches", value: "\(warningSummary.subseasonalWatchCount)")
                    summaryRow(title: "Seasonal watches", value: "\(warningSummary.seasonalWatchCount)")
                    summaryRow(title: "Overlay-ready locations", value: "\(warningSummary.overlayReadyLocationCount)")
                } else {
                    Text("No warning summary feed is available yet.")
                        .font(.footnote)
                        .foregroundColor(Color.white.opacity(0.68))
                }
            }
        }
    }

    private var trustCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Data Trust")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    trustPill(title: "Source", value: store.trustSummary.sourceLabel)
                    trustPill(title: "Mode", value: store.trustSummary.sourceMode)
                    trustPill(title: "Confidence", value: store.trustSummary.confidenceLabel)
                    trustPill(title: "Freshness", value: store.trustSummary.freshnessLabel)
                    trustPill(title: "Official Status", value: store.trustSummary.officialStatus)
                    trustPill(title: "Last Updated", value: store.trustSummary.updatedLabel)
                }

                Text(store.trustSummary.validWindowLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color.white.opacity(0.82))

                Text(store.trustSummary.note)
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.68))
            }
        }
    }

    private var mapCard: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.selectedLocationName)
                            .font(.appSectionTitle)
                            .foregroundColor(.white)
                        Text(store.selectedHorizon.providerStatus)
                            .font(.footnote)
                            .foregroundColor(Color.white.opacity(0.72))
                    }
                    Spacer()
                    Text(store.sourceStateShortLabel)
                        .font(.caption.weight(.semibold))
                        .foregroundColor(.white)
                        .padding(.vertical, 8)
                        .padding(.horizontal, 10)
                        .background(
                            Capsule(style: .continuous)
                                .fill(store.sourceStateColor.opacity(0.25))
                        )
                }

                Map(position: $mapCameraPosition) {
                    ForEach(store.locationPins) { pin in
                        Marker(store.selectedLocationName, coordinate: pin.coordinate)
                            .tint(pin.tint)
                    }
                }
                .frame(height: 320)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
        }
    }

    private var metricsGrid: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Forecast Variables")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)
                Text(store.forecastVariablesSubtitle)
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.68))

                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                    ForEach(store.weatherCards) { card in
                        metricCard(card)
                    }
                }
            }
        }
    }

    private var airQualityGrid: some View {
        dashboardCard {
            VStack(alignment: .leading, spacing: 14) {
                Text("Air Quality Outlook")
                    .font(.appSectionTitle)
                    .foregroundColor(.white)
                Text(store.airQualitySubtitle)
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.68))

                if store.airQualityCards.isEmpty {
                    EmptyView()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                        ForEach(store.airQualityCards) { card in
                            metricCard(card)
                        }
                    }
                }
            }
        }
    }

    private func metricCard(_ card: ForecastMetricCard) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(card.title)
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.74))
            Text(card.value)
                .font(.appMetric)
                .foregroundColor(.white)
            Text(card.detail)
                .font(.caption)
                .foregroundColor(Color.white.opacity(0.64))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.footnote)
                .foregroundColor(Color.white.opacity(0.7))
            Spacer()
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
        }
    }

    private func dashboardCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            content()
        }
        .padding(22)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func trustPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color.white.opacity(0.58))
            Text(value)
                .font(.footnote.weight(.semibold))
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func matrixHeader(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.semibold))
            .foregroundColor(Color.white.opacity(0.66))
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func matrixValue(_ text: String) -> some View {
        Text(text)
            .font(.footnote)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func supportMark(_ supported: Bool) -> some View {
        Image(systemName: supported ? "checkmark" : "xmark")
            .foregroundColor(supported ? .green : .red)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
