import Foundation

// Persisted model of a disclosure engagement: one client company, one financial year.
//
// Every struct decodes with defaults for missing keys, so fields can be added later
// without breaking saved engagements. Framework content (which KPIs exist, what they
// mean) is code in `Catalog/`, not data; engagements only store answers keyed by id.

// MARK: - Frameworks and workflow

nonisolated enum DisclosureFramework: String, Codable, CaseIterable, Identifiable, Sendable {
    case brsr, brsrCore, ifrsS2

    var id: String { rawValue }
    var title: String {
        switch self {
        case .brsr: return "BRSR"
        case .brsrCore: return "BRSR Core"
        case .ifrsS2: return "IFRS S2"
        }
    }
    var detail: String {
        switch self {
        case .brsr: return "SEBI Business Responsibility and Sustainability Report: Sections A–C across nine principles."
        case .brsrCore: return "SEBI's subset of BRSR KPIs that needs independent assessment or assurance."
        case .ifrsS2: return "ISSB climate-related disclosures: governance, strategy, risk management, metrics and targets."
        }
    }
}

/// Where one data point or narrative stands.
nonisolated enum WorkflowStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case notStarted, inProgress, readyForReview, changesRequested, approved

    var id: String { rawValue }
    var title: String {
        switch self {
        case .notStarted: return "Not Started"
        case .inProgress: return "In Progress"
        case .readyForReview: return "Ready for Review"
        case .changesRequested: return "Changes Requested"
        case .approved: return "Approved"
        }
    }
    var systemImage: String {
        switch self {
        case .notStarted: return "circle"
        case .inProgress: return "circle.lefthalf.filled"
        case .readyForReview: return "paperplane"
        case .changesRequested: return "arrow.uturn.backward.circle"
        case .approved: return "checkmark.seal.fill"
        }
    }
}

nonisolated enum ReportingBoundary: String, Codable, CaseIterable, Identifiable, Sendable {
    case standalone, consolidated
    var id: String { rawValue }
    var title: String { self == .standalone ? "Standalone" : "Consolidated" }
}

nonisolated enum AssuranceLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case none, assessment, limited, reasonable
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none: return "None yet"
        case .assessment: return "Assessment"
        case .limited: return "Limited assurance"
        case .reasonable: return "Reasonable assurance"
        }
    }
}


// MARK: - Company and team

nonisolated struct CompanyProfile: Codable, Hashable, Sendable {
    var legalName = ""
    var cin = ""
    var yearOfIncorporation: Int?
    var registeredAddress = ""
    var corporateAddress = ""
    var email = ""
    var phone = ""
    var website = ""
    var stockExchanges = ""
    var paidUpCapitalCrore: Double?
    var sector: IndustrySector = .manufacturing
    var nicCode = ""
    var isListed = true
    /// Rank by market capitalisation (1 = largest), as published by the exchanges.
    var marketCapRank: Int?
    var contactName = ""
    var contactRole = ""
    var contactEmail = ""
    var contactPhone = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case legalName, cin, yearOfIncorporation, registeredAddress, corporateAddress, email, phone, website
        case stockExchanges, paidUpCapitalCrore, sector, nicCode, isListed, marketCapRank
        case contactName, contactRole, contactEmail, contactPhone
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        legalName = try c.value(.legalName, default: "")
        cin = try c.value(.cin, default: "")
        yearOfIncorporation = try c.decodeIfPresent(Int.self, forKey: .yearOfIncorporation)
        registeredAddress = try c.value(.registeredAddress, default: "")
        corporateAddress = try c.value(.corporateAddress, default: "")
        email = try c.value(.email, default: "")
        phone = try c.value(.phone, default: "")
        website = try c.value(.website, default: "")
        stockExchanges = try c.value(.stockExchanges, default: "")
        paidUpCapitalCrore = try c.decodeIfPresent(Double.self, forKey: .paidUpCapitalCrore)
        sector = try c.value(.sector, default: .manufacturing)
        nicCode = try c.value(.nicCode, default: "")
        isListed = try c.value(.isListed, default: true)
        marketCapRank = try c.decodeIfPresent(Int.self, forKey: .marketCapRank)
        contactName = try c.value(.contactName, default: "")
        contactRole = try c.value(.contactRole, default: "")
        contactEmail = try c.value(.contactEmail, default: "")
        contactPhone = try c.value(.contactPhone, default: "")
    }
}

