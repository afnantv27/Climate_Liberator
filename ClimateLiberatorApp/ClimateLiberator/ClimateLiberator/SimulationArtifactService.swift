import Foundation
import CryptoKit

protocol SimulationArtifactServicing {
    func persistTCFDBundle(summary: RunSummary,
                           stdout: String,
                           stderr: String,
                           startedAt: Date,
                           completedAt: Date,
                           configuration: RunConfigurationSnapshot,
                           logFilePath: String?) throws -> PersistedTCFDBundleResult
}

final class SimulationArtifactService: SimulationArtifactServicing {
    func persistTCFDBundle(summary: RunSummary,
                           stdout: String,
                           stderr: String,
                           startedAt: Date,
                           completedAt: Date,
                           configuration: RunConfigurationSnapshot,
                           logFilePath: String?) throws -> PersistedTCFDBundleResult {
        let fm = FileManager.default
        let outputURL = URL(fileURLWithPath: configuration.outputDirectory)
        let containerURL = outputURL.appendingPathComponent("_climateliberator", isDirectory: true)
        try fm.createDirectory(at: containerURL, withIntermediateDirectories: true)

        let runID = "run-\(bundleTimestampString(completedAt))-\(String(UUID().uuidString.prefix(8)))"
        let bundleURL = containerURL.appendingPathComponent(runID, isDirectory: true)
        try fm.createDirectory(at: bundleURL, withIntermediateDirectories: true)

        let stdoutURL = bundleURL.appendingPathComponent("raw_stdout.txt")
        let stderrURL = bundleURL.appendingPathComponent("raw_stderr.txt")
        try stdout.write(to: stdoutURL, atomically: true, encoding: .utf8)
        try stderr.write(to: stderrURL, atomically: true, encoding: .utf8)

        let inputEvidence = collectInputEvidence(in: URL(fileURLWithPath: configuration.inputFolder))
        let outputEvidence = collectOutputEvidence(in: outputURL, startedAt: startedAt)
        let summaryDocument = makePersistedSummaryDocument(runID: runID, summary: summary)
        let summaryJSONURL = bundleURL.appendingPathComponent("simulation_summary.json")
        try writeJSON(summaryDocument, to: summaryJSONURL)

        let summaryCSVURL = bundleURL.appendingPathComponent("simulation_summary.csv")
        try makeSimulationSummaryCSV(runID: runID, summary: summary).write(to: summaryCSVURL,
                                                                            atomically: true,
                                                                            encoding: .utf8)

        let artifactIndex = PersistedArtifactIndex(runID: runID,
                                                   generatedAt: completedAt,
                                                   artifacts: outputEvidence)
        let artifactIndexURL = bundleURL.appendingPathComponent("artifact_index.json")
        try writeJSON(artifactIndex, to: artifactIndexURL)

        let mapping = makeTCFDMapping(runID: runID,
                                      generatedAt: completedAt,
                                      configuration: configuration,
                                      summary: summary,
                                      outputEvidence: outputEvidence)
        let mappingURL = bundleURL.appendingPathComponent("tcfd_mapping.json")
        try writeJSON(mapping, to: mappingURL)

        let reportURL = bundleURL.appendingPathComponent("tcfd_pilot_report.md")
        try makeTCFDPilotReport(runID: runID,
                                startedAt: startedAt,
                                completedAt: completedAt,
                                configuration: configuration,
                                summary: summary,
                                mapping: mapping,
                                outputEvidence: outputEvidence).write(to: reportURL,
                                                                      atomically: true,
                                                                      encoding: .utf8)

        let generatedFiles = [
            describeFile(at: stdoutURL, baseURL: bundleURL, kind: "raw_stdout"),
            describeFile(at: stderrURL, baseURL: bundleURL, kind: "raw_stderr"),
            describeFile(at: summaryJSONURL, baseURL: bundleURL, kind: "summary_json"),
            describeFile(at: summaryCSVURL, baseURL: bundleURL, kind: "summary_csv"),
            describeFile(at: artifactIndexURL, baseURL: bundleURL, kind: "artifact_index"),
            describeFile(at: mappingURL, baseURL: bundleURL, kind: "tcfd_mapping"),
            describeFile(at: reportURL, baseURL: bundleURL, kind: "tcfd_report")
        ]

        let manifest = PersistedRunManifest(
            runID: runID,
            appVersion: appVersionString(),
            generatedAt: completedAt,
            startedAt: startedAt,
            completedAt: completedAt,
            durationSeconds: max(0, completedAt.timeIntervalSince(startedAt)),
            binaryPath: configuration.binaryPath,
            binaryHash: sha256(for: URL(fileURLWithPath: configuration.binaryPath)),
            inputFolder: configuration.inputFolder,
            outputDirectory: configuration.outputDirectory,
            logFilePath: logFilePath,
            simulatorCode: configuration.simulatorCode,
            simulatorLabel: configuration.simulatorLabel,
            scenarioName: configuration.scenarioName,
            tcfdScenarioLabel: configuration.scenarioLabel,
            scenarioPathway: configuration.scenarioPathway,
            scenarioHorizon: configuration.scenarioHorizon,
            includeROS: configuration.includeROS,
            weatherPeriodMinutes: configuration.weatherPeriodMinutes,
            outputFormat: configuration.outputFormat,
            numberOfSimulations: configuration.numberOfSimulations,
            numberOfThreads: configuration.numberOfThreads,
            seed: configuration.seed,
            summaryJSON: summaryJSONURL.path,
            summaryCSV: summaryCSVURL.path,
            artifactIndexJSON: artifactIndexURL.path,
            tcfdMappingJSON: mappingURL.path,
            tcfdPilotReport: reportURL.path,
            generatedFiles: generatedFiles,
            inputEvidence: inputEvidence,
            outputEvidence: outputEvidence
        )
        try writeJSON(manifest, to: bundleURL.appendingPathComponent("run_manifest.json"))
        return PersistedTCFDBundleResult(runID: runID, bundleDirectory: bundleURL, reportURL: reportURL)
    }

