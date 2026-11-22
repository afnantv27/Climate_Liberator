import Foundation

/// Where an attention item sends the user.
nonisolated enum HomeDestination: Hashable, Sendable {
    case engagement(UUID)
    case client(UUID)
    case reductionPlan(UUID)
}

nonisolated struct AttentionItem: Identifiable, Hashable, Sendable {
    enum Severity: Int, Comparable, Sendable {
        case urgent = 0, warning, info
        static func < (a: Severity, b: Severity) -> Bool { a.rawValue < b.rawValue }
    }

    let id: String
    let severity: Severity
    let title: String
    let detail: String
    let destination: HomeDestination
}

/// Everything Home shows, computed from the other modules' data in one pass.
nonisolated struct HomeSummary: Sendable {
    var clientCount = 0
    var clusterCount = 0
    var siteCount = 0
    var sitesWithoutCoordinates = 0
    var activeEngagements = 0
    var signedOffEngagements = 0
    var itemsAwaitingReview = 0
    var targetCount = 0
    var targetsOffTrack = 0
    var inventoryCount = 0
    var attention: [AttentionItem] = []

    /// Deadlines closer than this (days) are flagged.
    static let deadlineWindowDays = 45

    static func build(clients: [Client], engagements: [DisclosureEngagement], plans: [ReductionPlan],
                      inventoryCount: Int, today: Date = Date()) -> HomeSummary {
        var summary = HomeSummary()
        summary.clientCount = clients.count
        summary.clusterCount = Set(clients.map { $0.clusterName.lowercased() }.filter { !$0.isEmpty }).count
        summary.siteCount = clients.reduce(0) { $0 + $1.sites.count }
        summary.sitesWithoutCoordinates = clients.reduce(0) { $0 + $1.sites.filter { !$0.hasCoordinates }.count }
        summary.inventoryCount = inventoryCount

        var items: [AttentionItem] = []
        for engagement in engagements {
            if engagement.isLocked { summary.signedOffEngagements += 1; continue }
            summary.activeEngagements += 1
            let waiting = engagement.metrics.values.filter { $0.status == .readyForReview }.count
                + engagement.narratives.values.filter { $0.status == .readyForReview }.count
            summary.itemsAwaitingReview += waiting
            items += engagementItems(engagement, waiting: waiting, today: today)
        }

        let names = Dictionary(clients.map { ($0.id, $0.displayName) }, uniquingKeysWith: { first, _ in first })
        for plan in plans where !plan.targets.isEmpty {
            let history = DisclosurePerformanceSource.history(for: plan.id, engagements: engagements)
            for target in plan.targets {
                summary.targetCount += 1
                let assessment = TargetAssessor.assess(target, history: history)
                guard assessment.status == .offTrack else { continue }
                summary.targetsOffTrack += 1
                let name = names[plan.id] ?? plan.clientName
                items.append(AttentionItem(id: "target.\(target.id)", severity: .warning,
                                           title: "\(name): off track for \(target.displayName)",
                                           detail: assessment.gapAtLatest.map { "\(DisplayFormat.number($0)) above the target line" } ?? "",
                                           destination: .reductionPlan(plan.id)))
            }
        }

        for client in clients {
            let missing = client.sites.filter { !$0.hasCoordinates }.count
            if client.sites.isEmpty {
                items.append(AttentionItem(id: "sites.\(client.id)", severity: .info, title: "\(client.displayName): no sites",
                                           detail: "Add sites with coordinates to check climate risks.", destination: .client(client.id)))
            } else if missing > 0 {
                items.append(AttentionItem(id: "coords.\(client.id)", severity: .info,
                                           title: "\(client.displayName): \(missing) site(s) without coordinates",
                                           detail: "Coordinates are needed to check climate risks.", destination: .client(client.id)))
            }
        }

        summary.attention = items.sorted { ($0.severity, $0.title) < ($1.severity, $1.title) }
        return summary
    }

    private static func engagementItems(_ engagement: DisclosureEngagement, waiting: Int, today: Date) -> [AttentionItem] {
        var items: [AttentionItem] = []
        let name = engagement.displayName
        if let deadline = engagement.filingDeadline {
            let calendar = Calendar.current
            let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: today),
                                               to: calendar.startOfDay(for: deadline)).day ?? 0
            if days < 0 {
                items.append(AttentionItem(id: "deadline.\(engagement.id)", severity: .urgent, title: "\(name): filing date passed",
                                           detail: "\(-days) day(s) ago, not signed off.", destination: .engagement(engagement.id)))
            } else if days <= deadlineWindowDays {
                let readiness = ReadinessAnalyzer.analyze(engagement).overallAnswered
                items.append(AttentionItem(id: "deadline.\(engagement.id)", severity: days <= 14 ? .urgent : .warning,
                                           title: "\(name): \(days) day(s) to filing",
                                           detail: "\(DisplayFormat.percent(readiness)) of data entered.",
                                           destination: .engagement(engagement.id)))
            }
        }
        let blockers = DataQualityChecks.run(engagement, today: today).filter { $0.severity == .blocker }.count
        if blockers > 0 {
            items.append(AttentionItem(id: "blockers.\(engagement.id)", severity: .warning, title: "\(name): \(blockers) blocker(s)",
                                       detail: "Must be fixed before sign-off.", destination: .engagement(engagement.id)))
        }
        if waiting > 0 {
            items.append(AttentionItem(id: "review.\(engagement.id)", severity: .info, title: "\(name): \(waiting) item(s) to review",
                                       detail: "Submitted and waiting for a reviewer.", destination: .engagement(engagement.id)))
        }
        return items
    }
}
