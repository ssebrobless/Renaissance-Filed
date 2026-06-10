import Testing
import Foundation
@testable import RenaissanceLedger

/// Mid-year opening-balance migration (ADR-002 / issue #6): a cutover date excludes imperfect
/// pre-cutover history from the ledger, an opening-balance entry sets the true position, and
/// the computed statements tie out from the cutover forward.
@Suite("Migration backfill (cutover)")
struct MigrationBackfillTests {

    @Test("Cutover date round-trips and clears")
    func cutoverConfigRoundTrips() throws {
        let db = try TestDB.make()
        #expect(try db.ledgerCutoverDate() == nil)
        try db.setLedgerCutoverDate("2025-12-31")
        #expect(try db.ledgerCutoverDate() == "2025-12-31")
        try db.setLedgerCutoverDate(nil)
        #expect(try db.ledgerCutoverDate() == nil)
    }

    @Test("Pre-cutover transactions are excluded once a cutover is set")
    func preCutoverExcluded() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Old Co")
        let inv = try db.saveInvoiceWithLines(
            number: "OLD-1", customerID: customer, issueDate: "2025-06-01", dueDate: "2025-07-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        // Reproduce the migrated-data problem: invoice marked paid with no payment record, so a
        // rebuild has nothing crediting A/R and overstates the receivable.
        try db.updateInvoicePaidStatus(id: inv, paid: 1000)
        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 1000)   // the overstatement

        _ = try MigrationBackfillService.applyCutover(date: "2025-12-31", openingBalances: [], in: db)
        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 0)      // pre-cutover excluded
    }

    @Test("Opening balances set the cutover position and the balance sheet ties out")
    func openingBalancesTieOut() throws {
        let db = try TestDB.make()
        let result = try MigrationBackfillService.applyCutover(
            date: "2025-12-31",
            openingBalances: [
                .init("Checking Account", 5000),
                .init("Accounts Receivable", 300),
            ], in: db)
        #expect(result.applied == 2)
        #expect(result.notFound.isEmpty)

        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Checking Account") == 5000)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 300)

        let bs = try db.computeBalanceSheet(asOf: "2025-12-31")
        #expect(bs.isBalanced)
        #expect(bs.totalAssets == 5300)
        #expect(bs.totalEquity == 5300)   // Opening Balance Equity is the plug
    }

    @Test("Post-cutover activity posts on top of the opening balances")
    func postCutoverPostsOnTop() throws {
        let db = try TestDB.make()
        _ = try MigrationBackfillService.applyCutover(
            date: "2025-12-31", openingBalances: [.init("Checking Account", 5000)], in: db)
        let customer = try TestDB.customer(db, "New Co")
        _ = try db.saveInvoiceWithLines(
            number: "NEW-1", customerID: customer, issueDate: "2026-02-01", dueDate: "2026-03-01",
            memo: "", total: 800,
            lines: [(description: "Work", quantity: 1, rate: 800, amount: 800)], jobID: nil)
        _ = try db.rebuildJournal()

        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 800)   // forward invoice posts
        let bs = try db.computeBalanceSheet(asOf: "2026-03-01")
        #expect(bs.isBalanced)
        #expect(bs.totalAssets == 5800)   // 5000 opening cash + 800 new A/R
    }

    @Test("Reverting a cutover restores direct posting of all history")
    func revertRestores() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Old Co")
        _ = try db.saveInvoiceWithLines(
            number: "OLD-1", customerID: customer, issueDate: "2025-06-01", dueDate: "2025-07-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        _ = try MigrationBackfillService.applyCutover(
            date: "2025-12-31", openingBalances: [.init("Checking Account", 5000)], in: db)
        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 0)

        try MigrationBackfillService.revertCutover(in: db)
        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 1000)   // history posts again
        #expect(try db.ledgerBalance(named: "Checking Account") == 0)         // opening entry removed
    }
}
