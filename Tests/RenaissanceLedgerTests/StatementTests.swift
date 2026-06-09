import Testing
import Foundation
@testable import RenaissanceLedger

/// Self-computed financial statements (issue #3): a Profit & Loss and a Balance Sheet
/// derived from the double-entry ledger. The Balance Sheet must balance by construction.
@Suite("Computed statements")
struct StatementTests {

    @Test("Profit & Loss equals income minus expenses over the period")
    func profitLoss() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "PL Co")
        _ = try db.saveInvoiceWithLines(
            number: "PL-1", customerID: customer, issueDate: "2026-01-15", dueDate: "2026-02-15",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        let expenseAcct = try TestDB.expenseAccountID(db)
        let bank = try TestDB.bankAccountID(db)
        _ = try db.insertExpense(
            vendorNameOverride: "Vendor", vendorID: nil, expenseDate: "2026-01-20",
            amount: 300, accountID: expenseAcct, paymentAccountID: bank,
            checkNumber: "", memo: "", jobID: nil)

        _ = try db.rebuildJournal()
        let pl = try db.computeProfitLoss(start: "2026-01-01", end: "2026-12-31")
        #expect(pl.totalIncome == 1000)
        #expect(pl.totalExpenses == 300)
        #expect(pl.netIncome == 700)
    }

    @Test("The P&L period excludes transactions outside the date range")
    func profitLossRespectsPeriod() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Period Co")
        _ = try db.saveInvoiceWithLines(
            number: "Y25", customerID: customer, issueDate: "2025-06-01", dueDate: "2025-07-01",
            memo: "", total: 5000,
            lines: [(description: "Old", quantity: 1, rate: 5000, amount: 5000)], jobID: nil)
        _ = try db.saveInvoiceWithLines(
            number: "Y26", customerID: customer, issueDate: "2026-06-01", dueDate: "2026-07-01",
            memo: "", total: 800,
            lines: [(description: "New", quantity: 1, rate: 800, amount: 800)], jobID: nil)

        _ = try db.rebuildJournal()
        let pl2026 = try db.computeProfitLoss(start: "2026-01-01", end: "2026-12-31")
        #expect(pl2026.totalIncome == 800)   // 2025 invoice excluded
    }

    @Test("Balance sheet balances: assets = liabilities + equity")
    func balanceSheetBalances() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "BS Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "BS-1", customerID: customer, issueDate: "2026-01-01", dueDate: "2026-02-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        let payment = try #require(try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-01-10", paymentAmount: 600, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 600)], creditApplications: []))
        let bank = try TestDB.bankAccountID(db)
        _ = try db.recordDeposit(paymentIDs: [payment], depositDate: "2026-01-11",
                                 destinationAccountID: bank, reference: "d", memo: "")
        let expenseAcct = try TestDB.expenseAccountID(db)
        let vendor = try db.insertVendor(name: "Vendor", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        _ = try db.insertBill(vendorNameOverride: "Vendor", vendorID: vendor, billDate: "2026-01-05",
                              dueDate: "2026-02-05", amount: 200, accountID: expenseAcct, jobID: nil, memo: "")

        _ = try db.rebuildJournal()
        let bs = try db.computeBalanceSheet(asOf: "2026-12-31")

        #expect(bs.isBalanced)
        // Assets: A/R 400 (1000−600) + bank 600 = 1000.
        #expect(bs.totalAssets == 1000)
        // Liabilities: A/P 200.
        #expect(bs.totalLiabilities == 200)
        // Equity = retained earnings = net income = income 1000 − expense 200 = 800.
        #expect(bs.totalEquity == 800)
        #expect(bs.equity.contains { $0.name == "Retained Earnings" && $0.amount == 800 })
    }
}
