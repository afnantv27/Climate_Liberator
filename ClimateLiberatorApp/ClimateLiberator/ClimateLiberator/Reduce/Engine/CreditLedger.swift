import Foundation

/// Something a buyer, verifier or auditor would question about a credit block.
nonisolated struct CreditIssue: Hashable, Sendable {
    let creditID: UUID
    let message: String
}

/// Totals and integrity checks over a client's carbon credits.
///
/// Credits are kept beside emissions, never netted from them: BRSR and IFRS S2
/// report gross emissions, and claims built on credits must say so.
nonisolated struct CreditLedger: Sendable {
    let credits: [CarbonCredit]

    /// Vintages older than this many years at retirement are flagged for review.
    static let oldVintageYears = 5

    var held: Double { total(credits.filter { $0.status == .held }) }
    var retired: Double { total(credits.filter { $0.status == .retired }) }

    func retired(forYear year: Int) -> [CarbonCredit] {
        credits.filter { $0.status == .retired && $0.retiredForYear == year }
    }

    func retiredQuantity(forYear year: Int) -> Double { total(retired(forYear: year)) }

    /// Share of the year's retirements that are removals rather than avoidance.
    func removalShare(forYear year: Int) -> Double? {
        let all = retiredQuantity(forYear: year)
        guard all > 0 else { return nil }
        return total(retired(forYear: year).filter { $0.projectType.isRemoval }) / all
    }

    /// Retired credits for the year as a share of the year's emissions.
    func coverage(ofEmissions emissions: Double?, forYear year: Int) -> Double? {
        guard let emissions, emissions > 0 else { return nil }
        return retiredQuantity(forYear: year) / emissions
    }

    /// Money spent on credits with a price entered (₹).
    var spend: Double {
        credits.reduce(0) { $0 + ($1.unitPrice ?? 0) * $1.quantity }
    }

    var issues: [CreditIssue] {
        credits.flatMap { credit -> [CreditIssue] in
            var found: [CreditIssue] = []
            func flag(_ message: String) { found.append(CreditIssue(creditID: credit.id, message: "\(credit.displayName): \(message)")) }
            if credit.quantity <= 0 { flag("quantity is missing.") }
            if credit.status == .retired {
                if credit.retirementDate == nil { flag("retired without a retirement date.") }
                if credit.retiredForYear == nil { flag("retired without the year it is claimed against.") }
                if credit.serialNumbers.trimmingCharacters(in: .whitespaces).isEmpty { flag("no serial numbers recorded.") }
                if let year = credit.retiredForYear, year - credit.vintageYear > Self.oldVintageYears {
                    flag("vintage \(credit.vintageYear) is more than \(Self.oldVintageYears) years before the claim year; buyers often question old vintages.")
                }
            }
            if credit.status != .cancelled, credit.evidence.trimmingCharacters(in: .whitespaces).isEmpty {
                flag("no registry record or invoice linked.")
            }
            return found
        }
    }

    private func total(_ list: [CarbonCredit]) -> Double { list.reduce(0) { $0 + $1.quantity } }
}