nonisolated struct EngagementTeam: Codable, Hashable, Sendable {
    /// Consulting firm running the engagement; empty when the company reports itself.
    var consultingFirm = ""
    var engagementLead = ""
    var preparer = ""
    var reviewer = ""
    var approver = ""
    var boardCommittee = ""
    var assuranceProvider = ""
    var assuranceLevel: AssuranceLevel = .none

    init() {}

    private enum CodingKeys: String, CodingKey {
        case consultingFirm, engagementLead, preparer, reviewer, approver, boardCommittee, assuranceProvider, assuranceLevel
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        consultingFirm = try c.value(.consultingFirm, default: "")
        engagementLead = try c.value(.engagementLead, default: "")
        preparer = try c.value(.preparer, default: "")
        reviewer = try c.value(.reviewer, default: "")
        approver = try c.value(.approver, default: "")
        boardCommittee = try c.value(.boardCommittee, default: "")
        assuranceProvider = try c.value(.assuranceProvider, default: "")
        assuranceLevel = try c.value(.assuranceLevel, default: .none)
    }
}

// MARK: - Answers

nonisolated enum ValueOrigin: String, Codable, Sendable {
    case manual, imported, dataRequest, rolledForward
    var title: String {
        switch self {
        case .manual: return "Entered"
        case .imported: return "Imported"
        case .dataRequest: return "Data request"
        case .rolledForward: return "Rolled forward"
        }
    }
}

nonisolated enum CommentKind: String, Codable, Sendable {
    case comment, changeRequest, approval, reopened
}

nonisolated struct ReviewComment: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var author: String
    var date = Date()
    var text: String
    var kind: CommentKind = .comment
}

