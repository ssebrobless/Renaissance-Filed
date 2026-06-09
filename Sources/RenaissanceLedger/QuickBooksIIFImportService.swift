import Foundation

/// Imports QuickBooks Desktop **list** exports (IIF — Intuit Interchange Format, a
/// tab-separated text format) into the books: chart of accounts, customers, and vendors.
///
/// In QuickBooks Desktop these come from `File > Utilities > Export > Lists to IIF Files`.
/// Note: QuickBooks Desktop will NOT export *transactions* to IIF — those come out of the
/// Journal report as CSV and are handled by a separate transaction importer (roadmap #4
/// Phase B). This service is Phase A: the lists.
enum QuickBooksIIFImportService {

    struct Summary: Equatable {
        var accounts = 0
        var customers = 0
        var vendors = 0
        var skipped = 0
    }

    /// Map a QuickBooks `ACCNTTYPE` to one of our account types. Unknown types fall back to
    /// `asset` so an account is always created and visible, never silently dropped.
    static func mappedAccountType(_ qbType: String) -> String {
        switch qbType.uppercased() {
        case "BANK", "AR", "OCASSET", "FIXASSET", "OASSET": return "asset"
        case "AP", "CCARD", "OCLIAB", "LTLIAB": return "liability"
        case "EQUITY": return "equity"
        case "INC", "OINC", "EXINC": return "income"
        case "EXP", "COGS", "OEXP", "EXEXP": return "expense"
        default: return "asset"
        }
    }

    /// QuickBooks non-posting account types (Estimates, Purchase/Sales Orders) carry no real
    /// balance and don't belong in a double-entry chart, so they're skipped on import.
    static func isNonPosting(_ qbType: String) -> Bool {
        qbType.uppercased() == "NONPOSTING"
    }

    /// Parse IIF text into records grouped by record type. Header lines begin with `!TYPE`
    /// and define the columns; data lines begin with `TYPE` and map positionally to the most
    /// recent header for that type. Column keys are upper-cased.
    static func parse(_ text: String) -> [String: [[String: String]]] {
        var headers: [String: [String]] = [:]
        var records: [String: [[String: String]]] = [:]
        let lines = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .split(separator: "\n", omittingEmptySubsequences: true)
        for line in lines {
            let fields = line.components(separatedBy: "\t")
            guard let first = fields.first, !first.isEmpty else { continue }
            if first.hasPrefix("!") {
                headers[String(first.dropFirst())] = Array(fields.dropFirst())
            } else if let cols = headers[first] {
                let values = Array(fields.dropFirst())
                var record: [String: String] = [:]
                for (i, col) in cols.enumerated() where i < values.count {
                    record[col.uppercased()] = values[i]
                }
                records[first, default: []].append(record)
            }
        }
        return records
    }

    /// Parse `text` and import its accounts/customers/vendors. Names that already exist
    /// (case-insensitive) are skipped, so re-importing the same file is safe.
    @discardableResult
    static func importIIF(_ text: String, into db: SQLiteDatabase) throws -> Summary {
        let records = parse(text)
        var summary = Summary()

        var existingAccounts = Set(try db.fetchAccounts().map { $0.name.lowercased() })
        var existingCustomers = Set(try db.fetchCustomers().map { $0.name.lowercased() })
        var existingVendors = Set(try db.fetchVendors().map { $0.name.lowercased() })

        func value(_ r: [String: String], _ keys: [String]) -> String {
            for k in keys { if let v = r[k], !v.isEmpty { return v } }
            return ""
        }

        for r in records["ACCNT"] ?? [] {
            let name = value(r, ["NAME"])
            guard !name.isEmpty else { summary.skipped += 1; continue }
            if isNonPosting(value(r, ["ACCNTTYPE"])) { summary.skipped += 1; continue }
            if existingAccounts.contains(name.lowercased()) { summary.skipped += 1; continue }
            _ = try db.insertGLAccount(name: name,
                                       type: mappedAccountType(value(r, ["ACCNTTYPE"])),
                                       number: value(r, ["ACCNUM"]))
            existingAccounts.insert(name.lowercased())
            summary.accounts += 1
        }

        for r in records["CUST"] ?? [] {
            let name = value(r, ["NAME"])
            guard !name.isEmpty else { summary.skipped += 1; continue }
            if existingCustomers.contains(name.lowercased()) { summary.skipped += 1; continue }
            _ = try db.insertCustomer(
                name: name,
                company: value(r, ["COMPANYNAME"]),
                primaryContact: value(r, ["CONT1", "CONTACT"]),
                email: value(r, ["EMAIL"]),
                phone: value(r, ["PHONE1", "PHONE"]),
                address: value(r, ["BADDR1", "ADDR1"]),
                city: "", state: "", zip: "")
            existingCustomers.insert(name.lowercased())
            summary.customers += 1
        }

        for r in records["VEND"] ?? [] {
            let name = value(r, ["NAME"])
            guard !name.isEmpty else { summary.skipped += 1; continue }
            if existingVendors.contains(name.lowercased()) { summary.skipped += 1; continue }
            _ = try db.insertVendor(
                name: name,
                company: value(r, ["COMPANYNAME", "PRINTAS"]),
                primaryContact: value(r, ["CONT1", "CONTACT"]),
                phone: value(r, ["PHONE1", "PHONE"]),
                address: value(r, ["VADDR1", "ADDR1"]),
                ein: value(r, ["TAXID"]),
                is1099: value(r, ["1099"]).uppercased() == "Y",
                isInternalSelf: false)
            existingVendors.insert(name.lowercased())
            summary.vendors += 1
        }

        return summary
    }
}
