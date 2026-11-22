import Foundation

/// An illustrative engagement for demonstrations and training. The company, people
/// and every figure are invented; the numbers are only internally consistent
/// (e.g. Scope 2 ≈ grid electricity × 0.727 kg CO2e/kWh).
nonisolated enum DisclosureExample {

    static func engagement(user: String, today: Date = Date()) -> DisclosureEngagement {
        let calendar = Calendar(identifier: .gregorian)
        let year = calendar.component(.year, from: today)
        let month = calendar.component(.month, from: today)
        // The last completed Indian financial year (April–March).
        let lastCompleted = (month >= 4 ? year : year - 1) - 1

        var engagement = DisclosureEngagement(fiscalYearStart: lastCompleted)
        engagement.isExample = true
        engagement.frameworks = [.brsr, .brsrCore, .ifrsS2]
        engagement.boundary = .standalone
        engagement.filingDeadline = calendar.date(byAdding: .day, value: 60, to: today)

        var profile = CompanyProfile()
        profile.legalName = "Deccan Polymer Components Ltd (example)"
        profile.cin = "L00000XX0000PLC000000"
        profile.yearOfIncorporation = 1994
        profile.registeredAddress = "Example Industrial Estate, Hosur, Tamil Nadu"
        profile.corporateAddress = "Example Tech Park, Bengaluru, Karnataka"
        profile.email = "sustainability@example.com"
        profile.phone = "+91 00000 00000"
        profile.website = "https://example.com"
        profile.stockExchanges = "BSE, NSE"
        profile.paidUpCapitalCrore = 48.5
        profile.sector = .manufacturing
        profile.nicCode = "22207"
        profile.isListed = true
        profile.marketCapRank = 640
        profile.contactName = "Head of Sustainability (example)"
        profile.contactRole = "Head of Sustainability"
        profile.contactEmail = "sustainability@example.com"
        engagement.profile = profile

        var team = EngagementTeam()
        team.consultingFirm = "Example Advisory LLP"
        team.engagementLead = "Engagement Lead (example)"
        team.preparer = user
        team.reviewer = "Reviewer (example)"
        team.approver = "Chief Financial Officer (example)"
        team.boardCommittee = "Risk Management Committee"
        team.assuranceProvider = "Example Assurance & Co."
        team.assuranceLevel = .reasonable
        engagement.team = team

        // Values: (id, current, prior, status, source, method)
        let reviewer = team.reviewer
        func put(_ id: String, _ current: Double?, _ prior: Double?, _ status: WorkflowStatus,
                 source: String = "", method: String = "", owner: String = "") {
            var entry = MetricEntry()
            entry.current = current
            entry.prior = prior
            entry.status = status
            entry.source = source
            entry.method = method
            entry.owner = owner
            entry.updatedBy = user
            entry.updatedAt = today
            if status == .approved {
                entry.approvedBy = reviewer
                entry.approvedAt = today
            }
            engagement.metrics[id] = entry
        }

        // Financials
        put(MetricID.revenue, 2_450, 2_210, .approved, source: "Audited standalone P&L", owner: "Finance")
        put(MetricID.pppRate, 21.0, nil, .readyForReview, source: "IMF PPP conversion rate (illustrative value — replace with the current figure)", owner: "Finance")
        put(MetricID.output, 98_000, 90_400, .approved, source: "Production MIS (net good parts shipped)", owner: "Operations")
        var unit = MetricEntry()
        unit.text = "tonnes of moulded and printed parts"
        unit.status = .approved
        unit.approvedBy = reviewer
        engagement.metrics[MetricID.outputUnit] = unit
        put(MetricID.totalWages, 310, 285, .approved, source: "Payroll register", owner: "HR")
        put("fin.accountsPayable", 412, 388, .approved, source: "Audited balance sheet", owner: "Finance")
        put("fin.purchaseCost", 1_630, 1_505, .approved, source: "Audited financial statements", owner: "Finance")

        // GHG and energy
        put(MetricID.scope1, 4_100, 4_350, .approved, source: "Fuel purchase register (diesel gensets, LPG), refrigerant log",
            method: "Fuel (GJ) × IPCC 2006 default factors; chiller refrigerant top-ups × AR6 GWPs.", owner: "EHS")
        put(MetricID.scope2, 31_800, 30_900, .readyForReview, source: "DISCOM electricity bills",
            method: "Grid kWh × CEA weighted-average factor (location-based).", owner: "EHS")
        put(MetricID.scope3, 142_500, nil, .inProgress, source: "Supplier spend and logistics data",
            method: "Polymer resin purchases × cradle-to-gate factors for category 1; distance-based for categories 4 and 9.", owner: "Sustainability")
        var categories = MetricEntry()
        categories.text = "1 Purchased goods and services (resins, additives); 4 Upstream transport; 9 Downstream transport"
        categories.status = .inProgress
        engagement.metrics["ghg.scope3Categories"] = categories
        put(MetricID.electricityRenewable, 21_600, 14_400, .approved, source: "Open-access solar PPA invoices", owner: "Energy")
        put("energy.renewableFuel", 0, 0, .approved, source: "No renewable fuel used", owner: "Energy")
        put("energy.renewableOther", 0, 0, .approved, owner: "Energy")
        put(MetricID.electricityNonRenewable, 157_500, 152_600, .readyForReview, source: "DISCOM bills", owner: "Energy")
        put("energy.nonRenewableFuel", 58_000, 61_500, .approved, source: "Fuel purchase register (diesel, LPG)", owner: "Energy")
        put("energy.nonRenewableOther", 0, 0, .approved, owner: "Energy")

        // Water and waste
        put("water.surface", 0, 0, .approved, owner: "EHS")
        put("water.ground", 182_000, 191_500, .approved, source: "Borewell flow meters (process cooling towers)", owner: "EHS")
        put("water.thirdParty", 64_500, 60_200, .approved, source: "Municipal bills", owner: "EHS")
        put("water.seawater", 0, 0, .approved, owner: "EHS")
        put("water.other", 8_200, 6_900, .approved, source: "Rainwater harvesting meter", owner: "EHS")
        put(MetricID.waterConsumption, 196_300, 205_800, .readyForReview, source: "Flow meters",
            method: "Withdrawal minus discharge.", owner: "EHS")
        put("water.dischargeUntreated", 0, 0, .approved, owner: "EHS")
        put("water.dischargePrimary", 0, 0, .approved, owner: "EHS")
        put("water.dischargeSecondary", 41_200, 38_900, .inProgress, source: "ETP outlet meter",
            method: "To municipal sewer after secondary treatment.", owner: "EHS")
        put("water.dischargeTertiary", 17_200, 13_900, .inProgress, source: "STP outlet meter", owner: "EHS")
        put("waste.plastic", 420, 465, .approved, source: "Moulding rejects and purge to authorised recyclers (manifests)", owner: "EHS")
        put("waste.eWaste", 12, 9.5, .approved, owner: "EHS")
        put("waste.bioMedical", 0.4, 0.4, .approved, owner: "EHS")
        put("waste.constructionDemolition", 140, 65, .inProgress, owner: "EHS")
        put("waste.battery", 3.2, 2.8, .approved, owner: "EHS")
        put("waste.radioactive", 0, 0, .approved, owner: "EHS")
        put("waste.otherHazardous", 610, 655, .approved, source: "Form 4 returns (used oil, spent resin powder, solvent wipes)", owner: "EHS")
        put("waste.otherNonHazardous", 4_820, 4_510, .readyForReview, source: "Scrap sales register (packaging, metal, wood)", owner: "EHS")
        put("waste.recycled", 4_744, 4_493, .readyForReview, owner: "EHS")
        put("waste.reused", 120, 110, .approved, owner: "EHS")
        put("waste.otherRecovery", 380, 350, .approved, method: "Co-processing in cement kilns.", owner: "EHS")
        put("waste.incinerated", 12, 11, .approved, owner: "EHS")
        put("waste.landfilled", 640, 690, .approved, owner: "EHS")
        put("waste.otherDisposal", 0, 0, .approved, owner: "EHS")
        put("air.nox", 14, 15, .approved, source: "SPCB returns (DG set stacks)", owner: "EHS")
        put("air.sox", 6, 7, .approved, source: "SPCB returns (DG set stacks)", owner: "EHS")
        put("air.pm", 9, 10, .approved, source: "SPCB returns (DG sets, powder handling)", owner: "EHS")

        // People
        put("safety.wellbeingSpend", 18.4, 15.9, .approved, source: "Insurance premiums, crèche invoices", owner: "HR")
        put("safety.lostTimeInjuries", 9, 13, .approved, source: "Incident register", owner: "EHS")
        put("safety.hoursWorked", 14_200_000, 13_600_000, .approved, source: "Attendance system", owner: "HR")
        put("safety.fatalities", 0, 0, .approved, owner: "EHS")
        put("safety.permanentDisabilities", 1, 0, .readyForReview, owner: "EHS")
        put("workforce.employeesMale", 2_140, 2_050, .approved, owner: "HR")
        put("workforce.employeesFemale", 410, 362, .approved, owner: "HR")
        put("workforce.workersMale", 3_860, 3_790, .approved, owner: "HR")
        put("workforce.workersFemale", 520, 455, .approved, owner: "HR")
        put("workforce.boardSize", 10, 10, .approved, owner: "Secretarial")
        put("workforce.womenOnBoard", 2, 2, .approved, owner: "Secretarial")
        put("workforce.employeeTurnover", 11.5, 12.8, .inProgress, owner: "HR")
        put("gender.femaleWages", 41.2, 34.6, .approved, source: "Payroll register", owner: "HR")
        put("gender.poshComplaints", 3, 2, .approved, source: "Internal Committee records", owner: "HR")
        put("gender.femaleHeadcount", 930, 817, .approved, owner: "HR")
        put("gender.poshUpheld", 1, 1, .approved, owner: "HR")
        put("inclusion.msmeSourcing", 22.5, 19.8, .readyForReview, source: "Vendor master (Udyam numbers)", owner: "Procurement")
        put("inclusion.indiaSourcing", 81, 79, .approved, owner: "Procurement")
        put("inclusion.smallerTownWages", 34, 33, .notStarted, owner: "HR")
        put("fairness.dataBreachShare", 0, 0, .approved, source: "IT security incident log", owner: "IT")
        put("openness.tradingHousePurchases", 6.5, 7.1, .approved, owner: "Procurement")
        put("openness.tradingHouseCount", 14, 15, .approved, owner: "Procurement")
        put("openness.top10TradingHouses", 88, 86, .approved, owner: "Procurement")
        put("openness.dealerSales", 41, 39, .approved, owner: "Sales")
        put("openness.dealerCount", 220, 208, .approved, owner: "Sales")
        put("openness.top10Dealers", 37, 36, .approved, owner: "Sales")
        put("openness.rptPurchases", 4.2, 4.6, .approved, source: "Audited RPT note", owner: "Finance")
        put("openness.rptSales", 2.1, 2.3, .approved, source: "Audited RPT note", owner: "Finance")
        put("openness.rptLoans", 0, 0, .approved, owner: "Finance")
        put("openness.rptInvestments", 9.6, 10.2, .approved, owner: "Finance")

        // IFRS S2 cross-industry metrics
        put("s2.transitionVulnerableAmount", 310, nil, .inProgress, method: "Revenue from single-use packaging parts exposed to plastic bans and EPR costs.", owner: "Strategy")
        put("s2.transitionVulnerableShare", 12.6, nil, .inProgress, owner: "Strategy")
        put("s2.opportunityAlignedAmount", 145, nil, .inProgress, method: "Revenue from recycled-content parts and 3D-printed lightweight components.", owner: "Strategy")
        put("s2.opportunityAlignedShare", 5.9, nil, .inProgress, owner: "Strategy")
        put("s2.capitalDeployed", 62, nil, .readyForReview, method: "Solar PPA, servo-drive retrofits on moulding machines and a recycled-polymer line.", owner: "Finance")
        var carbonPrice = MetricEntry()
        carbonPrice.notApplicable = true
        carbonPrice.notApplicableReason = "No internal carbon price is used yet."
        carbonPrice.status = .approved
        carbonPrice.approvedBy = reviewer
        engagement.metrics["s2.internalCarbonPrice"] = carbonPrice
        put("s2.remunerationLinkedShare", 5, nil, .inProgress, owner: "HR")

        // Narratives
        func write(_ id: String, _ text: String, _ status: WorkflowStatus, covered: Set<Int>) {
            var entry = NarrativeEntry()
            entry.text = text
            entry.status = status
            entry.coveredElements = covered
            entry.updatedBy = user
            entry.updatedAt = today
            if status == .approved { entry.approvedBy = reviewer; entry.approvedAt = today }
            engagement.narratives[id] = entry
        }
        write("s2.gov.board", "The Board oversees climate-related risks and opportunities through its Risk Management Committee, whose terms of reference were updated to include climate. The Committee receives a climate risk update each quarter from the Chief Sustainability Officer and reviews progress on emission-reduction targets twice a year. Climate considerations are included in the review of capital projects above ₹25 crore.",
              .approved, covered: [0, 2, 3, 4])
        write("brsr.a.business", "Injection-moulded and 3D-printed (additive manufacturing) polymer components for automotive, electrical and medical-device customers (NIC 22207), about 90% of turnover. Mould design and tooling services make up the rest.",
              .approved, covered: [0, 1])
        write("brsr.b.director", "This year we doubled renewable electricity through an open-access solar agreement and cut our lost-time injury rate by a third. Our main challenge is the electricity use of moulding machines, dryers and powder-bed printers; we have set a target to source 30% of electricity from renewables by FY 2027-28.",
              .readyForReview, covered: [0, 1, 2])

        // Risks and opportunities
        func issue(_ title: String, _ type: IssueType, _ topic: IssueTopic, _ horizon: TimeHorizon, likelihood: Int, impact: Int,
                   rationale: String, approach: String, implication: FinancialImplication) -> MaterialIssue {
            var issue = MaterialIssue()
            issue.title = title
            issue.type = type
            issue.topic = topic
            issue.horizon = horizon
            issue.likelihood = likelihood
            issue.impact = impact
            issue.rationale = rationale
            issue.approach = approach
            issue.implication = implication
            return issue
        }
        engagement.issues = [
            issue("Carbon pricing and energy-efficiency regulation", .risk, .transitionPolicy, .medium, likelihood: 3, impact: 4,
                  rationale: "India's carbon credit trading scheme may extend to plastics processing; electricity is 9% of cost.",
                  approach: "Energy-efficiency programme; renewable PPA; monitoring CCTS developments.", implication: .negative),
            issue("Plastic regulation: single-use bans and Extended Producer Responsibility", .risk, .transitionPolicy, .short,
                  likelihood: 4, impact: 3,
                  rationale: "Packaging parts face bans on listed single-use items and EPR obligations passed on by brand-owner customers.",
                  approach: "Shift packaging lines to reusable and recycled-content designs; track EPR costs per customer.", implication: .negative),
            issue("Flooding at the Hosur and Chennai plants", .risk, .physicalAcute, .short, likelihood: 3, impact: 4,
                  rationale: "Two plants lie in flood-prone zones; 2023 floods halted one line for nine days.",
                  approach: "Raised critical equipment; flood insurance; business continuity plan.", implication: .negative),
            issue("Demand for recycled-content and lightweight parts", .opportunity, .transitionMarket, .medium, likelihood: 4, impact: 3,
                  rationale: "Automotive and electronics customers set recycled-content and weight-reduction targets for suppliers.",
                  approach: "Recycled-polymer compounding line and additive manufacturing for lightweight, low-volume parts.", implication: .positive),
            issue("Groundwater stress", .risk, .physicalChronic, .long, likelihood: 3, impact: 3,
                  rationale: "Plants draw 71% of water from borewells in water-stressed districts.",
                  approach: "Rainwater harvesting and tertiary treatment for reuse.", implication: .negative),
            issue("Worker health and safety", .risk, .social, .short, likelihood: 2, impact: 4,
                  rationale: "Moulding machines, hot runners and polymer powder handling in 3D printing carry injury and dust risks.",
                  approach: "ISO 45001 system; machine guarding audits; dust extraction on printer rooms; contractor safety training.", implication: .negative),
        ]

        var flood = PhysicalRiskAssessment()
        flood.hazard = .flood
        flood.scenario = "1-in-100-year flood, current climate"
        flood.horizon = "Short term (to 2030)"
        flood.assetsAssessed = 6
        flood.valueAssessedCrore = 1_840
        flood.valueVulnerableCrore = 260
        flood.grossLossCrore = 38
        flood.insuredLossCrore = 9
        flood.notes = "Illustrative assessment."
        engagement.physicalRisks = [flood]

        // Section B
        engagement.policies = BRSRPrinciple.allCases.map { principle in
            var policy = PrinciplePolicy(principle: principle.rawValue)
            if principle == .p7 {
                policy.hasPolicy = .no
                policy.reasonIfNoPolicy = "Advocacy is limited to industry associations; a policy is planned for next year."
            } else {
                policy.hasPolicy = .yes
                policy.boardApproved = .yes
                policy.translatedToProcedures = .yes
                policy.extendsToValueChain = principle == .p6 || principle == .p1 ? .yes : .no
                policy.webLink = "https://example.com/policies"
            }
            return policy
        }
        engagement.governance.highestAuthority = "Managing Director (example)"
        engagement.governance.hasSustainabilityCommittee = .yes
        engagement.governance.committeeDetails = "Risk Management Committee, chaired by an independent director."
        engagement.governance.reviewFrequency = "Half-yearly by the Committee; annually by the Board."

        // Evidence
        var bills = EvidenceItem(title: "DISCOM electricity bills (12 months)", kind: .invoice, location: "")
        bills.period = engagement.periodLabel
        var fuel = EvidenceItem(title: "Fuel purchase register", kind: .register, location: "")
        fuel.period = engagement.periodLabel
        fuel.verified = true
        fuel.verifiedBy = reviewer
        var payroll = EvidenceItem(title: "Payroll register extract", kind: .register, location: "")
        payroll.period = engagement.periodLabel
        engagement.evidence = [bills, fuel, payroll]
        engagement.metrics[MetricID.scope2]?.evidenceIDs = [bills.id]
        engagement.metrics[MetricID.electricityNonRenewable]?.evidenceIDs = [bills.id]
        engagement.metrics[MetricID.scope1]?.evidenceIDs = [fuel.id]
        engagement.metrics["energy.nonRenewableFuel"]?.evidenceIDs = [fuel.id]
        engagement.metrics[MetricID.totalWages]?.evidenceIDs = [payroll.id]
        engagement.metrics["gender.femaleWages"]?.evidenceIDs = [payroll.id]

        engagement.appendActivity(ActivityEvent(date: today, user: user, action: "Loaded example engagement",
                                                target: engagement.periodLabel, detail: "Illustrative data"))
        return engagement
    }
}
