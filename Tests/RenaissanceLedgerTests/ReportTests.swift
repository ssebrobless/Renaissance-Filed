import Testing
import Foundation
@testable import RenaissanceLedger

/// Report correctness: A/R aging and customer statements derived from the books.
/// Mirrors parts of the `RenaissanceHarness` "prove report correctness" scenario.
@Suite("Report correctness")
struct ReportTests {

    @Test("An open invoice shows its full balance in A/R aging")
    func arAgingShowsOpenBalance() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "AR Co")
        _ = try db.saveInvoiceWithLines(
            number: "AR-1", customerID: customer, issueDate: "2026-01-01", dueDate: "2026-01-31",
            memo: "", total: 750,
            lines: [(description: "Work", quantity: 1, rate: 750, amount: 750)], jobID: nil)

        let row = try #require(try db.fetchARAgingReport(asOf: "2026-02-15")
            .first { $0.customerName.localizedCaseInsensitiveContains("AR Co") })
        let total = row.current + row.days1_30 + row.days31_60 + row.days61_90 + row.over90
        #expect(total == 750)
    }

    @Test("A customer statement nets charges and payments to the open balance")
    func customerStatementNetsToBalance() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "Stmt Co")
        let invoice = try db.saveInvoiceWithLines(
            number: "S-1", customerID: customer, issueDate: "2026-01-01", dueDate: "2026-02-01",
            memo: "", total: 1000,
            lines: [(description: "Work", quantity: 1, rate: 1000, amount: 1000)], jobID: nil)
        _ = try db.recordCustomerPayment(
            customerID: customer, paymentDate: "2026-01-10", paymentAmount: 400, method: "check",
            reference: "", memo: "", depositAccountID: nil,
            cashAllocations: [(invoiceID: invoice, amount: 400)], creditApplications: [])

        let lines = try db.fetchCustomerStatement(customerID: customer)
        #expect(!lines.isEmpty)
        // Charge $1000 then payment $400 → running balance ends at $600.
        #expect(lines.last?.balance == 600)
    }
}
