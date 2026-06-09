import Testing
import Foundation
@testable import RenaissanceLedger

/// QuickBooks IIF list import (issue #4, Phase A): chart of accounts, customers, vendors.
@Suite("QuickBooks IIF import")
struct IIFImportTests {

    /// A small but representative QuickBooks "Lists to IIF" export (tab-separated).
    static let sampleIIF = """
    !ACCNT\tNAME\tACCNTTYPE\tACCNUM
    ACCNT\tBusiness Checking\tBANK\t1000
    ACCNT\tConsulting Income\tINC\t4000
    ACCNT\tOffice Supplies\tEXP\t6000
    ACCNT\tCredit Card\tCCARD\t2100
    !CUST\tNAME\tCOMPANYNAME\tPHONE1\tEMAIL
    CUST\tJane Smith\tSmith LLC\t555-1212\tjane@example.com
    CUST\tBob Jones\t\t\t
    !VEND\tNAME\tPHONE1\t1099
    VEND\tStaples\t555-9999\tN
    VEND\tContractor Joe\t\tY
    """

    @Test("Imports accounts, customers, and vendors with mapped account types")
    func importsLists() throws {
        let db = try TestDB.make()
        let summary = try QuickBooksIIFImportService.importIIF(Self.sampleIIF, into: db)
        #expect(summary.accounts == 4)
        #expect(summary.customers == 2)
        #expect(summary.vendors == 2)

        let accounts = try db.fetchAccounts()
        #expect(accounts.contains { $0.name == "Business Checking" && $0.type == "asset" })
        #expect(accounts.contains { $0.name == "Consulting Income" && $0.type == "income" })
        #expect(accounts.contains { $0.name == "Office Supplies" && $0.type == "expense" })
        #expect(accounts.contains { $0.name == "Credit Card" && $0.type == "liability" })

        #expect(try db.fetchCustomers().contains { $0.name == "Jane Smith" })
        #expect(try db.fetchCustomers().contains { $0.name == "Bob Jones" })
        #expect(try db.fetchVendors().contains { $0.name == "Contractor Joe" })
    }

    @Test("Re-importing the same file skips everything that already exists (idempotent)")
    func reImportSkips() throws {
        let db = try TestDB.make()
        _ = try QuickBooksIIFImportService.importIIF(Self.sampleIIF, into: db)
        let second = try QuickBooksIIFImportService.importIIF(Self.sampleIIF, into: db)
        #expect(second.accounts == 0)
        #expect(second.customers == 0)
        #expect(second.vendors == 0)
        #expect(second.skipped == 8)   // 4 accounts + 2 customers + 2 vendors, all already present
    }

    @Test("Account-type mapping covers the common QuickBooks types and never drops one")
    func accountTypeMapping() throws {
        #expect(QuickBooksIIFImportService.mappedAccountType("BANK") == "asset")
        #expect(QuickBooksIIFImportService.mappedAccountType("AR") == "asset")
        #expect(QuickBooksIIFImportService.mappedAccountType("AP") == "liability")
        #expect(QuickBooksIIFImportService.mappedAccountType("CCARD") == "liability")
        #expect(QuickBooksIIFImportService.mappedAccountType("EQUITY") == "equity")
        #expect(QuickBooksIIFImportService.mappedAccountType("inc") == "income")
        #expect(QuickBooksIIFImportService.mappedAccountType("COGS") == "expense")
        #expect(QuickBooksIIFImportService.mappedAccountType("SOMETHING_NEW") == "asset")
    }
}
