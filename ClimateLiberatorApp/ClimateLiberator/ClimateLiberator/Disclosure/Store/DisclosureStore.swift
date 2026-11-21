import Foundation
import AppKit
import Combine

/// Client engagements (one JSON file each), their edits, review workflow, audit trail
/// and exports.
///
/// Nothing is written to disk without the user asking: new engagements, the example
/// and every edit stay in memory, marked unsaved, until the user saves (⌘S) or
/// confirms saving when the app quits. A signed-off engagement is read-only until
/// it is reopened.
@MainActor
final class DisclosureStore: ObservableObject {
    @Published private(set) var engagements: [DisclosureEngagement] = []
    @Published var selectedID: UUID?
    @Published var statusMessage = ""
    @Published private(set) var unsavedIDs: Set<UUID> = []

    let locations: DisclosureDataLocations
    private let persists: Bool
    private var savedIDs: Set<UUID> = []

    /// The app's store, consulted before quitting. Tests create their own stores.
    static weak var active: DisclosureStore?
    static let userNameKey = "disclosure.userName"
    /// Edits by the same person to the same item within this window form one audit event.
    static let coalesceInterval: TimeInterval = 120

    init(locations: DisclosureDataLocations = .current, loadFromDisk: Bool = true) {
        self.locations = locations
        self.persists = loadFromDisk
        if loadFromDisk {
            load()
            if Self.active == nil { Self.active = self }
        }
        selectedID = engagements.first?.id
    }

    // MARK: Lookup

    var selected: DisclosureEngagement? { selectedID.flatMap(engagement) }
    func engagement(_ id: UUID) -> DisclosureEngagement? { engagements.first { $0.id == id } }
    var hasUnsavedChanges: Bool { !unsavedIDs.isEmpty }
    var unsavedEngagements: [DisclosureEngagement] { engagements.filter { unsavedIDs.contains($0.id) } }
    func isUnsaved(_ id: UUID) -> Bool { unsavedIDs.contains(id) }
    func isOnDisk(_ id: UUID) -> Bool { savedIDs.contains(id) }

    /// Name recorded in the audit trail and on approvals.
    var userName: String {
        let saved = UserDefaults.standard.string(forKey: Self.userNameKey)?.trimmingCharacters(in: .whitespaces) ?? ""
        if !saved.isEmpty { return saved }
        let full = NSFullUserName()
        return full.isEmpty ? "Unknown user" : full
    }

    func setUserName(_ name: String) {
        UserDefaults.standard.set(name.trimmingCharacters(in: .whitespaces), forKey: Self.userNameKey)
        objectWillChange.send()
    }

    // MARK: Lifecycle

    @discardableResult
    func createEngagement(companyName: String, fiscalYearStart: Int, frameworks: Set<DisclosureFramework>,
                          isListed: Bool, marketCapRank: Int?, sector: IndustrySector) -> DisclosureEngagement {
        var engagement = DisclosureEngagement(fiscalYearStart: fiscalYearStart)
        engagement.profile.legalName = companyName.trimmingCharacters(in: .whitespaces)
        engagement.profile.isListed = isListed
        engagement.profile.marketCapRank = marketCapRank
        engagement.profile.sector = sector
        engagement.frameworks = frameworks
        engagement.team.preparer = userName
        engagement.appendActivity(ActivityEvent(user: userName, action: "Created engagement", target: engagement.periodLabel,
                                                detail: frameworks.map(\.title).sorted().joined(separator: ", ")))
        insert(engagement)
        statusMessage = "Created \(engagement.displayName). It is not saved until you choose Save (⌘S)."
        return engagement
    }

    func loadExample() {
        var example = DisclosureExample.engagement(user: userName)
        example.id = UUID()
        insert(example)
        statusMessage = "Loaded an illustrative example company (not saved). All its figures are invented."
    }

    /// Starts next financial year from the selected engagement.
    func rollForward(id: UUID) {
        guard let source = engagement(id) else { return }
        let next = RollForward.nextYear(from: source, user: userName)
        insert(next)
        statusMessage = "Created \(next.displayName) from \(source.periodLabel): values became prior-year figures. Not saved yet."
    }

