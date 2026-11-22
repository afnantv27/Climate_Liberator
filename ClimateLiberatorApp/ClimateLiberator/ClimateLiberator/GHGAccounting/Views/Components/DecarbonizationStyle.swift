import SwiftUI

// Colours and number formats shared by the Scenarios and Action Plan steps.

extension MeasureCategory {
    var tint: Color {
        switch self {
        case .buildings: return Color(red: 0.40, green: 0.64, blue: 0.98)
        case .transport: return Color(red: 0.98, green: 0.64, blue: 0.30)
        case .waste: return Color(red: 0.47, green: 0.80, blue: 0.42)
        case .wastewater: return Color(red: 0.72, green: 0.58, blue: 0.96)
        case .energySupply: return Color(red: 0.98, green: 0.83, blue: 0.32)
        case .landUse: return Color(red: 0.36, green: 0.82, blue: 0.70)
        }
    }

    /// Bars and values for measures that add emissions.
    static let addsEmissionsTint = Color(red: 0.96, green: 0.42, blue: 0.42)
}

extension ActionStatus {
    var tint: Color {
        switch self {
        case .proposed: return Color(white: 0.62)
        case .approved: return Color(red: 0.40, green: 0.64, blue: 0.98)
        case .underway: return Color(red: 0.98, green: 0.74, blue: 0.30)
        case .completed: return Color(red: 0.42, green: 0.82, blue: 0.48)
        }
    }
}

enum DecarbonizationFormat {
    /// "−12.3 t" for a cut, "+4.5 t" when a measure adds emissions, "0 t" for neither.
    static func cut(_ tonnes: Double) -> String {
        guard tonnes != 0 else { return "0 t" }
        return (tonnes < 0 ? "+" : "−") + "\(GHGFormat.plain(abs(tonnes))) t"
    }

    static func signedPercent(_ value: Double) -> String {
        (value > 0.0005 ? "+" : value < -0.0005 ? "−" : "") + GHGFormat.percent(abs(value))
    }

    /// Money with Indian lakh/crore for INR ("₹4.2 lakh", "₹1.35 crore"), currency format otherwise.
    static func money(_ value: Double, currency: String) -> String {
        let sign = value < 0 ? "−" : ""
        let amount = abs(value)
        guard currency == "INR" else {
            return sign + amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
        }
        if amount >= 10_000_000 { return "\(sign)₹\(short(amount / 10_000_000)) crore" }
        if amount >= 100_000 { return "\(sign)₹\(short(amount / 100_000)) lakh" }
        return "\(sign)₹\(Int(amount.rounded()).formatted())"
    }

    /// "₹1,250/t" or "−₹300/t" (a saving).
    static func perTonne(_ value: Double, currency: String) -> String {
        let sign = value < 0 ? "−" : ""
        let amount = abs(value)
        let text = currency == "INR"
            ? "₹\(Int(amount.rounded()).formatted())"
            : amount.formatted(.currency(code: currency).precision(.fractionLength(0)))
        return "\(sign)\(text)/t"
    }

    static func currencySymbol(_ currency: String) -> String {
        switch currency {
        case "INR": return "₹"
        case "USD": return "$"
        case "EUR": return "€"
        default: return currency
        }
    }

    private static func short(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(value < 10 ? 2 : value < 100 ? 1 : 0)))
    }
}
