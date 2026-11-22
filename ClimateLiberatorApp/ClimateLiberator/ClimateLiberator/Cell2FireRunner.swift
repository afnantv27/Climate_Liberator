import Foundation

struct Cell2FireResult {
    let terminationStatus: Int32
    let stdout: String
    let stderr: String
}

final class Cell2FireRunner {
    private let stateQueue = DispatchQueue(label: "com.climateliberator.cell2fire.runner-state", qos: .utility)
    private var activeProcess: Process?

    struct RunnerError: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    func cancel() {
        stateQueue.sync {
            activeProcess?.terminate()
        }
    }

    func run(binaryPath: String,
             sim: String = "S",
             inputFolder: String,
             includeRos: Bool = true,
             weatherPeriodMinutes: Int = 60,
             firePeriodLength: Double = 1.0,
             outputFolder: String? = nil,
             numberOfSimulations: Int = 1,
             numberOfThreads: Int = 1,
             seed: Int = 123,
             onStandardOutput: ((String) -> Void)? = nil,
             onStandardError: ((String) -> Void)? = nil,
             completion: @escaping (Result<Cell2FireResult, Error>) -> Void) {

        let binaryURL = URL(fileURLWithPath: binaryPath)
        let workDir = binaryURL.standardizedFileURL == AppDataLocations.bundledEngineURL.standardizedFileURL
            ? Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Engine")
            : binaryURL.deletingLastPathComponent()

        guard FileManager.default.isExecutableFile(atPath: binaryURL.path) else {
            completion(.failure(RunnerError(message: "Cell2Fire binary missing or not executable at \(binaryURL.path)")))
            return
        }

        let weatherMinutes = max(1, weatherPeriodMinutes)

        var args = ["--sim", sim,
                    "--input-instance-folder", inputFolder,
                    "--Weather-Period-Length", "\(weatherMinutes)",
                    "--Fire-Period-Length", "\(max(0.1, firePeriodLength))",
                    "--nsims", "\(max(1, numberOfSimulations))",
                    "--nthreads", "\(max(1, numberOfThreads))",
                    "--seed", "\(seed)"]
        if let outputFolder, !outputFolder.isEmpty {
            args.append(contentsOf: ["--output-folder", outputFolder])
        }
        if includeRos { args.append("--out-ros") }

        let process = Process()
        process.executableURL = binaryURL
        process.arguments = args
        process.currentDirectoryURL = workDir

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = errPipe

        let stdoutHandle = outPipe.fileHandleForReading
        let stderrHandle = errPipe.fileHandleForReading

        var capturedStdout = ""
        var capturedStderr = ""
        let logCallbackQueue = DispatchQueue(label: "com.climateliberator.cell2fire.logcallback", qos: .utility)
        let appendStdout: (String) -> Void = { [self] chunk in
            self.stateQueue.sync {
                capturedStdout.append(chunk)
            }
        }
        let appendStderr: (String) -> Void = { [self] chunk in
            self.stateQueue.sync {
                capturedStderr.append(chunk)
            }
        }

        stdoutHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            appendStdout(chunk)
            if let onStandardOutput {
                logCallbackQueue.async {
                    onStandardOutput(chunk)
                }
            }
        }

        stderrHandle.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { return }
            appendStderr(chunk)
            if let onStandardError {
                logCallbackQueue.async {
                    onStandardError(chunk)
                }
            }
        }

        DispatchQueue.global().async {
            do {
                self.stateQueue.sync {
                    self.activeProcess = process
                }
                try process.run()
            } catch {
                self.stateQueue.sync {
                    self.activeProcess = nil
                }
                DispatchQueue.main.async { completion(.failure(error)) }
                return
            }

            process.waitUntilExit()

            stdoutHandle.readabilityHandler = nil
            stderrHandle.readabilityHandler = nil

            let remainingStdout = stdoutHandle.readDataToEndOfFile()
            let remainingStderr = stderrHandle.readDataToEndOfFile()

            if let chunk = String(data: remainingStdout, encoding: .utf8), !chunk.isEmpty {
                appendStdout(chunk)
                if let onStandardOutput {
                    logCallbackQueue.async {
                        onStandardOutput(chunk)
                    }
                }
            }

            if let chunk = String(data: remainingStderr, encoding: .utf8), !chunk.isEmpty {
                appendStderr(chunk)
                if let onStandardError {
                    logCallbackQueue.async {
                        onStandardError(chunk)
                    }
                }
            }

            self.stateQueue.sync {
                self.activeProcess = nil
            }

            let finalOutput = self.stateQueue.sync {
                (stdout: capturedStdout, stderr: capturedStderr)
            }
            let result = Cell2FireResult(
                terminationStatus: process.terminationStatus,
                stdout: finalOutput.stdout,
                stderr: finalOutput.stderr
            )

            DispatchQueue.main.async {
                if process.terminationStatus == 0 {
                    completion(.success(result))
                } else {
                    let message = result.stderr.isEmpty
                        ? "Cell2Fire exited with code \(process.terminationStatus)"
                        : result.stderr
                    completion(.failure(RunnerError(message: message)))
                }
            }
        }
    }
}
