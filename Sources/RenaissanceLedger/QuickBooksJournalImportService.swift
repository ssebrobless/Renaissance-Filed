import Foundation

/// Imports QuickBooks Desktop **transaction** history from a Journal report exported to CSV
/// (Reports > Accountant & Taxes > Journal > export). QuickBooks won't export transactions
/// to IIF, but the Journal report *is* the full double-entry journal — every row is a
/// debit/credit line that maps 1:1 onto our ledger. Imported lines are stored with kind
/// `qb_import` (historical/opening data) and survive `rebuildJournal`. Match the chart first
/// via `QuickBooksIIFImportService`; any account name not found is created so nothing drops.
enum QuickBooksJournalImportService {

    struct Summary: Equatable {
        var transactions = 0
        var lines = 0
        var accountsCreated = 0
        var balancingPlug = 0.0   // total routed to Opening Balance Equity to balance imperfect groups
    }

    struct ReconciliationCheck {
        let accountName: String
        let expected: Double
        let actual: Double
        var difference: Double { actual - expected }
        var matches: Bool { abs(difference) < 0.005 }
    }

    /// Trim QuickBooks report title rows so the column header (the row with Account + Debit/
    /// Credit) is first, which is what `CSVParser` expects.
    static func trimmedToHeader(_ text: String) -> String {
        let normalized = text.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        let lines = normalized.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        if let idx = lines.firstIndex(where: { l in
            let low = l.lowercased()
            return low.contains("account") && (low.contains("debit") || low.contains("credit"))
        }) {
            return lines[idx...].joined(separator: "\n")
        }
        return normalized
    }

    static func parseAmount(_ raw: String) -> Double {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return 0 }
        var negative = false
        if s.hasPrefix("(") && s.hasSuffix(")") { negative = true; s = String(s.dropFirst().dropLast()) }
        s = s.replacingOccurrences(of: "$", with: "")
             .replacingOccurrences(of: ",", with: "")
             .replacingOccurrences(of: " ", with: "")
        let v = Double(s) ?? 0
        return negative ? -abs(v) : v
    }

    /// Normalize common date formats to ISO `YYYY-MM-DD` so imported dates sort with the
    /// rest of the ledger.
    static func normalizeDate(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespaces)
        if s.isEmpty { return s }
        if s.count == 10, s.dropFirst(4).first == "-" { return s }   // already ISO
        let parts = s.split(separator: "/")
        if parts.count == 3, let m = Int(parts[0]), let d = Int(parts[1]) {
            var y = String(parts[2]); if y.count == 2 { y = "20" + y }
            return String(format: "%@-%02d-%02d", y, m, d)
        }
        return s
    }

    @discardableResult
    static func importJournalCSV(_ text: String, into db: SQLiteDatabase) throws -> Summary {
        try importJournalCSVFiles([text], into: db)
    }

    private struct Group { var date: String; var name: String; var lines: [SQLiteDatabase.JournalPosting] }

    /// Import one or more QuickBooks Journal-report CSV exports as a single combined import.
    /// QuickBooks caps a Journal export at a row limit, so a long history must be exported in
    /// chunks (e.g. one file per quarter or year). Pass them all here and they import together
    /// with a continuous transaction counter, so later chunks don't overwrite earlier ones.
    /// Replaces any prior `qb_import`, so re-running with the full set is safe and idempotent.
    @discardableResult
    static func importJournalCSVFiles(_ texts: [String], into db: SQLiteDatabase) throws -> Summary {
        var summary = Summary()

        var accountIDByName: [String: Int64] = [:]
        for a in try db.fetchAccounts() { accountIDByName[a.name.lowercased()] = a.id }
        func accountID(for name: String) throws -> Int64 {
            let key = name.lowercased()
            if let id = accountIDByName[key] { return id }
            let id = try db.insertGLAccount(name: name, type: "asset", number: "")
            accountIDByName[key] = id
            summary.accountsCreated += 1
            return id
        }
        func openingBalanceEquityID() throws -> Int64 {
            if let id = accountIDByName["opening balance equity"] { return id }
            let id = try db.insertGLAccount(name: "Opening Balance Equity", type: "equity", number: "3900")
            accountIDByName["opening balance equity"] = id
            return id
        }
        func value(_ r: CSVRecord, _ keys: [String]) -> String {
            for k in keys { if let v = r.fields[k], !v.isEmpty { return v } }
            return ""
        }

        try db.deleteJournalEntries(kind: "qb_import")   // re-import (the full set) replaces any prior import

        var counter: Int64 = 0
        for text in texts {
            let records = CSVParser.parse(trimmedToHeader(text))
            // Group rows into transactions within this chunk (QuickBooks restarts Trans # per
            // export, so grouping is per-file; the posted txn id uses the continuous counter).
            var groups: [String: Group] = [:]
            var order: [String] = []
            var lastTrans = "", lastDate = "", lastName = ""

            for r in records {
                var trans = value(r, ["trans_#", "trans", "trans_no", "transaction_#"])
                if trans.isEmpty { trans = lastTrans } else { lastTrans = trans }
                var date = value(r, ["date"]); if date.isEmpty { date = lastDate } else { lastDate = date }
                let nm = value(r, ["name"]); if !nm.isEmpty { lastName = nm }
                let account = value(r, ["account"]); if account.isEmpty { continue }
                let debit = parseAmount(value(r, ["debit"]))
                let credit = parseAmount(value(r, ["credit"]))
                if abs(debit) < 0.005 && abs(credit) < 0.005 { continue }
                if trans.isEmpty { trans = "row-\(order.count)" }
                let acct = try accountID(for: account)
                if groups[trans] == nil {
                    groups[trans] = Group(date: normalizeDate(date), name: lastName, lines: [])
                    order.append(trans)
                }
                groups[trans]?.lines.append(SQLiteDatabase.JournalPosting(accountID: acct, debit: debit, credit: credit))
            }

            for key in order {
                guard var group = groups[key] else { continue }
                counter += 1
                let residual = group.lines.reduce(0.0) { $0 + $1.debit - $1.credit }
                if abs(residual) > 0.005 {
                    let obe = try openingBalanceEquityID()
                    group.lines.append(residual > 0
                        ? SQLiteDatabase.JournalPosting(accountID: obe, debit: 0, credit: residual)
                        : SQLiteDatabase.JournalPosting(accountID: obe, debit: -residual, credit: 0))
                    summary.balancingPlug += abs(residual)
                }
                try db.postJournalEntry(kind: "qb_import", txnID: counter, date: group.date,
                                        lines: group.lines, memo: group.name)
                summary.transactions += 1
                summary.lines += group.lines.count
            }
        }
        return summary
    }

    /// Compare the ledger balance of an account to an expected figure from QuickBooks — the
    /// "your imported books match your last QuickBooks statement" confidence check.
    static func reconcile(accountNamed name: String, expected: Double, in db: SQLiteDatabase) throws -> ReconciliationCheck {
        ReconciliationCheck(accountName: name, expected: expected, actual: try db.ledgerBalance(named: name))
    }
}
