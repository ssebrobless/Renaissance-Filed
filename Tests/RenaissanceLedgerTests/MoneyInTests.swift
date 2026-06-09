import Testing
import Foundation
@testable import RenaissanceLedger

/// The money-in spine: invoice → customer payment → deposit. These mirror the
/// `RenaissanceHarness` "prove money-in" scenario as fast, GUI-free unit tests.
@Suite("Money-in spine")
struct MoneyInTests {

    @Test("Paying an invoice in full clears its balance and marks it paid")
    func paymentClearsInvoice() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Acme Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "INV-1", customerID: customer, issueDate: "2026-01-15", dueDate: "2026-02-15",
            memo: "test", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)

        let payment = try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-01-20", paymentAmount: 1000, method: "check",
            reference: "1234", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 1000)], creditApplications: [])
        #expect(payment != nil)

        let inv = try #require(try db.fetchInvoice(id: invoice))
        #expect(inv.paid == 1000)
        #expect(inv.balance == 0)
        #expect(inv.status == "paid")
    }

    @Test("A partial payment leaves the remaining balance open")
    func partialPaymentLeavesBalance() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Partial Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "INV-P", customerID: customer, issueDate: "2026-03-01", dueDate: "2026-04-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)

        _ = try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-03-05", paymentAmount: 400, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 400)], creditApplications: [])

        let inv = try #require(try db.fetchInvoice(id: invoice))
        #expect(inv.paid == 400)
        #expect(inv.balance == 600)
        #expect(inv.status != "paid")
    }

    @Test("An undeposited payment sits in Undeposited Funds until it is deposited")
    func depositClearsUndepositedFunds() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Beta LLC")
        let invoice = try db.saveInvoiceWithLines(
            number: "INV-2", customerID: customer, issueDate: "2026-02-01", dueDate: "2026-03-01",
            memo: "", total: 500,
            lines: [(description: "Work", quantity: 1, rate: 500, amount: 500)], jobID: nil)
        let payment = try #require(try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-02-05", paymentAmount: 500, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 500)], creditApplications: []))

        // Before deposit: the payment is in Undeposited Funds.
        #expect(try db.fetchUndepositedPayments().contains { $0.id == payment })

        let bank = try TestDB.bankAccountID(db)
        _ = try db.recordDeposit(paymentIDs: [payment], depositDate: "2026-02-06",
                                 destinationAccountID: bank, reference: "dep", memo: "")

        // After deposit: it has left Undeposited Funds.
        #expect(!(try db.fetchUndepositedPayments().contains { $0.id == payment }))
    }
}
