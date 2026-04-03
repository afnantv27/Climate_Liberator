import SwiftUI

struct CommandCenterWorkspaceView: View {
    @ObservedObject var scenarioStore: ScenarioLibraryStore
    @ObservedObject var reviewStore: TCFDReviewStore
    @ObservedObject var forecastStore: ForecastIntelligenceStore
    @Binding var activeWorkspace: AppWorkspace

    let theme: ThemeStyle
    let enterpriseReadiness: EnterpriseReadinessSummary
    let latestDisclosureReportAvailability: ActionAvailability
    let logActionAvailability: ActionAvailability
    let operationsWorkspaceAvailability: ActionAvailability
    let portfolioIntelligenceAvailability: ActionAvailability
    let disclosureReviewAvailability: ActionAvailability
    let openTCFDDashboard: () -> Void
    let openForecastIntelligence: () -> Void
    let openOperationsLog: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.06, blue: 0.1),
                    Color(red: 0.07, green: 0.11, blue: 0.18),
                    Color(red: 0.13, green: 0.15, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(Color.teal.opacity(0.12))
                .frame(width: 520, height: 520)
                .blur(radius: 40)
                .offset(x: -320, y: -220)

            Circle()
                .fill(Color.blue.opacity(0.12))
                .frame(width: 460, height: 460)
                .blur(radius: 48)
                .offset(x: 360, y: 260)

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard

                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 18) {
                        executiveMetricCard(title: "Board-Pack Ready Packages",
                                            value: "\(reviewStore.readyForBoardCount())",
                                            detail: reviewStore.bundles.first?.runID ?? "No package generated yet")
                        executiveMetricCard(title: "Packages With Escalation",
                                            value: "\(reviewStore.escalatedCount())",
                                            detail: "\(reviewStore.breachedPackageCount()) package(s) with threshold pressure")
                        executiveMetricCard(title: "Packages Awaiting Finance Review",
                                            value: "\(reviewStore.financePendingCount())",
                                            detail: reviewStore.financePendingCount() == 0 ? "No package waiting on finance review" : "Finance sign-off still missing on package backlog")
                    }

                    HStack(alignment: .top, spacing: 18) {
                        dashboardPanelCard(title: "Workflow Readiness",
                                           subtitle: "High-level readiness only. Detailed blockers stay inside the owning workspace.") {
                            readinessRow(title: "Operations workspace", availability: operationsWorkspaceAvailability)
                            readinessRow(title: "Portfolio screening", availability: portfolioIntelligenceAvailability)
                            readinessRow(title: "Disclosure review", availability: disclosureReviewAvailability)
                        }

                        dashboardPanelCard(title: "Next Actions",
                                           subtitle: "Move into the next task without touching technical controls first.") {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("1. Screen site or portfolio • 2. Run scenario • 3. Review disclosure package • 4. Export approved board pack")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)

                                HStack(spacing: 12) {
                                    Button("Open Portfolio Intelligence") {
                                        activeWorkspace = .intelligence
                                    }
                                    .buttonStyle(.bordered)

                                    Button("Open Simulation Workspace") {
                                        activeWorkspace = .operations
                                    }
                                    .buttonStyle(.borderedProminent)

                                    Button("Open TCFD Dashboard") {
                                        openTCFDDashboard()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack(spacing: 12) {
                                    Button("Open Forecast Intelligence") {
                                        openForecastIntelligence()
                                    }
                                    .buttonStyle(.bordered)
                                }

                                HStack(spacing: 12) {
                                    Button("Open Latest Report") {
                                        if let latest = reviewStore.bundles.first {
                                            _ = AppActionSupport.openExistingPath(latest.reportURL, expectation: .file)
                                        }
                                    }
                                    .disabled(!latestDisclosureReportAvailability.isEnabled)
                                    .buttonStyle(.bordered)

                                    Button("Open Operations Log") {
                                        openOperationsLog()
                                    }
                                    .disabled(!logActionAvailability.isEnabled)
                                    .buttonStyle(.bordered)
                                }

                                if let message = latestDisclosureReportAvailability.reason {
                                    Text(message)
                                        .font(.footnote)
                                        .foregroundColor(theme.subtleTextColor)
                                } else if let message = logActionAvailability.reason {
                                    Text(message)
                                        .font(.footnote)
                                        .foregroundColor(theme.subtleTextColor)
                                }
                            }
                        }
                    }

                    dashboardPanelCard(title: "Forecast Evidence",
                                       subtitle: "Only persisted and promoted forecast snapshots appear here.") {
                        if let snapshot = forecastStore.latestExecutiveSnapshot {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(snapshot.locationLabel)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                Text("\(snapshot.horizon.capitalized) • \(snapshot.confidence.rawValue.capitalized) confidence")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                                Text(snapshot.statusSummary)
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            }
                        } else {
                            Text("No forecast snapshot has been promoted to Executive Overview yet. Promote a snapshot from Forecast Intelligence first.")
                                .font(.footnote)
                                .foregroundColor(theme.subtleTextColor)
                        }
                    }

                    dashboardPanelCard(title: "Disclosure Packages",
                                       subtitle: "Latest disclosure bundles generated from successful wildfire runs.") {
                        if let latest = reviewStore.bundles.first {
                            HStack(alignment: .center, spacing: 14) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(latest.runID)
                                        .font(.headline)
                                        .foregroundColor(.white)
                                    Text(latest.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption)
                                        .foregroundColor(theme.subtleTextColor)
                                }

                                Divider()
                                    .frame(height: 28)

                                compactDisclosureChip(title: "Board-ready", value: "\(reviewStore.readyForBoardCount())")
                                compactDisclosureChip(title: "Escalations", value: "\(reviewStore.escalatedCount())")
                                compactDisclosureChip(title: "Finance pending", value: "\(reviewStore.financePendingCount())")

                                Spacer(minLength: 0)

                                VStack(alignment: .trailing, spacing: 6) {
                                    Text(latest.reviewRecord?.reviewStatus.displayName ?? "Generated")
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundColor(.white)
                                    Text(latest.totalBurntPercent.map { String(format: "%.1f%% burnt", $0) } ?? "Burn % n/a")
                                        .font(.caption.monospacedDigit())
                                        .foregroundColor(theme.subtleTextColor)
                                }

                                Button("Open Latest") {
                                    _ = AppActionSupport.openExistingPath(latest.reportURL, expectation: .file)
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!latestDisclosureReportAvailability.isEnabled)
                                .help(latestDisclosureReportAvailability.reason ?? "Open the latest disclosure report.")
                            }
                            .padding(16)
                            .background(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .fill(Color.white.opacity(0.05))
                            )
                        } else {
                            Text("No disclosure package has been generated yet. Complete a simulation run from the operations workspace.")
                                .font(.footnote)
                                .foregroundColor(theme.subtleTextColor)
                        }
                    }

                    dashboardPanelCard(title: "Enterprise Control Plane",
                                       subtitle: "Current enterprise telemetry coverage, artifact indexing, and service readiness from the local platform façade.") {
                        VStack(alignment: .leading, spacing: 14) {
                            HStack {
                                compactDisclosureChip(title: "Coverage", value: enterpriseReadiness.coverageLabel)
                                compactDisclosureChip(title: "Artifacts", value: "\(enterpriseReadiness.activeArtifactCount)")
                                compactDisclosureChip(title: "Disclosure manifests", value: "\(enterpriseReadiness.disclosureManifestCount)")
                            }

                            if let latestSimulationEngineLabel = enterpriseReadiness.latestSimulationEngineLabel {
                                Text("Latest simulation registry entry: \(latestSimulationEngineLabel)")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            } else {
                                Text("No simulation artifact has been registered through the enterprise artifact registry yet.")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            }

                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(enterpriseReadiness.surfaceReadiness.prefix(4)) { readiness in
                                    HStack {
                                        Text(readiness.surface.displayLabel)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundColor(.white)
                                        Spacer()
                                        Text(readiness.healthLabel)
                                            .font(.caption.weight(.bold))
                                            .foregroundColor(readiness.healthColor)
                                        Text(readiness.detailLabel)
                                            .font(.caption)
                                            .foregroundColor(theme.subtleTextColor)
                                            .lineLimit(1)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.top, 110)
                .padding(.horizontal, 28)
                .padding(.bottom, 32)
            }
        }
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Executive Overview")
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .foregroundColor(.white)
            Text("Track operational readiness, disclosure status, and the next management actions without crowding the main dashboard. Use this screen when you need detail, not just a launch point.")
                .font(.title3)
                .foregroundColor(Color.white.opacity(0.78))
                .frame(maxWidth: 940, alignment: .leading)

            HStack(spacing: 12) {
                executiveTag("Active Scenario", scenarioStore.selectedScenario?.name ?? "No active scenario")
                executiveTag("Latest Review", reviewStore.bundles.first?.reviewRecord?.reviewStatus.displayName ?? "No package")
                executiveTag("Overdue Reviews", "\(reviewStore.overdueReviewCount())")
                executiveTag("Hazard Scope", "Wildfire live • Flood / Heatwave planned")
            }
        }
        .padding(28)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.09), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 30, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
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

    private func readinessRow(title: String, availability: ActionAvailability) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: availability.isEnabled ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundColor(availability.isEnabled ? .green : .orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(availability.reason ?? "Ready")
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.72))
            }
            Spacer()
        }
    }

    private func executiveTag(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundColor(Color.white.opacity(0.55))
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color.white.opacity(0.07))
        )
    }

    private func compactDisclosureChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundColor(theme.subtleTextColor)
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(.white)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }
}
