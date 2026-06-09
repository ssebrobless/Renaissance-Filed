import Testing
import Foundation
@testable import RenaissanceLedger

/// Job profitability: invoiced revenue minus job expenses. Mirrors the
/// `RenaissanceHarness` "prove job costing" scenario.
@Suite("Job costing")
struct JobCostingTests {

    @Test("Job profit equals invoiced revenue minus expenses booked to the job")
    func jobProfit() throws {
        let db = try TestDB.make()
        let customer = try TestDB.customer(db, "JobCo")
        let job = try db.insertJob(customerID: customer, name: "Kitchen Remodel",
                                   status: "active", siteAddress: "", notes: "")

        // Revenue: a $300 invoice on the job.
        _ = try db.saveInvoiceWithLines(
            number: "J-1", customerID: customer, issueDate: "2026-01-15", dueDate: "2026-02-15",
            memo: "", total: 300,
            lines: [(description: "Labor", quantity: 1, rate: 300, amount: 300)], jobID: job)

        // Cost: a $100 expense on the job.
        let expenseAcct = try TestDB.expenseAccountID(db)
        let bank = try TestDB.bankAccountID(db)
        _ = try db.insertExpense(
            vendorNameOverride: "Subcontractor", vendorID: nil, expenseDate: "2026-01-20",
            amount: 100, accountID: expenseAcct, paymentAccountID: bank,
            checkNumber: "", memo: "", jobID: job)

        let row = try #require(try db.fetchJobProfitability(customerID: customer).first { $0.id == job })
        #expect(row.invoicedTotal == 300)
        #expect(row.expenseTotal == 100)
        #expect(row.profit == 200)
    }
}
