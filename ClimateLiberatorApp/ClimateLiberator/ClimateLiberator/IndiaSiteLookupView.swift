import SwiftUI
import CoreLocation

struct IndiaSiteLookupView: View {
    @ObservedObject var store: IndiaRiskStore
    let currentCoordinate: CLLocationCoordinate2D
    let onRefreshNearby: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("India Risk Database")
                        .font(.headline)
                    Text(store.statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Refresh DB") {
                    store.refreshDatabaseStatus()
                }
            }

            TextField("India database path", text: $store.databasePath)
                .textFieldStyle(.roundedBorder)

            HStack {
                infoMetric(title: "Imported Buildings", value: "\(store.buildingCount)")
                infoMetric(title: "Database", value: store.databaseConnected ? "Connected" : "Offline")
                infoMetric(title: "Queryable", value: store.lookupAvailability.isEnabled ? "Ready" : "Waiting")
                infoMetric(title: "Search Radius", value: "\(Int(store.radiusMeters)) m")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Current Site")
                    .font(.subheadline.weight(.semibold))
                Text(String(format: "Lat %.5f, Lon %.5f", currentCoordinate.latitude, currentCoordinate.longitude))
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(.secondary)
                Slider(value: $store.radiusMeters, in: 250...5000, step: 250)
                Button("Lookup Buildings Near Current Site") {
                    onRefreshNearby()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!store.lookupAvailability.isEnabled)
                if let reason = store.lookupAvailability.reason {
                    Text(reason)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            if store.lookupSummary.buildingCount > 0 {
                HStack {
                    infoMetric(title: "Nearby Buildings", value: "\(store.lookupSummary.buildingCount)")
                    infoMetric(title: "Footprint", value: String(format: "%.0f m²", store.lookupSummary.totalFootprintM2))
                    infoMetric(title: "Built-up", value: String(format: "%.0f m²", store.lookupSummary.totalBuiltUpM2))
                }

                if riskSnapshot.assessedCount > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Site Risk Snapshot")
                            .font(.subheadline.weight(.semibold))

                        HStack {
                            infoMetric(title: "Risk Assessed", value: "\(riskSnapshot.assessedCount)")
                            infoMetric(title: "High", value: "\(riskSnapshot.highCount)")
                            infoMetric(title: "Medium", value: "\(riskSnapshot.mediumCount)")
                            infoMetric(title: "Low", value: "\(riskSnapshot.lowCount)")
                        }

                        RiskDistributionChart(snapshot: riskSnapshot)
                    }
                }
            }

            if store.nearbyBuildings.isEmpty {
                Text(store.nearbyEmptyStateMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Nearby Buildings")
                        .font(.subheadline.weight(.semibold))
                    ForEach(store.nearbyBuildings.prefix(8)) { building in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(building.landuse ?? "Unclassified")
                                    .font(.headline)
                                Spacer()
                                Text(String(format: "%.0f m", building.distanceMeters))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Text("\(building.districtName), \(building.stateCode)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text(detailLine(for: building))
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                            if let riskBand = building.riskBand {
                                Text("Stored wildfire risk: \(riskBand)\(building.scenarioLabel.map { " • \($0)" } ?? "")")
                                    .font(.footnote)
                            } else {
                                Text("No stored wildfire risk assessment linked yet.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(12)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.secondary.opacity(0.08))
                        )
                    }
                }
            }
        }
    }

    private func detailLine(for building: IndiaNearbyBuilding) -> String {
        let area = building.areaM2.map { String(format: "Footprint %.0f m²", $0) } ?? "Footprint n/a"
        let builtUp = building.builtUpM2.map { String(format: "Built-up %.0f m²", $0) } ?? "Built-up n/a"
        let floors = building.floorCount.map { "\($0) floors" } ?? "Floors n/a"
        return "\(area) • \(builtUp) • \(floors)"
    }

    private var riskSnapshot: IndiaRiskSnapshot {
        IndiaRiskSnapshot(buildings: store.nearbyBuildings)
    }

    private func infoMetric(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct IndiaRiskSnapshot {
    let assessedCount: Int
    let highCount: Int
    let mediumCount: Int
    let lowCount: Int
    let unknownCount: Int

    init(buildings: [IndiaNearbyBuilding]) {
        var highCount = 0
        var mediumCount = 0
        var lowCount = 0
        var unknownCount = 0

        for building in buildings {
            guard let band = building.riskBand?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !band.isEmpty else {
                unknownCount += 1
                continue
            }

            switch band.lowercased() {
            case "high", "very high", "critical":
                highCount += 1
            case "medium", "moderate", "warning":
                mediumCount += 1
            case "low", "very low":
                lowCount += 1
            default:
                unknownCount += 1
            }
        }

        self.highCount = highCount
        self.mediumCount = mediumCount
        self.lowCount = lowCount
        self.unknownCount = unknownCount
        self.assessedCount = highCount + mediumCount + lowCount
    }

    var totalKnown: Int {
        max(assessedCount, 1)
    }
}

private struct RiskDistributionChart: View {
    let snapshot: IndiaRiskSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            riskBar(title: "High risk", count: snapshot.highCount, color: .red)
            riskBar(title: "Medium risk", count: snapshot.mediumCount, color: .orange)
            riskBar(title: "Low risk", count: snapshot.lowCount, color: .green)

            if snapshot.unknownCount > 0 {
                Text("\(snapshot.unknownCount) nearby building(s) do not have a stored wildfire assessment yet.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    private func riskBar(title: String, count: Int, color: Color) -> some View {
        let ratio = CGFloat(count) / CGFloat(snapshot.totalKnown)

        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.secondary.opacity(0.15))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(10, geometry.size.width * ratio))
                }
            }
            .frame(height: 10)
        }
    }
}