/// The answer to one KPI for the reporting year.
nonisolated struct MetricEntry: Codable, Hashable, Sendable {
    var current: Double?
    var prior: Double?
    /// Value of text metrics (e.g. unit of output); a note for numeric ones.
    var text = ""
    var notApplicable = false
    var notApplicableReason = ""
    /// System or document the value comes from.
    var source = ""
    /// Calculation method, factors and assumptions.
    var method = ""
    /// Why the value changed from the prior year.
    var varianceExplanation = ""
    var owner = ""
    var status: WorkflowStatus = .notStarted
    var evidenceIDs: [UUID] = []
    var comments: [ReviewComment] = []
    var origin: ValueOrigin = .manual
    var originNote = ""
    var approvedBy = ""
    var approvedAt: Date?
    var updatedAt: Date?
    var updatedBy = ""

    init() {}

    var hasValue: Bool { current != nil || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    /// Answered for completeness: a value, or not applicable with a reason.
    var isAnswered: Bool {
        hasValue || (notApplicable && !notApplicableReason.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    private enum CodingKeys: String, CodingKey {
        case current, prior, text, notApplicable, notApplicableReason, source, method, varianceExplanation, owner
        case status, evidenceIDs, comments, origin, originNote, approvedBy, approvedAt, updatedAt, updatedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        current = try c.decodeIfPresent(Double.self, forKey: .current)
        prior = try c.decodeIfPresent(Double.self, forKey: .prior)
        text = try c.value(.text, default: "")
        notApplicable = try c.value(.notApplicable, default: false)
        notApplicableReason = try c.value(.notApplicableReason, default: "")
        source = try c.value(.source, default: "")
        method = try c.value(.method, default: "")
        varianceExplanation = try c.value(.varianceExplanation, default: "")
        owner = try c.value(.owner, default: "")
        status = try c.value(.status, default: .notStarted)
        evidenceIDs = try c.value(.evidenceIDs, default: [])
        comments = try c.value(.comments, default: [])
        origin = try c.value(.origin, default: .manual)
        originNote = try c.value(.originNote, default: "")
        approvedBy = try c.value(.approvedBy, default: "")
        approvedAt = try c.decodeIfPresent(Date.self, forKey: .approvedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedBy = try c.value(.updatedBy, default: "")
    }
}

/// The answer to one narrative requirement.
nonisolated struct NarrativeEntry: Codable, Hashable, Sendable {
    var text = ""
    /// Indexes of the requirement's checklist elements the text covers.
    var coveredElements: Set<Int> = []
    var notApplicable = false
    var notApplicableReason = ""
    var owner = ""
    var status: WorkflowStatus = .notStarted
    var evidenceIDs: [UUID] = []
    var comments: [ReviewComment] = []
    var approvedBy = ""
    var approvedAt: Date?
    var updatedAt: Date?
    var updatedBy = ""

    init() {}

    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var isAnswered: Bool {
        hasText || (notApplicable && !notApplicableReason.trimmingCharacters(in: .whitespaces).isEmpty)
    }
    var wordCount: Int { text.split(whereSeparator: { $0.isWhitespace || $0.isNewline }).count }

    private enum CodingKeys: String, CodingKey {
        case text, coveredElements, notApplicable, notApplicableReason, owner, status, evidenceIDs, comments
        case approvedBy, approvedAt, updatedAt, updatedBy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        text = try c.value(.text, default: "")
        coveredElements = try c.value(.coveredElements, default: [])
        notApplicable = try c.value(.notApplicable, default: false)
        notApplicableReason = try c.value(.notApplicableReason, default: "")
        owner = try c.value(.owner, default: "")
        status = try c.value(.status, default: .notStarted)
        evidenceIDs = try c.value(.evidenceIDs, default: [])
        comments = try c.value(.comments, default: [])
        approvedBy = try c.value(.approvedBy, default: "")
        approvedAt = try c.decodeIfPresent(Date.self, forKey: .approvedAt)
        updatedAt = try c.decodeIfPresent(Date.self, forKey: .updatedAt)
        updatedBy = try c.value(.updatedBy, default: "")
    }
}

// MARK: - Evidence

nonisolated enum EvidenceKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case invoice, meterLog, certificate, register, policy, report, calculation, simulation, other

    var id: String { rawValue }
    var title: String {
        switch self {
        case .invoice: return "Invoice or bill"
        case .meterLog: return "Meter or log reading"
        case .certificate: return "Certificate"
        case .register: return "Register or HR record"
        case .policy: return "Policy or board minute"
        case .report: return "Report"
        case .calculation: return "Calculation workbook"
        case .simulation: return "Simulation package"
        case .other: return "Other"
        }
    }
    var systemImage: String {
        switch self {
        case .invoice: return "doc.text"
        case .meterLog: return "gauge"
        case .certificate: return "rosette"
        case .register: return "person.text.rectangle"
        case .policy: return "building.columns"
        case .report: return "doc.richtext"
        case .calculation: return "tablecells"
        case .simulation: return "flame"
        case .other: return "paperclip"
        }
    }
}

nonisolated struct EvidenceItem: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title: String
    var kind: EvidenceKind = .other
    /// File path or web address.
    var location = ""
    var period = ""
    var notes = ""
    var addedBy = ""
    var addedAt = Date()
    var verified = false
    var verifiedBy = ""
    /// Id in the source system, e.g. a simulation run id.
    var externalReference = ""

    init(title: String, kind: EvidenceKind = .other, location: String = "") {
        self.title = title
        self.kind = kind
        self.location = location
    }

    var isWebLink: Bool { location.hasPrefix("http://") || location.hasPrefix("https://") }

    private enum CodingKeys: String, CodingKey {
        case id, title, kind, location, period, notes, addedBy, addedAt, verified, verifiedBy, externalReference
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        title = try c.value(.title, default: "Untitled evidence")
        kind = try c.value(.kind, default: .other)
        location = try c.value(.location, default: "")
        period = try c.value(.period, default: "")
        notes = try c.value(.notes, default: "")
        addedBy = try c.value(.addedBy, default: "")
        addedAt = try c.value(.addedAt, default: Date())
        verified = try c.value(.verified, default: false)
        verifiedBy = try c.value(.verifiedBy, default: "")
        externalReference = try c.value(.externalReference, default: "")
    }
}

// MARK: - Risks and opportunities

nonisolated enum IssueType: String, Codable, CaseIterable, Identifiable, Sendable {
    case risk, opportunity
    var id: String { rawValue }
    var title: String { self == .risk ? "Risk" : "Opportunity" }
}

nonisolated enum IssueTopic: String, Codable, CaseIterable, Identifiable, Sendable {
    case physicalAcute, physicalChronic, transitionPolicy, transitionTechnology, transitionMarket, transitionReputation
    case environment, social, governance

    var id: String { rawValue }
    var title: String {
        switch self {
        case .physicalAcute: return "Climate – physical (acute)"
        case .physicalChronic: return "Climate – physical (chronic)"
        case .transitionPolicy: return "Climate – transition (policy & legal)"
        case .transitionTechnology: return "Climate – transition (technology)"
        case .transitionMarket: return "Climate – transition (market)"
        case .transitionReputation: return "Climate – transition (reputation)"
        case .environment: return "Environment (other)"
        case .social: return "Social"
        case .governance: return "Governance"
        }
    }
    /// Climate-related topics also feed IFRS S2.
    var isClimate: Bool {
        switch self {
        case .environment, .social, .governance: return false
        default: return true
        }
    }
}

nonisolated enum TimeHorizon: String, Codable, CaseIterable, Identifiable, Sendable {
    case short, medium, long
    var id: String { rawValue }
    var title: String {
        switch self {
        case .short: return "Short term"
        case .medium: return "Medium term"
        case .long: return "Long term"
        }
    }
}

nonisolated enum FinancialImplication: String, Codable, CaseIterable, Identifiable, Sendable {
    case negative, positive, mixed, notAssessed
    var id: String { rawValue }
    var title: String {
        switch self {
        case .negative: return "Negative"
        case .positive: return "Positive"
        case .mixed: return "Mixed"
        case .notAssessed: return "Not assessed"
        }
    }
}

/// A material issue: feeds BRSR Section A (material responsible business conduct
/// issues) and, when climate-related, IFRS S2 Strategy.
nonisolated struct MaterialIssue: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var title = ""
    var type: IssueType = .risk
    var topic: IssueTopic = .transitionPolicy
    /// Why the issue is material.
    var rationale = ""
    /// Approach to adapt or mitigate (risks) or to capture (opportunities).
    var approach = ""
    var implication: FinancialImplication = .notAssessed
    var financialNote = ""
    var horizon: TimeHorizon = .medium
    /// 1 (rare) – 5 (almost certain).
    var likelihood = 3
    /// 1 (minor) – 5 (severe).
    var impact = 3
    var owner = ""
    var evidenceIDs: [UUID] = []

    init() {}

    var score: Int { likelihood * impact }

    private enum CodingKeys: String, CodingKey {
        case id, title, type, topic, rationale, approach, implication, financialNote, horizon, likelihood, impact, owner, evidenceIDs
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        title = try c.value(.title, default: "")
        type = try c.value(.type, default: .risk)
        topic = try c.value(.topic, default: .transitionPolicy)
        rationale = try c.value(.rationale, default: "")
        approach = try c.value(.approach, default: "")
        implication = try c.value(.implication, default: .notAssessed)
        financialNote = try c.value(.financialNote, default: "")
        horizon = try c.value(.horizon, default: .medium)
        likelihood = min(max(try c.value(.likelihood, default: 3), 1), 5)
        impact = min(max(try c.value(.impact, default: 3), 1), 5)
        owner = try c.value(.owner, default: "")
        evidenceIDs = try c.value(.evidenceIDs, default: [])
    }
}

nonisolated enum PhysicalHazard: String, Codable, CaseIterable, Identifiable, Sendable {
    case wildfire, flood, cyclone, heat, drought, waterStress, seaLevelRise
    var id: String { rawValue }
    var title: String {
        switch self {
        case .wildfire: return "Wildfire"
        case .flood: return "Flood"
        case .cyclone: return "Cyclone"
        case .heat: return "Extreme heat"
        case .drought: return "Drought"
        case .waterStress: return "Water stress"
        case .seaLevelRise: return "Sea-level rise"
        }
    }
}

/// Modelled physical risk to the company's assets for one hazard; feeds IFRS S2 29(c).
nonisolated struct PhysicalRiskAssessment: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var hazard: PhysicalHazard = .flood
    var scenario = ""
    var horizon = ""
    var assetsAssessed: Int?
    /// Value of the assets assessed, ₹ crore.
    var valueAssessedCrore: Double?
    /// Value of the assets found vulnerable (e.g. inside the hazard footprint), ₹ crore.
    var valueVulnerableCrore: Double?
    var grossLossCrore: Double?
    var insuredLossCrore: Double?
    var evidenceID: UUID?
    var notes = ""

    init() {}

    var vulnerableShare: Double? {
        guard let total = valueAssessedCrore, total > 0, let vulnerable = valueVulnerableCrore else { return nil }
        return vulnerable / total
    }

    private enum CodingKeys: String, CodingKey {
        case id, hazard, scenario, horizon, assetsAssessed, valueAssessedCrore, valueVulnerableCrore
        case grossLossCrore, insuredLossCrore, evidenceID, notes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        hazard = try c.value(.hazard, default: .flood)
        scenario = try c.value(.scenario, default: "")
        horizon = try c.value(.horizon, default: "")
        assetsAssessed = try c.decodeIfPresent(Int.self, forKey: .assetsAssessed)
        valueAssessedCrore = try c.decodeIfPresent(Double.self, forKey: .valueAssessedCrore)
        valueVulnerableCrore = try c.decodeIfPresent(Double.self, forKey: .valueVulnerableCrore)
        grossLossCrore = try c.decodeIfPresent(Double.self, forKey: .grossLossCrore)
        insuredLossCrore = try c.decodeIfPresent(Double.self, forKey: .insuredLossCrore)
        evidenceID = try c.decodeIfPresent(UUID.self, forKey: .evidenceID)
        notes = try c.value(.notes, default: "")
    }
}

