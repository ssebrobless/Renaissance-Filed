import Testing
import Foundation
@testable import RenaissanceLedger

/// QuickBooks Journal CSV transaction import (issue #4, Phase B) + the reconciliation check.
@Suite("QuickBooks Journal import")
struct JournalImportTests {

    /// A QuickBooks "Journal" report exported to CSV, including the title rows QB prepends.
    static let sampleJournal = """
    "My Company"
    "Journal"
    "January 1 - December 31, 2026"
    ""
    "Trans #","Type","Date","Num","Name","Memo","Account","Debit","Credit"
    "1","Invoice","01/15/2026","1001","Acme Co","","Accounts Receivable","1,000.00",""
    "1","Invoice","01/15/2026","1001","Acme Co","Tile work","Consulting Income","","1,000.00"
    "2","Check","01/20/2026","5001","Staples","Supplies","Office Supplies","150.00",""
    "2","Check","01/20/2026","5001","Staples","","Business Checking","","150.00"
    """

    private func seededDB() throws -> SQLiteDatabase {
        let db = try TestDB.make()
        _ = try QuickBooksIIFImportService.importIIF(IIFImportTests.sampleIIF, into: db)  // chart first
        return db
    }

    @Test("Imports a QuickBooks Journal CSV as balanced ledger entries")
    func importsJournal() throws {
        let db = try seededDB()
        let summary = try QuickBooksJournalImportService.importJournalCSV(Self.sampleJournal, into: db)
        #expect(summary.transactions == 2)
        #expect(summary.lines == 4)
        #expect(summary.balancingPlug == 0)   // each QuickBooks transaction already balances

        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 1000)
        #expect(try db.ledgerBalance(named: "Consulting Income") == -1000)
        #expect(try db.ledgerBalance(named: "Office Supplies") == 150)
        #expect(try db.ledgerBalance(named: "Business Checking") == -150)

        let totals = try db.trialBalanceTotals()
        #expect(abs(totals.debits - totals.credits) < 0.005)
    }

    @Test("Imported history survives a rebuildJournal (kind qb_import is preserved)")
    func importSurvivesRebuild() throws {
        let db = try seededDB()
        _ = try QuickBooksJournalImportService.importJournalCSV(Self.sampleJournal, into: db)
        let before = try db.ledgerBalance(named: "Accounts Receivable")
        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == before)
    }

    @Test("Re-importing replaces the prior import rather than duplicating it")
    func reImportReplaces() throws {
        let db = try seededDB()
        _ = try QuickBooksJournalImportService.importJournalCSV(Self.sampleJournal, into: db)
        _ = try QuickBooksJournalImportService.importJournalCSV(Self.sampleJournal, into: db)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 1000)   // not 2000
    }

    @Test("Reconciliation check confirms (or flags) whether imported balances match QuickBooks")
    func reconciliationCheck() throws {
        let db = try seededDB()
        _ = try QuickBooksJournalImportService.importJournalCSV(Self.sampleJournal, into: db)

        let match = try QuickBooksJournalImportService.reconcile(
            accountNamed: "Business Checking", expected: -150, in: db)
        #expect(match.matches)
        #expect(match.difference == 0)

        let mismatch = try QuickBooksJournalImportService.reconcile(
            accountNamed: "Business Checking", expected: 500, in: db)
        #expect(!mismatch.matches)
        #expect(mismatch.difference == -650)   // actual -150 vs expected 500
    }

    @Test("A QuickBooks report's title rows are trimmed to the real column header")
    func trimsTitleRows() throws {
        let trimmed = QuickBooksJournalImportService.trimmedToHeader(Self.sampleJournal)
        #expect(trimmed.hasPrefix("\"Trans #\""))
    }

    /// QuickBooks caps a Journal export, so a long history is exported in chunks. Two chunks —
    /// each restarting Trans # at 1, the way QuickBooks numbers a fresh export.
    static let chunkOne = """
    "Trans #","Type","Date","Num","Name","Memo","Account","Debit","Credit"
    "1","Invoice","01/15/2026","1001","Acme Co","","Accounts Receivable","1,000.00",""
    "1","Invoice","01/15/2026","1001","Acme Co","","Consulting Income","","1,000.00"
    """
    static let chunkTwo = """
    "Trans #","Type","Date","Num","Name","Memo","Account","Debit","Credit"
    "1","Check","02/20/2026","5001","Staples","","Office Supplies","200.00",""
    "1","Check","02/20/2026","5001","Staples","","Business Checking","","200.00"
    """

    @Test("Chunked Journal files import together, later chunks not overwriting earlier ones")
    func chunkedImportKeepsAllChunks() throws {
        let db = try seededDB()
        let summary = try QuickBooksJournalImportService.importJournalCSVFiles([Self.chunkOne, Self.chunkTwo], into: db)

        // Both transactions survive even though each chunk reuses Trans # 1.
        #expect(summary.transactions == 2)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 1000)   // from chunk 1
        #expect(try db.ledgerBalance(named: "Office Supplies") == 200)        // chunk 2 didn't wipe chunk 1
        let totals = try db.trialBalanceTotals()
        #expect(abs(totals.debits - totals.credits) < 0.005)
    }

    @Test("Re-importing the full chunk set replaces the prior import, not duplicates it")
    func chunkedReimportReplaces() throws {
        let db = try seededDB()
        _ = try QuickBooksJournalImportService.importJournalCSVFiles([Self.chunkOne, Self.chunkTwo], into: db)
        _ = try QuickBooksJournalImportService.importJournalCSVFiles([Self.chunkOne, Self.chunkTwo], into: db)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 1000)   // not 2000
        #expect(try db.ledgerBalance(named: "Office Supplies") == 200)
    }
}
