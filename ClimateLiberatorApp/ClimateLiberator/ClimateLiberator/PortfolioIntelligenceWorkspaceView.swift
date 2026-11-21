import SwiftUI
import CoreLocation
import MapKit

struct PortfolioIntelligenceWorkspaceView: View {
    @ObservedObject var indiaRiskStore: IndiaRiskStore
    @ObservedObject var exposureIntakeStore: ExposureIntakeStore
    @Binding var mapRegion: MKCoordinateRegion
    @Binding var activeWorkspace: AppWorkspace

    let theme: ThemeStyle
    let openDisclosure: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.04, green: 0.07, blue: 0.11),
                    Color(red: 0.08, green: 0.12, blue: 0.18),
                    Color(red: 0.10, green: 0.14, blue: 0.20)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    heroCard

                    HStack(alignment: .top, spacing: 18) {
                        dashboardPanelCard(title: "Portfolio Workflow",
                                           subtitle: "Use this workspace for screening and concentration analysis before moving into simulation or disclosure review.") {
                            workflowPanel
                        }

                        dashboardPanelCard(title: "Exposure Intake",
                                           subtitle: "Import structured company exposure data in OED format so Climate Liberator can move beyond screening-only portfolio proxies.") {
                            HStack {
                                executiveMetricCard(title: "Locations",
                                                    value: exposureIntakeStore.lastImport.map { "\($0.summary.locationCount)" } ?? "0",
                                                    detail: exposureIntakeStore.lastImport?.summary.sourceLabel ?? "No OED exposure package imported yet")
                                executiveMetricCard(title: "Accounts",
                                                    value: exposureIntakeStore.lastImport.map { "\($0.summary.accountCount)" } ?? "0",
                                                    detail: exposureIntakeStore.lastImport.map { $0.summary.hasRIInfo || $0.summary.hasRIScope ? "RI files detected" : "Location/account only" } ?? "Import OED folder or Location CSV")
                                executiveMetricCard(title: "Financial Coverage",
                                                    value: exposureIntakeStore.lastImport.map { "\($0.summary.financialLocationCount)/\($0.summary.locationCount)" } ?? "0/0",
                                                    detail: exposureIntakeStore.lastImport.map { "\($0.summary.geocodedLocationCount) geocoded location(s)" } ?? "No OED artifact loaded")
                            }

                            HStack(spacing: 12) {
                                Button(exposureIntakeStore.isImporting ? "Importing OED…" : "Import OED Package") {
                                    exposureIntakeStore.importOEDPackage()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(exposureIntakeStore.isImporting)

                                Button("Open Latest Intake Artifact") {
                                    exposureIntakeStore.openLatestImportArtifact()
                                }
                                .buttonStyle(.bordered)
                                .disabled(!exposureIntakeStore.latestImportAvailability.isEnabled)
                            }

                            Text(exposureIntakeStore.statusMessage)
                                .font(.footnote)
                                .foregroundColor(theme.subtleTextColor)

                            if let summary = exposureIntakeStore.lastImport?.summary {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Imported Perils: \(summary.perilCodes.isEmpty ? "Not populated" : summary.perilCodes.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(Color.white.opacity(0.7))
                                    Text("Currencies: \(summary.currencyCodes.isEmpty ? "Not populated" : summary.currencyCodes.joined(separator: ", "))")
                                        .font(.caption)
                                        .foregroundColor(Color.white.opacity(0.7))
                                    Text(String(format: "Building TIV %.0f • Contents TIV %.0f • BI TIV %.0f",
                                                summary.totalBuildingTIV,
                                                summary.totalContentsTIV,
                                                summary.totalBusinessInterruptionTIV))
                                        .font(.caption)
                                        .foregroundColor(Color.white.opacity(0.7))
                                    if let issue = summary.validationIssues.first {
                                        Text("\(issue.severity.rawValue.capitalized): \(issue.message)")
                                            .font(.caption)
                                            .foregroundColor(issue.severity == .critical ? .red.opacity(0.9) : theme.subtleTextColor)
                                    }
                                }
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        dashboardPanelCard(title: "Imported Exposure Portfolio",
                                           subtitle: "Canonical OED portfolio analytics that can now feed company-level screening instead of staying as a raw import receipt.") {
                            if let overview = exposureIntakeStore.latestOverview {
                                HStack {
                                    executiveMetricCard(title: "Imported Locations",
                                                        value: "\(overview.locationCount)",
                                                        detail: "\(overview.accountCount) account(s) • \(overview.geocodedLocationCount) geocoded")
                                    executiveMetricCard(title: "Total Insured Value",
                                                        value: compactCurrency(overview.totalInsuredValue),
                                                        detail: overview.currencyCodes.isEmpty ? "Currency not populated" : overview.currencyCodes.joined(separator: ", "))
                                    executiveMetricCard(title: "Portfolio Mix",
                                                        value: overview.perilMix.first.map { "\($0.code) \($0.count)" } ?? "n/a",
                                                        detail: overview.hasReinsuranceStructure ? "RI structure present" : "Direct exposure only")
                                }

                                VStack(alignment: .leading, spacing: 10) {
                                    Text("Top Perils: \(overview.perilMix.prefix(3).map { "\($0.code) (\($0.count))" }.joined(separator: " • ").ifEmpty("Not populated"))")
                                        .font(.caption)
                                        .foregroundColor(Color.white.opacity(0.7))
                                    Text("Top Occupancies: \(overview.occupancyMix.prefix(3).map { "\($0.code) (\($0.count))" }.joined(separator: " • ").ifEmpty("Not populated"))")
                                        .font(.caption)
                                        .foregroundColor(Color.white.opacity(0.7))
                                    Text("Sample Assets: \(overview.sampleLocations.map(\.name).joined(separator: " • ").ifEmpty("No sample assets available"))")
                                        .font(.caption)
                                        .foregroundColor(Color.white.opacity(0.7))
                                }
                            } else {
                                Text("Import an OED package to activate company portfolio analytics here. The imported canonical portfolio will then be available for screening-oriented rollups.")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            }
                        }

                        dashboardPanelCard(title: "India Portfolio Screening",
                                           subtitle: "Roll-up of stored India wildfire assessments for executive screening. This stays separate from the TCFD board-pack workflow unless linked into a selected package.") {
                            HStack {
                                executiveMetricCard(title: "Assessed Assets",
                                                    value: "\(indiaRiskStore.portfolioSummary.assessedAssets)",
                                                    detail: indiaRiskStore.portfolioSummary.latestAssessmentAt.map { "Latest: \($0)" } ?? "No wildfire assessments linked yet")
                                executiveMetricCard(title: "High Risk Assets",
                                                    value: "\(indiaRiskStore.portfolioSummary.highRiskAssets)",
                                                    detail: "\(indiaRiskStore.portfolioSummary.mediumRiskAssets) medium • \(indiaRiskStore.portfolioSummary.lowRiskAssets) low")
                                executiveMetricCard(title: "Scenarios Tracked",
                                                    value: "\(indiaRiskStore.portfolioSummary.uniqueScenarios)",
                                                    detail: "Distinct wildfire scenarios represented in the India risk database")
                            }

                            HStack(spacing: 12) {
                                Button("Export OED CSV") {
                                    indiaRiskStore.exportPortfolioAsOEDCSV()
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!indiaRiskStore.oedExportAvailability.isEnabled)

                                Button("Open Latest OED") {
                                    if let path = indiaRiskStore.lastOEDExport?.filePath {
                                        _ = AppActionSupport.openExistingPath(path, expectation: .file)
                                    }
                                }
                                .buttonStyle(.bordered)
                                .disabled(indiaRiskStore.lastOEDExport == nil)
                            }

                            if let export = indiaRiskStore.lastOEDExport {
                                Text("Latest OED-style export: \(export.rowCount) rows from \(export.sourceLabel).")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            } else if let reason = indiaRiskStore.oedExportAvailability.reason,
                                      !indiaRiskStore.oedExportAvailability.isEnabled {
                                Text(reason)
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            }

                            portfolioRiskMixView
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        dashboardPanelCard(title: "Utility Demo Workflow",
                                           subtitle: "A company-oriented walkthrough showing how a utility moves from portfolio screening to scenario review and board escalation.") {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(ClimateLiberatorDemoCompany.indianUtility.workflow) { step in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(step.title)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                        Text(step.detail)
                                            .font(.footnote)
                                            .foregroundColor(theme.subtleTextColor)
                                        Text(step.output)
                                            .font(.caption)
                                            .foregroundColor(Color.white.opacity(0.66))
                                    }
                                    .padding(12)
                                    .background(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .fill(Color.white.opacity(0.05))
                                    )
                                }
                            }
                        }

                        dashboardPanelCard(title: "Scenario Comparison & Trust",
                                           subtitle: "Build-side processed feeds that summarize how the demo portfolio changes under the stressed scenario and how trustworthy that evidence is.") {
                            if let comparison = indiaRiskStore.demoComparisonSummary,
                               let trust = indiaRiskStore.demoTrustSummary {
                                HStack {
                                    executiveMetricCard(title: "Worsened Sites",
                                                        value: "\(comparison.worsenedSiteCount)",
                                                        detail: "\(comparison.improvedSiteCount) improved • Δ high-risk \(comparison.deltaHighRiskSiteCount)")
                                    executiveMetricCard(title: "Exposure Delta",
                                                        value: String(format: "%.1f m²", comparison.deltaExpectedExposedAreaM2),
                                                        detail: comparison.comparisonReady ? "Baseline vs stress comparison ready" : "Comparison evidence incomplete")
                                    executiveMetricCard(title: "Artifact-backed Sites",
                                                        value: "\(trust.artifactBackedSiteCount)",
                                                        detail: "\(trust.missingProvenanceSiteCount) missing provenance • \(trust.preparedInstanceReferencedRunCount) prepared instances")
                                }
                            } else {
                                Text("Processed demo comparison feeds are not available yet. Generate or refresh the Build-side demo feed export to populate this panel.")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            }
                        }
                    }

                    HStack(alignment: .top, spacing: 18) {
                        dashboardPanelCard(title: "Risk Concentration",
                                           subtitle: "Concentration hotspots where wildfire risk is clustering across the assessed portfolio.") {
                            if indiaRiskStore.topRiskConcentrations.isEmpty {
                                Text("No assessed concentration hotspots yet. Persist wildfire assessments into the India database to activate portfolio accumulation views.")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            } else {
                                VStack(alignment: .leading, spacing: 12) {
                                    ForEach(indiaRiskStore.topRiskConcentrations) { concentration in
                                        accumulationRow(for: concentration)
                                    }
                                }
                            }
                        }

                        dashboardPanelCard(title: "India Site Screening",
                                           subtitle: "Use the current site center to screen nearby Indian assets and stored wildfire context. This is a screening surface unless linked into a selected package.") {
                            HStack {
                                executiveMetricCard(title: "Current Latitude",
                                                    value: String(format: "%.3f", mapRegion.center.latitude),
                                                    detail: "Selected site center")
                                executiveMetricCard(title: "Current Longitude",
                                                    value: String(format: "%.3f", mapRegion.center.longitude),
                                                    detail: "Selected site center")
                            }

                            HStack(spacing: 12) {
                                Button("Screen Selected Site") {
                                    indiaRiskStore.lookupNearbyBuildings(
                                        latitude: mapRegion.center.latitude,
                                        longitude: mapRegion.center.longitude
                                    )
                                }
                                .buttonStyle(.borderedProminent)
                                .disabled(!indiaRiskStore.lookupAvailability.isEnabled)

                                Button("Refresh India Database") {
                                    indiaRiskStore.refreshDatabaseStatus()
                                }
                                .buttonStyle(.bordered)
                            }

                            if let nearest = indiaRiskStore.nearbyBuildings.first {
                                Text("Nearest imported asset: \(nearest.districtName), \(nearest.stateCode) at \(Int(nearest.distanceMeters)) m.")
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            } else {
                                Text(indiaRiskStore.nearbyEmptyStateMessage)
                                    .font(.footnote)
                                    .foregroundColor(theme.subtleTextColor)
                            }
                        }
                    }

                    dashboardPanelCard(title: "Screening Notes",
                                       subtitle: "This workspace is for screening and concentration analysis, not execution or approval.") {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Use Portfolio Intelligence to identify exposed states, districts, and selected sites.")
                                .font(.footnote)
                                .foregroundColor(theme.subtleTextColor)
                            Text("Move into Simulation Workspace when you need prepared-instance checks, execution, outputs, or run history.")
                                .font(.footnote)
                                .foregroundColor(theme.subtleTextColor)
                            Text("Move into the TCFD Dashboard when a run package needs threshold actions, review, approval, or board-pack export.")
                                .font(.footnote)
                                .foregroundColor(theme.subtleTextColor)
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
            Text("Portfolio Intelligence")
                .font(.appPageTitle)
                .foregroundColor(.white)
            Text("Screen asset concentration, inspect selected sites, and understand exposure before moving into simulation or disclosure review.")
                .font(.title3)
                .foregroundColor(Color.white.opacity(0.78))
                .frame(maxWidth: 940, alignment: .leading)

            HStack(spacing: 12) {
                executiveTag("Company Demo", ClimateLiberatorDemoCompany.indianUtility.name)
                executiveTag("Primary Use", "Screening and preparedness")
                executiveTag("Portfolio Scope", portfolioScopeTagValue)
                executiveTag("Comparison", comparisonTagValue)
            }

            HStack(spacing: 12) {
                Button("Open Simulation Workspace") {
                    activeWorkspace = .operations
                }
                .buttonStyle(.bordered)

                Button("Open Disclosure") {
                    openDisclosure()
                }
                .buttonStyle(.borderedProminent)
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
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private var workflowPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("1. Review concentration hotspots and assessed-asset mix.")
                .font(.footnote)
                .foregroundColor(theme.subtleTextColor)
            Text("2. Screen the selected site to inspect nearby imported assets and building context.")
                .font(.footnote)
                .foregroundColor(theme.subtleTextColor)
            Text("3. Move into Simulation Workspace when a site needs prepared-instance validation or scenario execution.")
                .font(.footnote)
                .foregroundColor(theme.subtleTextColor)
            Text("4. Move into the TCFD Dashboard only after a run package needs review or board-pack export.")
                .font(.footnote)
                .foregroundColor(theme.subtleTextColor)
        }
    }

    private var portfolioScopeTagValue: String {
        if let overview = exposureIntakeStore.latestOverview {
            return "\(overview.locationCount) imported locations"
        }
        if let overview = indiaRiskStore.demoPortfolioOverview {
            return "\(overview.assessedSiteCount) assessed sites"
        }
        return "\(indiaRiskStore.portfolioSummary.assessedAssets) assessed assets"
    }

    private var comparisonTagValue: String {
        guard let comparison = indiaRiskStore.demoComparisonSummary else {
            return "Comparison pending"
        }
        return comparison.comparisonReady ? "Baseline vs stress ready" : "Comparison pending"
    }

    private func executiveMetricCard(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.72))
            Text(value)
                .font(.appMetric)
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
                .font(.appSectionTitle)
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

    private var portfolioRiskMixView: some View {
        let total = max(indiaRiskStore.portfolioSummary.assessedAssets, 1)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Risk Mix")
                .font(.headline)
                .foregroundColor(.white)

            portfolioRiskBar(title: "High Risk",
                             count: indiaRiskStore.portfolioSummary.highRiskAssets,
                             total: total,
                             color: .red)
            portfolioRiskBar(title: "Medium Risk",
                             count: indiaRiskStore.portfolioSummary.mediumRiskAssets,
                             total: total,
                             color: .orange)
            portfolioRiskBar(title: "Low Risk",
                             count: indiaRiskStore.portfolioSummary.lowRiskAssets,
                             total: total,
                             color: .green)
        }
    }

    private func portfolioRiskBar(title: String, count: Int, total: Int, color: Color) -> some View {
        let ratio = CGFloat(count) / CGFloat(max(total, 1))
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.white)
                Spacer()
                Text("\(count)")
                    .font(.caption.monospacedDigit())
                    .foregroundColor(Color.white.opacity(0.72))
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.12))
                    Capsule()
                        .fill(color.gradient)
                        .frame(width: max(10, geometry.size.width * ratio))
                }
            }
            .frame(height: 10)
        }
    }

    private func accumulationRow(for concentration: IndiaRiskConcentration) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(concentration.stateCode)
                    .font(.headline)
                    .foregroundColor(.white)
                Text("\(concentration.assetCount) assessed asset(s)")
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.72))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(concentration.highRiskCount) high risk")
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(concentration.highRiskCount > 0 ? .orange : .white)
                Text(concentration.averageBurnProbability.map { String(format: "Avg burn probability %.0f%%", $0 * 100) } ?? "Avg burn probability n/a")
                    .font(.caption)
                    .foregroundColor(Color.white.opacity(0.68))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func compactCurrency(_ value: Double) -> String {
        if value >= 1_000_000_000 {
            return String(format: "%.1fB", value / 1_000_000_000)
        }
        if value >= 1_000_000 {
            return String(format: "%.1fM", value / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.0fK", value / 1_000)
        }
        return String(format: "%.0f", value)
    }
}

private extension String {
    func ifEmpty(_ replacement: String) -> String {
        isEmpty ? replacement : self
    }
}
