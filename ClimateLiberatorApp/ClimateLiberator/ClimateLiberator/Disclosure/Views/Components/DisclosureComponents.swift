import SwiftUI

// Disclosure-specific styling. Generic components (DSCard, DSTag, …) are in
// Shared/DesignSystem.

// MARK: - Colours

extension WorkflowStatus {
    var tint: Color {
        switch self {
        case .notStarted: return Color(white: 0.55)
        case .inProgress: return Color(red: 0.40, green: 0.64, blue: 0.98)
        case .readyForReview: return DSStyle.warning
        case .changesRequested: return DSStyle.bad
        case .approved: return DSStyle.good
        }
    }
}

extension IssueSeverity {
    var tint: Color {
        switch self {
        case .blocker: return Color(red: 0.96, green: 0.42, blue: 0.42)
        case .warning: return DSStyle.warning
        case .info: return DSStyle.info
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

// MARK: - Workflow

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
