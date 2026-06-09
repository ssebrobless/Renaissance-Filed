import Testing
import Foundation
@testable import RenaissanceLedger

/// The double-entry posting layer (ADR-001): the ledger derived from the operational
/// tables must always balance, and account balances must match the operational reality.
@Suite("Double-entry ledger")
struct LedgerTests {

    @Test("Trial balance balances and A/R, cash, and income are correct after a money-in flow")
    func moneyInLedgerBalances() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Ledger Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "L-1", customerID: customer, issueDate: "2026-01-01", dueDate: "2026-02-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        let payment = try #require(try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-01-10", paymentAmount: 600, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 600)], creditApplications: []))
        let bank = try TestDB.bankAccountID(db)
        _ = try db.recordDeposit(paymentIDs: [payment], depositDate: "2026-01-11",
                                 destinationAccountID: bank, reference: "d", memo: "")

        let totals = try db.rebuildJournal()
        #expect(abs(totals.debits - totals.credits) < 0.005)   // the fundamental invariant

        // A/R = invoiced 1000 − paid 600 = 400 (debit balance).
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 400)
        // The $600 was deposited, so Undeposited Funds nets to 0 and the bank holds 600.
        #expect(abs(try db.ledgerBalance(named: "Undeposited Funds")) < 0.005)
        #expect(try db.ledgerBalance(named: TestDB.accountName(db, id: bank)) == 600)
        // Income is recognized at invoice (credit balance, shown negative).
        #expect(try db.ledgerBalance(named: "Tile Installation Services") == -1000)
    }

    @Test("An unpaid bill posts to A/P; paying it clears A/P without double-counting expense")
    func billAccrualClearsAP() throws {
        let db = try TestDB.make()
        let vendor = try db.insertVendor(name: "Vendor X", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        let expenseAcct = try TestDB.expenseAccountID(db)
        let bill = try db.insertBill(vendorNameOverride: "Vendor X", vendorID: vendor, billDate: "2026-01-01",
                                     dueDate: "2026-01-31", amount: 200, accountID: expenseAcct, jobID: nil, memo: "")

        _ = try db.rebuildJournal()
        // Unpaid: A/P is a $200 liability (credit balance), expense recognized once.
        #expect(try db.ledgerBalance(named: "Accounts Payable") == -200)
        #expect(try db.ledgerBalance(named: TestDB.accountName(db, id: expenseAcct)) == 200)

        let bank = try TestDB.bankAccountID(db)
        try db.recordBillPayments(billIDs: [bill], paymentDate: "2026-02-01",
                                  paymentAccountID: bank, paymentMethod: "Check",
                                  startingCheckNumber: "2001", memo: "")

        let totals = try db.rebuildJournal()
        #expect(abs(totals.debits - totals.credits) < 0.005)
        // A/P cleared; expense still recognized exactly once (not doubled by the payment).
        #expect(abs(try db.ledgerBalance(named: "Accounts Payable")) < 0.005)
        #expect(try db.ledgerBalance(named: TestDB.accountName(db, id: expenseAcct)) == 200)
        // Bank reduced by the $200 check.
        #expect(try db.ledgerBalance(named: TestDB.accountName(db, id: bank)) == -200)
    }

    @Test("rebuildJournal is idempotent — running it twice yields the same balanced ledger")
    func rebuildIsIdempotent() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Idem Co")
        _ = try db.saveInvoiceWithLines(
            number: "I-1", customerID: customer, issueDate: "2026-01-01", dueDate: "2026-02-01",
            memo: "", total: 300,
            lines: [(description: "Work", quantity: 1, rate: 300, amount: 300)], jobID: nil)
        let first = try db.rebuildJournal()
        let second = try db.rebuildJournal()
        #expect(first.debits == second.debits)
        #expect(first.credits == second.credits)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 300)
    }
}