    private func makePersistedSummaryDocument(runID: String, summary: RunSummary) -> PersistedRunSummaryDocument {
        let totalBurnt = aggregatedBurnt(for: summary)
        let totalCells = aggregatedTotal(for: summary)
        let highestROS = summary.simulations.compactMap(\.highestROS).max()
        let lowestROS = summary.simulations.compactMap(\.lowestROS).min()
        let totalBurntPercent: Double?
        if let totalBurnt, let totalCells, totalCells > 0 {
            totalBurntPercent = (Double(totalBurnt) / Double(totalCells)) * 100.0
        } else {
            totalBurntPercent = nil
        }

        return PersistedRunSummaryDocument(
            runID: runID,
            timestamp: summary.timestamp,
            totalBurnt: totalBurnt,
            totalCells: totalCells,
            totalBurntPercent: totalBurntPercent,
            highestROS: highestROS,
            lowestROS: lowestROS,
            simulations: summary.simulations.map { stats in
                let total = stats.resolvedTotal
                let burntPercent: Double?
                if let burnt = stats.burnt, let total, total > 0 {
                    burntPercent = (Double(burnt) / Double(total)) * 100.0
                } else {
                    burntPercent = nil
                }
                return PersistedSimulationSummary(
                    simulationIndex: stats.simulationIndex,
                    weatherFile: stats.weatherFile,
                    ignitionCell: stats.ignitionCell,
                    totalCells: total,
                    available: stats.available,
                    burnt: stats.burnt,
                    nonBurnable: stats.nonBurnable,
                    firebreak: stats.firebreak,
                    burntPercent: burntPercent,
                    highestROS: stats.highestROS,
                    lowestROS: stats.lowestROS
                )
            }
        )
    }

