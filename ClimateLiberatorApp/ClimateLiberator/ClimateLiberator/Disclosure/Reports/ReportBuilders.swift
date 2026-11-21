import Foundation

/// Reports the platform produces.
nonisolated enum ReportKind: String, CaseIterable, Identifiable, Sendable {
    case brsr, brsrCore, ifrsS2, assurancePack, auditTrail

    var id: String { rawValue }
    var title: String {
        switch self {
        case .brsr: return "BRSR Report (draft)"
        case .brsrCore: return "BRSR Core KPI Table"
        case .ifrsS2: return "IFRS S2 Climate Disclosure (draft)"
        case .assurancePack: return "Assurance Pack"
        case .auditTrail: return "Audit Trail"
        }
    }
    var detail: String {
        switch self {
        case .brsr: return "Sections A, B and C in SEBI's structure, current and prior year."
        case .brsrCore: return "All nine attributes with values, units and assurance status."
        case .ifrsS2: return "Governance, strategy, risk management, metrics and targets, with a paragraph index."
        case .assurancePack: return "Every BRSR Core KPI with source, method, owner, approval and evidence, for the assessor or assurer."
        case .auditTrail: return "Who changed, submitted and approved what, and when."
        }
    }
    var systemImage: String {
        switch self {
        case .brsr: return "doc.text"
        case .brsrCore: return "tablecells"
        case .ifrsS2: return "globe.asia.australia"
        case .assurancePack: return "checkmark.shield"
        case .auditTrail: return "clock.arrow.circlepath"
        }
    }
    var framework: DisclosureFramework? {
        switch self {
        case .brsr: return .brsr
        case .brsrCore, .assurancePack: return .brsrCore
        case .ifrsS2: return .ifrsS2
        case .auditTrail: return nil
        }
    }
}

