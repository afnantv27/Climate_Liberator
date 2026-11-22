import Foundation

/// Review actions a user can take on a data point or narrative.
nonisolated enum ReviewAction: String, Sendable {
    case start, submit, approve, requestChanges, reopen

    var title: String {
        switch self {
        case .start: return "Start"
        case .submit: return "Submit for Review"
        case .approve: return "Approve"
        case .requestChanges: return "Request Changes"
        case .reopen: return "Reopen"
        }
    }
    var systemImage: String {
        switch self {
        case .start: return "play.circle"
        case .submit: return "paperplane"
        case .approve: return "checkmark.seal"
        case .requestChanges: return "arrow.uturn.backward"
        case .reopen: return "lock.open"
        }
    }
}

/// The review workflow: which actions are allowed from which status, and what
/// blocks the final sign-off.
nonisolated enum WorkflowEngine {

    static func actions(from status: WorkflowStatus) -> [ReviewAction] {
        switch status {
        case .notStarted: return [.start, .submit]
        case .inProgress: return [.submit]
        case .readyForReview: return [.approve, .requestChanges]
        case .changesRequested: return [.submit]
        case .approved: return [.reopen]
        }
    }

    static func status(after action: ReviewAction) -> WorkflowStatus {
        switch action {
        case .start, .reopen: return .inProgress
        case .submit: return .readyForReview
        case .approve: return .approved
        case .requestChanges: return .changesRequested
        }
    }

    /// Whether `action` is allowed now. Submitting needs an answer.
    static func canApply(_ action: ReviewAction, status: WorkflowStatus, isAnswered: Bool) -> Bool {
        guard actions(from: status).contains(action) else { return false }
        return action != .submit || isAnswered
    }

    /// Status after a content edit: editing approved or returned work sends it back to In Progress.
    static func statusAfterEdit(_ status: WorkflowStatus) -> WorkflowStatus {
        switch status {
        case .notStarted, .approved, .changesRequested: return .inProgress
        case .inProgress, .readyForReview: return status
        }
    }

    /// Reasons the engagement cannot be signed off yet; empty when it can.
    static func signOffBlockers(_ engagement: DisclosureEngagement, issues: [QualityIssue]) -> [String] {
        var reasons: [String] = []
        let blockers = issues.filter { $0.severity == .blocker }
        if !blockers.isEmpty {
            reasons.append("\(blockers.count) blocking issue\(blockers.count == 1 ? "" : "s") in Data Checks.")
        }
        let scope = engagement.frameworks
        let unapprovedMetrics = MetricCatalog.requiredInputs(for: scope).filter { engagement.metric($0.id).status != .approved }
        if !unapprovedMetrics.isEmpty {
            reasons.append("\(unapprovedMetrics.count) required data point\(unapprovedMetrics.count == 1 ? " is" : "s are") not approved.")
        }
        let unapprovedNarratives = NarrativeCatalog.required(in: scope).filter { engagement.narrative($0.id).status != .approved }
        if !unapprovedNarratives.isEmpty {
            reasons.append("\(unapprovedNarratives.count) required narrative\(unapprovedNarratives.count == 1 ? " is" : "s are") not approved.")
        }
        if engagement.team.approver.trimmingCharacters(in: .whitespaces).isEmpty {
            reasons.append("No approver named in Company & Scope → Team.")
        }
        return reasons
    }
}

/// Starts next year's engagement from this one.
nonisolated enum RollForward {
    static func nextYear(from engagement: DisclosureEngagement, user: String, now: Date = Date()) -> DisclosureEngagement {
        var next = DisclosureEngagement(fiscalYearStart: engagement.fiscalYearStart + 1)
        next.profile = engagement.profile
        next.frameworks = engagement.frameworks
        next.boundary = engagement.boundary
        next.team = engagement.team
        next.governance = engagement.governance
        next.policies = engagement.policies
        next.issues = engagement.issues
        next.isExample = engagement.isExample
        next.createdAt = now
        next.updatedAt = now

        // This year's values become next year's comparatives; method, source and owner carry over.
        for definition in MetricCatalog.all where !definition.isCalculated {
            let old = engagement.metric(definition.id)
            guard old.hasValue || old.notApplicable || !old.method.isEmpty || !old.source.isEmpty else { continue }
            var entry = MetricEntry()
            entry.prior = old.notApplicable ? nil : old.current
            if definition.isText { entry.text = old.text }
            entry.source = old.source
            entry.method = old.method
            entry.owner = old.owner
            entry.origin = .rolledForward
            entry.originNote = "Rolled forward from \(engagement.periodLabel)"
            next.metrics[definition.id] = entry
        }
        // Narratives keep last year's text as a starting draft.
        for (id, old) in engagement.narratives where old.hasText {
            var entry = NarrativeEntry()
            entry.text = old.text
            entry.owner = old.owner
            entry.status = .inProgress
            next.narratives[id] = entry
        }
        next.appendActivity(ActivityEvent(date: now, user: user, action: "Created by roll-forward",
                                          target: engagement.periodLabel,
                                          detail: "Values became prior-year figures; narratives kept as drafts."))
        return next
    }
}