    private func insert(_ engagement: DisclosureEngagement) {
        engagements.insert(engagement, at: 0)
        selectedID = engagement.id
        unsavedIDs.insert(engagement.id)
    }

    /// A saved file goes to the Trash so it can be recovered; an unsaved engagement is discarded.
    func deleteEngagement(id: UUID) {
        guard let engagement = engagement(id) else { return }
        let wasOnDisk = savedIDs.contains(id)
        unsavedIDs.remove(id)
        savedIDs.remove(id)
        engagements.removeAll { $0.id == id }
        if persists, wasOnDisk {
            try? FileManager.default.trashItem(at: locations.engagementFile(id), resultingItemURL: nil)
        }
        if selectedID == id { selectedID = engagements.first?.id }
        statusMessage = wasOnDisk ? "Moved \(engagement.displayName) to the Trash." : "Discarded \(engagement.displayName)."
    }

    // MARK: Saving

    @discardableResult
    func save(id: UUID) -> Bool {
        guard let engagement = engagement(id) else { return false }
        guard persists else { unsavedIDs.remove(id); return true }
        do {
            try DisclosureJSON.write(engagement, to: locations.engagementFile(id))
            unsavedIDs.remove(id)
            savedIDs.insert(id)
            statusMessage = "Saved \(engagement.displayName)."
            return true
        } catch {
            statusMessage = "Could not save \(engagement.displayName): \(error.localizedDescription)"
            return false
        }
    }

    @discardableResult
    func saveSelected() -> Bool {
        guard let selectedID else { return false }
        return save(id: selectedID)
    }

    @discardableResult
    func saveAll() -> Bool {
        unsavedIDs.map { save(id: $0) }.allSatisfy { $0 }
    }

    /// Replaces in-memory changes with the saved file.
    func revert(id: UUID) {
        guard persists, savedIDs.contains(id),
              let saved = try? DisclosureJSON.read(from: locations.engagementFile(id)),
              let index = engagements.firstIndex(where: { $0.id == id }) else { return }
        engagements[index] = saved
        unsavedIDs.remove(id)
        statusMessage = "Reverted \(saved.displayName) to the saved version."
    }

    /// Writes a copy of the engagement for sharing (e.g. consultant ↔ client).
    func exportEngagementFile(id: UUID, to url: URL) {
        guard let engagement = engagement(id) else { return }
        do {
            try DisclosureJSON.write(engagement, to: url)
            statusMessage = "Exported \(engagement.displayName) to \(url.lastPathComponent)."
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
        }
    }

    /// Opens a shared engagement file as a new, unsaved engagement.
    func importEngagementFile(from url: URL) {
        do {
            var engagement = try DisclosureJSON.read(from: url)
            if self.engagement(engagement.id) != nil { engagement.id = UUID() }
            engagement.appendActivity(ActivityEvent(user: userName, action: "Imported engagement file", target: url.lastPathComponent))
            insert(engagement)
            statusMessage = "Imported \(engagement.displayName) (not saved)."
        } catch {
            statusMessage = "Could not read \(url.lastPathComponent): \(error.localizedDescription)"
        }
    }

    // MARK: Editing

    /// Applies a change, stamps it and marks the engagement unsaved. Refused while signed off.
    func mutate(_ id: UUID, allowWhenLocked: Bool = false, _ change: (inout DisclosureEngagement) -> Void) {
        guard let index = engagements.firstIndex(where: { $0.id == id }) else { return }
        if engagements[index].isLocked && !allowWhenLocked {
            statusMessage = "This engagement is signed off. Reopen it in Review & Approval to make changes."
            return
        }
        var engagement = engagements[index]
        change(&engagement)
        engagement.updatedAt = Date()
        engagements[index] = engagement
        unsavedIDs.insert(id)
    }

