import SwiftUI

// Design system shared by every workspace (Home, Clients, Reduce, Disclosure…):
// dark translucent panels, white text, one set of status colours.
// Module-specific styling (e.g. workflow status tints) lives with its module.

enum DSStyle {
    static let panel = Color.white.opacity(0.06)
    static let panelStroke = Color.white.opacity(0.10)
    static let rowFill = Color.white.opacity(0.04)
    static let rowSelected = Color.white.opacity(0.12)
    static let subtle = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.42)
    static let good = Color(red: 0.42, green: 0.82, blue: 0.52)
    static let bad = Color(red: 0.96, green: 0.45, blue: 0.42)
    static let warning = Color(red: 0.98, green: 0.74, blue: 0.30)
    static let info = Color(red: 0.55, green: 0.72, blue: 0.98)
    static let background = LinearGradient(
        colors: [Color(red: 0.04, green: 0.07, blue: 0.10), Color(red: 0.06, green: 0.10, blue: 0.14),
                 Color(red: 0.08, green: 0.12, blue: 0.17)],
        startPoint: .topLeading, endPoint: .bottomTrailing)

    /// "42%" for 0.42; used by accessibility values.
    static func percent(_ fraction: Double) -> String {
        "\(Int((max(0, min(1, fraction)) * 100).rounded()))%"
    }
}

// MARK: - Panels

/// A titled panel with an optional accessory on the right of the title.
struct DSCard<Accessory: View, Content: View>: View {
    let title: String
    let subtitle: String
    let accessory: Accessory
    let content: Content

    init(_ title: String, subtitle: String = "", @ViewBuilder content: () -> Content) where Accessory == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.accessory = EmptyView()
        self.content = content()
    }

    init(_ title: String, subtitle: String = "", @ViewBuilder accessory: () -> Accessory, @ViewBuilder content: () -> Content) {
        self.title = title
        self.subtitle = subtitle
        self.accessory = accessory()
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(title).font(.headline)
                Spacer(minLength: 8)
                accessory
            }
            if !subtitle.isEmpty {
                Text(subtitle).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DSStyle.panel)
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).stroke(DSStyle.panelStroke, lineWidth: 1))
        )
    }
}

/// A headline number with context.
struct DSMetricTile: View {
    let title: String
    let value: String
    var detail: String = ""
    var trend: String? = nil
    /// true = the change is good (e.g. lower emissions), false = bad, nil = neutral.
    var trendIsGood: Bool? = nil
    var systemImage: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                if let systemImage {
                    Image(systemName: systemImage).font(.caption).foregroundStyle(DSStyle.subtle)
                }
                Text(title).font(.caption.weight(.medium)).foregroundStyle(DSStyle.subtle).lineLimit(1)
            }
            Text(value)
                .font(.system(size: 22, weight: .semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                if let trend {
                    Text(trend)
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(trendColor)
                }
                if !detail.isEmpty {
                    Text(detail).font(.caption).foregroundStyle(DSStyle.faint).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(DSStyle.panel))
    }

    private var trendColor: Color {
        guard let trendIsGood else { return DSStyle.subtle }
        return trendIsGood ? DSStyle.good : DSStyle.bad
    }
}

// MARK: - Small pieces

struct DSTag: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .padding(.vertical, 3)
            .padding(.horizontal, 7)
            .background(Capsule().fill(color.opacity(0.22)))
    }
}

struct DSProgressBar: View {
    let value: Double
    var tint: Color = .teal
    var height: CGFloat = 6

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.08))
                Capsule().fill(tint).frame(width: max(0, min(1, value)) * proxy.size.width)
            }
        }
        .frame(height: height)
        .accessibilityValue(DSStyle.percent(value))
    }
}

struct DSProgressRing: View {
    let value: Double
    let label: String
    var tint: Color = .teal
    var size: CGFloat = 74

    var body: some View {
        ZStack {
            Circle().stroke(Color.white.opacity(0.08), lineWidth: 7)
            Circle()
                .trim(from: 0, to: max(0, min(1, value)))
                .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: 0) {
                Text(DSStyle.percent(value)).font(.system(size: size * 0.22, weight: .semibold).monospacedDigit())
                Text(label).font(.system(size: size * 0.12)).foregroundStyle(DSStyle.subtle)
            }
        }
        .frame(width: size, height: size)
        .accessibilityElement(children: .combine)
    }
}

struct DSEmptyState<Actions: View>: View {
    let systemImage: String
    let title: String
    let message: String
    let actions: Actions

    init(systemImage: String, title: String, message: String, @ViewBuilder actions: () -> Actions) {
        self.systemImage = systemImage
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: systemImage).font(.system(size: 34)).foregroundStyle(DSStyle.faint)
            Text(title).font(.title3.weight(.semibold))
            Text(message).font(.callout).foregroundStyle(DSStyle.subtle).multilineTextAlignment(.center).frame(maxWidth: 460)
            HStack(spacing: 10) { actions }
        }
        .frame(maxWidth: .infinity)
        .padding(36)
    }
}

struct DSSearchField: View {
    @Binding var text: String
    var prompt = "Search"

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(DSStyle.faint)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.borderless)
                    .foregroundStyle(DSStyle.faint)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 10)
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(Color.white.opacity(0.07)))
    }
}

/// Label column of fixed width and a control column, for forms inside a `Grid`.
func DSFormRow<Content: View>(_ label: String, width: CGFloat = 150, @ViewBuilder _ content: () -> Content) -> some View {
    GridRow {
        Text(label)
            .font(.callout)
            .foregroundStyle(DSStyle.subtle)
            .frame(width: width, alignment: .leading)
            .gridColumnAlignment(.leading)
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Optional number entry that commits on Return or leaving the field.
struct DSNumberField: View {
    let placeholder: String
    let value: Double?
    let onCommit: (Double?) -> Void
    var width: CGFloat? = 150
    var isDisabled = false

    var body: some View {
        TextField(placeholder, value: Binding(get: { value }, set: commit),
                  format: .number.precision(.fractionLength(0...4)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .disabled(isDisabled)
    }

    /// A field commits when it loses focus, which can happen while SwiftUI is tearing
    /// the view down (e.g. switching KPI). Skip unchanged values and hand real changes
    /// to the next run-loop turn so the store never publishes during a view update.
    private func commit(_ newValue: Double?) {
        guard newValue != value else { return }
        let onCommit = onCommit
        Task { @MainActor in onCommit(newValue) }
    }
}