nonisolated enum ReportBuilder {

    /// `physicalRiskParagraphs` come from the physical-risk drafting adapter (main actor).
    static func build(_ kind: ReportKind, engagement: DisclosureEngagement, physicalRiskParagraphs: [String] = [],
                      generatedAt: Date = Date()) -> ReportDocument {
        let values = MetricResolver(engagement)
        switch kind {
        case .brsr: return brsr(engagement, values: values, generatedAt: generatedAt)
        case .brsrCore: return coreTable(engagement, values: values, generatedAt: generatedAt)
        case .ifrsS2: return ifrsS2(engagement, values: values, physicalRiskParagraphs: physicalRiskParagraphs, generatedAt: generatedAt)
        case .assurancePack: return assurancePack(engagement, values: values, generatedAt: generatedAt)
        case .auditTrail: return auditTrail(engagement, generatedAt: generatedAt)
        }
    }

    // MARK: Shared pieces

    private static func subtitle(_ engagement: DisclosureEngagement, generatedAt: Date) -> String {
        var parts = [engagement.periodLabel, "\(engagement.boundary.title) basis", "Generated \(DisclosureFormat.dateTime(generatedAt))"]
        if let signOff = engagement.signOff {
            parts.append("Signed off by \(signOff.approvedBy) on \(DisclosureFormat.date(signOff.approvedAt))")
        } else {
            parts.append("Draft")
        }
        return parts.joined(separator: " · ")
    }

    private static func standardNotes(_ document: inout ReportDocument, _ engagement: DisclosureEngagement) {
        if engagement.isExample {
            document.note("Illustrative example company. All figures are invented for demonstration.")
        }
        if engagement.signOff == nil {
            document.note("Draft for review. Check against the regulator's prescribed format and the latest circulars before filing.")
        }
    }

    /// Value text: number with unit, text, "Not applicable" or "Not reported".
    static func valueText(_ definition: MetricDefinition, value: Double?, entry: MetricEntry, isCurrent: Bool) -> String {
        if definition.isText {
            return isCurrent ? (entry.text.isEmpty ? "Not reported" : entry.text) : "—"
        }
        if entry.notApplicable && !definition.isCalculated {
            return "Not applicable" + (entry.notApplicableReason.isEmpty ? "" : " (\(entry.notApplicableReason))")
        }
        guard let value else { return isCurrent ? "Not reported" : "—" }
        return DisclosureFormat.value(value, unit: definition.unit == "count" ? "" : definition.unit)
    }

    private static func metricTable(_ caption: String, _ definitions: [MetricDefinition], engagement: DisclosureEngagement,
                                    values: MetricResolver, referenceColumn: (MetricDefinition) -> String) -> ReportTable {
        let rows = definitions.map { definition -> [String] in
            let entry = engagement.metric(definition.id)
            let resolved = values[definition.id]
            return [definition.title, referenceColumn(definition),
                    valueText(definition, value: resolved.current, entry: entry, isCurrent: true),
                    valueText(definition, value: resolved.prior, entry: entry, isCurrent: false)]
        }
        return ReportTable(caption: caption, columns: ["Indicator", "Reference", engagement.periodLabel, engagement.priorPeriodLabel], rows: rows)
    }

    private static func narrative(_ document: inout ReportDocument, _ id: String, _ engagement: DisclosureEngagement, level: Int = 3) {
        guard let requirement = NarrativeCatalog.requirement(id) else { return }
        let entry = engagement.narrative(id)
        document.heading("\(requirement.title) (\(requirement.reference))", level: level)
        if entry.notApplicable {
            document.paragraph("Not applicable. \(entry.notApplicableReason)")
        } else if entry.hasText {
            document.paragraph(entry.text)
        } else {
            document.note("Not yet written.")
        }
    }

    // MARK: BRSR

    private static func brsr(_ engagement: DisclosureEngagement, values: MetricResolver, generatedAt: Date) -> ReportDocument {
        let profile = engagement.profile
        var document = ReportDocument(title: "Business Responsibility and Sustainability Report — \(engagement.companyName)",
                                      subtitle: subtitle(engagement, generatedAt: generatedAt))
        standardNotes(&document, engagement)

        document.heading("Section A: General disclosures")
        func text(_ value: String) -> String { value.trimmingCharacters(in: .whitespaces).isEmpty ? "—" : value }
        document.table(ReportTable(caption: "I. Details of the listed entity", columns: ["Item", "Details"], rows: [
            ["Corporate Identity Number (CIN)", text(profile.cin)],
            ["Name of the listed entity", text(profile.legalName)],
            ["Year of incorporation", profile.yearOfIncorporation.map { String($0) } ?? "—"],
            ["Registered office address", text(profile.registeredAddress)],
            ["Corporate address", text(profile.corporateAddress)],
            ["E-mail", text(profile.email)],
            ["Telephone", text(profile.phone)],
            ["Website", text(profile.website)],
            ["Financial year", engagement.periodLabel],
            ["Stock exchanges where listed", text(profile.stockExchanges)],
            ["Paid-up capital", profile.paidUpCapitalCrore.map { DisclosureFormat.value($0, unit: "₹ crore") } ?? "—"],
            ["Contact person for BRSR queries", text([profile.contactName, profile.contactRole, profile.contactEmail, profile.contactPhone]
                .filter { !$0.isEmpty }.joined(separator: ", "))],
            ["Reporting boundary", engagement.boundary.title],
            ["Assessment or assurance provider", text(engagement.team.assuranceProvider)],
            ["Type of assessment or assurance", engagement.team.assuranceLevel.title],
        ]))
        narrative(&document, "brsr.a.business", engagement)
        narrative(&document, "brsr.a.operations", engagement)
        document.table(metricTable("IV. Employees", MetricCatalog.metrics(in: .workforce), engagement: engagement, values: values,
                                   referenceColumn: { $0.brsr?.reference ?? "" }))
        narrative(&document, "brsr.a.entities", engagement)
        narrative(&document, "brsr.a.csr", engagement)
        narrative(&document, "brsr.a.complaints", engagement)
        document.heading("Material responsible business conduct issues", level: 3)
        if engagement.issues.isEmpty {
            document.note("No material issues recorded.")
        } else {
            document.table(ReportTable(caption: "", columns: ["Material issue", "Risk / opportunity", "Rationale",
                                                             "Approach to adapt or mitigate", "Financial implications"],
                                       rows: sortedIssues(engagement.issues).map { issue in
                                           [issue.title, issue.type.title, issue.rationale, issue.approach, implicationText(issue)]
                                       }))
        }

        document.heading("Section B: Management and process disclosures")
        let principles = BRSRPrinciple.allCases
        func policyRow(_ label: String, _ answer: (PrinciplePolicy) -> String) -> [String] {
            [label] + principles.map { answer(engagement.policy($0.rawValue)) }
        }
        document.table(ReportTable(caption: "Policy and management processes", columns: ["Question"] + principles.map(\.code), rows: [
            policyRow("Policy covers the principle and its core elements") { $0.hasPolicy.title },
            policyRow("Policy approved by the Board") { $0.boardApproved.title },
            policyRow("Web link of the policy") { $0.webLink.isEmpty ? "—" : $0.webLink },
            policyRow("Policy translated into procedures") { $0.translatedToProcedures.title },
            policyRow("Policy extends to value-chain partners") { $0.extendsToValueChain.title },
            policyRow("Certifications and standards adopted") { $0.certifications.isEmpty ? "—" : $0.certifications },
            policyRow("Commitments, goals and targets") { $0.commitments.isEmpty ? "—" : $0.commitments },
            policyRow("Performance against commitments") { $0.performance.isEmpty ? "—" : $0.performance },
            policyRow("Reason if no policy") { $0.reasonIfNoPolicy.isEmpty ? "—" : $0.reasonIfNoPolicy },
        ]))
        narrative(&document, "brsr.b.director", engagement)
        let governance = engagement.governance
        document.table(ReportTable(caption: "Governance, leadership and oversight", columns: ["Item", "Details"], rows: [
            ["Highest authority responsible for implementation and oversight", text(governance.highestAuthority)],
            ["Specified committee of the Board / Director for sustainability decisions",
             governance.hasSustainabilityCommittee == .unanswered ? "—" : "\(governance.hasSustainabilityCommittee.title). \(governance.committeeDetails)"],
            ["Review of NGRBC performance and compliance", text(governance.reviewFrequency)],
            ["Independent assessment of policies by an external agency", text(governance.independentAssessment)],
        ]))

        document.heading("Section C: Principle-wise performance disclosure")
        for principle in principles {
            let definitions = MetricCatalog.all.filter { $0.brsr?.principle == principle }
                .sorted { sectionCOrder($0) < sectionCOrder($1) }
            let narratives = NarrativeCatalog.all.filter { $0.framework == .brsr && $0.id.hasPrefix("brsr.\(principle.code.lowercased()).") }
            document.heading("Principle \(principle.rawValue): \(principle.title)")
            document.paragraph(principle.statement)
            if definitions.isEmpty && narratives.isEmpty {
                document.note("Answer this principle's questions in the full SEBI format; the platform does not collect them yet.")
                continue
            }
            if !definitions.isEmpty {
                document.table(metricTable("", definitions, engagement: engagement, values: values,
                                           referenceColumn: { definition in
                                               let level = definition.brsr?.level == .leadership ? " (leadership)" : ""
                                               return (definition.brsr?.reference ?? "") + level
                                           }))
            }
            for requirement in narratives { narrative(&document, requirement.id, engagement) }
        }
        if engagement.frameworks.contains(.brsrCore) {
            document.heading("BRSR Core summary")
            document.table(coreSummaryTable(engagement, values: values))
        }
        return document
    }

    // MARK: BRSR Core

    private static func coreSummaryTable(_ engagement: DisclosureEngagement, values: MetricResolver) -> ReportTable {
        var rows: [[String]] = []
        for attribute in BRSRCoreAttribute.allCases {
            for definition in MetricCatalog.metrics(in: attribute) {
                let entry = engagement.metric(definition.id)
                let resolved = values[definition.id]
                let status = definition.isCalculated ? "Calculated" : entry.status.title
                rows.append(["\(attribute.rawValue). \(attribute.title)", definition.title, definition.unit == "count" ? "number" : definition.unit,
                             valueText(definition, value: resolved.current, entry: entry, isCurrent: true),
                             valueText(definition, value: resolved.prior, entry: entry, isCurrent: false),
                             definition.brsr?.reference ?? "", status])
            }
        }
        return ReportTable(caption: "BRSR Core KPIs",
                           columns: ["Attribute", "Parameter", "Unit", engagement.periodLabel, engagement.priorPeriodLabel, "BRSR reference", "Status"],
                           rows: rows)
    }

    private static func coreTable(_ engagement: DisclosureEngagement, values: MetricResolver, generatedAt: Date) -> ReportDocument {
        var document = ReportDocument(title: "BRSR Core KPIs — \(engagement.companyName)", subtitle: subtitle(engagement, generatedAt: generatedAt))
        standardNotes(&document, engagement)
        document.paragraph("Assessment or assurance provider: \(engagement.team.assuranceProvider.isEmpty ? "not appointed" : engagement.team.assuranceProvider) (\(engagement.team.assuranceLevel.title)).")
        document.table(coreSummaryTable(engagement, values: values))
        return document
    }

    private static func assurancePack(_ engagement: DisclosureEngagement, values: MetricResolver, generatedAt: Date) -> ReportDocument {
        var document = ReportDocument(title: "Assurance Pack — \(engagement.companyName)", subtitle: subtitle(engagement, generatedAt: generatedAt))
        standardNotes(&document, engagement)
        let readiness = ReadinessAnalyzer.analyze(engagement)
        document.paragraph("BRSR Core assurance readiness: \(DisclosureFormat.percent(readiness.coreAssuranceScore)) of checks passed (value, prior year, source or method, evidence, approval) across \(readiness.coreRows.count) inputs.")
        let rows = MetricCatalog.requiredInputs(for: .brsrCore).map { definition -> [String] in
            let entry = engagement.metric(definition.id)
            let row = ReadinessAnalyzer.coreRow(definition, in: engagement)
            let evidence = entry.evidenceIDs.compactMap(engagement.evidenceItem).map { item in
                item.location.isEmpty ? item.title : "\(item.title) <\(item.location)>"
            }.joined(separator: "; ")
            return [definition.core.map { "\($0.rawValue). \($0.title)" } ?? "Input", definition.title, definition.unit,
                    valueText(definition, value: values[definition.id].current, entry: entry, isCurrent: true),
                    valueText(definition, value: values[definition.id].prior, entry: entry, isCurrent: false),
                    entry.source, entry.method, entry.owner, entry.status.title,
                    entry.approvedBy.isEmpty ? "" : "\(entry.approvedBy), \(entry.approvedAt.map(DisclosureFormat.date) ?? "")",
                    evidence.isEmpty ? "None" : evidence, "\(row.checksPassed)/\(CoreAssuranceRow.checkCount)"]
        }
        document.table(ReportTable(caption: "BRSR Core inputs",
                                   columns: ["Attribute", "KPI", "Unit", engagement.periodLabel, engagement.priorPeriodLabel, "Source",
                                             "Method", "Owner", "Status", "Approved", "Evidence", "Checks"], rows: rows))
        let evidenceRows = engagement.evidence.map { item -> [String] in
            [item.title, item.kind.title, item.location, item.period, item.verified ? "Yes (\(item.verifiedBy))" : "No", item.addedBy]
        }
        document.table(ReportTable(caption: "Evidence register", columns: ["Document", "Type", "Location", "Period", "Verified", "Added by"], rows: evidenceRows))
        return document
    }

    // MARK: IFRS S2

    private static func ifrsS2(_ engagement: DisclosureEngagement, values: MetricResolver, physicalRiskParagraphs: [String],
                               generatedAt: Date) -> ReportDocument {
        var document = ReportDocument(title: "Climate-related Disclosures (IFRS S2) — \(engagement.companyName)",
                                      subtitle: subtitle(engagement, generatedAt: generatedAt))
        standardNotes(&document, engagement)
        narrative(&document, "s2.basis", engagement, level: 2)

        document.heading("Governance")
        narrative(&document, "s2.gov.board", engagement)
        narrative(&document, "s2.gov.management", engagement)

        document.heading("Strategy")
        narrative(&document, "s2.str.risks", engagement)
        let climateIssues = sortedIssues(engagement.issues.filter { $0.topic.isClimate })
        if !climateIssues.isEmpty {
            document.table(ReportTable(caption: "Climate-related risks and opportunities",
                                       columns: ["Risk or opportunity", "Type", "Horizon", "Likelihood × impact", "Financial effect", "Response"],
                                       rows: climateIssues.map { issue in
                                           ["\(issue.title) (\(issue.type.title.lowercased()))", issue.topic.title, issue.horizon.title,
                                            "\(issue.likelihood) × \(issue.impact) = \(issue.score)",
                                            implicationText(issue), issue.approach]
                                       }))
        }
        narrative(&document, "s2.str.businessModel", engagement)
        narrative(&document, "s2.str.decisions", engagement)
        narrative(&document, "s2.str.financial", engagement)
        narrative(&document, "s2.str.resilience", engagement)
        if !engagement.physicalRisks.isEmpty {
            document.heading("Physical-risk assessment", level: 3)
            document.table(ReportTable(caption: "", columns: ["Hazard", "Scenario / horizon", "Assets", "Value assessed", "Value vulnerable", "Share", "Modelled gross loss"],
                                       rows: engagement.physicalRisks.map { risk in
                                           [risk.hazard.title, [risk.scenario, risk.horizon].filter { !$0.isEmpty }.joined(separator: ", "),
                                            risk.assetsAssessed.map { String($0) } ?? "—",
                                            DisclosureFormat.value(risk.valueAssessedCrore, unit: "₹ crore"),
                                            DisclosureFormat.value(risk.valueVulnerableCrore, unit: "₹ crore"),
                                            risk.vulnerableShare.map(DisclosureFormat.percent) ?? "—",
                                            DisclosureFormat.value(risk.grossLossCrore, unit: "₹ crore")]
                                       }))
            for paragraph in physicalRiskParagraphs { document.paragraph(paragraph) }
        }

        document.heading("Risk management")
        narrative(&document, "s2.rm.process", engagement)

        document.heading("Metrics and targets")
        let ghgIDs = [MetricID.scope1, MetricID.scope2, "ghg.scope2Market", MetricID.scope3, MetricID.scope12,
                      MetricID.ghgIntensityPPP, "ghg.intensityRevenue", "ghg.scope3Categories"]
        document.table(metricTable("Greenhouse gas emissions", ghgIDs.compactMap(MetricCatalog.metric), engagement: engagement,
                                   values: values, referenceColumn: { $0.ifrs?.reference ?? ($0.brsr?.reference ?? "") }))
        narrative(&document, "s2.mt.ghg", engagement)
        document.table(metricTable("Cross-industry metrics", MetricCatalog.metrics(in: .climateRisk), engagement: engagement,
                                   values: values, referenceColumn: { $0.ifrs?.reference ?? "" }))
        narrative(&document, "s2.mt.metrics", engagement)
        narrative(&document, "s2.mt.industry", engagement)
        narrative(&document, "s2.mt.targets", engagement)

        document.heading("Index to IFRS S2")
        document.table(ReportTable(caption: "", columns: ["Requirement", "Reference", "Status"],
                                   rows: NarrativeCatalog.requirements(for: .ifrsS2).map { requirement in
                                       let entry = engagement.narrative(requirement.id)
                                       return [requirement.title, requirement.reference,
                                               entry.notApplicable ? "Not applicable" : entry.hasText ? entry.status.title : "Not written"]
                                   }))
        return document
    }

    // MARK: Audit trail

    private static func auditTrail(_ engagement: DisclosureEngagement, generatedAt: Date) -> ReportDocument {
        var document = ReportDocument(title: "Audit Trail — \(engagement.companyName)", subtitle: subtitle(engagement, generatedAt: generatedAt))
        let rows = engagement.activity.reversed().map { event in
            [DisclosureFormat.dateTime(event.date), event.user, event.action, event.target, event.detail]
        }
        document.table(ReportTable(caption: "\(engagement.activity.count) events, newest first",
                                   columns: ["When", "Who", "Action", "Item", "Detail"], rows: Array(rows)))
        return document
    }

    /// Essential indicators before leadership ones, then catalog order.
    private static func sectionCOrder(_ definition: MetricDefinition) -> (Int, Int) {
        (definition.brsr?.level == .leadership ? 1 : 0, MetricCatalog.position(of: definition.id))
    }

    static func implicationText(_ issue: MaterialIssue) -> String {
        let parts = issue.implication == .notAssessed ? [issue.financialNote] : [issue.implication.title, issue.financialNote]
        return parts.filter { !$0.isEmpty }.joined(separator: ": ")
    }

    static func sortedIssues(_ issues: [MaterialIssue]) -> [MaterialIssue] {
        issues.sorted { ($1.score, $0.title) < ($0.score, $1.title) }
    }
}
