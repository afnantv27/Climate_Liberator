import SwiftUI

struct OperationsWorkspaceView<HeaderControls: View,
                               SiteContent: View,
                               InputsContent: View,
                               RunContent: View,
                               OutputsContent: View,
                               LogsContent: View>: View {
    let style: WorkspaceSectionStyle
    let controlsExpanded: Bool
    let onToggleExpanded: () -> Void
    let headerControls: HeaderControls
    let siteContent: SiteContent
    let inputsContent: InputsContent
    let runContent: RunContent
    let outputsContent: OutputsContent
    let logsContent: LogsContent

    init(style: WorkspaceSectionStyle,
         controlsExpanded: Bool,
         onToggleExpanded: @escaping () -> Void,
         @ViewBuilder headerControls: () -> HeaderControls,
         @ViewBuilder siteContent: () -> SiteContent,
         @ViewBuilder inputsContent: () -> InputsContent,
         @ViewBuilder runContent: () -> RunContent,
         @ViewBuilder outputsContent: () -> OutputsContent,
         @ViewBuilder logsContent: () -> LogsContent) {
        self.style = style
        self.controlsExpanded = controlsExpanded
        self.onToggleExpanded = onToggleExpanded
        self.headerControls = headerControls()
        self.siteContent = siteContent()
        self.inputsContent = inputsContent()
        self.runContent = runContent()
        self.outputsContent = outputsContent()
        self.logsContent = logsContent()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button(action: onToggleExpanded) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Climate Liberator Operations Console")
                            .font(.appPageTitle)
                            .foregroundColor(style.textColor)
                        Text("Site context, run preparation, wildfire execution, and evidence review.")
                            .font(.footnote)
                            .foregroundColor(style.subtleTextColor)
                    }
                    Spacer()
                    Image(systemName: controlsExpanded ? "chevron.up.circle.fill" : "chevron.down.circle.fill")
                        .foregroundColor(style.textColor)
                        .imageScale(.large)
                }
            }
            .buttonStyle(.plain)

            if controlsExpanded {
                headerControls

                VStack(alignment: .leading, spacing: 18) {
                    WorkspaceSectionCard(
                        title: "Site",
                        subtitle: "Search locations, inspect the active coordinate, pull Earth Engine context, and screen Indian building exposure.",
                        style: style
                    ) {
                        siteContent
                    }

                    WorkspaceSectionCard(
                        title: "Inputs",
                        subtitle: "Prepare the binary path, prepared instance, output directory, and scenario inputs before a run.",
                        style: style
                    ) {
                        inputsContent
                    }

                    WorkspaceSectionCard(
                        title: "Run",
                        subtitle: "Control simulation volume, threads, seed, weather cadence, and execution.",
                        style: style
                    ) {
                        runContent
                    }

                    WorkspaceSectionCard(
                        title: "Outputs",
                        subtitle: "Inspect generated artifacts, export GIS deliverables, and review persisted disclosure packages.",
                        style: style
                    ) {
                        outputsContent
                    }

                    WorkspaceSectionCard(
                        title: "Logs",
                        subtitle: "Track command output, warnings, and run notes without leaving the operations workspace.",
                        style: style
                    ) {
                        logsContent
                    }
                }
            }
        }
        .padding(24)
        .background(
            RoundedRectangle(cornerRadius: 32, style: .continuous)
                .fill(style.material)
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .fill(style.cardTint)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 32, style: .continuous)
                        .stroke(style.borderColor, lineWidth: 1)
                )
        )
        .shadow(color: style.shadowColor, radius: 12, x: 0, y: 12)
        .padding(.vertical, 32)
        .padding(.horizontal)
    }
}
