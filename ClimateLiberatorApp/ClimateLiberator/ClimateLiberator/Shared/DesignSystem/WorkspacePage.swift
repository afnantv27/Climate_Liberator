import SwiftUI

/// Page frame shared by the workspaces: background, title row with actions,
/// content, and a status line. Leaves room at the top for the app toolbar.
struct WorkspacePage<Actions: View, Content: View>: View {
    let title: String
    let subtitle: String
    var status: String = ""
    @ViewBuilder let actions: () -> Actions
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack {
            DSStyle.background.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(.appPageTitle).accessibilityAddTraits(.isHeader)
                        if !subtitle.isEmpty {
                            Text(subtitle).font(.callout).foregroundStyle(DSStyle.subtle)
                        }
                    }
                    Spacer(minLength: 12)
                    actions()
                }
                content()
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                if !status.isEmpty {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(DSStyle.subtle)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }
            }
            .padding(.top, 84)
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .foregroundStyle(.white)
    }
}

extension WorkspacePage where Actions == EmptyView {
    init(title: String, subtitle: String, status: String = "", @ViewBuilder content: @escaping () -> Content) {
        self.init(title: title, subtitle: subtitle, status: status, actions: { EmptyView() }, content: content)
    }
}
