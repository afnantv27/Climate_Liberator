import Foundation

/// How far one framework's required content has got.
nonisolated struct FrameworkReadiness: Identifiable, Sendable {
    let framework: DisclosureFramework
    let total: Int
    let answered: Int
    let approved: Int
    let dataPoints: Int
    let dataPointsAnswered: Int
    let narratives: Int
    let narrativesAnswered: Int

    var id: String { framework.rawValue }
    var answeredShare: Double { total > 0 ? Double(answered) / Double(total) : 0 }
    var approvedShare: Double { total > 0 ? Double(approved) / Double(total) : 0 }
}

/// Assurance-readiness of one BRSR Core input: what an assessor or assurer will check.
nonisolated struct CoreAssuranceRow: Identifiable, Sendable {
    let metricID: String
    let hasValue: Bool
    let hasPrior: Bool
    let hasMethod: Bool
    let hasEvidence: Bool
    let isApproved: Bool

    var id: String { metricID }
    var checksPassed: Int { [hasValue, hasPrior, hasMethod, hasEvidence, isApproved].filter { $0 }.count }
    static let checkCount = 5
    var isReady: Bool { checksPassed == Self.checkCount }
}

nonisolated struct EngagementReadiness: Sendable {
    let frameworks: [FrameworkReadiness]
    let coreRows: [CoreAssuranceRow]
    /// Workflow status of every required item in scope.
    let statusCounts: [WorkflowStatus: Int]
    let totalItems: Int

    var overallAnswered: Double {
        let total = frameworks.reduce(0) { $0 + $1.total }
        return total > 0 ? Double(frameworks.reduce(0) { $0 + $1.answered }) / Double(total) : 0
    }
    var overallApproved: Double {
        let total = frameworks.reduce(0) { $0 + $1.total }
        return total > 0 ? Double(frameworks.reduce(0) { $0 + $1.approved }) / Double(total) : 0
    }
    var coreAssuranceScore: Double {
        guard !coreRows.isEmpty else { return 0 }
        let passed = coreRows.reduce(0) { $0 + $1.checksPassed }
        return Double(passed) / Double(coreRows.count * CoreAssuranceRow.checkCount)
    }
    func readiness(_ framework: DisclosureFramework) -> FrameworkReadiness? { frameworks.first { $0.framework == framework } }
}

/// Completeness, approval and assurance-readiness of an engagement.
nonisolated enum ReadinessAnalyzer {

    static func analyze(_ engagement: DisclosureEngagement) -> EngagementReadiness {
        let scope = engagement.frameworks
        let frameworks = DisclosureFramework.allCases.filter(scope.contains).map { framework in
            readiness(of: framework, in: engagement)
        }

        var counts: [WorkflowStatus: Int] = [:]
        let inputs = MetricCatalog.requiredInputs(for: scope)
        for definition in inputs { counts[engagement.metric(definition.id).status, default: 0] += 1 }
        let narratives = NarrativeCatalog.required(in: scope)
        for requirement in narratives { counts[engagement.narrative(requirement.id).status, default: 0] += 1 }

        let coreRows: [CoreAssuranceRow]
        if scope.contains(.brsrCore) {
            coreRows = MetricCatalog.requiredInputs(for: .brsrCore).map { coreRow($0, in: engagement) }
        } else {
            coreRows = []
        }
        return EngagementReadiness(frameworks: frameworks, coreRows: coreRows, statusCounts: counts,
                                   totalItems: inputs.count + narratives.count)
    }

    static func readiness(of framework: DisclosureFramework, in engagement: DisclosureEngagement) -> FrameworkReadiness {
        let inputs = MetricCatalog.requiredInputs(for: framework)
        let entries = inputs.map { engagement.metric($0.id) }
        let narratives = NarrativeCatalog.required(in: [framework]).map { engagement.narrative($0.id) }

        var total = entries.count + narratives.count
        var answered = entries.filter(\.isAnswered).count + narratives.filter(\.isAnswered).count
        var approved = entries.filter { $0.status == .approved }.count + narratives.filter { $0.status == .approved }.count

        // BRSR also needs the company profile, the material-issue register and the Section B policy matrix.
        if framework == .brsr {
            let extras = [profileComplete(engagement.profile), !engagement.issues.isEmpty,
                          engagement.policies.allSatisfy(\.isComplete)]
            total += extras.count
            answered += extras.filter { $0 }.count
            approved += engagement.isLocked ? extras.filter { $0 }.count : 0
        }
        return FrameworkReadiness(framework: framework, total: total, answered: answered, approved: approved,
                                  dataPoints: entries.count, dataPointsAnswered: entries.filter(\.isAnswered).count,
                                  narratives: narratives.count, narrativesAnswered: narratives.filter(\.isAnswered).count)
    }

    static func coreRow(_ definition: MetricDefinition, in engagement: DisclosureEngagement) -> CoreAssuranceRow {
        let entry = engagement.metric(definition.id)
        let hasMethod = !entry.method.trimmingCharacters(in: .whitespaces).isEmpty
            || !entry.source.trimmingCharacters(in: .whitespaces).isEmpty
        return CoreAssuranceRow(metricID: definition.id,
                                hasValue: entry.isAnswered,
                                hasPrior: entry.prior != nil || entry.notApplicable,
                                hasMethod: hasMethod,
                                hasEvidence: !entry.evidenceIDs.isEmpty,
                                isApproved: entry.status == .approved)
    }

    /// Section A identity fields a filing cannot go without.
    static func profileComplete(_ profile: CompanyProfile) -> Bool {
        [profile.legalName, profile.cin, profile.registeredAddress, profile.email, profile.contactName]
            .allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    /// Completion of one metric group for the frameworks in scope.
    static func groupProgress(_ group: MetricGroup, in engagement: DisclosureEngagement) -> (answered: Int, total: Int) {
        let inputs = MetricCatalog.requiredInputs(for: engagement.frameworks).filter { $0.group == group }
        return (inputs.filter { engagement.metric($0.id).isAnswered }.count, inputs.count)
    }
}
