import SwiftUI

struct DashboardWorkspaceView: View {
    let enterpriseReadiness: EnterpriseReadinessSummary
    let openClimateSimulation: () -> Void
    let openForecastIntelligence: () -> Void
    let openTCFDDashboard: () -> Void
    let openCommandCenter: () -> Void
    let openPortfolioIntelligence: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.03, green: 0.04, blue: 0.08),
                    Color(red: 0.05, green: 0.09, blue: 0.16),
                    Color(red: 0.08, green: 0.13, blue: 0.2)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RoundedRectangle(cornerRadius: 520, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.08, green: 0.36, blue: 0.46).opacity(0.36),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 40,
                        endRadius: 280
                    )
                )
                .frame(width: 560, height: 560)
                .offset(x: 360, y: -240)
                .blur(radius: 40)

            RoundedRectangle(cornerRadius: 520, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.28, green: 0.2, blue: 0.52).opacity(0.32),
                            Color.clear
                        ],
                        center: .center,
                        startRadius: 30,
                        endRadius: 260
                    )
                )
                .frame(width: 520, height: 520)
                .offset(x: -320, y: 260)
                .blur(radius: 54)

            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    heroSection

                    HStack(alignment: .top, spacing: 20) {
                        dashboardToolCard(
                            title: "Climate Simulation",
                            subtitle: "Run hazard scenarios and generate evidence packages from the operations workspace.",
                            icon: "flame.fill",
                            accent: Color.orange,
                            actionTitle: "Open Climate Simulation",
                            action: openClimateSimulation,
                            prominence: .primary
                        )

                        VStack(spacing: 20) {
                            dashboardToolCard(
                                title: "Forecast Intelligence",
                                subtitle: "Track forecast conditions, climate variables, and air-quality outlooks.",
                                icon: "cloud.sun.fill",
                                accent: Color.cyan,
                                actionTitle: "Open Forecast Intelligence",
                                action: openForecastIntelligence,
                                prominence: .secondary
                            )

                            dashboardToolCard(
                                title: "TCFD Dashboard",
                                subtitle: "Review disclosure packages and prepare board-ready outputs.",
                                icon: "doc.text.magnifyingglass",
                                accent: Color.teal,
                                actionTitle: "Open TCFD Dashboard",
                                action: openTCFDDashboard,
                                prominence: .secondary
                            )
                        }
                        .frame(maxWidth: .infinity)
                    }

                    enterpriseReadinessSection

                    secondarySection
                }
                .padding(.top, 112)
                .padding(.horizontal, 28)
                .padding(.bottom, 36)
            }
        }
    }

    private var heroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Dashboard")
                .font(.system(size: 42, weight: .bold, design: .rounded))
                .foregroundColor(.white)

            Text("Climate Risk Workflows")
                .font(.system(size: 24, weight: .semibold, design: .rounded))
                .foregroundColor(Color.white.opacity(0.92))

            Text("Launch simulation, forecast intelligence, and disclosure review from one control point. The detailed management status view now lives separately so this screen stays clean and easy to navigate.")
                .font(.title3)
                .foregroundColor(Color.white.opacity(0.72))
                .frame(maxWidth: 920, alignment: .leading)

            HStack(spacing: 12) {
                dashboardTag("Wildfire live")
                dashboardTag("India-first depth")
                dashboardTag("Forecast + AQ")
                dashboardTag("Board-pack workflow")
            }
        }
        .padding(30)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color.white.opacity(0.1), Color.white.opacity(0.04)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private var secondarySection: some View {
        HStack(alignment: .top, spacing: 20) {
            secondaryCard(
                title: "Executive Overview",
                subtitle: "Management status, disclosure readiness, finance backlog, and latest package signals.",
                buttonTitle: "Open Executive Overview",
                icon: "gauge.with.dots.needle.67percent",
                accent: Color.indigo,
                action: openCommandCenter
            )

            secondaryCard(
                title: "Portfolio Intelligence",
                subtitle: "Inspect site exposure, concentration hotspots, utility demo workflow, and India screening.",
                buttonTitle: "Open Portfolio Intelligence",
                icon: "building.2.crop.circle",
                accent: Color.green,
                action: openPortfolioIntelligence
            )
        }
    }

    private var enterpriseReadinessSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Enterprise Readiness")
                    .font(.title3.bold())
                    .foregroundColor(.white)
                Spacer()
                Text(enterpriseReadiness.coverageLabel)
                    .font(.footnote.weight(.semibold))
                    .foregroundColor(Color.white.opacity(0.68))
            }

            HStack(alignment: .top, spacing: 16) {
                enterpriseMiniMetric(title: "SLO catalog", value: "\(enterpriseReadiness.serviceLevelObjectiveCount)", detail: "\(enterpriseReadiness.availabilityObjectiveCount) availability objectives")
                enterpriseMiniMetric(title: "Artifacts indexed", value: "\(enterpriseReadiness.activeArtifactCount)", detail: "\(enterpriseReadiness.disclosureManifestCount) disclosure manifests discovered")
                enterpriseMiniMetric(title: "Simulation backend", value: enterpriseReadiness.latestSimulationEngineLabel ?? "None", detail: "Latest registered simulation engine")
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(enterpriseReadiness.surfaceReadiness) { readiness in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(readiness.surface.displayLabel)
                            .font(.subheadline.weight(.semibold))
                            .foregroundColor(.white)
                        Text(readiness.healthLabel)
                            .font(.headline.weight(.bold))
                            .foregroundColor(readiness.healthColor)
                        Text(readiness.detailLabel)
                            .font(.caption)
                            .foregroundColor(Color.white.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.055))
                            .overlay(
                                RoundedRectangle(cornerRadius: 18, style: .continuous)
                                    .stroke(Color.white.opacity(0.10), lineWidth: 1)
                            )
                    )
                }
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
    }

    private enum CardProminence {
        case primary
        case secondary
    }

    private func enterpriseMiniMetric(title: String, value: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundColor(Color.white.opacity(0.72))
            Text(value)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundColor(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(detail)
                .font(.caption)
                .foregroundColor(Color.white.opacity(0.66))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.white.opacity(0.05))
        )
    }

    private func dashboardToolCard(title: String,
                                   subtitle: String,
                                   icon: String,
                                   accent: Color,
                                   actionTitle: String,
                                   action: @escaping () -> Void,
                                   prominence: CardProminence) -> some View {
        VStack(alignment: .leading, spacing: prominence == .primary ? 22 : 16) {
            ZStack {
                RoundedRectangle(cornerRadius: prominence == .primary ? 24 : 20, style: .continuous)
                    .fill(accent.opacity(0.16))
                    .frame(width: prominence == .primary ? 88 : 72,
                           height: prominence == .primary ? 88 : 72)

                Image(systemName: icon)
                    .font(.system(size: prominence == .primary ? 34 : 28, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(title)
                    .font(prominence == .primary ? .system(size: 28, weight: .bold, design: .rounded) : .title3.weight(.bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(prominence == .primary ? .title3 : .body)
                    .foregroundColor(Color.white.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)

            Button(actionTitle, action: action)
                .buttonStyle(.borderedProminent)
                .tint(accent)
        }
        .padding(prominence == .primary ? 28 : 22)
        .frame(maxWidth: .infinity,
               minHeight: prominence == .primary ? 360 : 170,
               alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: prominence == .primary ? 30 : 26, style: .continuous)
                .fill(Color.white.opacity(prominence == .primary ? 0.08 : 0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: prominence == .primary ? 30 : 26, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
        )
        .shadow(color: accent.opacity(0.16), radius: 20, y: 12)
    }

    private func secondaryCard(title: String,
                               subtitle: String,
                               buttonTitle: String,
                               icon: String,
                               accent: Color,
                               action: @escaping () -> Void) -> some View {
        HStack(alignment: .center, spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(accent.opacity(0.18))
                    .frame(width: 58, height: 58)

                Image(systemName: icon)
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(.headline.weight(.bold))
                    .foregroundColor(.white)
                Text(subtitle)
                    .font(.footnote)
                    .foregroundColor(Color.white.opacity(0.72))
            }

            Spacer(minLength: 12)

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .tint(accent)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(Color.white.opacity(0.05))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func dashboardTag(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundColor(.white)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                Capsule()
                    .fill(Color.white.opacity(0.08))
            )
    }
}
