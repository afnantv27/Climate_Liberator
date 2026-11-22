import SwiftUI

/// Company profile (BRSR Section A identity), reporting scope, team and assurance.
struct SetupView: View {
    @ObservedObject var store: DisclosureStore
    let engagement: DisclosureEngagement
    let accent: Color

    @State private var userNameDraft = ""

    private var locked: Bool { engagement.isLocked }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if locked {
                    Label("Signed off: read-only. Reopen it in Review & Approval to make changes.", systemImage: "lock.fill")
                        .font(.callout)
                        .foregroundStyle(WorkflowStatus.approved.tint)
                }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 14) {
                        companyCard.frame(minWidth: 460)
                        VStack(spacing: 14) {
                            scopeCard
                            teamCard
                        }
                        .frame(minWidth: 420)
                    }
                    VStack(spacing: 14) {
                        companyCard
                        scopeCard
                        teamCard
                    }
                }
                userCard
            }
            .padding(.bottom, 16)
        }
        .onAppear { userNameDraft = store.userName }
    }

    // MARK: Helpers

    private func edit(_ target: String, _ change: (inout DisclosureEngagement) -> Void) {
        store.edit(engagement.id, action: "Edited company and scope", target: target, change)
    }

    private func textRow(_ label: String, _ path: WritableKeyPath<DisclosureEngagement, String>, prompt: String = "") -> some View {
        DSFormRow(label) {
            TextField(prompt, text: Binding(get: { engagement[keyPath: path] },
                                            set: { value in edit(label) { $0[keyPath: path] = value } }))
                .textFieldStyle(.roundedBorder)
                .disabled(locked)
        }
    }

    // MARK: Company

    private var companyCard: some View {
        DSCard("Company", subtitle: "BRSR Section A · I. Details of the listed entity.") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                textRow("Legal name", \.profile.legalName, prompt: "As registered")
                textRow("CIN", \.profile.cin, prompt: "Corporate Identity Number")
                DSFormRow("Year incorporated") {
                    DSNumberField(placeholder: "e.g. 1994", value: engagement.profile.yearOfIncorporation.map { Double($0) },
                                  onCommit: { value in edit("Year incorporated") { $0.profile.yearOfIncorporation = value.map { Int($0) } } },
                                  width: 110, isDisabled: locked)
                }
                textRow("Registered office", \.profile.registeredAddress)
                textRow("Corporate address", \.profile.corporateAddress)
                textRow("E-mail", \.profile.email)
                textRow("Telephone", \.profile.phone)
                textRow("Website", \.profile.website)
                textRow("Stock exchanges", \.profile.stockExchanges, prompt: "e.g. BSE, NSE")
                DSFormRow("Paid-up capital") {
                    HStack {
                        DSNumberField(placeholder: "—", value: engagement.profile.paidUpCapitalCrore,
                                      onCommit: { value in edit("Paid-up capital") { $0.profile.paidUpCapitalCrore = value } },
                                      width: 120, isDisabled: locked)
                        Text("₹ crore").font(.caption).foregroundStyle(DSStyle.subtle)
                    }
                }
                DSFormRow("Sector") {
                    Picker("Sector", selection: Binding(get: { engagement.profile.sector },
                                                        set: { value in edit("Sector") { $0.profile.sector = value } })) {
                        ForEach(IndustrySector.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(locked)
                }
                textRow("NIC code", \.profile.nicCode, prompt: "National Industrial Classification")
                Divider().gridCellUnsizedAxes(.horizontal)
                textRow("BRSR contact", \.profile.contactName, prompt: "Name")
                textRow("Designation", \.profile.contactRole)
                textRow("Contact e-mail", \.profile.contactEmail)
                textRow("Contact phone", \.profile.contactPhone)
            }
        }
    }

    // MARK: Scope

    private var scopeCard: some View {
        let findings = ApplicabilityRules.assess(engagement.profile, fiscalYearStart: engagement.fiscalYearStart)
        return DSCard("Reporting Scope", subtitle: "Which frameworks this engagement covers. The applicability check uses SEBI's rules as checked in \(ApplicabilityRules.rulesCheckedOn); confirm with the latest circulars.") {
            VStack(alignment: .leading, spacing: 12) {
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                    DSFormRow("Financial year") {
                        Stepper(value: Binding(get: { engagement.fiscalYearStart },
                                               set: { value in edit("Financial year") { $0.fiscalYearStart = value } }),
                                in: 2020...2040) {
                            Text(engagement.periodLabel).monospacedDigit()
                        }
                        .disabled(locked)
                    }
                    DSFormRow("Boundary") {
                        Picker("Boundary", selection: Binding(get: { engagement.boundary },
                                                              set: { value in edit("Boundary") { $0.boundary = value } })) {
                            ForEach(ReportingBoundary.allCases) { Text($0.title).tag($0) }
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 240)
                        .disabled(locked)
                    }
                    DSFormRow("Listed") {
                        Toggle("Listed on a stock exchange", isOn: Binding(get: { engagement.profile.isListed },
                                                                          set: { value in edit("Listing") { $0.profile.isListed = value } }))
                            .disabled(locked)
                    }
                    DSFormRow("Market-cap rank") {
                        HStack {
                            DSNumberField(placeholder: "e.g. 640", value: engagement.profile.marketCapRank.map { Double($0) },
                                          onCommit: { value in edit("Market-cap rank") { $0.profile.marketCapRank = value.map { Int($0) } } },
                                          width: 110, isDisabled: locked || !engagement.profile.isListed)
                            Text("from the exchanges' published list").font(.caption).foregroundStyle(DSStyle.subtle)
                        }
                    }
                    DSFormRow("Filing date") {
                        HStack {
                            Toggle("Set", isOn: Binding(get: { engagement.filingDeadline != nil },
                                                        set: { on in edit("Filing date") { $0.filingDeadline = on ? Self.defaultDeadline(for: $0.fiscalYearStart) : nil } }))
                                .labelsHidden()
                            if let deadline = engagement.filingDeadline {
                                DatePicker("Filing date", selection: Binding(get: { deadline },
                                                                             set: { value in edit("Filing date") { $0.filingDeadline = value } }),
                                           displayedComponents: .date)
                                    .labelsHidden()
                            } else {
                                Text("Not set").foregroundStyle(DSStyle.subtle)
                            }
                        }
                        .disabled(locked)
                    }
                }
                Divider()
                ForEach(findings) { finding in
                    frameworkRow(finding)
                }
                Text(ApplicabilityRules.valueChainNote(fiscalYearStart: engagement.fiscalYearStart))
                    .font(.caption)
                    .foregroundStyle(DSStyle.subtle)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func frameworkRow(_ finding: ApplicabilityRules.Finding) -> some View {
        let isOn = engagement.frameworks.contains(finding.framework)
        return HStack(alignment: .top, spacing: 10) {
            Toggle(isOn: Binding(get: { isOn }, set: { value in
                edit(finding.framework.title) { engagement in
                    if value { _ = engagement.frameworks.insert(finding.framework) } else { _ = engagement.frameworks.remove(finding.framework) }
                    // BRSR Core is part of BRSR.
                    if value && finding.framework == .brsrCore { _ = engagement.frameworks.insert(.brsr) }
                }
            })) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .disabled(locked)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(finding.framework.title).font(.callout.weight(.semibold))
                    DSTag(text: finding.requirement.title,
                          color: finding.requirement == .mandatory ? IssueSeverity.warning.tint : DSStyle.subtle)
                    if finding.requirement == .mandatory && !isOn {
                        Text("Recommended").font(.caption2.weight(.semibold)).foregroundStyle(IssueSeverity.warning.tint)
                    }
                }
                Text(finding.reason).font(.caption).foregroundStyle(DSStyle.subtle).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// 31 August after the financial year ends (annual reports usually go out before September AGMs).
    static func defaultDeadline(for fiscalYearStart: Int) -> Date {
        Calendar(identifier: .gregorian).date(from: DateComponents(year: fiscalYearStart + 1, month: 8, day: 31)) ?? Date()
    }

    // MARK: Team

    private var teamCard: some View {
        DSCard("Team and Assurance", subtitle: "Names appear on approvals and in the audit trail. Assurers expect the preparer and reviewer to differ.") {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 10) {
                textRow("Consulting firm", \.team.consultingFirm, prompt: "Leave empty if the company reports itself")
                textRow("Engagement lead", \.team.engagementLead)
                textRow("Preparer", \.team.preparer)
                textRow("Reviewer", \.team.reviewer)
                textRow("Approver", \.team.approver, prompt: "Signs off the report, e.g. CFO")
                textRow("Board committee", \.team.boardCommittee, prompt: "e.g. Risk Management Committee")
                textRow("Assurance provider", \.team.assuranceProvider)
                DSFormRow("Assurance type") {
                    Picker("Assurance type", selection: Binding(get: { engagement.team.assuranceLevel },
                                                                set: { value in edit("Assurance type") { $0.team.assuranceLevel = value } })) {
                        ForEach(AssuranceLevel.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                    .disabled(locked)
                }
            }
        }
    }

    private var userCard: some View {
        DSCard("You", subtitle: "The name recorded on your edits, comments and approvals on this Mac.") {
            HStack(spacing: 10) {
                TextField("Your name", text: $userNameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 320)
                    .onSubmit { store.setUserName(userNameDraft) }
                Button("Save Name") { store.setUserName(userNameDraft) }
                    .disabled(userNameDraft.trimmingCharacters(in: .whitespaces).isEmpty || userNameDraft == store.userName)
                Spacer()
            }
        }
    }
}