    /// Adds an audit event; repeated edits of one item by one person within two minutes merge.
    private func log(_ action: String, target: String = "", detail: String = "", coalesce: Bool = false,
                     in engagement: inout DisclosureEngagement) {
        let now = Date()
        if coalesce, let last = engagement.activity.last, last.user == userName, last.action == action, last.target == target,
           now.timeIntervalSince(last.date) < Self.coalesceInterval {
            engagement.activity[engagement.activity.count - 1].date = now
            engagement.activity[engagement.activity.count - 1].detail = detail
            return
        }
        engagement.appendActivity(ActivityEvent(date: now, user: userName, action: action, target: target, detail: detail))
    }

    /// General audited edit of engagement-level fields (profile, team, policies…).
    func edit(_ id: UUID, action: String, target: String = "", _ change: (inout DisclosureEngagement) -> Void) {
        mutate(id) { engagement in
            change(&engagement)
            log(action, target: target, coalesce: true, in: &engagement)
        }
    }

    func updateMetric(_ metricID: String, in id: UUID, _ change: (inout MetricEntry) -> Void) {
        guard let current = engagement(id) else { return }
        let old = current.metric(metricID)
        var entry = old
        change(&entry)
        // Bindings often write back an unchanged value; that is not an edit.
        guard entry != old else { return }
        let title = MetricCatalog.metric(metricID)?.title ?? metricID
        let user = userName
        let valueChanged = old.current != entry.current || old.prior != entry.prior || old.text != entry.text
            || old.notApplicable != entry.notApplicable || old.notApplicableReason != entry.notApplicableReason
        mutate(id) { engagement in
            if valueChanged {
                if old.status == .approved {
                    entry.comments.append(ReviewComment(author: user, text: "Approval withdrawn: value changed after approval.", kind: .reopened))
                    entry.approvedBy = ""
                    entry.approvedAt = nil
                    log("Approval withdrawn", target: title, detail: "Value changed after approval", in: &engagement)
                }
                entry.status = WorkflowEngine.statusAfterEdit(old.status)
            }
            entry.updatedAt = Date()
            entry.updatedBy = user
            engagement.metrics[metricID] = entry
            if valueChanged {
                let unit = MetricCatalog.metric(metricID)?.unit ?? ""
                let detail = entry.notApplicable ? "Not applicable"
                    : MetricCatalog.metric(metricID)?.isText == true ? entry.text
                    : "\(DisclosureFormat.value(entry.current, unit: unit)) (prior \(DisclosureFormat.value(entry.prior, unit: unit)))"
                log("Edited value", target: title, detail: detail, coalesce: true, in: &engagement)
            } else {
                log("Edited details", target: title, coalesce: true, in: &engagement)
            }
        }
    }

    func updateNarrative(_ narrativeID: String, in id: UUID, _ change: (inout NarrativeEntry) -> Void) {
        guard let current = engagement(id) else { return }
        let old = current.narrative(narrativeID)
        var entry = old
        change(&entry)
        guard entry != old else { return }
        let title = NarrativeCatalog.requirement(narrativeID)?.title ?? narrativeID
        let user = userName
        let textChanged = old.text != entry.text || old.notApplicable != entry.notApplicable
        mutate(id) { engagement in
            if textChanged {
                if old.status == .approved {
                    entry.comments.append(ReviewComment(author: user, text: "Approval withdrawn: text changed after approval.", kind: .reopened))
                    entry.approvedBy = ""
                    entry.approvedAt = nil
                    log("Approval withdrawn", target: title, detail: "Text changed after approval", in: &engagement)
                }
                entry.status = WorkflowEngine.statusAfterEdit(old.status)
            }
            entry.updatedAt = Date()
            entry.updatedBy = user
            engagement.narratives[narrativeID] = entry
            log(textChanged ? "Edited narrative" : "Edited narrative details", target: title,
                detail: textChanged ? "\(entry.wordCount) words" : "", coalesce: true, in: &engagement)
        }
    }

