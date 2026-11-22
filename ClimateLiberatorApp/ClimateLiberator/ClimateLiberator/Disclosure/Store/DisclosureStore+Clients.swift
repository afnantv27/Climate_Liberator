import Foundation

extension DisclosureStore {
    /// Links an engagement to a client in the Clients register, or unlinks it (nil).
    /// Allowed after sign-off: it files the engagement, it does not change figures.
    func setClient(_ clientID: UUID?, clientName: String, for engagementID: UUID) {
        guard let current = engagement(engagementID), current.clientID != clientID else { return }
        let user = userName
        mutate(engagementID, allowWhenLocked: true) { engagement in
            engagement.clientID = clientID
            engagement.appendActivity(ActivityEvent(user: user, action: clientID == nil ? "Unlinked from client" : "Linked to client",
                                                    target: clientName))
        }
    }

    func engagements(forClient clientID: UUID) -> [DisclosureEngagement] {
        engagements.filter { $0.clientID == clientID }.sorted { $0.fiscalYearStart > $1.fiscalYearStart }
    }

    var unlinkedEngagements: [DisclosureEngagement] {
        engagements.filter { $0.clientID == nil }
    }
}
