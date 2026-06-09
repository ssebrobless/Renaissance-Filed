import Testing
import Foundation
@testable import RenaissanceLedger

/// The money-out spine: direct expenses, and bills that create A/P and clear when paid.
/// Mirrors the `RenaissanceHarness` "prove money-out" scenario.
@Suite("Money-out spine")
struct MoneyOutTests {

    @Test("A direct expense paid from the bank is recorded with its amount and check #")
    func directExpenseRecorded() throws {
        let db = try TestDB.make()
        let vendor = try db.insertVendor(name: "Supplier Co", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        let expenseAcct = try TestDB.expenseAccountID(db)
        let bank = try TestDB.bankAccountID(db)
        let expense = try db.insertExpense(
            vendorNameOverride: "Supplier Co", vendorID: vendor, expenseDate: "2026-01-10",
            amount: 150, accountID: expenseAcct, paymentAccountID: bank,
            checkNumber: "1001", memo: "", jobID: nil)

        let row = try #require(try db.fetchExpenses().first { $0.id == expense })
        #expect(row.amount == 150)
        #expect(row.checkNumber == "1001")
    }

    @Test("An unpaid bill appears in A/P, then clears once it is paid")
    func billCreatesAndClearsPayable() throws {
        let db = try TestDB.make()
        let vendor = try db.insertVendor(name: "Bill Vendor", company: "", primaryContact: "",
                                         phone: "", address: "", is1099: false, isInternalSelf: false)
        let expenseAcct = try TestDB.expenseAccountID(db)
        let bill = try db.insertBill(
            vendorNameOverride: "Bill Vendor", vendorID: vendor, billDate: "2026-01-01",
            dueDate: "2026-01-31", amount: 200, accountID: expenseAcct, jobID: nil, memo: "")

        // The unpaid bill is present and shows in A/P aging.
        #expect(try db.fetchBills(unpaidOnly: true).contains { $0.id == bill })
        let apRow = try #require(try db.fetchAPAgingReport(asOf: "2026-02-15")
            .first { $0.vendorName.localizedCaseInsensitiveContains("Bill Vendor") })
        let apTotal = apRow.current + apRow.days1_30 + apRow.days31_60 + apRow.days61_90 + apRow.over90
        #expect(apTotal == 200)

        // Pay it from the bank.
        let bank = try TestDB.bankAccountID(db)
        try db.recordBillPayments(billIDs: [bill], paymentDate: "2026-02-01",
                                  paymentAccountID: bank, paymentMethod: "Check",
                                  startingCheckNumber: "2001", memo: "")

        // No longer outstanding.
        #expect(!(try db.fetchBills(unpaidOnly: true).contains { $0.id == bill }))
    }
}
