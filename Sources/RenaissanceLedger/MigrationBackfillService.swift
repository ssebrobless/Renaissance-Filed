import Foundation

/// Mid-year opening-balance migration (ADR-002). Rebuilding the ledger from imperfect migrated
/// history doesn't tie out, so instead we draw a cutover line: operational activity on or before
/// the cutover date is captured by a one-time opening-balance entry rather than posted
/// transaction-by-transaction, and everything after it posts normally. From the cutover forward
/// the computed statements are correct by construction.
///
/// The opening balances come from a trusted source — the last reconciled statement or the
/// QuickBooks Balance Sheet — not from the migrated transactions. Each is recorded against
/// Opening Balance Equity (reusing `OnboardingService.recordOpeningBalance`), so the equity side
/// is the running plug that makes the books balance.
enum MigrationBackfillService {

    /// One account's opening position as a **signed ledger balance** (debit − credit): positive
    /// for a normal debit balance (assets, expenses; e.g. a bank account), negative for a normal
    /// credit balance (liabilities, equity, income). A QuickBooks payable shown as a negative
    /// liability (vendor credits) is a net debit, so it's positive here.
    struct OpeningBalance {
        let accountName: String
        let signedBalance: Double
        init(_ accountName: String, _ signedBalance: Double) {
            self.accountName = accountName
            self.signedBalance = signedBalance
        }
    }

    struct Result {
        var applied = 0       // opening balances recorded
        var notFound: [String] = []   // account names that don't exist (skipped)
    }

    /// Set the cutover date and record the opening balances as of it. Idempotent: re-running
    /// replaces the cutover and each account's opening entry rather than stacking. Reversible —
    /// call `revertCutover` to clear it. Accounts that don't exist are reported, not created
    /// (set up the chart first, e.g. via a template or an import).
    @discardableResult
    static func applyCutover(date: String,
                             openingBalances: [OpeningBalance],
                             in db: SQLiteDatabase) throws -> Result {
        try db.setLedgerCutoverDate(date)
        var result = Result()
        for ob in openingBalances {
            let ok = try OnboardingService.recordOpeningBalance(
                accountNamed: ob.accountName, amount: ob.signedBalance, asOf: date, in: db)
            if ok { result.applied += 1 } else { result.notFound.append(ob.accountName) }
        }
        return result
    }

    /// Undo a cutover migration: clear the cutover date and remove every opening-balance entry,
    /// returning the ledger to posting all history directly. A `rebuildJournal` afterward restores
    /// the pre-cutover derived ledger.
    static func revertCutover(in db: SQLiteDatabase) throws {
        try db.setLedgerCutoverDate(nil)
        try db.deleteJournalEntries(kind: "opening")
    }
}