    /// Submit, approve, return or reopen a data point. Returns false when not allowed.
    @discardableResult
    func review(_ action: ReviewAction, metric metricID: String, in id: UUID, comment: String = "") -> Bool {
        guard let engagement = engagement(id) else { return false }
        let entry = engagement.metric(metricID)
        guard WorkflowEngine.canApply(action, status: entry.status, isAnswered: entry.isAnswered) else { return false }
        let title = MetricCatalog.metric(metricID)?.title ?? metricID
        let user = userName
        mutate(id) { engagement in
            var updated = engagement.metric(metricID)
            Self.apply(action, user: user, comment: comment, status: &updated.status, approvedBy: &updated.approvedBy,
                       approvedAt: &updated.approvedAt, comments: &updated.comments)
            engagement.metrics[metricID] = updated
            log(action.title, target: title, detail: comment, in: &engagement)
        }
        return true
    }

    @discardableResult
    func review(_ action: ReviewAction, narrative narrativeID: String, in id: UUID, comment: String = "") -> Bool {
        guard let engagement = engagement(id) else { return false }
        let entry = engagement.narrative(narrativeID)
        guard WorkflowEngine.canApply(action, status: entry.status, isAnswered: entry.isAnswered) else { return false }
        let title = NarrativeCatalog.requirement(narrativeID)?.title ?? narrativeID
        let user = userName
        mutate(id) { engagement in
            var updated = engagement.narrative(narrativeID)
            Self.apply(action, user: user, comment: comment, status: &updated.status, approvedBy: &updated.approvedBy,
                       approvedAt: &updated.approvedAt, comments: &updated.comments)
            engagement.narratives[narrativeID] = updated
            log(action.title, target: title, detail: comment, in: &engagement)
        }
        return true
    }

    private static func apply(_ action: ReviewAction, user: String, comment: String, status: inout WorkflowStatus,
                              approvedBy: inout String, approvedAt: inout Date?, comments: inout [ReviewComment]) {
        status = WorkflowEngine.status(after: action)
        switch action {
        case .approve:
            approvedBy = user
            approvedAt = Date()
            comments.append(ReviewComment(author: user, text: comment.isEmpty ? "Approved." : comment, kind: .approval))
        case .requestChanges:
            approvedBy = ""
            approvedAt = nil
            comments.append(ReviewComment(author: user, text: comment.isEmpty ? "Changes requested." : comment, kind: .changeRequest))
        case .reopen:
            approvedBy = ""
            approvedAt = nil
            comments.append(ReviewComment(author: user, text: comment.isEmpty ? "Reopened." : comment, kind: .reopened))
        case .start, .submit:
            if !comment.isEmpty { comments.append(ReviewComment(author: user, text: comment)) }
        }
    }

    func addComment(_ text: String, metric metricID: String, in id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let user = userName
        mutate(id) { engagement in
            var entry = engagement.metric(metricID)
            entry.comments.append(ReviewComment(author: user, text: trimmed))
            engagement.metrics[metricID] = entry
            log("Commented", target: MetricCatalog.metric(metricID)?.title ?? metricID, detail: trimmed, in: &engagement)
        }
    }