// MARK: - BRSR Section B

nonisolated enum TriState: String, Codable, CaseIterable, Identifiable, Sendable {
    case unanswered, yes, no
    var id: String { rawValue }
    var title: String {
        switch self {
        case .unanswered: return "—"
        case .yes: return "Yes"
        case .no: return "No"
        }
    }
}

/// Section B policy and management answers for one NGRBC principle.
nonisolated struct PrinciplePolicy: Codable, Hashable, Identifiable, Sendable {
    var principle: Int
    var hasPolicy: TriState = .unanswered
    var boardApproved: TriState = .unanswered
    var webLink = ""
    var translatedToProcedures: TriState = .unanswered
    var extendsToValueChain: TriState = .unanswered
    var certifications = ""
    var commitments = ""
    var performance = ""
    /// Required when there is no policy for the principle.
    var reasonIfNoPolicy = ""

    var id: Int { principle }

    init(principle: Int) { self.principle = principle }

    var isComplete: Bool {
        switch hasPolicy {
        case .unanswered: return false
        case .no: return !reasonIfNoPolicy.trimmingCharacters(in: .whitespaces).isEmpty
        case .yes:
            return boardApproved != .unanswered && translatedToProcedures != .unanswered && extendsToValueChain != .unanswered
        }
    }

    private enum CodingKeys: String, CodingKey {
        case principle, hasPolicy, boardApproved, webLink, translatedToProcedures, extendsToValueChain
        case certifications, commitments, performance, reasonIfNoPolicy
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        principle = try c.value(.principle, default: 1)
        hasPolicy = try c.value(.hasPolicy, default: .unanswered)
        boardApproved = try c.value(.boardApproved, default: .unanswered)
        webLink = try c.value(.webLink, default: "")
        translatedToProcedures = try c.value(.translatedToProcedures, default: .unanswered)
        extendsToValueChain = try c.value(.extendsToValueChain, default: .unanswered)
        certifications = try c.value(.certifications, default: "")
        commitments = try c.value(.commitments, default: "")
        performance = try c.value(.performance, default: "")
        reasonIfNoPolicy = try c.value(.reasonIfNoPolicy, default: "")
    }
}

