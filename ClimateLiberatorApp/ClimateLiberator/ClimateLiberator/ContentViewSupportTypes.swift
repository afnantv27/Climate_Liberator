import SwiftUI
import AppKit
import MapKit
import CoreLocation
import Combine

enum OutputFormat: String, CaseIterable, Identifiable {
    case asc
    case tif

    var id: String { rawValue }

    var label: String {
        switch self {
        case .asc:
            return "ESRI ASCII (.asc)"
        case .tif:
            return "GeoTIFF (.tif)"
        }
    }
}

struct ROSColorStop {
    let location: Double
    let red: Double
    let green: Double
    let blue: Double
    let alpha: Double

    init(location: Double, red: Double, green: Double, blue: Double, alpha: Double) {
        self.location = location
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }
}

enum RateOfSpreadPalette: String, CaseIterable, Identifiable {
    case terrain
    case spectrum
    case inferno

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .terrain: return "Terrain (Green→Red)"
        case .spectrum: return "Spectrum (Blue→Red)"
        case .inferno: return "Inferno"
        }
    }

    var colorStops: [ROSColorStop] {
        switch self {
        case .terrain:
            return [
                ROSColorStop(location: 0.0, red: 0.0, green: 0.25, blue: 0.0, alpha: 0.1),
                ROSColorStop(location: 0.3, red: 0.0, green: 0.68, blue: 0.2, alpha: 0.55),
                ROSColorStop(location: 0.6, red: 0.98, green: 0.83, blue: 0.0, alpha: 0.92),
                ROSColorStop(location: 0.8, red: 0.98, green: 0.46, blue: 0.0, alpha: 0.95),
                ROSColorStop(location: 1.0, red: 0.75, green: 0.0, blue: 0.0, alpha: 1.0)
            ]
        case .spectrum:
            return [
                ROSColorStop(location: 0.0, red: 0.1, green: 0.1, blue: 0.35, alpha: 0.18),
                ROSColorStop(location: 0.25, red: 0.0, green: 0.6, blue: 0.95, alpha: 0.5),
                ROSColorStop(location: 0.5, red: 0.1, green: 0.85, blue: 0.1, alpha: 0.8),
                ROSColorStop(location: 0.75, red: 0.98, green: 0.83, blue: 0.0, alpha: 0.95),
                ROSColorStop(location: 1.0, red: 0.82, green: 0.0, blue: 0.0, alpha: 1.0)
            ]
        case .inferno:
            return [
                ROSColorStop(location: 0.0, red: 0.05, green: 0.02, blue: 0.1, alpha: 0.12),
                ROSColorStop(location: 0.35, red: 0.29, green: 0.06, blue: 0.33, alpha: 0.6),
                ROSColorStop(location: 0.6, red: 0.8, green: 0.27, blue: 0.06, alpha: 0.9),
                ROSColorStop(location: 1.0, red: 1.0, green: 0.97, blue: 0.65, alpha: 1.0)
            ]
        }
    }

    var gradientColors: [Color] {
        colorStops.map { Color(red: $0.red, green: $0.green, blue: $0.blue) }
    }
}

enum ThemeStyle: String, CaseIterable, Identifiable {
    case night
    case day
    case purple

    var id: String { rawValue }
    var displayName: String { rawValue.capitalized }

    var gradient: [Color] {
        switch self {
        case .night:
            return [Color.black.opacity(0.9), Color.gray.opacity(0.4)]
        case .day:
            return [Color.white, Color.blue.opacity(0.25)]
        case .purple:
            return [Color(red: 0.38, green: 0.1, blue: 0.6), Color(red: 0.16, green: 0.08, blue: 0.32)]
        }
    }

    var textColor: Color {
        switch self {
        case .day: return .black
        default: return .white
        }
    }

    var subtleTextColor: Color {
        switch self {
        case .day: return Color.black.opacity(0.6)
        default: return Color.white.opacity(0.75)
        }
    }

    var cardBackground: Color {
        switch self {
        case .night:
            return Color.white.opacity(0.08)
        case .day:
            return Color.white.opacity(0.35)
        case .purple:
            return Color(red: 0.7, green: 0.5, blue: 0.95).opacity(0.18)
        }
    }

    var fieldBackground: Color {
        switch self {
        case .day:
            return Color.white.opacity(0.8)
        default:
            return Color.white.opacity(0.2)
        }
    }

    var editorBackground: Color {
        switch self {
        case .day:
            return Color.white.opacity(0.65)
        case .purple:
            return Color(red: 0.5, green: 0.2, blue: 0.8).opacity(0.2)
        case .night:
            return Color.white.opacity(0.08)
        }
    }

    var accentColor: Color {
        switch self {
        case .night: return .teal
        case .day: return .blue
        case .purple: return .purple
        }
    }

    var material: Material {
        switch self {
        case .day: return .ultraThinMaterial
        case .night: return .thinMaterial
        case .purple: return .ultraThinMaterial
        }
    }

    var borderColor: Color {
        switch self {
        case .day: return Color.black.opacity(0.08)
        default: return Color.white.opacity(0.18)
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .day: return .light
        default: return .dark
        }
    }

