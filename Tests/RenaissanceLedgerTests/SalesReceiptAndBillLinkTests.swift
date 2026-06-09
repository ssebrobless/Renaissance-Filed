import Testing
import Foundation
@testable import RenaissanceLedger

/// Deeper posting correctness (issue #2): a sales receipt is a cash sale that earns income
/// directly (no receivable), and a bill payment settles Accounts Payable via a real link
/// rather than a memo-text guess.
@Suite("Sales receipts & bill-payment links")
struct SalesReceiptAndBillLinkTests {

    @Test("A sales receipt books cash as income, not a receivable")
    func salesReceiptIsIncomeNotReceivable() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Counter Customer")

        _ = try db.saveSalesReceiptWithLines(
            number: "SR-1", customerID: customer, jobID: nil, receiptDate: "2026-04-01",
            paymentMethodID: nil, depositAccountID: nil, memo: "",
            total: 500, lines: [(description: "Counter sale", quantity: 1, rate: 500, amount: 500)])

        // Live ledger — no rebuild. Cash is in Undeposited Funds; income is recognized; the
        // receivable is untouched (a sales receipt has no invoice behind it).
        #expect(try db.ledgerBalance(named: "Undeposited Funds") == 500)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 0)
        #expect(try db.ledgerBalance(named: "Tile Installation Services") == -500)

        let tb = try db.trialBalanceTotals()
        #expect(abs(tb.debits - tb.credits) < 0.005)
    }

    @Test("The sales-receipt income posting survives a rebuild unchanged")
    func salesReceiptMatchesRebuild() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Counter Customer")
        _ = try db.saveSalesReceiptWithLines(
            number: "SR-2", customerID: customer, jobID: nil, receiptDate: "2026-04-02",
            paymentMethodID: nil, depositAccountID: nil, memo: "",
            total: 750, lines: [(description: "Counter sale", quantity: 1, rate: 750, amount: 750)])

        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 0)
        #expect(try db.ledgerBalance(named: "Tile Installation Services") == -750)
        let tb = try db.trialBalanceTotals()
        #expect(abs(tb.debits - tb.credits) < 0.005)
    }

    @Test("A bill payment with a custom memo still settles A/P via the link, not the memo text")
    func billPaymentLinkSettlesAccountsPayable() throws {
        let db = try TestDB.make()
        let bank = try TestDB.bankAccountID(db)
        let expenseAcct = try TestDB.expenseAccountID(db)
        let vendor = try db.insertVendor(name: "V", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        let bill = try db.insertBill(vendorNameOverride: "V", vendorID: vendor,
                                     billDate: "2026-05-01", dueDate: "2026-06-01", amount: 300,
                                     accountID: expenseAcct, jobID: nil, memo: "")
        #expect(try db.ledgerBalance(named: "Accounts Payable") == -300)   // owed

        // Custom memo that does NOT start with "Bill payment" — the old heuristic would have
        // mistaken this for a second expense and never cleared the payable.
        try db.recordBillPayments(billIDs: [bill], paymentDate: "2026-05-15", paymentAccountID: bank,
                                  paymentMethod: "Check", startingCheckNumber: "3001", memo: "Check to vendor")

        #expect(try db.ledgerBalance(named: "Accounts Payable") == 0)       // payable cleared
        #expect(try db.ledgerAccountBalance(expenseAcct) == 300)            // expense counted once
        let tb = try db.trialBalanceTotals()
        #expect(abs(tb.debits - tb.credits) < 0.005)
    }

    @Test("The bill-payment link gives the same ledger live and after a rebuild")
    func billPaymentLinkMatchesRebuild() throws {
        let db = try TestDB.make()
        let bank = try TestDB.bankAccountID(db)
        let expenseAcct = try TestDB.expenseAccountID(db)
        let vendor = try db.insertVendor(name: "V", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        let bill = try db.insertBill(vendorNameOverride: "V", vendorID: vendor,
                                     billDate: "2026-05-01", dueDate: "2026-06-01", amount: 300,
                                     accountID: expenseAcct, jobID: nil, memo: "")
        try db.recordBillPayments(billIDs: [bill], paymentDate: "2026-05-15", paymentAccountID: bank,
                                  paymentMethod: "Check", startingCheckNumber: "3001", memo: "Custom note")

        let liveAP = try db.ledgerBalance(named: "Accounts Payable")
        let liveExpense = try db.ledgerAccountBalance(expenseAcct)
        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Payable") == liveAP)
        #expect(try db.ledgerAccountBalance(expenseAcct) == liveExpense)
    }
}
