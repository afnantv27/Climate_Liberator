import Foundation

/// Number and date formats shared by every workspace's views and reports.
nonisolated enum DisplayFormat {
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
