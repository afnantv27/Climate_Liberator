import Foundation

/// Data-request round trip: export a CSV of the KPIs a client must provide, import
/// the filled sheet back. Consultants send it to plant, HR and finance teams.
nonisolated enum DataRequest {
    static let header = ["metric_id", "area", "metric", "unit", "brsr_ref", "brsr_core", "ifrs_s2_ref",
                         "current_value", "prior_value", "source", "method", "owner", "notes"]

    /// One row per input KPI in scope (required first), pre-filled with what is known.
    static func template(for engagement: DisclosureEngagement, requiredOnly: Bool = false) -> String {
        let scope = engagement.frameworks
        let required = Set(MetricCatalog.requiredInputs(for: scope).map(\.id))
        let definitions = MetricCatalog.all.filter { definition in
            !definition.isCalculated && (required.contains(definition.id) || (!requiredOnly && definition.isUsed(in: scope)))
        }
        let rows = definitions.map { definition -> [String] in
            let entry = engagement.metric(definition.id)
            let current = definition.isText ? entry.text : entry.current.map(plain) ?? ""
            return [definition.id, definition.group.title, definition.title, definition.unit,
                    definition.brsr?.reference ?? "", definition.core.map { "\($0.rawValue) \($0.title)" } ?? "",
                    definition.ifrs?.reference ?? "", current, entry.prior.map(plain) ?? "",
                    entry.source, entry.method, entry.owner, required.contains(definition.id) ? "Required" : "Optional"]
        }
        return DisclosureCSV.write(header: header, rows: rows)
    }

    nonisolated struct Update: Sendable {
        let metricID: String
        var current: Double?
        var prior: Double?
        var text: String?
        var source: String?
        var method: String?
        var owner: String?
    }

    nonisolated struct ImportResult: Sendable {
        var updates: [Update] = []
        var skipped: [String] = []
    }

    /// Parses a filled template. Blank cells leave existing values alone.
    static func parse(_ csv: String) -> ImportResult {
        var result = ImportResult()
        let rows = DisclosureCSV.parse(csv)
        guard let headerRow = rows.first else {
            result.skipped.append("The file is empty.")
            return result
        }
        let columns = Dictionary(headerRow.enumerated().map { ($1.trimmingCharacters(in: .whitespaces).lowercased(), $0) },
                                 uniquingKeysWith: { first, _ in first })
        guard let idColumn = columns["metric_id"] else {
            result.skipped.append("No metric_id column: use the template exported from the app.")
            return result
        }
        func cell(_ row: [String], _ name: String) -> String? {
            guard let index = columns[name], index < row.count else { return nil }
            let value = row[index].trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty ? nil : value
        }
        for (offset, row) in rows.dropFirst().enumerated() {
            let line = offset + 2
            guard idColumn < row.count else { continue }
            let id = row[idColumn].trimmingCharacters(in: .whitespaces)
            guard let definition = MetricCatalog.metric(id) else {
                if !id.isEmpty { result.skipped.append("Line \(line): unknown metric '\(id)'.") }
                continue
            }
            guard !definition.isCalculated else {
                result.skipped.append("Line \(line): \(definition.title) is calculated by the app.")
                continue
            }
            var update = Update(metricID: id)
            if let raw = cell(row, "current_value") {
                if definition.isText {
                    update.text = raw
                } else if let number = DisclosureFormat.parse(raw) {
                    update.current = number
                } else {
                    result.skipped.append("Line \(line): '\(raw)' is not a number for \(definition.title).")
                }
            }
            if let raw = cell(row, "prior_value"), !definition.isText {
                if let number = DisclosureFormat.parse(raw) { update.prior = number }
                else { result.skipped.append("Line \(line): prior value '\(raw)' is not a number.") }
            }
            update.source = cell(row, "source")
            update.method = cell(row, "method")
            update.owner = cell(row, "owner")
            let changesSomething = update.current != nil || update.prior != nil || update.text != nil
                || update.source != nil || update.method != nil || update.owner != nil
            if changesSomething { result.updates.append(update) }
        }
        return result
    }

    private static func plain(_ value: Double) -> String {
        value == value.rounded() && abs(value) < 1e15 ? String(Int64(value)) : String(value)
    }
}