    private func makeSimulationSummaryCSV(runID: String, summary: RunSummary) -> String {
        var lines = ["run_id,simulation_index,weather_file,ignition_cell,total_cells,available_cells,burnt_cells,burnt_pct,non_burnable_cells,firebreak_cells,highest_ros_m_per_min,lowest_ros_m_per_min"]
        for stats in summary.simulations {
            let burntPercent: String
            if let burnt = stats.burnt, let total = stats.resolvedTotal, total > 0 {
                burntPercent = csvField(String(format: "%.4f", (Double(burnt) / Double(total)) * 100.0))
            } else {
                burntPercent = ""
            }
            let row = [
                csvField(runID),
                csvField(String(stats.simulationIndex)),
                csvField(stats.weatherFile),
                csvField(optionalString(stats.ignitionCell)),
                csvField(optionalString(stats.resolvedTotal)),
                csvField(optionalString(stats.available)),
                csvField(optionalString(stats.burnt)),
                burntPercent,
                csvField(optionalString(stats.nonBurnable)),
                csvField(optionalString(stats.firebreak)),
                csvField(optionalString(stats.highestROS)),
                csvField(optionalString(stats.lowestROS))
            ].joined(separator: ",")
            lines.append(row)
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private func makeTCFDMapping(runID: String,
                                 generatedAt: Date,
                                 configuration: RunConfigurationSnapshot,
                                 summary: RunSummary,
                                 outputEvidence: [PersistedFileReference]) -> TCFDMappingDocument {
        let simulator = configuration.simulatorLabel
        let latestROSEvidence = outputEvidence.filter { $0.kind.hasPrefix("ros_") }.map(\.relativePathOrPath)
        let summaryEvidence = [
            "simulation_summary.json",
            "simulation_summary.csv",
            "run_manifest.json"
        ]

        return TCFDMappingDocument(
            runID: runID,
            generatedAt: generatedAt,
            governance: TCFDSectionDocument(
                summary: [
                    "This run evidence package translates a completed Climate Liberator wildfire run into a board-reviewable evidence bundle.",
                    "Current governance evidence captures who ran the model, when it ran, which binary and study area were used, and the resulting wildfire outputs."
                ],
                evidence: summaryEvidence,
                gaps: [
                    "Board approvals, delegated authority, and risk appetite thresholds are not yet captured as structured user inputs.",
                    "Management accountability fields still need to be added to the app layer."
                ]
            ),
            strategy: TCFDSectionDocument(
                summary: [
                    "This run used the \(simulator) simulator with \(configuration.numberOfSimulations) stochastic simulation(s), a \(configuration.weatherPeriodMinutes)-minute weather interval, and seed \(configuration.seed).",
                    "Scenario context for this package is \(configuration.scenarioLabel) with pathway \(configuration.scenarioPathway ?? "unspecified") and horizon \(configuration.scenarioHorizon ?? "unspecified")."
                ],
                evidence: summaryEvidence + latestROSEvidence,
                gaps: [
                    "Scenario assumptions still need baseline-versus-comparator evidence and financial deltas.",
                    "Comparative resilience conclusions are not yet generated from paired scenario runs."
                ]
            ),
            riskManagement: TCFDSectionDocument(
                summary: [
                    "The same run workflow used for operational wildfire analysis now produces a durable evidence package for disclosure review.",
                    "Raw stdout/stderr, output rasters, and file inventory are preserved to support traceability."
                ],
                evidence: ["artifact_index.json", "raw_stdout.txt", "raw_stderr.txt"] + latestROSEvidence,
                gaps: [
                    "ERM/GRC export mappings and webhook integrations are not yet implemented.",
                    "Risk thresholds are not yet stored alongside each run."
                ]
            ),
            metricsTargets: TCFDSectionDocument(
                summary: [
                    "Current quantitative outputs include burnt, available, non-burnable, and firebreak cell counts plus ROS extrema per simulation.",
                    "Forward-looking target bands can be layered onto these outputs once target fields are introduced."
                ],
                evidence: summaryEvidence + latestROSEvidence,
                gaps: [
                    "Expected annual loss, exposed assets, and recovery metrics are not yet modeled.",
                    "Target-vs-actual tracking still needs structured configuration."
                ]
            )
        )
    }

    private func makeTCFDPilotReport(runID: String,
                                     startedAt: Date,
                                     completedAt: Date,
                                     configuration: RunConfigurationSnapshot,
                                     summary: RunSummary,
                                     mapping: TCFDMappingDocument,
                                     outputEvidence: [PersistedFileReference]) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium

        let totalBurnt = aggregatedBurnt(for: summary)
        let totalCells = aggregatedTotal(for: summary)
        let burntPercentString: String
        if let totalBurnt, let totalCells, totalCells > 0 {
            burntPercentString = String(format: "%.2f%%", (Double(totalBurnt) / Double(totalCells)) * 100.0)
        } else {
            burntPercentString = "N/A"
        }

        let rosArtifacts = outputEvidence
            .filter { $0.kind.hasPrefix("ros_") }
            .map(\.relativePathOrPath)

        var lines: [String] = []
        lines.append("# Climate Liberator TCFD Run Evidence Report")
        lines.append("")
        lines.append("Run ID: `\(runID)`")
        lines.append("Generated: \(formatter.string(from: completedAt))")
        lines.append("Run window: \(formatter.string(from: startedAt)) to \(formatter.string(from: completedAt))")
        lines.append("Study area: `\(configuration.inputFolder)`")
        lines.append("Output directory: `\(configuration.outputDirectory)`")
        lines.append("Scenario: `\(configuration.scenarioName ?? configuration.scenarioLabel)`")
        lines.append("Pathway: `\(configuration.scenarioPathway ?? "Unspecified")`")
        lines.append("Horizon: `\(configuration.scenarioHorizon ?? "Unspecified")`")
        lines.append("")
        lines.append("This run evidence report packages the current wildfire run into the four TCFD sections using the evidence currently available in Climate Liberator and Cell2Fire.")
        lines.append("")
        lines.append("## Governance")
        lines.append("")
        for item in mapping.governance.summary { lines.append("- \(item)") }
        lines.append("- Evidence: \(mapping.governance.evidence.joined(separator: ", "))")
        lines.append("- Current gap: \(mapping.governance.gaps.joined(separator: " "))")
        lines.append("")
        lines.append("## Strategy")
        lines.append("")
        for item in mapping.strategy.summary { lines.append("- \(item)") }
        lines.append("- Evidence: \(mapping.strategy.evidence.joined(separator: ", "))")
        lines.append("- Current gap: \(mapping.strategy.gaps.joined(separator: " "))")
        lines.append("")
        lines.append("## Risk Management")
        lines.append("")
        for item in mapping.riskManagement.summary { lines.append("- \(item)") }
        lines.append("- Evidence: \(mapping.riskManagement.evidence.joined(separator: ", "))")
        lines.append("- Current gap: \(mapping.riskManagement.gaps.joined(separator: " "))")
        lines.append("")
        lines.append("## Metrics & Targets")
        lines.append("")
        for item in mapping.metricsTargets.summary { lines.append("- \(item)") }
        if let totalBurnt, let totalCells {
            lines.append("- Current aggregate burn outcome: \(formattedCount(totalBurnt)) of \(formattedCount(totalCells)) cells burnt (\(burntPercentString)).")
        }
        if !rosArtifacts.isEmpty {
            lines.append("- ROS evidence: \(rosArtifacts.joined(separator: ", "))")
        }
        lines.append("")
        lines.append("| Simulation | Weather File | Ignition Cell | Burnt | Total | Burnt % | Highest ROS | Lowest ROS |")
        lines.append("| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |")
        for stats in summary.simulations {
            let burntPercent: String
            if let burnt = stats.burnt, let total = stats.resolvedTotal, total > 0 {
                burntPercent = String(format: "%.2f%%", (Double(burnt) / Double(total)) * 100.0)
            } else {
                burntPercent = "N/A"
            }
            lines.append("| \(stats.simulationIndex) | \(stats.weatherFile ?? "N/A") | \(optionalString(stats.ignitionCell) ?? "N/A") | \(optionalString(stats.burnt) ?? "N/A") | \(optionalString(stats.resolvedTotal) ?? "N/A") | \(burntPercent) | \(optionalString(stats.highestROS) ?? "N/A") | \(optionalString(stats.lowestROS) ?? "N/A") |")
        }
        lines.append("")
        lines.append("- Current gap: \(mapping.metricsTargets.gaps.joined(separator: " "))")
        lines.append("")
        lines.append("## Appendix")
        lines.append("")
        lines.append("- `run_manifest.json`")
        lines.append("- `simulation_summary.json`")
        lines.append("- `simulation_summary.csv`")
        lines.append("- `artifact_index.json`")
        lines.append("- `tcfd_mapping.json`")
        lines.append("- `raw_stdout.txt`")
        lines.append("- `raw_stderr.txt`")
        return lines.joined(separator: "\n") + "\n"
    }

    private func collectInputEvidence(in inputURL: URL) -> [PersistedFileReference] {
        let fm = FileManager.default
        var candidates: [URL] = []
        let preferredNames = [
            "fuels.asc",
            "fuels.tif",
            "Weather.csv",
            "Ignitions.csv",
            "Data.csv",
            "probabilityMap.asc",
            "probabilityMap.tif"
        ]

        for name in preferredNames {
            let url = inputURL.appendingPathComponent(name)
            if fm.fileExists(atPath: url.path) {
                candidates.append(url)
            }
        }

        if let contents = try? fm.contentsOfDirectory(at: inputURL,
                                                      includingPropertiesForKeys: nil,
                                                      options: [.skipsHiddenFiles]) {
            let lookupTables = contents.filter {
                $0.pathExtension.lowercased() == "csv" &&
                $0.lastPathComponent.lowercased().contains("lookup_table")
            }
            candidates.append(contentsOf: lookupTables)
        }

        return deduplicated(candidates)
            .map { describeFile(at: $0, baseURL: inputURL, kind: inputArtifactKind(for: $0)) }
            .sorted { ($0.relativePath ?? $0.path) < ($1.relativePath ?? $1.path) }
    }

    private func collectOutputEvidence(in outputURL: URL, startedAt: Date) -> [PersistedFileReference] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: outputURL,
                                             includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
                                             options: [.skipsHiddenFiles]) else {
            return []
        }

