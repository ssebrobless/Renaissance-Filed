import Testing
import Foundation
@testable import RenaissanceLedger

/// Customer credits (issue #2): a credit memo applied to an invoice is a revenue reversal —
/// it reduces the receivable and backs out the income, and keeps the ledger balanced.
@Suite("Customer credits")
struct CustomerCreditTests {

    @Test("An applied customer credit reduces the receivable and reverses income")
    func appliedCreditReducesReceivable() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Credit Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "C-1", customerID: customer, issueDate: "2026-06-01", dueDate: "2026-07-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 1000)
        #expect(try db.ledgerBalance(named: "Tile Installation Services") == -1000)

        let credit = try db.insertCustomerCredit(
            customerID: customer, creditDate: "2026-06-05", amount: 400,
            reference: "CM-1", creditType: "credit memo", memo: "returned tile")
        _ = try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-06-06", paymentAmount: 0, method: "",
            reference: "", memo: "", depositAccountID: nil, cashAllocations: [],
            creditApplications: [(creditID: credit, invoiceID: invoice, amount: 400)])

        // Live (no rebuild): receivable and income both fall by the applied credit.
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 600)
        #expect(try db.ledgerBalance(named: "Tile Installation Services") == -600)
        let tb = try db.trialBalanceTotals()
        #expect(abs(tb.debits - tb.credits) < 0.005)
    }

    @Test("A credit plus a cash payment together clear the receivable to zero")
    func creditPlusCashClearsInvoice() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Mixed Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "C-2", customerID: customer, issueDate: "2026-06-01", dueDate: "2026-07-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        let credit = try db.insertCustomerCredit(
            customerID: customer, creditDate: "2026-06-05", amount: 400,
            reference: "CM-2", creditType: "credit memo", memo: "")

        // Apply a $400 credit and a $600 cash payment to fully settle the $1000 invoice.
        _ = try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-06-06", paymentAmount: 600, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 600)],
            creditApplications: [(creditID: credit, invoiceID: invoice, amount: 400)])

        #expect(try db.ledgerBalance(named: "Accounts Receivable") == 0)       // fully settled
        #expect(try db.ledgerBalance(named: "Undeposited Funds") == 600)       // cash received
        #expect(try db.ledgerBalance(named: "Tile Installation Services") == -600)  // net income
        let tb = try db.trialBalanceTotals()
        #expect(abs(tb.debits - tb.credits) < 0.005)
    }

    @Test("Applied credits give the same ledger live and after a rebuild")
    func creditMatchesRebuild() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Equiv Credit Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "C-3", customerID: customer, issueDate: "2026-06-01", dueDate: "2026-07-01",
            memo: "", total: 800,
            lines: [(description: "Work", quantity: 1, rate: 800, amount: 800)], jobID: nil)
        let credit = try db.insertCustomerCredit(
            customerID: customer, creditDate: "2026-06-05", amount: 300,
            reference: "CM-3", creditType: "adjustment", memo: "")
        _ = try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-06-06", paymentAmount: 0, method: "",
            reference: "", memo: "", depositAccountID: nil, cashAllocations: [],
            creditApplications: [(creditID: credit, invoiceID: invoice, amount: 300)])

        let liveAR = try db.ledgerBalance(named: "Accounts Receivable")
        let liveIncome = try db.ledgerBalance(named: "Tile Installation Services")
        _ = try db.rebuildJournal()
        #expect(try db.ledgerBalance(named: "Accounts Receivable") == liveAR)         // 500
        #expect(try db.ledgerBalance(named: "Tile Installation Services") == liveIncome)  // -500
    }
}