    func addComment(_ text: String, narrative narrativeID: String, in id: UUID) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        let user = userName
        mutate(id) { engagement in
            var entry = engagement.narrative(narrativeID)
            entry.comments.append(ReviewComment(author: user, text: trimmed))
            engagement.narratives[narrativeID] = entry
            log("Commented", target: NarrativeCatalog.requirement(narrativeID)?.title ?? narrativeID, detail: trimmed, in: &engagement)
        }
    }

    // MARK: Imports

    /// Copies Scope 1, 2 and/or 3 totals from a GHG Accounting inventory.
    func importGHG(_ totals: GHGInventoryTotals, scopes: Set<Int>, into id: UUID) {
        let pairs: [(Int, String, Double)] = [(1, MetricID.scope1, totals.scope1), (2, MetricID.scope2, totals.scope2),
                                              (3, MetricID.scope3, totals.scope3)]
        for (scope, metricID, value) in pairs where scopes.contains(scope) {
            updateMetric(metricID, in: id) { entry in
                entry.current = (value * 100).rounded() / 100
                entry.origin = .imported
                entry.originNote = totals.sourceNote
                entry.source = totals.sourceNote
                if entry.method.isEmpty {
                    entry.method = "Calculated in GHG Accounting (activity × emission factor, IPCC GWPs as set in the inventory). Check the inventory boundary matches the company's organisational boundary."
                }
            }
        }
        mutate(id) { engagement in
            log("Imported from GHG Accounting", target: totals.name,
                detail: scopes.sorted().map { "Scope \($0)" }.joined(separator: ", "), in: &engagement)
        }
        statusMessage = "Imported \(scopes.sorted().map { "Scope \($0)" }.joined(separator: ", ")) from \(totals.name)."
    }

    /// Applies a filled data-request sheet. Returns a one-line summary.
    @discardableResult
    func applyDataRequest(_ result: DataRequest.ImportResult, to id: UUID, fileName: String) -> String {
        guard engagement(id)?.isLocked == false else {
            statusMessage = "This engagement is signed off. Reopen it to import data."
            return statusMessage
        }
        for update in result.updates {
            updateMetric(update.metricID, in: id) { entry in
                if let current = update.current { entry.current = current }
                if let prior = update.prior { entry.prior = prior }
                if let text = update.text { entry.text = text }
                if let source = update.source { entry.source = source }
                if let method = update.method { entry.method = method }
                if let owner = update.owner { entry.owner = owner }
                entry.origin = .dataRequest
                entry.originNote = fileName
            }
        }
        mutate(id) { engagement in
            log("Imported data request", target: fileName,
                detail: "\(result.updates.count) KPIs updated, \(result.skipped.count) lines skipped", in: &engagement)
        }
        let summary = "Imported \(result.updates.count) KPI\(result.updates.count == 1 ? "" : "s") from \(fileName)"
            + (result.skipped.isEmpty ? "." : "; \(result.skipped.count) line\(result.skipped.count == 1 ? "" : "s") skipped.")
        statusMessage = summary
        return summary
    }

    // MARK: Evidence

    @discardableResult
    func addEvidence(_ item: EvidenceItem, linkTo metricIDs: [String] = [], in id: UUID) -> UUID {
        var stamped = item
        stamped.addedBy = userName
        stamped.addedAt = Date()
        mutate(id) { engagement in
            engagement.evidence.append(stamped)
            for metricID in metricIDs {
                var entry = engagement.metric(metricID)
                if !entry.evidenceIDs.contains(stamped.id) { entry.evidenceIDs.append(stamped.id) }
                engagement.metrics[metricID] = entry
            }
            log("Added evidence", target: stamped.title, detail: stamped.kind.title, in: &engagement)
        }
        return stamped.id
    }

    func updateEvidence(_ item: EvidenceItem, in id: UUID) {
        mutate(id) { engagement in
            guard let index = engagement.evidence.firstIndex(where: { $0.id == item.id }) else { return }
            engagement.evidence[index] = item
            log("Edited evidence", target: item.title, coalesce: true, in: &engagement)
        }
    }

    func setEvidenceVerified(_ evidenceID: UUID, verified: Bool, in id: UUID) {
        let user = userName
        mutate(id) { engagement in
            guard let index = engagement.evidence.firstIndex(where: { $0.id == evidenceID }) else { return }
            engagement.evidence[index].verified = verified
            engagement.evidence[index].verifiedBy = verified ? user : ""
            log(verified ? "Verified evidence" : "Cleared verification", target: engagement.evidence[index].title, in: &engagement)
        }
    }

    func linkEvidence(_ evidenceID: UUID, metric metricID: String, linked: Bool, in id: UUID) {
        mutate(id) { engagement in
            var entry = engagement.metric(metricID)
            if linked {
                if !entry.evidenceIDs.contains(evidenceID) { entry.evidenceIDs.append(evidenceID) }
            } else {
                entry.evidenceIDs.removeAll { $0 == evidenceID }
            }
            engagement.metrics[metricID] = entry
            let title = engagement.evidenceItem(evidenceID)?.title ?? "evidence"
            log(linked ? "Linked evidence" : "Unlinked evidence", target: MetricCatalog.metric(metricID)?.title ?? metricID,
                detail: title, in: &engagement)
        }
    }

    func removeEvidence(_ evidenceID: UUID, in id: UUID) {
        mutate(id) { engagement in
            let title = engagement.evidenceItem(evidenceID)?.title ?? "evidence"
            engagement.evidence.removeAll { $0.id == evidenceID }
            for key in Array(engagement.metrics.keys) {
                engagement.metrics[key]?.evidenceIDs.removeAll { $0 == evidenceID }
            }
            for key in Array(engagement.narratives.keys) {
                engagement.narratives[key]?.evidenceIDs.removeAll { $0 == evidenceID }
            }
            for index in engagement.issues.indices {
                engagement.issues[index].evidenceIDs.removeAll { $0 == evidenceID }
            }
            for index in engagement.physicalRisks.indices where engagement.physicalRisks[index].evidenceID == evidenceID {
                engagement.physicalRisks[index].evidenceID = nil
            }
            log("Removed evidence", target: title, in: &engagement)
        }
    }

    // MARK: Risks

    func upsertIssue(_ issue: MaterialIssue, in id: UUID) {
        mutate(id) { engagement in
            if let index = engagement.issues.firstIndex(where: { $0.id == issue.id }) {
                engagement.issues[index] = issue
                log("Edited material issue", target: issue.title, coalesce: true, in: &engagement)
            } else {
                engagement.issues.append(issue)
                log("Added material issue", target: issue.title, detail: issue.type.title, in: &engagement)
            }
        }
    }

    func removeIssue(_ issueID: UUID, in id: UUID) {
        mutate(id) { engagement in
            let title = engagement.issues.first { $0.id == issueID }?.title ?? "issue"
            engagement.issues.removeAll { $0.id == issueID }
            log("Removed material issue", target: title, in: &engagement)
        }
    }

    func upsertPhysicalRisk(_ risk: PhysicalRiskAssessment, in id: UUID) {
        mutate(id) { engagement in
            if let index = engagement.physicalRisks.firstIndex(where: { $0.id == risk.id }) {
                engagement.physicalRisks[index] = risk
                log("Edited physical-risk assessment", target: risk.hazard.title, coalesce: true, in: &engagement)
            } else {
                engagement.physicalRisks.append(risk)
                log("Added physical-risk assessment", target: risk.hazard.title, detail: risk.scenario, in: &engagement)
            }
        }
    }

    func removePhysicalRisk(_ riskID: UUID, in id: UUID) {
        mutate(id) { engagement in
            engagement.physicalRisks.removeAll { $0.id == riskID }
            log("Removed physical-risk assessment", in: &engagement)
        }
    }

    /// Adds a simulation package as evidence and starts a wildfire assessment from it.
    func addPhysicalRisk(from candidate: SimulationEvidenceCandidate, in id: UUID) {
        var item = EvidenceItem(title: candidate.title, kind: .simulation, location: candidate.folderPath)
        item.period = DisclosureFormat.date(candidate.generatedAt)
        item.externalReference = candidate.id
        item.notes = "Scenario: \(candidate.scenario)" + (candidate.burntPercent.map { ". Burnt area \(DisclosureFormat.number($0))%" } ?? "")
        let evidenceID = addEvidence(item, in: id)
        var risk = PhysicalRiskAssessment()
        risk.hazard = .wildfire
        risk.scenario = candidate.scenario
        risk.horizon = candidate.horizon
        risk.valueVulnerableCrore = candidate.exposureCrore
        risk.grossLossCrore = candidate.grossLossCrore
        risk.insuredLossCrore = candidate.insuredLossCrore
        risk.evidenceID = evidenceID
        risk.notes = "From wildfire simulation package \(candidate.id). Enter the value of all assets assessed."
        upsertPhysicalRisk(risk, in: id)
    }

    /// Fills IFRS S2 29(c) from the physical-risk assessments.
    func applyPhysicalRisksToMetrics(in id: UUID) {
        guard let engagement = engagement(id) else { return }
        let rows = engagement.physicalRisks.filter { $0.valueVulnerableCrore != nil }
        guard !rows.isEmpty else {
            statusMessage = "Enter the value of vulnerable assets in at least one assessment first."
            return
        }
        let vulnerable = rows.compactMap(\.valueVulnerableCrore).reduce(0, +)
        let assessed = engagement.physicalRisks.compactMap(\.valueAssessedCrore).max()
        let method = "Sum of assets found vulnerable across \(rows.count) physical-risk assessment\(rows.count == 1 ? "" : "s") (\(rows.map(\.hazard.title).joined(separator: ", "))). Assets exposed to more than one hazard may be counted more than once; adjust if needed."
        updateMetric(MetricID.physicalVulnerableAmount, in: id) { entry in
            entry.current = (vulnerable * 100).rounded() / 100
            entry.origin = .imported
            entry.originNote = "Physical-risk assessments"
            entry.method = method
        }
        if let assessed, assessed > 0 {
            updateMetric(MetricID.physicalVulnerableShare, in: id) { entry in
                entry.current = (min(vulnerable / assessed, 1) * 1000).rounded() / 10
                entry.origin = .imported
                entry.originNote = "Physical-risk assessments"
                entry.method = method + " Share uses the largest value assessed as the denominator."
            }
        }
        statusMessage = "Filled IFRS S2 29(c) from the physical-risk assessments. Review the figures in KPI Data."
    }

    // MARK: Sign-off

    func signOff(id: UUID, statement: String) {
        let user = userName
        mutate(id) { engagement in
            engagement.signOff = SignOff(approvedBy: user, approvedAt: Date(), statement: statement)
            log("Signed off engagement", target: engagement.periodLabel, detail: statement, in: &engagement)
        }
        statusMessage = "Signed off. The engagement is read-only until reopened. Save to keep the sign-off."
    }

    func reopen(id: UUID, reason: String) {
        mutate(id, allowWhenLocked: true) { engagement in
            let previous = engagement.signOff
            engagement.signOff = nil
            log("Reopened engagement", target: engagement.periodLabel,
                detail: "Sign-off by \(previous?.approvedBy ?? "unknown") withdrawn. \(reason)", in: &engagement)
        }
    }

    // MARK: Exports

    /// Writes a report and returns its file, or nil if writing failed.
    @discardableResult
    func exportReport(_ kind: ReportKind, format: ExportFormat, id: UUID) -> URL? {
        guard let engagement = engagement(id) else { return nil }
        let paragraphs = kind == .ifrsS2 ? PhysicalRiskDrafting.paragraphs(for: engagement) : []
        let document = ReportBuilder.build(kind, engagement: engagement, physicalRiskParagraphs: paragraphs)
        let text = ReportRenderer.render(document, as: format)
        return write(text, name: "\(DisclosureFormat.fileStem(engagement.companyName))_\(kind.rawValue).\(format.fileExtension)",
                     for: engagement, what: kind.title)
    }

    @discardableResult
    func exportDataRequest(id: UUID) -> URL? {
        guard let engagement = engagement(id) else { return nil }
        return write(DataRequest.template(for: engagement),
                     name: "\(DisclosureFormat.fileStem(engagement.companyName))_data_request.csv",
                     for: engagement, what: "Data request template")
    }

    private func write(_ text: String, name: String, for engagement: DisclosureEngagement, what: String) -> URL? {
        do {
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd-HHmmss"
            let folder = locations.exportsDirectory.appendingPathComponent(
                "\(DisclosureFormat.fileStem(engagement.companyName))-\(DisclosureFormat.fileStem(engagement.periodLabel))-\(formatter.string(from: Date()))",
                isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let url = folder.appendingPathComponent(name)
            try text.write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Exported \(what) to \(url.path)."
            return url
        } catch {
            statusMessage = "Export failed: \(error.localizedDescription)"
            return nil
        }
    }

    // MARK: Persistence

    private func load() {
        let directory = locations.engagementsDirectory
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        var loaded: [DisclosureEngagement] = []
        var failures = 0
        for file in files where file.pathExtension == "json" {
            guard let engagement = try? DisclosureJSON.read(from: file) else { failures += 1; continue }
            savedIDs.insert(engagement.id)
            loaded.append(engagement)
        }
        engagements = loaded.sorted { $0.updatedAt > $1.updatedAt }
        if failures > 0 { statusMessage = "\(failures) engagement file(s) could not be read and were skipped." }
    }
}