        var artifacts: [PersistedFileReference] = []
        for case let fileURL as URL in enumerator {
            if fileURL.pathComponents.contains("_climateliberator") {
                continue
            }
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
                  values.isRegularFile == true else {
                continue
            }
            if let modifiedAt = values.contentModificationDate,
               modifiedAt < startedAt.addingTimeInterval(-5) {
                continue
            }
            artifacts.append(describeFile(at: fileURL, baseURL: outputURL, kind: outputArtifactKind(for: fileURL)))
        }

        return artifacts.sorted { $0.relativePathOrPath < $1.relativePathOrPath }
    }

    private func describeFile(at url: URL, baseURL: URL?, kind: String) -> PersistedFileReference {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        let relativePath: String?
        if let baseURL {
            let prefix = baseURL.path.hasSuffix("/") ? baseURL.path : baseURL.path + "/"
            relativePath = url.path.hasPrefix(prefix) ? String(url.path.dropFirst(prefix.count)) : nil
        } else {
            relativePath = nil
        }

        return PersistedFileReference(
            label: url.lastPathComponent,
            kind: kind,
            path: url.path,
            relativePath: relativePath,
            sha256: sha256(for: url),
            sizeBytes: values?.fileSize.map(Int64.init),
            modifiedAt: values?.contentModificationDate
        )
    }

    private func inputArtifactKind(for url: URL) -> String {
        let name = url.lastPathComponent.lowercased()
        if name.hasPrefix("fuels.") { return "input_fuels" }
        if name == "weather.csv" { return "input_weather" }
        if name == "ignitions.csv" { return "input_ignitions" }
        if name == "data.csv" { return "input_data_matrix" }
        if name.contains("lookup_table") { return "input_lookup_table" }
        if name.hasPrefix("probabilitymap.") { return "input_probability_map" }
        return "input_file"
    }

    private func outputArtifactKind(for url: URL) -> String {
        let path = url.path.lowercased()
        let name = url.lastPathComponent.lowercased()
        if path.contains("/rateofspread/") {
            switch url.pathExtension.lowercased() {
            case "asc": return "ros_ascii"
            case "tif": return "ros_geotiff"
            case "kmz": return "ros_kmz"
            default: return "ros_output"
            }
        }
        if name == "ignition_and_weather_log.csv" { return "ignition_weather_log" }
        if path.contains("/messages/") { return "messages_csv" }
        if name.hasPrefix("finalstatus") { return "final_grid" }
        if path.contains("/surfaceintensity/") { return "surface_intensity" }
        if path.contains("/crownintensity/") { return "crown_intensity" }
        if path.contains("/surfaceflamelength/") { return "surface_flame_length" }
        if path.contains("/crownflamelength/") { return "crown_flame_length" }
        if path.contains("/maxflamelength/") { return "max_flame_length" }
        if path.contains("/crownfractionburn/") { return "crown_fraction_burn" }
        if path.contains("/surffractionburn/") { return "surface_fraction_burn" }
        if path.contains("/crownfire/") { return "crown_fire" }
        return "output_file"
    }

    private func writeJSON<T: Encodable>(_ value: T, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        try data.write(to: url, options: .atomic)
    }

    private func sha256(for url: URL) -> String? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func bundleTimestampString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: date)
    }

    private func appVersionString() -> String {
        let bundle = Bundle.main
        let shortVersion = bundle.infoDictionary?["CFBundleShortVersionString"] as? String
        let buildNumber = bundle.infoDictionary?["CFBundleVersion"] as? String
        switch (shortVersion, buildNumber) {
        case let (.some(short), .some(build)) where !short.isEmpty && !build.isEmpty:
            return "\(short) (\(build))"
        case let (.some(short), _):
            return short
        case let (_, .some(build)):
            return build
        default:
            return "unknown"
        }
    }

    private func csvField(_ value: String?) -> String {
        guard let value else { return "" }
        let escaped = value.replacingOccurrences(of: "\"", with: "\"\"")
        return "\"\(escaped)\""
    }

    private func optionalString<T>(_ value: T?) -> String? {
        guard let value else { return nil }
        return String(describing: value)
    }

    private func deduplicated(_ urls: [URL]) -> [URL] {
        var seen: Set<String> = []
        var ordered: [URL] = []
        for url in urls {
            let path = url.standardizedFileURL.path
            if seen.insert(path).inserted {
                ordered.append(url)
            }
        }
        return ordered
    }

    private func aggregatedBurnt(for summary: RunSummary) -> Int? {
        let values = summary.simulations.compactMap { $0.burnt }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func aggregatedTotal(for summary: RunSummary) -> Int? {
        let values = summary.simulations.compactMap { $0.resolvedTotal }
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +)
    }

    private func formattedCount(_ value: Int?) -> String {
        guard let value else { return "—" }
        return NumberFormatter.localizedString(from: NSNumber(value: value), number: .decimal)
    }
}

// `resolvedTotal` is defined once (internal) on SimulationStats in MapOverlays.swift
// and shared across the module.
