import SwiftUI

// Shared building blocks for the Disclosure workspace. Visual language matches the
// GHG Accounting workspace (dark panels, white text) without depending on it.

// MARK: - Colours

extension WorkflowStatus {
    var tint: Color {
        switch self {
        case .notStarted: return Color(white: 0.55)
        case .inProgress: return Color(red: 0.40, green: 0.64, blue: 0.98)
        case .readyForReview: return Color(red: 0.98, green: 0.74, blue: 0.30)
        case .changesRequested: return Color(red: 0.96, green: 0.45, blue: 0.42)
        case .approved: return Color(red: 0.42, green: 0.82, blue: 0.52)
        }
    }
}

extension IssueSeverity {
    var tint: Color {
        switch self {
        case .blocker: return Color(red: 0.96, green: 0.42, blue: 0.42)
        case .warning: return Color(red: 0.98, green: 0.74, blue: 0.30)
        case .info: return Color(red: 0.55, green: 0.72, blue: 0.98)
        }
    }
    var systemImage: String {
        switch self {
        case .blocker: return "xmark.octagon.fill"
        case .warning: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }
}

extension DisclosureFramework {
    var tint: Color {
        switch self {
        case .brsr: return Color(red: 0.33, green: 0.78, blue: 0.75)
        case .brsrCore: return Color(red: 0.62, green: 0.55, blue: 0.98)
        case .ifrsS2: return Color(red: 0.98, green: 0.64, blue: 0.32)
        }
    }
}

enum DSStyle {
    static let panel = Color.white.opacity(0.06)
    static let panelStroke = Color.white.opacity(0.10)
    static let rowFill = Color.white.opacity(0.04)
    static let rowSelected = Color.white.opacity(0.12)
    static let subtle = Color.white.opacity(0.62)
    static let faint = Color.white.opacity(0.42)
    static let background = LinearGradient(
        colors: [Color(red: 0.04, green: 0.07, blue: 0.10), Color(red: 0.06, green: 0.10, blue: 0.14),
                 Color(red: 0.08, green: 0.12, blue: 0.17)],
        startPoint: .topLeading, endPoint: .bottomTrailing)
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
        return trendIsGood ? WorkflowStatus.approved.tint : WorkflowStatus.changesRequested.tint
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

struct DSStatusPill: View {
    let status: WorkflowStatus
    var compact = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: status.systemImage)
            if !compact { Text(status.title) }
        }
        .font(.caption2.weight(.semibold))
        .foregroundStyle(status.tint)
        .padding(.vertical, 3)
        .padding(.horizontal, compact ? 5 : 8)
        .background(Capsule().fill(status.tint.opacity(0.16)))
        .help(status.title)
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
        .accessibilityValue(DisclosureFormat.percent(value))
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
                Text(DisclosureFormat.percent(value)).font(.system(size: size * 0.22, weight: .semibold).monospacedDigit())
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
        TextField(placeholder, value: Binding(get: { value }, set: onCommit),
                  format: .number.precision(.fractionLength(0...4)))
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.trailing)
            .frame(width: width)
            .disabled(isDisabled)
    }
}

/// A severity-coloured row for a data-quality issue.
struct DSIssueRow: View {
    let issue: QualityIssue
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: issue.severity.systemImage)
                .foregroundStyle(issue.severity.tint)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(issue.title).font(.callout.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                if !issue.detail.isEmpty {
                    Text(issue.detail).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 6)
            if let action {
                Button("Fix", action: action).controlSize(.small)
            }
        }
        .padding(.vertical, 4)
    }
}
