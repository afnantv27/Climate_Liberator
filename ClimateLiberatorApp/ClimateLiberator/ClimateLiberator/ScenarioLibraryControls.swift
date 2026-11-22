import SwiftUI

/// New, edit and delete for saved simulation scenarios, shown beside the scenario
/// picker in the Simulation workspace.
struct ScenarioLibraryControls: View {
    @ObservedObject var store: ScenarioLibraryStore

    @State private var editorTarget: EditorTarget?
    @State private var confirmingDelete = false

    /// Identifies which scenario the editor sheet opens with; nil scenario = new.
    private struct EditorTarget: Identifiable {
        let id = UUID()
        let scenario: ScenarioDefinition?
    }

    var body: some View {
        HStack(spacing: 8) {
            Button { editorTarget = EditorTarget(scenario: nil) } label: { Label("New Scenario", systemImage: "plus") }
            Button { editorTarget = EditorTarget(scenario: store.selectedScenario) } label: { Label("Edit", systemImage: "pencil") }
                .disabled(store.selectedScenario == nil)
            Button(role: .destructive) { confirmingDelete = true } label: { Label("Delete", systemImage: "trash") }
                .disabled(store.selectedScenario == nil)
        }
        .buttonStyle(.bordered)
        .sheet(item: $editorTarget) { target in
            ScenarioEditorView(scenario: target.scenario) { scenario in
                if store.scenarios.contains(where: { $0.id == scenario.id }) {
                    store.updateScenario(scenario)
                } else {
                    store.addScenario(scenario)
                }
            }
        }
        .confirmationDialog("Delete “\(store.selectedScenario?.name ?? "scenario")”?", isPresented: $confirmingDelete) {
            Button("Delete Scenario", role: .destructive) {
                if let id = store.selectedScenario?.id { store.deleteScenario(id: id) }
            }
        } message: {
            Text("The scenario is removed from the library. Simulation outputs already produced are not affected.")
        }
    }
}
