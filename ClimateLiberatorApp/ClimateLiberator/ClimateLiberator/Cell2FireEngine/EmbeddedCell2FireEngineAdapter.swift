import Foundation

/// Simulation engine adapter that runs Cell2Fire in-process via the C API.
/// No subprocess, no external binary needed.
final class EmbeddedCell2FireEngineAdapter: SimulationEngineServicing {
    private let stateQueue = DispatchQueue(label: "com.climateliberator.embedded-engine.state", qos: .utility)
    private var isCancelled = false

    func cancel() {
        stateQueue.sync { isCancelled = true }
    }

    func run(request: SimulationEngineRequest,
             onStandardOutput: ((String) -> Void)?,
             onStandardError: ((String) -> Void)?,
             completion: @escaping (Result<SimulationEngineExecutionResult, Error>) -> Void) {

        stateQueue.sync { isCancelled = false }

        let emit: (String) -> Void = { msg in
            onStandardOutput?(msg)
        }
        let emitErr: (String) -> Void = { msg in
            onStandardError?(msg)
        }

        DispatchQueue.global(qos: .userInitiated).async { [self] in
            var logBuffer = ""
            var errBuffer = ""

            let log: (String) -> Void = { line in
                let msg = line + "\n"
                logBuffer.append(msg)
                emit(msg)
            }
            let logErr: (String) -> Void = { line in
                let msg = line + "\n"
                errBuffer.append(msg)
                emitErr(msg)
            }

            log("Cell2Fire Embedded Engine v\(Cell2FireSimulation.engineVersion)")
            log("Simulator: \(request.simulatorCode)")
            log("Input: \(request.inputFolder)")
            log("Output: \(request.outputFolder)")
            log("Simulations: \(request.numberOfSimulations) | Threads: \(request.numberOfThreads) | Seed: \(request.seed)")

            // Ensure output directory exists
            do {
                try FileManager.default.createDirectory(
                    atPath: request.outputFolder,
                    withIntermediateDirectories: true
                )
            } catch {
                logErr("Failed to create output directory: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
                return
            }

            do {
                // Configure
                let config = try Cell2FireConfiguration()
                try config.setInputFolder(request.inputFolder)
                try config.setOutputFolder(request.outputFolder)
                try config.setSimulator(request.simulatorCode)
                try config.setNsims(request.numberOfSimulations)
                try config.setNthreads(request.numberOfThreads)
                try config.setSeed(request.seed)
                try config.setFirePeriodLength(Float(request.firePeriodLength))
                try config.setFinalGrid(true)
                try config.setVerbose(true)
                try config.setOutROS(request.includeROS)

                log("Configuration complete. Initializing simulation...")

                // Create simulation
                let sim = try Cell2FireSimulation(config: config)

                // Set progress callback
                sim.setProgressCallback { episode, period, pct in
                    let cancelled = self.stateQueue.sync { self.isCancelled }
                    if !cancelled {
                        let pctStr = String(format: "%.1f", pct * 100)
                        emit("  Episode \(episode) | Period \(period) | \(pctStr)%\n")
                    }
                }

                log("Running \(request.numberOfSimulations) simulation(s)...")

                // Check cancellation before running
                let cancelled = stateQueue.sync { isCancelled }
                if cancelled {
                    logErr("Simulation cancelled before start")
                    DispatchQueue.main.async {
                        completion(.failure(Cell2FireRunner.RunnerError(message: "Simulation cancelled")))
                    }
                    return
                }

                // Run all simulations
                try sim.runAll()

                // Get summary
                let summary = try sim.getSummary()
                let dims = try sim.getDimensions()

                log("")
                log("Simulation Complete")
                log("  Grid: \(dims.rows) x \(dims.cols) (\(dims.cellCount) cells)")
                log("  Burnt: \(summary.burntCells) (\(String(format: "%.2f", summary.burntPercent))%)")
                log("  Available: \(summary.availableCells)")
                log("  Non-burnable: \(summary.nonBurnableCells)")
                log("  Firebreak: \(summary.firebreakCells)")

                let result = SimulationEngineExecutionResult(
                    mode: .embeddedCell2Fire,
                    engineLabel: SimulationEngineMode.embeddedCell2Fire.label,
                    terminationStatus: 0,
                    stdout: logBuffer,
                    stderr: errBuffer,
                    outputManifestURL: nil,
                    runManifestURL: nil,
                    runArtifactURL: nil,
                    artifactIndexURL: nil
                )

                DispatchQueue.main.async {
                    completion(.success(result))
                }

            } catch {
                logErr("Simulation failed: \(error.localizedDescription)")
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
}
