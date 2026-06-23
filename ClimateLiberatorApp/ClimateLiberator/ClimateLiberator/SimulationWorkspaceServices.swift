import Foundation
import Combine

struct OperationalRunConfigDocument: Codable {
    let schemaVersion: Int
    let hazardType: String
    let exportedAt: Date
    let binaryPath: String
    let inputFolder: String
    let outputFolder: String
    let simulatorCode: String
    let includeROS: Bool
    let weatherPeriodMinutes: Int
    let outputFormat: String
    let numberOfSimulations: Int
    let numberOfThreads: Int
    let seed: Int
    let selectedScenarioID: UUID?
    let scenarioName: String?
    let tcfdScenarioLabel: String?
    let scenarioPathway: String?
    let scenarioHorizon: String?
}

struct OutputNode: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let url: URL
    let isDirectory: Bool
    var children: [OutputNode]?

    nonisolated init(name: String, url: URL, isDirectory: Bool, children: [OutputNode]?) {
        self.id = "\(url.path)#\(name)"
        self.name = name
        self.url = url
        self.isDirectory = isDirectory
        self.children = children
    }

    nonisolated var isSelectable: Bool {
        !isDirectory && url.pathExtension.lowercased() == "asc"
    }

    nonisolated var iconName: String {
        isDirectory ? "folder" : "square.stack.3d.up"
    }
}

struct OutputTreeDiscoveryLimits {
    let maxDepth: Int
    let maxNodes: Int
}

private struct OutputTreeDiscoveryState: Sendable {
    var emittedNodeCount = 0
    var didHitLimit = false

    nonisolated init(emittedNodeCount: Int = 0, didHitLimit: Bool = false) {
        self.emittedNodeCount = emittedNodeCount
        self.didHitLimit = didHitLimit
    }
}

protocol SimulationRunConfigServicing {
    func exportData(for document: OperationalRunConfigDocument) throws -> Data
    func importDocument(from url: URL) throws -> OperationalRunConfigDocument
    func exportFileName(at date: Date) -> String
}

struct SimulationRunConfigService: SimulationRunConfigServicing {
    func exportData(for document: OperationalRunConfigDocument) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(document)
    }

    func importDocument(from url: URL) throws -> OperationalRunConfigDocument {
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(OperationalRunConfigDocument.self, from: data)
    }

    func exportFileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return "climateliberator-run-config-\(formatter.string(from: date)).json"
    }
}

protocol SimulationReviewDiscoveryServicing: Sendable {
    func discoveryRoots(for outputFolder: String) -> [URL]
}

struct SimulationReviewDiscoveryService: SimulationReviewDiscoveryServicing, Sendable {
    nonisolated func discoveryRoots(for outputFolder: String) -> [URL] {
        let trimmed = outputFolder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }
        let resolved = NSString(string: trimmed).expandingTildeInPath
        let rootURL = URL(fileURLWithPath: resolved)
        let bundleRoot = rootURL.appendingPathComponent("_climateliberator", isDirectory: true)
        if FileManager.default.fileExists(atPath: bundleRoot.path) {
            return [bundleRoot]
        }
        return [rootURL]
    }
}

protocol SimulationOutputTreeServicing: Sendable {
    func buildOutputTree(rateOfSpreadBase: String?,
                         earthEngineOverlaysDirectory: URL?,
                         limits: OutputTreeDiscoveryLimits) -> [OutputNode]
}

enum SimulationEngineMode: String, Codable, CaseIterable, Identifiable {
    case legacyCell2Fire
    case embeddedCell2Fire
    case climateLiberatorRuntimePreview

    var id: String { rawValue }

    var label: String {
        switch self {
        case .legacyCell2Fire:
            return "Legacy Cell2Fire (subprocess)"
        case .embeddedCell2Fire:
            return "Embedded Cell2Fire (in-process)"
        case .climateLiberatorRuntimePreview:
            return "Climate Liberator Runtime preview"
        }
    }

    var requiresExternalBinary: Bool {
        switch self {
        case .embeddedCell2Fire: return false
        default: return true
        }
    }
}

struct SimulationEngineRequest: Sendable {
    let mode: SimulationEngineMode
    let legacyBinaryPath: String
    let simulatorCode: String
    let inputFolder: String
    let outputFolder: String
    let includeROS: Bool
    let weatherPeriodMinutes: Int
    let firePeriodLength: Double
    let outputFormat: OutputFormat
    let numberOfSimulations: Int
    let numberOfThreads: Int
    let seed: Int
}

