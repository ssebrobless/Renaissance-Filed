import Testing
import Foundation
@testable import RenaissanceLedger

/// Live inline posting (issue #2): each operational write posts its own balanced ledger entry
/// as it happens, so the ledger is continuously correct without an on-demand rebuild — and a
/// rebuild produces exactly the same numbers (the rules live in one place).
@Suite("Live ledger posting")
struct LiveLedgerTests {

    /// Balance of every account, keyed by id — used to compare the live ledger to a rebuild.
    private func snapshot(_ db: SQLiteDatabase) throws -> [Int64: Double] {
        var m: [Int64: Double] = [:]
        for a in try db.fetchAccounts() { m[a.id] = try db.ledgerAccountBalance(a.id) }
        return m
    }

    @Test("After a full round of operations the ledger is already correct — no rebuild needed")
    func liveLedgerIsCorrectWithoutRebuild() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Live Co")
        let bank = try TestDB.bankAccountID(db)
        let expenseAcct = try TestDB.expenseAccountID(db)

        let invoice = try db.saveInvoiceWithLines(
            number: "L-1", customerID: customer, issueDate: "2026-01-01", dueDate: "2026-02-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        let payment = try #require(try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-01-10", paymentAmount: 600, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 600)], creditApplications: []))
        _ = try db.recordDeposit(paymentIDs: [payment], depositDate: "2026-01-11",
                                 destinationAccountID: bank, reference: "d", memo: "")
        _ = try db.insertExpense(
            vendorNameOverride: "Direct", vendorID: nil, expenseDate: "2026-01-15",
            amount: 200, accountID: expenseAcct, paymentAccountID: bank,
            checkNumber: "", memo: "", jobID: nil)
        let vendor = try db.insertVendor(name: "BillVendor", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        let bill = try db.insertBill(vendorNameOverride: "BillVendor", vendorID: vendor,
                                     billDate: "2026-01-05", dueDate: "2026-02-05", amount: 300,
                                     accountID: expenseAcct, jobID: nil, memo: "")
        try db.recordBillPayments(billIDs: [bill], paymentDate: "2026-01-20", paymentAccountID: bank,
                                  paymentMethod: "Check", startingCheckNumber: "1001", memo: "")

        // No rebuildJournal() call — assert the live-posted ledger is already right.
        let tb = try db.trialBalanceTotals()
        #expect(abs(tb.debits - tb.credits) < 0.005)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 400)   // 1000 − 600
        #expect(try db.ledgerBalance(named: "Undeposited Funds") == 0)       // 600 in, 600 out
        #expect(try db.ledgerBalance(named: "Accounts Payable") == 0)        // bill 300, paid 300
    }

    @Test("The live ledger matches a full rebuild account-for-account")
    func liveLedgerEqualsRebuild() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Equiv Co")
        let bank = try TestDB.bankAccountID(db)
        let expenseAcct = try TestDB.expenseAccountID(db)

        let invoice = try db.saveInvoiceWithLines(
            number: "E-1", customerID: customer, issueDate: "2026-02-01", dueDate: "2026-03-01",
            memo: "", total: 1500,
            lines: [(description: "Work", quantity: 1, rate: 1500, amount: 1500)], jobID: nil)
        let payment = try #require(try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-02-10", paymentAmount: 900, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 900)], creditApplications: []))
        _ = try db.recordDeposit(paymentIDs: [payment], depositDate: "2026-02-11",
                                 destinationAccountID: bank, reference: "d", memo: "")
        let vendor = try db.insertVendor(name: "V", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        let bill = try db.insertBill(vendorNameOverride: "V", vendorID: vendor,
                                     billDate: "2026-02-05", dueDate: "2026-03-05", amount: 400,
                                     accountID: expenseAcct, jobID: nil, memo: "")
        try db.recordBillPayments(billIDs: [bill], paymentDate: "2026-02-20", paymentAccountID: bank,
                                  paymentMethod: "Check", startingCheckNumber: "2001", memo: "")

        let live = try snapshot(db)
        _ = try db.rebuildJournal()
        let rebuilt = try snapshot(db)

        #expect(live.count == rebuilt.count)
        for (id, balance) in rebuilt {
            #expect(abs((live[id] ?? .nan) - balance) < 0.005)
        }
    }

    @Test("Editing and deleting reflect in the ledger immediately")
    func liveEditAndDelete() throws {
        let db = try TestDB.make()
        let bank = try TestDB.bankAccountID(db)
        let acct = try TestDB.expenseAccountID(db)

        let id = try db.insertExpense(
            vendorNameOverride: "V", vendorID: nil, expenseDate: "2026-03-01",
            amount: 100, accountID: acct, paymentAccountID: bank, checkNumber: "", memo: "", jobID: nil)
        #expect(try db.ledgerAccountBalance(acct) == 100)

        try db.updateExpense(
            id: id, vendorNameOverride: "V", vendorID: nil, expenseDate: "2026-03-01",
            amount: 250, accountID: acct, paymentAccountID: bank, checkNumber: "", memo: "", jobID: nil)
        #expect(try db.ledgerAccountBalance(acct) == 250)   // edited amount, no rebuild

        try db.deleteExpense(id: id)
        #expect(try db.ledgerAccountBalance(acct) == 0)     // lines cleared on delete
    }
}
