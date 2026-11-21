import SwiftUI
import AppKit

@main
struct ClimateLiberatorApp: App {
    /// Asks to save unsaved GHG inventories and disclosure engagements before quitting.
    @NSApplicationDelegateAdaptor(ClimateLiberatorAppDelegate.self) private var appDelegate
    @StateObject private var scenarioStore: ScenarioLibraryStore
    @StateObject private var reviewStore: TCFDReviewStore
    @StateObject private var forecastStore: ForecastIntelligenceStore
    @StateObject private var ghgInventoryStore = GPCInventoryStore()
    @StateObject private var emissionFactorStore = EmissionFactorLibraryStore()
    @StateObject private var disclosureStore = DisclosureStore()
    @State private var bootstrapError: String?

    init() {
        var setupError: String?
        do { try AppDataBootstrap.prepare() }
        catch { setupError = error.localizedDescription }
        _bootstrapError = State(initialValue: setupError)
        _scenarioStore = StateObject(wrappedValue: ScenarioLibraryStore())
        _reviewStore = StateObject(wrappedValue: TCFDReviewStore())
        _forecastStore = StateObject(wrappedValue: ForecastIntelligenceStore())
    }

    var body: some Scene {
        WindowGroup {
            LaunchExperienceView {
                ContentView(scenarioStore: scenarioStore, reviewStore: reviewStore, forecastStore: forecastStore,
                            ghgInventoryStore: ghgInventoryStore, emissionFactorStore: emissionFactorStore,
                            disclosureStore: disclosureStore)
            }
            .alert("Local data setup failed", isPresented: Binding(
                get: { bootstrapError != nil }, set: { if !$0 { bootstrapError = nil } }
            )) {
                Button("OK") { bootstrapError = nil }
            } message: {
                Text((bootstrapError ?? "") + " Open Settings > India Data to inspect your installation.")
            }
        }
        .defaultSize(width: 1240, height: 820)

        Window("Forecast Intelligence", id: "forecast-intelligence") {
            ForecastIntelligenceWindow(store: forecastStore)
        }
        Settings { DataLibraryView() }
    }
}

private struct LaunchExperienceView<Content: View>: View {
    let content: Content
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var splashVisible = true

    init(@ViewBuilder content: () -> Content) { self.content = content() }

    var body: some View {
        content
            .overlay {
                if splashVisible && !reduceMotion {
                    GeometryReader { geometry in
                        ZStack(alignment: .bottom) {
                            Image("LaunchMark").resizable().scaledToFill()
                                .frame(width: geometry.size.width, height: geometry.size.height).clipped()
                            LinearGradient(colors: [.clear, .black.opacity(0.85)], startPoint: .center, endPoint: .bottom)
                            VStack(spacing: 8) {
                                Text("Climate Liberator").font(.appDisplay)
                                Text("India Climate Risk Intelligence").font(.title3.weight(.medium))
                            }
                            .foregroundStyle(.white).padding(.bottom, 52)
                        }
                    }
                    .allowsHitTesting(false).accessibilityHidden(true).transition(.opacity)
                }
            }
            .task {
                if !reduceMotion { try? await Task.sleep(for: .milliseconds(350)) }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { splashVisible = false }
            }
    }
}