struct SimulationEngineExecutionResult: Sendable {
    let mode: SimulationEngineMode
    let engineLabel: String
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
    let outputManifestURL: URL?
    let runManifestURL: URL?
    let runArtifactURL: URL?
    let artifactIndexURL: URL?
}

protocol SimulationEngineServicing {
    func cancel()
    func run(request: SimulationEngineRequest,
             onStandardOutput: ((String) -> Void)?,
             onStandardError: ((String) -> Void)?,
             completion: @escaping (Result<SimulationEngineExecutionResult, Error>) -> Void)
}

final class LegacyCell2FireEngineAdapter: SimulationEngineServicing {
    private let runner: Cell2FireRunner

    init(runner: Cell2FireRunner = Cell2FireRunner()) {
        self.runner = runner
    }

    func cancel() {
        runner.cancel()
    }

    func run(request: SimulationEngineRequest,
             onStandardOutput: ((String) -> Void)?,
             onStandardError: ((String) -> Void)?,
             completion: @escaping (Result<SimulationEngineExecutionResult, Error>) -> Void) {
        runner.run(binaryPath: request.legacyBinaryPath,
                   sim: request.simulatorCode,
                   inputFolder: request.inputFolder,
                   includeRos: request.includeROS,
                   weatherPeriodMinutes: request.weatherPeriodMinutes,
                   firePeriodLength: request.firePeriodLength,
                   outputFolder: request.outputFolder,
                   numberOfSimulations: request.numberOfSimulations,
                   numberOfThreads: request.numberOfThreads,
                   seed: request.seed,
                   onStandardOutput: onStandardOutput,
                   onStandardError: onStandardError) { result in
            switch result {
            case .success(let output):
                completion(.success(
                    SimulationEngineExecutionResult(
                        mode: .legacyCell2Fire,
                        engineLabel: SimulationEngineMode.legacyCell2Fire.label,
                        terminationStatus: output.terminationStatus,
                        stdout: output.stdout,
                        stderr: output.stderr,
                        outputManifestURL: nil,
                        runManifestURL: nil,
                        runArtifactURL: nil,
                        artifactIndexURL: nil
                    )
                ))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}

final class ClimateLiberatorEngineAdapter: SimulationEngineServicing {
    private let stateQueue = DispatchQueue(label: "com.climateliberator.runtime.preview-state", qos: .utility)
    private var activeProcess: Process?
    private let runtimeBinaryURL: URL

    init(runtimeBinaryURL: URL = URL(fileURLWithPath: "/Users/afnan/Desktop/Build/engine-rewrite/build/climate-liberator-engine")) {
        self.runtimeBinaryURL = runtimeBinaryURL
    }

    func cancel() {
        stateQueue.sync {
            activeProcess?.terminate()
        }
    }

    func run(request: SimulationEngineRequest,
             onStandardOutput: ((String) -> Void)?,
             onStandardError: ((String) -> Void)?,
             completion: @escaping (Result<SimulationEngineExecutionResult, Error>) -> Void) {
        guard FileManager.default.isExecutableFile(atPath: runtimeBinaryURL.path) else {
            completion(.failure(Cell2FireRunner.RunnerError(
                message: "Climate Liberator Runtime preview binary is missing or not executable at \(runtimeBinaryURL.path)"
            )))
            return
        }

        let process = Process()
        process.executableURL = runtimeBinaryURL
        process.currentDirectoryURL = runtimeBinaryURL.deletingLastPathComponent()

        var args = [
            "--input-instance-folder", request.inputFolder,
            "--output-folder", request.outputFolder,
            "--sim", request.simulatorCode,
            "--landscape-format", request.outputFormat == .tif ? "tif" : "asc",
            "--weather-input-format", "csv",
            "--ignition-input-mode", "csv",
            "--weather", "rows",
            "--nsims", "\(request.numberOfSimulations)",
            "--nthreads", "\(request.numberOfThreads)",
            "--seed", "\(request.seed)",
            "--weather-period-minutes", "\(request.weatherPeriodMinutes)",
            "--execute"
        ]
        if !request.includeROS {
            args.append("--no-ros")
        }
        process.arguments = args

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stdoutHandle = outPipe.fileHandleForReading
        let stderrHandle = errPipe.fileHandleForReading
        var capturedStdout = ""
        var capturedStderr = ""
        let callbackQueue = DispatchQueue(label: "com.climateliberator.runtime.preview-callback", qos: .utility)

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            self.stateQueue.sync { capturedStdout.append(chunk) }
            if let onStandardOutput {
                callbackQueue.async { onStandardOutput(chunk) }
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            self.stateQueue.sync { capturedStderr.append(chunk) }
            if let onStandardError {
                callbackQueue.async { onStandardError(chunk) }
            }
        }

        DispatchQueue.global(qos: .userInitiated).async {
            do {
                self.stateQueue.sync { self.activeProcess = process }
                try process.run()
            } catch {
                self.stateQueue.sync { self.activeProcess = nil }
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            process.waitUntilExit()
            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil

            if let chunk = String(data: stdoutHandle.readDataToEndOfFile(), encoding: .utf8), !chunk.isEmpty {
                self.stateQueue.sync { capturedStdout.append(chunk) }
                if let onStandardOutput {
                    callbackQueue.async { onStandardOutput(chunk) }
                }
            }
            if let chunk = String(data: stderrHandle.readDataToEndOfFile(), encoding: .utf8), !chunk.isEmpty {
                self.stateQueue.sync { capturedStderr.append(chunk) }
                if let onStandardError {
                    callbackQueue.async { onStandardError(chunk) }
                }
            }

            self.stateQueue.sync { self.activeProcess = nil }

            let finalOutput = self.stateQueue.sync {
                (stdout: capturedStdout, stderr: capturedStderr)
            }
            let manifestRoot = URL(fileURLWithPath: request.outputFolder).appendingPathComponent("_climate_liberator_engine", isDirectory: true)
            let result = SimulationEngineExecutionResult(
                mode: .climateLiberatorRuntimePreview,
                engineLabel: SimulationEngineMode.climateLiberatorRuntimePreview.label,
                terminationStatus: process.terminationStatus,
                stdout: finalOutput.stdout,
                stderr: finalOutput.stderr,
                outputManifestURL: manifestRoot.appendingPathComponent("output_manifest.json"),
                runManifestURL: manifestRoot.appendingPathComponent("run_manifest.json"),
                runArtifactURL: manifestRoot.appendingPathComponent("run_artifact.json"),
                artifactIndexURL: manifestRoot.appendingPathComponent("artifact_index.json")
            )

            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(.success(result))
                } else {
                    let message = result.stderr.isEmpty
                        ? "\(SimulationEngineMode.climateLiberatorRuntimePreview.label) exited with code \(process.terminationStatus)"
                        : result.stderr
                    completion(.failure(Cell2FireRunner.RunnerError(message: message)))
                }
            }
        }
    }
}

final class HybridSimulationEngineAdapter: SimulationEngineServicing {
    private let legacyAdapter: SimulationEngineServicing
    private let embeddedAdapter: SimulationEngineServicing
    private let nativeAdapter: SimulationEngineServicing
    private let stateQueue = DispatchQueue(label: "com.climateliberator.simulation-engine.hybrid-state", qos: .utility)
    private var activeMode: SimulationEngineMode = .embeddedCell2Fire

    init(legacyAdapter: SimulationEngineServicing = LegacyCell2FireEngineAdapter(),
         embeddedAdapter: SimulationEngineServicing = EmbeddedCell2FireEngineAdapter(),
         nativeAdapter: SimulationEngineServicing = ClimateLiberatorEngineAdapter()) {
        self.legacyAdapter = legacyAdapter
        self.embeddedAdapter = embeddedAdapter
        self.nativeAdapter = nativeAdapter
    }

    private func adapter(for mode: SimulationEngineMode) -> SimulationEngineServicing {
        switch mode {
        case .legacyCell2Fire:                 return legacyAdapter
        case .embeddedCell2Fire:               return embeddedAdapter
        case .climateLiberatorRuntimePreview:  return nativeAdapter
        }
    }

    func cancel() {
        let mode = stateQueue.sync { activeMode }
        adapter(for: mode).cancel()
    }

    func run(request: SimulationEngineRequest,
             onStandardOutput: ((String) -> Void)?,
             onStandardError: ((String) -> Void)?,
             completion: @escaping (Result<SimulationEngineExecutionResult, Error>) -> Void) {
        stateQueue.sync { activeMode = request.mode }
        adapter(for: request.mode).run(
            request: request,
            onStandardOutput: onStandardOutput,
            onStandardError: onStandardError,
            completion: completion
        )
    }
}

struct SimulationOutputTreeService: SimulationOutputTreeServicing, Sendable {
    nonisolated func buildOutputTree(rateOfSpreadBase: String?,
                                     earthEngineOverlaysDirectory: URL?,
                                     limits: OutputTreeDiscoveryLimits) -> [OutputNode] {
        var nodes: [OutputNode] = []
        var discoveryState = OutputTreeDiscoveryState()

        if let path = rateOfSpreadBase {
            let rosDir = rateOfSpreadDirectory(basePath: path)
            var isDir: ObjCBool = false
            if FileManager.default.fileExists(atPath: rosDir.path, isDirectory: &isDir),
               isDir.boolValue {
                let children = buildOutputNodes(at: rosDir,
                                                depth: 0,
                                                limits: limits,
                                                state: &discoveryState)
                if !children.isEmpty {
                    nodes.append(OutputNode(name: rosDir.lastPathComponent,
                                            url: rosDir,
                                            isDirectory: true,
                                            children: children))
                }
            }
        }

        if let earthEngineOverlaysDirectory {
            let children = buildOutputNodes(at: earthEngineOverlaysDirectory,
                                            depth: 0,
                                            limits: limits,
                                            state: &discoveryState)
            if !children.isEmpty {
                nodes.append(OutputNode(name: "Earth Engine Imports",
                                        url: earthEngineOverlaysDirectory,
                                        isDirectory: true,
                                        children: children))
            }
        }

        return nodes
    }

    nonisolated private func rateOfSpreadDirectory(basePath: String) -> URL {
        let baseURL = URL(fileURLWithPath: basePath)
        if baseURL.lastPathComponent.compare("RateOfSpread", options: .caseInsensitive) == .orderedSame {
            return baseURL
        }
        return baseURL.appendingPathComponent("RateOfSpread")
    }

    nonisolated private func buildOutputNodes(at directory: URL,
                                              depth: Int,
                                              limits: OutputTreeDiscoveryLimits,
                                              state: inout OutputTreeDiscoveryState) -> [OutputNode] {
        guard depth <= limits.maxDepth, !state.didHitLimit else { return [] }
        let fm = FileManager.default
        guard let contents = try? fm.contentsOfDirectory(at: directory,
                                                         includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
                                                         options: [.skipsHiddenFiles]) else {
            return []
        }

        var nodes: [OutputNode] = []
        nodes.reserveCapacity(min(contents.count, 64))

        for url in contents {
            guard !state.didHitLimit else { break }
            if state.emittedNodeCount >= limits.maxNodes {
                state.didHitLimit = true
                break
            }

            let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink == true {
                continue
            }
            var isDir: ObjCBool = false
            fm.fileExists(atPath: url.path, isDirectory: &isDir)
            if isDir.boolValue {
                let children = buildOutputNodes(at: url,
                                                depth: depth + 1,
                                                limits: limits,
                                                state: &state)
                if !children.isEmpty {
                    state.emittedNodeCount += 1
                    nodes.append(OutputNode(name: url.lastPathComponent,
                                            url: url,
                                            isDirectory: true,
                                            children: children))
                }
            } else {
                guard url.pathExtension.lowercased() == "asc" else { continue }
                state.emittedNodeCount += 1
                nodes.append(OutputNode(name: url.lastPathComponent,
                                        url: url,
                                        isDirectory: false,
                                        children: nil))
            }
        }

        if state.didHitLimit {
            nodes.append(OutputNode(name: "More outputs not shown…",
                                    url: directory,
                                    isDirectory: false,
                                    children: nil))
        }

        return nodes.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory && !rhs.isDirectory
            }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }
}

@MainActor
final class SimulationOutputStore: ObservableObject {
    @Published private(set) var nodes: [OutputNode] = []
    @Published private(set) var isLoading = false

    private let treeService: any SimulationOutputTreeServicing
    private var loadToken: UInt = 0

    init(treeService: any SimulationOutputTreeServicing) {
        self.treeService = treeService
    }

    func rebuild(rateOfSpreadBase: String?,
                 earthEngineOverlaysDirectory: URL?,
                 limits: OutputTreeDiscoveryLimits) {
        loadToken &+= 1
        let token = loadToken
        isLoading = true
        let treeService = self.treeService
        DispatchQueue.global(qos: .userInitiated).async {
            let nodes = treeService.buildOutputTree(rateOfSpreadBase: rateOfSpreadBase,
                                                    earthEngineOverlaysDirectory: earthEngineOverlaysDirectory,
                                                    limits: limits)
            DispatchQueue.main.async {
                guard token == self.loadToken else { return }
                self.nodes = nodes
                self.isLoading = false
            }
        }
    }

    func clearLoadingState() {
        isLoading = false
    }
}
