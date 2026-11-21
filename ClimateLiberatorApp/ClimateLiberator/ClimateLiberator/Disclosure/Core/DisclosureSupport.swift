import Foundation

// MARK: - Storage

/// Per-user storage for the Disclosure workspace, beside the app's other data.
nonisolated struct DisclosureDataLocations: Sendable {
    let root: URL
    let exportsDirectory: URL

    init(root: URL, exportsDirectory: URL) {
        self.root = root
        self.exportsDirectory = exportsDirectory
    }

    static var current: DisclosureDataLocations {
        DisclosureDataLocations(root: AppDataLocations.current.root.appendingPathComponent("Disclosure", isDirectory: true),
                                exportsDirectory: AppDataLocations.exportsDirectory.appendingPathComponent("Disclosure", isDirectory: true))
    }

    var engagementsDirectory: URL { root.appendingPathComponent("Engagements", isDirectory: true) }

    func engagementFile(_ id: UUID) -> URL {
        engagementsDirectory.appendingPathComponent("\(id.uuidString).json")
    }
}

nonisolated enum DisclosureJSON {
    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }

    static func write(_ engagement: DisclosureEngagement, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try encoder().encode(engagement).write(to: url, options: .atomic)
    }

    static func read(from url: URL) throws -> DisclosureEngagement {
        try decoder().decode(DisclosureEngagement.self, from: Data(contentsOf: url))
    }
}

// MARK: - Formatting

/// Number and date formats shared by the views and the reports.
nonisolated enum DisclosureFormat {
    /// Plain number: "12,450", "3.42", "0.0071". No scientific notation.
    static func number(_ value: Double) -> String {
        let magnitude = abs(value)
        if magnitude == 0 { return "0" }
        if magnitude >= 1_000 { return value.formatted(.number.precision(.fractionLength(0))) }
        if magnitude >= 100 { return value.formatted(.number.precision(.fractionLength(0...1))) }
        if magnitude >= 1 { return value.formatted(.number.precision(.fractionLength(0...2))) }
        return value.formatted(.number.precision(.significantDigits(1...3)))
    }

    /// Number with its unit, "%" attached without a space.
    static func value(_ value: Double?, unit: String) -> String {
        guard let value else { return "—" }
        if unit == "%" { return "\(number(value))%" }
        if unit.isEmpty || unit == "count" { return number(value) }
        return "\(number(value)) \(unit)"
    }

    static func percent(_ share: Double) -> String {
        share.formatted(.percent.precision(.fractionLength(0)))
    }

    /// Signed change, "+12%" or "−4%"; nil without a usable prior value.
    static func change(current: Double?, prior: Double?) -> String? {
        guard let ratio = changeRatio(current: current, prior: prior) else { return nil }
        let text = abs(ratio).formatted(.percent.precision(.fractionLength(0...1)))
        if abs(ratio) < 0.0005 { return "0%" }
        return (ratio > 0 ? "+" : "−") + text
    }

    static func changeRatio(current: Double?, prior: Double?) -> Double? {
        guard let current, let prior, prior != 0 else { return nil }
        return (current - prior) / abs(prior)
    }

    static func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    static func dateTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    /// Strict number parsing for typed or imported text: "12,450.5" → 12450.5.
    static func parse(_ raw: String) -> Double? {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "\u{00A0}", with: "")
            .replacingOccurrences(of: "%", with: "")
        guard !cleaned.isEmpty, let value = Double(cleaned), value.isFinite else { return nil }
        return value
    }

    /// File-system-safe name: "Acme Steel Ltd" → "Acme-Steel-Ltd".
    static func fileStem(_ text: String) -> String {
        let parts = text.components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        return parts.isEmpty ? "client" : parts.joined(separator: "-")
    }
}

// MARK: - CSV

/// RFC 4180 CSV: quoted fields, doubled quotes, newlines inside quotes.
nonisolated enum DisclosureCSV {
    static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" || $0 == "\r" }) else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func line(_ fields: [String]) -> String {
        fields.map(field).joined(separator: ",")
    }

    static func write(header: [String], rows: [[String]]) -> String {
        ([line(header)] + rows.map(line)).joined(separator: "\n") + "\n"
    }

    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var inQuotes = false
        var characters = Array(text.replacingOccurrences(of: "\r\n", with: "\n"))
        if characters.first == "\u{FEFF}" { characters.removeFirst() }
        var index = 0
        while index < characters.count {
            let character = characters[index]
            if inQuotes {
                if character == "\"" {
                    if index + 1 < characters.count, characters[index + 1] == "\"" {
                        field.append("\"")
                        index += 1
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(character)
                }
            } else {
                switch character {
                case "\"": inQuotes = true
                case ",":
                    row.append(field)
                    field = ""
                case "\n", "\r":
                    row.append(field)
                    rows.append(row)
                    row = []
                    field = ""
                default: field.append(character)
                }
            }
            index += 1
        }
        if !field.isEmpty || !row.isEmpty {
            row.append(field)
            rows.append(row)
        }
        return rows.filter { !($0.count == 1 && $0[0].trimmingCharacters(in: .whitespaces).isEmpty) }
    }
}
