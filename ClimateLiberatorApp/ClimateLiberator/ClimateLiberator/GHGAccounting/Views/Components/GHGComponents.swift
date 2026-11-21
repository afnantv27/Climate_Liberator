import SwiftUI
import MapKit

// MARK: - Shared components

struct GHGPanelCard<Content: View, Accessory: View>: View {
    let title: String
    let subtitle: String
    let accessory: Accessory
    let content: Content

    init(title: String, subtitle: String, @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.accessory = EmptyView()
        self.content = content()
    }

    /// `accessory` sits at the trailing end of the title row (a picker, a button).
    init(title: String, subtitle: String, @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.appSectionTitle)
                Spacer(minLength: 8)
                accessory
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.footnote).foregroundStyle(.white.opacity(0.7))
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(Color.white.opacity(0.06))
                .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).stroke(Color.white.opacity(0.1), lineWidth: 1))
        )
    }
}

struct GHGMetricCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline).foregroundStyle(.white.opacity(0.72))
            Text(value).font(.appMetric)
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(detail).font(.caption).foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Color.white.opacity(0.06)))
    }
}

struct GHGTag: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.vertical, 3)
            .padding(.horizontal, 8)
            .background(Capsule().fill(color.opacity(0.22)))
    }
}

enum GHGFormat {
    static func tonnes(_ value: Double) -> String {
        "\(value.formatted(.number.precision(.fractionLength(0...2)))) tCO2e"
    }

    static func number(_ value: Double, maxDigits: Int = 4) -> String {
        value.formatted(.number.precision(.significantDigits(1...maxDigits)))
    }

    /// Plain number without scientific notation (see `EmissionCalculator.format`).
    static func plain(_ value: Double) -> String { EmissionCalculator.format(value) }

    /// A mass given in kg, shown in the most readable unit: "1,188 t", "94.2 kg", "350 g".
    static func mass(_ kg: Double) -> String {
        let magnitude = abs(kg)
        if magnitude >= 1_000 { return "\(plain(kg / 1_000)) t" }
        if magnitude >= 1 || magnitude == 0 { return "\(plain(kg)) kg" }
        return "\(plain(kg * 1_000)) g"
    }

    static func percent(_ share: Double) -> String {
        if share > 0, share < 0.001 { return "<0.1%" }
        if share >= 0.9995 { return "100%" }
        return share.formatted(.percent.precision(.fractionLength(share < 0.1 || share > 0.99 ? 1 : 0)))
    }

    static func factorValue(_ factor: EmissionFactor, gwp: GWPSet) -> String {
        guard let value = factor.displayCO2ePerUnit(gwp) else { return "value via remote estimate" }
        return "\(number(value, maxDigits: 5)) kg CO2e/\(factor.activityUnit)"
    }

    /// "value · source · region · year" for list rows.
    static func factorDetail(_ factor: EmissionFactor, gwp: GWPSet) -> String {
        var parts = [factorValue(factor, gwp: gwp), factor.source]
        if !factor.region.isEmpty { parts.append(factor.region) }
        if let year = factor.year { parts.append(String(year)) }
        return parts.joined(separator: " · ")
    }
}

extension GeoCoordinate {
    var clCoordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }

    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
