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
        #expect(QuickBooksIIFImportService.mappedAccountType("EXEXP") == "expense")   // Other Expense
        #expect(QuickBooksIIFImportService.mappedAccountType("EXINC") == "income")    // Other Income
        #expect(QuickBooksIIFImportService.mappedAccountType("SOMETHING_NEW") == "asset")
    }

    /// A realistic export modeled on a full QuickBooks "Lists to IIF" file (synthetic data,
    /// real structure): the `!HDR` metadata row, the wide real `!ACCNT` column layout with
    /// ACCNTTYPE/ACCNUM far from the front, non-posting accounts, an "Other Expense" (EXEXP)
    /// account, and the grouped `!INVITEM` / `!ENDGRP` blocks that must not derail parsing.
    static let realisticIIF = """
    !HDR\tPROD\tVER\tREL\tIIFVER\tDATE\tTIME
    HDR\tQuickBooks\tVersion 24.0\tR5\t1\t03/09/2026\t21:47
    !ACCNT\tNAME\tREFNUM\tTIMESTAMP\tACCNTTYPE\tOBAMOUNT\tDESC\tACCNUM\tSCD\tEXTRA
    ACCNT\tSample Operating\t1\t0\tBANK\t0\tOperating account\t1000\t\t
    ACCNT\tSample Fuel\t2\t0\tEXEXP\t0\tOther vehicle expense\t6500\t\t
    ACCNT\tSample Materials\t3\t0\tCOGS\t0\t\t5000\t\t
    ACCNT\tEstimates\t4\t0\tNONPOSTING\t0\t\t0\t\t
    ACCNT\tPurchase Orders\t5\t0\tNONPOSTING\t0\t\t0\t\t
    !INVITEM\tNAME\tREFNUM\tTIMESTAMP\tINVITEMTYPE\tDESC\tPURCHASEDESC\tACCNT
    INVITEM\tSome Service\t10\t0\tSERV\twork\t\tSample Operating
    !INVITEM\tNAME\tREFNUM\tTIMESTAMP\tINVITEMTYPE\tDESC\tTOPRINT\tEXTRA\tQNTY
    !ENDGRP
    !CUST\tNAME\tREFNUM\tTIMESTAMP\tBADDR1\tPHONE1\tEMAIL\tCONT1\tCOMPANYNAME
    CUST\tSample Customer\t20\t0\t123 Main\t555-1000\tcust@example.com\tPat\tSample Co
    !VEND\tNAME\tREFNUM\tTIMESTAMP\tPRINTAS\tADDR1\tPHONE1\tEMAIL\tTAXID\tCOMPANYNAME\t1099
    VEND\tSample Vendor\t30\t0\tSample Vendor\t1 Vendor Rd\t555-2000\tvend@example.com\t12-3456789\tSample Vendor LLC\tY
    """

    @Test("A realistic full-format export imports cleanly, skipping non-posting accounts")
    func realisticExportImports() throws {
        let db = try TestDB.make()
        let summary = try QuickBooksIIFImportService.importIIF(Self.realisticIIF, into: db)

        // Three real accounts import; the two NONPOSTING accounts are skipped.
        #expect(summary.accounts == 3)
        #expect(summary.skipped >= 2)
        let accounts = try db.fetchAccounts()
        #expect(!accounts.contains { $0.name == "Estimates" })
        #expect(!accounts.contains { $0.name == "Purchase Orders" })

        // Columns are read by header name despite the wide real layout.
        #expect(accounts.contains { $0.name == "Sample Operating" && $0.type == "asset" && $0.number == "1000" })
        #expect(accounts.contains { $0.name == "Sample Fuel" && $0.type == "expense" })   // EXEXP → expense

        // The HDR / INVITEM / ENDGRP noise doesn't derail customers and vendors.
        #expect(try db.fetchCustomers().contains { $0.name == "Sample Customer" })
        let vendor = try #require(try db.fetchVendors().first { $0.name == "Sample Vendor" })
        #expect(vendor.is1099)
    }

    @Test("Re-importing a realistic export skips everything (idempotent on real-shaped data)")
    func realisticReimportIsIdempotent() throws {
        let db = try TestDB.make()
        _ = try QuickBooksIIFImportService.importIIF(Self.realisticIIF, into: db)
        let second = try QuickBooksIIFImportService.importIIF(Self.realisticIIF, into: db)
        #expect(second.accounts == 0)
        #expect(second.customers == 0)
        #expect(second.vendors == 0)
    }

    /// QuickBooks CSV-style quotes any field containing a comma (e.g. "Lastname, Firstname"
    /// names and "City, ST ZIP" addresses). Those quotes must be stripped, or the imported
    /// name carries the quotes and never matches the same customer entered without them.
    static let quotedIIF = """
    !CUST\tNAME\tREFNUM\tTIMESTAMP\tBADDR1\tBADDR2\tPHONE1\tCOMPANYNAME
    CUST\t"Ables, Ed"\t1\t0\t123 Main St\t"Nokesville, VA 20181"\t555-1000\tAbles Construction
    """

    @Test("QuickBooks field quotes are stripped from imported values")
    func stripsQuotedFields() throws {
        // The raw value keeps its quotes; unquote removes them and unescapes doubled quotes.
        #expect(QuickBooksIIFImportService.unquote("\"Ables, Ed\"") == "Ables, Ed")
        #expect(QuickBooksIIFImportService.unquote("\"a \"\"b\"\" c\"") == "a \"b\" c")
        #expect(QuickBooksIIFImportService.unquote("Plain") == "Plain")

        let db = try TestDB.make()
        _ = try QuickBooksIIFImportService.importIIF(Self.quotedIIF, into: db)
        // Imported under the clean, unquoted name — not "\"Ables, Ed\"".
        #expect(try db.fetchCustomers().contains { $0.name == "Ables, Ed" })
        #expect(try !db.fetchCustomers().contains { $0.name.hasPrefix("\"") })
    }

    @Test("A customer already present unquoted is not re-added from a quoted export")
    func quotedNameDedupesAgainstUnquoted() throws {
        let db = try TestDB.make()
        // The customer already exists, entered normally (no quotes), as if from a prior migration.
        _ = try db.insertCustomer(name: "Ables, Ed", company: "", primaryContact: "",
                                  email: "", phone: "", address: "", city: "", state: "", zip: "")
        // Importing the quoted export must recognize it as the same customer and skip it.
        let summary = try QuickBooksIIFImportService.importIIF(Self.quotedIIF, into: db)
        #expect(summary.customers == 0)
        #expect(summary.skipped >= 1)
        #expect(try db.fetchCustomers().filter { $0.name.contains("Ables") }.count == 1)
    }
}
