import Foundation
@testable import RenaissanceLedger

/// Helpers for running the money-logic tests against an isolated, throwaway database.
enum TestDB {
    enum TestError: Error { case noAccount }

    /// A fresh database in a unique temp file, fully migrated with the default chart of
    /// accounts. `open()` runs every migration and seeds accounts, so the returned
    /// instance is ready to use. Each call is isolated from every other.
    static func make() throws -> SQLiteDatabase {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("rftest-\(UUID().uuidString).sqlite")
        let db = SQLiteDatabase(databaseURL: url)
        try db.open()
        return db
    }

    /// A bank/asset account id to deposit into (defaults to the seeded "Checking Account").
    static func bankAccountID(_ db: SQLiteDatabase, containing needle: String = "Checking") throws -> Int64 {
        let assets = try db.fetchAccounts(type: "asset")
        guard let acct = assets.first(where: { $0.name.localizedCaseInsensitiveContains(needle) })
            ?? assets.first else {
            throw TestError.noAccount
        }
        return acct.id
    }

    /// Convenience: create a customer with just a name.
    @discardableResult
    static func customer(_ db: SQLiteDatabase, _ name: String) throws -> Int64 {
        try db.insertCustomer(name: name, company: "", primaryContact: "", email: "",
                              phone: "", address: "", city: "", state: "", zip: "")
    }
}
