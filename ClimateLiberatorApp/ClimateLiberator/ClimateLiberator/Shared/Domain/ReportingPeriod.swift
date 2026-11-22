import Foundation

/// Indian financial years (April–March), named by the calendar year they start in.
nonisolated enum ReportingPeriod {
    /// "FY 2025-26" for the year starting April 2025.
    static func label(_ startYear: Int) -> String {
        "FY \(startYear)-\(String(format: "%02d", (startYear + 1) % 100))"
    }
    static func priorLabel(_ startYear: Int) -> String { label(startYear - 1) }

    /// Start year of the financial year containing `date`.
    static func startYear(containing date: Date, calendar: Calendar = Calendar(identifier: .gregorian)) -> Int {
        let parts = calendar.dateComponents([.year, .month], from: date)
        let year = parts.year ?? 2025
        return (parts.month ?? 1) >= 4 ? year : year - 1
    }
}