    var shadowColor: Color {
        accentColor.opacity(0.2)
    }
}

enum EarthEngineTarget: String, CaseIterable, Identifiable {
    case overlay
    case dem

    var id: String { rawValue }

    var label: String {
        switch self {
        case .overlay: return "Map Overlay"
        case .dem: return "DEM (elevation)"
        }
    }
}

enum AppWorkspace: String, CaseIterable, Identifiable {
    case dashboard
    case commandCenter
    case intelligence
    case operations
    case ghgAccounting
    case disclosure

    var id: String { rawValue }

    var title: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .commandCenter: return "Executive Overview"
        case .intelligence: return "Portfolio Intelligence"
        case .operations: return "Simulation Workspace"
        case .ghgAccounting: return "GHG Accounting (GPC)"
        case .disclosure: return "Disclosure (BRSR · IFRS S2)"
        }
    }

    var shortTitle: String {
        switch self {
        case .dashboard: return "Dashboard"
        case .commandCenter: return "Overview"
        case .intelligence: return "Portfolio"
        case .operations: return "Simulation"
        case .ghgAccounting: return "GHG Inventory"
        case .disclosure: return "Disclosure"
        }
    }

    var subtitle: String {
        switch self {
        case .dashboard:
            return "Launch the core Climate Liberator workspaces from one place."
        case .commandCenter:
            return "Management status, disclosure readiness, and next actions."
        case .intelligence:
            return "India screening, demo workflow, and portfolio concentration analysis."
        case .operations:
            return "Map-based modelling, inputs, and run execution."
        case .ghgAccounting:
            return "City GHG inventories (GPC BASIC/BASIC+) with emission factors from connected databases."
        case .disclosure:
            return "BRSR, BRSR Core and IFRS S2 reporting for client companies: data, review, sign-off and reports."
        }
    }
}

enum BinaryResolution {
    case resolved(String)
    case needsPath
    case invalid

    var failureMessage: String {
        switch self {
        case .needsPath:
            return "Set the Cell2Fire binary path."
        case .invalid:
            return "Binary path must point to the Cell2Fire executable."
        case .resolved:
            return ""
        }
    }
}

@MainActor
final class SimulationRunState: ObservableObject {
    @Published var log = "Ready."
    @Published var isRunning = false
    @Published var selectedSim = "S"
    @Published var includeRos = true
    @Published var weatherPeriodMinutes = 60
    @Published var weatherPeriodInput = "60"
    @Published var showWeatherInfo = false
    @Published var outputFormat: OutputFormat = .asc
    @Published var numberOfSimulationsInput = "1"
    @Published var numberOfSimulations = 1
    @Published var numberOfThreadsInput = "7"
    @Published var numberOfThreads = 7
    @Published var seedInput = "123"
    @Published var seedValue = 123
    @Published var showSimInfo = false
    @Published var showThreadInfo = false
    @Published var showSeedInfo = false
    @Published var runSummaries: [RunSummary] = []
    @Published var hasSuccessfulRun = false
    @Published var lastOutputDirectory: String?
    @Published var isExportingKMZ = false
    @Published var logFileURL: URL?
    @Published var showLogSheet = false

    func appendLog(_ entry: String, maxCharacterCount: Int) {
        log.append(contentsOf: entry)
        if log.count > maxCharacterCount {
            let overflow = log.count - maxCharacterCount
            if let cutoff = log.index(log.startIndex, offsetBy: overflow, limitedBy: log.endIndex) {
                log = String(log[cutoff...])
            }
        }
    }
}

@MainActor
final class SimulationOverlayState: ObservableObject {
    @Published var rosOverlay: RateOfSpreadOverlay?
    @Published var lastOverlayASCIIURL: URL?
    @Published var lastOverlaySourceURL: URL?
    @Published var lastOverlayGrid: RateOfSpreadGrid?
    @Published var overlaySnapshotBeforeRun: OverlaySnapshot?
    @Published var overlayLoadVersion = 0
    @Published var inspectMode = false
    @Published var inspectResult: InspectResult?
    @Published var defaultIgnitionCells: [Int] = []
    @Published var currentIgnitionCell: Int?
    @Published var ignitionMarkers: [IgnitionMarker] = []

    var activeIgnitionCell: Int? {
        currentIgnitionCell ?? defaultIgnitionCells.first
    }
}

struct RateOfSpreadGrid {
    let sourceURL: URL
    let width: Int
    let height: Int
    let cellSize: Double
    let minValue: Double
    let maxValue: Double
    let minLon: Double
    let maxLon: Double
    let minLat: Double
    let maxLat: Double
    let values: [Double?]
}

struct OverlaySnapshot {
    let overlay: RateOfSpreadOverlay?
    let asciiURL: URL?
    let sourceURL: URL?
    let grid: RateOfSpreadGrid?
}

struct ASCIIHeaderMetadata {
    let xOrigin: Double?
    let yOrigin: Double?
    let cellSize: Double?
}

