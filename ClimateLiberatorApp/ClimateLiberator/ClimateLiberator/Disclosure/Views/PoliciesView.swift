import SwiftUI

/// BRSR Section B: policy and management processes for P1–P9, and governance.
struct PoliciesView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let accent: Color

    @State private var selected: Int = 1

    private var locked: Bool { engagement.isLocked }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                matrixCard
                HStack(alignment: .top, spacing: 14) {
                    principleCard.frame(maxWidth: .infinity)
                    governanceCard.frame(width: 380)
                }
            }
            .padding(.bottom, 16)
        }
    }

    private func edit(_ target: String, _ change: (inout DisclosureEngagement) -> Void) {
        store.edit(engagement.id, action: "Edited Section B", target: target, change)
    }

    private func policyBinding<Value>(_ principle: Int, _ path: WritableKeyPath<PrinciplePolicy, Value>) -> Binding<Value> {
        Binding(get: { engagement.policy(principle)[keyPath: path] }, set: { value in
            edit("P\(principle) policy") { engagement in
                guard let index = engagement.policies.firstIndex(where: { $0.principle == principle }) else { return }
                engagement.policies[index][keyPath: path] = value
            }
        })
    }

    // MARK: Matrix

    private struct MatrixQuestion: Identifiable {
        let title: String
        let path: KeyPath<PrinciplePolicy, TriState>
        var id: String { title }
    }

    private let matrixQuestions = [
        MatrixQuestion(title: "Policy in place", path: \.hasPolicy),
        MatrixQuestion(title: "Approved by the board", path: \.boardApproved),
        MatrixQuestion(title: "Translated into procedures", path: \.translatedToProcedures),
        MatrixQuestion(title: "Extends to value-chain partners", path: \.extendsToValueChain)
    ]

    private var matrixCard: some View {
        let complete = engagement.policies.filter(\.isComplete).count
        return DSCard("Section B · Policy and Management Processes",
                      subtitle: "One column per NGRBC principle. Select a principle to answer its questions; a principle without a policy needs a reason.") {
            Text("\(complete) of 9 complete").font(.caption.monospacedDigit())
                .foregroundStyle(complete == 9 ? WorkflowStatus.approved.tint : DSStyle.subtle)
        } content: {
            Grid(alignment: .center, horizontalSpacing: 6, verticalSpacing: 6) {
                GridRow {
                    Text("").gridColumnAlignment(.leading)
                    ForEach(BRSRPrinciple.allCases) { principle in
                        Button { selected = principle.rawValue } label: {
                            Text(principle.code)
                                .font(.caption.weight(.semibold))
                                .frame(width: 54, height: 24)
                                .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(selected == principle.rawValue ? accent.opacity(0.45) : DSStyle.rowFill))
                        }
                        .buttonStyle(.plain)
                        .help(principle.title)
                    }
                }
                ForEach(matrixQuestions) { question in
                    GridRow {
                        Text(question.title).font(.callout).foregroundStyle(DSStyle.subtle)
                        ForEach(BRSRPrinciple.allCases) { principle in
                            matrixCell(engagement.policy(principle.rawValue)[keyPath: question.path], principle: principle.rawValue)
                        }
                    }
                }
                GridRow {
                    Text("Complete").font(.callout).foregroundStyle(DSStyle.subtle)
                    ForEach(BRSRPrinciple.allCases) { principle in
                        Image(systemName: engagement.policy(principle.rawValue).isComplete ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(engagement.policy(principle.rawValue).isComplete ? WorkflowStatus.approved.tint : DSStyle.faint)
                    }
                }
            }
        }
    }

    private func matrixCell(_ value: TriState, principle: Int) -> some View {
        let color: Color = value == .yes ? WorkflowStatus.approved.tint : value == .no ? IssueSeverity.warning.tint : DSStyle.faint
        return Button { selected = principle } label: {
            Text(value.title)
                .font(.caption.weight(.medium))
                .foregroundStyle(color)
                .frame(width: 54, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(color.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    // MARK: Principle editor

    private var principleCard: some View {
        let principle = BRSRPrinciple(rawValue: selected) ?? .p1
        let policy = engagement.policy(selected)
        return DSCard("\(principle.code) · \(principle.title)", subtitle: principle.statement) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                DSFormRow("Policy in place", width: 200) { triPicker(policyBinding(selected, \.hasPolicy)) }
                if policy.hasPolicy == .no {
                    DSFormRow("Reason for no policy", width: 200) {
                        TextField("e.g. Not material to the business; policy planned for next year",
                                  text: policyBinding(selected, \.reasonIfNoPolicy), axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    }
                } else {
                    DSFormRow("Approved by the board", width: 200) { triPicker(policyBinding(selected, \.boardApproved)) }
                    DSFormRow("Translated into procedures", width: 200) { triPicker(policyBinding(selected, \.translatedToProcedures)) }
                    DSFormRow("Extends to value chain", width: 200) { triPicker(policyBinding(selected, \.extendsToValueChain)) }
                    DSFormRow("Web link", width: 200) {
                        TextField("https://", text: policyBinding(selected, \.webLink)).textFieldStyle(.roundedBorder)
                    }
                    DSFormRow("Standards and certifications", width: 200) {
                        TextField("e.g. ISO 14001, ISO 45001, SA 8000", text: policyBinding(selected, \.certifications))
                            .textFieldStyle(.roundedBorder)
                    }
                    DSFormRow("Commitments, goals, targets", width: 200) {
                        TextField("With timelines", text: policyBinding(selected, \.commitments), axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    }
                    DSFormRow("Performance against them", width: 200) {
                        TextField("Reasons if not met", text: policyBinding(selected, \.performance), axis: .vertical)
                            .lineLimit(2...4).textFieldStyle(.roundedBorder)
                    }
                }
            }
            .disabled(locked)
            HStack {
                Button { selected = max(1, selected - 1) } label: { Label("Previous", systemImage: "chevron.left") }
                    .disabled(selected == 1)
                Spacer()
                Button { selected = min(9, selected + 1) } label: { Label("Next", systemImage: "chevron.right") }
                    .disabled(selected == 9)
            }
            .controlSize(.small)
        }
    }

    private func triPicker(_ binding: Binding<TriState>) -> some View {
        Picker("", selection: binding) {
            ForEach(TriState.allCases) { Text($0.title).tag($0) }
        }
        .labelsHidden()
        .pickerStyle(.segmented)
        .frame(width: 180)
    }

    // MARK: Governance

    private func governanceBinding<Value>(_ path: WritableKeyPath<GovernanceDetails, Value>) -> Binding<Value> {
        Binding(get: { engagement.governance[keyPath: path] }, set: { value in
            edit("Governance") { $0.governance[keyPath: path] = value }
        })
    }

    private var governanceCard: some View {
        DSCard("Governance, Leadership and Oversight",
               subtitle: "Section B questions 8–11; the director's statement is under Narratives.") {
            VStack(alignment: .leading, spacing: 10) {
                labelled("Highest authority responsible for BRSR policies") {
                    TextField("Name, designation, DIN", text: governanceBinding(\.highestAuthority)).textFieldStyle(.roundedBorder)
                }
                labelled("Board committee for sustainability decisions") {
                    triPicker(governanceBinding(\.hasSustainabilityCommittee))
                }
                if engagement.governance.hasSustainabilityCommittee == .yes {
                    labelled("Committee details") {
                        TextField("Name and members", text: governanceBinding(\.committeeDetails), axis: .vertical)
                            .lineLimit(1...3).textFieldStyle(.roundedBorder)
                    }
                }
                labelled("How often performance is reviewed") {
                    TextField("e.g. Quarterly by the CSR & ESG committee", text: governanceBinding(\.reviewFrequency))
                        .textFieldStyle(.roundedBorder)
                }
                labelled("Independent assessment of policies") {
                    TextField("Agency name, or none", text: governanceBinding(\.independentAssessment)).textFieldStyle(.roundedBorder)
                }
            }
            .disabled(locked)
        }
    }

    private func labelled<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(DSStyle.subtle)
            content()
        }
    }
}
