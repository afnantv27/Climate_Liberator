import SwiftUI

struct ClimateLiberatorWorkspaceShellView: View {
    @Binding var activeWorkspace: AppWorkspace

    let theme: ThemeStyle
    let dashboardView: AnyView
    let executiveOverviewView: AnyView
    let portfolioIntelligenceView: AnyView
    let operationsView: AnyView
    let operationsOverlayControls: AnyView
    let openTCFDDashboard: () -> Void
    let quitApplication: () -> Void

    var body: some View {
        routedContent
            .overlay(alignment: .top) {
                globalToolbar
                    .padding(.top, 20)
                    .padding(.horizontal, 20)
            }
            .overlay(alignment: .bottomTrailing) {
                if activeWorkspace == .operations {
                    operationsOverlayControls
                        .padding(.trailing, 20)
                        .padding(.bottom, 110)
                }
            }
    }

    private var routedContent: AnyView {
        switch activeWorkspace {
        case .dashboard:
            return dashboardView
        case .commandCenter:
            return executiveOverviewView
        case .intelligence:
            return portfolioIntelligenceView
        case .operations:
            return operationsView
        }
    }

    private var globalToolbar: some View {
        ViewThatFits(in: .horizontal) {
            toolbarContent(showFocusLabel: true)
            toolbarContent(showFocusLabel: false)
        }
    }

    private func toolbarContent(showFocusLabel: Bool) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Text("Climate Liberator")
                    .font(.headline.weight(.semibold))
                if showFocusLabel {
                    Text("India-first")
                        .font(.subheadline)
                        .foregroundColor(theme.subtleTextColor)
                }
            }
            .lineLimit(1)
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .glassBackground(material: theme.material,
                             tint: theme.cardBackground,
                             cornerRadius: 18,
                             strokeColor: theme.borderColor)

            Picker("Workspace", selection: $activeWorkspace) {
                ForEach(AppWorkspace.allCases) { workspace in
                    Text(workspace.shortTitle).tag(workspace)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 520)

            Spacer(minLength: 0)

            Button("Open Disclosure Review") {
                openTCFDDashboard()
            }
            .buttonStyle(.bordered)

            Button(action: quitApplication) {
                Label("Quit", systemImage: "xmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
    }
}