struct ProjectionInfo {
    let srs: String
    let isWGS84: Bool
}

struct IndiaWildfireReadinessCheck: Identifiable {
    let id = UUID()
    let title: String
    let isReady: Bool
    let detail: String
}

struct SimulationStats: Identifiable {
    let id = UUID()
    let simulationIndex: Int
    let weatherFile: String?
    let ignitionCell: Int?
    let totalCells: Int?
    let available: Int?
    let burnt: Int?
    let nonBurnable: Int?
    let firebreak: Int?
    let highestROS: Double?
    let lowestROS: Double?
}

struct RunSummary: Identifiable {
    let id = UUID()
    let timestamp: Date
    let simulations: [SimulationStats]
}

struct PersistedSimulationSummary: Codable {
    let simulationIndex: Int
    let weatherFile: String?
    let ignitionCell: Int?
    let totalCells: Int?
    let available: Int?
    let burnt: Int?
    let nonBurnable: Int?
    let firebreak: Int?
    let burntPercent: Double?
    let highestROS: Double?
    let lowestROS: Double?
}

struct PersistedRunSummaryDocument: Codable {
    let runID: String
    let timestamp: Date
    let totalBurnt: Int?
    let totalCells: Int?
    let totalBurntPercent: Double?
    let highestROS: Double?
    let lowestROS: Double?
    let simulations: [PersistedSimulationSummary]
}

struct PersistedFileReference: Codable {
    let label: String
    let kind: String
    let path: String
    let relativePath: String?
    let sha256: String?
    let sizeBytes: Int64?
    let modifiedAt: Date?
}

extension PersistedFileReference {
    var relativePathOrPath: String {
        relativePath ?? path
    }
}

struct PersistedArtifactIndex: Codable {
    let runID: String
    let generatedAt: Date
    let artifacts: [PersistedFileReference]
}

struct TCFDSectionDocument: Codable {
    let summary: [String]
    let evidence: [String]
    let gaps: [String]
}

struct TCFDMappingDocument: Codable {
    let runID: String
    let generatedAt: Date
    let governance: TCFDSectionDocument
    let strategy: TCFDSectionDocument
    let riskManagement: TCFDSectionDocument
    let metricsTargets: TCFDSectionDocument
}

struct PersistedRunManifest: Codable {
    let runID: String
    let appVersion: String
    let generatedAt: Date
    let startedAt: Date
    let completedAt: Date
    let durationSeconds: Double
    let binaryPath: String
    let binaryHash: String?
    let inputFolder: String
    let outputDirectory: String
    let logFilePath: String?
    let simulatorCode: String
    let simulatorLabel: String
    let scenarioName: String?
    let tcfdScenarioLabel: String?
    let scenarioPathway: String?
    let scenarioHorizon: String?
    let includeROS: Bool
    let weatherPeriodMinutes: Int
    let outputFormat: String
    let numberOfSimulations: Int
    let numberOfThreads: Int
    let seed: Int
    let summaryJSON: String
    let summaryCSV: String
    let artifactIndexJSON: String
    let tcfdMappingJSON: String
    let tcfdPilotReport: String
    let generatedFiles: [PersistedFileReference]
    let inputEvidence: [PersistedFileReference]
    let outputEvidence: [PersistedFileReference]
}

struct PersistedTCFDBundleResult {
    let runID: String
    let bundleDirectory: URL
    let reportURL: URL
}

struct RunConfigurationSnapshot {
    let binaryPath: String
    let inputFolder: String
    let outputDirectory: String
    let simulatorCode: String
    let simulatorLabel: String
    let scenarioName: String?
    let scenarioLabel: String
    let scenarioPathway: String?
    let scenarioHorizon: String?
    let includeROS: Bool
    let weatherPeriodMinutes: Int
    let outputFormat: String
    let numberOfSimulations: Int
    let numberOfThreads: Int
    let seed: Int
}

struct CachedSearchResult {
    let coordinate: CLLocationCoordinate2D
    let span: MKCoordinateSpan?
}

struct ThemedFieldStyle: ViewModifier {
    var background: Color
    var textColor: Color

    func body(content: Content) -> some View {
        content
            .textFieldStyle(.plain)
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(background)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .foregroundColor(textColor)
    }
}

extension View {
    func themedField(background: Color, textColor: Color) -> some View {
        modifier(ThemedFieldStyle(background: background, textColor: textColor))
    }
}

@MainActor
final class LocationSearchState: ObservableObject {
    @Published var query = ""
    @Published var isSearching = false
    @Published var statusMessage: String?

    var activeSearch: MKLocalSearch?
    var cache: [String: CachedSearchResult] = [:]
    var cacheOrder: [String] = []
    var fallbackWorkItem: DispatchWorkItem?
}

@MainActor
final class EarthEngineFetchState: ObservableObject {
    @Published var statusMessage: String?
    @Published var isFetching = false
    @Published var showExtentInfo = false
    @Published var studyAreaExtentStatusMessage = "Study area extent not evaluated yet."

    var studyAreaExtentRefreshWorkItem: DispatchWorkItem?
}
