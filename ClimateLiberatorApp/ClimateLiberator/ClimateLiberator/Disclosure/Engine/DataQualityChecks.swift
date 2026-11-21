import Foundation

nonisolated enum IssueSeverity: Int, Comparable, CaseIterable, Sendable {
    /// Must be fixed before sign-off.
    case blocker = 0
    /// Likely to be questioned by a reviewer or assurer.
    case warning
    /// Worth a look.
    case info

    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    var title: String {
        switch self {
        case .blocker: return "Blocker"
        case .warning: return "Warning"
        case .info: return "Note"
        }
    }
}

/// Where the user goes to fix an issue.
nonisolated enum IssueArea: String, Sendable {
    case setup, data, narratives, risks, policies, evidence, review
}

nonisolated struct QualityIssue: Identifiable, Hashable, Sendable {
    let id: String
    let severity: IssueSeverity
    let area: IssueArea
    /// Metric, narrative or group id the issue points at, for navigation.
    let target: String?
    let title: String
    let detail: String
}

/// Checks a reviewer or assurance provider would run before accepting the numbers.
nonisolated enum DataQualityChecks {
    /// Year-on-year movement above this needs an explanation.
    static let varianceThreshold = 0.30

    static func run(_ engagement: DisclosureEngagement, resolved: MetricResolver? = nil,
                    today: Date = Date(),
                    fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }) -> [QualityIssue] {
        let values = resolved ?? MetricResolver(engagement)
        let scope = engagement.frameworks
        var issues: [QualityIssue] = []

        // Setup
        if scope.isEmpty {
            issues.append(QualityIssue(id: "setup.frameworks", severity: .blocker, area: .setup, target: nil,
                                       title: "No framework selected", detail: "Choose BRSR, BRSR Core or IFRS S2 in Company & Scope."))
        }
        if scope.contains(.brsr), !ReadinessAnalyzer.profileComplete(engagement.profile) {
            issues.append(QualityIssue(id: "setup.profile", severity: .blocker, area: .setup, target: nil,
                                       title: "Company details incomplete",
                                       detail: "BRSR Section A needs the legal name, CIN, registered address, e-mail and a contact person."))
        }

        // Missing required data, one issue per group.
        let inputs = MetricCatalog.requiredInputs(for: scope)
        for group in MetricGroup.allCases {
            let missing = inputs.filter { $0.group == group && !engagement.metric($0.id).isAnswered }
            guard !missing.isEmpty else { continue }
            let isCore = scope.contains(.brsrCore) && missing.contains { $0.core != nil }
            issues.append(QualityIssue(id: "missing.\(group.rawValue)", severity: isCore ? .blocker : .warning, area: .data,
                                       target: group.rawValue,
                                       title: "\(missing.count) required data point\(missing.count == 1 ? "" : "s") missing in \(group.title)",
                                       detail: missing.prefix(3).map(\.title).joined(separator: "; ") + (missing.count > 3 ? "; …" : "")))
        }

        // Value checks on every answered input.
        var unexplained: [MetricDefinition] = []
        for definition in MetricCatalog.all where !definition.isCalculated && !definition.isText {
            let entry = engagement.metric(definition.id)
            guard !entry.notApplicable else { continue }
            for (label, value) in [("current", entry.current), ("prior-year", entry.prior)] {
                guard let value else { continue }
                if value < 0 && !definition.allowsNegative {
                    issues.append(QualityIssue(id: "negative.\(definition.id).\(label)", severity: .blocker, area: .data,
                                               target: definition.id, title: "Negative \(label) value: \(definition.title)",
                                               detail: "This KPI cannot be negative."))
                }
                if definition.kind == .percent, value > 100 {
                    issues.append(QualityIssue(id: "percent.\(definition.id).\(label)", severity: .blocker, area: .data,
                                               target: definition.id, title: "Share above 100%: \(definition.title)",
                                               detail: "Enter a percentage between 0 and 100."))
                }
            }
            if let ratio = DisclosureFormat.changeRatio(current: entry.current, prior: entry.prior),
               abs(ratio) > varianceThreshold,
               entry.varianceExplanation.trimmingCharacters(in: .whitespaces).isEmpty {
                unexplained.append(definition)
            }
        }
        for definition in unexplained {
            let change = DisclosureFormat.change(current: engagement.metric(definition.id).current,
                                                 prior: engagement.metric(definition.id).prior) ?? ""
            issues.append(QualityIssue(id: "variance.\(definition.id)", severity: .warning, area: .data, target: definition.id,
                                       title: "\(change) year on year, no explanation: \(definition.title)",
                                       detail: "Movements above \(DisclosureFormat.percent(varianceThreshold)) need a reason for reviewers and assurers."))
        }

        // Cross-checks between related KPIs.
        if let consumption = values.current(MetricID.waterConsumption),
           let withdrawal = values.current(MetricID.waterWithdrawal), consumption > withdrawal * 1.001 {
            issues.append(QualityIssue(id: "consistency.water", severity: .warning, area: .data, target: MetricID.waterConsumption,
                                       title: "Water consumed exceeds water withdrawn",
                                       detail: "Consumption \(DisclosureFormat.number(consumption)) kL is above withdrawal \(DisclosureFormat.number(withdrawal)) kL."))
        }
        if let total = values.current(MetricID.wasteTotal), total > 0 {
            let handled = (values.current(MetricID.wasteRecovered) ?? 0) + (values.current(MetricID.wasteDisposed) ?? 0)
            if handled > total * 1.05 {
                issues.append(QualityIssue(id: "consistency.waste", severity: .warning, area: .data, target: MetricID.wasteTotal,
                                           title: "More waste recovered and disposed than generated",
                                           detail: "\(DisclosureFormat.number(handled)) t handled vs \(DisclosureFormat.number(total)) t generated. Stored waste from earlier years should be explained."))
            }
        }
        let electricity = (values.current(MetricID.electricityNonRenewable) ?? 0) + (values.current(MetricID.electricityRenewable) ?? 0)
        let scope2 = values.current(MetricID.scope2)
        if let scope2, scope2 > 0, electricity == 0, engagement.metric(MetricID.electricityNonRenewable).isAnswered {
            issues.append(QualityIssue(id: "consistency.scope2", severity: .warning, area: .data, target: MetricID.scope2,
                                       title: "Scope 2 reported but no electricity in energy",
                                       detail: "Scope 2 comes from purchased electricity, heat or steam; check the energy table."))
        }
        if (values.current(MetricID.electricityNonRenewable) ?? 0) > 0, scope2 == nil || scope2 == 0,
           !engagement.metric(MetricID.scope2).notApplicable, scope.contains(.brsr) || scope.contains(.ifrsS2) {
            issues.append(QualityIssue(id: "consistency.electricity", severity: .warning, area: .data, target: MetricID.scope2,
                                       title: "Non-renewable electricity used but no Scope 2",
                                       detail: "Grid electricity normally produces Scope 2 emissions. Calculate them in GHG Accounting or enter them."))
        }
        if values.current(MetricID.ghgIntensityPPP) == nil, values.current(MetricID.scope12) != nil, scope.contains(.brsrCore) {
            issues.append(QualityIssue(id: "intensity.ppp", severity: .warning, area: .data, target: MetricID.pppRate,
                                       title: "PPP-adjusted intensities cannot be calculated",
                                       detail: "Enter revenue from operations and the PPP conversion factor."))
        }

        // Evidence and method for BRSR Core.
        if scope.contains(.brsrCore) {
            let rows = MetricCatalog.requiredInputs(for: .brsrCore).map { ReadinessAnalyzer.coreRow($0, in: engagement) }
            let noEvidence = rows.filter { $0.hasValue && !$0.hasEvidence }
            if !noEvidence.isEmpty {
                issues.append(QualityIssue(id: "core.evidence", severity: .warning, area: .evidence, target: nil,
                                           title: "\(noEvidence.count) BRSR Core value\(noEvidence.count == 1 ? "" : "s") without evidence",
                                           detail: "Assessors and assurers ask for source documents for every Core KPI."))
            }
            let noMethod = rows.filter { $0.hasValue && !$0.hasMethod }
            if !noMethod.isEmpty {
                issues.append(QualityIssue(id: "core.method", severity: .info, area: .data, target: nil,
                                           title: "\(noMethod.count) BRSR Core value\(noMethod.count == 1 ? "" : "s") without source or method",
                                           detail: "Record the system or document and the calculation method."))
            }
            let noPrior = rows.filter { $0.hasValue && !$0.hasPrior }
            if !noPrior.isEmpty {
                issues.append(QualityIssue(id: "core.prior", severity: .info, area: .data, target: nil,
                                           title: "\(noPrior.count) BRSR Core value\(noPrior.count == 1 ? "" : "s") without a prior-year figure",
                                           detail: "BRSR shows the current and previous financial year side by side."))
            }
        }
        let missingFiles = engagement.evidence.filter { !$0.location.isEmpty && !$0.isWebLink && !fileExists($0.location) }
        if !missingFiles.isEmpty {
            issues.append(QualityIssue(id: "evidence.missing", severity: .warning, area: .evidence, target: nil,
                                       title: "\(missingFiles.count) evidence file\(missingFiles.count == 1 ? "" : "s") not found",
                                       detail: missingFiles.prefix(3).map(\.title).joined(separator: "; ")))
        }

        // Narratives, register and policies.
        let emptyNarratives = NarrativeCatalog.required(in: scope).filter { !engagement.narrative($0.id).isAnswered }
        for framework in [DisclosureFramework.ifrsS2, .brsr] where scope.contains(framework) {
            let missing = emptyNarratives.filter { $0.framework == framework }
            guard !missing.isEmpty else { continue }
            issues.append(QualityIssue(id: "narratives.\(framework.rawValue)", severity: .warning, area: .narratives, target: missing.first?.id,
                                       title: "\(missing.count) \(framework.title) narrative\(missing.count == 1 ? "" : "s") not written",
                                       detail: missing.prefix(3).map(\.title).joined(separator: "; ")))
        }
        if (scope.contains(.brsr) || scope.contains(.ifrsS2)), engagement.issues.isEmpty {
            issues.append(QualityIssue(id: "risks.empty", severity: .warning, area: .risks, target: nil,
                                       title: "No material issues recorded",
                                       detail: "BRSR Section A and IFRS S2 Strategy both need the material risks and opportunities."))
        }
        if scope.contains(.ifrsS2), !engagement.issues.contains(where: { $0.topic.isClimate }) {
            issues.append(QualityIssue(id: "risks.climate", severity: .warning, area: .risks, target: nil,
                                       title: "No climate-related risk or opportunity",
                                       detail: "IFRS S2 needs each material climate-related risk and opportunity described."))
        }
        let openPolicies = engagement.policies.filter { !$0.isComplete }
        if scope.contains(.brsr), !openPolicies.isEmpty {
            issues.append(QualityIssue(id: "policies.open", severity: .warning, area: .policies, target: nil,
                                       title: "Section B incomplete for \(openPolicies.count) principle\(openPolicies.count == 1 ? "" : "s")",
                                       detail: openPolicies.map { "P\($0.principle)" }.joined(separator: ", ")))
        }
        if scope.contains(.ifrsS2), engagement.metric(MetricID.scope3).current == nil, !engagement.metric(MetricID.scope3).notApplicable {
            issues.append(QualityIssue(id: "ifrs.scope3", severity: .info, area: .data, target: MetricID.scope3,
                                       title: "No Scope 3 figure",
                                       detail: "IFRS S2 lets a company omit Scope 3 in its first reporting year; say so in the basis of preparation."))
        }

        // Workflow
        let selfApproved = MetricCatalog.all.filter { definition in
            let entry = engagement.metric(definition.id)
            return entry.status == .approved && !entry.approvedBy.isEmpty
                && entry.approvedBy.caseInsensitiveCompare(entry.updatedBy) == .orderedSame
        }
        if !selfApproved.isEmpty {
            issues.append(QualityIssue(id: "workflow.segregation", severity: .info, area: .review, target: nil,
                                       title: "\(selfApproved.count) item\(selfApproved.count == 1 ? "" : "s") approved by the person who last edited \(selfApproved.count == 1 ? "it" : "them")",
                                       detail: "Assurers look for a separate preparer and reviewer."))
        }
        if let deadline = engagement.filingDeadline, !engagement.isLocked {
            let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: today),
                                                       to: Calendar.current.startOfDay(for: deadline)).day ?? 0
            let readiness = ReadinessAnalyzer.analyze(engagement).overallAnswered
            if days < 0 {
                issues.append(QualityIssue(id: "deadline.passed", severity: .blocker, area: .review, target: nil,
                                           title: "Filing date passed \(-days) day\(days == -1 ? "" : "s") ago",
                                           detail: "The engagement is not signed off."))
            } else if days <= 30, readiness < 0.8 {
                issues.append(QualityIssue(id: "deadline.near", severity: .warning, area: .review, target: nil,
                                           title: "\(days) day\(days == 1 ? "" : "s") to filing, \(DisclosureFormat.percent(readiness)) complete",
                                           detail: "Prioritise blockers and BRSR Core KPIs."))
            }
        }
        return issues.sorted { ($0.severity, $0.area.rawValue, $0.title) < ($1.severity, $1.area.rawValue, $1.title) }
    }
}