/// Section B governance, leadership and oversight.
nonisolated struct GovernanceDetails: Codable, Hashable, Sendable {
    var highestAuthority = ""
    var hasSustainabilityCommittee: TriState = .unanswered
    var committeeDetails = ""
    var reviewFrequency = ""
    var independentAssessment = ""

    init() {}

    private enum CodingKeys: String, CodingKey {
        case highestAuthority, hasSustainabilityCommittee, committeeDetails, reviewFrequency, independentAssessment
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        highestAuthority = try c.value(.highestAuthority, default: "")
        hasSustainabilityCommittee = try c.value(.hasSustainabilityCommittee, default: .unanswered)
        committeeDetails = try c.value(.committeeDetails, default: "")
        reviewFrequency = try c.value(.reviewFrequency, default: "")
        independentAssessment = try c.value(.independentAssessment, default: "")
    }
}

// MARK: - Sign-off and audit trail

nonisolated struct SignOff: Codable, Hashable, Sendable {
    var approvedBy: String
    var approvedAt = Date()
    var statement = ""
}

nonisolated struct ActivityEvent: Codable, Hashable, Identifiable, Sendable {
    var id = UUID()
    var date = Date()
    var user: String
    var action: String
    var target = ""
    var detail = ""
}

// MARK: - Engagement

