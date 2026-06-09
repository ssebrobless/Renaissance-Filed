import Testing
import Foundation
@testable import RenaissanceLedger

/// Bank reconciliation: deposits and checks on an account net to the right ending
/// movement. Mirrors the `RenaissanceHarness` "prove bank reconciliation" scenario.
@Suite("Bank reconciliation")
struct BankReconciliationTests {

    @Test("Reconcile items net a deposit against a check to the correct movement")
    func reconcileItemsNet() throws {
        let db = try TestDB.make()
        let bank = try TestDB.bankAccountID(db)

        // A $400 deposit (customer payment, then deposited into the bank).
        let customer = try TestDB.customer(db, "Recon Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "R-1", customerID: customer, issueDate: "2026-01-01", dueDate: "2026-02-01",
            memo: "", total: 400,
            lines: [(description: "Work", quantity: 1, rate: 400, amount: 400)], jobID: nil)
        let payment = try #require(try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-01-05", paymentAmount: 400, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 400)], creditApplications: []))
        _ = try db.recordDeposit(paymentIDs: [payment], depositDate: "2026-01-06",
                                 destinationAccountID: bank, reference: "dep", memo: "")

        // A $150 check (expense) out of the bank.
        let expenseAcct = try TestDB.expenseAccountID(db)
        _ = try db.insertExpense(
            vendorNameOverride: "Utility", vendorID: nil, expenseDate: "2026-01-10",
            amount: 150, accountID: expenseAcct, paymentAccountID: bank,
            checkNumber: "3001", memo: "", jobID: nil)

        let bankName = try TestDB.accountName(db, id: bank)
        let items = try db.fetchReconcileItems(accountID: bank, accountName: bankName,
                                               throughDate: "2026-02-15")

        let net = items.reduce(0.0) { $0 + $1.signedAmount }
        #expect(net == 250)   // +400 deposit, -150 check
        #expect(items.contains { $0.sourceKind == .deposit && $0.signedAmount == 400 })
        #expect(items.contains { $0.sourceKind == .expense && $0.signedAmount == -150 })
    }
}