nonisolated struct DisclosureEngagement: Codable, Hashable, Identifiable, Sendable {
    static let maxActivityEvents = 2_000

    var id = UUID()
    var profile = CompanyProfile()
    /// First calendar year of the financial year: 2025 = FY 2025-26.
    var fiscalYearStart: Int
    var frameworks: Set<DisclosureFramework> = [.brsr, .brsrCore]
    var boundary: ReportingBoundary = .standalone
    var team = EngagementTeam()
    var filingDeadline: Date?
    /// Answers keyed by `MetricDefinition.id`.
    var metrics: [String: MetricEntry] = [:]
    /// Answers keyed by `NarrativeRequirement.id`.
    var narratives: [String: NarrativeEntry] = [:]
    var issues: [MaterialIssue] = []
    var physicalRisks: [PhysicalRiskAssessment] = []
    var policies: [PrinciplePolicy] = (1...9).map { PrinciplePolicy(principle: $0) }
    var governance = GovernanceDetails()
    var evidence: [EvidenceItem] = []
    var signOff: SignOff?
    var activity: [ActivityEvent] = []
    /// The client in the Clients register this engagement belongs to, if linked.
    var clientID: UUID?
    /// Illustrative data, never a real company.
    var isExample = false
    var createdAt = Date()
    var updatedAt = Date()

    init(fiscalYearStart: Int) {
        self.fiscalYearStart = fiscalYearStart
    }

    var periodLabel: String { ReportingPeriod.label(fiscalYearStart) }
    var priorPeriodLabel: String { ReportingPeriod.priorLabel(fiscalYearStart) }
    var companyName: String {
        let name = profile.legalName.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Untitled client" : name
    }
    var displayName: String { "\(companyName) · \(periodLabel)" }
    var isLocked: Bool { signOff != nil }

    func metric(_ id: String) -> MetricEntry { metrics[id] ?? MetricEntry() }
    func narrative(_ id: String) -> NarrativeEntry { narratives[id] ?? NarrativeEntry() }
    func evidenceItem(_ id: UUID) -> EvidenceItem? { evidence.first { $0.id == id } }
    func policy(_ principle: Int) -> PrinciplePolicy {
        policies.first { $0.principle == principle } ?? PrinciplePolicy(principle: principle)
    }

    mutating func appendActivity(_ event: ActivityEvent) {
        activity.append(event)
        if activity.count > Self.maxActivityEvents {
            activity.removeFirst(activity.count - Self.maxActivityEvents)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case id, profile, fiscalYearStart, frameworks, boundary, team, filingDeadline, metrics, narratives, issues
        case physicalRisks, policies, governance, evidence, signOff, activity, isExample, createdAt, updatedAt
        case clientID
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.value(.id, default: UUID())
        profile = try c.value(.profile, default: CompanyProfile())
        fiscalYearStart = try c.value(.fiscalYearStart, default: 2025)
        frameworks = try c.value(.frameworks, default: [.brsr, .brsrCore])
        boundary = try c.value(.boundary, default: .standalone)
        team = try c.value(.team, default: EngagementTeam())
        filingDeadline = try c.decodeIfPresent(Date.self, forKey: .filingDeadline)
        metrics = try c.value(.metrics, default: [:])
        narratives = try c.value(.narratives, default: [:])
        issues = try c.value(.issues, default: [])
        physicalRisks = try c.value(.physicalRisks, default: [])
        let savedPolicies = try c.value(.policies, default: [PrinciplePolicy]())
        policies = (1...9).map { number in savedPolicies.first { $0.principle == number } ?? PrinciplePolicy(principle: number) }
        governance = try c.value(.governance, default: GovernanceDetails())
        evidence = try c.value(.evidence, default: [])
        signOff = try c.decodeIfPresent(SignOff.self, forKey: .signOff)
        activity = try c.value(.activity, default: [])
        isExample = try c.value(.isExample, default: false)
        clientID = try c.decodeIfPresent(UUID.self, forKey: .clientID)
        createdAt = try c.value(.createdAt, default: Date())
        updatedAt = try c.value(.updatedAt, default: Date())
    }
}
